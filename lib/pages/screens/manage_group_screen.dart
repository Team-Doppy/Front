import 'dart:ui' as ui;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/friend_service.dart'; // 🎯 FriendService 추가
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/pages/components/group_sheet.dart'; // 🎯 GroupDropDown 사용
import 'package:doppy/pages/components/shimmer_box.dart'; // 🎯 ShimmerBox 추가
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../data/models/friend_model.dart';
import '../../../data/models/group_model.dart'; // GroupColorPalette 포함
import '../../../providers/group_provider.dart';
import 'user_profile_screen.dart';

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

    // 전달받은 그룹으로 초기화
    if (widget.selectedGroup != null) {
      _selectedGroup = widget.selectedGroup;
    }

    // 첫 빌드 후 캐시 우선 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GroupProvider>().fetchMyGroups();
      // 친구 데이터도 함께 로드
      context.read<FriendProvider>().fetchAllFriendData();

      // 🎯 선택된 그룹의 멤버 데이터 로드
      if (_selectedGroup != null && _selectedGroup!.id != -1) {
        context.read<GroupProvider>().fetchGroupMembers(_selectedGroup!.id);
      }
    });
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
    _groupDropDown.dispose(); // 🎯 GroupDropDown 정리
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 🎯 배경 레이어
          Positioned.fill(
            child:
                _selectedGroup?.profileImageUrl != null &&
                        _selectedGroup!.profileImageUrl!.isNotEmpty
                    ? Image.network(
                      _selectedGroup!.profileImageUrl!,
                      fit: BoxFit.cover,
                    )
                    : Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-0.5, -0.7),
                          radius: 1.5,
                          colors: [
                            GroupColorPalette.getColor(
                              _selectedGroup?.id ?? 0,
                            ).withOpacity(0.4),
                            GroupColorPalette.getColor(
                              _selectedGroup?.id ?? 0,
                            ).withOpacity(0.6),
                            GroupColorPalette.getColor(
                              (_selectedGroup?.id ?? 0) +
                                  3 % GroupColorPalette.colors.length,
                            ).withOpacity(0.4),
                            GroupColorPalette.getColor(
                              (_selectedGroup?.id ?? 0) +
                                  3 % GroupColorPalette.colors.length,
                            ).withOpacity(0.3),
                          ],
                          stops: const [0.0, 0.4, 0.7, 1.0],
                        ),
                      ),
                    ),
          ),

          // 🎯 콘텐츠 레이어
          Consumer<GroupProvider>(
            builder: (context, groupProv, child) {
              // 🎯 그룹 스키마 로딩 중
              if (groupProv.isLoading) {
                return GestureDetector(
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
                );
              }

              // 🎯 선택된 그룹의 멤버 로딩 중 (전체 친구 제외)
              if (_selectedGroup != null &&
                  _selectedGroup!.id != -1 &&
                  groupProv.isLoadingMembers(_selectedGroup!.id) &&
                  !groupProv.isMembersCached(_selectedGroup!.id)) {
                return GestureDetector(
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
                );
              }

              return Consumer<FriendProvider>(
                builder: (context, friendProv, child) {
                  // 🎯 HomeScreen 스타일: Stack으로 배경 + 콘텐츠 분리
                  return Stack(
                    children: [
                      _buildDynamicBackground(), // 배경
                      _buildMainContent(groupProv, friendProv), // 콘텐츠
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // 🎯 동적 배경 (그룹 이미지 또는 그라디언트 + 블러)
  Widget _buildDynamicBackground() {
    final hasImage =
        _selectedGroup?.profileImageUrl != null &&
        _selectedGroup!.profileImageUrl!.isNotEmpty;

    return Positioned.fill(
      child: Stack(
        children: [
          // 1️⃣ 배경 이미지 또는 그라디언트 (블러 전 원본)
          Positioned.fill(
            child:
                hasImage
                    ? Image.network(
                      _selectedGroup!.profileImageUrl!,
                      fit: BoxFit.cover,
                      key: ValueKey('group-bg-${_selectedGroup!.id}'),
                    )
                    : _buildGradientBackground(),
          ),
          // 2️⃣ 블러 필터 + 오버레이
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 25,
                sigmaY: 25,
              ), // 30 → 20으로 감소
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors:
                        Theme.of(context).brightness == Brightness.dark ||
                                _selectedGroup?.profileImageUrl != null &&
                                    _selectedGroup!.profileImageUrl!.isNotEmpty
                            ? [
                              Colors.black.withOpacity(0.5),
                              Colors.black.withOpacity(0.6),
                              Colors.black.withOpacity(0.5),
                            ]
                            : [
                              Colors.white.withOpacity(0.2),
                              Colors.white.withOpacity(0.4),
                              Colors.white.withOpacity(0.6),
                            ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🎯 복잡한 그라디언트 배경 (이미지 느낌)
  Widget _buildGradientBackground() {
    final groupColor = GroupColorPalette.getColor(_selectedGroup?.id ?? 0);
    final accentColor = GroupColorPalette.getColor(
      (_selectedGroup?.id ?? 0) + 3 % GroupColorPalette.colors.length,
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.5, -0.7),
          radius: 1.5,
          colors: [
            groupColor.withOpacity(0.4),
            groupColor.withOpacity(0.5),
            accentColor.withOpacity(0.3),
            accentColor.withOpacity(0.2),
          ],
          stops: const [0.0, 0.4, 0.7, 1.0],
        ),
      ),
    );
  }

  Widget _buildMainContent(GroupProvider groupProv, FriendProvider friendProv) {
    List<Group> groups = groupProv.myGroups;

    // 전체 친구 가상 그룹 생성
    final allFriendsGroup = Group(
      id: -1, // 특별한 ID로 구분
      name: context.tr('all_friends'),
      description: context.tr('all_friends'),
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
          surfaceTintColor: Colors.transparent,
          floating: false,
          pinned: true,
          expandedHeight: 0,
          collapsedHeight: 70,
          toolbarHeight: 70,

          leading: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 24,
                color: Colors.white, // 🎯 흰색
              ),
            ),
          ),
          title: Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedGroup?.name ?? context.tr('manage_groups'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white, // 🎯 흰색
                          letterSpacing: -0.4,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (_selectedGroup != null && _selectedGroup!.id != -1)
                        Text(
                          '${context.tr('members')} · ${context.read<GroupProvider>().membersOf(_selectedGroup!.id).length}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.7), // 🎯 흰색 투명
                            letterSpacing: -0.2,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          centerTitle: false,
          // 🎯 그룹 수정 버튼 - 모든 그룹에 표시 (전체 친구 포함)
          actions:
              _selectedGroup != null
                  ? [
                    Container(
                      margin: const EdgeInsets.only(
                        right: 0,
                        top: 0,
                        bottom: 12,
                      ),
                      child: Center(
                        child: Container(
                          width: 70,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2), // 🎯 반투명 흰색
                          ),
                          child: TextButton(
                            onPressed: _showEditGroupSheet,
                            child: Text(
                              context.tr('edit'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white, // 🎯 흰색
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]
                  : null,
        ),
      );
    } else {
      // 임베드일 때는 상단 여백 추가
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 20)));
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

                  Text(
                    '해당하는 멤버나 그룹이 없어요',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.7), // 🎯 흰색
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
      child: RawScrollbar(
        controller: _scrollController,
        thumbColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
        radius: const Radius.circular(8),
        thickness: 4,
        thumbVisibility: true, // 항상 표시
        child: CustomScrollView(
          controller: _scrollController,
          slivers: slivers,
        ),
      ),
    );

    if (widget.embedded) {
      return body;
    }

    // 🎯 스와이프 제스처로 뒤로 가기
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        // 오른쪽으로 드래그 감지
        if (details.primaryDelta != null && details.primaryDelta! > 0) {
          // 드래그 중
        }
      },
      onHorizontalDragEnd: (details) {
        // 오른쪽으로 스와이프 (velocity.dx > 300)
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          body,
          // 플로팅 액션 버튼
          _buildFloatingActionButton(),
        ],
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
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final double bottomGap = keyboardInset > 0 ? 10 : 30;

    return AnimatedPositioned(
      right: 25,
      bottom: bottomGap + 10,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 전체 친구 그룹 여부
          if (_selectedGroup != null && _selectedGroup!.id == -1) ...[
            // 검색 플로팅 버튼(전체 친구일 때만 표시)
            Container(
              height: 58,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSearchExpanded)
                    GestureDetector(
                      onTap: () {},
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
                            hintText: context.tr('search_groups_friends'),
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceVariant.withOpacity(0.6),
                              fontSize: 16,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 20,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(28),
                              ),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(28),
                              ),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(28),
                              ),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: _toggleSearch,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isSearchExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.search,
                        color: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // + 버튼 (멤버 추가) - 전체 친구가 아닐 때만 표시
            GestureDetector(
              onTap: _showAddMemberBottomSheet,
              child: Container(
                width: 65, // 🎯 50 → 70으로 증가
                height: 65,

                decoration: BoxDecoration(
                  color: Colors.white, // ✅ 항상 흰색
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add,
                  size: 32,
                  color: Colors.black, // ✅ 아이콘은 검은색
                ),
              ),
            ),
          ],
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
      barrierColor: Colors.black.withOpacity(0.6),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _AddMemberBottomSheet(
            selectedGroup: _selectedGroup,
            onClose: () => Navigator.pop(context),
          ),
    ).then((_) {
      // 🎯 바텀시트 닫힐 때 키보드도 함께 닫기
      FocusManager.instance.primaryFocus?.unfocus();
    });
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
          _selectedGroup!.id != -1 ? _deleteGroup : null, // 🎯 전체 친구는 삭제 불가
    );
  }

  // 🎯 그룹 삭제
  Future<void> _deleteGroup() async {
    if (_selectedGroup == null || _selectedGroup!.id == -1) return; // 🎯 이중 체크

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
      );

      if (success) {
        // 로컬 상태 업데이트
        setState(() {
          _selectedGroup = _selectedGroup!.copyWith(
            name: name.trim(),
            description: description,
            profileImageUrl: imageUrl,
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('group_name_updated')),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('group_update_failed')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('error_occurred')}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
  final Set<String> _selectedFriends = <String>{}; // 친구인 사람들 (그룹 추가)
  final Set<String> _selectedNonFriends = <String>{}; // 🎯 친구가 아닌 사람들 (친구 요청)
  final Set<String> _selectedPendingCancels = <String>{}; // 🎯 요청 취소할 사람들
  final Set<String> _pendingRequests = <String>{}; // 🎯 친구 요청 보낸 사람들
  final TextEditingController _searchController = TextEditingController();
  List<User> _searchedUsers = []; // 🎯 검색된 사용자 목록
  bool _isSearching = false; // 🎯 검색 중 플래그
  bool _isSendingRequests = false; // 🎯 친구 요청 전송 중
  String _lastQuery = ''; // 🎯 마지막 검색어

  @override
  void initState() {
    super.initState();
    // 🎯 이미 보낸 친구 요청 목록 로드
    _loadSentFriendRequests();
  }

  @override
  void dispose() {
    // 🎯 키보드 닫기
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.dispose();
    super.dispose();
  }

  // 🎯 서버에서 이미 보낸 친구 요청 목록 가져오기
  Future<void> _loadSentFriendRequests() async {
    try {
      final friendService = FriendService();
      final sentRequests = await friendService.getSentFriendRequests();

      if (mounted) {
        setState(() {
          // 이미 보낸 요청들을 _pendingRequests에 추가
          for (final friend in sentRequests) {
            _pendingRequests.add(friend.username);
          }
        });
        print('🎯 [MGScreen] 이미 보낸 요청 로드: ${_pendingRequests.toList()}');
      }
    } catch (e) {
      print('❌ [MGScreen] 보낸 요청 로드 실패: $e');
    }
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
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                // 드래그 핸들
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                Row(
                  children: [
                    Expanded(child: _buildSearchBar()),

                    GestureDetector(
                      onTap: widget.onClose,
                      child: SizedBox(
                        height: 40,

                        child: Icon(
                          Icons.close,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
                const SizedBox(height: 30),
                // 친구 그리드
                Expanded(child: _buildFriendsGrid(scrollController)),
                // 하단 액션바
                _buildActionBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    final isDarkMode =
        Theme.of(context).colorScheme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      height: 46,
      decoration: BoxDecoration(
        color:
            isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade200.withOpacity(0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        cursorColor: Theme.of(context).colorScheme.onSurface,
        controller: _searchController,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        onChanged: (value) {
          // 🎯 검색어가 변경되면 사용자 검색 실행
          _searchUsers(value.trim());
        },
        decoration: InputDecoration(
          hintText: context.tr('add_friend_or_search_user'),
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
          ),
          suffixIcon: Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
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

  // 🎯 사용자 검색
  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchedUsers = [];
        _lastQuery = '';
        // 🎯 검색어 지우면 선택 초기화
        _selectedFriends.clear();
        _selectedNonFriends.clear();
        _selectedPendingCancels.clear();
      });
      return;
    }

    if (query == _lastQuery) return; // 같은 검색어면 스킵

    setState(() {
      _isSearching = true;
      _lastQuery = query;
      // 🎯 검색어 바뀌면 선택 초기화
      _selectedFriends.clear();
      _selectedNonFriends.clear();
      _selectedPendingCancels.clear();
    });

    try {
      final friendService = FriendService();
      final users = await friendService.searchUsers(query);

      if (mounted) {
        setState(() {
          _searchedUsers = users;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('❌ [AddMemberBottomSheet] 사용자 검색 에러: $e');
      if (mounted) {
        setState(() {
          _searchedUsers = [];
          _isSearching = false;
        });
      }
    }
  }

  Widget _buildFriendsGrid(ScrollController scrollController) {
    final friendProv = context.watch<FriendProvider>();
    final groupProv = context.watch<GroupProvider>();

    if (widget.selectedGroup == null || widget.selectedGroup!.id == -1) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('select_group_please'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7), // 🎯 흰색
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final groupMembers = groupProv.membersOf(widget.selectedGroup!.id);
    final memberUsernames = groupMembers.map((m) => m.userId).toSet();

    // 🎯 친구 목록 (그룹에 없는 친구만)
    // ⚠️ 서버 정책: 요청 보낸 친구(pending)는 그룹에 추가 불가
    final availableFriends =
        friendProv.acceptedFriends
            .where((f) => !memberUsernames.contains(f.username))
            .toList();

    // 🎯 검색 모드: 검색된 사용자 표시
    if (_lastQuery.isNotEmpty) {
      if (_isSearching) {
        // 🎯 쉬머 효과로 로딩 표시
        return GridView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 6,
            childAspectRatio: 0.8,
          ),
          itemCount: 3, // 🎯 6개의 쉬머 아이템 표시
          itemBuilder: (context, index) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 프로필 원형 쉬머
                ShimmerBox(
                  width: 110,
                  height: 110,
                  shape: const CircleBorder(),
                ),
                const SizedBox(height: 6),
                // 이름 쉬머
                ShimmerBox(
                  width: 80,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          },
        );
      }

      if (_searchedUsers.isEmpty) {
        return Center(
          child: Text(
            '검색 결과가 없습니다',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7), // 🎯 흰색
              fontSize: 16,
            ),
          ),
        );
      }

      // 검색된 사용자 표시 (친구 여부 구분)
      final friendUsernames =
          friendProv.acceptedFriends.map((f) => f.username).toSet();

      return GridView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 6,
          childAspectRatio: 0.8,
        ),
        itemCount: _searchedUsers.length,
        itemBuilder: (context, index) {
          final user = _searchedUsers[index];
          final isFriend = friendUsernames.contains(user.username);
          final isAlreadyMember = memberUsernames.contains(user.username);
          final isSelected = _selectedFriends.contains(user.username);
          final isSelectedNonFriend = _selectedNonFriends.contains(
            user.username,
          );
          final isPending = _pendingRequests.contains(
            user.username,
          ); // 🎯 요청 보낸 상태
          final isSelectedForCancel = _selectedPendingCancels.contains(
            user.username,
          ); // 🎯 취소 선택

          return GestureDetector(
            onTap: () {
              if (isAlreadyMember) return; // 이미 그룹 멤버면 무시

              setState(() {
                if (isFriend) {
                  // 🎯 친구면 선택/해제
                  if (isSelected) {
                    _selectedFriends.remove(user.username);
                  } else {
                    _selectedFriends.add(user.username);
                    _selectedNonFriends.remove(user.username);
                    _selectedPendingCancels.remove(user.username);
                  }
                } else if (isPending) {
                  // 🎯 이미 요청을 보낸 경우 → 취소 선택/해제
                  if (isSelectedForCancel) {
                    _selectedPendingCancels.remove(user.username);
                  } else {
                    _selectedPendingCancels.add(user.username);
                    _selectedFriends.remove(user.username);
                    _selectedNonFriends.remove(user.username);
                  }
                } else {
                  // 🎯 친구가 아니면 선택/해제 (친구 요청용)
                  if (isSelectedNonFriend) {
                    _selectedNonFriends.remove(user.username);
                  } else {
                    _selectedNonFriends.add(user.username);
                    _selectedFriends.remove(user.username);
                    _selectedPendingCancels.remove(user.username);
                  }
                }
              });
            },
            child: _buildUserTile(
              user,
              isFriend,
              isAlreadyMember,
              isSelected ||
                  isSelectedNonFriend ||
                  isSelectedForCancel, // 🎯 선택 상태
              isPending, // 🎯 요청 보낸 상태 전달
            ),
          );
        },
      );
    }

    // 🎯 기본 모드: 친구 목록 표시
    if (availableFriends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.tr('no_friends_to_add'),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7), // 🎯 흰색
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RawScrollbar(
      controller: scrollController,
      thumbColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
      radius: const Radius.circular(8),
      thickness: 4,
      thumbVisibility: true, // 항상 표시
      child: GridView.builder(
        controller: scrollController,
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
                      size: 110,
                      borderWidth: isSelected ? 4 : 0, // 선택 시만 테두리
                      borderColor:
                          isSelected
                              ? Theme.of(context).colorScheme.onSurface
                              : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  friend.username,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 🎯 사용자 타일 빌드 (친구 여부에 따라 다른 UI)
  Widget _buildUserTile(
    User user,
    bool isFriend,
    bool isAlreadyMember,
    bool isSelected,
    bool isPending, // 🎯 친구 요청 보낸 상태
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 🎯 최소 크기로 설정
      children: [
        Stack(
          children: [
            CommonProfileAvatar(
              imageUrl: '', // User 모델에 profileImageUrl이 없으므로 빈 문자열
              username: user.username,
              size: 110,
              borderWidth:
                  isPending
                      ? (isSelected
                          ? 4
                          : 2) // 🎯 pending: 선택 시 두껍게(4), 기본은 얇게(2)
                      : (isSelected ? 4 : 0), // 일반: 선택 시만 테두리
              borderColor:
                  (isSelected || isPending)
                      ? isPending
                          ? (isSelected
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface // 🎯 pending 선택: 두꺼운 onSurface
                              : Theme.of(context)
                                  .colorScheme
                                  .primary) // 🎯 pending 미선택: 얇은 primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface // 친구 선택: onSurface
                      : null,
            ),
            // 🎯 선택 시 체크 표시 (친구만, pending 아닐 때)
            if (isSelected && !isAlreadyMember && !isPending && isFriend)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, color: Colors.white, size: 16),
                ),
              ),

            // 🎯 이미 멤버면 흐리게
            if (isAlreadyMember)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.3),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6), // 🎯 8 → 6으로 줄임
        Flexible(
          // 🎯 Flexible로 감싸서 오버플로우 방지
          child: Text(
            user.username,
            style: TextStyle(
              color:
                  isAlreadyMember
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                      : Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 🎯 요청 보낸 상태 표시
        if (isPending)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4), // ✅ 상하 패딩 추가
            child: Text(
              context.tr('request_sent'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.3, // ✅ 줄 높이 추가
              ),
              textAlign: TextAlign.center,
              maxLines: 1, // 🎯 1줄로 제한
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // 🎯 선택된 사용자들에게 친구 요청 보내기
  Future<void> _sendFriendRequests() async {
    if (_selectedNonFriends.isEmpty) return;

    print('🚀 [MGScreen] 친구 요청 시작: ${_selectedNonFriends.toList()}');

    setState(() {
      _isSendingRequests = true; // 🎯 로딩 시작
    });

    // 🎯 FriendService를 직접 호출 (FriendProvider의 _friendStatus 체크를 우회)
    final friendService = FriendService();
    int successCount = 0;
    final List<String> successUsernames = [];
    final List<String> failedUsernames = [];

    for (final username in _selectedNonFriends) {
      try {
        print('📤 [MGScreen] $username 에게 요청 보내는 중...');
        await friendService.sendFriendRequest(username);
        successCount++;
        successUsernames.add(username);
        print('✅ [MGScreen] $username 요청 성공!');
      } catch (e) {
        failedUsernames.add(username);
        print('❌ [MGScreen] $username 요청 실패 (exception): $e');
      }
    }

    print(
      '🎯 [MGScreen] 요청 완료 | 성공: ${successUsernames.length}, 실패: ${failedUsernames.length}',
    );

    if (mounted) {
      setState(() {
        _isSendingRequests = false; // 🎯 로딩 종료

        // 🎯 성공한 요청은 pending 상태로 이동
        for (final username in successUsernames) {
          _pendingRequests.add(username);
        }

        // 선택 초기화
        _selectedNonFriends.clear();
      });

      if (successCount > 0) {
        ErrorHandler.showInfo(context, '$successCount명에게 친구 요청을 보냈습니다');
      } else {
        ErrorHandler.showError(context, '친구 요청 보내기에 실패했습니다');
      }
    }
  }

  // 🎯 선택된 친구 요청들 취소
  Future<void> _cancelFriendRequests() async {
    if (_selectedPendingCancels.isEmpty) return;

    setState(() {
      _isSendingRequests = true; // 🎯 로딩 시작
    });

    int successCount = 0;

    // TODO: 친구 요청 취소 API 추가 필요
    // final friendProv = context.read<FriendProvider>();

    for (final username in _selectedPendingCancels) {
      try {
        // await friendProv.cancelFriendRequest(username);

        // 일단 로컬 상태만 업데이트
        _pendingRequests.remove(username);
        successCount++;
      } catch (e) {
        print('❌ 요청 취소 실패: $username - $e');
      }
    }

    if (mounted) {
      setState(() {
        _isSendingRequests = false; // 🎯 로딩 종료
        _selectedPendingCancels.clear(); // 선택 초기화
      });

      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount명의 친구 요청을 취소했습니다'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('요청 취소에 실패했습니다'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildActionBar() {
    // 🎯 선택된 항목이 있는지 확인
    final hasSelectedFriends = _selectedFriends.isNotEmpty;
    final hasSelectedNonFriends = _selectedNonFriends.isNotEmpty;
    final hasSelectedPendingCancels =
        _selectedPendingCancels.isNotEmpty; // 🎯 요청 취소
    final hasSelection =
        hasSelectedFriends ||
        hasSelectedNonFriends ||
        hasSelectedPendingCancels;

    // 🎯 버튼 텍스트 결정
    String buttonText;
    if (hasSelectedPendingCancels) {
      // 🎯 요청 취소할 사람이 선택되면 "친구 요청 취소"
      buttonText = context
          .tr('cancel_request_count')
          .replaceAll('{count}', '${_selectedPendingCancels.length}');
    } else if (hasSelectedNonFriends) {
      // 친구가 아닌 사람이 선택되면 "친구 요청 보내기"
      buttonText = '친구 요청 보내기 (${_selectedNonFriends.length})';
    } else if (hasSelectedFriends) {
      // 친구만 선택되면 "추가하기"
      buttonText = context
          .tr('add_with_count')
          .replaceAll('{count}', '${_selectedFriends.length}');
    } else {
      buttonText = context.tr('add_with_count').replaceAll('{count}', '0');
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(bottom: 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        child: Row(
          children: [
            // Done 버튼
            Expanded(
              child: ElevatedButton(
                onPressed:
                    (hasSelection && !_isSendingRequests) // 🎯 로딩 중에는 비활성화
                        ? () {
                          if (hasSelectedPendingCancels) {
                            // 🎯 요청 취소
                            _cancelFriendRequests();
                          } else if (hasSelectedNonFriends) {
                            // 🎯 친구 요청 보내기
                            _sendFriendRequests();
                          } else {
                            // 🎯 그룹에 추가
                            _addSelectedMembers();
                          }
                        }
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child:
                    _isSendingRequests
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        )
                        : Text(
                          buttonText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSelectedMembers() {
    final group = widget.selectedGroup;
    if (group == null || group.id == -1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('select_group_first'))));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('members_added').replaceAll('{count}', '$success'),
            ),
          ),
        );
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
              ? context
                  .tr('no_friends_in_group')
                  .replaceAll('{groupName}', selectedGroup!.name)
              : context.tr('no_friends_to_display'),
          style: TextStyle(
            color: Colors.white.withOpacity(0.7), // 🎯 흰색
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

  // 🎯 고급스러운 멤버 액션 메뉴 (롱프레스)
  static void _showMemberActionMenu(
    BuildContext context,
    String username,
    String? profileImageUrl,
    Group? selectedGroup,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _MemberActionMenuOverlay(
          username: username,
          profileImageUrl: profileImageUrl,
          selectedGroup: selectedGroup,
          animation: animation,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = Colors.white; // 🎯 흰색
    final bool blur = data.state != _FriendState.accepted;
    final groupProv = context.watch<GroupProvider>();
    final selectedGroup =
        groupProv.myGroups.where((g) => g.id != -1).firstOrNull;

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
      onLongPress:
          data.state == _FriendState.accepted
              ? () {
                // 🎯 롱프레스 시 고급스러운 액션 메뉴
                _showMemberActionMenu(
                  context,
                  data.username,
                  data.url,
                  selectedGroup,
                );
              }
              : null,
      child: CommonProfileAvatar(
        imageUrl: data.url,
        username: data.username,
        size: 110,
      ),
    );

    if (blur) {
      avatar = Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                data.state == _FriendState.requestReceived
                    ? Theme.of(context).colorScheme.primary
                    : Colors.pink.withOpacity(0.8),
            width: data.state == _FriendState.requestReceived ? 3.5 : 2,
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
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 15),

            // 프로필 정보
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => UserProfileScreen(
                          otherUser: User(id: 0, username: widget.username),
                        ),
                  ),
                );
              },
              child: Row(
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
                          context.tr('accept_friend_request'),
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
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                    child: CommonProfileAvatar(
                      imageUrl: widget.profileImageUrl ?? '',
                      username: widget.username,
                      size: 130,
                    ),
                  ),
                ],
              ),
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
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.1),
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
                            : Text(
                              context.tr('reject'),
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
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
                            : Text(
                              context.tr('accept'),
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
            SnackBar(
              content: Text(
                context.tr('error_occurred_simple'),
                style: const TextStyle(color: Colors.white),
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
          SnackBar(
            content: Text(
              context.tr('error_occurred_simple'),
              style: const TextStyle(color: Colors.white),
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

// 🎯 고급스러운 멤버 액션 메뉴 오버레이
class _MemberActionMenuOverlay extends StatelessWidget {
  final String username;
  final String? profileImageUrl;
  final Group? selectedGroup;
  final Animation<double> animation;

  const _MemberActionMenuOverlay({
    required this.username,
    required this.profileImageUrl,
    required this.selectedGroup,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🎯 프로필 이미지
                      Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          border: Border.all(color: Colors.white, width: 0.5),
                        ),
                        child: ClipOval(
                          child: CommonProfileAvatar(
                            imageUrl: profileImageUrl,
                            username: username,
                            size: 240,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 사용자 이름
                      Text(
                        username,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      // 🎯 액션 버튼들
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 프로필 방문
                            _buildActionButton(
                              context,
                              icon: Icons.person_outline,
                              label: '프로필 방문',
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => UserProfileScreen(
                                          otherUser: User(
                                            id: 0,
                                            username: username,
                                          ),
                                        ),
                                  ),
                                );
                              },
                            ),
                            // 구분선
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1),
                            ),
                            // 그룹에서 제거
                            _buildActionButton(
                              context,
                              icon: Icons.person_remove_outlined,
                              label: '그룹에서 제거',
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _removeMemberFromGroup(
                                  context,
                                  username,
                                  selectedGroup,
                                );
                              },
                              isDestructive: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isDestructive
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 그룹에서 멤버 제거
  static Future<void> _removeMemberFromGroup(
    BuildContext context,
    String username,
    Group? selectedGroup,
  ) async {
    if (selectedGroup == null || selectedGroup.id == -1) return;

    final groupProv = context.read<GroupProvider>();

    try {
      await groupProv.removeMember(selectedGroup.id, username);

      if (context.mounted) {
        ErrorHandler.showInfo(context, '$username님을 그룹에서 제거했습니다');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(context, '멤버 제거에 실패했습니다');
      }
    }
  }
}
