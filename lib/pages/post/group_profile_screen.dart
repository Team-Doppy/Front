import 'package:flutter/material.dart';

// 그룹 멤버 정보를 담을 데이터 모델
class GroupMember {
  final String name;
  final String userId;
  final int mutualFriends;
  final String? profileImageUrl;

  GroupMember({
    required this.name,
    required this.userId,
    required this.mutualFriends,
    this.profileImageUrl,
  });
}

// 그룹 프로필 화면 메인 위젯
class GroupProfileScreen extends StatefulWidget {
  const GroupProfileScreen({Key? key}) : super(key: key);

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  int _selectedIndex = 3;

  // 샘플 데이터: 그룹 멤버 목록
  final List<GroupMember> _members = List.generate(
    7,
        (index) => GroupMember(
      name: '이웃 ${index + 1}',
      userId: '@userID${index + 1}',
      mutualFriends: 23,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // TODO: 뒤로가기 로직
          },
        ),
        title: const Text(
          '그룹프로필',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () {
              // TODO: 메뉴 버튼 로직
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupHeader(),
          _buildSearchBar(),
          _buildMemberListHeader(),
          Expanded(
            child: ListView.builder(
              itemCount: _members.length,
              itemBuilder: (context, index) {
                return _MemberTile(member: _members[index]);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
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

  // 상단 그룹 정보 헤더
  Widget _buildGroupHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 좌측 프로필 이미지
          const CircleAvatar(
            radius: 50,
            backgroundImage: NetworkImage('https://placehold.co/100x100/FFC107/000000?text=Group'),
          ),
          const SizedBox(width: 28),
          // 우측 정보 (이름, 설명, 버튼)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '에운방',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  '에오스 운영진~~~',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // OutlinedButton의 크기를 조절하기 위해 SizedBox로 감쌈
                    SizedBox(
                      width: 100,
                      height: 32, // 버튼 높이 조절
                      child: OutlinedButton(
                        onPressed: () {},
                        child: const Text('그룹 편집', style: TextStyle(color: Colors.black, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      height: 32, // 버튼 높이 조절
                      child: OutlinedButton(
                        onPressed: () {},
                        child: const Text('멤버 추가', style: TextStyle(color: Colors.black, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }


  // 멤버 검색 바
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

  // 멤버 목록 헤더
  Widget _buildMemberListHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Text(
        '멤버 ${_members.length}명',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

// 멤버 목록의 각 항목을 구성하는 위젯
class _MemberTile extends StatelessWidget {
  final GroupMember member;
  const _MemberTile({Key? key, required this.member}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        child: member.profileImageUrl != null
            ? ClipOval(child: Image.network(member.profileImageUrl!))
            : const Icon(Icons.person, color: Colors.white, size: 30),
      ),
      title: Row(
        children: [
          Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(member.userId, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
      subtitle: Text('이웃 ${member.mutualFriends}명'),
      trailing: OutlinedButton(
        onPressed: () {
          // TODO: 삭제 로직
        },
        child: const Text('삭제', style: TextStyle(color: Colors.black)),
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey[300]!),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
        ),
      ),
    );
  }
}
