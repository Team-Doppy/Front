import 'dart:ui';

import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart'
    show CustomRefreshIndicator;
import 'package:doppy/pages/components/friend_request_bottom_sheet.dart';
import 'package:doppy/pages/components/received_request_bottom_sheet.dart';
import 'package:doppy/pages/components/sent_requests_list_bottom_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/profile_image_view_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 내 친구 목록 화면
class MyFriendsScreen extends StatefulWidget {
  const MyFriendsScreen({super.key});

  @override
  State<MyFriendsScreen> createState() => _MyFriendsScreenState();
}

class _MyFriendsScreenState extends State<MyFriendsScreen> {
  final ScrollController _scrollController = ScrollController();
  double _appBarOpacity = 1.0;

  @override
  void initState() {
    super.initState();

    // 스크롤 리스너 추가
    _scrollController.addListener(_onScroll);

    // 친구 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final friendProvider = context.read<FriendProvider>();
      if (friendProvider.acceptedFriends.isEmpty && !friendProvider.isLoading) {
        friendProvider.fetchAllFriendData(forceRefresh: false);
      }
    });
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    // 아래로 스크롤할 때 (음수 오프셋): 0~-60 픽셀에서 1.0에서 0.0으로 투명도 변화
    final scrollDistance = offset.abs();
    final opacity = (1.0 - (scrollDistance / 60).clamp(0.0, 1.0));
    if (_appBarOpacity != opacity) {
      setState(() {
        _appBarOpacity = opacity;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    final friendProvider = context.read<FriendProvider>();
    await friendProvider.fetchAllFriendData(forceRefresh: true);
  }

  void _showReceivedRequests(BuildContext context) {
    final friendProvider = context.read<FriendProvider>();
    final receivedRequests = friendProvider.receivedRequests;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => ReceivedRequestBottomSheet(
            requests: List<Friend>.from(receivedRequests),
          ),
    );
  }

  void _showSentRequests(BuildContext context) {
    SentRequestsListBottomSheet.show(context);
  }

  void _showUserSearchBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _UserSearchBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<FriendProvider>(
          builder: (context, friendProvider, _) {
            // 로딩 중이면 투명도 0, 아니면 스크롤에 따른 투명도
            final opacity = friendProvider.isLoading ? 0.0 : _appBarOpacity;

            return CustomRefreshIndicator(
              onRefresh: _handleRefresh,
              child: RawScrollbar(
                controller: _scrollController,
                thumbColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.15),
                radius: const Radius.circular(8),
                thickness: 4,
                thumbVisibility: true,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // SliverAppBar
                    SliverAppBar(
                      scrolledUnderElevation: 0,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      pinned: false, // 상단에 고정하지 않음
                      floating: true, // 위로 스크롤하면 숨겨지고, 아래로 내리면 나타남
                      snap: false, // 스냅 효과 없음 (부드러운 전환)
                      toolbarHeight: kToolbarHeight,
                      leading: Opacity(
                        opacity: opacity,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      actions: [
                        // + 버튼 (유저 검색)
                        Opacity(
                          opacity: opacity,
                          child: GestureDetector(
                            onTap: () => _showUserSearchBottomSheet(context),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Icon(
                                Icons.add,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        // 받은 요청 아이콘
                        Opacity(
                          opacity: opacity,
                          child: Consumer<FriendProvider>(
                            builder: (context, friendProvider, _) {
                              final receivedCount =
                                  friendProvider.receivedRequests.length;
                              return GestureDetector(
                                onTap: () => _showReceivedRequests(context),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Icon(
                                        Icons.person_add,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                    ),
                                    if (receivedCount > 0)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 16,
                                            minHeight: 16,
                                          ),
                                          child: Text(
                                            receivedCount > 9
                                                ? '9+'
                                                : '$receivedCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        // 보낸 요청 아이콘
                        Opacity(
                          opacity: opacity,
                          child: GestureDetector(
                            onTap: () => _showSentRequests(context),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Icon(
                                Icons.person_add_outlined,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // SliverGrid로 친구 목록 표시
                    _buildFriendsSliver(context, friendProvider),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFriendsSliver(
    BuildContext context,
    FriendProvider friendProvider,
  ) {
    // 🎯 친구 로딩 중: Shimmer로 그리드 UI 유지
    if (friendProvider.isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 6,
            childAspectRatio: 0.75,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 프로필 원형 Shimmer
                ShimmerBox(
                  width: 110,
                  height: 110,
                  shape: const CircleBorder(),
                ),
                const SizedBox(height: 6),
                // 이름 Shimmer (한 줄만)
                SizedBox(
                  width: double.infinity,
                  height: 18,
                  child: Center(
                    child: ShimmerBox(
                      width: 80,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            );
          }, childCount: 9),
        ),
      );
    }

    List<Friend> accepted = friendProvider.acceptedFriends;
    List<Friend> received = friendProvider.receivedRequests;

    final List<FriendTileData> tiles = [];
    // 받은 요청 추가
    for (final f in received) {
      tiles.add(
        FriendTileData(
          username: f.username,
          url: f.profileImageUrl,
          alias: f.alias,
          state: FriendState.requestReceived,
        ),
      );
    }
    // 수락된 친구 추가
    for (final f in accepted) {
      tiles.add(
        FriendTileData(
          username: f.username,
          url: f.profileImageUrl,
          alias: f.alias,
          state: FriendState.accepted,
        ),
      );
    }

    // 🎯 로딩 완료 후에만 "친구 없음" 메시지 표시
    if (tiles.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Container()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.tr('no_friends_to_display'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(child: Container()),
            ],
          ),
        ),
      );
    }

    // 무한 스크롤
    final bool shouldLoadMore =
        friendProvider.hasMoreAcceptedFriends &&
        !friendProvider.isLoadingMoreAcceptedFriends;

    final bool showLoadingIndicator =
        friendProvider.isLoadingMoreAcceptedFriends ||
        friendProvider.hasMoreAcceptedFriends;

    final itemCount = tiles.length + (showLoadingIndicator ? 3 : 0);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 6,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          // 🎯 마지막에서 3번째 아이템에 도달하면 더 불러오기
          if (i == tiles.length - 3 && shouldLoadMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              friendProvider.loadMoreAcceptedFriends();
            });
          }

          // 🎯 로딩 인디케이터
          if (i >= tiles.length) {
            return Center(
              child:
                  friendProvider.isLoadingMoreAcceptedFriends
                      ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      )
                      : const SizedBox.shrink(),
            );
          }

          final t = tiles[i];
          return FriendTile(
            data: t,
            isMultiSelectMode: false,
            isSelected: false,
            onToggle: () {},
          );
        }, childCount: itemCount),
      ),
    );
  }
}

/// 유저 검색 및 친구 요청 바텀시트
class _UserSearchBottomSheet extends StatefulWidget {
  @override
  State<_UserSearchBottomSheet> createState() => _UserSearchBottomSheetState();
}

class _UserSearchBottomSheetState extends State<_UserSearchBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Map<String, bool> _sendingRequests = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    // SearchService 검색어 초기화
    SearchService().onSearchChanged('');
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    SearchService().onSearchChanged(query);
  }

  Future<void> _sendFriendRequest(String username) async {
    if (_sendingRequests[username] == true) return;

    setState(() {
      _sendingRequests[username] = true;
    });

    try {
      final friendProvider = context.read<FriendProvider>();
      final success = await friendProvider.sendFriendRequest(username);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$username에게 친구 요청을 보냈습니다'),
              duration: const Duration(seconds: 2),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        } else {
          ErrorHandler.showError(context, '친구 요청 전송에 실패했습니다');
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '친구 요청 전송에 실패했습니다');
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingRequests.remove(username);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 제목
                    Text(
                      '친구 찾기',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // 검색창
                    TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: '사용자 이름 검색',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.onSurface.withOpacity(
                          0.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 검색 결과
                    Flexible(
                      child: Consumer<SearchService>(
                        builder: (context, searchService, _) {
                          final query = _searchController.text.trim();
                          final accounts = searchService.searchingAccounts;

                          if (query.isEmpty) {
                            return Center(
                              child: Text(
                                '사용자 이름을 입력하세요',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                            );
                          }

                          if (searchService.isLoading) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          if (accounts.isEmpty) {
                            return Center(
                              child: Text(
                                '검색 결과가 없습니다',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: accounts.length,
                            itemBuilder: (context, index) {
                              final account = accounts[index];
                              final username = account.username ?? '';
                              final alias = account.alias ?? username;
                              final profileImageUrl =
                                  account.profileImageUrl ?? '';
                              final isSending =
                                  _sendingRequests[username] == true;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    // 프로필 이미지
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => UserProfileScreen(
                                                  otherUser: User(
                                                    username: username,
                                                  ),
                                                ),
                                          ),
                                        );
                                      },
                                      child: CommonProfileAvatar(
                                        imageUrl: profileImageUrl,
                                        username: username,
                                        size: 48,
                                        borderWidth: 0,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // 사용자 정보
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            alias,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          if (alias != username) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              username,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.6),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    // 친구 요청 버튼
                                    if (isSending)
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                theme.colorScheme.onSurface
                                                    .withOpacity(0.6),
                                              ),
                                        ),
                                      )
                                    else
                                      InkWell(
                                        onTap:
                                            () => _sendFriendRequest(username),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '요청',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 닫기 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface
                              .withOpacity(0.03),
                          foregroundColor: theme.colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '닫기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 친구 상태 enum
enum FriendState { requestReceived, accepted }

// 친구 타일 데이터
class FriendTileData {
  final String username;
  final String? url;
  final String? alias;
  final FriendState state;
  FriendTileData({
    required this.username,
    required this.url,
    this.alias,
    required this.state,
  });
}

// --- 친구 타일 위젯 (프로필 아바타, 이름, 별명 표시) ---
class FriendTile extends StatelessWidget {
  final FriendTileData data;
  final bool isMultiSelectMode; // 🎯 다중 선택 모드
  final bool isSelected; // 🎯 선택 여부
  final VoidCallback onToggle; // 🎯 선택 토글 콜백

  const FriendTile({
    Key? key,
    required this.data,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onToggle,
  }) : super(key: key);

  static void showFriendRequestBottomSheet(
    BuildContext context,
    String username,
  ) {
    // 받은 요청에서 해당 사용자의 프로필 이미지 URL 찾기
    final friendProvider = context.read<FriendProvider>();
    final receivedRequest =
        friendProvider.receivedRequests
            .where((friend) => friend.username == username)
            .firstOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
              child: FriendRequestBottomSheet(
                username: username,
                profileImageUrl: receivedRequest?.profileImageUrl,
              ),
            ),
          ),
    );
  }

  // 🎯 고급스러운 멤버 액션 메뉴 (롱프레스) - Hero 애니메이션으로 프로필 이미지 뷰로 이동
  static void showMemberActionMenu(
    BuildContext context,
    String username,
    String? profileImageUrl,
  ) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => ProfileImageViewScreen(
              profileImageUrl: profileImageUrl,
              username: username,
              onShareProfile: () {},
              onCopyProfileLink: () {},
              onGallerySelected: (_) {},
              onSetDefaultImage: () {},
              isOwnProfile: false,
            ),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final bool blur = data.state != FriendState.accepted;
    // 그룹 기능 제거로 인해 그룹 선택 로직 제거

    Widget avatar = GestureDetector(
      onTap: () {
        // 🎯 다중 선택 모드일 때는 선택/해제만
        if (isMultiSelectMode) {
          onToggle();
          return;
        }

        if (data.state == FriendState.requestReceived) {
          // 받은 요청인 경우 수락/거절 바텀시트 표시
          showFriendRequestBottomSheet(context, data.username);
        } else {
          // 수락된 친구인 경우 프로필 화면으로 이동
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => UserProfileScreen(
                    otherUser: User(
                      username: data.username,
                      profileImageUrl: data.url,
                    ),
                  ),
            ),
          );
        }
      },
      onLongPress:
          data.state == FriendState.accepted
              ? () {
                // 🎯 롱프레스 시 고급스러운 액션 메뉴
                showMemberActionMenu(context, data.username, data.url);
              }
              : null,
      child: Stack(
        children: [
          Hero(
            tag: 'profile_image_${data.username}',
            createRectTween: (begin, end) {
              // ✅ 직선 경로(나갈 때처럼 자연스럽게)
              return RectTween(begin: begin, end: end);
            },
            flightShuttleBuilder: (
              flightContext,
              animation,
              flightDirection,
              fromHeroContext,
              toHeroContext,
            ) {
              // ✅ 비행 중에는 "출발/도착 Hero의 child"를 그대로 재사용해야
              //    CachedNetworkImage placeholder ↔ image 스왑으로 인한 시작 깜빡임이 줄어듭니다.
              final fromHero =
                  fromHeroContext.widget is Hero
                      ? (fromHeroContext.widget as Hero).child
                      : fromHeroContext.widget;
              final toHero =
                  toHeroContext.widget is Hero
                      ? (toHeroContext.widget as Hero).child
                      : toHeroContext.widget;

              final stableChild =
                  flightDirection == HeroFlightDirection.push
                      ? fromHero
                      : toHero;

              return SizedBox(
                width: 110,
                height: 110,
                child: Material(color: Colors.transparent, child: stableChild),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: StaticProfileAvatar(
                key: ValueKey(
                  'static_avatar_${data.url}_${data.username}',
                ), // ✅ 이미지 URL이 바뀔 때 완전히 재생성하여 잔상 방지
                imageUrl: data.url,
                username: data.username,
                size: 110,
                borderWidth: 0.5,
                borderColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.1),
                backgroundColor: Theme.of(context).colorScheme.background,
              ),
            ),
          ),
          // 🎯 다중 선택 모드일 때 체크 표시
          if (isMultiSelectMode)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected
                          ? Colors.white.withOpacity(0.7)
                          : Colors.transparent,
                ),
                child:
                    isSelected
                        ? Center(
                          child: Container(
                            width: 36,
                            height: 36,

                            child: Icon(
                              Icons.check,
                              color: Colors.black,
                              size: 40,
                            ),
                          ),
                        )
                        : null,
              ),
            ),
        ],
      ),
    );

    if (blur) {
      avatar = Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                data.state == FriendState.requestReceived
                    ? Theme.of(context).colorScheme.primary
                    : Colors.pink.withOpacity(0.8),
            width: data.state == FriendState.requestReceived ? 3.5 : 2,
          ),
        ),
        child: ClipOval(
          child: Stack(alignment: Alignment.center, children: [avatar]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatar,
        const SizedBox(height: 6),
        // 🎯 텍스트가 잘리지 않도록 SizedBox로 최소 높이 보장
        SizedBox(
          width: double.infinity,
          height: 18, // 최소 높이 보장
          child: Center(
            child: Text(
              "@" + data.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (data.alias != null && data.alias!.isNotEmpty) ...[
          const SizedBox(height: 2),
          // 🎯 텍스트가 잘리지 않도록 SizedBox로 최소 높이 보장
          SizedBox(
            width: double.infinity,
            height: 16, // 최소 높이 보장
            child: Center(
              child: Text(
                data.alias!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
