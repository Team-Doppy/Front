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
import 'package:flutter_svg/svg.dart';
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserSearchBottomSheet(context),
        backgroundColor: Theme.of(context).colorScheme.onSurface,
        foregroundColor: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
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
                      toolbarHeight:
                          kToolbarHeight + 8, // 🎯 빨간 닷이 잘리지 않도록 높이 추가
                      leading: Opacity(
                        opacity: opacity,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      title: Opacity(
                        opacity: opacity,
                        child: Text(
                          context.tr('follow'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      actions: [
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
                                      padding: const EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.arrow_downward_rounded,
                                        size: 28,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                    ),
                                    if (receivedCount > 0)
                                      Positioned(
                                        right: 8,
                                        top: 7,
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
                          child: Consumer<FriendProvider>(
                            builder: (context, friendProvider, _) {
                              final sentCount =
                                  friendProvider.sentRequests.length;
                              return GestureDetector(
                                onTap: () => _showSentRequests(context),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 20.0,
                                        left: 10.0,
                                      ),
                                      child: Icon(
                                        Icons.arrow_upward_rounded,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                        size: 28,
                                      ),
                                    ),
                                    if (sentCount > 0)
                                      Positioned(
                                        right: 8,
                                        top: 7,
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
                                            sentCount > 9 ? '9+' : '$sentCount',
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
          return FriendTile(data: t, isSelected: false, onToggle: () {});
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
  // 🎯 username별 액션(요청/취소) 로딩 상태
  final Map<String, bool> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ✅ 바텀시트 오픈 직후 곧바로 requestFocus를 주면 튀는 케이스가 있어서
      //    아주 짧게 지연 후 포커스(키보드) 올림
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _focusNode.requestFocus();
      });
    });
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
    // query empty UI 갱신용
    if (mounted) setState(() {});
  }

  Future<void> _sendFriendRequest(String username) async {
    if (_actionLoading[username] == true) return;

    setState(() {
      _actionLoading[username] = true;
    });

    try {
      final friendProvider = context.read<FriendProvider>();
      final success = await friendProvider.sendFriendRequestOptimistic(
        username,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context
                    .tr('friend_request_sent_to_user')
                    .replaceAll('{username}', username)
                    .replaceAll('{count}', '1')
                    .replaceAll('명에게', '$username에게'),
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        } else {
          ErrorHandler.showError(
            context,
            context.tr('friend_request_send_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '친구 요청 전송에 실패했습니다');
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading.remove(username);
        });
      }
    }
  }

  Future<void> _cancelFriendRequest(String username) async {
    if (_actionLoading[username] == true) return;

    setState(() {
      _actionLoading[username] = true;
    });

    try {
      final friendProvider = context.read<FriendProvider>();
      final success = await friendProvider.cancelSentRequestOptimistic(
        username,
      );

      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context
                  .tr('request_cancelled_for_user')
                  .replaceAll('{username}', username)
                  .replaceAll('{count}', '1')
                  .replaceAll('개의 팔로우 요청을', '$username 요청을'),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.onSurface,
          ),
        );
      } else {
        ErrorHandler.showError(context, context.tr('cancel_request_failed'));
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, context.tr('cancel_request_failed'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading.remove(username);
        });
      }
    }
  }

  bool _containsUsername(List<Friend> list, String username) {
    return list.any((f) => f.username == username);
  }

  Widget _buildLeftActionButton({
    required ThemeData theme,
    required String username,
    required FriendProvider friendProvider,
  }) {
    final actionRadius = BorderRadius.circular(12);
    final isLoading = _actionLoading[username] == true;
    final isFriend = _containsUsername(
      friendProvider.acceptedFriends,
      username,
    );
    final isReceived = _containsUsername(
      friendProvider.receivedRequests,
      username,
    );
    final isSent = _containsUsername(friendProvider.sentRequests, username);

    // ✅ 친구(수락됨)
    if (isFriend) {
      return SizedBox(
        width: 84,
        height: 38,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withOpacity(0.06),
            borderRadius: actionRadius,
          ),
          child: Center(
            child: Text(
              context.tr('friend'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ),
        ),
      );
    }

    // ✅ 받은 요청이면 응답(수락/거절 바텀시트)
    if (isReceived) {
      return SizedBox(
        width: 84,
        height: 38,
        child: OutlinedButton(
          onPressed:
              isLoading
                  ? null
                  : () {
                    FriendTile.showFriendRequestBottomSheet(context, username);
                  },
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: actionRadius),
            side: BorderSide(
              color: theme.colorScheme.primary.withOpacity(0.65),
              width: 1.2,
            ),
            foregroundColor: theme.colorScheme.primary,
          ),
          child: Text(
            context.tr('respond'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    // ✅ 보낸 요청이면 요청 취소
    if (isSent) {
      return SizedBox(
        width: 84,
        height: 38,
        child: OutlinedButton(
          onPressed: isLoading ? null : () => _cancelFriendRequest(username),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: actionRadius),
            side: BorderSide(
              color: theme.colorScheme.onSurface.withOpacity(0.18),
              width: 1.2,
            ),
            foregroundColor: theme.colorScheme.onSurface,
          ),
          child: Text(
            context.tr('cancel_friend_request'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    // ✅ 기본: 팔로우(=친구요청)
    return SizedBox(
      width: 84,
      height: 38,
      child: ElevatedButton(
        onPressed: isLoading ? null : () => _sendFriendRequest(username),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: actionRadius),
          backgroundColor: theme.colorScheme.onSurface,
          foregroundColor: theme.colorScheme.surface,
          elevation: 0,
        ),
        child: Text(
          context.tr('follow'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchService = context.watch<SearchService>();
    final friendProvider = context.watch<FriendProvider>();
    final query = _searchController.text.trim();
    final accounts = searchService.searchingAccounts;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        // ✅ 키보드가 올라와도 레이아웃이 밀리지 않고 "덮고" 올라오도록 viewInsets 무시
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(viewInsets: EdgeInsets.zero),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // 드래그 핸들
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                // 검색창
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    autofocus: false,
                    cursorColor: theme.colorScheme.onSurface,
                    decoration: InputDecoration(
                      hintText: context.tr('search_username_hint'),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SvgPicture.asset(
                          'assets/icons/ic_search.svg',
                          width: 20,
                          height: 20,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(
                            0.5,
                          ),
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                        1,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                // 검색 결과 리스트
                Expanded(
                  child:
                      !query.isEmpty && searchService.isSearching
                          ? ListView.builder(
                            controller: scrollController,
                            itemCount: 5,
                            itemBuilder: (context, index) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    // 프로필 아바타 Shimmer
                                    ShimmerBox(
                                      width: 58,
                                      height: 58,
                                      shape: const CircleBorder(),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // 이름 Shimmer
                                          ShimmerBox(
                                            width: 120,
                                            height: 18,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // 아이디 Shimmer
                                          ShimmerBox(
                                            width: 90,
                                            height: 14,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 버튼 Shimmer
                                    ShimmerBox(
                                      width: 84,
                                      height: 38,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                          : accounts.isEmpty
                          ? Center(child: Container())
                          : ListView.builder(
                            controller: scrollController,
                            itemCount: accounts.length,
                            itemBuilder: (context, index) {
                              final account = accounts[index];
                              final username = account.username ?? '';
                              final alias =
                                  (account.alias?.isNotEmpty == true)
                                      ? account.alias!
                                      : username;
                              final profileImageUrl =
                                  account.profileImageUrl ?? '';

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => UserProfileScreen(
                                            otherUser: User(username: username),
                                          ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      CommonProfileAvatar(
                                        imageUrl: profileImageUrl,
                                        username: username,
                                        size: 58.0,
                                        // 🎯 프로필 이미지 없을 때만 배경색
                                        backgroundColor:
                                            theme.colorScheme.background,
                                        borderColor: theme.colorScheme.onSurface
                                            .withOpacity(0.1),
                                        borderWidth: 1,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              alias,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '@$username',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w400,
                                                color:
                                                    theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _buildLeftActionButton(
                                        theme: theme,
                                        username: username,
                                        friendProvider: friendProvider,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
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
  final bool isSelected; // 🎯 선택 여부
  final VoidCallback onToggle; // 🎯 선택 토글 콜백

  const FriendTile({
    Key? key,
    required this.data,
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
                borderWidth: 2,
                borderColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.1),
                backgroundColor: Theme.of(context).colorScheme.background,
              ),
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
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
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
