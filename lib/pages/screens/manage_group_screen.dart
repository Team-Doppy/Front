import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/card_view_shimmer.dart';
import 'package:doppy/pages/components/group_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/card_view.dart';
import 'package:doppy/pages/components/add_member_bottom_sheet.dart'
    show AddMemberScreen;
import 'package:doppy/pages/components/group_post_readers_bottom_sheet.dart';
import 'package:doppy/pages/components/access_level_sheet.dart';
import 'package:doppy/pages/components/friends_grid.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../data/models/friend_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/post_data.dart';
import '../../../data/models/system_category_keys.dart';
import '../../../data/services/blog_service.dart';
import '../../../providers/group_provider.dart';
import '../../../providers/feed_provider/my_profile_feed_provider.dart';

// 그룹 관리 화면 메인 위젯
class ManageGroupScreen extends StatefulWidget {
  final Group? selectedGroup;
  final bool embedded;
  final String? filterText;

  const ManageGroupScreen({
    Key? key,
    this.selectedGroup,
    this.embedded = false,
    this.filterText,
  }) : super(key: key);

  @override
  State<ManageGroupScreen> createState() => _ManageGroupScreenState();

  /// 🎯 그룹 포스트 캐시 무효화 (외부에서 호출 가능)
  /// 새 포스트 발행 또는 공개범위 변경 시 호출
  static void invalidateGroupPostsCache(int groupId) {
    _ManageGroupScreenState.invalidateGroupPostsCacheInternal(groupId);
  }

  /// 🎯 여러 그룹의 포스트 캐시 일괄 무효화
  static void invalidateMultipleGroupsPostsCache(List<int> groupIds) {
    _ManageGroupScreenState.invalidateMultipleGroupsPostsCacheInternal(
      groupIds,
    );
  }

  /// 🎯 특정 그룹의 캐시 무효화 상태 확인
  static bool isGroupPostsCacheInvalidated(int groupId) {
    return _ManageGroupScreenState.isGroupPostsCacheInvalidatedInternal(
      groupId,
    );
  }

  /// 🎯 모든 그룹 포스트 캐시 무효화 플래그 제거
  static void clearInvalidationFlags() {
    _ManageGroupScreenState.clearInvalidationFlagsInternal();
  }
}

class _ManageGroupScreenState extends State<ManageGroupScreen>
    with TickerProviderStateMixin {
  // 🎯 앱바 확장 높이 상수
  static const double _appBarExpandedHeight = 270.0;

  // 🎯 새로고침 관련 상수
  static const double _refreshStart = 30.0; // 스피너 표시 시작 역치
  static const double _refreshTrigger = 80.0; // 리프레시 수행 역치

  late final AnimationController _selectionAnimationController;
  late final AnimationController _loadingAnimationController;
  final GroupDropDown _groupDropDown = GroupDropDown();

  // 선택된 그룹 상태
  Group? _selectedGroup;

  // 검색 관련 상태
  final TextEditingController _appbarSearchController = TextEditingController();
  String _searchQuery = '';
  bool _isAppbarSearchExpanded = false;
  final FocusNode _appbarSearchFocusNode = FocusNode();

  // 다중 선택 모드
  bool _isMultiSelectMode = false;
  final Set<String> _selectedMembers = {};
  final Set<String> _selectedPosts = {};

  // 포스트/멤버 뷰 전환
  int _currentViewIndex = 0; // 0: 멤버, 1: 포스트

  // 🎯 앱바 expandedHeight 애니메이션 컨트롤러
  late final AnimationController _appBarHeightAnimationController;
  late final Animation<double> _appBarHeightAnimation;

  // 🎯 SliverAppBar의 접힘 상태 추적
  bool _isAppBarCollapsed = false;

  // 🎯 그룹 포스트 관련 상태 (static으로 유지하여 화면 전환 시에도 캐시 보존)
  static final Map<int, List<PostData>> _groupPostsCache = {};
  static final Map<int, bool> _isLoadingGroupPosts = {};
  static final Map<int, int> _groupPostsPage = {};
  static final Map<int, bool> _hasMoreGroupPosts = {};
  // 🎯 포스트 로딩 시작 시간 (최소 shimmer 표시 시간 보장용)
  static final Map<int, DateTime?> _postsLoadingStartTime = {};

  // 🎯 그룹 포스트 캐시 무효화 플래그 (동기화용)
  static final Set<int> _invalidatedGroupIds = {};

  // 🎯 앱바 드래그 새로고침 관련 상태
  double _pullOffset = 0.0; // 드래그 오프셋 (음수 = 아래로 당김)
  bool _isRefreshing = false; // 새로고침 중 여부
  late final AnimationController _refreshAnimationController;
  late final Animation<double> _refreshRotationAnimation;

  // 🎯 초기 로딩 상태 (화면 진입 시 로딩 로고 표시용)
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();

    // 선택 애니메이션 컨트롤러 초기화
    _selectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 로딩 애니메이션 컨트롤러 초기화
    _loadingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // 앱바 높이 애니메이션 컨트롤러 초기화 (성능 최적화: vsync 사용)
    _appBarHeightAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250), // 🎯 성능 최적화: 300ms → 250ms
      vsync: this,
    );
    _appBarHeightAnimation = Tween<double>(
      begin: _appBarExpandedHeight,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _appBarHeightAnimationController,
        curve: Curves.easeInOutCubic, // 🎯 더 부드러운 커브
      ),
    );

    // 🎯 새로고침 스피너 애니메이션 컨트롤러
    _refreshAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _refreshRotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _refreshAnimationController,
        curve: Curves.linear,
      ),
    );

    // 앱바 검색 포커스 리스너
    _appbarSearchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isAppbarSearchExpanded = _appbarSearchFocusNode.hasFocus;
      });
      // 🎯 포커스를 받았을 때 앱바가 펼쳐져 있으면만 자동으로 접기
      if (_isAppbarSearchExpanded) {
        // 현재 앱바가 펼쳐져 있는지 확인 (0.5 이상이면 펼쳐져 있음)
        if (_appBarHeightAnimation.value > _appBarExpandedHeight * 0.5) {
          _appBarHeightAnimationController.value = 1.0; // 즉시 0.0 (end)로 설정
        }
      }
      // 🎯 포커스 해제 시: expandedHeight는 원래 값으로 유지하되,
      // 컨트롤러 값은 현재 상태 유지 (자동으로 펼쳐지지 않음)
      // 사용자가 스크롤로 자연스럽게 접었다 펼칠 수 있음
    });

    // 전달받은 그룹으로 초기화
    if (widget.selectedGroup != null) {
      _selectedGroup = widget.selectedGroup;
    }

    // 🎯 첫 빌드 후 초기 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final groupProv = context.read<GroupProvider>();
      final friendProv = context.read<FriendProvider>();

      // 🎯 그룹 목록 및 전체 친구 그룹 정보 로드 (서버 스키마 기반)
      await groupProv.fetchMyGroups(friendProvider: friendProv);

      // 🎯 서버에서 받은 최신 그룹 정보로 업데이트
      if (mounted) {
        final updatedGroups = groupProv.myGroups;
        if (_selectedGroup != null) {
          final isSystemGroup = _selectedGroup!.isSystem == true;
          final updatedGroup =
              isSystemGroup
                  ? updatedGroups.firstWhere(
                    (g) => g.isSystem == true,
                    orElse: () => _selectedGroup!,
                  )
                  : updatedGroups.firstWhere(
                    (g) => g.id == _selectedGroup!.id,
                    orElse: () => _selectedGroup!,
                  );

          setState(() {
            _selectedGroup = updatedGroup;
          });
        }
      }

      // 🎯 처음 들어올 때는 항상 멤버 탭이므로 멤버만 로드
      // 🎯 시스템 그룹 체크는 isSystem만 사용
      final isSystemGroup =
          _selectedGroup != null && _selectedGroup!.isSystem == true;
      if (_selectedGroup == null || isSystemGroup) {
        // allFriends 그룹: 친구 데이터만 추가로 로드 (그룹 정보는 이미 위에서 로드됨)
        if (!friendProv.isLoading && friendProv.acceptedFriends.isEmpty) {
          // 🎯 초기 로딩 완료 전에 친구 데이터 로드
          await friendProv.fetchAllFriendData();
        }
        // 🎯 전체 친구 그룹 멤버 수 동기화 (누락된 친구가 포함된 커스텀 그룹 동기화 포함)
        groupProv.syncAllFriendsMemberCount(
          friendProv.acceptedFriends.length,
          friendProvider: friendProv,
        );
      } else {
        // 일반 그룹: 캐시 확인 후 멤버 목록 로드
        if (!groupProv.isMembersCached(_selectedGroup!.id) &&
            !groupProv.isLoadingMembers(_selectedGroup!.id)) {
          await groupProv.fetchGroupMembers(_selectedGroup!.id);
        }
      }

      // 🎯 전체 친구 그룹에 처음 들어갔을 때 포스트도 자동 로드
      if (isSystemGroup) {
        final groupId = -1;
        final posts = _groupPostsCache[groupId] ?? [];
        final isLoading = _isLoadingGroupPosts[groupId] ?? false;
        final hasMore = _hasMoreGroupPosts[groupId] ?? true;

        // 🎯 캐시가 무효화되었거나 비어있으면 자동 로드
        final isInvalidated = _invalidatedGroupIds.contains(groupId);
        if ((isInvalidated || posts.isEmpty) && !isLoading && hasMore) {
          // 포스트 탭으로 자동 전환하지 않고 백그라운드에서 로드
          if (isInvalidated) {
            // 무효화된 경우 새로고침으로 처음부터 다시 로드
            _refreshPosts();
          } else {
            _loadAllFriendsPosts();
          }
        }
      }

      // 🎯 초기 로딩 완료 - 부드럽게 화면 전환
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _loadingAnimationController.stop();
    _loadingAnimationController.dispose();
    _selectionAnimationController.dispose();
    _appBarHeightAnimationController.dispose();
    _refreshAnimationController.dispose();
    _appbarSearchController.dispose();
    _appbarSearchFocusNode.dispose();
    _groupDropDown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProv, child) {
        return Consumer<FriendProvider>(
          builder: (context, friendProv, child) {
            // 🎯 초기 로딩 중일 때는 로딩 로고만 표시
            if (_isInitialLoading) {
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.background,
                body: const Center(child: DoppyLoadingLogo()),
              );
            }

            // 🎯 로딩 완료 후 부드럽게 실제 콘텐츠 표시
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: KeyedSubtree(
                key: const ValueKey('manage_group_content'),
                child: _buildScaffold(groupProv, friendProv),
              ),
            );
          },
        );
      },
    );
  }

  // 🎯 NestedScrollView 기반 안정형 구조
  Widget _buildScaffold(GroupProvider groupProv, FriendProvider friendProv) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 🎯 NestedScrollView: Slack/Instagram 스타일 안정형 구조
          if (!widget.embedded)
            NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                // 🎯 SliverAppBar의 접힘 상태 업데이트
                if (_isAppBarCollapsed != innerBoxIsScrolled) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _isAppBarCollapsed = innerBoxIsScrolled;
                      });
                    }
                  });
                }

                return [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                    sliver: AnimatedBuilder(
                      animation: _appBarHeightAnimation,
                      builder: (context, child) {
                        return SliverAppBar(
                          pinned: true,
                          expandedHeight:
                              _isAppbarSearchExpanded
                                  ? 0.0
                                  : _appBarExpandedHeight,
                          toolbarHeight:
                              MediaQuery.of(context).padding.top + 55,
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          automaticallyImplyLeading: false,
                          flexibleSpace: FlexibleSpaceBar(
                            collapseMode: CollapseMode.pin,
                            background: AnimatedBuilder(
                              animation: Listenable.merge([
                                _appBarHeightAnimationController,
                                _refreshAnimationController,
                              ]),
                              builder: (context, child) {
                                // 두 투명도 중 더 작은 값 사용
                                final finalOpacity =
                                    (1.0 -
                                        (_pullOffset / _refreshTrigger).clamp(
                                          0.0,
                                          1.0,
                                        ));
                                return RepaintBoundary(
                                  child: Opacity(
                                    opacity: finalOpacity,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                      ),
                                      child: _buildAppBarContent(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          bottom: PreferredSize(
                            preferredSize: const Size.fromHeight(0),
                            child: Container(
                              color: Theme.of(context).colorScheme.surface,
                              child: Stack(
                                children: [
                                  // 🎯 기존 레이아웃 (레이아웃 유지)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedOpacity(
                                        opacity:
                                            (1.0 -
                                                (_pullOffset / _refreshTrigger)
                                                    .clamp(0.0, 1.0)),
                                        duration: const Duration(
                                          milliseconds: 50, // 더 빠른 애니메이션
                                        ),
                                        child: AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          curve: Curves.easeInOut,
                                          child: Row(
                                            children: [
                                              const SizedBox(width: 22),
                                              if (!_isAppbarSearchExpanded) ...[
                                                _buildViewToggle(),
                                                const Spacer(),
                                              ],
                                              if (_isAppbarSearchExpanded)
                                                Expanded(
                                                  child:
                                                      _buildExpandedSearchField(),
                                                )
                                              else
                                                _buildCollapsedSearchField(),
                                              _buildMultiSelectButton(),
                                              const SizedBox(width: 10),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 10),
                                    ],
                                  ),
                                  // 🎯 스피너 (상단에 고정) - _refreshStart 이상일 때만 표시
                                  if (_pullOffset > _refreshStart ||
                                      _isRefreshing)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 60,
                                        alignment: Alignment.center,
                                        child: AnimatedBuilder(
                                          animation: _refreshRotationAnimation,
                                          builder: (context, child) {
                                            // 🎯 당김 진행률에 따라 스피너 하나씩 채워지기
                                            // _refreshStart부터 _refreshTrigger까지 진행률 계산
                                            final pullProgress = ((_pullOffset -
                                                        _refreshStart) /
                                                    (_refreshTrigger -
                                                        _refreshStart))
                                                .clamp(0.0, 1.0);
                                            return CustomSpinner(
                                              progress:
                                                  _isRefreshing
                                                      ? 1.0
                                                      : pullProgress,
                                              isAnimating: _isRefreshing,
                                              rotation:
                                                  _refreshRotationAnimation
                                                      .value,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ];
              },
              body: SafeArea(
                top: false,
                child: Builder(
                  builder: (context) {
                    return NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (_handlePullToRefresh(notification, context)) {
                          return true;
                        }
                        // 🎯 검색 중에도 스크롤로 앱바를 접었다 펼칠 수 있게 함
                        if (_isAppbarSearchExpanded || _searchQuery.isEmpty) {
                          _handleScrollForAppBar(notification);
                        }
                        return false;
                      },
                      child: CustomScrollView(
                        slivers: [
                          SliverOverlapInjector(
                            handle:
                                NestedScrollView.sliverOverlapAbsorberHandleFor(
                                  context,
                                ),
                          ),
                          ..._buildBodySlivers(groupProv, friendProv),
                          if (_isMultiSelectMode)
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height:
                                    MediaQuery.of(context).padding.bottom + 80,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            )
          else
            // embedded 모드는 기존 구조 유지
            CustomScrollView(slivers: _buildBodySlivers(groupProv, friendProv)),
          // 뒤로가기 버튼과 그룹 이름 (접혔을 때만 표시)
          if (!widget.embedded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 9,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 24,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  AnimatedOpacity(
                    opacity:
                        (_isAppBarCollapsed || _isAppbarSearchExpanded)
                            ? 1.0
                            : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      // 🎯 시스템 그룹(isSystem == true)인 경우 "모든 친구"로 표시
                      (_selectedGroup?.isSystem == true)
                          ? context.tr('all_friends')
                          : (_selectedGroup?.name ?? ''),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 멤버 추가 버튼
          if (!widget.embedded &&
              !_isMultiSelectMode &&
              _selectedGroup != null &&
              _selectedGroup!.id != -1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 13,
              right: 60,
              child: GestureDetector(
                onTap: _showAddMemberBottomSheet,
                child: Icon(
                  Icons.add,
                  size: 30,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.9),
                ),
              ),
            ),
          // 편집 버튼
          if (!widget.embedded && !_isMultiSelectMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 20,
              child: GestureDetector(
                onTap: _showEditGroupSheet,
                child: SvgPicture.asset(
                  'assets/icons/pen.svg',
                  width: 23,
                  height: 23,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          // 다중 선택 모드 하단 액션바
          if (_isMultiSelectMode && _currentViewIndex == 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildMultiSelectActionBar(),
            ),
          if (_isMultiSelectMode && _currentViewIndex == 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildPostMultiSelectActionBar(),
            ),
        ],
      ),
    );
  }

  // 🎯 앱바 콘텐츠 (그룹 이미지 및 설명)
  Widget _buildAppBarContent() {
    final group = _selectedGroup;
    if (group == null) {
      return SizedBox(height: 100);
    }

    // 🎯 검색 중일 때는 숨김
    if (_isAppbarSearchExpanded) {
      return SizedBox.shrink();
    }

    // 🎯 서버에서 받은 데이터 직접 사용
    final displayImageUrl = group.profileImageUrl;
    final displayDescription = group.description;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 50),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Hero(
              tag: 'group-${group.id}',
              child: RepaintBoundary(
                child: GestureDetector(
                  // 🎯 이미지 탭 시 편집 화면으로 이동
                  onTap: () {
                    if (!widget.embedded && !_isMultiSelectMode) {
                      _showEditGroupSheet();
                    }
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(shape: BoxShape.circle),
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.02),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child:
                                displayImageUrl != null &&
                                        displayImageUrl.isNotEmpty &&
                                        (displayImageUrl.startsWith(
                                              'http://',
                                            ) ||
                                            displayImageUrl.startsWith(
                                              'https://',
                                            ))
                                    ? CachedNetworkImage(
                                      key: ValueKey(
                                        'group-appbar-image-${group.id}',
                                      ),
                                      imageUrl: displayImageUrl,
                                      fit: BoxFit.cover,
                                      width: 90,
                                      height: 90,
                                      fadeInDuration: const Duration(
                                        milliseconds: 0,
                                      ), // 🎯 즉시 표시 (캐시된 이미지)
                                      fadeOutDuration: const Duration(
                                        milliseconds: 0,
                                      ), // 🎯 즉시 사라짐
                                      memCacheWidth: 180, // 🎯 메모리 캐시 크기 지정
                                      maxWidthDiskCache: 180, // 🎯 디스크 캐시 크기 지정
                                      placeholder:
                                          (context, url) => Container(
                                            width: 100,
                                            height: 100,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                            child: Center(),
                                          ),
                                      errorWidget: (context, url, error) {
                                        return _buildGroupAvatarPlaceholder(
                                          group,
                                        );
                                      },
                                    )
                                    : _buildGroupAvatarPlaceholder(group),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // 🎯 시스템 그룹(isSystem == true)인 경우 "모든 친구"로 표시
                    (group.isSystem == true)
                        ? context.tr('all_friends')
                        : group.name,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.2,
                      height: 1.3,
                    ),
                  ),

                  // 🎯 첫 번째 줄: 디스크립션 (있다면)
                  SizedBox(height: 8),
                  if (displayDescription.isNotEmpty) ...[
                    RepaintBoundary(
                      child: Text(
                        displayDescription,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          letterSpacing: -0.2,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],

                  // 🎯 두 번째 줄: 멤버 수 · 포스트 수 (프로필 화면 스타일)
                  RepaintBoundary(
                    child: Padding(
                      padding: EdgeInsets.only(top: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // 멤버 수
                          _buildStatItem(
                            context,
                            count: group.memberCount ?? 0,
                            label: context.tr('members'),
                          ),

                          // 포스트 수
                          _buildStatItem(
                            context,
                            count: group.postCount ?? 0,
                            label: context.tr('post'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 스크롤로 앱바 접었다 펼치기 핸들러 (검색 종료 후)
  void _handleScrollForAppBar(ScrollNotification notification) {
    final metrics = notification.metrics;

    // 🎯 맨 위에서 스크롤 방향 감지
    if (metrics.pixels <= 0 && notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;

      // 위로 스크롤 (아래로 당김): 앱바 펼치기
      if (delta < 0 && _appBarHeightAnimationController.value > 0.0) {
        final newValue = (_appBarHeightAnimationController.value -
                (-delta / _appBarExpandedHeight * 0.5))
            .clamp(0.0, 1.0);
        _appBarHeightAnimationController.value = newValue;
      }
      // 아래로 스크롤 (위로 올림): 앱바 접기
      else if (delta > 0 && _appBarHeightAnimationController.value < 1.0) {
        final newValue = (_appBarHeightAnimationController.value +
                (delta / _appBarExpandedHeight * 0.5))
            .clamp(0.0, 1.0);
        _appBarHeightAnimationController.value = newValue;
      }
    }
  }

  // 🎯 앱바 드래그 새로고침 핸들러
  bool _handlePullToRefresh(
    ScrollNotification notification,
    BuildContext context,
  ) {
    // 🎯 검색 중에는 새로고침 불가
    if (_isAppbarSearchExpanded || _searchQuery.isNotEmpty) {
      return false;
    }

    final metrics = notification.metrics;

    // 🎯 맨 위에서 아래로 당길 때만 처리
    if (metrics.pixels <= 0) {
      if (notification is ScrollUpdateNotification) {
        final delta = notification.scrollDelta ?? 0.0;
        if (delta < 0) {
          // 아래로 당김
          setState(() {
            _pullOffset = (_pullOffset + (-delta) * 0.5).clamp(
              0.0,
              _refreshTrigger,
            );
          });

          // 🎯 _refreshTrigger 이상 당기면 새로고침 시작
          if (_pullOffset >= _refreshTrigger && !_isRefreshing) {
            _startRefresh(context);
          }
        } else if (delta > 0 && _pullOffset > 0) {
          // 위로 올림 (당김 해제)
          setState(() {
            _pullOffset = (_pullOffset - delta * 0.8).clamp(
              0.0,
              _refreshTrigger,
            );
          });
        }
      } else if (notification is ScrollEndNotification) {
        // 손을 놓았을 때
        // 🎯 _refreshTrigger 이상 당겼을 때만 새로고침 시작
        if (_pullOffset >= _refreshTrigger && !_isRefreshing) {
          _startRefresh(context);
        } else if (_pullOffset > 0) {
          // 새로고침 안 되면 원래대로
          setState(() {
            _pullOffset = 0.0;
          });
        }
      }
    }

    return false;
  }

  // 🎯 새로고침 시작
  Future<void> _startRefresh(BuildContext context) async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _refreshAnimationController.repeat();
    });

    try {
      final groupProv = Provider.of<GroupProvider>(context, listen: false);
      final friendProv = Provider.of<FriendProvider>(context, listen: false);

      // 🎯 현재 탭에 따라 해당 데이터만 새로고침
      if (_currentViewIndex == 0) {
        // 멤버 탭: 멤버 새로고침
        await _refreshMembers(groupProv, friendProv);
      } else {
        // 포스트 탭: 포스트 새로고침
        await _refreshPosts();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _pullOffset = 0.0;
          _refreshAnimationController.stop();
          _refreshAnimationController.reset();
        });
      }
    }
  }

  // 🎯 Body 위젯 (Sliver 리스트 반환)
  List<Widget> _buildBodySlivers(
    GroupProvider groupProv,
    FriendProvider friendProv,
  ) {
    List<Group> groups = groupProv.myGroups;
    final previousGroup = _selectedGroup;

    if (_selectedGroup == null) {
      _selectedGroup = groups.firstOrNull;
    } else {
      // 🎯 시스템 그룹 체크는 isSystem만 사용
      final isSystemGroup = _selectedGroup!.isSystem == true;
      final updatedGroup =
          isSystemGroup
              ? groups.firstWhere(
                (g) => g.isSystem == true,
                orElse: () => _selectedGroup!,
              )
              : groups.firstWhere(
                (g) => g.id == _selectedGroup!.id,
                orElse: () => _selectedGroup!,
              );

      // 🎯 그룹 정보 변경 감지 및 업데이트
      if (updatedGroup.name != _selectedGroup!.name ||
          updatedGroup.description != _selectedGroup!.description ||
          updatedGroup.profileImageUrl != _selectedGroup!.profileImageUrl ||
          updatedGroup.memberCount != _selectedGroup!.memberCount ||
          updatedGroup.postCount != _selectedGroup!.postCount) {
        _selectedGroup = updatedGroup;
      }
    }

    // 🎯 그룹 변경 감지 (시스템 그룹은 isSystem으로 비교)
    final previousIsSystem = previousGroup?.isSystem == true;
    final currentIsSystem = _selectedGroup?.isSystem == true;
    final isGroupChanged =
        previousIsSystem != currentIsSystem ||
        (previousIsSystem == false &&
            previousGroup?.id != _selectedGroup?.id) ||
        (previousGroup == null && _selectedGroup != null) ||
        (previousGroup != null && _selectedGroup == null);

    if (isGroupChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _onGroupChanged(previousGroup, _selectedGroup, groupProv, friendProv);
      });
    }

    // 🎯 스마트 감지기: 포스트가 추가된 그룹 자동 새로고침
    if (_selectedGroup != null && _currentViewIndex == 1) {
      final isAllFriendsGroup = _selectedGroup!.isSystem == true;
      final groupId = isAllFriendsGroup ? -1 : _selectedGroup!.id;

      // 🎯 현재 그룹이 최근 업데이트된 그룹 목록에 있는지 확인
      if (groupProv.checkAndClearGroupUpdate(groupId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // 포스트 탭이 활성화되어 있고, 해당 그룹의 포스트가 있으면 새로고침
          _refreshPosts();
        });
      }
    }

    // 🎯 검색은 멤버/포스트 검색이므로 그룹 필터링 제거
    // 현재 선택된 그룹에서만 멤버/포스트를 검색함
    return _buildFriendsListSlivers(friendProv, groupProv, groups);
  }

  // 🎯 그룹 변경 시 데이터 로딩
  void _onGroupChanged(
    Group? previousGroup,
    Group? newGroup,
    GroupProvider groupProv,
    FriendProvider friendProv,
  ) {
    if (newGroup == null) return;

    if (_currentViewIndex == 0) {
      // 🎯 시스템 그룹 체크는 isSystem만 사용
      if (newGroup.isSystem == true) {
        if (!friendProv.isLoading && friendProv.acceptedFriends.isEmpty) {
          friendProv.fetchAllFriendData();
        }
      } else {
        if (!groupProv.isMembersCached(newGroup.id) &&
            !groupProv.isLoadingMembers(newGroup.id)) {
          groupProv.fetchGroupMembers(newGroup.id);
        }
      }
    }

    if (_currentViewIndex == 1) {
      final isAllFriendsGroup = newGroup.isSystem == true;

      if (!isAllFriendsGroup && newGroup.id != -1) {
        final groupId = newGroup.id;
        final posts = _groupPostsCache[groupId] ?? [];
        final isLoading = _isLoadingGroupPosts[groupId] ?? false;
        final hasMore = _hasMoreGroupPosts[groupId] ?? true;
        final isInvalidated = _invalidatedGroupIds.contains(groupId);

        // 🎯 캐시가 무효화되었거나 비어있으면 로드
        if ((isInvalidated || posts.isEmpty) && !isLoading && hasMore) {
          if (isInvalidated) {
            // 무효화된 경우 새로고침으로 처음부터 다시 로드
            _refreshPosts();
          } else {
            _loadGroupPosts(groupId);
          }
        }
      } else if (isAllFriendsGroup) {
        final groupId = -1;
        final posts = _groupPostsCache[groupId] ?? [];
        final isLoading = _isLoadingGroupPosts[groupId] ?? false;
        final hasMore = _hasMoreGroupPosts[groupId] ?? true;
        final isInvalidated = _invalidatedGroupIds.contains(groupId);

        // 🎯 캐시가 무효화되었거나 비어있으면 로드
        if ((isInvalidated || posts.isEmpty) && !isLoading && hasMore) {
          if (isInvalidated) {
            // 무효화된 경우 새로고침으로 처음부터 다시 로드
            _refreshPosts();
          } else {
            _loadAllFriendsPosts();
          }
        }
      }
    }
  }

  // 🎯 그룹 아바타 플레이스홀더
  /// 🎯 통계 아이템 빌드 (프로필 화면 스타일)
  Widget _buildStatItem(
    BuildContext context, {
    required int count,
    required String label,
  }) {
    return IntrinsicWidth(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: -0.2,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: -0.2,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupAvatarPlaceholder(Group group) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GroupColorPalette.getColor(group.id).withOpacity(0.55),
            GroupColorPalette.getColor(group.id),
            GroupColorPalette.getColor(group.id).withOpacity(0.95),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.4, -0.4),
            radius: 1.0,
            colors: [Colors.white.withOpacity(0.12), Colors.transparent],
          ),
        ),
        child: Center(
          child: ClipOval(
            child: Image.asset(
              'assets/images/doppy_nobg.png',
              width: 25,
              height: 25,
              color: Colors.white,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  // 🎯 접혀있는 검색 필드
  Widget _buildCollapsedSearchField() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isAppbarSearchExpanded = true;
        });
        // 🎯 올라갈 때 애니메이션 제거: 즉시 사라짐
        _appBarHeightAnimationController.value = 1.0;
        // 포커스 요청
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _appbarSearchFocusNode.requestFocus();
          }
        });
      },
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(right: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.search,
          size: 20,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
        ),
      ),
    );
  }

  // 🎯 펼쳐진 검색 필드
  Widget _buildExpandedSearchField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: 40,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _appbarSearchController,
        focusNode: _appbarSearchFocusNode,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
          height: 1.0,
        ),
        cursorColor: Theme.of(context).colorScheme.onSurface,
        textAlignVertical: TextAlignVertical.center,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        onSubmitted: (value) {
          _appbarSearchController.clear();
          _appbarSearchFocusNode.unfocus();
          // 🎯 검색 완료 시: expandedHeight는 원래대로, 애니메이션 컨트롤러는 펼쳐진 상태(0.0)로 초기화
          setState(() {
            _searchQuery = '';
            _isAppbarSearchExpanded = false;
          });
          // 🎯 검색 완료 후 앱바를 펼쳐진 상태로 초기화 (사용자가 스크롤로 접었다 펼칠 수 있음)
          _appBarHeightAnimationController.value = 0.0;
        },
        decoration: InputDecoration(
          hintText:
              _currentViewIndex == 0
                  ? context.tr('search_members')
                  : context.tr('search_posts'),
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            fontSize: 14,
            height: 1.0,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            onPressed: () {
              _appbarSearchController.clear();
              _appbarSearchFocusNode.unfocus();
              // 🎯 검색 완료 시: expandedHeight는 원래대로, 애니메이션 컨트롤러는 펼쳐진 상태(0.0)로 초기화
              setState(() {
                _searchQuery = '';
                _isAppbarSearchExpanded = false;
              });
              // 🎯 검색 완료 후 앱바를 펼쳐진 상태로 초기화 (사용자가 스크롤로 접었다 펼칠 수 있음)
              _appBarHeightAnimationController.value = 0.0;
            },
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 0,
          ),
        ),
      ),
    );
  }

  // 🎯 뷰 전환 토글 UI
  Widget _buildViewToggle() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            index: 0,
            label: '  ${context.tr('members')}  ',
            icon: Icons.people_outline,
          ),
          _buildToggleButton(
            index: 1,
            label: context.tr('post'),
            icon: Icons.grid_view_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _currentViewIndex == index;
    return GestureDetector(
      onTap: () {
        _onViewIndexChanged(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.onSurface : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color:
                    isSelected
                        ? Theme.of(context).colorScheme.background
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 뷰 전환 시 데이터 로딩
  void _onViewIndexChanged(int newIndex) {
    final group = _selectedGroup;
    final groupProv = context.read<GroupProvider>();
    final friendProv = context.read<FriendProvider>();

    if (newIndex == 1 && _currentViewIndex == 0) {
      // 포스트 탭으로 전환
      if (group != null) {
        final isAllFriendsGroup = group.isSystem == true;
        final groupId = isAllFriendsGroup ? -1 : group.id;
        final posts = _groupPostsCache[groupId] ?? [];
        final isLoading = _isLoadingGroupPosts[groupId] ?? false;
        final isInvalidated = _invalidatedGroupIds.contains(groupId);

        // 🎯 캐시가 무효화되었거나 비어있으면 로드
        if ((isInvalidated || posts.isEmpty) && !isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedGroup?.id == group.id) {
              if (isInvalidated) {
                // 무효화된 경우 새로고침으로 처음부터 다시 로드
                _refreshPosts();
              } else if (isAllFriendsGroup) {
                _loadAllFriendsPosts();
              } else if (groupId != -1) {
                _loadGroupPosts(groupId);
              }
            }
          });
        }
      }
    } else if (newIndex == 0 && _currentViewIndex == 1) {
      if (group != null) {
        // 🎯 시스템 그룹 체크는 isSystem만 사용
        if (group.isSystem == true) {
          if (!friendProv.isLoading && friendProv.acceptedFriends.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                friendProv.fetchAllFriendData();
              }
            });
          }
        } else {
          if (!groupProv.isMembersCached(group.id) &&
              !groupProv.isLoadingMembers(group.id)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedGroup?.id == group.id) {
                groupProv.fetchGroupMembers(group.id);
              }
            });
          }
        }
      }
    }

    setState(() {
      _currentViewIndex = newIndex;
    });
  }

  // 🎯 다중 선택 버튼
  Widget _buildMultiSelectButton() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color:
            _isMultiSelectMode
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          setState(() {
            _isMultiSelectMode = !_isMultiSelectMode;
            if (!_isMultiSelectMode) {
              _selectedMembers.clear();
              _selectedPosts.clear();
            }
          });
        },
        icon: Icon(
          Icons.check,
          size: 20,
          color:
              _isMultiSelectMode
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  // 🎯 친구 목록 위젯 (Sliver 리스트 반환)
  List<Widget> _buildFriendsListSlivers(
    FriendProvider friendProv,
    GroupProvider groupProv,
    List<Group> groups, // 🎯 filteredGroups 파라미터명 변경 (실제로는 필터링하지 않음)
  ) {
    if (_selectedGroup == null) {
      return [];
    }

    // 🎯 검색은 멤버/포스트 검색이므로 그룹 필터링 제거
    // 현재 선택된 그룹에서만 멤버/포스트를 검색함
    if (_currentViewIndex == 0) {
      // 🎯 멤버 탭: 현재 선택된 그룹의 멤버만 검색 및 표시
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 100),
          sliver: _buildFriendsSliverGrid(
            friendProv,
            groupProv,
            _selectedGroup!,
          ),
        ),
      ];
    } else {
      // 🎯 포스트 탭: 현재 선택된 그룹의 포스트만 검색 및 표시
      return _buildPostsViewSlivers(_selectedGroup!);
    }
  }

  // 🎯 포스트 뷰 빌드
  List<Widget> _buildPostsViewSlivers(Group selectedGroup) {
    final isAllFriendsGroup = selectedGroup.isSystem == true;
    final groupId = isAllFriendsGroup ? -1 : selectedGroup.id;
    final allPosts = _groupPostsCache[groupId] ?? [];

    // 🎯 검색 쿼리가 있으면 포스트 필터링
    final posts =
        _searchQuery.isNotEmpty
            ? allPosts.where((post) {
              final query = _searchQuery.toLowerCase();
              return post.title.toLowerCase().contains(query) ||
                  post.summary.toLowerCase().contains(query) ||
                  post.author.toLowerCase().contains(query);
            }).toList()
            : allPosts;

    final isLoading = _isLoadingGroupPosts[groupId] ?? false;
    final hasMore = _hasMoreGroupPosts[groupId] ?? true;

    // 🎯 최소 shimmer 표시 시간 보장 (0.5초)
    final loadingStartTime = _postsLoadingStartTime[groupId];
    final shouldShowShimmer =
        isLoading ||
        (loadingStartTime != null &&
            DateTime.now().difference(loadingStartTime).inMilliseconds < 500);

    // 🎯 로딩 중이거나 새로고침 중일 때 Shimmer 표시
    if ((shouldShowShimmer || _isRefreshing) && _currentViewIndex == 1) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12.0, 24.0, 12.0, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: CardViewShimmer(),
              );
            }, childCount: 5),
          ),
        ),
      ];
    }

    // 🎯 빈 상태: SliverToBoxAdapter + 고정 height (선택 모드일 때는 숨김)
    if (posts.isEmpty && !_isMultiSelectMode) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.45 + 46,
            child: Center(
              child: Text(
                _searchQuery.isNotEmpty
                    ? context.tr('no_matching_posts')
                    : context.tr('no_posts_in_group'),
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ];
    }

    // 🎯 포스트가 있을 때: SliverList
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12.0, 24.0, 12.0, 30),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index.isOdd) {
              return const SizedBox(height: 12.0);
            }
            final postIndex = index ~/ 2;
            if (postIndex >= posts.length) return null;

            final post = posts[postIndex];
            final isSelected = _selectedPosts.contains(post.id);

            // 🎯 더 일찍 로드 모어 트리거 (마지막 5개 남았을 때)
            if (postIndex == posts.length - 5 && hasMore && !isLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedGroup?.id == selectedGroup.id) {
                  if (isAllFriendsGroup) {
                    _loadAllFriendsPosts();
                  } else if (groupId != -1) {
                    _loadGroupPosts(groupId);
                  }
                }
              });
            }

            return _isMultiSelectMode
                ? Row(
                  children: [
                    // 🎯 선택 UI (왼쪽)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedPosts.remove(post.id);
                          } else {
                            _selectedPosts.add(post.id);
                          }
                        });
                      },
                      child: Container(
                        width: 35,
                        alignment: Alignment.center,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isSelected
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2,
                            ),
                          ),
                          child:
                              isSelected
                                  ? Icon(
                                    Icons.check,
                                    size: 22,
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                  )
                                  : null,
                        ),
                      ),
                    ),
                    // 🎯 카드뷰 (선택 모드 시 길이 조정)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedPosts.remove(post.id);
                            } else {
                              _selectedPosts.add(post.id);
                            }
                          });
                        },
                        child: CardView(
                          post: post,
                          isLast: postIndex == posts.length - 1,
                          isFirst: postIndex == 0,
                        ),
                      ),
                    ),
                  ],
                )
                : GestureDetector(
                  onTap: () {
                    _showGroupPostReadersBottomSheet(post);
                  },
                  child: CardView(
                    post: post,
                    isLast: postIndex == posts.length - 1,
                    isFirst: postIndex == 0,
                  ),
                );
          }, childCount: posts.isEmpty ? 0 : (posts.length * 2 - 1)),
        ),
      ),
    ];
  }

  // 🎯 그룹 포스트 로드 (일반 그룹)
  Future<void> _loadGroupPosts(int groupId) async {
    if (_isLoadingGroupPosts[groupId] == true) return;
    if (_hasMoreGroupPosts[groupId] == false) return;
    if (!mounted) return;

    final loadingStartTime = DateTime.now();
    setState(() {
      _isLoadingGroupPosts[groupId] = true;
      _postsLoadingStartTime[groupId] = loadingStartTime;
    });

    try {
      final blogService = BlogService();
      final page = _groupPostsPage[groupId] ?? 0;
      final response = await blogService.getGroupPosts(
        groupId: groupId,
        page: page,
        size: 20, // 🎯 10 -> 20으로 증가
        includeContent: false,
      );

      if (!mounted) return;

      final postsData = response['posts'] as Map<String, dynamic>?;
      final postsList = (postsData?['content'] as List?) ?? [];

      final newPosts =
          postsList
              .map<PostData>(
                (item) => PostData.fromServer(item as Map<String, dynamic>),
              )
              .toList();

      final hasMore = newPosts.length >= 20; // 🎯 10 -> 20으로 변경

      // 🎯 최소 0.5초 shimmer 표시 보장
      final elapsed =
          DateTime.now().difference(loadingStartTime).inMilliseconds;
      final remainingDelay = 500 - elapsed;

      if (remainingDelay > 0) {
        await Future.delayed(Duration(milliseconds: remainingDelay));
      }

      if (!mounted) return;
      setState(() {
        final existingPosts = _groupPostsCache[groupId] ?? [];
        _groupPostsCache[groupId] = [...existingPosts, ...newPosts];
        _hasMoreGroupPosts[groupId] = hasMore;
        if (hasMore) {
          _groupPostsPage[groupId] = (page + 1);
        }
        _isLoadingGroupPosts[groupId] = false;
        _postsLoadingStartTime.remove(groupId);
      });
    } catch (e) {
      debugPrint('❌ [ManageGroupScreen] 그룹 포스트 로드 에러: $e');

      // 🎯 최소 0.5초 shimmer 표시 보장 (에러 발생 시에도)
      final elapsed =
          DateTime.now().difference(loadingStartTime).inMilliseconds;
      final remainingDelay = 500 - elapsed;

      if (remainingDelay > 0) {
        await Future.delayed(Duration(milliseconds: remainingDelay));
      }

      if (!mounted) return;
      setState(() {
        _isLoadingGroupPosts[groupId] = false;
        _hasMoreGroupPosts[groupId] = false;
        _postsLoadingStartTime.remove(groupId);
      });
    }
  }

  // 🎯 멤버 새로고침 (캐시 무시하고 다시 로드)
  Future<void> _refreshMembers(
    GroupProvider groupProv,
    FriendProvider friendProv,
  ) async {
    if (!mounted || _selectedGroup == null) return;

    // 🎯 시스템 그룹 체크는 isSystem만 사용
    if (_selectedGroup!.isSystem == true) {
      // allFriends 그룹: 친구 데이터 + 그룹 정보(이미지, 설명, 친구 수) 새로고침
      await Future.wait([
        friendProv.fetchAllFriendData(forceRefresh: true),
        groupProv.fetchMyGroups(forceRefresh: true, friendProvider: friendProv),
      ]);

      // 🎯 그룹 정보 업데이트 반영
      final updatedGroups = groupProv.myGroups;
      final updatedAllFriendsGroup = updatedGroups.firstWhere(
        (g) => g.isSystem == true,
        orElse: () => _selectedGroup!,
      );

      if (mounted) {
        setState(() {
          _selectedGroup = updatedAllFriendsGroup;
        });
      }
    } else {
      // 일반 그룹: 멤버 목록 + 그룹 정보(멤버 수 등) 새로고침
      await Future.wait([
        groupProv.fetchGroupMembers(_selectedGroup!.id, forceRefresh: true),
        groupProv.fetchMyGroups(forceRefresh: true, friendProvider: friendProv),
      ]);

      // 🎯 그룹 정보 업데이트 반영
      final updatedGroups = groupProv.myGroups;
      final updatedGroup = updatedGroups.firstWhere(
        (g) => g.id == _selectedGroup!.id,
        orElse: () => _selectedGroup!,
      );

      if (mounted) {
        setState(() {
          _selectedGroup = updatedGroup;
        });
      }
    }
  }

  // 🎯 포스트 새로고침 (캐시 무시하고 다시 로드)
  Future<void> _refreshPosts() async {
    if (!mounted || _selectedGroup == null) return;

    final isAllFriendsGroup = _selectedGroup!.isSystem == true;
    final groupId = isAllFriendsGroup ? -1 : _selectedGroup!.id;

    // 🎯 캐시 및 페이지 초기화
    setState(() {
      _groupPostsCache[groupId] = [];
      _groupPostsPage[groupId] = 0;
      _hasMoreGroupPosts[groupId] = true;
    });

    // 🎯 무효화 플래그 제거
    _invalidatedGroupIds.remove(groupId);

    // 🎯 처음부터 다시 로드
    if (isAllFriendsGroup) {
      await _loadAllFriendsPosts();
    } else if (groupId != -1) {
      await _loadGroupPosts(groupId);
    }
  }

  /// 🎯 그룹 포스트 캐시 무효화 (내부 구현)
  static void invalidateGroupPostsCacheInternal(int groupId) {
    debugPrint('🔄 [ManageGroupScreen] 그룹 $groupId 포스트 캐시 무효화');
    _invalidatedGroupIds.add(groupId);
    // 캐시는 즉시 삭제하지 않고, 화면 진입 시 확인 후 새로고침
    // (현재 화면에서 보고 있는 경우 즉시 새로고침하도록 플래그만 설정)
  }

  /// 🎯 여러 그룹의 포스트 캐시 일괄 무효화 (내부 구현)
  static void invalidateMultipleGroupsPostsCacheInternal(List<int> groupIds) {
    debugPrint('🔄 [ManageGroupScreen] 여러 그룹 포스트 캐시 무효화: $groupIds');
    for (final groupId in groupIds) {
      _invalidatedGroupIds.add(groupId);
    }
  }

  /// 🎯 특정 그룹의 캐시 무효화 상태 확인 (내부 구현)
  static bool isGroupPostsCacheInvalidatedInternal(int groupId) {
    return _invalidatedGroupIds.contains(groupId);
  }

  /// 🎯 모든 그룹 포스트 캐시 무효화 플래그 제거 (내부 구현)
  static void clearInvalidationFlagsInternal() {
    _invalidatedGroupIds.clear();
  }

  // 🎯 allFriends 그룹 포스트 로드 (내가 작성한 FRIENDS 공개 범위만)
  Future<void> _loadAllFriendsPosts() async {
    const int groupId = -1;
    if (_isLoadingGroupPosts[groupId] == true) return;
    if (_hasMoreGroupPosts[groupId] == false) return;
    if (!mounted) return;

    final loadingStartTime = DateTime.now();
    setState(() {
      _isLoadingGroupPosts[groupId] = true;
      _postsLoadingStartTime[groupId] = loadingStartTime;
    });

    try {
      final blogService = BlogService();
      final page = _groupPostsPage[groupId] ?? 0;
      // 🎯 새로운 엔드포인트 사용: 내가 작성한 FRIENDS 공개 범위 포스트만 조회
      final postsList = await blogService.getMyFriendsPosts(
        page: page,
        size: 20, // 🎯 10 -> 20으로 증가
        includeContent: false,
      );

      if (!mounted) return;

      final newPosts =
          postsList.map<PostData>((item) => PostData.fromServer(item)).toList();

      final hasMore = newPosts.length >= 20; // 🎯 10 -> 20으로 변경

      // 🎯 최소 0.5초 shimmer 표시 보장
      final elapsed =
          DateTime.now().difference(loadingStartTime).inMilliseconds;
      final remainingDelay = 500 - elapsed;

      if (remainingDelay > 0) {
        await Future.delayed(Duration(milliseconds: remainingDelay));
      }

      if (!mounted) return;
      setState(() {
        final existingPosts = _groupPostsCache[groupId] ?? [];
        _groupPostsCache[groupId] = [...existingPosts, ...newPosts];
        _hasMoreGroupPosts[groupId] = hasMore;
        if (hasMore) {
          _groupPostsPage[groupId] = (page + 1);
        }
        _isLoadingGroupPosts[groupId] = false;
        _postsLoadingStartTime.remove(groupId);
      });
    } catch (e) {
      debugPrint('❌ [ManageGroupScreen] allFriends 포스트 로드 에러: $e');

      // 🎯 최소 0.5초 shimmer 표시 보장 (에러 발생 시에도)
      final elapsed =
          DateTime.now().difference(loadingStartTime).inMilliseconds;
      final remainingDelay = 500 - elapsed;

      if (remainingDelay > 0) {
        await Future.delayed(Duration(milliseconds: remainingDelay));
      }

      if (!mounted) return;
      setState(() {
        _isLoadingGroupPosts[groupId] = false;
        _hasMoreGroupPosts[groupId] = false;
        _postsLoadingStartTime.remove(groupId);
      });
    }
  }

  // 🎯 멤버 그리드 빌드
  Widget _buildFriendsSliverGrid(
    FriendProvider friendProv,
    GroupProvider groupProv,
    Group selectedGroup,
  ) {
    if (selectedGroup.id != -1 &&
        !groupProv.isMembersCached(selectedGroup.id) &&
        !groupProv.isLoadingMembers(selectedGroup.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedGroup?.id == selectedGroup.id) {
          groupProv.fetchGroupMembers(selectedGroup.id);
        }
      });
    }

    // 🎯 새로고침 중이거나 로딩 중일 때 Shimmer 표시
    final isAllFriendsGroup = selectedGroup.isSystem == true;
    final isLoading =
        isAllFriendsGroup
            ? friendProv.isLoading
            : (selectedGroup.id != -1 &&
                groupProv.isLoadingMembers(selectedGroup.id) &&
                !groupProv.isMembersCached(selectedGroup.id));

    // 🎯 새로고침 중이거나 일반 로딩 중일 때 Shimmer 표시
    if ((_isRefreshing && _currentViewIndex == 0) || isLoading) {
      return _buildMembersShimmer();
    }

    List<Friend> accepted;
    List<Friend> received;

    if (isAllFriendsGroup) {
      accepted = friendProv.acceptedFriends;
      received = [];
    } else {
      final groupMembers = groupProv.membersOf(selectedGroup.id);
      final memberUsernames = groupMembers.map((m) => m.userId).toSet();

      if (memberUsernames.isEmpty) {
        accepted = [];
        received = [];
      } else {
        accepted =
            friendProv.acceptedFriends
                .where((f) => memberUsernames.contains(f.username))
                .toList();
        received =
            friendProv.receivedRequests
                .where((f) => memberUsernames.contains(f.username))
                .toList();
      }
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      accepted =
          accepted
              .where(
                (f) =>
                    f.username.toLowerCase().contains(query) ||
                    f.alias.toLowerCase().contains(query),
              )
              .toList();
      received =
          received
              .where(
                (f) =>
                    f.username.toLowerCase().contains(query) ||
                    f.alias.toLowerCase().contains(query),
              )
              .toList();
    }

    final List<FriendTileData> tiles = [];
    if (!isAllFriendsGroup) {
      for (final f in received) {
        tiles.add(
          FriendTileData(
            username: f.username,
            url: f.profileImageUrl,
            alias: f.alias,
            state: FriendState.requestReceived,
          ),
        );
      }
    }
    for (final f in accepted) {
      tiles.add(
        FriendTileData(
          username: f.username,
          url: f.profileImageUrl,
          alias: f.alias,
          state: FriendState.accepted,
        ),
      );
    }

    // 🎯 빈 상태: SliverToBoxAdapter + 고정 height (선택 모드일 때는 숨김)
    if (tiles.isEmpty && !_isMultiSelectMode) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: Center(
            child: Text(
              _searchQuery.isNotEmpty
                  ? context.tr('no_matching_members_or_groups')
                  : selectedGroup.isSystem == true
                  ? context.tr('no_friends_to_display')
                  : context.tr('no_friends_in_group'),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // 🎯 친구가 있을 때: SliverGrid
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 50,
        crossAxisSpacing: 6,
        childAspectRatio: 0.75, // 🎯 텍스트 공간 확보를 위해 높이 증가 (0.82 -> 0.75)
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final tile = tiles[index];
        return FriendTile(
          data: tile,
          isMultiSelectMode: _isMultiSelectMode,
          isSelected: _selectedMembers.contains(tile.username),
          onToggle: () {
            setState(() {
              if (_selectedMembers.contains(tile.username)) {
                _selectedMembers.remove(tile.username);
              } else {
                _selectedMembers.add(tile.username);
              }
            });
          },
        );
      }, childCount: tiles.length),
    );
  }

  // 🎯 멤버 그리드 Shimmer
  Widget _buildMembersShimmer() {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 50,
          crossAxisSpacing: 6,
          childAspectRatio: 0.82, // 🎯 실제 그리드와 동일하게 맞춤
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              ShimmerBox(width: 120, height: 130, shape: const CircleBorder()),
            ],
          );
        }, childCount: 9),
      ),
    );
  }

  // 🎯 포스트 다중 선택 모드 하단 액션바
  Widget _buildPostMultiSelectActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎯 얇은 디바이더 - 화면 너비 전체
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 0,
              endIndent: 0,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            ),
            // 🎯 공개범위 일괄 변경 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: GestureDetector(
                onTap:
                    _selectedPosts.isEmpty ? null : _showBatchAccessLevelChange,
                child: Text(
                  textAlign: TextAlign.center,
                  '${context.tr('batch_change_access_level_button')}(${_selectedPosts.length})',
                  style: TextStyle(
                    color:
                        _selectedPosts.isEmpty
                            ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.5)
                            : Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight:
                        _selectedPosts.isEmpty
                            ? FontWeight.normal
                            : FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 선택된 포스트들의 공개범위 일괄 변경
  Future<void> _showBatchAccessLevelChange() async {
    if (_selectedPosts.isEmpty) {
      return;
    }

    final postIdsToChange = _selectedPosts.toList();

    // 🎯 단일 포스트인 경우: 실제 postId를 전달하여 배치 엔드포인트로 즉시 처리
    if (postIdsToChange.length == 1) {
      final singlePostId = postIdsToChange.first;

      // 🎯 포스트 정보 가져오기 (현재 공개범위 확인용)
      final currentGroup = _selectedGroup;
      final isAllFriendsGroup =
          currentGroup != null && currentGroup.isSystem == true;
      final groupId = isAllFriendsGroup ? -1 : currentGroup?.id;
      final posts = _groupPostsCache[groupId] ?? [];
      final post = posts.firstWhere(
        (p) => p.id == singlePostId,
        orElse: () => posts.first,
      );

      // 🎯 현재 공개범위 정보
      String currentAccessLevel = SystemCategoryKeys.public;
      if (post.accessLevel == AccessLevel.private) {
        currentAccessLevel = SystemCategoryKeys.private;
      } else if (post.accessLevel == AccessLevel.friends) {
        currentAccessLevel = SystemCategoryKeys.friends;
      } else if (post.accessLevel == AccessLevel.groups) {
        currentAccessLevel = SystemCategoryKeys.groups;
      }

      // 🎯 제외할 그룹 ID: 일반 그룹일 때는 현재 그룹 ID, 전체 친구 그룹일 때는 -1
      final excludeGroupIdForSingle =
          isAllFriendsGroup
              ? -1 // 🎯 전체 친구 그룹: -1로 제외
              : (currentGroup?.id); // 🎯 일반 그룹: 현재 그룹 ID

      // 🎯 단일 포스트: 실제 postId를 전달하여 배치 엔드포인트로 처리
      AccessLevelSheet.show(
        context,
        postId: singlePostId, // 🎯 실제 포스트 ID 전달
        currentAccessLevel: currentAccessLevel,
        currentSharedGroupIds: post.sharedGroupIds,
        currentSharedGroupNames: post.sharedGroupNames,
        excludeGroupId: excludeGroupIdForSingle, // 🎯 현재 그룹 제외
        onChanged: (String newAccessLevel, List<int>? newSharedGroupIds) async {
          // 🎯 단일 포스트는 AccessLevelSheet 내부에서 배치 엔드포인트로 처리됨
          // 여기서는 변경된 포스트를 캐시에서 제거하고 재빌드
          if (!mounted || groupId == null) return;

          // 🎯 원래 공개범위 정보 수집 (postCount 업데이트용)
          final originalAccessLevel = post.accessLevel;
          final originalSharedGroupIds = post.sharedGroupIds;

          // 🎯 변경된 포스트를 캐시에서 제거
          setState(() {
            final currentPosts = _groupPostsCache[groupId] ?? [];
            _groupPostsCache[groupId] =
                currentPosts.where((p) => p.id != singlePostId).toList();
            _selectedPosts.clear();
            _isMultiSelectMode = false;
          });

          // 🎯 그룹 postCount 업데이트
          final groupProvider = context.read<GroupProvider>();

          // 🎯 1. 현재 그룹에서 포스트 제거
          if (groupId != -1) {
            groupProvider.updateGroupPostCount(groupId, -1);
            ManageGroupScreen.invalidateGroupPostsCache(groupId);
          } else {
            groupProvider.updateGroupPostCount(-1, -1);
            ManageGroupScreen.invalidateGroupPostsCache(-1);
          }

          // 🎯 2. 원래 공개범위에 따른 다른 그룹들의 postCount 감소
          if (originalAccessLevel == AccessLevel.groups &&
              originalSharedGroupIds != null &&
              originalSharedGroupIds.isNotEmpty) {
            final groupIdToDelta = <int, int>{};
            for (final gId in originalSharedGroupIds) {
              if (gId != groupId) {
                // 🎯 현재 그룹이 아닌 다른 그룹들에서만 감소
                groupIdToDelta[gId] = -1;
              }
            }
            if (groupIdToDelta.isNotEmpty) {
              groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);
              ManageGroupScreen.invalidateMultipleGroupsPostsCache(
                groupIdToDelta.keys.toList(),
              );
            }
          }

          if (originalAccessLevel == AccessLevel.friends && groupId != -1) {
            // 🎯 원래 FRIENDS에 있던 포스트: allFriends 그룹에서 제거
            groupProvider.updateGroupPostCount(-1, -1);
            ManageGroupScreen.invalidateGroupPostsCache(-1);
          }

          // 🎯 3. 변경 후 공개범위에 따른 새로운 그룹들의 postCount 증가
          final newAccessLevelStr = newAccessLevel.toUpperCase();
          if (newAccessLevelStr == SystemCategoryKeys.groups &&
              newSharedGroupIds != null &&
              newSharedGroupIds.isNotEmpty) {
            final groupIdToDelta = <int, int>{};
            for (final gId in newSharedGroupIds) {
              groupIdToDelta[gId] = 1;
            }
            groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);
            ManageGroupScreen.invalidateMultipleGroupsPostsCache(
              newSharedGroupIds,
            );
          }

          if (newAccessLevelStr == SystemCategoryKeys.friends) {
            groupProvider.updateGroupPostCount(-1, 1);
            ManageGroupScreen.invalidateGroupPostsCache(-1);
          }

          // 🎯 프로필 피드 업데이트: 변경된 포스트의 메타데이터 업데이트
          try {
            final feed = MyProfileFeedProvider(); // 싱글톤 직접 접근
            feed.updatePostMetadata(
              singlePostId,
              accessLevel: newAccessLevelStr,
              sharedGroupIds: newSharedGroupIds,
            );
            debugPrint(
              '[ManageGroupScreen] 프로필 피드 선택적 업데이트 완료 (단일 포스트: $singlePostId)',
            );
          } catch (e) {
            debugPrint('[ManageGroupScreen] 프로필 피드 선택적 업데이트 실패: $e');
          }
        },
      );
      return;
    }

    // 🎯 여러 포스트인 경우: 배치 모드 (선택만, API는 나중에 호출)
    // 🎯 공개범위 선택을 위한 변수
    String? selectedAccessLevel;
    List<int>? selectedSharedGroupIds;
    final completer = Completer<bool>(); // 🎯 선택 여부를 나타내는 Completer

    debugPrint(
      '[ManageGroupScreen] AccessLevelSheet.show 호출 (배치 모드: isBatchMode=true)',
    );
    // 🎯 AccessLevelSheet를 열어서 공개범위 선택 (배치 모드: isBatchMode=true)
    // 🎯 여러 포스트 중 첫 번째 포스트 ID와 공개범위를 가져오기
    final firstPostId = postIdsToChange.first;

    // 🎯 첫 번째 포스트의 현재 공개범위 가져오기
    final currentGroup = _selectedGroup;
    final isAllFriendsGroup =
        currentGroup != null && currentGroup.isSystem == true;
    final groupId = isAllFriendsGroup ? -1 : currentGroup?.id;
    final posts = _groupPostsCache[groupId ?? -1] ?? [];
    final firstPost = posts.firstWhere(
      (p) => p.id == firstPostId,
      orElse: () => posts.first,
    );

    // 🎯 첫 번째 포스트의 현재 공개범위
    String firstPostAccessLevel = SystemCategoryKeys.public;
    if (firstPost.accessLevel == AccessLevel.private) {
      firstPostAccessLevel = SystemCategoryKeys.private;
    } else if (firstPost.accessLevel == AccessLevel.friends) {
      firstPostAccessLevel = SystemCategoryKeys.friends;
    } else if (firstPost.accessLevel == AccessLevel.groups) {
      firstPostAccessLevel = SystemCategoryKeys.groups;
    }

    // 🎯 제외할 그룹 ID: 일반 그룹일 때는 현재 그룹 ID, 전체 친구 그룹일 때는 -1 (전체 친구 그룹 제외)
    // 🎯 배치 모드에서 일반 그룹의 경우 항상 현재 그룹을 제외해야 함
    final excludeGroupId =
        isAllFriendsGroup
            ? -1
            : (currentGroup != null ? currentGroup.id : null);

    AccessLevelSheet.show(
      context,
      postId: firstPostId, // 🎯 필수 파라미터 (실제로는 사용 안 함, isBatchMode로 구분)
      currentAccessLevel: firstPostAccessLevel, // 🎯 첫 번째 포스트의 현재 공개범위
      currentSharedGroupIds: firstPost.sharedGroupIds,
      currentSharedGroupNames: firstPost.sharedGroupNames,
      excludeGroupId: excludeGroupId, // 🎯 배치 모드: 일반 그룹일 때 현재 그룹 제외
      isBatchMode: true, // 🎯 배치 모드: API 호출 없이 선택만
      onChanged: (String accessLevel, List<int>? sharedGroupIds) {
        // 🎯 선택한 공개범위 저장
        selectedAccessLevel = accessLevel;
        selectedSharedGroupIds = sharedGroupIds;
        if (!completer.isCompleted) {
          completer.complete(true); // 🎯 선택 완료
        }
      },
    );

    // 🎯 공개범위 선택 완료 대기 (타임아웃: 30초)
    final selected = await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => false, // 🎯 타임아웃 시 false 반환
    );

    // 🎯 공개범위를 선택하지 않고 시트를 닫았으면 취소
    if (!selected || selectedAccessLevel == null || !mounted) {
      return;
    }

    // 🎯 다이얼로그: 선택한 공개범위로 변경 확인
    String accessLevelLabel;
    final accessLevel = selectedAccessLevel!;
    switch (accessLevel) {
      case SystemCategoryKeys.public:
        accessLevelLabel = context.tr('visibility_public'); // '전체공개'
        break;
      case SystemCategoryKeys.friends:
        accessLevelLabel = context.tr('visibility_friends'); // '모든 친구'
        break;
      case SystemCategoryKeys.private:
        accessLevelLabel = context.tr('visibility_private'); // '나만보기'
        break;
      case SystemCategoryKeys.groups:
        final sharedGroupIds = selectedSharedGroupIds;
        accessLevelLabel =
            sharedGroupIds != null && sharedGroupIds.isNotEmpty
                ? context.tr('visibility_group') // '그룹공개'
                : context.tr(
                  'visibility_private',
                ); // 🎯 sharedGroupIds가 비어있으면 PRIVATE으로
        break;
      default:
        accessLevelLabel = accessLevel;
    }

    // 🎯 GROUPS인데 sharedGroupIds가 비어있으면 PRIVATE으로 자동 변경
    String finalAccessLevel = accessLevel;
    List<int>? finalSharedGroupIds = selectedSharedGroupIds;
    if (accessLevel == SystemCategoryKeys.groups) {
      final sharedGroupIds = selectedSharedGroupIds;
      if (sharedGroupIds == null || sharedGroupIds.isEmpty) {
        finalAccessLevel = SystemCategoryKeys.private;
        accessLevelLabel = context.tr('visibility_private'); // '나만보기'
        finalSharedGroupIds = null;
      }
    }

    final confirmed = await DialogUtils.showConfirmDialog(
      context,
      title: context.tr('batch_change_access_level_title'),
      message: context
          .tr('batch_change_access_level_message')
          .replaceAll('{count}', '${postIdsToChange.length}')
          .replaceAll('{accessLevel}', accessLevelLabel),
      confirmText: context.tr('change'),
      cancelText: context.tr('cancel'),
      isDestructive: false,
    );

    if (confirmed != true || !mounted) return;

    try {
      final blogService = BlogService();

      final postIdsInt =
          postIdsToChange
              .map((id) => int.tryParse(id))
              .where((id) => id != null)
              .cast<int>()
              .toList();

      if (postIdsInt.isEmpty) {
        throw Exception('유효한 포스트 ID가 없습니다');
      }

      // 🎯 배치 공개범위 변경 API 호출
      final updatedPosts = await blogService.batchUpdatePostsAccessLevel(
        postIds: postIdsInt,
        accessLevel: finalAccessLevel,
        sharedGroupIds:
            finalAccessLevel == SystemCategoryKeys.groups
                ? finalSharedGroupIds
                : null,
      );

      if (mounted) {
        final currentGroup = _selectedGroup;
        final isAllFriendsGroup =
            currentGroup != null && currentGroup.isSystem == true;
        final groupId = isAllFriendsGroup ? -1 : currentGroup?.id;

        // 🎯 변경된 포스트를 캐시에서 제거
        if (groupId != null) {
          final currentPosts = _groupPostsCache[groupId] ?? [];
          final updatedPostIds =
              updatedPosts.map((p) => p['id']?.toString()).toSet();

          // 🎯 변경 전 포스트들의 원래 공개범위 수집 (동기화용)
          final selectedPosts =
              currentPosts
                  .where((post) => updatedPostIds.contains(post.id))
                  .toList();

          // 🎯 원래 공개범위별로 그룹 정보 수집
          final originalGroupsPostCount = <int, int>{}; // 그룹 ID -> 감소할 포스트 수
          var originalFriendsCount = 0; // FRIENDS에 있던 포스트 수

          for (final post in selectedPosts) {
            if (post.accessLevel == AccessLevel.groups &&
                post.sharedGroupIds != null &&
                post.sharedGroupIds!.isNotEmpty) {
              // 🎯 원래 GROUPS에 있던 포스트: 각 그룹에서 제거해야 함
              for (final gId in post.sharedGroupIds!) {
                if (gId != groupId) {
                  // 🎯 현재 그룹이 아닌 다른 그룹들에서만 감소
                  originalGroupsPostCount[gId] =
                      (originalGroupsPostCount[gId] ?? 0) + 1;
                }
              }
            } else if (post.accessLevel == AccessLevel.friends) {
              // 🎯 원래 FRIENDS에 있던 포스트
              if (groupId != -1) {
                // 🎯 현재 그룹이 GROUPS면 allFriends 그룹에서 제거
                originalFriendsCount++;
              }
            }
          }

          setState(() {
            _groupPostsCache[groupId] =
                currentPosts
                    .where((post) => !updatedPostIds.contains(post.id))
                    .toList();
            _selectedPosts.clear();
            _isMultiSelectMode = false;
          });

          // 🎯 그룹 postCount 업데이트
          final groupProvider = context.read<GroupProvider>();

          // 🎯 1. 현재 그룹에서 포스트 제거
          if (groupId != -1) {
            // 일반 그룹의 경우 해당 그룹만 업데이트
            groupProvider.updateGroupPostCount(groupId, -updatedPostIds.length);
            // 🎯 해당 그룹 포스트 캐시 무효화
            ManageGroupScreen.invalidateGroupPostsCache(groupId);
          } else {
            // allFriends 그룹의 경우
            groupProvider.updateGroupPostCount(-1, -updatedPostIds.length);
            // 🎯 allFriends 그룹 포스트 캐시 무효화
            ManageGroupScreen.invalidateGroupPostsCache(-1);
          }

          // 🎯 2. 원래 공개범위에 따른 다른 그룹들의 postCount 감소
          if (originalGroupsPostCount.isNotEmpty) {
            // 🎯 원래 다른 GROUPS에 있던 포스트들 제거
            final groupIdToDelta = <int, int>{};
            originalGroupsPostCount.forEach((gId, count) {
              groupIdToDelta[gId] = -count;
            });
            groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);
            // 🎯 원래 그룹들의 포스트 캐시 무효화
            ManageGroupScreen.invalidateMultipleGroupsPostsCache(
              originalGroupsPostCount.keys.toList(),
            );
          }

          if (originalFriendsCount > 0 && groupId != -1) {
            // 🎯 원래 FRIENDS에 있던 포스트들 allFriends 그룹에서 제거
            groupProvider.updateGroupPostCount(-1, -originalFriendsCount);
            // 🎯 allFriends 그룹 포스트 캐시 무효화
            ManageGroupScreen.invalidateGroupPostsCache(-1);
          }

          // 🎯 3. 변경 후 공개범위에 따른 새로운 그룹들의 postCount 증가
          // 🎯 GROUPS로 변경한 경우 선택한 그룹들의 postCount도 업데이트
          if (finalAccessLevel == SystemCategoryKeys.groups &&
              finalSharedGroupIds != null &&
              finalSharedGroupIds.isNotEmpty) {
            final groupIdToDelta = <int, int>{};
            for (final gId in finalSharedGroupIds) {
              groupIdToDelta[gId] = updatedPostIds.length;
            }
            groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);
            // 🎯 선택한 그룹들의 포스트 캐시 무효화
            ManageGroupScreen.invalidateMultipleGroupsPostsCache(
              finalSharedGroupIds,
            );
          }

          // 🎯 FRIENDS로 변경한 경우 allFriends 그룹 postCount 업데이트
          if (finalAccessLevel == SystemCategoryKeys.friends) {
            groupProvider.updateGroupPostCount(-1, updatedPostIds.length);
            // 🎯 allFriends 그룹 포스트 캐시 무효화
            ManageGroupScreen.invalidateGroupPostsCache(-1);
          }

          // 🎯 프로필 피드 업데이트: 변경된 모든 포스트의 메타데이터 업데이트
          try {
            final feed = MyProfileFeedProvider(); // 싱글톤 직접 접근
            for (final updatedPost in updatedPosts) {
              final postId = updatedPost['id']?.toString();
              if (postId != null) {
                // 🎯 공개범위 및 그룹 정보 업데이트
                feed.updatePostMetadata(
                  postId,
                  accessLevel: finalAccessLevel,
                  sharedGroupIds: finalSharedGroupIds,
                );
              }
            }
            debugPrint(
              '[ManageGroupScreen] 프로필 피드 선택적 업데이트 완료 (${updatedPosts.length}개 포스트)',
            );
          } catch (e) {
            debugPrint('[ManageGroupScreen] 프로필 피드 선택적 업데이트 실패: $e');
          }
        } else {
          setState(() {
            _selectedPosts.clear();
            _isMultiSelectMode = false;
          });
        }

        if (updatedPosts.isNotEmpty) {
          ErrorHandler.showInfo(
            context,
            '${updatedPosts.length}개의 포스트가 $accessLevelLabel로 변경되었습니다',
          );
        } else {
          ErrorHandler.showError(context, '공개범위 변경에 실패했습니다');
        }
      }
    } catch (e) {
      debugPrint('❌ [ManageGroupScreen] 포스트 공개범위 일괄 변경 에러: $e');
      if (mounted) {
        setState(() {
          _selectedPosts.clear();
          _isMultiSelectMode = false;
        });
        ErrorHandler.showError(context, '공개범위 변경에 실패했습니다');
      }
    }
  }

  // 🎯 다중 선택 모드 하단 액션바
  Widget _buildMultiSelectActionBar() {
    // 🎯 시스템 그룹 체크는 isSystem만 사용
    final isAllFriendsTab =
        _selectedGroup == null || (_selectedGroup!.isSystem == true);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: () {
            _removeSelectedMembers();
          },
          child: Text(
            textAlign: TextAlign.center,
            isAllFriendsTab
                ? context
                    .tr('unfriend_selected')
                    .replaceAll('{count}', '${_selectedMembers.length}')
                : context
                    .tr('delete_selected_members')
                    .replaceAll('{count}', '${_selectedMembers.length}'),
            style: TextStyle(
              color:
                  _selectedMembers.isEmpty
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                      : Theme.of(context).colorScheme.error,
              fontSize: 16,
              fontWeight:
                  _selectedMembers.isEmpty
                      ? FontWeight.normal
                      : FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // 🎯 그룹 포스트 읽은 사람 리스트 바텀시트 표시
  void _showGroupPostReadersBottomSheet(PostData post) {
    showModalBottomSheet(
      barrierColor: Colors.black.withOpacity(0.6),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupPostReadersBottomSheet(post: post),
    );
  }

  // 멤버 추가 바텀시트 표시
  void _showAddMemberBottomSheet() {
    if (_selectedGroup != null && _selectedGroup!.id != -1) {
      context.read<GroupProvider>().fetchGroupMembers(_selectedGroup!.id);
    }
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    AddMemberScreen(selectedGroup: _selectedGroup),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              const curve = Curves.easeOutCubic;

              var tween = Tween(
                begin: begin,
                end: end,
              ).chain(CurveTween(curve: curve));

              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 300),
          ),
        )
        .then((_) {
          FocusManager.instance.primaryFocus?.unfocus();
        });
  }

  // 🎯 선택된 멤버들을 그룹에서 제거 또는 친구 해제
  Future<void> _removeSelectedMembers() async {
    if (_selectedMembers.isEmpty) {
      return;
    }

    final usernamesToRemove = _selectedMembers.toList();
    // 🎯 시스템 그룹 체크는 isSystem만 사용
    final isAllFriendsTab =
        _selectedGroup == null || (_selectedGroup!.isSystem == true);

    final confirmed = await DialogUtils.showConfirmDialog(
      context,
      title:
          isAllFriendsTab
              ? context.tr('unfriend')
              : context.tr('remove_member'),
      message:
          isAllFriendsTab
              ? context
                  .tr('unfriend_confirm_message')
                  .replaceAll('{count}', '${usernamesToRemove.length}')
              : context
                  .tr('remove_members_confirm')
                  .replaceAll('{count}', '${usernamesToRemove.length}'),
      confirmText:
          isAllFriendsTab ? context.tr('unfriend') : context.tr('remove'),
      cancelText: context.tr('cancel'),
      isDestructive: true,
    );

    if (confirmed != true || !mounted) return;

    try {
      bool success = false;

      if (isAllFriendsTab) {
        if (!mounted) return;
        debugPrint(
          '🔄 [ManageGroupScreen] 친구 일괄 해제 시작: ${usernamesToRemove.length}명',
        );
        final friendProv = context.read<FriendProvider>();
        final groupProv = context.read<GroupProvider>(); // 🎯 그룹 데이터 동기화용
        // 🎯 GroupProvider 전달하여 allFriends 그룹 memberCount 업데이트
        success = await friendProv.deleteFriendsBatch(
          usernamesToRemove,
          groupProvider: groupProv,
        );
      } else {
        if (!mounted) return;
        final groupProv = context.read<GroupProvider>();
        success = await groupProv.removeMembersBatch(
          _selectedGroup!.id,
          usernamesToRemove,
        );
        // 🎯 멤버 제외 후 FriendsGrid UI 즉시 업데이트
        // GroupProvider의 fetchGroupMembers가 notifyListeners()를 호출하여
        // Consumer<GroupProvider> 내부의 _buildFriendsSliverGrid가 자동으로 다시 빌드됨
      }

      if (mounted) {
        setState(() {
          _selectedMembers.clear();
          _isMultiSelectMode = false;
        });

        if (success) {
          ErrorHandler.showInfo(
            context,
            isAllFriendsTab
                ? context
                    .tr('unfriend_success')
                    .replaceAll('{count}', '${usernamesToRemove.length}')
                : context
                    .tr('members_removed')
                    .replaceAll('{count}', '${usernamesToRemove.length}'),
          );
        } else {
          ErrorHandler.showError(
            context,
            isAllFriendsTab
                ? context.tr('unfriend_failed')
                : context.tr('remove_member_failed'),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [ManageGroupScreen] 일괄 작업 에러: $e');

      if (mounted) {
        setState(() {
          _selectedMembers.clear();
          _isMultiSelectMode = false;
        });

        ErrorHandler.showError(
          context,
          isAllFriendsTab
              ? context.tr('unfriend_failed')
              : context.tr('remove_member_failed'),
        );
      }
    }
  }

  // 🎯 그룹 수정 바텀시트
  void _showEditGroupSheet() {
    if (_selectedGroup == null) return;

    _groupDropDown.showGroupDropdown(
      context,
      GlobalKey(),
      [],
      _selectedGroup, // 🎯 selectedGroup 전달
      (group) {},
      (name, description, imageUrl) =>
          _updateGroup(name, description, imageUrl),
      startWithCreate: true,
      editMode: true,
      initialName: _selectedGroup!.name,
      initialDescription: _selectedGroup!.description,
      initialImageUrl: _selectedGroup!.profileImageUrl,
      // 🎯 시스템 그룹이 아닌 경우에만 삭제 버튼 표시
      onDeleteGroup: _selectedGroup!.isSystem != true ? _deleteGroup : null,
    );
  }

  // 🎯 그룹 삭제
  Future<void> _deleteGroup() async {
    // 🎯 시스템 그룹 체크는 isSystem만 사용
    if (_selectedGroup == null || _selectedGroup!.isSystem == true) {
      return;
    }

    final groupProv = context.read<GroupProvider>();
    final groupId = _selectedGroup!.id;
    final navigatorContext =
        Navigator.of(context).context; // 🎯 popUntil 전 context 저장

    try {
      // 🎯 화면을 먼저 닫아서 로딩 로고 표시 방지
      if (mounted) {
        // group_sheet는 이미 pop됨 (group_sheet.dart에서 처리)
        // manage_group_screen을 닫고 group_selection_screen으로 돌아가기
        // pop() 한 번만 호출하여 group_selection_screen까지만 이동
        Navigator.of(context).pop();
      }

      // 🎯 화면 닫은 후 백그라운드에서 그룹 삭제 처리
      await groupProv.deleteGroup(groupId);

      // 🎯 성공 메시지 표시 (group_selection_screen에서)
      // popUntil 후에는 group_selection_screen의 context 사용
      if (navigatorContext.mounted) {
        ErrorHandler.showInfo(
          navigatorContext,
          navigatorContext.tr('group_deleted'),
        );
      }
    } catch (e) {
      // 🎯 에러 발생 시에도 화면은 이미 닫힘, 에러 메시지만 표시
      if (navigatorContext.mounted) {
        ErrorHandler.showError(
          navigatorContext,
          navigatorContext.tr('group_delete_failed'),
        );
      }
    }
  }

  // 🎯 그룹 정보 업데이트
  Future<void> _updateGroup(
    String name,
    String? description,
    String? imageUrl,
  ) async {
    if (_selectedGroup == null) {
      return;
    }

    // 🎯 전체 친구 그룹은 이름 수정 불가
    final bool isAllFriendsGroup = _selectedGroup!.isSystem == true;

    // 🎯 일반 그룹만 id 체크 (전체 친구 그룹은 id가 -1일 수도 있으므로 isSystem으로만 판단)
    if (!isAllFriendsGroup) {
      if (_selectedGroup!.id == -1) {
        return;
      }
    }

    // 🎯 전체 친구 그룹은 이름 수정 불가
    if (isAllFriendsGroup) {
      if (name.trim().toLowerCase() != _selectedGroup!.name.toLowerCase()) {
        if (mounted) {
          ErrorHandler.showError(
            context,
            context.tr('all_friends_group_name_not_editable'),
          );
        }
        return;
      }
    }

    if (name.trim().isEmpty) return;

    try {
      final groupProvider = context.read<GroupProvider>();

      // 🎯 시스템 그룹(전체 친구)은 항상 -1을 ID로 보냄 (서버가 알아서 처리)
      final targetGroupId = isAllFriendsGroup ? -1 : _selectedGroup!.id;

      final success = await groupProvider.updateGroup(
        targetGroupId,
        name.trim(),
        description ?? '',
        profileImageUrl: imageUrl,
      );

      if (success) {
        final updatedGroups = groupProvider.myGroups;
        final updatedGroup = updatedGroups.firstWhere(
          (g) =>
              isAllFriendsGroup
                  ? (g.isSystem == true)
                  : (g.id == _selectedGroup!.id),
          orElse: () => _selectedGroup!,
        );

        if (mounted) {
          setState(() {
            _selectedGroup = updatedGroup;
          });
        }

        if (mounted) {
          ErrorHandler.showInfo(context, context.tr('group_updated'));
        }
      } else {
        if (mounted) {
          ErrorHandler.showError(context, context.tr('group_update_failed'));
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '${context.tr('error_occurred')}: $e');
      }
    }
  }
}
