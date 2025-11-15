import 'dart:ui' as ui;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/group_model.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_provider.dart';

// 멤버 추가 바텀시트 위젯
class AddMemberBottomSheet extends StatefulWidget {
  final Group? selectedGroup;
  final VoidCallback onClose;

  const AddMemberBottomSheet({
    Key? key,
    required this.selectedGroup,
    required this.onClose,
  }) : super(key: key);

  @override
  State<AddMemberBottomSheet> createState() => _AddMemberBottomSheetState();
}

class _AddMemberBottomSheetState extends State<AddMemberBottomSheet> {
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
    if (!mounted) return;
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
        print(
          '🎯 [AddMemberBottomSheet] 이미 보낸 요청 로드: ${_pendingRequests.toList()}',
        );
      }
    } catch (e) {
      print('❌ [AddMemberBottomSheet] 보낸 요청 로드 실패: $e');
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
                // 🎯 하단 액션바 - SafeArea로 키보드 위에 위치
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 2,
                  ),
                  child: _buildActionBar(),
                ),
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
          itemCount: 3, // 🎯 3개의 쉬머 아이템 표시
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
            context.tr('no_search_results'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    CommonProfileAvatar(
                      imageUrl: friend.profileImageUrl,
                      username: friend.username,
                      size: 110,
                      borderWidth: 0,
                      borderColor: null,
                    ),
                    // 🎯 선택 시 체크 표시
                    if (isSelected)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.check,
                              color: Colors.black,
                              size: 40,
                              shadows: const [
                                Shadow(
                                  blurRadius: 2,
                                  color: Colors.white,
                                  offset: Offset(0, 0),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                      ? 3.3 // 🎯 pending: 두꺼운 보라색 테두리
                      : 0, // 일반: 테두리 없음
              borderColor:
                  isPending ? Theme.of(context).colorScheme.primary : null,
            ),
            // 🎯 선택 시 체크 표시 (pending 아닐 때, 이미 멤버 아닐 때)
            if (isSelected && !isAlreadyMember && !isPending)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  child: Center(
                    child: Icon(Icons.check, color: Colors.black, size: 30),
                  ),
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
    if (_selectedNonFriends.isEmpty || !mounted) return;

    print(
      '🚀 [AddMemberBottomSheet] 친구 요청 시작: ${_selectedNonFriends.toList()}',
    );

    if (!mounted) return;
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
        print('📤 [AddMemberBottomSheet] $username 에게 요청 보내는 중...');
        await friendService.sendFriendRequest(username);
        successCount++;
        successUsernames.add(username);
        print('✅ [AddMemberBottomSheet] $username 요청 성공!');
      } catch (e) {
        failedUsernames.add(username);
        print('❌ [AddMemberBottomSheet] $username 요청 실패 (exception): $e');
      }
    }

    print(
      '🎯 [AddMemberBottomSheet] 요청 완료 | 성공: ${successUsernames.length}, 실패: ${failedUsernames.length}',
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
        ErrorHandler.showInfo(
          context,
          context
              .tr('friend_request_sent')
              .replaceAll('{count}', '$successCount'),
        );
      } else {
        ErrorHandler.showError(context, context.tr('friend_request_failed'));
      }
    }
  }

  // 🎯 선택된 친구 요청들 취소
  Future<void> _cancelFriendRequests() async {
    if (_selectedPendingCancels.isEmpty || !mounted) return;

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

      // 🎯 친구 요청 취소 성공 시 스낵바 표시하지 않음
      if (successCount == 0) {
        // 실패 시에만 에러 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('cancel_request_failed')),
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
      buttonText = context
          .tr('send_friend_request')
          .replaceAll('{count}', '${_selectedNonFriends.length}');
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
    if (!mounted) return;
    final group = widget.selectedGroup;
    if (group == null || group.id == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('select_group_first'))),
        );
      }
      return;
    }

    if (!mounted) return;
    final groupProv = context.read<GroupProvider>();

    // 순차 추가(간단 구현). 필요 시 Future.wait로 병렬 처리 가능
    Future<void> run() async {
      int success = 0;
      for (final username in _selectedFriends) {
        if (!mounted) break;
        final ok = await groupProv.addMember(group.id, username);
        if (ok) success++;
      }

      if (mounted) {
        ErrorHandler.showInfo(
          context,
          context.tr('members_added').replaceAll('{count}', '$success'),
        );
        widget.onClose();
      }
    }

    run();
  }
}
