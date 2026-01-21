import 'package:doppy/pages/components/category_sheet.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/feed.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/share_profile_bottom_sheet.dart';
import 'package:doppy/pages/components/profile_action_bottom_sheet.dart';
import 'package:doppy/pages/screens/my_friends_screen.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/screens/setting_screen.dart';
import 'package:doppy/pages/screens/profile_image_view_screen.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/profile_edit_sheet.dart';
import 'package:doppy/pages/components/link_bottom_sheet.dart';
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
  double _pullProgress = 0.0; // 당기는 진행률 (0.0 ~ 1.0)
  Future<void>? _friendStatusFuture; // 친구 상태 초기 확인 Future (빌드 내 로딩 제어)
  VoidCallback? _disconnectHandler; // 코디네이터 해제용

  // 프로필 편집용 TextEditingController
  final TextEditingController _nameController = TextEditingController();

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

      // 🎯 Feed Provider의 username을 항상 현재 프로필과 동기화
      try {
        final bool isOther = !_isOwnProfile;
        final String? targetUsername =
            isOther ? widget.otherUser?.username : null;

        // 🎯 내 프로필일 때는 로드 건너뛰기 (캐시된 데이터만 사용)
        if (!isOther) {
          // 내 프로필일 때는 로드를 건너뜀
          return;
        }

        // 타인 프로필일 때만 Feed Provider의 username 동기화 및 로드
        if (isOther && targetUsername != null) {
          final otherProvider = _feedProvider as OtherProfileFeedProvider;
          if (otherProvider.username != targetUsername) {
            // username이 다르면 강제로 새로 로드
            await otherProvider.loadInitial(
              username: targetUsername,
              force: true,
            );
          } else {
            // username이 같으면 캐시 확인 후 로드
            final bool hasCachedData = _feedProvider.posts.isNotEmpty;
            if (!hasCachedData) {
              await _feedProvider.loadInitial(
                username: targetUsername,
                force: false,
              );
            }
          }

          // ✅ loadInitial 후 userInfo를 사용해서 viewedUser 설정
          final userInfo = _feedProvider.userInfo;
          if (userInfo != null && mounted) {
            try {
              final viewedUser = User.fromJson(userInfo);
              context.read<UserProvider>().setViewedUser(viewedUser);
              debugPrint(
                '[UserProfileScreen] viewedUser 설정 완료: ${viewedUser.username}',
              );
            } catch (e) {
              debugPrint('[UserProfileScreen] viewedUser 설정 실패: $e');
            }
          }
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
                  ((me.profileImageUrl ?? '').isEmpty));
          if (missing) {
            try {
              await context.read<UserProvider>().fetchMyProfile();
            } catch (_) {}
          }
        }
        // 자동 데이터 가져오기 시, 이미 내용이 있으면 추가 요청 보내지 않음
        final bool hasFeedData = _feedProvider.posts.isNotEmpty;
        if (!hasFeedData) {
          await _handleRefresh();
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _handleRefresh() async {
    try {
      final bool isOther = !_isOwnProfile;
      // ✅ 새로고침 중 "시작 가이드(빈 상태)"가 잠깐 보이는 플리커 방지:
      // - clearInMemory()는 데이터/로딩 플래그를 즉시 비워 UI가 빈 상태를 그릴 수 있음
      // - 대신 캐시만 무효화하고(force=true로) 서버 재로딩한다. (기존 데이터는 유지)
      try {
        if (!isOther) {
          final dyn = _feedProvider;
          if (dyn is MyProfileFeedProvider) {
            dyn.invalidateCache();
          }
        }
      } catch (_) {}

      // 🎯 내 프로필일 때 UserProvider도 새로고침
      if (!isOther) {
        try {
          await context.read<UserProvider>().fetchMyProfile();
        } catch (e) {
          debugPrint('[UserProfileScreen] 내 프로필 새로고침 실패: $e');
        }
      }

      // 🎯 남의 프로필일 때 친구 관계도 새로고침
      if (isOther) {
        try {
          final friendProvider = context.read<FriendProvider>();
          await friendProvider.checkFriendStatus(widget.otherUser!.username);
        } catch (e) {
          debugPrint('[UserProfileScreen] 친구 상태 새로고침 실패: $e');
        }
      }

      await _feedProvider.loadInitial(
        username: isOther ? widget.otherUser!.username : null,
        force: true, // 강제로 새로 로드
      );

      // ✅ loadInitial 후 userInfo를 사용해서 viewedUser 설정 (타인 프로필일 때만)
      if (isOther && mounted) {
        final userInfo = _feedProvider.userInfo;
        if (userInfo != null) {
          try {
            final viewedUser = User.fromJson(userInfo);
            context.read<UserProvider>().setViewedUser(viewedUser);
            debugPrint(
              '[UserProfileScreen] viewedUser 설정 완료 (refresh): ${viewedUser.username}',
            );
          } catch (e) {
            debugPrint('[UserProfileScreen] viewedUser 설정 실패 (refresh): $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[UserProfileScreen] Refresh error: $e');
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
        debugPrint(
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
    _scrollController.dispose();
    _nameController.dispose();
    _disconnectHandler?.call();
    if (_profileUploadTask != null && _profileTaskListener != null) {
      _profileUploadTask!.removeListener(_profileTaskListener!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ otherUser가 변경되면 상태를 강제로 업데이트하여 이전 이미지가 남지 않도록
    if (oldWidget.otherUser?.username != widget.otherUser?.username) {
      // 위젯 key가 변경되므로 자동으로 재생성됨
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    // ✅ build에서도 currentUser가 로드된 후 다시 확인 (initState에서 currentUser가 null일 수 있음)
    final User? me = userProvider.currentUser;
    final bool isActuallyMeNow =
        widget.otherUser != null &&
        me != null &&
        widget.otherUser!.username == me.username;
    final bool isOther =
        widget.otherUser != null &&
        !isActuallyMeNow; // true: 타인 프로필, false: 내 프로필

    final User? other = widget.otherUser;
    final User? viewedUser = isOther ? userProvider.viewedUser : null;

    // 🎯 build 메서드에서도 username 동기화 확인 (더 확실하게)
    // didUpdateWidget이 호출되지 않는 경우를 대비
    if (isOther && other != null) {
      final otherProvider = _feedProvider as OtherProfileFeedProvider;
      final targetUsername = other.username;

      // username이 다르면 즉시 동기화
      if (otherProvider.username != targetUsername &&
          !otherProvider.isLoading) {
        // 기존 데이터 클리어 (clearData 내부에서 notifyListeners 호출됨)
        otherProvider.clearData();

        // 즉시 새로 로드
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            await otherProvider.loadInitial(
              username: targetUsername,
              force: true,
            );

            // ✅ loadInitial 후 userInfo를 사용해서 viewedUser 설정
            if (mounted) {
              final userInfo = otherProvider.userInfo;
              if (userInfo != null) {
                try {
                  final viewedUser = User.fromJson(userInfo);
                  context.read<UserProvider>().setViewedUser(viewedUser);
                  debugPrint(
                    '[UserProfileScreen] viewedUser 설정 완료 (build): ${viewedUser.username}',
                  );
                } catch (e) {
                  debugPrint(
                    '[UserProfileScreen] viewedUser 설정 실패 (build): $e',
                  );
                }
              }
            }
          }
        });
      }
    }

    // 표시할 이미지 URL과 사용자명 결정
    String _displayImageUrl = '';
    String _displayUsername = '';
    String? _displayAlias;

    if (isOther) {
      // ✅ 타인 프로필: viewedUser 우선, 없으면 other 사용
      // other.profileImageUrl이 null이어도 viewedUser가 로드되면 자동으로 업데이트됨
      final displayUser = viewedUser ?? other;
      if (displayUser != null) {
        _displayImageUrl = displayUser.profileImageUrl ?? '';
        _displayUsername = displayUser.username;
        _displayAlias = displayUser.alias;
      }
    } else {
      // ✅ 내 프로필: me 사용
      if (me != null) {
        _displayImageUrl = me.profileImageUrl ?? '';
        _displayUsername = me.username;
        _displayAlias = me.alias;
      }
    }

    // 이 화면 하위 트리에 BaseFeedProvider 타입으로 현재 피드 프로바이더를 주입
    return ChangeNotifierProvider<BaseFeedProvider>.value(
      value: _feedProvider,
      child: PopScope(
        canPop: !widget.isFromBottomTab, // ✅ IndexedStack을 통해 들어온 경우 pop 막기
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).colorScheme.background,
          body: Stack(
            clipBehavior: Clip.none,
            children: [
              // 스크롤 가능한 컨텐츠 (Sliver)
              Positioned.fill(
                child: CustomRefreshIndicator(
                  top: 80,
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
                      physics:
                          const AlwaysScrollableScrollPhysics(), // 🎯 컨텐츠가 부족해도 스크롤 가능하도록
                      slivers: [
                        SliverAppBar(
                          expandedHeight: 0,
                          toolbarHeight: 56,
                          centerTitle: false,

                          leading:
                              widget.isFromBottomTab
                                  ? null // ✅ IndexedStack을 통해 들어온 경우 뒤로가기 버튼 숨김
                                  : Opacity(
                                    opacity: 1.0 - _pullProgress,
                                    child: Container(
                                      margin: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.background,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            size: 24,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.75),
                                          ),
                                          onPressed:
                                              () => Navigator.of(context).pop(),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ),
                                    ),
                                  ),
                          backgroundColor: Colors.transparent,
                          automaticallyImplyLeading: false,
                          elevation: 0,
                          pinned: false, // ✅ 위로 스크롤하면 사라짐
                          floating: false, // ✅ 아래로 스크롤하면 나타남
                          scrolledUnderElevation: 0,
                          actions: [
                            SafeArea(
                              bottom: false,
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.background,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  child: Opacity(
                                    opacity: 1.0 - _pullProgress,
                                    child: Row(
                                      children: [
                                        // 🎯 보낸 요청 아이콘 (내 프로필일 때만 표시)
                                        if (_isOwnProfile)
                                          Consumer<FriendProvider>(
                                            builder: (
                                              context,
                                              friendProvider,
                                              _,
                                            ) {
                                              final receivedCount =
                                                  friendProvider
                                                      .receivedRequests
                                                      .length;
                                              return Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  if (receivedCount > 0)
                                                    Positioned(
                                                      right: 7,
                                                      top: 9,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .error,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 16,
                                                              minHeight: 16,
                                                            ),
                                                        child: Text(
                                                          receivedCount > 99
                                                              ? '99+'
                                                              : '$receivedCount',
                                                          style:
                                                              const TextStyle(
                                                                color:
                                                                    Colors
                                                                        .white,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        if (_isOwnProfile) ...[
                                          SizedBox(width: 10),
                                          GestureDetector(
                                            child: SvgPicture.asset(
                                              'assets/icons/edit.svg',
                                              width: 25,
                                              height: 25,
                                              colorFilter: ColorFilter.mode(
                                                Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.85),
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
                                          SizedBox(width: 18),
                                          // 설정 버튼
                                          GestureDetector(
                                            child: SvgPicture.asset(
                                              'assets/icons/menu.svg',
                                              width: 23,
                                              height: 23,
                                              colorFilter: ColorFilter.mode(
                                                Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.85),
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) => SettingScreen(),
                                                ),
                                              );
                                            },
                                          ),
                                          SizedBox(width: 15),
                                        ] else ...[
                                          // 🎯 타인 프로필일 때 메뉴 버튼 (action 바텀시트 열기)
                                          SizedBox(width: 8),
                                          GestureDetector(
                                            child: SvgPicture.asset(
                                              'assets/icons/menu.svg',
                                              width: 21,
                                              height: 21,
                                              colorFilter: ColorFilter.mode(
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                            onTap: () {
                                              if (other != null) {
                                                ProfileActionBottomSheet.show(
                                                  context,
                                                  username: other.username,
                                                  alias: other.alias,
                                                  profileImageUrl:
                                                      other.profileImageUrl,
                                                  onBlockSuccess: () {
                                                    // 🎯 차단 성공 시 프로필 페이지 닫기
                                                    if (mounted) {
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                    }
                                                  },
                                                  hideViewProfile: true,
                                                );
                                              }
                                            },
                                          ),
                                          SizedBox(width: 15),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(height: 20),
                              // 원형 아바타 (링크 아래에 위치)
                              // 🎯 Consumer로 UploadService 감시하여 프로필 이미지 업로드 상태 자동 감지
                              Consumer<UploadService>(
                                builder: (context, uploadService, _) {
                                  // 프로필 이미지 업로드 중인 태스크 확인
                                  final profileUploadTasks =
                                      uploadService.tasks
                                          .where(
                                            (task) =>
                                                task.kind ==
                                                    UploadKind.profile &&
                                                (task.state ==
                                                        UploadState.pending ||
                                                    task.state ==
                                                        UploadState.uploading),
                                          )
                                          .toList();
                                  final isUploading =
                                      profileUploadTasks.isNotEmpty ||
                                      _isUploadingProfileImage;

                                  // ✅ Hero는 Transform/Progress/Shimmer 등 "동적 요소"와 분리된
                                  //    정적 아바타만 사용해야 비행 시작 깜빡임/튐이 줄어듭니다.
                                  // ✅ key를 추가하여 otherUser가 변경될 때 위젯을 강제로 재생성
                                  final heroAvatar = StaticProfileAvatar(
                                    key: ValueKey(
                                      'profile_avatar_${_displayUsername}_${_displayImageUrl}',
                                    ),
                                    imageUrl: _displayImageUrl,
                                    username: _displayUsername,
                                    size: 180,
                                    borderWidth: isUploading ? 0 : 3,
                                    borderColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.2),
                                  );

                                  // Hero 애니메이션 적용
                                  return Stack(
                                    alignment: Alignment.center,
                                    clipBehavior: Clip.none,
                                    children: [
                                      Hero(
                                        tag:
                                            'profile_image_${_displayUsername}',
                                        createRectTween: (begin, end) {
                                          // ✅ 직선 경로(나갈 때처럼 자연스럽게)
                                          return RectTween(
                                            begin: begin,
                                            end: end,
                                          );
                                        },
                                        child: Material(
                                          color: Colors.transparent,
                                          child: heroAvatar,
                                        ),
                                      ),
                                      // 탭/업로드 인디케이터는 Hero 바깥에서 처리(비행 중 변형 독립)
                                      if (!isUploading)
                                        Positioned.fill(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap:
                                                  _isOwnProfile
                                                      ? _changeProfileImage
                                                      : _viewOtherProfileImage,
                                            ),
                                          ),
                                        ),
                                      if (isUploading)
                                        Positioned.fill(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                          ),
                                        ),
                                      // 🎯 링크 아이콘 (프로필 원형의 우측 하단에 배치)
                                      if ((isOther &&
                                              other?.links != null &&
                                              other!.links!.isNotEmpty) ||
                                          (!isOther &&
                                              me?.links != null &&
                                              me!.links!.isNotEmpty))
                                        Positioned(
                                          right: 5,
                                          bottom: 5,
                                          child: GestureDetector(
                                            onTap: () {
                                              final links =
                                                  isOther
                                                      ? (other?.links ?? [])
                                                      : (me?.links ?? []);
                                              final linkTitles =
                                                  isOther
                                                      ? (other?.linkTitles)
                                                      : (me?.linkTitles);
                                              final linkThumbnails =
                                                  isOther
                                                      ? (other?.linkThumbnails)
                                                      : (me?.linkThumbnails);
                                              if (links.isNotEmpty) {
                                                LinkBottomSheet.show(
                                                  context,
                                                  links: links,
                                                  linkTitles: linkTitles,
                                                  linkThumbnails:
                                                      linkThumbnails,
                                                  otherUser: widget.otherUser,
                                                );
                                              }
                                            },
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              child: SvgPicture.asset(
                                                'assets/icons/link.svg',
                                                width: 24,
                                                height: 24,
                                                colorFilter: ColorFilter.mode(
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.surface,
                                                  BlendMode.srcIn,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
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
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 다른 사용자 프로필일 때만 친구 추가 버튼 표시
                              if (isOther) ...[_buildOtherProfileButton()],
                              if (_isOwnProfile) ...[_buildMyProfileButton()],
                            ],
                          ),
                        ),
                        // Feed 모드 전환 스위처 (카드뷰 / 이미지 전용)
                        _buildFeedModeSwitcher(),
                        // Feed 내부에 이미 Consumer가 있으므로 중복 제거
                        _feed.buildFeedContent(
                          scrollController: _scrollController,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ✅ 상태바 영역 배경색 (항상 최상단에 표시)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.of(context).padding.top,
                child: Container(
                  color: Theme.of(context).colorScheme.background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFeedModeSwitcher() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
        child: ValueListenableBuilder<FeedDisplayMode>(
          valueListenable: FeedDisplayModeManager(),
          builder: (context, displayMode, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _isOwnProfile
                    ? _buildCategoryButton(Icons.grid_view_rounded)
                    : SizedBox.shrink(),
                Spacer(),
                // 그리드 아이콘 → 이미지 전용 모드
                _buildModeButton(
                  FeedDisplayMode.imageOnly,
                  Icons.grid_view_rounded,
                  18,
                  EdgeInsets.all(2),
                ),
                SizedBox(width: 6),

                // 리스트 아이콘 → 카드(텍스트 포함) 모드
                _buildModeButton(
                  FeedDisplayMode.card,
                  Icons.view_list_rounded,
                  22,
                  EdgeInsets.zero,
                ),
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
          ),

          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
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
                              fontWeight: FontWeight.w500,
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
                              fontWeight: FontWeight.w500,
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

  Widget _buildModeButton(
    FeedDisplayMode mode,
    IconData icon,
    double size,
    EdgeInsets? padding,
  ) {
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Icon(
            icon,
            size: size,
            color:
                selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withOpacity(0.3),
          ),
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
              text: '내 친구',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => MyFriendsScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildGlassyButton(
              text: context.tr('share_profile'),
              onTap: () {
                final me = context.read<UserProvider>().currentUser;
                if (me == null) return;
                ShareProfileBottomSheet.show(
                  context,
                  username: me.username,
                  profileImageUrl: me.profileImageUrl,
                  bio: null,
                  friendCount: me.friendCount ?? 0,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 그룹 기능 제거로 인해 _navigateToManageGroup() 메서드 제거

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
                  // 🎯 단일 차단 해제도 배치 엔드포인트 사용
                  final message = await friendService.unblockUsersBatch([
                    widget.otherUser!.username,
                  ]);

                  // 상태 새로고침
                  await friendProvider.checkFriendStatus(
                    widget.otherUser!.username,
                  );

                  if (mounted) {
                    // ErrorHandler.showInfo로 차단 해제 메시지 표시
                    ErrorHandler.showInfo(context, message);
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
                  // 그룹 기능 제거로 인해 groupProvider 파라미터 제거
                  await friendProvider.deleteFriend(widget.otherUser!.username);
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
                // 🎯 친구인 경우 버튼과 공유 버튼을 나란히 표시
                final isFriend =
                    friendProvider.friendStatus == FriendRequestStatus.accepted;

                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: 4,
                    left: 12,
                    right: 12,
                    top: 20,
                  ),
                  child: Opacity(
                    opacity: opacity,
                    child:
                        isFriend
                            ? Row(
                              children: [
                                SizedBox(width: 10),
                                Expanded(
                                  child: _buildFilledButton(
                                    text: buttonText,
                                    onTap: buttonAction,
                                    isLoading: friendProvider.isLoadingStatus,
                                    isFilled: false,
                                    isBlocked: false,
                                  ),
                                ),
                                // 🎯 공유 버튼은 항상 표시
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: GestureDetector(
                                    onTap: () {
                                      if (widget.otherUser == null) return;
                                      ShareProfileBottomSheet.show(
                                        context,
                                        username: widget.otherUser!.username,
                                        profileImageUrl:
                                            widget.otherUser!.profileImageUrl,
                                        bio: null,
                                        friendCount:
                                            widget.otherUser!.friendCount ?? 0,
                                      );
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.1),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 2,
                                        ),
                                        child: Icon(
                                          Icons.ios_share,
                                          size: 18,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                            : Row(
                              children: [
                                Expanded(
                                  child: _buildFilledButton(
                                    text: buttonText,
                                    onTap: buttonAction,
                                    isLoading: friendProvider.isLoadingStatus,
                                    isFilled:
                                        friendProvider.friendStatus ==
                                        FriendRequestStatus.none,
                                    isBlocked:
                                        friendProvider.friendStatus ==
                                        FriendRequestStatus
                                            .blocked, // 🎯 차단된 경우 스타일 변경
                                  ),
                                ),
                                // 🎯 공유 버튼은 항상 표시
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: GestureDetector(
                                    onTap: () {
                                      if (widget.otherUser == null) return;
                                      ShareProfileBottomSheet.show(
                                        context,
                                        username: widget.otherUser!.username,
                                        profileImageUrl:
                                            widget.otherUser!.profileImageUrl,
                                        bio: null,
                                        friendCount:
                                            widget.otherUser!.friendCount ?? 0,
                                      );
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.06),
                                      ),
                                      child: Icon(
                                        Icons.ios_share,
                                        size: 20,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
        height: 50, // 고정 높이로 UI 흔들림 방지
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color:
              isBlocked
                  ? Colors.transparent
                  : isFilled
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(1)
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
                            ? Theme.of(context).colorScheme.surface
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                  : Text(
                    text,
                    style: TextStyle(
                      color:
                          isFilled
                              ? Theme.of(context).colorScheme.surface
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 14,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
        ),
      ),
    );
  }

  /// 프로필 사진 변경 화면 표시
  void _changeProfileImage() {
    if (_isUploadingProfileImage) return;

    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder:
            (context, animation, secondaryAnimation) => ProfileImageViewScreen(
              profileImageUrl: user.profileImageUrl,
              username: user.username,
              isOwnProfile: true,
              onShareProfile: () {
                ShareProfileBottomSheet.show(
                  context,
                  username: user.username,
                  profileImageUrl: user.profileImageUrl,
                  bio: null,
                  friendCount: user.friendCount ?? 0,
                );
              },
              onCopyProfileLink: () async {
                final profileUrl = 'https://doppy.world/@${user.username}';
                await Clipboard.setData(ClipboardData(text: profileUrl));

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context).translate('link_copied'),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              onGallerySelected: (file) {
                _handleImageSelected(file);
              },
              onSetDefaultImage: () {
                _clearProfileImage();
              },
              onFollowStatusChanged: null,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 나갈 때: 페이지 전환만 빠르게 (히어로 애니메이션은 자동으로 무시됨)
          // 들어올 때: 히어로 애니메이션과 함께 나타남
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// 타인 프로필 이미지 보기 (읽기 모드)
  void _viewOtherProfileImage() {
    if (widget.otherUser == null) return;

    final otherUser = widget.otherUser!;
    final userProvider = context.read<UserProvider>();
    final viewedUser = userProvider.viewedUser ?? otherUser;

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder:
            (context, animation, secondaryAnimation) => ProfileImageViewScreen(
              profileImageUrl: viewedUser.profileImageUrl,
              username: viewedUser.username,
              isOwnProfile: false, // 읽기 모드
              alias: viewedUser.alias,
              links: viewedUser.links,
              linkTitles: viewedUser.linkTitles,
              linkThumbnails: viewedUser.linkThumbnails,
              onShareProfile: () {
                ShareProfileBottomSheet.show(
                  context,
                  username: viewedUser.username,
                  profileImageUrl: viewedUser.profileImageUrl,
                  bio: null,
                  friendCount: viewedUser.friendCount ?? 0,
                );
              },
              onCopyProfileLink: () async {
                final profileUrl =
                    'https://doppy.world/@${viewedUser.username}';
                await Clipboard.setData(ClipboardData(text: profileUrl));

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context).translate('link_copied'),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              onGallerySelected: (_) {
                // 읽기 모드에서는 편집 불가
              },
              onSetDefaultImage: () {
                // 읽기 모드에서는 편집 불가
              },
              onFollowStatusChanged: () {
                // 팔로우 상태 변경 시 프로필 화면 새로고침
                if (mounted) {
                  setState(() {});
                }
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void showProfileInfoEditBottomSheet(User me) {
    // 컨트롤러에 현재 값 설정
    _nameController.text = me.alias ?? '';

    debugPrint('[UserProfile] Bottom sheet 열기 - 이름: "${_nameController.text}"');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return ProfileInfoEditBottomSheet(
          user: me,
          nameController: _nameController,
          onClearProfileImage: _clearProfileImage,
          onImagesSelected: (files) => _handleImageSelected(files.first),
          onSave: ({
            required String alias,
            List<String>? links, // 🎯 프로필 링크 목록
            Map<String, String>? linkTitles, // 🎯 링크 타이틀 (URL -> 타이틀)
            Map<String, String>?
            linkThumbnails, // 🎯 링크 썸네일 (URL -> thumbnailUrl)
          }) async {
            // UserProvider를 통해 API 호출 및 상태 업데이트
            final userProvider = context.read<UserProvider>();

            final success = await userProvider.updateProfileInfo(
              alias: alias,
              links: links,
              linkTitles: linkTitles,
              linkThumbnails: linkThumbnails,
            );

            if (mounted) {
              final l10n = AppLocalizations.of(context);
              if (success) {
                // 성공 메시지 표시
                ErrorHandler.showInfo(context, l10n.t('profile_updated'));
              } else {
                // 실패 메시지 표시
                ErrorHandler.showError(context, '프로필 저장에 실패했습니다');
              }
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

  /// 선택된 이미지 처리 (원형 크롭된 이미지 업로드)
  Future<void> _handleImageSelected(File file) async {
    try {
      setState(() {
        _isUploadingProfileImage = true;
      });

      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(file, kind: UploadKind.profile);
      _profileUploadTask = task;
      final finalTempFile = file; // 클로저에서 사용하기 위해
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
              debugPrint(
                '[UserProfileScreen] imageUrl is empty, calling fetchMyProfile',
              );
              await context.read<UserProvider>().fetchMyProfile();
            }
          } catch (e) {
            debugPrint(
              '[UserProfileScreen] Error in upload success handler: $e',
            );
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

          // 임시 파일 삭제
          try {
            if (await finalTempFile.exists()) {
              await finalTempFile.delete();
            }
          } catch (_) {}
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

          // 임시 파일 삭제
          try {
            if (await finalTempFile.exists()) {
              await finalTempFile.delete();
            }
          } catch (_) {}
        }
      };
      task.addListener(_profileTaskListener!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingProfileImage = false;
        });
        ErrorHandler.showError(context, '이미지 처리 중 오류가 발생했습니다: $e');
      }
      // 에러 발생 시 파일 삭제 (크롭된 파일은 ProfileImageViewScreen에서 생성됨)
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}
