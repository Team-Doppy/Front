import 'package:doppy/pages/components/card_view_shimmer.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/pages/components/group_sheet.dart'; // 🎯 GroupDropDown 사용
import 'package:doppy/pages/components/shimmer_box.dart'; // 🎯 ShimmerBox 추가
import 'package:doppy/pages/components/card_view.dart'; // 🎯 CardView 추가
import 'package:doppy/pages/components/add_member_bottom_sheet.dart'; // 🎯 AddMemberBottomSheet 추가
import 'package:doppy/pages/components/group_post_readers_bottom_sheet.dart'; // 🎯 GroupPostReadersBottomSheet 추가
import 'package:doppy/pages/components/friends_grid.dart'; // 🎯 FriendsGrid, FriendTile 추가
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart'; // 🎯 DialogUtils 추가
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../data/models/friend_model.dart';
import '../../../data/models/group_model.dart'; // GroupColorPalette 포함
import '../../../data/models/post_data.dart'; // 🎯 PostData 추가
import '../../../data/services/blog_service.dart'; // 🎯 BlogService 추가
import '../../../providers/group_provider.dart';

// 그룹 관리 화면 메인 위젯
class ManageGroupScreen extends StatefulWidget {
  final Group? selectedGroup; // 선택된 그룹
  final bool embedded; // Tab 내 임베드 시 true
  final String? filterText; // 상위에서 전달한 검색어로 그룹 필터

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
  late final ScrollController _scrollController;
  late final AnimationController _selectionAnimationController;
  late final AnimationController _loadingAnimationController;
  final GroupDropDown _groupDropDown = GroupDropDown(); // 🎯 GroupDropDown 인스턴스

  // 선택된 그룹 상태 (기본값: 전체 친구)
  Group? _selectedGroup;

  // 검색 관련 상태
  final TextEditingController _appbarSearchController =
      TextEditingController(); // 🎯 앱바 검색용
  String _searchQuery = '';
  bool _isAppbarSearchExpanded = false; // 🎯 앱바 검색 확장 여부
  final FocusNode _appbarSearchFocusNode = FocusNode(); // 🎯 앱바 검색 포커스

  // 🎯 다중 선택 모드
  bool _isMultiSelectMode = false;
  final Set<String> _selectedMembers = {};
  final Set<String> _selectedPosts = {}; // 🎯 선택된 포스트

  // 🎯 스크롤 컨트롤러 (앱바 상태 감지용)
  late final ScrollController _appBarScrollController;

  // 🎯 포스트/멤버 뷰 전환
  int _currentViewIndex = 0; // 0: 멤버, 1: 포스트

  // 🎯 그룹 포스트 관련 상태
  final Map<int, List<PostData>> _groupPostsCache = {}; // 그룹별 포스트 캐시
  final Map<int, bool> _isLoadingGroupPosts = {};
  final Map<int, int> _groupPostsPage = {};
  final Map<int, bool> _hasMoreGroupPosts = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _appBarScrollController = ScrollController();

    // 선택 애니메이션 컨트롤러 초기화
    _selectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 로딩 애니메이션 컨트롤러 초기화
    _loadingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(); // 무한 반복

    // 전달받은 그룹으로 초기화
    if (widget.selectedGroup != null) {
      _selectedGroup = widget.selectedGroup;
    }

    // 첫 빌드 후 캐시 우선 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final groupProv = context.read<GroupProvider>();
      final friendProv = context.read<FriendProvider>();

      // 🎯 그룹 목록 로드 (캐시 체크는 Provider 내부에서)
      groupProv.fetchMyGroups();

      // 🎯 선택된 그룹에 따라 필요한 데이터만 로드
      if (_selectedGroup == null || _selectedGroup!.id == -1) {
        // 전체 친구: 친구 데이터 로드 (캐시 체크)
        if (!friendProv.isLoading && friendProv.acceptedFriends.isEmpty) {
          friendProv.fetchAllFriendData();
        }
      } else {
        // 특정 그룹: 멤버 데이터 로드 (캐시 체크)
        if (!groupProv.isMembersCached(_selectedGroup!.id) &&
            !groupProv.isLoadingMembers(_selectedGroup!.id)) {
          groupProv.fetchGroupMembers(_selectedGroup!.id);
        }
      }
    });
  }

  @override
  void dispose() {
    // ⚠️ 중요: 무한 반복 중인 애니메이션을 먼저 중지해야 Ticker 누수 방지
    _loadingAnimationController.stop();
    _loadingAnimationController.dispose();

    _scrollController.dispose();
    _appBarScrollController.dispose();
    _selectionAnimationController.dispose();
    _appbarSearchController.dispose(); // 🎯 앱바 검색 컨트롤러 정리
    _appbarSearchFocusNode.dispose(); // 🎯 앱바 검색 포커스 정리
    _groupDropDown.dispose(); // 🎯 GroupDropDown 정리
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProv, child) {
        // 🎯 그룹 스키마 로딩 중
        if (groupProv.isLoading) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 300) {
                  Navigator.of(context).pop();
                }
              },
              child: DoppyLoadingLogo(
                showBackButton: true,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          );
        }

        // 🎯 선택된 그룹의 멤버 로딩 중은 Shimmer로 처리 (Scaffold 구조 유지)

        return Consumer<FriendProvider>(
          builder: (context, friendProv, child) {
            return _buildScaffold(groupProv, friendProv);
          },
        );
      },
    );
  }

  // 🎯 Scaffold 빌드
  Widget _buildScaffold(GroupProvider groupProv, FriendProvider friendProv) {
    final group = _selectedGroup;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Stack(
          children: [
            CustomScrollView(
              controller: _appBarScrollController,
              slivers: [
                // 🎯 앱바 (Sliver 구조)
                if (!widget.embedded)
                  SliverAppBar(
                    scrolledUnderElevation: 0,
                    pinned: true,
                    expandedHeight: 355,
                    toolbarHeight: MediaQuery.of(context).padding.top + 110,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: SafeArea(
                        bottom: false,
                        child: _buildAppBar(),
                      ),
                    ),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(0),
                      child: Container(
                        color: Theme.of(context).colorScheme.surface,

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isMultiSelectMode
                                        ? '${_selectedMembers.length} ${context.tr('selected')}'
                                        : _getGroupDisplayName(group),
                                    style: TextStyle(
                                      fontSize: 32,
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
                            SizedBox(height: 16),

                            Row(
                              children: [
                                const SizedBox(width: 22),
                                if (!_isAppbarSearchExpanded) ...[
                                  _buildViewToggle(),
                                  const Spacer(),
                                ],

                                if (_isAppbarSearchExpanded)
                                  Expanded(child: _buildExpandedSearchField())
                                else
                                  _buildCollapsedSearchField(),

                                _buildMultiSelectButton(),
                                const SizedBox(width: 10),
                              ],
                            ),
                            SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 🎯 Body 내용 (Sliver 구조)
                ..._buildBodySlivers(groupProv, friendProv),
                // 🎯 다중 선택 모드일 때 패딩 추가 (바텀바 공간 확보)
                if (_isMultiSelectMode)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 80,
                    ),
                  ),
              ],
            ),
            // 뒤로가기 버튼 (왼쪽 위 고정)
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
            // 🎯 멤버 추가 버튼 (pen 아이콘 왼쪽)
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
            // 🎯 편집 버튼 (pen 아이콘) - 다중 선택 모드일 때 숨김
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
            // 🎯 다중 선택 모드 하단 액션바 (고정) - 멤버 뷰일 때만
            if (_isMultiSelectMode && _currentViewIndex == 0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildMultiSelectActionBar(),
              ),
            // 🎯 포스트 다중 선택 모드 하단 액션바 (고정)
            if (_isMultiSelectMode && _currentViewIndex == 1)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildPostMultiSelectActionBar(),
              ),
          ],
        ),
      ),
    );
  }

  // 🎯 앱바 위젯 - 그룹에 공유한 포스트 가로 스크롤
  Widget _buildAppBar() {
    final group = _selectedGroup;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 상단 네비게이션 바 (뒤로가기 버튼)
        const SizedBox(height: 100),
        if (group != null)
          Container(
            margin: const EdgeInsets.only(left: 20),
            width: 100,
            height: 100,
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
                        group.profileImageUrl != null &&
                                group.profileImageUrl!.isNotEmpty
                            ? Image.network(
                              group.profileImageUrl!,
                              fit: BoxFit.cover,
                              width: 100,
                              height: 100,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildGroupAvatarPlaceholder(group);
                              },
                            )
                            : _buildGroupAvatarPlaceholder(group),
                  ),
                ),
                // 시스템 그룹인 경우 중앙에 아이콘
                if (group.isSystem == true)
                  Center(
                    child: Image.asset(
                      'assets/images/doppy_nobg.png',
                      width: 30,
                      height: 30,
                      color: Colors.white,
                      fit: BoxFit.contain,
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(height: 20),
        if (group?.description != null || group?.memberCount != null)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              () {
                final desc = group?.description;
                final count = group?.memberCount;
                final hasDesc = desc != null && desc.isNotEmpty;
                final hasCount = count != null;

                if (hasDesc && hasCount) {
                  return '$desc · $count';
                } else if (hasCount) {
                  return '$count ${context.tr('members')}';
                }
                return '';
              }(),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: -0.2,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // 🎯 Body 위젯 (Sliver 리스트 반환)
  List<Widget> _buildBodySlivers(
    GroupProvider groupProv,
    FriendProvider friendProv,
  ) {
    List<Group> groups = groupProv.myGroups;

    // 서버에서 받은 그룹 목록 사용 (전체 친구 그룹 포함)
    final previousGroup = _selectedGroup;

    // 🎯 _selectedGroup이 없으면 첫 번째 그룹으로 설정
    if (_selectedGroup == null) {
      _selectedGroup = groups.firstOrNull;
    } else {
      // 🎯 _selectedGroup이 있으면 Provider의 최신 정보로 동기화
      final updatedGroup = groups.firstWhere(
        (g) => g.id == _selectedGroup!.id,
        orElse: () => _selectedGroup!,
      );
      // 그룹 정보가 변경되었으면 업데이트
      if (updatedGroup.name != _selectedGroup!.name ||
          updatedGroup.description != _selectedGroup!.description ||
          updatedGroup.profileImageUrl != _selectedGroup!.profileImageUrl ||
          updatedGroup.memberCount != _selectedGroup!.memberCount) {
        _selectedGroup = updatedGroup;
      }
    }

    // 🎯 그룹이 변경되었을 때 데이터 로딩
    if (previousGroup?.id != _selectedGroup?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _onGroupChanged(previousGroup, _selectedGroup, groupProv, friendProv);
      });
    }

    final filteredGroups = _filterGroups(groups, _searchQuery, friendProv);

    return _buildFriendsListSlivers(friendProv, groupProv, filteredGroups);
  }

  // 🎯 그룹 변경 시 데이터 로딩 최적화
  void _onGroupChanged(
    Group? previousGroup,
    Group? newGroup,
    GroupProvider groupProv,
    FriendProvider friendProv,
  ) {
    if (newGroup == null) return;

    // 🎯 멤버 뷰일 때: 멤버 데이터 로드
    if (_currentViewIndex == 0) {
      if (newGroup.id == -1) {
        // 전체 친구: 친구 데이터 로드 (캐시 체크: acceptedFriends가 비어있지 않으면 캐시됨)
        if (!friendProv.isLoading && friendProv.acceptedFriends.isEmpty) {
          friendProv.fetchAllFriendData();
        }
      } else {
        // 특정 그룹: 멤버 데이터 로드
        if (!groupProv.isMembersCached(newGroup.id) &&
            !groupProv.isLoadingMembers(newGroup.id)) {
          groupProv.fetchGroupMembers(newGroup.id);
        }
      }
    }

    // 🎯 포스트 뷰일 때: 포스트 데이터 로드
    if (_currentViewIndex == 1 && newGroup.id != -1) {
      final posts = _groupPostsCache[newGroup.id] ?? [];
      final isLoading = _isLoadingGroupPosts[newGroup.id] ?? false;
      final hasMore =
          _hasMoreGroupPosts[newGroup.id] ?? true; // 기본값은 true (첫 로드 시)
      // 🎯 포스트가 비어있고, 로딩 중이 아니고, 더 불러올 게 있을 때만 로드
      if (posts.isEmpty && !isLoading && hasMore) {
        _loadGroupPosts(newGroup.id);
      }
    }
  }

  // 🎯 그룹 아바타 플레이스홀더 (프로필 이미지 없을 때)
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
      ),
    );
  }

  // 🎯 접혀있는 검색 필드 (아이콘 버튼)
  Widget _buildCollapsedSearchField() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isAppbarSearchExpanded = true;
        });

        // 🎯 검색 필드 확장 시 앱바 부드럽게 콜랩스
        if (_appBarScrollController.hasClients) {
          final expandedHeight = 350.0;
          final toolbarHeight = MediaQuery.of(context).padding.top + 120.0;
          final scrollOffset = expandedHeight - toolbarHeight;

          _appBarScrollController.animateTo(
            scrollOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }

        Future.delayed(const Duration(milliseconds: 100), () {
          _appbarSearchFocusNode.requestFocus();
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
      duration: const Duration(milliseconds: 300),
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
          height: 1.0, // 🎯 텍스트 높이 정확히 맞추기
        ),
        cursorColor: Theme.of(context).colorScheme.onSurface,
        textAlignVertical: TextAlignVertical.center,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: context.tr('search_members'),
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            fontSize: 14,
            height: 1.0, // 🎯 힌트 텍스트 높이 정확히 맞추기
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
              setState(() {
                _searchQuery = '';
                _isAppbarSearchExpanded = false;
              });
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
          isDense: true, // 🎯 간격 최소화로 정확한 중앙 정렬
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0, // 🎯 세로 패딩 제거 (textAlignVertical.center가 처리)
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

  // 🎯 뷰 전환 시 데이터 로딩 최적화
  void _onViewIndexChanged(int newIndex) {
    final group = _selectedGroup;
    final groupProv = context.read<GroupProvider>();
    final friendProv = context.read<FriendProvider>();

    if (newIndex == 1 && _currentViewIndex == 0) {
      // 멤버 뷰 → 포스트 뷰: 포스트 데이터 로드
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
      // 포스트 뷰 → 멤버 뷰: 멤버 데이터 로드
      if (group != null) {
        if (group.id == -1) {
          // 전체 친구: 친구 데이터 로드 (캐시 체크: acceptedFriends가 비어있지 않으면 캐시됨)
          if (!friendProv.isLoading && friendProv.acceptedFriends.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                friendProv.fetchAllFriendData();
              }
            });
          }
        } else {
          // 특정 그룹: 멤버 데이터 로드
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

  // 🎯 다중 선택 버튼 위젯
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
    List<Group> filteredGroups,
  ) {
    if (filteredGroups.isEmpty && _searchQuery.isNotEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              context.tr('no_matching_members_or_groups'),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        ),
      ];
    }

    if (filteredGroups.isEmpty) {
      return [];
    }

    // 현재 선택된 뷰에 따라 다른 위젯 렌더링
    if (_currentViewIndex == 0) {
      // 멤버 뷰
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
          sliver: _buildFriendsSliverGrid(
            friendProv,
            groupProv,
            filteredGroups.first,
          ),
        ),
      ];
    } else {
      // 포스트 뷰
      return _buildPostsViewSlivers(filteredGroups.first);
    }
  }

  // 🎯 포스트 뷰 빌드 (Sliver 리스트)
  List<Widget> _buildPostsViewSlivers(Group selectedGroup) {
    final groupId = selectedGroup.id;
    final posts = _groupPostsCache[groupId] ?? [];
    final isLoading = _isLoadingGroupPosts[groupId] ?? false;
    final hasMore = _hasMoreGroupPosts[groupId] ?? true; // 기본값은 true (첫 로드 시)

    // 🎯 그룹 포스트 로드 (빌드 메서드 외부에서 처리)
    // 🎯 포스트가 비어있고, 로딩 중이 아니고, 더 불러올 게 있을 때만 로드
    if (posts.isEmpty && !isLoading && hasMore && groupId != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedGroup?.id == groupId) {
          _loadGroupPosts(groupId);
        }
      });
    }

    if (isLoading && posts.isEmpty) {
      // 🎯 Shimmer로 포스트 카드 UI 유지
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12.0, 24.0, 12.0, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: CardViewShimmer(),
                );
              },
              childCount: 5, // 5개의 shimmer 카드 표시
            ),
          ),
        ),
      ];
    }

    // 🎯 검색 결과가 적어도 일정 높이 유지
    if (posts.isEmpty) {
      // 🎯 빈 상태: 고정 높이로 상하 간격 보장 (키보드 영향 받지 않음)
      return [
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.4, // 화면 높이의 40%
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Text(
                  context.tr('no_posts_in_group'),
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
        ),
      ];
    }

    // 🎯 포스트가 있을 때: SliverFillRemaining 사용
    return [
      SliverFillRemaining(
        hasScrollBody: true,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12.0, 24.0, 12.0, 30),
          itemCount: posts.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12.0),
          itemBuilder: (context, index) {
            final post = posts[index];
            final isSelected = _selectedPosts.contains(post.id);

            return Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isMultiSelectMode) {
                      // 다중 선택 모드: 선택/해제
                      setState(() {
                        if (isSelected) {
                          _selectedPosts.remove(post.id);
                        } else {
                          _selectedPosts.add(post.id);
                        }
                      });
                    } else {
                      // 일반 모드: 바텀시트 표시
                      _showGroupPostReadersBottomSheet(post);
                    }
                  },
                  child: CardView(
                    post: post,
                    isLast: index == posts.length - 1,
                    isFirst: index == 0,
                  ),
                ),
                // 🎯 다중 선택 모드일 때 원형 체크 버튼 (왼쪽)
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
          },
        ),
      ),
    ];
  }

  // 🎯 그룹 포스트 로드
  Future<void> _loadGroupPosts(int groupId) async {
    // 🎯 이미 로딩 중이거나 더 이상 불러올 게 없으면 리턴
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

      // 🎯 더 이상 불러올 게 없으면 (포스트가 10개 미만이면 마지막 페이지)
      final hasMore = newPosts.length >= 10;

      if (!mounted) return;
      setState(() {
        final existingPosts = _groupPostsCache[groupId] ?? [];
        _groupPostsCache[groupId] = [...existingPosts, ...newPosts];
        _hasMoreGroupPosts[groupId] = hasMore; // 명확히 false로 설정
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
        // 에러 발생 시에도 더 이상 시도하지 않도록 false로 설정
        _hasMoreGroupPosts[groupId] = false;
      });
    }
  }

  // 🎯 SliverGrid 빌드
  Widget _buildFriendsSliverGrid(
    FriendProvider friendProv,
    GroupProvider groupProv,
    Group selectedGroup,
  ) {
    // 🎯 멤버 데이터 사전 로드 (캐시되어 있지 않으면)
    if (selectedGroup.id != -1 &&
        !groupProv.isMembersCached(selectedGroup.id) &&
        !groupProv.isLoadingMembers(selectedGroup.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedGroup?.id == selectedGroup.id) {
          groupProv.fetchGroupMembers(selectedGroup.id);
        }
      });
    }

    // 🎯 멤버 로딩 중: Shimmer로 그리드 UI 유지
    if (selectedGroup.id != -1 &&
        groupProv.isLoadingMembers(selectedGroup.id) &&
        !groupProv.isMembersCached(selectedGroup.id)) {
      return _buildMembersShimmer();
    }

    List<Friend> accepted = friendProv.acceptedFriends;
    List<Friend> received = friendProv.receivedRequests;

    // 🎯 전체 친구 그룹인지 확인 (isSystem == true 또는 이름이 "allFriends")
    final isAllFriendsGroup =
        selectedGroup.isSystem == true ||
        selectedGroup.name.toLowerCase() == 'allfriends';

    // 그룹이 선택된 경우 해당 그룹의 멤버만 필터링
    if (!isAllFriendsGroup) {
      final groupMembers = groupProv.membersOf(selectedGroup.id);
      final memberUsernames = groupMembers.map((m) => m.userId).toSet();

      accepted =
          accepted.where((f) => memberUsernames.contains(f.username)).toList();
      received =
          received.where((f) => memberUsernames.contains(f.username)).toList();
    } else {
      // 🎯 전체 친구 그룹에서는 받은 요청 제외 (수락된 친구만 표시)
      received = [];
    }

    // 검색어가 있으면 필터링
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
    // 🎯 전체 친구 그룹이 아닌 경우에만 받은 요청 추가
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

    // 🎯 검색 결과가 적어도 일정 높이 유지
    if (tiles.isEmpty) {
      // 🎯 빈 상태: 고정 높이로 상하 간격 보장 (키보드 영향 받지 않음)
      return SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.4, // 화면 높이의 40%
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                selectedGroup.id != -1
                    ? context
                        .tr('no_friends_in_group')
                        .replaceAll('{groupName}', selectedGroup.name)
                    : context.tr('no_friends_to_display'),
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
      );
    }

    // 🎯 친구가 있을 때: SliverFillRemaining 사용
    return SliverFillRemaining(
      hasScrollBody: true,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12.0, 24.0, 12.0, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 50,
          crossAxisSpacing: 6,
          childAspectRatio: 0.82,
        ),
        itemCount: tiles.length,
        itemBuilder: (context, index) {
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
        },
      ),
    );
  }

  // 🎯 멤버 그리드 Shimmer 빌드
  Widget _buildMembersShimmer() {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 50,
          crossAxisSpacing: 6,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 프로필 원형 Shimmer
                ShimmerBox(
                  width: 130,
                  height: 130,
                  shape: const CircleBorder(),
                ),
                const SizedBox(height: 8),
                // 이름 Shimmer
                ShimmerBox(
                  width: 80,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                // 별명 Shimmer (선택적)
                ShimmerBox(
                  width: 60,
                  height: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          },
          childCount: 9, // 9개의 shimmer 아이템 표시
        ),
      ),
    );
  }

  // 검색 필터링 로직
  List<Group> _filterGroups(
    List<Group> groups,
    String query,
    FriendProvider friendProv,
  ) {
    if (query.isEmpty) {
      return groups;
    }

    final filteredGroups = <Group>[];

    for (final group in groups) {
      // 1. 그룹 이름으로 검색
      if (group.name.toLowerCase().contains(query)) {
        filteredGroups.add(group);
        continue;
      }

      // 2. 사용자 이름으로 검색 (해당 사용자가 포함된 그룹 찾기)
      // 모든 친구 상태(확정, 받은 요청, 보낸 요청)를 검색 대상에 포함
      final allFriends = [
        ...friendProv.acceptedFriends,
        ...friendProv.receivedRequests,
        ...friendProv.sentRequests,
      ];

      final matchingFriends =
          allFriends
              .where((friend) => friend.username.toLowerCase().contains(query))
              .toList();

      if (matchingFriends.isNotEmpty) {
        // 전체 친구 그룹인 경우
        if (group.id == -1) {
          filteredGroups.add(group);
        } else {
          // 특정 그룹에 해당 사용자가 있는지 확인
          final groupMembers = context.read<GroupProvider>().membersOf(
            group.id,
          );
          final memberUsernames = groupMembers.map((m) => m.userId).toSet();

          final hasMatchingMember = matchingFriends.any(
            (friend) => memberUsernames.contains(friend.username),
          );

          if (hasMatchingMember) {
            filteredGroups.add(group);
          }
        }
      }
    }

    // 검색 결과가 없으면 빈 리스트 반환 (아무것도 표시하지 않음)
    return filteredGroups;
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

  // 🎯 선택된 포스트들을 나만보기로 일괄 변경 (배치 API 사용)
  Future<void> _changeSelectedPostsToPrivate() async {
    if (_selectedPosts.isEmpty) return;

    final postIdsToChange = _selectedPosts.toList();

    // 확인 다이얼로그
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

      // 🎯 문자열 postId를 int로 변환
      final postIdsInt =
          postIdsToChange
              .map((id) => int.tryParse(id))
              .where((id) => id != null)
              .cast<int>()
              .toList();

      if (postIdsInt.isEmpty) {
        throw Exception('유효한 포스트 ID가 없습니다');
      }

      // 🎯 배치 API 호출
      final updatedPosts = await blogService.batchMakePostsPrivate(postIdsInt);

      if (mounted) {
        // 🎯 그룹 포스트 캐시에서 업데이트된 포스트 제거 (나만보기로 변경되었으므로 그룹 포스트 목록에서 사라짐)
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
    // 전체 친구 탭인지 확인
    final isAllFriendsTab = _selectedGroup == null || _selectedGroup!.id == -1;

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
    // 바텀시트 열기 전에 해당 그룹 멤버 최신화
    if (_selectedGroup != null && _selectedGroup!.id != -1) {
      // 캐시 유효 시 내부에서 네트워크 호출을 생략함
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
      // 🎯 바텀시트 닫힐 때 키보드도 함께 닫기
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  // 🎯 선택된 멤버들을 그룹에서 제거 또는 친구 해제 (배치 API 사용)
  Future<void> _removeSelectedMembers() async {
    if (_selectedMembers.isEmpty) {
      return;
    }

    final usernamesToRemove = _selectedMembers.toList();

    // 🎯 전체 친구 탭인지 확인
    final isAllFriendsTab = _selectedGroup == null || _selectedGroup!.id == -1;

    // 이중 확인 다이얼로그
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
        // 🎯 전체 친구: 친구 일괄 해제
        if (!mounted) return;
        print(
          '🔄 [ManageGroupScreen] 친구 일괄 해제 시작: ${usernamesToRemove.length}명',
        );
        final friendProv = context.read<FriendProvider>();
        success = await friendProv.deleteFriendsBatch(usernamesToRemove);
      } else {
        // 🎯 특정 그룹: 그룹에서 멤버 일괄 제거
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
          _isMultiSelectMode = false; // 삭제 후 다중 선택 모드 해제
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

  // 🎯 그룹 수정 바텀시트 (그룹 생성 바텀시트 재활용)
  void _showEditGroupSheet() {
    if (_selectedGroup == null) return;

    _groupDropDown.showGroupDropdown(
      context,
      GlobalKey(),
      [], // 그룹 목록 불필요 (수정 모드)
      null,
      (group) {}, // 그룹 선택 콜백 불필요
      (name, description, imageUrl) =>
          _updateGroup(name, description, imageUrl),
      startWithCreate: true, // 그룹 수정 UI 바로 표시
      editMode: true, // 🎯 수정 모드
      initialName: _selectedGroup!.name, // 🎯 기존 그룹 이름
      initialDescription: _selectedGroup!.description, // 🎯 기존 설명
      initialImageUrl: _selectedGroup!.profileImageUrl, // 🎯 기존 이미지
      onDeleteGroup:
          (_selectedGroup!.id != -1 && _selectedGroup!.isSystem != true)
              ? _deleteGroup
              : null, // 🎯 시스템 그룹은 삭제 불가
    );
  }

  // 🎯 그룹 표시 이름 가져오기
  String _getGroupDisplayName(Group? group) {
    if (group == null) return '';
    // 🎯 시스템 그룹이거나 이름이 "allFriends"인 경우 "전체 친구"로 표시
    if (group.isSystem == true || group.name.toLowerCase() == 'allfriends') {
      return context.tr('all_friends');
    }
    return group.name;
  }

  // 🎯 그룹 삭제
  Future<void> _deleteGroup() async {
    // 🎯 시스템 그룹이거나 id가 -1인 경우 삭제 불가
    if (_selectedGroup == null ||
        _selectedGroup!.id == -1 ||
        _selectedGroup!.isSystem == true) {
      return;
    }

    final groupProv = context.read<GroupProvider>();

    try {
      await groupProv.deleteGroup(_selectedGroup!.id);

      if (mounted) {
        // 삭제 성공 시 이전 화면으로 돌아가기
        Navigator.of(context).pop();

        ErrorHandler.showInfo(context, context.tr('group_deleted'));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, context.tr('group_delete_failed'));
      }
    }
  }

  // 🎯 그룹 정보 업데이트
  Future<void> _updateGroup(
    String name,
    String? description,
    String? imageUrl,
  ) async {
    if (_selectedGroup == null || _selectedGroup!.id == -1) return;
    if (name.trim().isEmpty) return;

    try {
      final groupProvider = context.read<GroupProvider>();

      // 그룹 업데이트
      final success = await groupProvider.updateGroup(
        _selectedGroup!.id,
        name.trim(),
        description ?? '',
        profileImageUrl: imageUrl,
      );

      if (success) {
        // 🎯 Provider에서 최신 그룹 정보 가져와서 동기화
        // 🎯 GroupProvider.updateGroup이 이미 notifyListeners()를 호출하므로
        // group_selection_screen.dart도 자동으로 업데이트됨
        final updatedGroups = groupProvider.myGroups;
        final updatedGroup = updatedGroups.firstWhere(
          (g) => g.id == _selectedGroup!.id,
          orElse: () => _selectedGroup!,
        );

        // 로컬 상태 업데이트 (Provider의 최신 정보 사용)
        if (mounted) {
          setState(() {
            _selectedGroup = updatedGroup;
          });
        }

        if (mounted) {
          ErrorHandler.showInfo(context, context.tr('group_name_updated'));
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
