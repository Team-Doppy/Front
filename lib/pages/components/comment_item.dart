import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';

/// 개별 댓글 아이템 위젯
class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.comment,
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
  });

  final Comment comment;
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

  String _formatRelativeTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
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

    return Padding(
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
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
            if (showProfile)
              _buildProfileImage(context)
            else
              const SizedBox(width: 34),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileImage(BuildContext context) {
    return CommonProfileAvatar(
      imageUrl: comment.authorProfileImageUrl,
      username: comment.author,
      size: 34,
      borderWidth: 1,
      borderColor: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withOpacity(0.3),
    );
  }

  Widget _buildCommentBubble(BuildContext context, bool hasReactions) {
    return GestureDetector(
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        onLongPress(details.globalPosition, comment);
      },
      onDoubleTap: () => onReactionToggle(comment.id, '❤️'),
      child: Transform.scale(
        scale: isAnimating ? bounceAnimationValue : 1.0,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4,
          ),
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color:
                isMe
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.9),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
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
                child: Text(
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in comment.emotionCounts.entries)
            if (entry.value != '0')
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: const TextStyle(fontSize: 12),
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
        '${comment.author} • ${_formatRelativeTime(comment.createdAt)}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          fontSize: 11,
        ),
      ),
    );
  }

  static Future<String?> openMessageMenu(
    BuildContext context, {
    required Offset anchor,
    required Comment comment,
  }) async {
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        anchor.dx - 100,
        anchor.dy + 20,
        anchor.dx,
        anchor.dy,
      ),
      constraints: BoxConstraints(maxWidth: 200),
      color: Theme.of(context).colorScheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      elevation: 8,

      items: [
        // 이모지 반응
        PopupMenuItem<String>(
          value: '❤️',
          child: SizedBox(
            height: 32,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    const ['❤️', '😮', '😡', '👍', '🔥', '👏'].map((emoji) {
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pop(emoji),
                        child: SizedBox(
                          height: 24,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
        ),
        // 답글 달기
        PopupMenuItem<String>(
          value: 'reply',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              '답글 달기',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // 수정
        PopupMenuItem<String>(
          value: 'edit',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              '수정',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // 삭제
        PopupMenuItem<String>(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              '삭제',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
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
              '복사',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
