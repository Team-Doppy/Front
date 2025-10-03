import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/pages/user/setting_screen.dart';
import 'package:doppy/utils/route_observer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/screens/manage_neighbor_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';

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

  @override
  void initState() {
    super.initState();
    _isOwnProfile = (widget.otherUser == null);
    _scrollController = ScrollController()..addListener(_onScroll);

    // 캐시된 값들 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheMediaQueryValues();
    });

    // 배경 이미지 상태 즉시 확인
    _checkBackgroundImage();

    // ✅ [구조 개선] Provider를 통해 필요한 데이터를 한번에 요청합니다.
    // 이 코드 하나로 모든 데이터 로딩이 시작됩니다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_isOwnProfile) {
        // 내 프로필에 필요한 데이터 로딩
      } else {
        // 다른 사용자 프로필: 서버에서 상세 정보 & 친구 상태 병렬 로딩
        context.read<FriendProvider>().checkFriendStatus(
          widget.otherUser!.username,
        );
      }
      // 프로필 피드 초기 로드
      try {
        final bool isOther = !_isOwnProfile;
        await context.read<ProfileFeedProvider>().loadInitial(
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

  void _checkBackgroundImage() {
    final userProvider = context.read<UserProvider>();
    String imageUrl = '';

    if (_isOwnProfile) {
      final me = userProvider.currentUser;
      imageUrl = me?.profileImageUrl ?? '';
    } else {
      final other = widget.otherUser;
      imageUrl = other?.profileImageUrl ?? '';
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
              duration: const Duration(milliseconds: 150),
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

    // 맨 위로 복귀하면 스냅을 다시 허용
    if (currentOffset < 10.0 && _didAutoSnap) {
      _didAutoSnap = false;
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
      color: Colors.transparent,
      child: Stack(
        children: [
          // 배경 (테마에 맞는 단일 색상)
          Positioned.fill(
            child: Container(color: Theme.of(context).colorScheme.background),
          ),

          // 스크롤 가능한 컨텐츠 (Sliver)
          Positioned.fill(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  expandedHeight: topPadding + _baseHeight,
                  toolbarHeight: topPadding + 0,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading:
                      isOther
                          ? IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 20,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          )
                          : SizedBox(),

                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(color: Colors.transparent),
                  ),

                  actions: [
                    if (_isOwnProfile) ...[
                      // 내 이웃 버튼
                      IconButton(
                        icon: Icon(
                          Icons.people,
                          color: Theme.of(context).colorScheme.onBackground,
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
                          color: Theme.of(context).colorScheme.onSurface,
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
                        child:
                            _hasFeeds
                                ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 50),
                                    // 원형 아바타 (텍스트 위에 위치)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // 아바타 (1차 스냅에서 완전히 페이드아웃)
                                        Opacity(
                                          opacity: avatarOpacity,
                                          child: CommonProfileAvatar(
                                            imageUrl: _displayImageUrl,
                                            username: _displayUsername,
                                            size: 150,
                                            borderWidth: 2,
                                            borderColor:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade600,
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
                                            ? (other
                                                        ?.selfIntroduction
                                                        ?.isNotEmpty ==
                                                    true
                                                ? other!.selfIntroduction!
                                                : _displayUsername)
                                            : (myIntro?.isNotEmpty == true
                                                ? myIntro!
                                                : '행복은 사소한 이 순간부터 시작된다고 믿어요, \n모두 행복하길 바랍니다.'),
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
                                          builder: (
                                            context,
                                            friendProvider,
                                            _,
                                          ) {
                                            // 친구 상태에 따른 버튼 텍스트와 액션 결정
                                            String buttonText;
                                            VoidCallback buttonAction;

                                            switch (friendProvider
                                                .friendStatus) {
                                              case FriendRequestStatus.none:
                                                buttonText = '이웃 추가';
                                                buttonAction = () async {
                                                  try {
                                                    await friendProvider
                                                        .sendFriendRequest(
                                                          widget
                                                              .otherUser!
                                                              .username,
                                                        );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            '이웃 요청을 보냈습니다',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            '오류: $e',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                };
                                                break;
                                              case FriendRequestStatus
                                                  .requested:
                                                buttonText = '요청 취소';
                                                buttonAction = () async {
                                                  try {
                                                    await friendProvider
                                                        .deleteFriend(
                                                          widget
                                                              .otherUser!
                                                              .username,
                                                        );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '이웃 요청을 취소했습니다',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            '오류: $e',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                };
                                                break;
                                              case FriendRequestStatus.accepted:
                                                buttonText = '친구 취소';
                                                buttonAction = () async {
                                                  try {
                                                    await friendProvider
                                                        .deleteFriend(
                                                          widget
                                                              .otherUser!
                                                              .username,
                                                        );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '친구를 삭제했습니다',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            '오류: $e',
                                                          ),
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
                                              isLoading:
                                                  friendProvider.isLoading,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                                : SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.6,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // 아바타 (1차 스냅에서 완전히 페이드아웃)
                                          Opacity(
                                            opacity: avatarOpacity,
                                            child: CommonProfileAvatar(
                                              imageUrl: _displayImageUrl,
                                              username: _displayUsername,
                                              size: 80,
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
                                              ? (other
                                                          ?.selfIntroduction
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? other!.selfIntroduction!
                                                  : _displayUsername)
                                              : (myIntro?.isNotEmpty == true
                                                  ? myIntro!
                                                  : '행복은 사소한 이 순간부터 시작된다고 믿어요, \n모두 행복하길 바랍니다.'),
                                          style: TextStyle(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
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
                                            builder: (
                                              context,
                                              friendProvider,
                                              _,
                                            ) {
                                              // 친구 상태에 따른 버튼 텍스트와 액션 결정
                                              String buttonText;
                                              VoidCallback buttonAction;

                                              switch (friendProvider
                                                  .friendStatus) {
                                                case FriendRequestStatus.none:
                                                  buttonText = '이웃 추가';
                                                  buttonAction = () async {
                                                    try {
                                                      await friendProvider
                                                          .sendFriendRequest(
                                                            widget
                                                                .otherUser!
                                                                .username,
                                                          );
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              '이웃 요청을 보냈습니다',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              '오류: $e',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  };
                                                  break;
                                                case FriendRequestStatus
                                                    .requested:
                                                  buttonText = '요청 취소';
                                                  buttonAction = () async {
                                                    try {
                                                      await friendProvider
                                                          .deleteFriend(
                                                            widget
                                                                .otherUser!
                                                                .username,
                                                          );
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              '이웃 요청을 취소했습니다',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              '오류: $e',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  };
                                                  break;
                                                case FriendRequestStatus
                                                    .accepted:
                                                  buttonText = '친구 취소';
                                                  buttonAction = () async {
                                                    try {
                                                      await friendProvider
                                                          .deleteFriend(
                                                            widget
                                                                .otherUser!
                                                                .username,
                                                          );
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              '친구를 삭제했습니다',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              '오류: $e',
                                                            ),
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
                                                isLoading:
                                                    friendProvider.isLoading,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 100), // 하단 여백
                                    ],
                                  ),
                                ),
                      );
                    },
                  ),
                ),
                _buildFeedContent(),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
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
        if (feedProvider.isLoading && feedProvider.posts.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          );
        }

        if (feedProvider.posts.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Text(
                      '첫 번째 게시물을 작성해보세요!',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

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
    final String heroTag = 'profile_post_${post.id}_$index';

    return Hero(
      tag: heroTag,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder:
                    (context, animation, secondaryAnimation) =>
                        PostReaderScreen(
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
                          heroTag: heroTag,
                        ),
                transitionsBuilder: (
                  context,
                  animation,
                  secondaryAnimation,
                  child,
                ) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
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
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder:
                          (context, url) =>
                              Container(color: Colors.grey.withOpacity(0.3)),
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
      ),
    );
  }
}
