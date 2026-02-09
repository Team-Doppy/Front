import 'dart:ui';

import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/data/models/girlfriend_request_model.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart'
    show CustomRefreshIndicator;
import 'package:doppy/pages/components/friend_request_bottom_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/profile_image_view_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/text_bold_utils.dart';
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

  void _showUserSearchBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => UserSearchBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 메인 콘텐츠
            Consumer2<FriendProvider, UserProvider>(
              builder: (context, friendProvider, userProvider, _) {
                // 로딩 중이면 투명도 0, 아니면 스크롤에 따른 투명도
                final opacity = friendProvider.isLoading ? 0.0 : _appBarOpacity;
                final currentUser = userProvider.currentUser;

                // ✅ 커플 연결 상태 확인
                final isGirlfriend =
                    currentUser?.militaryInfo?.userType == UserType.girlfriend;
                final connectedMilitaryUser =
                    currentUser?.connectedMilitaryUser; // 곰신일 때
                final connectedGirlfriend =
                    currentUser?.connectedToMeByUser; // 군인/입대예정일 때
                final hasCouple =
                    (isGirlfriend && connectedMilitaryUser != null) ||
                    (!isGirlfriend && connectedGirlfriend != null);

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
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                        // ✅ 짝궁 섹션 (커플이 연결되어 있을 때만 표시)
                        if (hasCouple)
                          _buildCoupleSection(
                            context,
                            isGirlfriend,
                            connectedMilitaryUser,
                            connectedGirlfriend,
                            currentUser,
                          ),
                        // 받은 요청 섹션 (가로 스크롤)
                        _buildReceivedRequestsSection(
                          context,
                          friendProvider,
                          connectedGirlfriend?.username,
                        ),
                        // 보낸 요청 섹션 (가로 스크롤)
                        _buildSentRequestsSection(context, friendProvider),
                        // 수락된 친구 그리드
                        _buildAcceptedFriendsSliver(context, friendProvider),
                      ],
                    ),
                  ),
                );
              },
            ),
            // ✅ FloatingActionButton (Stack으로 직접 배치)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () => _showUserSearchBottomSheet(context),
                backgroundColor: Theme.of(context).colorScheme.onSurface,
                foregroundColor: Theme.of(context).colorScheme.surface,
                shape: const CircleBorder(),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ 짝궁 섹션 (커플 연결 표시)
  Widget _buildCoupleSection(
    BuildContext context,
    bool isGirlfriend,
    User? connectedMilitaryUser,
    User? connectedGirlfriend,
    User? currentUser,
  ) {
    // 연결된 상대방 정보
    final partner = isGirlfriend ? connectedMilitaryUser : connectedGirlfriend;
    if (partner == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ✅ 짝궁 타이틀 + pairAlias 표시
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // ✅ pairAlias가 있으면 애칭으로 표시, 없으면 "짝궁"
                        (partner.pairAlias != null &&
                                partner.pairAlias!.isNotEmpty)
                            ? partner.pairAlias!
                            : '짝궁',
                        style: LocaleTypography.setStyle(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed:
                      () => _showCoupleSettingsBottomSheet(
                        context,
                        isGirlfriend,
                        partner,
                        currentUser,
                      ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // 현재 사용자 프로필
                Expanded(
                  child: _buildCoupleProfileTile(
                    context,
                    currentUser?.profileImageUrl,
                    currentUser?.alias ?? currentUser?.username ?? '',
                    currentUser?.username ?? '',
                  ),
                ),
                const SizedBox(width: 12),
                // 상대방 프로필
                Expanded(
                  child: _buildCoupleProfileTile(
                    context,
                    partner.profileImageUrl,
                    partner.alias ?? partner.username,
                    partner.username,
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
          // ✅ 다른 섹션들과 동일한 간격 (받은 요청, 보낸 요청과 동일)
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ✅ 커플 프로필 타일
  Widget _buildCoupleProfileTile(
    BuildContext context,
    String? profileImageUrl,
    String alias,
    String username,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => UserProfileScreen(otherUser: User(username: username)),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommonProfileAvatar(
            imageUrl: profileImageUrl,
            username: username,
            size: 110.0,
            backgroundColor: Theme.of(context).colorScheme.background,
            borderColor: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(0.1),
            borderWidth: 2,
          ),
          const SizedBox(height: 8),
          Text(
            alias,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: LocaleTypography.setStyle(
              context: context,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 커플 설정 바텀시트 표시
  void _showCoupleSettingsBottomSheet(
    BuildContext context,
    bool isGirlfriend,
    User partner,
    User? currentUser,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => CoupleSettingsBottomSheet(
            isGirlfriend: isGirlfriend,
            partner: partner,
            currentUser: currentUser,
          ),
    );
  }

  // 🎯 받은 요청 섹션 (가로 스크롤)
  Widget _buildReceivedRequestsSection(
    BuildContext context,
    FriendProvider friendProvider,
    String? connectedGirlfriendUsername, // 🎯 이미 짝궁인 사용자 username
  ) {
    // 🎯 받은 요청에서 이미 짝궁인 사용자 제외 (곰신 요청 수락 완료)
    final received =
        friendProvider.receivedRequests.where((request) {
          // 곰신 요청이고 이미 짝궁인 경우 제외
          if (connectedGirlfriendUsername != null &&
              request.username == connectedGirlfriendUsername) {
            return false;
          }
          return true;
        }).toList();

    if (received.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            child: Text(
              context.tr('received_requests'),
              style: LocaleTypography.setStyle(
                context: context,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            height: 160,
            child: NotificationListener<ScrollNotification>(
              // 🎯 가로 스크롤 알림을 차단하여 새로고침 제스처와 분리
              onNotification: (notification) => true,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: received.length,
                itemBuilder: (context, index) {
                  final friend = received[index];
                  // 🎯 곰신 요청인지 확인
                  // 방법 1: role 필드 확인 (서버에서 제공하는 경우)
                  bool isCoupleRequest = false;
                  if (friend.role != null) {
                    final userType = UserTypeExtension.fromServerRole(
                      friend.role,
                    );
                    if (userType == UserType.girlfriend) {
                      isCoupleRequest = true;
                    }
                  }

                  // 방법 2: girlfriendRequest 필드 확인 (서버에서 role이 없을 때 대체)
                  final userProvider = context.watch<UserProvider>();
                  final currentUser = userProvider.currentUser;
                  final girlfriendRequest = currentUser?.girlfriendRequest;
                  if (!isCoupleRequest && girlfriendRequest != null) {
                    if (girlfriendRequest.requester.username ==
                            friend.username &&
                        girlfriendRequest.status ==
                            GirlfriendRequestStatus.pending) {
                      isCoupleRequest = true;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FriendTile(
                      data: FriendTileData(
                        username: friend.username,
                        url: friend.profileImageUrl,
                        alias: friend.alias,
                        state: FriendState.requestReceived,
                        isCoupleRequest: isCoupleRequest, // ✅ 곰신 요청 여부 전달
                      ),
                      isSelected: false,
                      onToggle: () {},
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 🎯 보낸 요청 섹션 (가로 스크롤)
  Widget _buildSentRequestsSection(
    BuildContext context,
    FriendProvider friendProvider,
  ) {
    final sent = friendProvider.sentRequests;

    if (sent.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            child: Text(
              context.tr('sent_requests'),
              style: LocaleTypography.setStyle(
                context: context,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            height: 160,
            child: NotificationListener<ScrollNotification>(
              // 🎯 가로 스크롤 알림을 차단하여 새로고침 제스처와 분리
              onNotification: (notification) => true,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sent.length,
                itemBuilder: (context, index) {
                  final friend = sent[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FriendTile(
                      data: FriendTileData(
                        username: friend.username,
                        url: friend.profileImageUrl,
                        alias: friend.alias,
                        state: FriendState.accepted, // 보낸 요청은 일반 표시
                      ),
                      isSelected: false,
                      onToggle: () {},
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 🎯 수락된 친구 그리드
  Widget _buildAcceptedFriendsSliver(
    BuildContext context,
    FriendProvider friendProvider,
  ) {
    final List<Friend> accepted = friendProvider.acceptedFriends;
    final List<Friend> received = friendProvider.receivedRequests;
    final List<Friend> sent = friendProvider.sentRequests;
    final List<User> recommended = friendProvider.friendRecommendations;

    // ✅ 받은 요청 또는 보낸 요청만 있어도 추천 친구 표시
    final bool showRecommended =
        accepted.isEmpty &&
        !friendProvider.isLoading &&
        (received.isNotEmpty || sent.isNotEmpty || recommended.isNotEmpty);

    // ✅ 모든 것이 없을 때 체크 (친구, 추천친구, 받은 요청, 보낸 요청 모두 없음)
    final bool isEmpty =
        accepted.isEmpty &&
        received.isEmpty &&
        sent.isEmpty &&
        recommended.isEmpty &&
        !friendProvider.isLoading;

    // ✅ 추천 친구 최대 10명만 표시 (원래 순서 유지, 매 프레임 섞이지 않도록)
    final List<User> limitedRecommended = recommended.take(10).toList();

    // 🎯 수락된 친구 섹션 제목과 그리드
    return SliverMainAxisGroup(
      slivers: [
        // ✅ 모든 것이 없을 때: 가운데에 "아직 친구가 없어요"만 표시
        if (isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
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
          )
        else ...[
          // 섹션 제목
          if (accepted.isNotEmpty ||
              friendProvider.isLoading ||
              showRecommended)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
                child: Text(
                  showRecommended
                      ? context.tr('no_friends_to_display')
                      : context.tr('all_friends'),
                  style: LocaleTypography.setStyle(
                    context: context,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          // 🎯 친구 로딩 중: Shimmer로 그리드 UI 유지
          if (friendProvider.isLoading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
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
            )
          // 🎯 친구가 없을 때 또는 받은/보낸 요청만 있을 때 추천 친구 그리드 표시
          else if (showRecommended)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
              sliver:
                  recommended.isEmpty
                      ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(child: Container()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
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
                      )
                      : SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 6,
                              childAspectRatio: 0.75,
                            ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          if (i >= limitedRecommended.length) {
                            return const SizedBox.shrink();
                          }

                          final user = limitedRecommended[i];
                          return FriendTile(
                            data: FriendTileData(
                              username: user.username,
                              url: user.profileImageUrl,
                              alias: user.alias,
                              state: FriendState.accepted,
                            ),
                            isSelected: false,
                            onToggle: () {},
                          );
                        }, childCount: limitedRecommended.length),
                      ),
            )
          // 무한 스크롤 그리드
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final bool shouldLoadMore =
                        friendProvider.hasMoreAcceptedFriends &&
                        !friendProvider.isLoadingMoreAcceptedFriends;

                    // 🎯 마지막에서 3번째 아이템에 도달하면 더 불러오기
                    if (i == accepted.length - 3 && shouldLoadMore) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        friendProvider.loadMoreAcceptedFriends();
                      });
                    }

                    // 🎯 로딩 인디케이터
                    if (i >= accepted.length) {
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

                    final friend = accepted[i];
                    return FriendTile(
                      data: FriendTileData(
                        username: friend.username,
                        url: friend.profileImageUrl,
                        alias: friend.alias,
                        state: FriendState.accepted,
                      ),
                      isSelected: false,
                      onToggle: () {},
                    );
                  },
                  childCount:
                      accepted.length +
                      (friendProvider.isLoadingMoreAcceptedFriends ||
                              friendProvider.hasMoreAcceptedFriends
                          ? 3
                          : 0),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 유저 검색 및 친구 요청 바텀시트
class UserSearchBottomSheet extends StatefulWidget {
  @override
  State<UserSearchBottomSheet> createState() => UserSearchBottomSheetState();
}

class UserSearchBottomSheetState extends State<UserSearchBottomSheet> {
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
        } else {
          ErrorHandler.showError(
            context,
            context.tr('friend_request_send_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          context.tr('friend_request_send_failed'),
        );
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
        ErrorHandler.showInfo(
          context,
          context
              .tr('request_cancelled_for_user')
              .replaceAll('{username}', username)
              .replaceAll('{count}', '1')
              .replaceAll('개의 팔로우 요청을', '$username 요청을'),
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                          : accounts.isEmpty && query.isEmpty
                          ? Center(
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    MediaQuery.of(context).viewInsets.bottom,
                              ),
                              child: Text(
                                context.tr('no_search_results_short'),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ),
                          )
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
  final bool isCoupleRequest; // ✅ 곰신 요청 여부
  FriendTileData({
    required this.username,
    required this.url,
    this.alias,
    required this.state,
    this.isCoupleRequest = false, // 기본값 false
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
    final userProvider = context.read<UserProvider>();
    final receivedRequest =
        friendProvider.receivedRequests
            .where((friend) => friend.username == username)
            .firstOrNull;

    // 🎯 곰신 요청인지 확인
    // 방법 1: role 필드 확인 (서버에서 제공하는 경우)
    bool isCoupleRequest = false;
    if (receivedRequest?.role != null) {
      final userType = UserTypeExtension.fromServerRole(receivedRequest!.role);
      if (userType == UserType.girlfriend) {
        isCoupleRequest = true;
      }
    }

    // 방법 2: girlfriendRequest 필드 확인 (서버에서 role이 없을 때 대체)
    final currentUser = userProvider.currentUser;
    final girlfriendRequest = currentUser?.girlfriendRequest;
    if (!isCoupleRequest && girlfriendRequest != null) {
      if (girlfriendRequest.requester.username == username &&
          girlfriendRequest.status == GirlfriendRequestStatus.pending) {
        isCoupleRequest = true;
      }
    }

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
                isCoupleRequest: isCoupleRequest, // ✅ 곰신 요청 여부 전달
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
          // ✅ 곰신 요청일 때 하트 아이콘 표시 (가운데)
          if (data.isCoupleRequest && data.state == FriendState.requestReceived)
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 16,
                  ),
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
        // 🎯 가로 스크롤에서도 작동하도록 고정 너비 사용
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Center(
            child: Text(
              data.alias ?? data.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: LocaleTypography.setStyle(
                context: context,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: textColor.withOpacity(0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ✅ 커플 설정 바텀시트
class CoupleSettingsBottomSheet extends StatefulWidget {
  final bool isGirlfriend;
  final User partner;
  final User? currentUser;

  const CoupleSettingsBottomSheet({
    super.key,
    required this.isGirlfriend,
    required this.partner,
    this.currentUser,
  });

  @override
  State<CoupleSettingsBottomSheet> createState() =>
      _CoupleSettingsBottomSheetState();
}

class _CoupleSettingsBottomSheetState extends State<CoupleSettingsBottomSheet> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isDisconnecting = false;

  @override
  void initState() {
    super.initState();
    // ✅ 서버에서 받은 pairAlias를 TextField에 설정
    final pairAlias = widget.partner.pairAlias;
    if (pairAlias != null && pairAlias.isNotEmpty) {
      _nicknameController.text = pairAlias;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _handleDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('헤어지기'),
            content: const Text('정말 헤어지시겠어요? 연결이 해제되면 다시 연결할 수 없습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('헤어지기'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDisconnecting = true;
    });

    try {
      final userProvider = context.read<UserProvider>();
      await userProvider.disconnectMilitaryConnection();
      if (mounted) {
        Navigator.of(context).pop(); // 바텀시트 닫기
        final myAlias =
            widget.currentUser?.alias ?? widget.currentUser?.username ?? '';
        ErrorHandler.showInfo(context, '힘내요, $myAlias');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: '헤어짐 실패');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDisconnecting = false;
        });
      }
    }
  }

  Future<void> _handleSaveNickname() async {
    final nickname = _nicknameController.text.trim();

    // ✅ 빈 문자열이면 삭제 (null로 전송)
    final pairAliasToSave = nickname.isEmpty ? null : nickname;

    try {
      final userProvider = context.read<UserProvider>();
      await userProvider.updatePairAlias(pairAliasToSave);

      if (mounted) {
        Navigator.of(context).pop(); // 바텀시트 닫기
        ErrorHandler.showInfo(context, '애칭이 저장되었어요');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: '애칭 저장에 실패했어요');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Material(
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
              // 제목
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '짝궁 설정',
                      style: LocaleTypography.setStyle(
                        context: context,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // 스크롤 가능한 내용
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // 현재 곰신일 수 있음 표시
                    if (widget.isGirlfriend)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withOpacity(
                            0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '현재 곰신일 수 있습니다',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.isGirlfriend) const SizedBox(height: 20),

                    // 커플 애칭 설정
                    Text(
                      '짝궁 애칭',
                      style: LocaleTypography.setStyle(
                        context: context,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nicknameController,
                      decoration: InputDecoration(
                        hintText: '예: 내 짝궁, 우리 커플 등',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
                          0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleSaveNickname,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('저장'),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 헤어짐 버튼
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isDisconnecting ? null : _handleDisconnect,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: theme.colorScheme.error.withOpacity(0.5),
                          ),
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child:
                            _isDisconnecting
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text('헤어지기'),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
