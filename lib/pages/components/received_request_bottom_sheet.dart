import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_provider.dart';

/// 🎯 받은 요청 리스트 바텀시트 (앱 진입 시 표시)
class ReceivedRequestBottomSheet extends StatefulWidget {
  final List<Friend> requests;

  const ReceivedRequestBottomSheet({Key? key, required this.requests})
    : super(key: key);

  @override
  State<ReceivedRequestBottomSheet> createState() =>
      _ReceivedRequestBottomSheetState();

  static void show(BuildContext context, {required List<Friend> requests}) {}
}

class _ReceivedRequestBottomSheetState
    extends State<ReceivedRequestBottomSheet> {
  final Map<String, bool> _processingRequests = {}; // 🎯 처리 중인 요청 추적

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 🎯 배경 클릭 영역
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.transparent),
          ),
        ),
        // 🎯 바텀시트
        DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return GestureDetector(
              // 🎯 내부 컨텐츠 클릭 시 이벤트 소비 (외부로 전파 방지)
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
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
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(
                                  context,
                                ).translate('new_friend_requests'),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)
                                    .translate('requests_count')
                                    .replaceAll(
                                      '{count}',
                                      '${widget.requests.length}',
                                    ),
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                              size: 24,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 리스트
                    Expanded(
                      child:
                          widget.requests.isEmpty
                              ? Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).translate('no_received_requests'),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              )
                              : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                itemCount: widget.requests.length,
                                itemBuilder: (context, index) {
                                  final request = widget.requests[index];
                                  final isProcessing =
                                      _processingRequests[request.username] ??
                                      false;

                                  return _RequestTile(
                                    request: request,
                                    isProcessing: isProcessing,
                                    onAccept:
                                        () => _handleRequest(request, true),
                                    onReject:
                                        () => _handleRequest(request, false),
                                  );
                                },
                              ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _handleRequest(Friend request, bool accept) async {
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

          // 성공 시 리스트에서 제거
          setState(() {
            widget.requests.removeWhere((r) => r.username == request.username);
            _processingRequests.remove(request.username);
          });

          // 모든 요청이 처리되면 바텀시트 닫기
          if (widget.requests.isEmpty && mounted) {
            Navigator.pop(context);
          }
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

/// 🎯 요청 타일 위젯
class _RequestTile extends StatelessWidget {
  final Friend request;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RequestTile({
    required this.request,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
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
              size: 56,
              borderWidth: 0,
            ),
          ),
          const SizedBox(width: 16),

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
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (request.alias.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    request.username,
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

          // 액션 버튼 또는 로딩 스피너
          isProcessing
              ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 거절 버튼
                  SizedBox(
                    width: 65,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        context.tr('reject'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 수락 버튼
                  SizedBox(
                    width: 65,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        context.tr('accept'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onPrimary,
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
