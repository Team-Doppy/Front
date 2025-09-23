import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../providers/friend_provider.dart';
import '../../../data/models/friend_model.dart'; // ✅ 실제 Friend 모델을 사용합니다.
import '../../../theme/theme.dart'; // (테마가 있다면 경로 확인)

// 이웃 관리 화면 메인 위젯
class ManageNeighborScreen extends StatefulWidget {
  const ManageNeighborScreen({Key? key}) : super(key: key);

  @override
  State<ManageNeighborScreen> createState() => _ManageNeighborScreenState();
}

class _ManageNeighborScreenState extends State<ManageNeighborScreen> {
  @override
  void initState() {
    super.initState();
    // ✅ 화면이 열릴 때 Provider를 통해 '받은 요청'과 '친구 목록' 데이터를 한번에 요청합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FriendProvider>(context, listen: false).fetchAllFriendData();
    });
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 상단 앱 바
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // 그림자 제거
        leading: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/ic_back.svg',
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          ),
          onPressed: () {
            // 뒤로가기 로직 구현
            Navigator.pop(context);
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
            onPressed: () {
              // TODO: 메뉴 버튼 로직 구현
            },
          ),
        ],
      ),
      // 화면 본문
      body: Consumer<FriendProvider>(
        builder: (context, provider, child) {
          // 로딩 중일 때
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          // 에러 발생 시
          if (provider.errorMessage != null) {
            return Center(child: Text(provider.errorMessage!));
          }

          // --- 데이터 로딩 성공 시 ---
          return Column(
            children: [
              _buildSearchBar(),
              // ✨ API에서 받아온 '받은 요청' 목록으로 섹션 빌드
              _buildRequestSection(provider),
              _buildFilterBar(),
              Expanded(
                child: ListView.builder(
                  // ✨ API에서 받아온 '수락된 친구' 목록 사용
                  itemCount: provider.acceptedFriends.length,
                  itemBuilder: (context, index) {
                    final friend = provider.acceptedFriends[index];
                    return _NeighborListTile(
                      friend: friend,
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {},
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 3,
        onTap: (_) {},
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

  Widget _buildRequestSection(FriendProvider provider) {
    // 요청이 없으면 아무것도 그리지 않음
    if (provider.receivedRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              '이웃 요청',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          // Column을 사용하여 요청 목록을 순서대로 그림
          ...provider.receivedRequests.map((request) {
            // ✅ [수정] friend 객체를 직접 전달하도록 수정
            return _NeighborListTile(
              friend: request,
              trailing: _AcceptButton(
                onPressed: () {
                  context.read<FriendProvider>().acceptFriendRequest(
                    request.username,
                  );
                },
              ),
            );
          }).toList(),
          const SizedBox(height: 16), // 섹션 간 간격
        ],
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
        // 프로필 이미지가 있으면 보여주고, 없으면 기본 아이콘 표시
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
            '@${friend.username}', // ✅ [수정] friend 객체의 username 사용
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
    // '수락됨' 상태는 Provider가 목록에서 제거해주므로 '수락' 버튼만 필요
    return SizedBox(
      width: 70,
      height: 32,
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
