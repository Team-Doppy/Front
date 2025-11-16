import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';

// 친구 요청 수락/거절 바텀시트
class FriendRequestBottomSheet extends StatefulWidget {
  final String username;
  final String? profileImageUrl;

  const FriendRequestBottomSheet({
    Key? key,
    required this.username,
    this.profileImageUrl,
  }) : super(key: key);

  @override
  State<FriendRequestBottomSheet> createState() =>
      _FriendRequestBottomSheetState();
}

class _FriendRequestBottomSheetState extends State<FriendRequestBottomSheet> {
  bool _isAccepting = false; // 🎯 수락 버튼 독립 로딩 상태
  bool _isRejecting = false; // 🎯 거절 버튼 독립 로딩 상태

  @override
  void initState() {
    super.initState();
    // 🎯 타이밍 기반 캐시 사용: 10초 이내 조회했으면 캐시 사용, 아니면 서버에서 조회
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<FriendProvider>().fetchAllFriendData(forceRefresh: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4, // 화면 높이의 40%
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 15),

            // 프로필 정보
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => UserProfileScreen(
                          otherUser: User(username: widget.username),
                        ),
                  ),
                );
              },
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 30),
                        Text(
                          widget.username,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                        ),

                        const SizedBox(height: 4),
                        Text(
                          context.tr('accept_friend_request'),
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onBackground.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                    child: CommonProfileAvatar(
                      imageUrl: widget.profileImageUrl ?? '',
                      username: widget.username,
                      size: 130,
                      borderWidth: 0,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: SizedBox()),

            // 액션 버튼들
            Row(
              children: [
                // 거절 버튼
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        (_isAccepting || _isRejecting)
                            ? null
                            : () => _handleFriendRequest(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.1),
                      foregroundColor:
                          Theme.of(context).colorScheme.onBackground,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        _isRejecting
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(
                              context.tr('reject'),
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                  ),
                ),

                const SizedBox(width: 6),

                // 수락 버튼
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        (_isAccepting || _isRejecting)
                            ? null
                            : () => _handleFriendRequest(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        _isAccepting
                            ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              context.tr('accept'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _handleFriendRequest(bool accept) async {
    if (!mounted) return;

    // 🎯 각 버튼의 독립적인 로딩 상태 설정
    setState(() {
      if (accept) {
        _isAccepting = true;
      } else {
        _isRejecting = true;
      }
    });

    try {
      if (!mounted) return;
      final friendProvider = context.read<FriendProvider>();
      bool? result;

      if (accept) {
        result = await friendProvider.acceptFriendRequest(widget.username);
      } else {
        // 거절 기능이 없으면 단순히 false 반환
        result = false;
      }

      if (mounted) {
        Navigator.pop(context); // 바텀시트 닫기

        if (result == true && mounted) {
          // 친구 데이터 새로고침
          context.read<FriendProvider>().fetchAllFriendData(forceRefresh: true);
        } else if (result == null && mounted) {
          // 🎯 이미 취소된 요청인 경우 - 조용히 처리 (메시지 없이 데이터만 새로고침)
          // 데이터 새로고침하여 UI 업데이트 (이미 Provider에서 처리되었을 수 있음)
          friendProvider.fetchAllFriendData(forceRefresh: true);
        } else if (result == false && mounted) {
          // 일반 실패 메시지 표시
          ErrorHandler.showError(
            context,
            context.tr('friend_request_accept_failed'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ErrorHandler.showError(
          context,
          context.tr('friend_request_accept_failed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          // 🎯 각 버튼의 독립적인 로딩 상태 해제
          if (accept) {
            _isAccepting = false;
          } else {
            _isRejecting = false;
          }
        });
      }
    }
  }
}
