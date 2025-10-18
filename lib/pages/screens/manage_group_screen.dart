import 'dart:ui' as ui;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../data/models/friend_model.dart';
import '../../../data/models/group_model.dart';
import '../../../providers/group_provider.dart';
import 'user_profile_screen.dart';

// 그룹 관리 화면 메인 위젯
class ManageGroupScreen extends StatefulWidget {
  final bool embedded; // Tab 내 임베드 시 true
  final String? filterText; // 상위에서 전달한 검색어로 그룹 필터
  const ManageGroupScreen({Key? key, this.embedded = false, this.filterText})
    : super(key: key);

  @override
  State<ManageGroupScreen> createState() => _ManageGroupScreenState();
}

class _ManageGroupScreenState extends State<ManageGroupScreen>
    with TickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _selectionAnimationController;
  late final AnimationController _loadingAnimationController;

  // 선택된 그룹 상태 (기본값: 전체 친구)
  Group? _selectedGroup;

  // 검색 관련 상태
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchExpanded = false;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

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

    // 첫 빌드 후 캐시 우선 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GroupProvider>().fetchMyGroups();
      // 친구 데이터도 함께 로드
      context.read<FriendProvider>().fetchAllFriendData();
    });
    // 0.5초 후 로딩 로고 표시
  }

  @override
  void dispose() {
    // ⚠️ 중요: 무한 반복 중인 애니메이션을 먼저 중지해야 Ticker 누수 방지
    _loadingAnimationController.stop();
    _loadingAnimationController.dispose();

    _scrollController.dispose();
    _selectionAnimationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,

      body: Consumer<GroupProvider>(
        builder: (context, groupProv, child) {
          return groupProv.isLoading
              ? Center(
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeIn,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "d",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        "ppy",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : Consumer<FriendProvider>(
                builder: (context, friendProv, child) {
                  return _buildMainContent(groupProv, friendProv);
                },
              );
        },
      ),
    );
  }

  Widget _buildMainContent(GroupProvider groupProv, FriendProvider friendProv) {
    List<Group> groups = groupProv.myGroups;

    // 전체 친구 가상 그룹 생성
    final allFriendsGroup = Group(
      id: -1, // 특별한 ID로 구분
      name: '전체 친구',
      description: '모든 친구',
      ownerId: 'system',
      owner: User(id: 0, username: 'system'),
      createdAt: DateTime.now(),
    );

    // 전체 친구 그룹을 맨 앞에 추가
    groups = [allFriendsGroup, ...groups];

    // 기본 선택을 전체 친구로 설정
    _selectedGroup ??= allFriendsGroup;

    // 검색 필터링 로직
    final filteredGroups = _filterGroups(groups, _searchQuery, friendProv);
    final List<Widget> slivers = [];
    final size = MediaQuery.of(context).size;
    final double friendsAreaH = size.height * (2 / 3); // flex 2

    // 상단 헤더는 단독 화면일 때만 포함(탭 임베드 시 상위 공통 AppBar 사용)
    if (!widget.embedded) {
      slivers.add(
        SliverAppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          floating: true,
          snap: true,
          expandedHeight: 60,

          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              // 그룹 드롭다운
              Expanded(child: _buildGroupDropdown(filteredGroups)),
              const SizedBox(width: 12),
              // 검색바
              // Expanded(child: _buildSearchBar()),
            ],
          ),
          centerTitle: false,
        ),
      );
    } else {
      // 임베드일 때는 상단 여백과 그룹 드롭다운 추가
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // 그룹 드롭다운
                Expanded(child: _buildGroupDropdown(filteredGroups)),
              ],
            ),
          ),
        ),
      );
    }

    // 하단: 친구들 (flex 2) - 검색 결과가 있을 때만 표시
    if (filteredGroups.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: friendsAreaH,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 30, 12, 16),
              child: _FriendsGrid(
                friendProv: friendProv,
                selectedGroup: _selectedGroup,
                groupProv: groupProv,
                searchQuery: _searchQuery,
              ),
            ),
          ),
        ),
      );
    } else if (_searchQuery.isNotEmpty) {
      // 검색 결과가 없을 때 메시지 표시
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  Text(
                    '해당하는 멤버나 그룹이 없어요',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final Widget body = GestureDetector(
      onTap: () {
        // 검색창이 열려있으면 닫기
        if (_isSearchExpanded) {
          _toggleSearch();
        }
        // 키보드 포커스 해제
        FocusScope.of(context).unfocus();
      },
      child: CustomScrollView(controller: _scrollController, slivers: slivers),
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          body,
          // 플로팅 액션 버튼
          _buildFloatingActionButton(),
        ],
      ),
    );
  }

  // 검색 필터링 로직

  // 그룹 드롭다운 위젯
  Widget _buildGroupDropdown(List<Group> groups) {
    return GestureDetector(
      onTap: () => _showGroupDropdown(groups),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const SizedBox(width: 8),
              // 그룹 이름
              Expanded(
                child: Text(
                  _selectedGroup?.name ?? '그룹 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Spacer(),
              Icon(
                Icons.keyboard_arrow_down,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 그룹 드롭다운 표시
  void _showGroupDropdown(List<Group> groups) {
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
              right: 20,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 현재 선택된 그룹 (헤더)
                          if (_selectedGroup != null)
                            _buildGroupDropdownItem(
                              group: _selectedGroup!,
                              isSelected: true,
                              onTap: () => Navigator.of(context).pop(),
                            ),

                          // 구분선
                          if (_selectedGroup != null)
                            Container(
                              height: 1,
                              margin: EdgeInsets.symmetric(horizontal: 16),
                              color: Colors.white.withOpacity(0.1),
                            ),

                          // 다른 그룹 목록
                          ...groups
                              .where((group) => group.id != _selectedGroup?.id)
                              .map(
                                (group) => _buildGroupDropdownItem(
                                  group: group,
                                  isSelected: false,
                                  onTap: () {
                                    setState(() {
                                      _selectedGroup = group;
                                    });
                                    // 선택 애니메이션 실행
                                    _selectionAnimationController
                                        .forward()
                                        .then((_) {
                                          _selectionAnimationController
                                              .reverse();
                                        });
                                    Navigator.of(context).pop();
                                  },
                                ),
                              )
                              .toList(),
                          _addGroupDropdownItem(
                            onTap: () => Navigator.of(context).pop(),
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
  Widget _buildGroupDropdownItem({
    required Group group,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color:
          isSelected
              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.1)
              : Theme.of(context).colorScheme.surface.withOpacity(0.8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.description,
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
              if (isSelected)
                Icon(
                  Icons.check,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 드롭다운 아이템 빌드
  Widget _addGroupDropdownItem({required VoidCallback onTap}) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '그룹 추가',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '새로운 그룹을 추가합니다',
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
                Icons.add,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
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

  // 플로팅 액션 버튼
  Widget _buildFloatingActionButton() {
    return Positioned(
      right: 10,
      bottom: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // + 버튼 (멤버 추가) - 전체 친구(-1) 선택 시 숨김
          if (_selectedGroup != null && _selectedGroup!.id != -1)
            GestureDetector(
              onTap: _showAddMemberBottomSheet,
              child: Container(
                width: 50,
                height: 50,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          // 검색 버튼
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 검색창 (확장 시에만 표시)
                if (_isSearchExpanded)
                  GestureDetector(
                    onTap: () {
                      // 검색창 클릭 시 이벤트 전파 방지 (닫히지 않도록)
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 280,
                      child: TextField(
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.8),
                        ),
                        cursorColor: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.8),
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.trim().toLowerCase();
                          });
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.transparent,
                          hintText: '그룹이나 친구를 검색해보세요',
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceVariant.withOpacity(0.6),
                            fontSize: 16,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 20,
                          ),
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(28)),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(28)),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(28)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 메인 검색 버튼
                GestureDetector(
                  onTap: _toggleSearch,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 300),
                      turns: 0.0,
                      child: Icon(
                        _isSearchExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.search,
                        color: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _AddMemberBottomSheet(
            selectedGroup: _selectedGroup,
            onClose: () => Navigator.pop(context),
          ),
    );
  }

  // 검색 토글
  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
    });

    if (_isSearchExpanded) {
      // 검색창이 확장되면 포커스
      Future.delayed(const Duration(milliseconds: 100), () {
        _searchFocusNode.requestFocus();
      });
    } else {
      // 검색창이 축소되면 포커스 해제 및 텍스트 초기화
      _searchFocusNode.unfocus();
      _searchController.clear();
      setState(() {
        _searchQuery = '';
      });
    }
  }
}

// 멤버 추가 바텀시트 위젯
class _AddMemberBottomSheet extends StatefulWidget {
  final Group? selectedGroup;
  final VoidCallback onClose;

  const _AddMemberBottomSheet({
    required this.selectedGroup,
    required this.onClose,
  });

  @override
  State<_AddMemberBottomSheet> createState() => _AddMemberBottomSheetState();
}

class _AddMemberBottomSheetState extends State<_AddMemberBottomSheet> {
  final Set<String> _selectedFriends = <String>{};
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border.all(color: Colors.white, width: 0.1),
            ),
            child: Column(
              children: [
                // 드래그 핸들
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 상단 타겟 그룹 UI
                _buildTargetGroupHeader(),
                // 검색바
                _buildSearchBar(),
                const SizedBox(height: 30),
                // 친구 그리드
                Expanded(child: _buildFriendsGrid()),
                // 하단 액션바
                _buildActionBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTargetGroupHeader() {
    if (widget.selectedGroup == null || widget.selectedGroup!.id == -1) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 멤버 아바타들 (겹쳐서 표시)

          // 그룹 이름
          Text(
            '${widget.selectedGroup!.name}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: '${widget.selectedGroup!.name}에 멤버 추가',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          suffixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsGrid() {
    final friendProv = context.watch<FriendProvider>();
    final groupProv = context.watch<GroupProvider>();

    if (widget.selectedGroup == null || widget.selectedGroup!.id == -1) {
      return Center(
        child: Text(
          '그룹을 선택해주세요',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
        ),
      );
    }

    final groupMembers = groupProv.membersOf(widget.selectedGroup!.id);
    final memberUsernames = groupMembers.map((m) => m.userId).toSet();
    final availableFriends =
        friendProv.acceptedFriends
            .where((f) => !memberUsernames.contains(f.username))
            .toList();

    if (availableFriends.isEmpty) {
      return Center(
        child: Text(
          '추가할 수 있는 친구가 없어요',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 6,
        childAspectRatio: 0.8,
      ),
      itemCount: availableFriends.length,
      itemBuilder: (context, index) {
        final friend = availableFriends[index];
        final isSelected = _selectedFriends.contains(friend.username);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedFriends.remove(friend.username);
              } else {
                _selectedFriends.add(friend.username);
              }
            });
          },
          child: Column(
            children: [
              Stack(
                children: [
                  CommonProfileAvatar(
                    imageUrl: friend.profileImageUrl,
                    username: friend.username,
                    size: 120,
                    borderWidth: isSelected ? 2 : 0,
                    borderColor:
                        isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.white.withOpacity(0.3),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.surface,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),

              Text(
                friend.username,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Done 버튼
          Expanded(
            child: ElevatedButton(
              onPressed:
                  _selectedFriends.isNotEmpty ? _addSelectedMembers : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.onSurface,
                foregroundColor: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Text(
                '추가하기 (${_selectedFriends.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addSelectedMembers() {
    final group = widget.selectedGroup;
    if (group == null || group.id == -1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('그룹을 먼저 선택해주세요')));
      return;
    }

    final groupProv = context.read<GroupProvider>();

    // 순차 추가(간단 구현). 필요 시 Future.wait로 병렬 처리 가능
    Future<void> run() async {
      int success = 0;
      for (final username in _selectedFriends) {
        final ok = await groupProv.addMember(group.id, username);
        if (ok) success++;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$success명의 멤버를 추가했습니다')));
        widget.onClose();
      }
    }

    run();
  }
}

// --- 하단 친구 그리드 (요청/대기/확정 순으로 정렬, 대기는 블러 처리) ---
class _FriendsGrid extends StatelessWidget {
  final FriendProvider friendProv;
  final Group? selectedGroup;
  final GroupProvider groupProv;
  final String searchQuery;
  const _FriendsGrid({
    required this.friendProv,
    required this.selectedGroup,
    required this.groupProv,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    List<Friend> accepted = friendProv.acceptedFriends;
    List<Friend> received = friendProv.receivedRequests; // 받은 요청(상단 우선)
    // List<Friend> sent = friendProv.sentRequests; // 내가 보낸 요청은 제외

    // 그룹이 선택된 경우 해당 그룹의 멤버만 필터링
    if (selectedGroup != null) {
      // 전체 친구 그룹인 경우 필터링하지 않음
      if (selectedGroup!.id != -1) {
        final groupMembers = groupProv.membersOf(selectedGroup!.id);
        final memberUsernames = groupMembers.map((m) => m.userId).toSet();

        accepted =
            accepted
                .where((f) => memberUsernames.contains(f.username))
                .toList();
        received =
            received
                .where((f) => memberUsernames.contains(f.username))
                .toList();
        // sent 상태는 제외
      }
      // selectedGroup.id == -1 (전체 친구)인 경우 모든 친구 표시
    }

    // 검색어가 있으면 친구 이름으로 필터링
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      accepted =
          accepted
              .where((f) => f.username.toLowerCase().contains(query))
              .toList();
      received =
          received
              .where((f) => f.username.toLowerCase().contains(query))
              .toList();
      // sent 상태는 제외
    }

    final List<_FriendTileData> tiles = [];
    for (final f in received) {
      tiles.add(
        _FriendTileData(
          username: f.username,
          url: f.profileImageUrl,
          state: _FriendState.requestReceived,
        ),
      );
    }
    // sent 상태는 제외
    for (final f in accepted) {
      tiles.add(
        _FriendTileData(
          username: f.username,
          url: f.profileImageUrl,
          state: _FriendState.accepted,
        ),
      );
    }

    if (tiles.isEmpty) {
      return Center(
        child: Text(
          selectedGroup != null
              ? '${selectedGroup!.name} 그룹에 친구가 없어요'
              : '표시할 친구가 없어요',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: tiles.length,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, i) {
        final t = tiles[i];
        return _FriendTile(data: t);
      },
    );
  }
}

enum _FriendState { requestReceived, accepted }

class _FriendTileData {
  final String username;
  final String? url;
  final _FriendState state;
  _FriendTileData({
    required this.username,
    required this.url,
    required this.state,
  });
}

class _FriendTile extends StatelessWidget {
  final _FriendTileData data;
  const _FriendTile({required this.data});

  static void _showFriendRequestBottomSheet(
    BuildContext context,
    String username,
  ) {
    // 받은 요청에서 해당 사용자의 프로필 이미지 URL 찾기
    final friendProvider = context.read<FriendProvider>();
    final receivedRequest =
        friendProvider.receivedRequests
            .where((friend) => friend.username == username)
            .firstOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
              child: _FriendRequestBottomSheet(
                username: username,
                profileImageUrl: receivedRequest?.profileImageUrl,
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final bool blur = data.state != _FriendState.accepted;

    Widget avatar = GestureDetector(
      onTap: () {
        if (data.state == _FriendState.requestReceived) {
          // 받은 요청인 경우 수락/거절 바텀시트 표시
          _showFriendRequestBottomSheet(context, data.username);
        } else {
          // 수락된 친구인 경우 프로필 화면으로 이동
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => UserProfileScreen(
                    otherUser: User(id: 0, username: data.username),
                  ),
            ),
          );
        }
      },
      child: CommonProfileAvatar(
        imageUrl: data.url,
        username: data.username,
        size: 120,
      ),
    );

    if (blur) {
      avatar = Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                data.state == _FriendState.requestReceived
                    ? Theme.of(context).colorScheme.primary
                    : Colors.pink.withOpacity(0.8),
            width: 2,
          ),
        ),
        child: ClipOval(
          child: Stack(alignment: Alignment.center, children: [avatar]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(height: 8),
        Text(
          data.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// 친구 요청 수락/거절 바텀시트
class _FriendRequestBottomSheet extends StatefulWidget {
  final String username;
  final String? profileImageUrl;

  const _FriendRequestBottomSheet({
    required this.username,
    this.profileImageUrl,
  });

  @override
  State<_FriendRequestBottomSheet> createState() =>
      _FriendRequestBottomSheetState();
}

class _FriendRequestBottomSheetState extends State<_FriendRequestBottomSheet> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4, // 화면 높이의 60%
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border.all(color: Colors.white, width: 0.1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 프로필 정보
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 30),
                      Text(
                        widget.username,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onBackground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '친구 요청을 수락할까요?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.onBackground.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: CommonProfileAvatar(
                    imageUrl: widget.profileImageUrl ?? '',
                    username: widget.username,
                    size: 120,
                  ),
                ),
              ],
            ),
            Expanded(child: SizedBox()),

            // 액션 버튼들
            Row(
              children: [
                // 거절 버튼
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _isProcessing
                            ? null
                            : () => _handleFriendRequest(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      foregroundColor:
                          Theme.of(context).colorScheme.onBackground,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        _isProcessing
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text(
                              '거절',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),

                const SizedBox(width: 6),

                // 수락 버튼
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _isProcessing ? null : () => _handleFriendRequest(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        _isProcessing
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Text(
                              '수락',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _handleFriendRequest(bool accept) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final friendProvider = context.read<FriendProvider>();
      bool success;

      if (accept) {
        success = await friendProvider.acceptFriendRequest(widget.username);
      } else {
        // 거절 기능이 없으면 단순히 false 반환
        success = false;
      }

      if (mounted) {
        Navigator.pop(context); // 바텀시트 닫기

        if (success) {
          // 친구 데이터 새로고침
          context.read<FriendProvider>().fetchAllFriendData(forceRefresh: true);
        } else {
          // 실패 메시지 표시
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '앗! 오류가 발생했어요.',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '앗! 오류가 발생했어요.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}
