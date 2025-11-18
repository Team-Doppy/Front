import 'dart:ui' as ui;
import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/friend_request_bottom_sheet.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';

// 받은 친구요청 리스트 바텀시트
class FriendRequestsListBottomSheet extends StatelessWidget {
  const FriendRequestsListBottomSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<FriendProvider>(
      builder: (context, friendProvider, child) {
        final receivedRequests = friendProvider.receivedRequests;

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // 드래그 핸들
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          "${context.tr('received_requests')} (${receivedRequests.length})",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  // 리스트
                  Expanded(
                    child:
                        receivedRequests.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [],
                              ),
                            )
                            : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              itemCount:
                                  receivedRequests.length +
                                  (friendProvider.hasMoreReceivedRequests ||
                                          friendProvider
                                              .isLoadingMoreReceivedRequests
                                      ? 1
                                      : 0),
                              separatorBuilder:
                                  (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                // 🎯 마지막 아이템에 도달하면 더 불러오기
                                if (index == receivedRequests.length - 3 &&
                                    friendProvider.hasMoreReceivedRequests &&
                                    !friendProvider
                                        .isLoadingMoreReceivedRequests) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    friendProvider.loadMoreReceivedRequests();
                                  });
                                }

                                // 🎯 로딩 인디케이터
                                if (index >= receivedRequests.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Center(
                                      child:
                                          friendProvider
                                                  .isLoadingMoreReceivedRequests
                                              ? const CircularProgressIndicator()
                                              : const SizedBox.shrink(),
                                    ),
                                  );
                                }

                                final friend = receivedRequests[index];
                                return _buildRequestTile(context, friend);
                              },
                            ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestTile(BuildContext context, Friend friend) {
    return _FriendRequestTileWithActions(
      friend: friend,
      onTap: () {
        Navigator.pop(context); // 리스트 바텀시트 닫기
        // 받은 요청 상세 바텀시트 표시
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder:
              (context) => BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                  ),
                  child: FriendRequestBottomSheet(
                    username: friend.username,
                    profileImageUrl: friend.profileImageUrl,
                  ),
                ),
              ),
        );
      },
      onReject: () async {
        final friendProvider = context.read<FriendProvider>();
        try {
          // 🎯 거절 기능 호출
          final success = await friendProvider.rejectFriendRequest(
            friend.username,
          );
          if (!success && context.mounted) {
            ErrorHandler.showError(
              context,
              context.tr('friend_request_reject_failed'),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ErrorHandler.showError(
              context,
              context.tr('friend_request_reject_failed'),
            );
          }
        }
      },
    );
  }

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const FriendRequestsListBottomSheet(),
    );
  }
}

// 스와이프 액션이 있는 친구 요청 타일
class _FriendRequestTileWithActions extends StatefulWidget {
  final Friend friend;
  final VoidCallback onTap;
  final VoidCallback onReject;

  const _FriendRequestTileWithActions({
    required this.friend,
    required this.onTap,
    required this.onReject,
  });

  @override
  State<_FriendRequestTileWithActions> createState() =>
      _FriendRequestTileWithActionsState();
}

class _FriendRequestTileWithActionsState
    extends State<_FriendRequestTileWithActions> {
  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          // 왼쪽으로만 밀기 지원 (primaryDelta가 음수)
          _dragOffset += details.primaryDelta!;
          // 오른쪽으로 밀리는 것 방지 및 왼쪽으로 제한
          if (_dragOffset > 0) _dragOffset = 0;
          if (_dragOffset < -200) _dragOffset = -200;
        });
      },
      onHorizontalDragEnd: (details) {
        // 스냅: 일정 이상 밀리면 고정(-70), 아니면 원위치(0)
        const double openThreshold = -30.0;
        setState(() {
          _dragOffset = (_dragOffset <= openThreshold) ? -70.0 : 0.0;
        });
      },
      onTap: () {
        // 탭은 항목 선택으로 처리
        if (_dragOffset != 0) {
          // 드래그 상태면 먼저 닫기
          setState(() {
            _dragOffset = 0.0;
          });
          // no-op
        } else {
          widget.onTap();
        }
      },
      child: Stack(
        children: [
          // 거절 버튼 (왼쪽으로 밀렸을 때 나타남)
          if (_dragOffset < -40)
            Positioned(
              left: MediaQuery.of(context).size.width + _dragOffset,
              top: 0,
              bottom: 0,
              width: 70,
              child: GestureDetector(
                onTap: () async {
                  // 먼저 원위치로 복귀
                  setState(() => _dragOffset = 0.0);
                  // 거절 처리
                  widget.onReject();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withOpacity(0.12),
                  ),
                  child: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.error,
                    size: 24,
                  ),
                ),
              ),
            ),

          // 메인 컨텐츠
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: InkWell(
                onTap: () {
                  if (_dragOffset != 0) {
                    // 드래그 상태면 먼저 닫기
                    setState(() {
                      _dragOffset = 0.0;
                    });
                    // no-op
                  } else {
                    widget.onTap();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      // 프로필 이미지
                      CommonProfileAvatar(
                        imageUrl: widget.friend.profileImageUrl ?? '',
                        username: widget.friend.username,
                        size: 56,
                        borderWidth: 0.5,
                      ),
                      const SizedBox(width: 16),

                      // 사용자 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.friend.username,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (widget.friend.alias.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.friend.alias,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // 화살표 아이콘
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
