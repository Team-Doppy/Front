import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';

/// 그룹 정보를 담을 데이터 모델
class Group {
  final String name;
  final String description;
  final int memberCount;
  final String? groupIconUrl;

  Group({
    required this.name,
    required this.description,
    required this.memberCount,
    this.groupIconUrl,
  });
}

/// 그룹 관리 화면
class ManageGroupScreen extends StatefulWidget {
  const ManageGroupScreen({Key? key}) : super(key: key);

  @override
  State<ManageGroupScreen> createState() => _ManageGroupScreenState();
}

class _ManageGroupScreenState extends State<ManageGroupScreen> {
  /// 하단 네비: 프로필 탭에서 열렸다고 가정 (0:홈, 1:검색, 2:작성, 3:프로필)
  int _bottomIndex = 3;

  /// 검색 상태
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  /// 샘플 데이터(실서버 연동 전)
  final List<Group> _groups = List.generate(
    10,
    (index) => Group(
      name: '그룹 ${index + 1}',
      description: '설명',
      memberCount: 23 + index,
    ),
  );

  /// 표시용 목록(검색/정렬 반영)
  late List<Group> _visibleGroups = List.of(_groups);

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------- 검색 로직 --------------------
  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _performSearch);
  }

  void _onSearchSubmitted(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _performSearch();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
    _performSearch();
  }

  void _performSearch() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _visibleGroups = List.of(_groups);
      });
      return;
    }

    final filtered =
        _groups.where((g) {
          final name = g.name.toLowerCase();
          final desc = g.description.toLowerCase();
          return name.contains(q) || desc.contains(q);
        }).toList();

    setState(() {
      _visibleGroups = filtered;
    });
  }

  // -------------------- 뒤로가기 로직 --------------------
  Future<void> _handleBack() async {
    // 뒤로갈 수 있으면 pop, 아니면 홈으로
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // 상단 앱 바
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: '뒤로가기',
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _handleBack,
        ),
        title: const Text(
          '그룹관리',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // 간단한 메뉴 (필요 시 확장)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.black),
            onSelected: (v) {
              switch (v) {
                case 'create':
                  _showSnack('그룹 생성은 별도 화면/모달로 연결하세요.');
                  break;
                case 'refresh':
                  setState(() {
                    // 서버 연동 시 목록 새로고침 자리
                    _visibleGroups = List.of(_groups);
                    _query = '';
                    _searchController.clear();
                  });
                  _showSnack('목록을 새로고침했습니다.');
                  break;
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(value: 'create', child: Text('그룹 생성')),
                  PopupMenuItem(value: 'refresh', child: Text('새로고침')),
                ],
          ),
        ],
      ),

      // 본문
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSortFilterBar(),
          Expanded(
            child:
                _visibleGroups.isEmpty
                    ? const _Empty(message: '그룹이 없습니다.')
                    : ListView.builder(
                      itemCount: _visibleGroups.length,
                      itemBuilder: (context, index) {
                        return _GroupListTile(
                          group: _visibleGroups[index],
                          onPressSettings:
                              () => _openGroupActions(_visibleGroups[index]),
                        );
                      },
                    ),
          ),
        ],
      ),

      // 하단 네비게이션: 커스텀 컴포넌트 사용
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: _bottomIndex,
        onTap: (i) {
          // 글쓰기(2)는 콜백으로만 처리됨. 필요 시 모달/페이지로 연결
          if (i == 2) {
            _showSnack('작성 버튼 눌림 (모달/페이지 연결)');
            return;
          }
          setState(() => _bottomIndex = i);
        },
      ),
    );
  }

  // 검색 바
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
          decoration: InputDecoration(
            hintText: '검색',
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            suffixIcon:
                _query.isNotEmpty
                    ? IconButton(
                      tooltip: '지우기',
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: _clearSearch,
                    )
                    : null,
            filled: true,
            fillColor: Colors.grey[100],
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  // 정렬/필터 바 (지금은 이름순 고정 표시만)
  Widget _buildSortFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          const Text(
            '이름순',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Icon(Icons.arrow_drop_down),
          const Spacer(),
          Text(
            '총 ${_visibleGroups.length}개',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // 그룹 액션(설정 버튼) 시트
  void _openGroupActions(Group group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('그룹 이름/설명 수정'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnack('"${group.name}" 수정 화면으로 이동하세요.');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text('멤버 관리'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnack('"${group.name}" 멤버 관리 화면으로 이동하세요.');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    '그룹 삭제',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnack('"${group.name}" 삭제 API 연결 자리.');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
      );
  }
}

/// 목록이 비었을 때 표시
class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Colors.black54, fontSize: 14),
      ),
    );
  }
}

/// 그룹 목록의 각 항목
class _GroupListTile extends StatelessWidget {
  final Group group;
  final VoidCallback onPressSettings;

  const _GroupListTile({
    Key? key,
    required this.group,
    required this.onPressSettings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // 그룹 아이콘
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[200],
            child:
                group.groupIconUrl != null
                    ? ClipOval(
                      child: Image.network(
                        group.groupIconUrl!,
                        fit: BoxFit.cover,
                        width: 56,
                        height: 56,
                      ),
                    )
                    : const Icon(Icons.groups, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          // 그룹 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        group.description,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '멤버 ${group.memberCount}명',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
          // 설정 버튼
          OutlinedButton(
            onPressed: onPressSettings,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: const Text('설정', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
