import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/girlfriend_request_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/user_provider.dart';

/// 🎯 받은 요청 리스트 바텀시트 (앱 진입 시 표시)
class ReceivedRequestBottomSheet extends StatefulWidget {
  final List<Friend> requests;

  const ReceivedRequestBottomSheet({Key? key, required this.requests})
    : super(key: key);

  @override
  State<ReceivedRequestBottomSheet> createState() =>
      _ReceivedRequestBottomSheetState();

  static void show(BuildContext context, {required List<Friend> requests}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReceivedRequestBottomSheet(requests: requests),
    );
  }
}

class _ReceivedRequestBottomSheetState
    extends State<ReceivedRequestBottomSheet> {
  final Map<String, bool> _processingRequests = {}; // 🎯 처리 중인 요청 추적

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

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
      final userProvider = context.read<UserProvider>();

      // 🎯 "짝궁 요청(곰신)"은 친구 요청과 분리해서 처리
      // 방법 1: role 필드 확인 (서버에서 제공하는 경우)
      bool isCoupleRequest = false;
      if (request.role != null) {
        final userType = UserTypeExtension.fromServerRole(request.role);
        if (userType == UserType.girlfriend) {
          isCoupleRequest = true;
        }
      }

      // 방법 2: girlfriendRequest 필드 확인 (서버에서 role이 없을 때 대체)
      final currentUser = userProvider.currentUser;
      final girlfriendRequest = currentUser?.girlfriendRequest;
      if (!isCoupleRequest && girlfriendRequest != null) {
        if (girlfriendRequest.requester.username == request.username &&
            girlfriendRequest.status == GirlfriendRequestStatus.pending) {
          isCoupleRequest = true;
        }
      }

      bool? result;
      if (isCoupleRequest) {
        // 서버 스펙: /api/girlfriend-requests/{requestId}/accept|reject
        // Friend 모델에는 requestId가 없으므로 id를 문자열로 사용 (서버에서 id를 그대로 쓰는 형태면 호환)
        final requestId = request.id.toString();
        if (accept) {
          await userProvider.acceptGirlfriendRequest(requestId);
        } else {
          await userProvider.rejectGirlfriendRequest(requestId);
        }
        result = true;
      } else {
        if (accept) {
          // 그룹 기능 제거로 인해 groupProvider 파라미터 제거
          result = await friendProvider.acceptFriendRequest(request.username);
        } else {
          result = await friendProvider.rejectFriendRequest(request.username);
        }
      }

      if (mounted) {
        if (result == false) {
          setState(() {
            _processingRequests.remove(request.username);
          });
          ErrorHandler.showError(
            context,
            accept
                ? (isCoupleRequest
                    ? '짝궁 요청 수락에 실패했어요. 잠시 후 다시 시도해주세요.'
                    : context.tr('friend_request_accept_failed'))
                : (isCoupleRequest
                    ? '짝궁 요청 거절에 실패했어요. 잠시 후 다시 시도해주세요.'
                    : context.tr('friend_request_reject_failed')),
          );
        } else {
          // 성공 시 토스트/스낵바 (수락인 경우만)
          if (accept && result == true) {
            if (isCoupleRequest) {
              ErrorHandler.showInfo(context, '짝궁이 되었어요! 이제 홈에서 함께할 수 있어요.');
            } else {
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
              ? '요청 수락에 실패했어요. 잠시 후 다시 시도해주세요.'
              : '요청 거절에 실패했어요. 잠시 후 다시 시도해주세요.',
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

  /// 🎯 여친인지 확인
  bool get _isGirlfriend {
    if (request.role == null) return false;
    final userType = UserTypeExtension.fromServerRole(request.role);
    return userType == UserType.girlfriend;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isGirlfriend = _isGirlfriend;

    // 🎯 여친인 경우 다른 UI
    if (isGirlfriend) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // 프로필 아바타 (여친 배지 포함)
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
              child: Stack(
                children: [
                  CommonProfileAvatar(
                    imageUrl: request.profileImageUrl ?? '',
                    username: request.username,
                    size: 54,
                    borderWidth: 1.5,
                  ),
                  // 여친 배지
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        '짝궁',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkTextPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        request.alias.isNotEmpty
                            ? request.alias
                            : request.username,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
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
                  const SizedBox(height: 4),
                  Text(
                    '짝궁 맺기 요청이 왔어요',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
                    theme.colorScheme.primary,
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
                          color: theme.colorScheme.primary.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '나중에',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 수락 버튼 (여친용 강조)
                  InkWell(
                    onTap: onAccept,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '짝궁 맺기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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

    // 🎯 일반 요청 UI (기존)
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
