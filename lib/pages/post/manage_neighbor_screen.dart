import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../providers/friend_provider.dart';
import '../../data/models/friend_model.dart';
import '../../theme/theme.dart'; // 쓰지 않으면 제거해도 OK
// import 'search_screen.dart'; // ✅ 2. 검색 화면을 import 합니다.

class ManageNeighborScreen extends StatefulWidget {
  const ManageNeighborScreen({Key? key}) : super(key: key);

  @override
  State<ManageNeighborScreen> createState() => _ManageNeighborScreenState();
}

class _ManageNeighborScreenState extends State<ManageNeighborScreen> {
  // ✨ 3. '모든 그룹' 필터의 토글 상태를 관리하기 위한 변수 추가
  bool _isGroupFilterExpanded = false;

  @override
  void initState() {
    super.initState();
    // 첫 진입 시 데이터 한 번에 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendProvider>().fetchAllFriendData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ─── AppBar ──────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/ic_back.svg',
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          ),
          onPressed: () {
            // ✅ 뒤로가기: 가능하면 pop, 아니면 홈으로 이동
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
        title: const Text(
          '이웃관리',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              'assets/icons/ic_menu.svg',
              colorFilter: const ColorFilter.mode(
                Colors.black,
                BlendMode.srcIn,
              ),
            ),
            onPressed: _openGlobalMenu, // ✅ 하단 시트 메뉴
          ),
        ],
      ),

      // ─── Body ────────────────────────────────────────────────────────────────
      body: Consumer<FriendProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.errorMessage != null) {
            return Center(child: Text(provider.errorMessage!));
          }

          return Column(
            // ✅ 3. 필터 바를 왼쪽 정렬하기 위해 Column의 정렬 속성을 추가합니다.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              _buildRequestSection(provider),
              _buildFilterBar(),
              Expanded(
                child: ListView.builder(
                  itemCount: provider.acceptedFriends.length,
                  itemBuilder: (context, index) {
                    final friend = provider.acceptedFriends[index];
                    return _NeighborListTile(
                      friend: friend,
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () => _openFriendActions(friend),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),

      // ─── BottomNav ───────────────────────────────────────────────────────────
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 3,
        onTap: (_) {},
      ),
    );
  }

  // ───────────────────────── UI pieces ─────────────────────────

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
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (q) {
          // TODO: 필요하면 검색 API/Provider에 연결
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('검색: $q')));
        },
      ),
    );
  }

  Widget _buildRequestSection(FriendProvider provider) {
    if (provider.receivedRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text(
              '이웃 요청',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...provider.receivedRequests.map((request) {
            return _NeighborListTile(
              friend: request,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AcceptButton(
                    onPressed: () async {
                      await context.read<FriendProvider>().acceptFriendRequest(
                        request.username,
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _RejectButton(
                    onPressed: () async {
                      // FriendProvider에 reject 메서드가 없다면 아래를 교체/주석 처리하세요.
                      // await context.read<FriendProvider>().rejectFriendRequest(request.username);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('거절 기능은 준비중입니다.')),
                      );
                    },
                  ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: InkWell( // ✨ 탭 가능하도록 InkWell로 감쌌습니다.
        onTap: () {
          // ✨ 탭하면 상태를 변경하여 UI를 다시 그리도록 합니다.
          setState(() {
            _isGroupFilterExpanded = !_isGroupFilterExpanded;
          });
          _toast(_isGroupFilterExpanded ? '그룹 필터 열림' : '그룹 필터 닫힘');
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min, // Row 크기를 내용물에 맞춤
            children: [
              const Text(
                '모든 그룹',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              // ✨ 상태에 따라 아이콘이 위/아래로 바뀝니다.
              Icon(_isGroupFilterExpanded
                  ? Icons.arrow_drop_up
                  : Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Menus ─────────────────────────

  // 상단 메뉴(오른쪽) 하단 시트
  void _openGlobalMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('전체 새로고침'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.read<FriendProvider>().fetchAllFriendData();
                  _toast('새로고침 완료');
                },
              ),
              ListTile(
                leading: const Icon(Icons.inbox),
                title: const Text('받은 요청 다시 불러오기'),
                onTap: () async {
                  Navigator.pop(ctx);
                  // FriendProvider가 분리된 fetch가 있으면 교체
                  await context.read<FriendProvider>().fetchAllFriendData();
                  _toast('받은 요청 갱신 완료');
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  // 친구 더보기(⋮) 시트
  void _openFriendActions(Friend friend) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_remove),
                title: const Text('친구 삭제'),
                onTap: () async {
                  Navigator.pop(ctx);
                  // FriendProvider에 deleteFriend가 있으면 아래 라인을 활성화
                  // await context.read<FriendProvider>().deleteFriend(friend.username);
                  _toast('친구 삭제 기능은 준비중입니다.');
                },
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('차단'),
                onTap: () async {
                  Navigator.pop(ctx);
                  // FriendProvider에 blockFriend가 있으면 아래 라인을 활성화
                  // await context.read<FriendProvider>().blockFriend(friend.username);
                  _toast('차단 기능은 준비중입니다.');
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ────────────────────── Tiles & Buttons ──────────────────────

class _NeighborListTile extends StatelessWidget {
  final Friend friend;
  final Widget? trailing;
  final String? profileImageUrl;

  const _NeighborListTile({
    Key? key,
    required this.friend,
    this.trailing,
    this.profileImageUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        child:
        profileImageUrl != null
            ? ClipOval(
          child: Image.network(profileImageUrl!, fit: BoxFit.cover),
        )
            : SvgPicture.asset(
          'assets/icons/ic_profile.svg',
          width: 30,
          height: 30,
          colorFilter: const ColorFilter.mode(
            Colors.white,
            BlendMode.srcIn,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            friend.username,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '@${friend.username}',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
      subtitle: const Text('함께 아는 이웃 0명'),
      trailing: trailing,
    );
  }
}

class _AcceptButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AcceptButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: const Text('수락', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _RejectButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RejectButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF9CA3AF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('거절', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}