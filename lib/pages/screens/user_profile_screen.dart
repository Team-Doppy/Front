import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/category_sheet.dart';
import 'package:doppy/pages/components/feed.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/share_profile_bottom_sheet.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/screens/group_selection_screen.dart';
import 'package:doppy/pages/screens/setting_screen.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/profile_edit_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:async';

class UserProfileScreen extends StatefulWidget {
  final User? otherUser; // 다른 사용자 프로필을 볼 때 username 전달
  final bool isFromBottomTab; // 바텀 탭에서 직접 열렸는지 여부

  const UserProfileScreen({
    super.key,
    this.otherUser,
    this.isFromBottomTab = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  // 스크롤 컨트롤러 및 상태
  late ScrollController _scrollController;
  late final bool _isOwnProfile;
  late final BaseFeedProvider _feedProvider;

  // 업로드 진행 상태
  UploadTask? _profileUploadTask;
  VoidCallback? _profileTaskListener;

  // 프로필 사진 변경 상태
  bool _isUploadingProfileImage = false;

  static final CategoryDropDown _categoryDropDown = CategoryDropDown();
  static final Feed _feed = Feed();
  final GlobalKey _categoryButtonKey = GlobalKey();
  static bool _prefetchedFriendsOnce = false; // 첫 진입 1회만 프리캐싱
  double _pullProgress = 0.0; // 당기는 진행률 (0.0 ~ 1.0)
  Future<void>? _friendStatusFuture; // 친구 상태 초기 확인 Future (빌드 내 로딩 제어)
  VoidCallback? _disconnectHandler; // 코디네이터 해제용

  // 프로필 편집용 TextEditingController
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // otherUser가 현재 사용자와 동일한지 확인
    final currentUser = context.read<UserProvider>().currentUser;
    final isActuallyMe =
        widget.otherUser != null &&
        currentUser != null &&
        widget.otherUser!.username == currentUser.username;

    // otherUser가 null이거나, otherUser가 나 자신이면 내 프로필
    _isOwnProfile = (widget.otherUser == null) || isActuallyMe;
    _scrollController = ScrollController();

    // 내 프로필이면 MyProfileFeedProvider, 다른 사람 프로필이면 ProfileFeedProvider 사용
    if (_isOwnProfile) {
      _feedProvider = context.read<MyProfileFeedProvider>();
    } else {
      _feedProvider = context.read<OtherProfileFeedProvider>();
    }

    // 스크롤 리스너 추가: 페이지네이션 자동 로드
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<PostDragDropService>().setVerticalController(
          _scrollController,
        );
      } catch (_) {}
    });

    // 피드 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _feedProvider.setReadOnly(!_isOwnProfile);
      } catch (_) {}
    });

    // 타인 프로필일 때 개인적인 카테고리가 선택되어 있으면 "전체"로 변경
    if (!_isOwnProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_feedProvider.selectedBase != BaseFilter.all) {
            _feedProvider.selectBase(BaseFilter.all);
          }
        } catch (_) {}
      });

      // 친구 상태 확인은 초기 1회만 수행하되, Future를 저장해 빌드에서 로딩 제어
      try {
        final friendProvider = context.read<FriendProvider>();
        _friendStatusFuture = friendProvider
            .checkFriendStatus(widget.otherUser!.username)
            .whenComplete(() {
              // 상태 플래그 제거: 더 이상 사용하지 않음
            });
      } catch (_) {}
    }

    // 카테고리 변경 콜백 설정
    _categoryDropDown.setOnCategoryChanged(() {});

    // 이 코드 하나로 모든 데이터 로딩이 시작됩니다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 시스템 네트워크 변화 구독 시작 (중복 호출 안전)
      try {
        NetworkManager.initConnectivityMonitor();
      } catch (_) {}
      // 오프라인 대비: 로컬 캐시된 사용자 정보 임시 로드
      try {
        await context.read<UserProvider>().loadCurrentUserFromPrefs();
      } catch (_) {}

      // 프로필 피드 초기 로드 (캐시가 있을 때는 요청 생략)
      try {
        final bool isOther = !_isOwnProfile;
        final bool hasCachedData =
            _feedProvider.categories.isNotEmpty ||
            _feedProvider.posts.isNotEmpty;
        if (!hasCachedData) {
          await _feedProvider.loadInitial(
            username: isOther ? widget.otherUser!.username : null,
            force: false, // 스마트 캐시 전략 사용 (3분 TTL)
          );
        }
      } catch (_) {}
    });

    // 전역 코디네이터에 등록: 온라인 시 단발 갱신
    _disconnectHandler = ConnectivityReloadCoordinator().registerHandler(
      id: 'profile',
      onOnline: () async {
        if (!mounted) return;
        // 캐시 사용자 정보가 비어있으면 먼저 프로필 정보를 로드
        if (_isOwnProfile) {
          final me = context.read<UserProvider>().currentUser;
          final bool missing =
              me == null ||
              (((me.alias ?? '').isEmpty) &&
                  ((me.profileImageUrl ?? '').isEmpty) &&
                  ((me.selfIntroduction ?? '').isEmpty));
          if (missing) {
            try {
              await context.read<UserProvider>().fetchMyProfile();
            } catch (_) {}
          }
        }
        // 자동 데이터 가져오기 시, 이미 내용이 있으면 추가 요청 보내지 않음
        final bool hasFeedData =
            _feedProvider.categories.isNotEmpty ||
            _feedProvider.posts.isNotEmpty;
        if (!hasFeedData) {
          await _handleRefresh();
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('[UserProfileScreen] didChangeDependencies');
  }

  Future<void> _handleRefresh() async {
    try {
      final bool isOther = !_isOwnProfile;
      // 새로고침 시 프로바이더 캐시를 먼저 비운다 (강제 재로딩 보장)
      try {
        _feedProvider.clearInMemory();
      } catch (_) {}

      // 🎯 남의 프로필일 때 친구 관계도 새로고침
      if (isOther) {
        try {
          final friendProvider = context.read<FriendProvider>();
          await friendProvider.checkFriendStatus(widget.otherUser!.username);
        } catch (e) {
          print('[UserProfileScreen] 친구 상태 새로고침 실패: $e');
        }
      }

      await _feedProvider.loadInitial(
        username: isOther ? widget.otherUser!.username : null,
        force: true, // 강제로 새로 로드
      );
    } catch (e) {
      print('[UserProfileScreen] Refresh error: $e');
    }
  }

  /// 스크롤 리스너: 끝에 가까워지면 다음 페이지 로드
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8; // 80% 지점에서 로드

    // 스크롤이 끝에서 200픽셀 이내이거나 80% 이상 스크롤되었을 때
    if (currentScroll >= threshold) {
      // 더 로드할 데이터가 있고, 현재 로딩 중이 아닐 때만 호출
      if (_feedProvider.hasMore && !_feedProvider.isLoadingMore) {
        print(
          '[UserProfileScreen] 스크롤 끝 감지 - 자동 로드 시작 (${(currentScroll / maxScroll * 100).toStringAsFixed(1)}%)',
        );
        _feedProvider.loadMore();
      }
    }
  }

  @override
  void dispose() {
    _categoryDropDown.setOnCategoryChanged(null);

    // 스크롤 리스너 제거
    _scrollController.removeListener(_onScroll);

    if (mounted) {
      try {
        _feedProvider.clearInMemory();
      } catch (_) {}
    }

    _scrollController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _disconnectHandler?.call();
    if (_profileUploadTask != null && _profileTaskListener != null) {
      _profileUploadTask!.removeListener(_profileTaskListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    final bool isOther = !_isOwnProfile; // true: 타인 프로필, false: 내 프로필
    final User? me = userProvider.currentUser;
    final User? other = widget.otherUser;

    final double topPadding = MediaQuery.of(context).padding.top;

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

    // 이 화면 하위 트리에 BaseFeedProvider 타입으로 현재 피드 프로바이더를 주입
    return ChangeNotifierProvider<BaseFeedProvider>.value(
      value: _feedProvider,
      child: Material(
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 스크롤 가능한 컨텐츠 (Sliver)
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _feed.isDraggingCategory,
                builder: (context, isDraggingCategory, _) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin:
                          isDraggingCategory
                              ? 0.7
                              : 1.0, // 초기값을 end와 동일하게 설정하여 애니메이션 방지
                      end: isDraggingCategory ? 0.7 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        alignment: Alignment.center,
                        child: child,
                      );
                    },

                    child: CustomRefreshIndicator(
                      top: 120,
                      onRefresh: _handleRefresh,
                      onPullProgress: (progress) {
                        setState(() {
                          _pullProgress = progress;
                        });
                      },
                      child: RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: false, // 🎯 스크롤할 때만 표시
                        thumbColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.15),
                        thickness: 4,
                        radius: Radius.circular(2),
                        child: CustomScrollView(
                          clipBehavior: Clip.none,
                          controller: _scrollController,
                          slivers: [
                            SliverAppBar(
                              expandedHeight: topPadding + 30,
                              toolbarHeight: 50,
                              backgroundColor: Colors.transparent,
                              automaticallyImplyLeading: false,
                              elevation: 0,
                              title: Opacity(
                                opacity: 1.0 - _pullProgress,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    // 바텀 탭에서 직접 온 경우가 아닐 때만 뒤로가기 버튼 표시
                                    if (!widget.isFromBottomTab)
                                      GestureDetector(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 1,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons
                                                    .arrow_back_ios_new_rounded,
                                                size: 24,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.75),
                                              ),
                                              SizedBox(width: 14),
                                            ],
                                          ),
                                        ),

                                        onTap:
                                            () => Navigator.of(context).pop(),
                                      ),
                                    Text(
                                      _displayUsername,
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface.withOpacity(1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              actions: [
                                Opacity(
                                  opacity: 1.0 - _pullProgress,
                                  child: Row(
                                    children: [
                                      // 🎯 링크 아이콘 (링크가 있을 때만 표시)
                                      if ((isOther &&
                                              other?.links != null &&
                                              other!.links!.isNotEmpty) ||
                                          (!isOther &&
                                              me?.links != null &&
                                              me!.links!.isNotEmpty))
                                        GestureDetector(
                                          onTap: () {
                                            final links =
                                                isOther
                                                    ? (other?.links ?? [])
                                                    : (me?.links ?? []);
                                            final linkTitles =
                                                isOther
                                                    ? (other?.linkTitles)
                                                    : (me?.linkTitles);
                                            if (links.isNotEmpty) {
                                              _showLinksModal(
                                                context,
                                                links,
                                                linkTitles,
                                              );
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            child: SvgPicture.asset(
                                              'assets/icons/link.svg',
                                              width: 26,
                                              height: 26,
                                              colorFilter: ColorFilter.mode(
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_isOwnProfile) ...[
                                        SizedBox(width: 8),
                                        GestureDetector(
                                          child: SvgPicture.asset(
                                            'assets/icons/edit.svg',
                                            width: 22,
                                            height: 22,
                                            colorFilter: ColorFilter.mode(
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                              BlendMode.srcIn,
                                            ),
                                          ),
                                          onTap: () {
                                            me != null
                                                ? showProfileInfoEditBottomSheet(
                                                  me,
                                                )
                                                : null;
                                          },
                                        ),
                                        SizedBox(width: 16),
                                        // 설정 버튼
                                        GestureDetector(
                                          child: SvgPicture.asset(
                                            'assets/icons/menu.svg',
                                            width: 20,
                                            height: 20,
                                            colorFilter: ColorFilter.mode(
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                              BlendMode.srcIn,
                                            ),
                                          ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => SettingScreen(),
                                              ),
                                            );
                                          },
                                        ),
                                        SizedBox(width: 15),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 50),

                                  // 원형 아바타 (링크 아래에 위치)
                                  CommonProfileAvatar(
                                    imageUrl: _displayImageUrl,
                                    username: _displayUsername,
                                    size: 150,
                                    borderWidth:
                                        _isUploadingProfileImage ? 0 : 3,
                                    borderColor:
                                        Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.grey.shade300
                                            : Colors.grey.shade400,
                                    isUploading: _isUploadingProfileImage,
                                    onTap:
                                        _isOwnProfile &&
                                                !_isUploadingProfileImage
                                            ? _changeProfileImage
                                            : null,
                                  ),

                                  const SizedBox(height: 20),
                                  GestureDetector(
                                    onTap: () {
                                      if (me != null) {
                                        showProfileInfoEditBottomSheet(me);
                                      }
                                    },
                                    child: Column(
                                      children: [
                                        Text(
                                          _displayAlias ?? _displayUsername,
                                          style: TextStyle(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                          ),
                                        ),

                                        const SizedBox(height: 5),
                                        Text(
                                          isOther
                                              ? (other
                                                          ?.selfIntroduction
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? other!.selfIntroduction!
                                                  : _displayUsername)
                                              : (me
                                                          ?.selfIntroduction
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? me!.selfIntroduction!
                                                  : ''),
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.8),

                                            fontSize: 14,
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 다른 사용자 프로필일 때만 친구 추가 버튼 표시
                                  if (isOther) ...[_buildOtherProfileButton()],
                                  if (_isOwnProfile) ...[
                                    _buildMyProfileButton(),
                                  ],
                                ],
                              ),
                            ),
                            // Feed 모드 전환 스위처 (카드뷰 / 이미지 전용)
                            _buildFeedModeSwitcher(),
                            // Feed 컨텐츠 (네트워크 에러 처리 포함)
                            Consumer<BaseFeedProvider>(
                              builder: (context, feedProvider, _) {
                                // 정상 상태일 때 Feed 컨텐츠 표시
                                return _feed.buildFeedContent(
                                  scrollController: _scrollController,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).padding.top - 10,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFeedModeSwitcher() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
        child: ValueListenableBuilder<FeedDisplayMode>(
          valueListenable: FeedDisplayModeManager(),
          builder: (context, displayMode, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildCategoryButton(Icons.grid_view_rounded),
                Spacer(),
                // 그리드 아이콘 → 이미지 전용 모드
                _buildModeButton(
                  FeedDisplayMode.imageOnly,
                  Icons.grid_view_rounded,
                ),
                const SizedBox(width: 8),
                // 리스트 아이콘 → 카드(텍스트 포함) 모드
                _buildModeButton(FeedDisplayMode.card, Icons.view_list_rounded),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryButton(IconData icon) {
    return GestureDetector(
      onTap: () {
        _categoryDropDown.showCategoryDropdown(
          context,
          _categoryButtonKey,
          _feedProvider,
        );
      },
      child: Container(
        key: _categoryButtonKey,

        child: Container(
          margin: EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
          ),

          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 8),
                _isOwnProfile
                    ? Consumer<MyProfileFeedProvider>(
                      builder:
                          (context, provider, _) => Text(
                            context.tr(provider.selectedLabel),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(1),
                            ),
                          ),
                    )
                    : Consumer<OtherProfileFeedProvider>(
                      builder:
                          (context, provider, _) => Text(
                            context.tr(provider.selectedLabel),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(1),
                            ),
                          ),
                    ),
                SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                ),
                SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(FeedDisplayMode mode, IconData icon) {
    final displayModeManager = FeedDisplayModeManager();
    final bool selected = displayModeManager.value == mode;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        if (mode == FeedDisplayMode.card) {
          displayModeManager.switchToCard();
        } else {
          displayModeManager.switchToImageOnly();
        }
      },

      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
        ),
        child: Icon(
          icon,
          size: 20,
          color:
              selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildMyProfileButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 12, right: 12, top: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildGlassyButton(
              text: context.tr('my_groups'),
              onTap: () => _navigateToManageGroup(),
            ),
          ),
          SizedBox(width: 4),
          Expanded(
            child: _buildGlassyButton(
              text: context.tr('share_profile'),
              onTap: () {
                final me = context.read<UserProvider>().currentUser;
                if (me == null) return;
                // 공유 버튼
                ShareProfileBottomSheet.show(
                  context,
                  username: me.username,
                  profileImageUrl: me.profileImageUrl,
                  bio: me.selfIntroduction,
                  friendCount: me.friendCount ?? 0,
                  links: me.links,
                  linkTitles: me.linkTitles,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 친구 관리 화면으로 이동 (이미지 프리캐싱 포함)
  Future<void> _navigateToManageGroup() async {
    final friendProvider = context.read<FriendProvider>();

    // 모든 친구의 프로필 이미지 수집
    final List<String> imageUrls = [];

    // 수락된 친구들의 이미지
    for (final friend in friendProvider.acceptedFriends) {
      if (friend.profileImageUrl != null &&
          friend.profileImageUrl!.isNotEmpty) {
        imageUrls.add(friend.profileImageUrl!);
      }
    }

    // 받은 요청의 이미지
    for (final friend in friendProvider.receivedRequests) {
      if (friend.profileImageUrl != null &&
          friend.profileImageUrl!.isNotEmpty) {
        imageUrls.add(friend.profileImageUrl!);
      }
    }

    // 보낸 요청의 이미지
    for (final friend in friendProvider.sentRequests) {
      if (friend.profileImageUrl != null &&
          friend.profileImageUrl!.isNotEmpty) {
        imageUrls.add(friend.profileImageUrl!);
      }
    }

    // 화면 전환: 페이드 인 전환 (옆에서 슬라이드되는 페이지 전환 대신)
    if (mounted) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  const GroupSelectionScreen(),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }

    // 이미지 프리캐싱: 백그라운드에서 1회만 수행(체감 지연 제거)
    if (!_prefetchedFriendsOnce && imageUrls.isNotEmpty && mounted) {
      _prefetchedFriendsOnce = true;
      final List<Future<void>> precacheFutures = [];
      for (final url in imageUrls) {
        precacheFutures.add(
          precacheImage(NetworkImage(url), context).catchError((_) {}),
        );
      }
      Future.wait(precacheFutures)
          .timeout(const Duration(seconds: 2), onTimeout: () => <void>[])
          .catchError((_) => <void>[]);
    }
  }

  Widget _buildOtherProfileButton() {
    return Consumer2<FriendProvider, BaseFeedProvider>(
      builder: (context, friendProvider, feedProvider, _) {
        // 네트워크 에러가 있으면 로딩 상태로 표시
        // NetworkManager 상태도 확인
        if (feedProvider.networkError != null || !NetworkManager.isOnline) {
          return SizedBox.shrink();
        }

        // 친구 상태에 따른 버튼 텍스트와 액션 결정
        String buttonText;
        VoidCallback buttonAction;

        final l10n = AppLocalizations.of(context);

        switch (friendProvider.friendStatus) {
          case FriendRequestStatus.blocked:
            // 🎯 차단된 사용자
            buttonText = l10n.t('blocked');
            buttonAction = () async {
              // 차단 해제 다이얼로그
              final confirm = await DialogUtils.showConfirmDialog(
                context,
                title: l10n.t('unblock_user_title'),
                message: l10n
                    .t('unblock_user_message')
                    .replaceAll(
                      '{name}',
                      widget.otherUser?.alias ??
                          widget.otherUser?.username ??
                          '이 사용자',
                    ),
                confirmText: l10n.t('unblock_user'),
                cancelText: l10n.t('cancel'),
                isDestructive: false,
              );

              if (confirm == true && mounted) {
                try {
                  final friendService = FriendService();
                  await friendService.unblockUser(widget.otherUser!.username);

                  // 상태 새로고침
                  await friendProvider.checkFriendStatus(
                    widget.otherUser!.username,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.t('unblock_success')),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ErrorHandler.showError(context, e.toString());
                  }
                }
              }
            };
            break;
          case FriendRequestStatus.none:
            buttonText = l10n.t('add_friend');
            buttonAction = () async {
              try {
                await friendProvider.sendFriendRequest(
                  widget.otherUser!.username,
                );
              } catch (e) {}
            };
            break;
          case FriendRequestStatus.requested:
            buttonText = l10n.t('cancel_friend_request');
            buttonAction = () async {
              try {
                await friendProvider.deleteFriend(widget.otherUser!.username);
              } catch (e) {}
            };
            break;
          case FriendRequestStatus.accepted:
            buttonText = l10n.t('remove_friend');
            buttonAction = () async {
              // 확인 다이얼로그 표시
              final confirm = await DialogUtils.showConfirmDialog(
                context,
                title: l10n.t('remove_friend'),
                message: l10n
                    .t('remove_friend_confirm')
                    .replaceAll(
                      '{name}',
                      widget.otherUser?.alias ??
                          widget.otherUser?.username ??
                          '이 사용자',
                    ),
                confirmText: l10n.t('remove_friend'),
                cancelText: l10n.t('cancel'),
                isDestructive: true,
              );

              // 확인을 누른 경우에만 친구 취소 실행
              if (confirm == true && mounted) {
                try {
                  // 🎯 GroupProvider 전달하여 allFriends 그룹 memberCount 업데이트
                  final groupProvider = context.read<GroupProvider>();
                  await friendProvider.deleteFriend(
                    widget.otherUser!.username,
                    groupProvider: groupProvider,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('오류: $e')));
                  }
                }
              }
            };
            break;
          default:
            buttonText = '';
            buttonAction = () {};
        }

        // 빌드 안에서 FutureBuilder로 로딩 → 완료 후 부드럽게 버튼 표시
        return FutureBuilder<void>(
          future: _friendStatusFuture,
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: isLoading ? 0.0 : 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (context, opacity, child) {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: 4,
                    left: 12,
                    right: 12,
                    top: 20,
                  ),
                  child: Opacity(
                    opacity: opacity,
                    child: _buildFilledButton(
                      text: buttonText,
                      onTap: buttonAction,
                      isLoading: friendProvider.isLoadingStatus,
                      isFilled:
                          friendProvider.friendStatus ==
                          FriendRequestStatus.none,
                      isBlocked:
                          friendProvider.friendStatus ==
                          FriendRequestStatus.blocked, // 🎯 차단된 경우 스타일 변경
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFilledButton({
    required String text,
    required VoidCallback onTap,
    bool isLoading = false,
    bool isFilled = false,
    bool isBlocked = false, // 🎯 차단된 사용자 표시용
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 44, // 고정 높이로 UI 흔들림 방지
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color:
              isBlocked
                  ? Theme.of(context).colorScheme.error.withOpacity(
                    0.1,
                  ) // 🎯 차단된 경우 빨간색 배경
                  : isFilled
                  ? Theme.of(context).colorScheme.primary.withOpacity(1)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
        ),
        child: Center(
          child:
              isLoading
                  ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isFilled
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                  : Text(
                    text,
                    style: TextStyle(
                      color:
                          isBlocked
                              ? Theme.of(context)
                                  .colorScheme
                                  .error // 🎯 차단된 경우 빨간색 텍스트
                              : isFilled
                              ? Colors.white
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildGlassyButton({
    required String text,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),

          color:
              isDarkMode
                  ? const Color.fromARGB(255, 60, 60, 60)
                  : Colors.grey.shade200,
        ),
        child: Center(
          child:
              isLoading
                  ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                  : Text(
                    text,
                    style: TextStyle(
                      color:
                          isDarkMode
                              ? Theme.of(context).colorScheme.onSurface
                              : const Color.fromARGB(255, 61, 61, 61),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
        ),
      ),
    );
  }

  /// 🎯 링크 모달 표시 (드래그로 닫기 가능)
  void _showLinksModal(
    BuildContext context,
    List<String> links,
    Map<String, String>? linkTitles,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true, // 🎯 드래그로 닫기 활성화
      isDismissible: true, // 🎯 배경 탭으로 닫기 활성화
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 드래그 핸들
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // 제목
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Row(
                      children: [
                        SvgPicture.asset(
                          'assets/icons/link.svg',
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                            Theme.of(context).colorScheme.onSurface,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(
                            Icons.close,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 링크 목록
                  Flexible(
                    child: ListView.separated(
                      controller: scrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: links.length,
                      separatorBuilder: (context, index) {
                        return Divider(
                          height: 1,
                          thickness: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.1),
                          indent: 0,
                          endIndent: 0,
                        );
                      },
                      itemBuilder: (context, index) {
                        return _buildLinkModalItem(
                          context,
                          links[index],
                          linkTitles,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 🎯 모달용 링크 아이템 위젯
  Widget _buildLinkModalItem(
    BuildContext context,
    String url,
    Map<String, String>? linkTitles,
  ) {
    // URL 정규화
    String displayUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      displayUrl = 'https://$url';
    }

    // 도메인 추출
    String domain = url;
    String? thumbnailUrl;
    try {
      final uri = Uri.parse(displayUrl);
      domain = uri.host.replaceFirst('www.', '');
      // 🎯 썸네일 URL 생성 (Google Favicon API 또는 도메인 기반)
      thumbnailUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
    } catch (_) {
      domain = url;
    }

    // 🎯 사용자가 설정한 커스텀 타이틀 가져오기
    final customTitle = linkTitles?[url];
    final displayTitle = customTitle ?? domain; // 커스텀 타이틀이 있으면 사용, 없으면 도메인

    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () async {
        try {
          final uri = Uri.parse(displayUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          // 바텀시트 닫기
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        } catch (e) {
          if (context.mounted) {
            ErrorHandler.showError(context, '링크를 열 수 없습니다: $url');
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),

        child: Row(
          children: [
            // 🎯 링크 썸네일
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  thumbnailUrl != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          thumbnailUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.link,
                              size: 20,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.5,
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            return Center();
                          },
                        ),
                      )
                      : Icon(
                        Icons.link,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
            ),
            const SizedBox(width: 16),
            // 링크 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🎯 커스텀 타이틀 또는 도메인 표시
                  Text(
                    displayTitle,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // URL 표시 (커스텀 타이틀이 있으면 URL, 없으면 도메인)
                  Text(
                    customTitle != null ? url : domain,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 프로필 사진 변경 바텀시트 표시
  void _changeProfileImage() {
    if (_isUploadingProfileImage) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,

      builder: (BuildContext context) {
        return ProfileEditBottomSheet(
          singleSelect: true,
          onClearProfileImage: _clearProfileImage,
          onImagesSelected: (files) => _handleImageSelected(files.first),
        );
      },
    );
  }

  void showProfileInfoEditBottomSheet(User me) {
    // 컨트롤러에 현재 값 설정
    _nameController.text = me.alias ?? '';
    _descriptionController.text = me.selfIntroduction ?? '';

    print(
      '[UserProfile] Bottom sheet 열기 - 이름: "${_nameController.text}", 소개: "${_descriptionController.text}"',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return ProfileInfoEditBottomSheet(
          user: me,
          nameController: _nameController,
          descriptionController: _descriptionController,
          onClearProfileImage: _clearProfileImage,
          onImagesSelected: (files) => _handleImageSelected(files.first),
          onSave: ({
            required String alias,
            required String description,
            List<String>? links, // 🎯 프로필 링크 목록 (최대 3개)
            Map<String, String>? linkTitles, // 🎯 링크 타이틀 (URL -> 타이틀)
          }) async {
            // UserProvider를 통해 API 호출 및 상태 업데이트
            final userProvider = context.read<UserProvider>();

            final success = await userProvider.updateProfileInfo(
              alias: alias,
              selfIntroduction: description,
              links: links,
              linkTitles: linkTitles,
            );

            if (!success && mounted) {
              // 실패 메시지 표시
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '프로필 저장에 실패했습니다',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
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
      bool success = false;
      if (_isOwnProfile) {
        success = await context
            .read<MyProfileFeedProvider>()
            .deleteProfileImageAndUpdateCache(context);
      } else {
        // 다른 사람 프로필에서는 이 기능을 사용할 수 없음
        throw Exception('다른 사람의 프로필 이미지는 삭제할 수 없습니다');
      }

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
            if (_isOwnProfile) {
              await context
                  .read<MyProfileFeedProvider>()
                  .updateProfileImageAfterUpload(imageUrl, context);
            } else {
              // 다른 사람 프로필에서는 이 기능을 사용할 수 없음
              throw Exception('다른 사람의 프로필 이미지는 업데이트할 수 없습니다');
            }
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
          ErrorHandler.showError(
            context,
            context.tr('profile_image_upload_failed'),
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
        return; // 흐름 즉시 중단
      }
    };
    task.addListener(_profileTaskListener!);
  }
}
