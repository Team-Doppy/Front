import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';

// 보낸 친구요청 리스트 바텀시트
class SentRequestsListBottomSheet extends StatefulWidget {
  const SentRequestsListBottomSheet({Key? key}) : super(key: key);

  @override
  State<SentRequestsListBottomSheet> createState() =>
      _SentRequestsListBottomSheetState();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SentRequestsListBottomSheet(),
    );
  }
}

class _SentRequestsListBottomSheetState
    extends State<SentRequestsListBottomSheet> {
  Set<String> _cancellingRequests = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Consumer<FriendProvider>(
      builder: (context, friendProvider, child) {
        final sentRequests = friendProvider.sentRequests;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                      borderRadius: BorderRadius.circular(50),
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
                          '${l10n.t('sent_requests')} (${sentRequests.length})',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        // 요청 리스트
                        if (sentRequests.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              l10n.t('no_sent_requests'),
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount:
                                  sentRequests.length +
                                  (friendProvider.hasMoreSentRequests ||
                                          friendProvider
                                              .isLoadingMoreSentRequests
                                      ? 1
                                      : 0),
                              itemBuilder: (context, index) {
                                // 🎯 마지막 아이템에 도달하면 더 불러오기
                                if (index == sentRequests.length - 3 &&
                                    friendProvider.hasMoreSentRequests &&
                                    !friendProvider.isLoadingMoreSentRequests) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    friendProvider.loadMoreSentRequests();
                                  });
                                }

                                // 🎯 로딩 인디케이터
                                if (index >= sentRequests.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child:
                                          friendProvider
                                                  .isLoadingMoreSentRequests
                                              ? CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(
                                                      theme
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.6),
                                                    ),
                                              )
                                              : const SizedBox.shrink(),
                                    ),
                                  );
                                }

                                final friend = sentRequests[index];
                                return _buildRequestTile(context, friend);
                              },
                            ),
                          ),
                        const SizedBox(height: 24),
                        // 취소 버튼
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
                            child: Text(
                              l10n.t('cancel'),
                              style: const TextStyle(
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
      },
    );
  }

  Widget _buildRequestTile(BuildContext context, Friend friend) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isCancelling = _cancellingRequests.contains(friend.username);

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
              onTap: () => _cancelRequest(context, friend.username),
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
        if (success) {
          // 취소 성공 (이미 FriendProvider에서 목록 업데이트됨)
          // 스낵바는 표시하지 않음 (사용자 요청에 따라)
        } else {
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
