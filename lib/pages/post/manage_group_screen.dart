import 'package:flutter/material.dart';

// 그룹 정보를 담을 데이터 모델
class Group {
  final String name;
  final String description;
  final int memberCount;
  final String? groupIconUrl; // 그룹 아이콘은 URL 형태일 수 있으므로 nullable

  Group({
    required this.name,
    required this.description,
    required this.memberCount,
    this.groupIconUrl,
  });
}

// 그룹 관리 화면 메인 위젯
class ManageGroupScreen extends StatefulWidget {
  const ManageGroupScreen({Key? key}) : super(key: key);

  @override
  State<ManageGroupScreen> createState() => _ManageGroupScreenState();
}

class _ManageGroupScreenState extends State<ManageGroupScreen> {
  // 하단 네비게이션 바의 현재 선택된 인덱스
  int _selectedIndex = 3;

  // 샘플 데이터 목록
  final List<Group> _groups = List.generate(
    10,
        (index) => Group(
      name: '그룹 ${index + 1}',
      description: '설명',
      memberCount: 23,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 상단 앱 바
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // TODO: 뒤로가기 로직 구현
          },
        ),
        title: const Text(
          '그룹관리',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () {
              // TODO: 메뉴 버튼 로직 구현
            },
          ),
        ],
      ),
      // 화면 본문
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSortFilterBar(),
          // 스크롤 가능한 그룹 목록
          Expanded(
            child: ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                return _GroupListTile(group: _groups[index]);
              },
            ),
          ),
        ],
      ),
      // 하단 네비게이션 바
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          // TODO: 각 탭에 대한 화면 이동 로직 구현
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_square), label: 'Write'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  // 검색 바 위젯
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: '검색',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // 정렬 필터 바 위젯
  Widget _buildSortFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          const Text(
            '이름순',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Icon(Icons.arrow_drop_down),
          const Spacer(),
        ],
      ),
    );
  }
}

// 그룹 목록의 각 항목을 구성하는 위젯
class _GroupListTile extends StatelessWidget {
  final Group group;

  const _GroupListTile({Key? key, required this.group}) : super(key: key);

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
            child: group.groupIconUrl != null
                ? ClipOval(child: Image.network(group.groupIconUrl!, fit: BoxFit.cover))
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
                    Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(group.description, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('멤버 ${group.memberCount}명', style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
          // 설정 버튼
          OutlinedButton(
            onPressed: () {
              // TODO: 설정 버튼 로직 구현
            },
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