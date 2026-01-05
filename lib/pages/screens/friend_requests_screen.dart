import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 친구 요청 관리 화면
class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final friendProvider = context.read<FriendProvider>();
      friendProvider.fetchAllFriendData(forceRefresh: false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.t('friend_requests'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: theme.colorScheme.onSurface,
              unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(
                0.5,
              ),
              indicatorColor: theme.colorScheme.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              tabs: [
                Tab(text: l10n.t('received_requests')),
                Tab(text: l10n.t('sent_requests')),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 받은 요청 탭
                _ReceivedRequestsTab(scrollController: _scrollController),
                // 보낸 요청 탭
                _SentRequestsTab(scrollController: _scrollController),
              ],
            ),
          ),
          // 추천 친구 섹션
          _RecommendedFriendsSection(),
        ],
      ),
    );
  }
}

/// 받은 요청 탭
class _ReceivedRequestsTab extends StatefulWidget {
  final ScrollController scrollController;

  const _ReceivedRequestsTab({required this.scrollController});

  @override
  State<_ReceivedRequestsTab> createState() => _ReceivedRequestsTabState();
}

class _ReceivedRequestsTabState extends State<_ReceivedRequestsTab> {
  final Map<String, bool> _processingRequests = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Consumer<FriendProvider>(
      builder: (context, friendProvider, _) {
        final receivedRequests = friendProvider.receivedRequests;
        final isLoading = friendProvider.isLoading;

        if (isLoading && receivedRequests.isEmpty) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          );
        }

        if (receivedRequests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 64,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.t('no_received_requests'),
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount:
              receivedRequests.length +
              (friendProvider.hasMoreReceivedRequests ||
                      friendProvider.isLoadingMoreReceivedRequests
                  ? 1
                  : 0),
          itemBuilder: (context, index) {
            // 더 불러오기
            if (index == receivedRequests.length - 3 &&
                friendProvider.hasMoreReceivedRequests &&
                !friendProvider.isLoadingMoreReceivedRequests) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                friendProvider.loadMoreReceivedRequests();
              });
            }

            // 로딩 인디케이터
            if (index >= receivedRequests.length) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child:
                      friendProvider.isLoadingMoreReceivedRequests
                          ? CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
              );
            }

            final request = receivedRequests[index];
            final isProcessing = _processingRequests[request.username] ?? false;

            return _ReceivedRequestTile(
              request: request,
              isProcessing: isProcessing,
              onAccept: () => _handleRequest(context, request, true),
              onReject: () => _handleRequest(context, request, false),
            );
          },
        );
      },
    );
  }

  Future<void> _handleRequest(
    BuildContext context,
    Friend request,
    bool accept,
  ) async {
    if (_processingRequests[request.username] == true) return;

    setState(() {
      _processingRequests[request.username] = true;
    });

    try {
      if (!mounted) return;
      final friendProvider = context.read<FriendProvider>();
      final groupProvider = context.read<GroupProvider>();

      bool? result;
      if (accept) {
        result = await friendProvider.acceptFriendRequest(
          request.username,
          groupProvider: groupProvider,
        );
      } else {
        result = await friendProvider.rejectFriendRequest(request.username);
      }

      if (mounted) {
        if (result == false) {
          setState(() {
            _processingRequests.remove(request.username);
          });
          ErrorHandler.showError(
            context,
            accept
                ? context.tr('friend_request_accept_failed')
                : context.tr('friend_request_reject_failed'),
          );
        } else {
          // 성공 시 스낵바 표시 (수락인 경우만)
          if (accept && result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)
                      .translate('friend_added')
                      .replaceAll(
                        '{name}',
                        request.alias.isNotEmpty
                            ? request.alias
                            : request.username,
                      ),
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
          }

          setState(() {
            _processingRequests.remove(request.username);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processingRequests.remove(request.username);
        });
        ErrorHandler.showError(
          context,
          accept
              ? context.tr('friend_request_accept_failed')
              : context.tr('friend_request_reject_failed'),
        );
      }
    }
  }
}

/// 받은 요청 타일
class _ReceivedRequestTile extends StatelessWidget {
  final Friend request;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _ReceivedRequestTile({
    required this.request,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // 프로필 아바타
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => UserProfileScreen(
                        otherUser: User(username: request.username),
                      ),
                ),
              );
            },
            child: CommonProfileAvatar(
              imageUrl: request.profileImageUrl ?? '',
              username: request.username,
              size: 54,
              borderWidth: 1,
            ),
          ),
          const SizedBox(width: 12),
          // 사용자 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.alias.isNotEmpty ? request.alias : request.username,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (request.alias.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    request.username,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 액션 버튼 또는 로딩 스피너
          if (isProcessing)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 거절 버튼
                InkWell(
                  onTap: onReject,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.t('reject'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 수락 버튼
                InkWell(
                  onTap: onAccept,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.t('accept'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkTextPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 보낸 요청 탭
class _SentRequestsTab extends StatefulWidget {
  final ScrollController scrollController;

  const _SentRequestsTab({required this.scrollController});

  @override
  State<_SentRequestsTab> createState() => _SentRequestsTabState();
}

class _SentRequestsTabState extends State<_SentRequestsTab> {
  final Set<String> _cancellingRequests = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Consumer<FriendProvider>(
      builder: (context, friendProvider, _) {
        final sentRequests = friendProvider.sentRequests;
        final isLoading = friendProvider.isLoading;

        if (isLoading && sentRequests.isEmpty) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          );
        }

        if (sentRequests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.send_outlined,
                  size: 64,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.t('no_sent_requests'),
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount:
              sentRequests.length +
              (friendProvider.hasMoreSentRequests ||
                      friendProvider.isLoadingMoreSentRequests
                  ? 1
                  : 0),
          itemBuilder: (context, index) {
            // 더 불러오기
            if (index == sentRequests.length - 3 &&
                friendProvider.hasMoreSentRequests &&
                !friendProvider.isLoadingMoreSentRequests) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                friendProvider.loadMoreSentRequests();
              });
            }

            // 로딩 인디케이터
            if (index >= sentRequests.length) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child:
                      friendProvider.isLoadingMoreSentRequests
                          ? CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
              );
            }

            final friend = sentRequests[index];
            return _SentRequestTile(
              friend: friend,
              isCancelling: _cancellingRequests.contains(friend.username),
              onCancel: () => _cancelRequest(context, friend.username),
            );
          },
        );
      },
    );
  }

  Future<void> _cancelRequest(BuildContext context, String username) async {
    if (!mounted) return;

    setState(() {
      _cancellingRequests.add(username);
    });

    try {
      final friendProvider = context.read<FriendProvider>();
      final success = await friendProvider.cancelSentRequestOptimistic(
        username,
      );

      if (mounted) {
        if (!success) {
          ErrorHandler.showError(
            context,
            context.tr('friend_request_cancel_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          context.tr('friend_request_cancel_failed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _cancellingRequests.remove(username);
        });
      }
    }
  }
}

/// 보낸 요청 타일
class _SentRequestTile extends StatelessWidget {
  final Friend friend;
  final bool isCancelling;
  final VoidCallback onCancel;

  const _SentRequestTile({
    required this.friend,
    required this.isCancelling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                        otherUser: User(username: friend.username),
                      ),
                ),
              );
            },
            child: CommonProfileAvatar(
              imageUrl: friend.profileImageUrl ?? '',
              username: friend.username,
              size: 48,
              borderWidth: 0,
            ),
          ),
          const SizedBox(width: 12),
          // 사용자 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.alias.isNotEmpty ? friend.alias : friend.username,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (friend.alias.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    friend.username,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 요청 취소 버튼
          if (isCancelling)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            )
          else
            InkWell(
              onTap: onCancel,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.t('cancel_friend_request'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 추천 친구 섹션
class _RecommendedFriendsSection extends StatefulWidget {
  @override
  State<_RecommendedFriendsSection> createState() =>
      _RecommendedFriendsSectionState();
}

class _RecommendedFriendsSectionState
    extends State<_RecommendedFriendsSection> {
  List<User> _recommendedUsers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 하드코딩된 더미 데이터 (UI 확인용)
    _recommendedUsers = [
      User(username: 'user1', alias: '사용자1', profileImageUrl: null),
      User(username: 'user2', alias: '사용자2', profileImageUrl: null),
      User(username: 'user3', alias: '사용자3', profileImageUrl: null),
      User(username: 'user4', alias: '사용자4', profileImageUrl: null),
      User(username: 'user5', alias: '사용자5', profileImageUrl: null),
      User(username: 'user6', alias: '사용자6', profileImageUrl: null),
    ];
    // TODO: 추천 친구 API 연결
    // _loadRecommendedFriends();
  }

  // TODO: 추천 친구 로드 함수
  // Future<void> _loadRecommendedFriends() async {
  //   setState(() {
  //     _isLoading = true;
  //   });
  //
  //   try {
  //     // 추천 친구 API 호출
  //     // final users = await friendService.getRecommendedFriends();
  //     // setState(() {
  //     //   _recommendedUsers = users;
  //     // });
  //   } catch (e) {
  //     debugPrint('추천 친구 로드 실패: $e');
  //   } finally {
  //     setState(() {
  //       _isLoading = false;
  //     });
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // TODO: 추천 친구가 없으면 숨김 처리 (API 연결 후 활성화)
    // if (_recommendedUsers.isEmpty && !_isLoading) {
    //   return const SizedBox.shrink();
    // }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.t('recommended_friends'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recommendedUsers.length,
                itemBuilder: (context, index) {
                  final user = _recommendedUsers[index];
                  return _RecommendedFriendTile(user: user);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 추천 친구 타일
class _RecommendedFriendTile extends StatelessWidget {
  final User user;

  const _RecommendedFriendTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendProvider = context.read<FriendProvider>();

    return Consumer<FriendProvider>(
      builder: (context, provider, _) {
        final isRequested = provider.sentRequests.any(
          (f) => f.username == user.username,
        );
        final isLoading = provider.isLoadingStatus;

        return Container(
          width: 80,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(otherUser: user),
                    ),
                  );
                },
                child: CommonProfileAvatar(
                  imageUrl: user.profileImageUrl ?? '',
                  username: user.username,
                  size: 64,
                  borderWidth: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user.alias ?? user.username,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (isRequested)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.tr('requested'),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap:
                      isLoading
                          ? null
                          : () async {
                            try {
                              await friendProvider.sendFriendRequest(
                                user.username,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      context
                                          .tr('friend_request_sent')
                                          .replaceAll('{count}', '1'),
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ErrorHandler.showError(
                                  context,
                                  context.tr('friend_request_send_failed'),
                                );
                              }
                            }
                          },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      context.tr('add_friend'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkTextPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
