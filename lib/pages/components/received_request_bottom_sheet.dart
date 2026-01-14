import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';

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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

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
                      '${l10n.t('new_friend_requests')} (${widget.requests.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // 요청 리스트
                    if (widget.requests.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          l10n.t('no_received_requests'),
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: widget.requests.length,
                          itemBuilder: (context, index) {
                            final request = widget.requests[index];
                            final isProcessing =
                                _processingRequests[request.username] ?? false;

                            return _RequestTile(
                              request: request,
                              isProcessing: isProcessing,
                              onAccept: () => _handleRequest(request, true),
                              onReject: () => _handleRequest(request, false),
                            );
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
  }

  Future<void> _handleRequest(Friend request, bool accept) async {
    if (_processingRequests[request.username] == true) return;

    setState(() {
      _processingRequests[request.username] = true;
    });

    try {
      if (!mounted) return;
      final friendProvider = context.read<FriendProvider>();

      bool? result;
      if (accept) {
        // 그룹 기능 제거로 인해 groupProvider 파라미터 제거
        result = await friendProvider.acceptFriendRequest(request.username);
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
