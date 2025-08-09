import 'package:flutter/material.dart';

// 이웃 정보를 담을 데이터 모델
class Neighbor {
  final String name;
  final String userId;
  final int mutualFriends;
  final String? profileImageUrl; // 프로필 이미지는 URL 형태일 수 있으므로 nullable

  Neighbor({
    required this.name,
    required this.userId,
    required this.mutualFriends,
    this.profileImageUrl,
  });
}

// 이웃 관리 화면 메인 위젯
class ManageNeighborScreen extends StatefulWidget {
  const ManageNeighborScreen({Key? key}) : super(key: key);

  @override
  State<ManageNeighborScreen> createState() => _ManageNeighborScreenState();
}

class _ManageNeighborScreenState extends State<ManageNeighborScreen> {
  // 하단 네비게이션 바의 현재 선택된 인덱스
  int _selectedIndex = 3; // 초기 선택을 '프로필'로 설정

  // 샘플 데이터 목록
  final List<Neighbor> _neighbors = List.generate(
    15,
        (index) => Neighbor(
      name: '이웃 ${index + 1}',
      userId: '@userID${index + 1}',
      mutualFriends: 23,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 상단 앱 바
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0, // 그림자 제거
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // TODO: 뒤로가기 로직 구현
          },
        ),
        title: const Text(
          '이웃관리',
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
          _buildFilterBar(),
          // 스크롤 가능한 이웃 목록
          Expanded(
            child: ListView.builder(
              itemCount: _neighbors.length,
              itemBuilder: (context, index) {
                return _NeighborListTile(neighbor: _neighbors[index]);
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
        type: BottomNavigationBarType.fixed, // 탭이 많아도 고정
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false, // 선택된 아이템 라벨 숨김
        showUnselectedLabels: false, // 선택되지 않은 아이템 라벨 숨김
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
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: '검색',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide.none, // 테두리 없음
          ),
        ),
      ),
    );
  }

  // 필터 바 위젯
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          const Text(
            '모든 그룹',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Icon(Icons.arrow_drop_down),
          const Spacer(), // 남은 공간을 모두 차지
        ],
      ),
    );
  }
}

// 이웃 목록의 각 항목을 구성하는 위젯
class _NeighborListTile extends StatelessWidget {
  final Neighbor neighbor;

  const _NeighborListTile({Key? key, required this.neighbor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        // 프로필 이미지가 있으면 보여주고, 없으면 기본 아이콘 표시
        child: neighbor.profileImageUrl != null
            ? ClipOval(child: Image.network(neighbor.profileImageUrl!, fit: BoxFit.cover))
            : const Icon(Icons.person, color: Colors.white, size: 30),
      ),
      title: Row(
        children: [
          Text(neighbor.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(neighbor.userId, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
      subtitle: Text('이웃 ${neighbor.mutualFriends}명'),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () {
          // TODO: 더보기 메뉴 로직 구현
        },
      ),
    );
  }
}