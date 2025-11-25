import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

/// 개별 댓글 아이템 위젯
class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.commentService,
    required this.currentUser,
    required this.isMe,
    required this.showProfile,
    required this.showAuthorInfo,
    required this.onReactionToggle,
    required this.onLongPress,
    required this.bounceAnimationValue,
    required this.isAnimating,
    required this.onTapTargetComment,
    required this.targetComment,
    required this.globalKey,
    required this.onSwipeReply,
    required this.dragOffset,
    this.onProfileTap,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
  });

  final Comment comment;
  final CommentService commentService;
  final User? currentUser;
  final bool isMe;
  final bool showProfile;
  final bool showAuthorInfo;
  final Function(String commentId, String emoji) onReactionToggle;
  final Function(Offset globalPosition, Comment comment) onLongPress;
  final double bounceAnimationValue;
  final bool isAnimating;
  final Function(String commentId) onTapTargetComment;
  final Comment? targetComment;
  final GlobalKey? globalKey;
  final VoidCallback onSwipeReply;
  final Function(String username)? onProfileTap; // 🎯 프로필 탭 콜백 (선택적)
  final double dragOffset; // 🎯 드래그 오프셋 (부모에서 관리)
  final Function(DragUpdateDetails)? onHorizontalDragUpdate; // 🎯 드래그 업데이트 핸들러
  final Function(DragEndDetails)? onHorizontalDragEnd; // 🎯 드래그 종료 핸들러

  BorderRadius _getBorderRadius() {
    // 첫 번째 버블 (꼬리 있음)
    if (showProfile && showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 20 : 20),
        topRight: Radius.circular(isMe ? 20 : 20),
        bottomLeft: Radius.circular(isMe ? 20 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 20),
      );
    }

    // 마지막 버블 (꼬리 있음, 꼬리 반대편을 더 둥글게)
    if (!showProfile && showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 20 : 4),
        topRight: Radius.circular(isMe ? 6 : 20),
        bottomLeft: Radius.circular(isMe ? 20 : 20), // ← 더 둥글게
        bottomRight: Radius.circular(isMe ? 20 : 20), // ← 더 둥글게
      );
    }

    // 첫 번째이지만 마지막 아님 (위를 더 둥글게)
    if (showProfile && !showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 24 : 24), // ← 더 둥글게
        topRight: Radius.circular(isMe ? 24 : 24), // ← 더 둥글게
        bottomLeft: Radius.circular(isMe ? 20 : 6),
        bottomRight: Radius.circular(isMe ? 6 : 20),
      );
    }

    // 가운데 버블 (양쪽 모서리만 약간 둥글게)
    return BorderRadius.only(
      topLeft: Radius.circular(isMe ? 20 : 6),
      topRight: Radius.circular(isMe ? 6 : 20),
      bottomLeft: Radius.circular(isMe ? 20 : 6),
      bottomRight: Radius.circular(isMe ? 6 : 20),
    );
  }

  String _formatRelativeTime(String isoString) {
    try {
      // UTC 시간을 로컬 시간으로 변환
      final dateTime = TimeUtils.toLocalTime(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return '방금';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}분 전';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}시간 전';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else {
        return '${(difference.inDays / 7).floor()}주 전';
      }
    } catch (e) {
      return '방금';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReactions = comment.emotionCounts.isNotEmpty;

    return GestureDetector(
      onHorizontalDragUpdate:
          onHorizontalDragUpdate != null
              ? (details) => onHorizontalDragUpdate!(details)
              : null,
      onHorizontalDragEnd:
          onHorizontalDragEnd != null
              ? (details) => onHorizontalDragEnd!(details)
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(dragOffset, 0, 0),
        child: Padding(
          key: globalKey,
          padding: EdgeInsets.only(
            top: showProfile ? 8 : 2,
            bottom: showAuthorInfo ? 8 : 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                if (showProfile)
                  _buildProfileImage(context)
                else
                  const SizedBox(width: 34),
                const SizedBox(width: 4),
              ],

              Expanded(
                child: Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment:
                        isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      // 댓글 버블 (답글인 경우 타겟도 포함)
                      _buildCommentBubble(context, hasReactions),

                      // 반응 표시
                      if (hasReactions) _buildReactions(context),
                      // 시간 표시
                      if (showAuthorInfo) _buildTimeStamp(context),
                    ],
                  ),
                ),
              ),

              if (isMe) ...[
                const SizedBox(width: 4),
                // 🎯 내 채팅일 때는 프로필 이미지 표시 안 함
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImage(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 🎯 프로필 탭 콜백이 있으면 사용, 없으면 기본 동작 (프로필 화면으로 이동)
        if (onProfileTap != null) {
          onProfileTap!(comment.author);
        } else {
          // 기본 동작: 프로필 화면으로 이동
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) => UserProfileScreen(
                    otherUser: User(
                      username: comment.author,
                      profileImageUrl: comment.authorProfileImageUrl,
                    ),
                  ),
            ),
          );
        }
      },
      child: CommonProfileAvatar(
        backgroundColor: Colors.transparent,
        imageUrl: comment.authorProfileImageUrl,
        username: comment.author,
        size: 34,
        borderWidth: 0,
      ),
    );
  }

  Widget _buildCommentBubble(BuildContext context, bool hasReactions) {
    return GestureDetector(
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        // 어떤 이모지든 있으면 취소, 없으면 ❤️ 추가
        if (comment.myEmotions.isNotEmpty) {
          // 기존 이모지 취소
          final currentEmoji = comment.myEmotions.keys.first;
          onReactionToggle(comment.id, currentEmoji);
        } else {
          // ❤️ 추가
          onReactionToggle(comment.id, '❤️');
        }
      },
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        onLongPress(details.globalPosition, comment);
      },
      child: Transform.scale(
        scale: isAnimating ? bounceAnimationValue : 1.0,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.55,
          ),
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color:
                isMe
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.9),
            borderRadius: _getBorderRadius(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타겟 댓글이 있으면 표시
              if (targetComment != null) ...[
                GestureDetector(
                  onTap: () => onTapTargetComment(targetComment!.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${targetComment!.author}',
                          style: TextStyle(
                            color:
                                isMe
                                    ? Colors.white.withOpacity(0.8)
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        Text(
                          targetComment!.content,
                          style: TextStyle(
                            color:
                                isMe
                                    ? Colors.white.withOpacity(0.7)
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(
                    height: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.2),
                  ),
                ),
              ],
              // 내 답글 내용
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  targetComment != null ? 8 : 8,
                  12,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.content,
                      style: TextStyle(
                        color:
                            isMe
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    // 전송 실패 시 재시도/삭제 버튼
                    if (comment.isFailed) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              commentService.retryComment(comment.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),

                              child: Row(
                                children: [
                                  Icon(
                                    Icons.refresh,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              commentService.removeFailedComment(comment.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in comment.emotionCounts.entries)
            if (entry.value != '0')
              Container(
                margin: const EdgeInsets.only(right: 1),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),

                child: Text(
                  '${entry.key}${entry.value}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTimeStamp(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        _formatRelativeTime(comment.createdAt),
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
    );
  }
}

/// 댓글 메뉴를 여는 helper 함수
Future<String?> openCommentMenu(
  BuildContext context, {
  required Offset anchor,
  required Comment comment,
  required bool isMyComment, // 내 댓글인지 여부
}) async {
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      anchor.dx - 140,
      anchor.dy + 20,
      anchor.dx,
      anchor.dy,
    ),
    constraints: BoxConstraints(minWidth: 180, maxWidth: 180),

    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    elevation: 8,

    items: [
      // 이모지 반응 (가로 배치)
      PopupMenuItem<String>(
        enabled: false, // 부모 아이템은 클릭 불가
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final emoji in ['❤️', '👍', '😆', '😮', '😭'])
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop(emoji);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      // 답글
      PopupMenuItem<String>(
        value: 'reply',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            AppLocalizations.of(context).translate('reply'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      // 수정 (내 댓글만)
      if (isMyComment)
        PopupMenuItem<String>(
          value: 'edit',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              AppLocalizations.of(context).translate('edit'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // 삭제 (내 댓글만)
      if (isMyComment)
        PopupMenuItem<String>(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              AppLocalizations.of(context).translate('delete'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // 복사
      PopupMenuItem<String>(
        value: 'copy',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            AppLocalizations.of(context).translate('copy'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ],
  );
}
