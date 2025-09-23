import 'package:flutter/material.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/models/friend_model.dart';
import '../../../data/models/group_model.dart';

// 멤버 추가 화면
class AddMemberScreen extends StatefulWidget {
  final Group group;

  const AddMemberScreen({Key? key, required this.group}) : super(key: key);

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  // API 서비스
  final FriendService _friendService = FriendService();
  final GroupService _groupService = GroupService();

  // 이웃(수락된 친구) 목록
  List<Friend> _friends = [];
  List<Friend> _filteredFriends = [];
  bool _isLoading = true;
  String? _error;

  // 검색 컨트롤러
  final TextEditingController _searchController = TextEditingController();

  // 선택된 친구들
  Set<String> _selectedFriends = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _searchController.addListener(_filterFriends);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 수락된 친구 목록 로드 (현재 그룹 멤버 제외)
  Future<void> _loadFriends() async {
    try {
      print('🔍 [AddMemberScreen] 수락된 친구 목록 로드 시작');

      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 친구 목록과 현재 그룹 멤버 목록을 동시에 로드
      final friends = await _friendService.getAcceptedFriends();
      final currentMembers = await _groupService.getGroupMembers(
        widget.group.id,
      );

      print('✅ [AddMemberScreen] 친구 목록 로드 성공: ${friends.length}명');
      print('✅ [AddMemberScreen] 현재 그룹 멤버: ${currentMembers.length}명');

      // 현재 그룹에 속한 친구들의 userId 목록
      final currentMemberIds =
          currentMembers.map((member) => member.userId).toSet();

      // 이미 그룹에 속한 친구들을 제외
      final availableFriends =
          friends
              .where((friend) => !currentMemberIds.contains(friend.username))
              .toList();

      print('✅ [AddMemberScreen] 추가 가능한 친구: ${availableFriends.length}명');

      setState(() {
        _friends = availableFriends;
        _filteredFriends = availableFriends;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ [AddMemberScreen] 친구 목록 로드 실패: $e');
      setState(() {
        _error = '친구 목록을 불러오는데 실패했습니다: $e';
        _isLoading = false;
      });
    }
  }

  // 친구 검색 필터링
  void _filterFriends() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFriends = _friends;
      } else {
        _filteredFriends =
            _friends
                .where(
                  (friend) => friend.username.toLowerCase().contains(query),
                )
                .toList();
      }
    });
  }

  // 친구 선택/해제 토글
  void _toggleFriendSelection(String username) {
    setState(() {
      if (_selectedFriends.contains(username)) {
        _selectedFriends.remove(username);
      } else {
        _selectedFriends.add(username);
      }
    });
  }

  // 선택된 친구들을 그룹에 추가
  Future<void> _addSelectedMembers() async {
    if (_selectedFriends.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('추가할 멤버를 선택해주세요')));
      return;
    }

    try {
      // 로딩 상태 표시
      setState(() {
        _isLoading = true;
      });

      print('🔍 [AddMemberScreen] 선택된 멤버들: $_selectedFriends');

      // 실제 그룹 멤버 추가 API 호출
      await _groupService.addMultipleMembersToGroup(
        widget.group.id,
        _selectedFriends.toList(),
      );

      print('✅ [AddMemberScreen] 그룹 멤버 추가 성공');

      // 성공 메시지 표시 후 이전 화면으로 돌아가기
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_selectedFriends.length}명의 멤버가 추가되었습니다')),
        );

        Navigator.pop(context, _selectedFriends.toList());
      }
    } catch (e) {
      print('❌ [AddMemberScreen] 그룹 멤버 추가 실패: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // 에러 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('멤버 추가에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.group.name} 멤버 추가',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _addSelectedMembers,
            child:
                _isLoading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(
                      '추가 (${_selectedFriends.length})',
                      style: TextStyle(
                        color:
                            _selectedFriends.isNotEmpty
                                ? Colors.blue
                                : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색 바
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '이웃 검색',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // 선택된 멤버 수 표시
          if (_selectedFriends.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedFriends.length}명 선택됨',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // 이웃 목록
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
                            onPressed: _loadFriends,
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    )
                    : _filteredFriends.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '추가할 수 있는 이웃이 없습니다',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '모든 이웃이 이미 그룹에 속해있거나\n새로운 이웃을 추가해주세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _filteredFriends.length,
                      itemBuilder: (context, index) {
                        final friend = _filteredFriends[index];
                        final isSelected = _selectedFriends.contains(
                          friend.username,
                        );

                        return _FriendTile(
                          friend: friend,
                          isSelected: isSelected,
                          onTap: () => _toggleFriendSelection(friend.username),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

// 친구 목록의 각 항목을 구성하는 위젯
class _FriendTile extends StatelessWidget {
  final Friend friend;
  final bool isSelected;
  final VoidCallback onTap;

  const _FriendTile({
    Key? key,
    required this.friend,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[200],
            child: const Icon(Icons.person, color: Colors.white, size: 30),
          ),
          if (isSelected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
      title: Text(
        friend.username,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('이웃'),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[300]!,
            width: 2,
          ),
          color: isSelected ? Colors.blue : Colors.transparent,
        ),
        child:
            isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
      ),
      onTap: onTap,
    );
  }
}
