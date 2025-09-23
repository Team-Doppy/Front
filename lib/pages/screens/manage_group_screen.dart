import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'group_profile_screen.dart';
import '../../../data/models/group_model.dart';
import '../../../providers/group_provider.dart';
import '../../../pages/components/custom_bottom_navigation_bar.dart';

// 그룹 관리 화면 메인 위젯
class ManageGroupScreen extends StatefulWidget {
  const ManageGroupScreen({Key? key}) : super(key: key);

  @override
  State<ManageGroupScreen> createState() => _ManageGroupScreenState();
}

class _ManageGroupScreenState extends State<ManageGroupScreen> {
  // 하단 네비게이션 바의 현재 선택된 인덱스
  int _selectedIndex = 3;

  @override
  void initState() {
    super.initState();
    // 첫 빌드 후 캐시 우선 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GroupProvider>().fetchMyGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupProv = context.watch<GroupProvider>();
    final List<Group> groups = groupProv.myGroups;
    return Scaffold(
      backgroundColor: Colors.white,
      // 상단 앱 바
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // 프로필 화면으로 뒤로가기
            Navigator.pop(context);
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
            child:
                groupProv.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        return _GroupListTile(
                          group: groups[index],
                          onGroupDeleted: () async {
                            // 삭제 후 강제 새로고침 (Provider가 무효화 처리)
                            await context.read<GroupProvider>().fetchMyGroups(
                              forceRefresh: true,
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
      // 하단 네비게이션 바
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          // CustomBottomNavigationBar가 자체적으로 화면 전환을 처리합니다
        },
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
  final VoidCallback? onGroupDeleted;

  const _GroupListTile({Key? key, required this.group, this.onGroupDeleted})
    : super(key: key);

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
            child: const Icon(Icons.groups, color: Colors.white, size: 30),
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
                      fit: FlexFit.tight,
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      fit: FlexFit.tight,
                      child: Text(
                        group.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '소유자: ${group.owner.username}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
          // 설정 버튼
          OutlinedButton(
            onPressed: () {
              // 그룹 프로필 화면으로 이동 (더미 데이터 전달)
              final dummyGroup = Group(
                id: group.id, // 실제 ID 사용
                name: group.name,
                description: group.description,
                ownerId: group.ownerId, // ownerId 추가
                owner: group.owner, // 실제 소유자 정보 사용
                createdAt: group.createdAt,
              );

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupProfileScreen(group: dummyGroup),
                ),
              ).then((result) {
                if (result == 'deleted') {
                  // 그룹이 삭제되었으면 콜백 호출
                  onGroupDeleted?.call();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('그룹이 삭제되었습니다')));
                }
              });
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
