import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/pages/user/setting_screen.dart';
import 'package:doppy/pages/user/join_screen.dart';
import 'package:doppy/utils/route_observer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/account_manager_service.dart';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/comps_for_profile/profile_avatar.dart';
import 'package:doppy/pages/components/comps_for_profile/user_profile_controller.dart';
import 'package:doppy/editor/image/profile_image_bottom_sheet.dart';

class UserProfileScreen extends StatefulWidget {
  final User? otherUser; // 다른 사용자 프로필을 볼 때 username 전달

  const UserProfileScreen({super.key, this.otherUser});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  // 위치 관련 상수
  static const double _baseHeight = 100.0; // 기본 높이 (topPadding + 이 값)
  static const double _snap1Offset = 300.0; // 1차 스냅 오프셋
  static const double _snap2Ratio = 0.2; // 2차 스냅 비율 (화면 높이의 50%)

  // 스크롤 컨트롤러 및 상태
  late ScrollController _scrollController;
  double _scrollY = 0.0;
  double _lastScrollY = 0.0;
  bool _didAutoSnap = false;
  bool _isAutoAnimating = false;

  // 성능 최적화를 위한 캐시된 값들
  double? _cachedTopPadding;
  double? _cachedSnap1;
  double? _cachedSnap2;

  // ✅ 프로필 구분 상태는 그대로 유지
  late final bool _isOwnProfile;

  // 피드 상태 추적
  bool _hasFeeds = false;

  // 배경 이미지 상태

  // 업로드 진행 상태
  UploadTask? _profileUploadTask;
  VoidCallback? _profileTaskListener;
  PageRoute<dynamic>? _activeRoute; // RouteObserver 중복 구독 방지

  // 프로필 사진 변경 상태
  bool _isUploadingProfileImage = false;
  late UserProfileController _controller;

  @override
  void initState() {
    super.initState();
    _isOwnProfile = (widget.otherUser == null);
    _scrollController = ScrollController()..addListener(_onScroll);
    _controller = UserProfileController(context);

    // 캐시된 값들 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheMediaQueryValues();
    });

    // ✅ [구조 개선] Provider를 통해 필요한 데이터를 한번에 요청합니다.
    // 이 코드 하나로 모든 데이터 로딩이 시작됩니다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_isOwnProfile) {
        // 내 프로필에 필요한 데이터 로딩
      } else {
        // 다른 사용자 프로필: 서버에서 상세 정보 & 친구 상태 병렬 로딩
        _controller.checkFriendStatus(widget.otherUser!.username);
      }
      // 프로필 피드 초기 로드
      try {
        final bool isOther = !_isOwnProfile;
        await _controller.loadFeed(
          username: isOther ? widget.otherUser!.username : null,
          force: isOther, // 타인: 항상 새로 로드, 내 계정: 캐시 사용
        );

        // 피드 상태 업데이트
        if (mounted) {
          setState(() {
            _hasFeeds = context.read<ProfileFeedProvider>().posts.isNotEmpty;
          });
        }
      } catch (_) {}
    });
  }

  void _cacheMediaQueryValues() {
    if (mounted) {
      _cachedTopPadding = MediaQuery.of(context).padding.top;
      _cachedSnap1 = _cachedTopPadding! + _snap1Offset;
      _cachedSnap2 = MediaQuery.of(context).size.height * _snap2Ratio;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // MediaQuery 값들이 변경되었을 때 캐시 업데이트
    _cacheMediaQueryValues();

    // RouteObserver 구독 (중복 방지)
    final modal = ModalRoute.of(context);
    if (modal is PageRoute<dynamic>) {
      if (!identical(_activeRoute, modal)) {
        // 이전 라우트 구독 해제 후 새 라우트로 구독
        routeObserver.unsubscribe(this);
        _activeRoute = modal;
        routeObserver.subscribe(this, modal);
      }
    }
  }

  @override
  void dispose() {
    // 화면 종료 시, 피드 메모리 정리 (캐시는 유지)
    if (mounted) {
      try {
        context.read<ProfileFeedProvider>().clearInMemory();
      } catch (_) {}
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (_profileUploadTask != null && _profileTaskListener != null) {
      _profileUploadTask!.removeListener(_profileTaskListener!);
    }
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _onScroll() {
    final double currentOffset = _scrollController.offset;
    final double delta = currentOffset - _lastScrollY;

    // 캐시된 값들 사용 (성능 최적화)
    if (_cachedSnap1 == null || _cachedSnap2 == null) return;

    final double snap0 = 0.0; // 기본 상태 (맨 위)
    final double snap1 = _cachedSnap1!; // 1차 스냅 (SliverAppBar와 연동)
    final double snap2 = _cachedSnap2!; // 2차 스냅 (절반 피드모드)

    // 하향 스크롤 감지 → snap1까지 자동 이동 (기본 상태에서만)
    if (delta > 0.5 &&
        !_didAutoSnap &&
        !_isAutoAnimating &&
        currentOffset > 5 &&
        currentOffset < 80) {
      // 기본 상태에서만 (5~80px 사이)
      _isAutoAnimating = true;
      _scrollController
          .animateTo(
            snap1,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) {
              setState(() {
                _didAutoSnap = true;
                _isAutoAnimating = false;
              });
            } else {
              _didAutoSnap = true;
              _isAutoAnimating = false;
            }
          });
    }

    // 상향 스크롤 감지 → snap0(기본) 또는 snap2(절반 피드)로 자동 이동
    if (delta < -0.5 && !_didAutoSnap && !_isAutoAnimating) {
      // 1차 스냅 근처에서 위로 스크롤 → 기본 상태로
      if (currentOffset > snap1 - 50 && currentOffset < snap1 + 50) {
        _isAutoAnimating = true;
        _scrollController
            .animateTo(
              snap0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (mounted) {
                setState(() {
                  _didAutoSnap = true;
                  _isAutoAnimating = false;
                });
              } else {
                _didAutoSnap = true;
                _isAutoAnimating = false;
              }
            });
      }
      // 1차 스냅과 2차 스냅 사이에서 위로 스크롤 → 2차 스냅으로
      else if (currentOffset > snap1 + 50 && currentOffset < snap2 - 50) {
        _isAutoAnimating = true;
        _scrollController
            .animateTo(
              snap2,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (mounted) {
                setState(() {
                  _didAutoSnap = true;
                  _isAutoAnimating = false;
                });
              } else {
                _didAutoSnap = true;
                _isAutoAnimating = false;
              }
            });
      }
    }

    // 스냅 완료 후 스냅을 다시 허용
    if (_didAutoSnap && !_isAutoAnimating) {
      // 1차 스냅에서 0으로 내려갈 때 스냅 허용
      if (currentOffset > snap1 - 50 && currentOffset < snap1 + 50) {
        _didAutoSnap = false;
      }
      // 맨 위로 복귀했을 때도 스냅 허용
      else if (currentOffset < 10.0) {
        _didAutoSnap = false;
      }
    }

    // setState 최적화: 스크롤 값이 실제로 변경되었을 때만 호출
    if ((_scrollY - currentOffset).abs() > 0.5) {
      setState(() {
        _scrollY = currentOffset;
      });
    }
    _lastScrollY = currentOffset;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    final bool isOther = !_isOwnProfile; // true: 타인 프로필, false: 내 프로필
    final User? me = userProvider.currentUser;
    final String? myIntro = userProvider.selfIntroduction;
    final User? other = widget.otherUser;

    final double topPadding =
        _cachedTopPadding ?? MediaQuery.of(context).padding.top;

    // 표시할 이미지 URL과 사용자명 결정
    String _displayImageUrl = '';
    String _displayUsername = '';
    String? _displayAlias;

    if (isOther && other != null) {
      _displayImageUrl = other.profileImageUrl ?? '';
      _displayUsername = other.username;
      _displayAlias = other.alias;
    } else if (!isOther && me != null) {
      _displayImageUrl = me.profileImageUrl ?? '';
      _displayUsername = me.username;
      _displayAlias = me.alias;
    }

    return Material(
      color: Theme.of(context).colorScheme.background,
      child: Stack(
        children: [
          // 스크롤 가능한 컨텐츠 (Sliver)
          Positioned.fill(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  expandedHeight: topPadding + _baseHeight,
                  toolbarHeight: topPadding + 0,
                  backgroundColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  elevation: 0,
                  title: Row(
                    children: [
                      if (isOther)
                        GestureDetector(
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            size: 20,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.8),
                          ),
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: isOther ? 20.0 : 5.0,
                          bottom: 3.0,
                        ),
                        child: Text(
                          _displayUsername,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      if (!isOther)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: GestureDetector(
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 24,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.8),
                            ),
                            onTap: () => _showAccountDropdown(context),
                          ),
                        ),
                    ],
                  ),

                  actions: [
                    if (_isOwnProfile) ...[
                      // 내 이웃 버튼
                      IconButton(
                        icon: Icon(
                          Icons.people,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          size: 26,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ManageGroupScreen(),
                            ),
                          );
                        },
                      ),
                      // 설정 버튼
                      IconButton(
                        icon: Icon(
                          Icons.settings,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => SettingScreen()),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                SliverToBoxAdapter(
                  child: Builder(
                    builder: (context) {
                      final double snap1 =
                          _cachedSnap1 ??
                          MediaQuery.of(context).padding.top + _snap1Offset;

                      // 아바타 opacity: 1차 스냅 전까지는 1.0, 1차 스냅에 도달하면 0.0
                      final double avatarOpacity =
                          _scrollY < snap1
                              ? 1.0 - (_scrollY / snap1).clamp(0.0, 1.0)
                              : 0.0;

                      // 텍스트들의 페이드아웃: 1차 스냅 이후부터 시작
                      final double fadeProgress =
                          _scrollY > snap1
                              ? ((_scrollY - snap1) / 200.0).clamp(0.0, 1.0)
                              : 0.0;
                      final double nameOpacity = (1.0 - fadeProgress * 1.1)
                          .clamp(0.0, 1.0);
                      final double descOpacity = (1.0 - fadeProgress * 1.2)
                          .clamp(0.0, 1.0);

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 50),
                            // 원형 아바타 (텍스트 위에 위치)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 아바타 (1차 스냅에서 완전히 페이드아웃)
                                Opacity(
                                  opacity: avatarOpacity,
                                  child: ProfileAvatar(
                                    imageUrl: _displayImageUrl,
                                    username: _displayUsername,
                                    size: 150,
                                    borderWidth: 2,
                                    borderColor:
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.grey.shade300
                                            : Colors.grey.shade600,
                                    isUploading: _isUploadingProfileImage,
                                    onTap:
                                        _isOwnProfile &&
                                                !_isUploadingProfileImage
                                            ? _changeProfileImage
                                            : null,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // 사용자 이름 (1차 스냅 이후 페이드아웃)
                                Opacity(
                                  opacity: nameOpacity,
                                  child: Text(
                                    _displayAlias ?? _displayUsername,
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Opacity(
                              opacity: descOpacity,
                              child: Text(
                                isOther
                                    ? (other?.selfIntroduction?.isNotEmpty ==
                                            true
                                        ? other!.selfIntroduction!
                                        : _displayUsername)
                                    : (myIntro?.isNotEmpty == true
                                        ? myIntro!
                                        : ''),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity(0.8)
                                          : Colors.black,
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // 다른 사용자 프로필일 때만 친구 추가 버튼 표시
                            if (isOther) ...[
                              const SizedBox(height: 20),
                              Opacity(
                                opacity: descOpacity,
                                child: Consumer<FriendProvider>(
                                  builder: (context, friendProvider, _) {
                                    // 친구 상태에 따른 버튼 텍스트와 액션 결정
                                    String buttonText;
                                    VoidCallback buttonAction;

                                    switch (friendProvider.friendStatus) {
                                      case FriendRequestStatus.none:
                                        buttonText = '이웃 추가';
                                        buttonAction = () async {
                                          try {
                                            await friendProvider
                                                .sendFriendRequest(
                                                  widget.otherUser!.username,
                                                );
                                          } catch (e) {}
                                        };
                                        break;
                                      case FriendRequestStatus.requested:
                                        buttonText = '요청 취소';
                                        buttonAction = () async {
                                          try {
                                            await friendProvider.deleteFriend(
                                              widget.otherUser!.username,
                                            );
                                          } catch (e) {}
                                        };
                                        break;
                                      case FriendRequestStatus.accepted:
                                        buttonText = '친구 취소';
                                        buttonAction = () async {
                                          try {
                                            await friendProvider.deleteFriend(
                                              widget.otherUser!.username,
                                            );
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text('오류: $e'),
                                                ),
                                              );
                                            }
                                          }
                                        };
                                        break;
                                      default:
                                        buttonText = '이웃 추가';
                                        buttonAction = () {};
                                    }

                                    return _buildGlassyButton(
                                      text: buttonText,
                                      onTap: buttonAction,
                                      isLoading: friendProvider.isLoading,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _buildFeedContent(),
                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ],
            ),
          ),

          // 바텀바 영역 그라데이션 오버레이
          if (_hasFeeds)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 100,
              child: IgnorePointer(
                ignoring: true,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.1),
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.4),
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.7),
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassyButton({
    required String text,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.white.withOpacity(0.05),
            ],
          ),
        ),
        child: Center(
          child:
              isLoading
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                  : Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildFeedContent() {
    return Consumer<ProfileFeedProvider>(
      builder: (context, feedProvider, _) {
        // 초기 진입(포스트 없음) 로딩 시에는 반짝임 방지를 위해 Shimmer 미표시
        if (feedProvider.isLoading && feedProvider.posts.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // 피드가 없을 때는 아무 것도 렌더링하지 않음 (잔상 방지)
        if (feedProvider.posts.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Column(
                children: [
                  Text(
                    "\"아직은 아무 글도 없어요\"",
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 실제 피드 그리드
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 9 / 12,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index >= feedProvider.posts.length) {
              return null;
            }

            try {
              final postData = PostData.fromServer(feedProvider.posts[index]);
              return _buildPostCard(postData, index);
            } catch (e) {
              return Container(
                color: Colors.grey.withOpacity(0.3),
                child: const Center(
                  child: Icon(Icons.error, color: Colors.white),
                ),
              );
            }
          }, childCount: feedProvider.posts.length),
        );
      },
    );
  }

  Widget _buildPostCard(PostData post, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) => PostReaderScreen(
                    exported: {
                      'id': post.id,
                      'title': post.title,
                      'content': post.content,
                      'author': post.author,
                      'authorProfileImageUrl': post.authorProfileImageUrl,
                      'thumbnailImageUrl': post.thumbnailImageUrl,
                      'createdAt': post.createdAt,
                      'updatedAt': post.updatedAt,
                      'accessLevel': post.accessLevel.name,
                      'viewCount': post.viewCount,
                      'likeCount': post.likeCount,
                      'isLiked': post.isLiked,
                    },
                    heroTag: null, // Hero 애니메이션 비활성화
                  ),
              transitionsBuilder: (
                context,
                animation,
                secondaryAnimation,
                child,
              ) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 200),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: Colors.grey.withOpacity(0.3),
          ),
          child:
              post.thumbnailImageUrl.isNotEmpty
                  ? CachedNetworkImage(
                    imageUrl: post.thumbnailImageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    maxWidthDiskCache: 300,
                    fadeInDuration: const Duration(milliseconds: 300),
                    fadeOutDuration: const Duration(milliseconds: 100),
                    placeholder:
                        (context, url) => ShimmerBox(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.circular(2),
                        ),
                    errorWidget:
                        (context, url, error) => Container(
                          color: Colors.grey.withOpacity(0.3),
                          child: const Icon(Icons.error, color: Colors.white),
                        ),
                  )
                  : Container(
                    color: Colors.grey.withOpacity(0.3),
                    child: const Icon(Icons.image, color: Colors.white),
                  ),
        ),
      ),
    );
  }

  /// 계정 드롭다운 표시
  void _showAccountDropdown(BuildContext context) async {
    // 현재 사용자 정보 가져오기
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    final displayImageUrl = currentUser?.profileImageUrl ?? '';
    final displayUsername = currentUser?.username ?? '';
    final displayAlias = currentUser?.alias;

    // 연결된 계정 목록 가져오기
    final linkedAccounts = await AccountManagerService.getAllAccounts();
    final currentAccount = await AccountManagerService.getCurrentAccount();

    AccountManagerService.debugPrintAllAccounts();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            // 배경 터치로 닫기
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // 드롭다운 컨텐츠
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 0,
              left: 20,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 현재 계정 (헤더)
                          Row(
                            children: [
                              Expanded(
                                child: _buildDropdownItem(
                                  icon: CommonProfileAvatar(
                                    imageUrl: displayImageUrl,
                                    username: displayUsername,
                                    size: 50,
                                    borderColor: Colors.white.withOpacity(0.2),
                                  ),
                                  title: displayUsername,
                                  subtitle: displayAlias ?? displayUsername,
                                  backgroundColor: Colors.white.withOpacity(
                                    0.1,
                                  ),
                                  onTap: () {},
                                ),
                              ),
                            ],
                          ),

                          // 구분선
                          Container(
                            height: 1,
                            margin: EdgeInsets.symmetric(horizontal: 16),
                            color: Colors.white.withOpacity(0.1),
                          ),

                          // 연결된 계정 목록 (슬라이드 삭제 가능)
                          ...linkedAccounts
                              .where(
                                (account) =>
                                    account.username !=
                                    currentAccount?.username,
                              )
                              .map(
                                (account) => Dismissible(
                                  key: Key(account.username),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                    ),
                                    child: Text(
                                      '삭제',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await _showDeleteConfirmDialog(
                                      context,
                                      account,
                                    );
                                  },
                                  onDismissed: (direction) async {
                                    await _removeAccount(account);
                                  },
                                  child: _buildDropdownItem(
                                    icon: CommonProfileAvatar(
                                      imageUrl: account.profileImageUrl,
                                      username: account.username,
                                      size: 50,
                                    ),
                                    title: account.username,
                                    subtitle: account.alias,
                                    onTap: () async {
                                      Navigator.of(context).pop();
                                      await _switchToAccount(account);
                                    },
                                  ),
                                ),
                              )
                              .toList(),

                          // 계정 관리 버튼
                          _buildDropdownItem(
                            icon: CommonProfileAvatar(
                              imageUrl: null,
                              username: "+",
                              size: 50,
                            ),
                            title: '계정 추가',
                            subtitle: '새 계정 생성 또는 기존 계정 연동',
                            onTap: () {
                              Navigator.of(context).pop();
                              _showAccountManagementOverlay(context);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 드롭다운 아이템 빌드
  Widget _buildDropdownItem({
    required Widget icon,
    required String title,
    required String subtitle,
    Color? backgroundColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 계정 삭제 확인 다이얼로그
  Future<bool?> _showDeleteConfirmDialog(
    BuildContext context,
    AccountInfo account,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            '계정 삭제',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '${account.alias} (${account.username}) 계정을 삭제하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                '취소',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(
                '삭제',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 계정 삭제
  Future<void> _removeAccount(AccountInfo account) async {
    try {
      print('[-] [UserProfileScreen] 계정 삭제 시작: ${account.username}');

      final result = await _controller.removeAccount(account);
      if (result.isCurrentRemoved) {
        if (result.remainingAccounts.isNotEmpty) {
          await _switchToAccount(result.remainingAccounts.first);
        } else {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      }

      // 화면 새로고침
      setState(() {});

      print('[-] [UserProfileScreen] 계정 삭제 완료: ${account.username}');
    } catch (e) {
      print('[-] [UserProfileScreen] _removeAccount error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('계정 삭제에 실패했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 계정 전환
  Future<void> _switchToAccount(AccountInfo accountInfo) async {
    try {
      print('[-] [UserProfileScreen] 계정 전환 시작: ${accountInfo.username}');

      final success = await _controller.switchToAccount(accountInfo);

      if (!success) {
        return;
      }

      if (mounted) {
        setState(() {});
      }

      print('[-] [UserProfileScreen] 계정 전환 완료: ${accountInfo.username}');
    } catch (e) {
      print('[-] [UserProfileScreen] _switchToAccount error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('계정 전환에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 프로필 사진 변경 바텀시트 표시
  void _changeProfileImage() {
    if (_isUploadingProfileImage) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ProfileImageBottomSheet(
          singleSelect: true,
          onClearProfileImage: _clearProfileImage,
          onImagesSelected: (files) => _handleImageSelected(files.first),
        );
      },
    );
  }

  /// 프로필 사진 제거 (기본 이미지로 변경)
  Future<void> _clearProfileImage() async {
    // 이미 프로필 이미지가 비어있다면 처리하지 않음
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    if (currentUser?.profileImageUrl == null ||
        currentUser!.profileImageUrl!.isEmpty) {
      return;
    }

    setState(() {
      _isUploadingProfileImage = true;
    });

    try {
      final success = await _controller.deleteProfileImageAndUpdateCache();
      if (!success) {
        throw Exception('프로필 이미지 삭제 실패');
      }

      setState(() {
        _isUploadingProfileImage = false;
      });
    } catch (e) {
      setState(() {
        _isUploadingProfileImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '프로필 이미지 삭제에 실패했습니다',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// 선택된 이미지 처리
  Future<void> _handleImageSelected(File file) async {
    setState(() {
      _isUploadingProfileImage = true;
    });

    final upload = context.read<UploadService>();
    final task = upload.enqueueFile(file, kind: UploadKind.profile);
    _profileUploadTask = task;
    _profileTaskListener = () async {
      if (!mounted) return;
      if (task.state == UploadState.success) {
        try {
          final imageUrl = task.url ?? '';

          if (imageUrl.isNotEmpty) {
            await _controller.updateProfileImageAfterUpload(imageUrl);
          } else {
            print(
              '[UserProfileScreen] imageUrl is empty, calling fetchMyProfile',
            );
            await context.read<UserProvider>().fetchMyProfile();
          }
        } catch (e) {
          print('[UserProfileScreen] Error in upload success handler: $e');
        }
        if (_profileTaskListener != null) {
          task.removeListener(_profileTaskListener!);
          _profileTaskListener = null;
        }
        _profileUploadTask = null;
        if (mounted) {
          // 1초 딜레이 후 로딩 인디케이터 숨김
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            setState(() {
              _isUploadingProfileImage = false;
            });
          }
        }
      }
      if (task.state == UploadState.failed ||
          task.state == UploadState.cancelled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '업로드에 실패했어요 네트워크 상태를 확인해주세요',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        if (_profileTaskListener != null) {
          task.removeListener(_profileTaskListener!);
          _profileTaskListener = null;
        }
        _profileUploadTask = null;
        if (mounted) {
          setState(() {
            _isUploadingProfileImage = false;
          });
        }
      }
    };
    task.addListener(_profileTaskListener!);
  }

  /// 계정 관리 바텀시트 표시
  void _showAccountManagementOverlay(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // 디버그: 드롭다운 열릴 때 계정 상태 덤프
        AccountManagerService.debugPrintAllAccounts();
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: JoinScreen(isRedirectMode: true),
          ),
        );
      },
    );
  }
}

// 위젯 분리: ShimmerEffect, ProfileAvatar는 각 widgets/ 파일로 이동
