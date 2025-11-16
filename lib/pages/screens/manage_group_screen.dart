import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/card_view_shimmer.dart';
import 'package:doppy/pages/components/group_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/card_view.dart';
import 'package:doppy/pages/components/add_member_bottom_sheet.dart';
import 'package:doppy/pages/components/group_post_readers_bottom_sheet.dart';
import 'package:doppy/pages/components/friends_grid.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
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
import '../../../data/services/blog_service.dart';
import '../../../providers/group_provider.dart';

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
}

class _ManageGroupScreenState extends State<ManageGroupScreen>
    with TickerProviderStateMixin {
  // 🎯 앱바 확장 높이 상수
  static const double _appBarExpandedHeight = 320.0;

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

  // 🎯 그룹 포스트 관련 상태 (static으로 유지하여 화면 전환 시에도 캐시 보존)
  static final Map<int, List<PostData>> _groupPostsCache = {};
  static final Map<int, bool> _isLoadingGroupPosts = {};
  static final Map<int, int> _groupPostsPage = {};
  static final Map<int, bool> _hasMoreGroupPosts = {};

  // 🎯 앱바 드래그 새로고침 관련 상태
  double _pullOffset = 0.0; // 드래그 오프셋 (음수 = 아래로 당김)
  bool _isRefreshing = false; // 새로고침 중 여부
  late final AnimationController _refreshAnimationController;
  late final Animation<double> _refreshRotationAnimation;

  // 🎯 전체 친구 그룹 로컬 데이터 리로드 트리거

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
          await friendProv.fetchAllFriendData();
        }
      } else {
        // 일반 그룹: 캐시 확인 후 멤버 목록 로드
        if (!groupProv.isMembersCached(_selectedGroup!.id) &&
            !groupProv.isLoadingMembers(_selectedGroup!.id)) {
          await groupProv.fetchGroupMembers(_selectedGroup!.id);
        }
      }
      // 🎯 포스트는 포스트 모드로 갈 때만 로드 (캐시 확인 후)
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
        // 🎯 로딩 중일 때는 shimmer만 표시 (DoppyLoadingLogo 제거)
        // 초기 로딩도 shimmer로 처리
        // if (groupProv.isLoading && !_isRefreshing) {
        //   return Scaffold(...);
        // }

        return Consumer<FriendProvider>(
          builder: (context, friendProv, child) {
            return _buildScaffold(groupProv, friendProv);
          },
        );
      },
    );
  }

  // 🎯 NestedScrollView 기반 안정형 구조
  Widget _buildScaffold(GroupProvider groupProv, FriendProvider friendProv) {
    final group = _selectedGroup;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 🎯 NestedScrollView: Slack/Instagram 스타일 안정형 구조
          if (!widget.embedded)
            NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                    sliver: AnimatedBuilder(
                      animation: _appBarHeightAnimation,
                      builder: (context, child) {
                        // 🎯 검색 활성화 시 expandedHeight를 0으로, 아니면 기본값으로 설정

                        return SliverAppBar(
                          pinned: true,
                          expandedHeight:
                              _isAppbarSearchExpanded
                                  ? 0.0
                                  : _appBarExpandedHeight,
                          toolbarHeight:
                              MediaQuery.of(context).padding.top + 110,
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          automaticallyImplyLeading: false,
                          flexibleSpace: FlexibleSpaceBar(
                            collapseMode: CollapseMode.pin,
                            background: RepaintBoundary(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                                child: _buildAppBarContent(),
                              ),
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
                                      // 🎯 드래그에 따른 투명도 조절 (_refreshTrigger에서 완전히 투명해지도록)
                                      AnimatedOpacity(
                                        opacity:
                                            (1.0 -
                                                (_pullOffset / _refreshTrigger)
                                                    .clamp(0.0, 1.0)),
                                        duration: const Duration(
                                          milliseconds: 50, // 더 빠른 애니메이션
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 28,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _isMultiSelectMode
                                                    ? '${_selectedMembers.length} ${context.tr('selected')}'
                                                    : _getGroupDisplayName(
                                                      group,
                                                    ),
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                  letterSpacing: -0.5,
                                                  height: 1.2,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 8),
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
                                      SizedBox(height: 12),
                                    ],
                                  ),
                                  // 🎯 스피너 (상단에 고정) - _refreshStart 이상일 때만 표시
                                  if (_pullOffset > _refreshStart ||
                                      _isRefreshing)
                                    Positioned(
                                      top: 0,
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
          // 뒤로가기 버튼
          if (!widget.embedded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 9,
              child: GestureDetector(
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
        padding: const EdgeInsets.only(left: 20, right: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Hero(
              tag: 'group-${group.id}',
              child: RepaintBoundary(
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
                            ).colorScheme.onSurface.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: ClipOval(
                          child:
                              displayImageUrl != null &&
                                      displayImageUrl.isNotEmpty &&
                                      (displayImageUrl.startsWith('http://') ||
                                          displayImageUrl.startsWith(
                                            'https://',
                                          ))
                                  ? CachedNetworkImage(
                                    imageUrl: displayImageUrl,
                                    fit: BoxFit.cover,
                                    width: 90,
                                    height: 90,
                                    placeholder:
                                        (context, url) => Container(
                                          width: 90,
                                          height: 90,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.surface,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.3),
                                                  ),
                                            ),
                                          ),
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
            SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🎯 첫 번째 줄: 디스크립션 (있다면)
                  if (displayDescription.isNotEmpty)
                    RepaintBoundary(
                      child: Text(
                        displayDescription,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
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
                  // 🎯 두 번째 줄: 멤버 수 · 포스트 수 (프로필 화면 스타일)
                  RepaintBoundary(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: displayDescription.isNotEmpty ? 4.0 : 0.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // 멤버 수
                          _buildStatItem(
                            context,
                            count: group.memberCount ?? 0,
                            label: context.tr('members'),
                          ),
                          const SizedBox(width: 20),
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
        final posts = _groupPostsCache[newGroup.id] ?? [];
        final isLoading = _isLoadingGroupPosts[newGroup.id] ?? false;
        final hasMore = _hasMoreGroupPosts[newGroup.id] ?? true;
        if (posts.isEmpty && !isLoading && hasMore) {
          _loadGroupPosts(newGroup.id);
        }
      } else if (isAllFriendsGroup) {
        final posts = _groupPostsCache[-1] ?? [];
        final isLoading = _isLoadingGroupPosts[-1] ?? false;
        final hasMore = _hasMoreGroupPosts[-1] ?? true;
        if (posts.isEmpty && !isLoading && hasMore) {
          _loadAllFriendsPosts();
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
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
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
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
      if (group != null && group.id != -1) {
        final posts = _groupPostsCache[group.id] ?? [];
        final isLoading = _isLoadingGroupPosts[group.id] ?? false;
        if (posts.isEmpty && !isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedGroup?.id == group.id) {
              _loadGroupPosts(group.id);
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

    // 🎯 새로고침 중이거나 (로딩 중이고 포스트가 비어있을 때) Shimmer 표시
    if ((_isRefreshing && _currentViewIndex == 1) ||
        (isLoading && posts.isEmpty && hasMore)) {
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

    // 🎯 빈 상태: SliverToBoxAdapter + 고정 height
    if (posts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.45 + 40,
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

            if (postIndex == posts.length - 3 && hasMore && !isLoading) {
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

            return Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isMultiSelectMode) {
                      setState(() {
                        if (isSelected) {
                          _selectedPosts.remove(post.id);
                        } else {
                          _selectedPosts.add(post.id);
                        }
                      });
                    } else {
                      _showGroupPostReadersBottomSheet(post);
                    }
                  },
                  child: CardView(
                    post: post,
                    isLast: postIndex == posts.length - 1,
                    isFirst: postIndex == 0,
                  ),
                ),
                if (_isMultiSelectMode)
                  Positioned(
                    left: 8,
                    top: 8,
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
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.white.withOpacity(0.9),
                          border: Border.all(
                            color:
                                isSelected
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child:
                            isSelected
                                ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.surface,
                                )
                                : null,
                      ),
                    ),
                  ),
              ],
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

    setState(() {
      _isLoadingGroupPosts[groupId] = true;
    });

    try {
      final blogService = BlogService();
      final page = _groupPostsPage[groupId] ?? 0;
      final response = await blogService.getGroupPosts(
        groupId: groupId,
        page: page,
        size: 10,
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

      final hasMore = newPosts.length >= 10;

      if (!mounted) return;
      setState(() {
        final existingPosts = _groupPostsCache[groupId] ?? [];
        _groupPostsCache[groupId] = [...existingPosts, ...newPosts];
        _hasMoreGroupPosts[groupId] = hasMore;
        if (hasMore) {
          _groupPostsPage[groupId] = (page + 1);
        }
        _isLoadingGroupPosts[groupId] = false;
      });
    } catch (e) {
      print('❌ [ManageGroupScreen] 그룹 포스트 로드 에러: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingGroupPosts[groupId] = false;
        _hasMoreGroupPosts[groupId] = false;
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

    // 🎯 처음부터 다시 로드
    if (isAllFriendsGroup) {
      await _loadAllFriendsPosts();
    } else if (groupId != -1) {
      await _loadGroupPosts(groupId);
    }
  }

  // 🎯 allFriends 그룹 포스트 로드 (내가 작성한 FRIENDS 공개 범위만)
  Future<void> _loadAllFriendsPosts() async {
    const int groupId = -1;
    if (_isLoadingGroupPosts[groupId] == true) return;
    if (_hasMoreGroupPosts[groupId] == false) return;
    if (!mounted) return;

    setState(() {
      _isLoadingGroupPosts[groupId] = true;
    });

    try {
      final blogService = BlogService();
      final page = _groupPostsPage[groupId] ?? 0;
      // 🎯 새로운 엔드포인트 사용: 내가 작성한 FRIENDS 공개 범위 포스트만 조회
      final postsList = await blogService.getMyFriendsPosts(
        page: page,
        size: 10,
        includeContent: false,
      );

      if (!mounted) return;

      final newPosts =
          postsList.map<PostData>((item) => PostData.fromServer(item)).toList();

      final hasMore = newPosts.length >= 10;

      if (!mounted) return;
      setState(() {
        final existingPosts = _groupPostsCache[groupId] ?? [];
        _groupPostsCache[groupId] = [...existingPosts, ...newPosts];
        _hasMoreGroupPosts[groupId] = hasMore;
        if (hasMore) {
          _groupPostsPage[groupId] = (page + 1);
        }
        _isLoadingGroupPosts[groupId] = false;
      });
    } catch (e) {
      print('❌ [ManageGroupScreen] allFriends 포스트 로드 에러: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingGroupPosts[groupId] = false;
        _hasMoreGroupPosts[groupId] = false;
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

    // 🎯 빈 상태: SliverToBoxAdapter + 고정 height
    if (tiles.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: Center(
            child: Text(
              _searchQuery.isNotEmpty
                  ? context.tr('no_matching_members_or_groups')
                  : selectedGroup.isSystem == true
                  ? context.tr('no_friends_to_display')
                  : context
                      .tr('no_friends_in_group')
                      .replaceAll('{groupName}', selectedGroup.name),
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
        childAspectRatio: 0.82,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: _selectedPosts.isEmpty ? null : _changeSelectedPostsToPrivate,
          child: Text(
            textAlign: TextAlign.center,
            context
                .tr('change_to_private_selected_posts')
                .replaceAll('{count}', '${_selectedPosts.length}'),
            style: TextStyle(
              color:
                  _selectedPosts.isEmpty
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                      : Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight:
                  _selectedPosts.isEmpty ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // 🎯 선택된 포스트들을 나만보기로 일괄 변경
  Future<void> _changeSelectedPostsToPrivate() async {
    if (_selectedPosts.isEmpty) return;

    final postIdsToChange = _selectedPosts.toList();

    final confirmed = await DialogUtils.showConfirmDialog(
      context,
      title: context.tr('change_to_private'),
      message: context
          .tr('change_to_private_confirm')
          .replaceAll('{count}', '${postIdsToChange.length}'),
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

      final updatedPosts = await blogService.batchMakePostsPrivate(postIdsInt);

      if (mounted) {
        final currentGroup = _selectedGroup;
        if (currentGroup != null && currentGroup.id != -1) {
          final currentPosts = _groupPostsCache[currentGroup.id] ?? [];
          final updatedPostIds =
              updatedPosts.map((p) => p['id']?.toString()).toSet();

          setState(() {
            _groupPostsCache[currentGroup.id] =
                currentPosts
                    .where((post) => !updatedPostIds.contains(post.id))
                    .toList();
            _selectedPosts.clear();
            _isMultiSelectMode = false;
          });
        } else {
          setState(() {
            _selectedPosts.clear();
            _isMultiSelectMode = false;
          });
        }

        if (updatedPosts.isNotEmpty) {
          ErrorHandler.showInfo(
            context,
            context
                .tr('posts_changed_to_private')
                .replaceAll('{count}', '${updatedPosts.length}'),
          );
        } else {
          ErrorHandler.showError(
            context,
            context.tr('change_to_private_failed'),
          );
        }
      }
    } catch (e) {
      print('❌ [ManageGroupScreen] 포스트 나만보기 변경 에러: $e');
      if (mounted) {
        setState(() {
          _selectedPosts.clear();
          _isMultiSelectMode = false;
        });
        ErrorHandler.showError(context, context.tr('change_to_private_failed'));
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
    showModalBottomSheet(
      barrierColor: Colors.black.withOpacity(0.6),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => AddMemberBottomSheet(
            selectedGroup: _selectedGroup,
            onClose: () => Navigator.pop(context),
          ),
    ).then((_) {
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
        print(
          '🔄 [ManageGroupScreen] 친구 일괄 해제 시작: ${usernamesToRemove.length}명',
        );
        final friendProv = context.read<FriendProvider>();
        success = await friendProv.deleteFriendsBatch(usernamesToRemove);
      } else {
        if (!mounted) return;
        final groupProv = context.read<GroupProvider>();
        success = await groupProv.removeMembersBatch(
          _selectedGroup!.id,
          usernamesToRemove,
        );
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
      print('❌ [ManageGroupScreen] 일괄 작업 에러: $e');

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

  // 🎯 그룹 표시 이름 가져오기
  String _getGroupDisplayName(Group? group) {
    if (group == null) return '';
    if (group.isSystem == true) {
      return context.tr('all_friends');
    }
    return group.name;
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
    print('🟢 [ManageGroupScreen] _updateGroup 호출 시작');
    print('🟢 [ManageGroupScreen] name: $name');
    print('🟢 [ManageGroupScreen] description: $description');
    print('🟢 [ManageGroupScreen] imageUrl: $imageUrl');
    print(
      '🟢 [ManageGroupScreen] _selectedGroup: ${_selectedGroup?.name} (id: ${_selectedGroup?.id}, isSystem: ${_selectedGroup?.isSystem})',
    );

    if (_selectedGroup == null) {
      print('🟢 [ManageGroupScreen] _selectedGroup가 null, 종료');
      return;
    }

    // 🎯 전체 친구 그룹은 이름 수정 불가
    final bool isAllFriendsGroup = _selectedGroup!.isSystem == true;
    print('🟢 [ManageGroupScreen] isAllFriendsGroup: $isAllFriendsGroup');

    // 🎯 일반 그룹만 id 체크 (전체 친구 그룹은 id가 -1일 수도 있으므로 isSystem으로만 판단)
    if (!isAllFriendsGroup) {
      if (_selectedGroup!.id == -1) {
        print('🟢 [ManageGroupScreen] 일반 그룹인데 id가 -1, 종료');
        return;
      }
    }

    // 🎯 전체 친구 그룹은 이름 수정 불가
    if (isAllFriendsGroup) {
      if (name.trim().toLowerCase() != _selectedGroup!.name.toLowerCase()) {
        print(
          '🟢 [ManageGroupScreen] 이름 변경 시도 차단: $name != ${_selectedGroup!.name}',
        );
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
