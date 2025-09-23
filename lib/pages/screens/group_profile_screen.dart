import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/group_model.dart';
import 'add_member_screen.dart';
import '../components/custom_bottom_navigation_bar.dart';
import 'group_edit_screen.dart'; // GroupEditScreen 추가
import '../../providers/group_provider.dart';

// 그룹 프로필 화면 메인 위젯
class GroupProfileScreen extends StatefulWidget {
  final Group group;

  const GroupProfileScreen({Key? key, required this.group}) : super(key: key);

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 3;

  // 그룹 정보 (상태로 관리)
  late Group _group;

  // 멤버 목록 표시 제거 (서버 500 회피). 필요 시 향후 별도 화면에서 구현

  @override
  void initState() {
    super.initState();
    // 초기 그룹 정보 설정
    _group = widget.group;
    // 멤버 목록 요청 제거

    // 화면 포커스 감지를 위한 observer 등록
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // observer 해제
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 포그라운드로 돌아올 때 그룹 정보 새로고침
    if (state == AppLifecycleState.resumed) {
      _refreshGroupInfo();
    }
  }

  // 멤버 목록 로드는 제거

  // 그룹 정보 새로고침
  Future<void> _refreshGroupInfo() async {
    try {
      print('🔍 [GroupProfileScreen] 그룹 정보 새로고침 시작');
      await context.read<GroupProvider>().fetchMyGroups();
      final prov = context.read<GroupProvider>();
      final updated = prov.myGroups.firstWhere(
        (g) => g.id == _group.id,
        orElse: () => _group,
      );
      setState(() {
        _group = updated;
      });
      print('✅ [GroupProfileScreen] 그룹 정보 새로고침 성공: ${_group.name}');
    } catch (e) {
      print('❌ [GroupProfileScreen] 그룹 정보 새로고침 실패: $e');
    }
  }

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
            // 그룹 관리 화면으로 뒤로가기
            Navigator.pop(context);
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
        children: [_buildGroupHeader(), _buildSearchBar()],
      ),
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

  // 상단 그룹 정보 헤더
  Widget _buildGroupHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 좌측 프로필 이미지
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[200],
            child: const Icon(Icons.groups, color: Colors.white, size: 50),
          ),
          const SizedBox(width: 28),
          // 우측 정보 (이름, 설명, 버튼)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _group.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _group.description.isNotEmpty
                      ? _group.description
                      : '설명이 없습니다',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // OutlinedButton의 크기를 조절하기 위해 SizedBox로 감쌈
                    SizedBox(
                      width: 100,
                      height: 32, // 버튼 높이 조절
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => GroupEditScreen(group: _group),
                            ),
                          ).then((result) {
                            if (result != null) {
                              if (result == 'deleted') {
                                // 그룹이 삭제되었으면 이전 화면으로 돌아가기
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('그룹이 삭제되었습니다')),
                                );
                                Navigator.pop(context, 'deleted');
                              } else {
                                // 그룹 정보가 수정되었으면 새로고침
                                _refreshGroupInfo();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('그룹 정보가 업데이트되었습니다'),
                                  ),
                                );
                              }
                            }
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          '그룹 편집',
                          style: TextStyle(color: Colors.black, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      height: 32, // 버튼 높이 조절
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => AddMemberScreen(group: _group),
                            ),
                          ).then((result) async {
                            if (result != null) {
                              // 멤버 추가 후 그룹 목록만 새로고침
                              await context.read<GroupProvider>().fetchMyGroups(
                                forceRefresh: true,
                              );
                              await _refreshGroupInfo();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${result.length}명의 멤버가 추가되었습니다',
                                  ),
                                ),
                              );
                            }
                          });
                        },
                        child: const Text(
                          '멤버 추가',
                          style: TextStyle(color: Colors.black, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
}
