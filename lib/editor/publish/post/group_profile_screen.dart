import 'package:flutter/material.dart';
import '../../../data/services/group_service.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/group_member_model.dart';
import 'add_member_screen.dart';
import '../../../pages/components/custom_bottom_navigation_bar.dart';
import 'group_edit_screen.dart'; // GroupEditScreen 추가

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

  // API 서비스
  final GroupService _groupService = GroupService();

  // 그룹 정보 (상태로 관리)
  late Group _group;

  // 그룹 멤버 목록
  List<GroupMember> _members = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 초기 그룹 정보 설정
    _group = widget.group;
    _loadGroupMembers();

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

  // 그룹 멤버 목록 로드
  Future<void> _loadGroupMembers() async {
    try {
      print('🔍 [GroupProfileScreen] 그룹 멤버 목록 로드 시작');
      print('🔍 [GroupProfileScreen] 그룹 ID: ${widget.group.id}');
      print('🔍 [GroupProfileScreen] 그룹 이름: ${widget.group.name}');

      setState(() {
        _isLoading = true;
        _error = null;
      });

      final members = await _groupService.getGroupMembers(widget.group.id);
      print('✅ [GroupProfileScreen] 그룹 멤버 목록 로드 성공: ${members.length}개');

      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ [GroupProfileScreen] 그룹 멤버 목록 로드 실패: $e');
      setState(() {
        _error = '멤버 목록을 불러오는데 실패했습니다: $e';
        _isLoading = false;
      });
    }
  }

  // 그룹 정보 새로고침
  Future<void> _refreshGroupInfo() async {
    try {
      print('🔍 [GroupProfileScreen] 그룹 정보 새로고침 시작');

      // 그룹 목록에서 최신 정보 가져오기
      final groups = await _groupService.getMyGroups();
      final updatedGroup = groups.firstWhere((g) => g.id == _group.id);

      print('✅ [GroupProfileScreen] 그룹 정보 새로고침 성공: ${updatedGroup.name}');

      // 그룹 정보 업데이트
      setState(() {
        _group = updatedGroup;
      });
    } catch (e) {
      print('❌ [GroupProfileScreen] 그룹 정보 새로고침 실패: $e');
      // 에러가 발생해도 기존 정보 유지
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
        children: [
          _buildGroupHeader(),
          _buildSearchBar(),
          _buildMemberListHeader(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadGroupMembers,
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        return _MemberTile(
                          member: _members[index],
                          onDelete: () {
                            // 멤버 삭제 로직을 여기서 처리
                            _removeMember(index);
                          },
                        );
                      },
                    ),
          ),
        ],
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
                        child: const Text(
                          '그룹 편집',
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
                          ).then((result) {
                            if (result != null) {
                              // 멤버 추가 후 멤버 목록 새로고침
                              _loadGroupMembers();
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

  // 멤버 삭제 로직
  Future<void> _removeMember(int index) async {
    final memberToRemove = _members[index];
    try {
      print('🔍 [GroupProfileScreen] 멤버 제거 시작: ${memberToRemove.userId}');

      // 실제 멤버 제거 API 호출
      await _groupService.removeMemberFromGroup(
        _group.id,
        memberToRemove.userId,
      );

      print('✅ [GroupProfileScreen] 멤버 제거 성공');

      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${memberToRemove.displayName}님이 그룹에서 제거되었습니다'),
          ),
        );
      }

      // 멤버 목록 새로고침
      _loadGroupMembers();
    } catch (e) {
      print('❌ [GroupProfileScreen] 멤버 제거 실패: $e');

      if (mounted) {
        // 에러 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('멤버 제거에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// 멤버 목록의 각 항목을 구성하는 위젯
class _MemberTile extends StatelessWidget {
  final GroupMember member;
  final VoidCallback onDelete; // 삭제 콜백 추가

  const _MemberTile({
    Key? key,
    required this.member,
    required this.onDelete, // onDelete 매개변수 추가
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        child:
            member.profileImageUrl != null
                ? ClipOval(child: Image.network(member.profileImageUrl!))
                : const Icon(Icons.person, color: Colors.white, size: 30),
      ),
      title: Row(
        children: [
          Text(
            member.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '@${member.userId}',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
      subtitle: Text('이웃 ${member.neighborCount}명'),
      trailing: OutlinedButton(
        onPressed: () async {
          // 삭제 확인 다이얼로그 표시
          final shouldDelete = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('멤버 제거'),
                content: Text('${member.displayName}님을 그룹에서 제거하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('제거'),
                  ),
                ],
              );
            },
          );

          if (shouldDelete == true) {
            onDelete(); // 부모 위젯에 삭제 로직 위임
          }
        },
        child: const Text('삭제', style: TextStyle(color: Colors.black)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[300]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
