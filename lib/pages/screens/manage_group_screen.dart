import 'dart:ui' as ui;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/theme/app_text_styles.dart';
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
  late final ScrollController _groupScrollController;
  late final AnimationController _selectionAnimationController;
  late final Animation<double> _selectionAnimation;

  // 그룹 버블 크기 상수
  static const double _groupBubbleSize = 200.0;

  // 선택된 그룹 상태 (기본값: 전체 친구)
  Group? _selectedGroup;
  List<Group> _groups = [];

  // 플로팅 액션 버튼 상태
  bool _isFloatingMenuOpen = false;

  // 검색 관련 상태
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _groupScrollController = ScrollController();

    // 선택 애니메이션 컨트롤러 초기화
    _selectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _selectionAnimation = CurvedAnimation(
      parent: _selectionAnimationController,
      curve: Curves.easeInOut,
    );

    // 그룹 스크롤 리스너 추가
    _groupScrollController.addListener(_onGroupScroll);

    // 첫 빌드 후 캐시 우선 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GroupProvider>().fetchMyGroups();
      // 친구 데이터도 함께 로드
      context.read<FriendProvider>().fetchAllFriendData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _groupScrollController.dispose();
    _selectionAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // 그룹 스크롤 리스너
  void _onGroupScroll() {
    if (!_groupScrollController.hasClients || _groups.isEmpty) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = _groupBubbleSize + 16; // 버블 크기 + 패딩
    final centerOffset = _groupScrollController.offset + (screenWidth / 2);

    // 중앙 계산 - 오른쪽으로 치우치지 않도록 조정
    final centerIndex =
        ((centerOffset + (itemWidth / 2)) / itemWidth).round() - 1;

    if (centerIndex >= 0 && centerIndex < _groups.length) {
      final centerGroup = _groups[centerIndex];
      if (_selectedGroup?.id != centerGroup.id) {
        setState(() {
          _selectedGroup = centerGroup;
        });
        // 선택 애니메이션 실행
        _selectionAnimationController.forward().then((_) {
          _selectionAnimationController.reverse();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupProv = context.watch<GroupProvider>();
    final friendProv = context.watch<FriendProvider>();
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

    // 그룹 리스트 업데이트
    _groups = groups;

    // 기본 선택을 전체 친구로 설정
    if (_selectedGroup == null) {
      _selectedGroup = allFriendsGroup;
    }

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
          title: Row(children: [Expanded(child: _buildSearchBar())]),
          centerTitle: false,
        ),
      );
    } else {
      // 임베드일 때는 상단 여백만 살짝 추가
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }

    // 상단: 그룹 (타이트한 고정 높이)
    slivers.add(
      SliverToBoxAdapter(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child:
              groupProv.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: SizedBox(
                      height: _groupBubbleSize, // 버블 크기 + 여백
                      child: ListView.builder(
                        controller: _groupScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredGroups.length,
                        itemBuilder: (context, index) {
                          final group = filteredGroups[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: DragTarget<String>(
                              builder: (context, candidate, rejected) {
                                final bool isHover = candidate.isNotEmpty;
                                return _AnimatedStaggered(
                                  index: index,
                                  child: AnimatedBuilder(
                                    animation: _selectionAnimation,
                                    builder: (context, child) {
                                      final isSelected =
                                          _selectedGroup?.id == group.id;
                                      final opacity =
                                          isSelected
                                              ? 1.0 -
                                                  (_selectionAnimation.value *
                                                      0.3)
                                              : 1.0;

                                      return AnimatedOpacity(
                                        opacity: opacity,
                                        duration: const Duration(
                                          milliseconds: 150,
                                        ),
                                        child: _GroupBubble(
                                          group: group,
                                          size: _groupBubbleSize,
                                          overlayGlow: isHover,
                                          isSelected: isSelected,
                                          onOpen: () {
                                            // 그룹을 가운데로 스크롤
                                            final targetIndex = filteredGroups
                                                .indexWhere(
                                                  (g) => g.id == group.id,
                                                );
                                            if (targetIndex != -1) {
                                              final targetOffset =
                                                  (targetIndex *
                                                      (_groupBubbleSize + 16)) -
                                                  (MediaQuery.of(
                                                            context,
                                                          ).size.width -
                                                          _groupBubbleSize) /
                                                      2;
                                              _groupScrollController.animateTo(
                                                targetOffset.clamp(
                                                  0.0,
                                                  _groupScrollController
                                                      .position
                                                      .maxScrollExtent,
                                                ),
                                                duration: const Duration(
                                                  milliseconds: 500,
                                                ),
                                                curve: Curves.easeInOut,
                                              );
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                              onWillAccept:
                                  (data) => data != null && data.isNotEmpty,
                              onAccept: (username) async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '$username 님을 "${group.name}"에 추가합니다',
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
        ),
      ),
    );

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
            height: 100,

            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
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
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Widget body = CustomScrollView(
      controller: _scrollController,
      slivers: slivers,
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          body,
          // 배경 클릭 감지
          if (_isFloatingMenuOpen)
            GestureDetector(
              onTap: _toggleFloatingMenu,
              child: Container(
                color: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          // 플로팅 액션 버튼
          _buildFloatingActionButton(),
        ],
      ),
    );
  }

  // 검색 바 위젯
  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textAlignVertical: TextAlignVertical.center,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          hintText: '무엇이든 검색해보세요',
          hintStyle: AppTextStyles.bodyLarge.copyWith(
            color: const Color(0xFF989898),
          ),

          suffixIcon: IconButton(
            tooltip: '검색',
            onPressed: () {
              FocusScope.of(context).unfocus();
              //
            },
            icon: const Icon(Icons.search, color: Color(0xFF989898), size: 22),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 16,
          ),

          isDense: true,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(30)),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.secondary,
            ),
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
      final matchingFriends =
          friendProv.acceptedFriends
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

  // 멤버 추가 바텀시트 표시
  void _showAddMemberBottomSheet() {
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

  // 플로팅 액션 버튼
  Widget _buildFloatingActionButton() {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 그룹 추가 버튼
          AnimatedOpacity(
            opacity: _isFloatingMenuOpen ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: _isFloatingMenuOpen ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: _onAddGroup,
                  child: FloatingActionButton(
                    heroTag: "add_group",
                    mini: true,
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    onPressed: null, // GestureDetector가 처리하므로 null
                    child: Icon(
                      Icons.group_add,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 멤버 추가 버튼
          AnimatedOpacity(
            opacity: _isFloatingMenuOpen ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: _isFloatingMenuOpen ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: _onAddMember,
                  child: FloatingActionButton(
                    heroTag: "add_member",
                    mini: true,
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    onPressed: null, // GestureDetector가 처리하므로 null
                    child: Icon(
                      Icons.person_add,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 메인 + 버튼
          GestureDetector(
            onTap: _toggleFloatingMenu,
            child: FloatingActionButton(
              heroTag: "main_fab",
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              onPressed: null, // GestureDetector가 처리하므로 null
              child: AnimatedRotation(
                turns: _isFloatingMenuOpen ? 0.125 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _isFloatingMenuOpen ? Icons.close : Icons.add,
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 플로팅 메뉴 토글
  void _toggleFloatingMenu() {
    setState(() {
      _isFloatingMenuOpen = !_isFloatingMenuOpen;
    });
  }

  // 그룹 추가 처리
  void _onAddGroup() {
    _toggleFloatingMenu();
    // TODO: 그룹 추가 로직 구현
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('그룹 추가 기능을 구현해주세요')));
  }

  // 멤버 추가 처리
  void _onAddMember() {
    _toggleFloatingMenu();
    if (_selectedGroup != null) {
      _showAddMemberBottomSheet();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('그룹을 먼저 선택해주세요')));
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
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const ui.Color.fromARGB(194, 41, 41, 41),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 그룹 멤버 아바타들 (겹쳐서 표시)

          // 그룹 이름
          Text(
            widget.selectedGroup!.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 서브텍스트
          Text(
            '${widget.selectedGroup!.description}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
          suffixIcon: Icon(Icons.mic, color: Colors.white.withOpacity(0.7)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 15,
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
                  borderRadius: BorderRadius.circular(12),
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
    // TODO: 선택된 멤버들을 그룹에 추가하는 로직 구현
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_selectedFriends.length}명의 멤버를 추가했습니다')),
    );
    widget.onClose();
  }
}

// --- 하단 친구 그리드 (요청/대기/확정 순으로 정렬, 대기는 블러 처리) ---
class _FriendsGrid extends StatelessWidget {
  final FriendProvider friendProv;
  final Group? selectedGroup;
  final GroupProvider groupProv;
  const _FriendsGrid({
    required this.friendProv,
    required this.selectedGroup,
    required this.groupProv,
  });

  @override
  Widget build(BuildContext context) {
    List<Friend> accepted = friendProv.acceptedFriends;
    List<Friend> received = friendProv.receivedRequests; // 받은 요청(상단 우선)
    List<Friend> sent = friendProv.sentRequests; // 내가 보낸 요청(대기)

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
        sent = sent.where((f) => memberUsernames.contains(f.username)).toList();
      }
      // selectedGroup.id == -1 (전체 친구)인 경우 모든 친구 표시
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
    for (final f in sent) {
      tiles.add(
        _FriendTileData(
          username: f.username,
          url: f.profileImageUrl,
          state: _FriendState.pending,
        ),
      );
    }
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

enum _FriendState { requestReceived, pending, accepted }

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

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final bool blur = data.state != _FriendState.accepted;
    final String label =
        data.state == _FriendState.requestReceived
            ? '요청받음'
            : (data.state == _FriendState.pending ? '대기중' : '');

    Widget avatar = GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => UserProfileScreen(
                  otherUser: User(id: 0, username: data.username),
                ),
          ),
        );
      },
      child: CommonProfileAvatar(
        imageUrl: data.url,
        username: data.username,
        size: 120,
      ),
    );

    if (blur) {
      avatar = ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black26,
                BlendMode.srcATop,
              ),
              child: avatar,
            ),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
            ),
            Positioned(
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
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

// 전형적인 원형 타일
class _GroupBubble extends StatelessWidget {
  final Group group;
  final VoidCallback onOpen;
  final bool overlayGlow;
  final bool isSelected;
  final double size;

  const _GroupBubble({
    required this.group,
    required this.onOpen,
    required this.size,
    this.overlayGlow = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _paletteFrom(group.id);
    final prov = context.watch<GroupProvider>();
    final friendProv = context.watch<FriendProvider>();

    // 전체 친구 그룹인 경우 모든 친구 수를 표시
    final int memberCount =
        group.id == -1
            ? friendProv.acceptedFriends.length
            : prov.membersOf(group.id).length;

    final List<String> urls;
    if (group.id == -1) {
      // 전체 친구 그룹인 경우 모든 친구의 프로필 이미지 사용
      urls =
          friendProv.acceptedFriends
              .map((f) => f.profileImageUrl)
              .whereType<String>()
              .where((u) => u.isNotEmpty)
              .take(4)
              .toList();
    } else {
      // 일반 그룹인 경우 그룹 멤버의 프로필 이미지 사용
      final members = prov.membersOf(group.id);
      urls =
          members
              .map((m) => m.profileImageUrl)
              .whereType<String>()
              .where((u) => u.isNotEmpty)
              .toList();
    }

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border:
              isSelected
                  ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 4,
                  )
                  : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경 콜라주
            Hero(
              tag: 'group-${group.id}',
              flightShuttleBuilder: (context, animation, direction, from, to) {
                return SizedBox.expand(
                  child: ClipOval(
                    child: _GroupCollage(urls: urls, fallbackColors: colors),
                  ),
                );
              },
              child: SizedBox.expand(
                child: ClipOval(
                  child: _GroupCollage(urls: urls, fallbackColors: colors),
                ),
              ),
            ),
            // 선택되지 않은 그룹에 검정색 투명 오버레이
            if (!isSelected)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            // 오버레이 글로우 효과
            if (overlayGlow)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.25),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            // 멤버 수 배지(우상단)
            if (isSelected)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$memberCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.surface,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.center,
              child: Text(
                group.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  group.owner.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _paletteFrom(int seed) {
    final idx = seed % _palettes.length;
    return _palettes[idx];
  }
}

// 그룹 멤버 프로필 2x2 콜라주
class _GroupCollage extends StatelessWidget {
  final List<String> urls;
  final List<Color> fallbackColors;
  const _GroupCollage({required this.urls, required this.fallbackColors});

  @override
  Widget build(BuildContext context) {
    final tiles = urls.take(4).toList();
    Widget network(String u) => Image.network(
      u,
      fit: BoxFit.cover,
      cacheWidth: 200,
      cacheHeight: 200,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: child,
        );
      },
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF3A3A3A)),
    );

    if (tiles.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [fallbackColors[0], fallbackColors[1]],
          ),
        ),
      );
    }

    Widget collage;
    if (tiles.length == 1) {
      collage = network(tiles[0]);
    } else if (tiles.length == 2) {
      collage = Row(
        children: [
          Expanded(child: network(tiles[0])),
          Expanded(child: network(tiles[1])),
        ],
      );
    } else {
      collage = Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(child: network(tiles[0])),
                Expanded(
                  child: network(tiles.length > 2 ? tiles[2] : tiles[0]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: network(tiles.length > 1 ? tiles[1] : tiles[0]),
                ),
                Expanded(
                  child: network(tiles.length > 3 ? tiles[3] : tiles[1]),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Padding(padding: const EdgeInsets.all(0), child: collage);
  }
}

// 타일 등장 시 더 부드러운 스태거드(슬라이드+페이드)
class _AnimatedStaggered extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedStaggered({required this.index, required this.child});

  @override
  State<_AnimatedStaggered> createState() => _AnimatedStaggeredState();
}

class _AnimatedStaggeredState extends State<_AnimatedStaggered>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);

    Future<void>.delayed(Duration(milliseconds: 60 * widget.index)).then((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

const List<List<Color>> _palettes = [
  [Color(0xFF6A85B6), Color(0xFFBAC8E0)],
  [Color(0xFF74EBD5), Color(0xFFACB6E5)],
  [Color(0xFFF5576C), Color(0xFFF093FB)],
  [Color(0xFF5EE7DF), Color(0xFFB490CA)],
  [Color(0xFF536976), Color(0xFF292E49)],
  [Color(0xFFFBD3E9), Color(0xFFBB377D)],
];
