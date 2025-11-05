import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';

/// 개별 댓글 아이템 위젯
class CommentItem extends StatefulWidget {
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
    required this.onSwipeReply,
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
  final VoidCallback onSwipeReply;

  @override
  State<CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<CommentItem> {
  double _dragOffset = 0.0;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      final delta = details.delta.dx;
      // 타인 댓글: 오른쪽으로만 (왼쪽에서 오른쪽), 내 댓글: 왼쪽으로만 (오른쪽에서 왼쪽)
      if (!widget.isMe && delta > 0) {
        _dragOffset = (_dragOffset + delta).clamp(0.0, 80.0);
      } else if (widget.isMe && delta < 0) {
        _dragOffset = (_dragOffset + delta).clamp(-80.0, 0.0);
      }
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 40.0) {
      // 임계값 초과 시 답글 실행
      HapticFeedback.mediumImpact();
      widget.onSwipeReply();
    }

    // 원위치로 복귀 (애니메이션)
    setState(() => _dragOffset = 0.0);
  }

  BorderRadius _getBorderRadius() {
    // 첫 번째 버블 (꼬리 있음)
    if (widget.showProfile && widget.showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(widget.isMe ? 20 : 20),
        topRight: Radius.circular(widget.isMe ? 20 : 20),
        bottomLeft: Radius.circular(widget.isMe ? 20 : 4),
        bottomRight: Radius.circular(widget.isMe ? 4 : 20),
      );
    }

    // 마지막 버블 (꼬리 있음, 꼬리 반대편을 더 둥글게)
    if (!widget.showProfile && widget.showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(widget.isMe ? 20 : 4),
        topRight: Radius.circular(widget.isMe ? 6 : 20),
        bottomLeft: Radius.circular(widget.isMe ? 20 : 20), // ← 더 둥글게
        bottomRight: Radius.circular(widget.isMe ? 20 : 20), // ← 더 둥글게
      );
    }

    // 첫 번째이지만 마지막 아님 (위를 더 둥글게)
    if (widget.showProfile && !widget.showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(widget.isMe ? 24 : 24), // ← 더 둥글게
        topRight: Radius.circular(widget.isMe ? 24 : 24), // ← 더 둥글게
        bottomLeft: Radius.circular(widget.isMe ? 20 : 6),
        bottomRight: Radius.circular(widget.isMe ? 6 : 20),
      );
    }

    // 가운데 버블 (양쪽 모서리만 약간 둥글게)
    return BorderRadius.only(
      topLeft: Radius.circular(widget.isMe ? 20 : 6),
      topRight: Radius.circular(widget.isMe ? 6 : 20),
      bottomLeft: Radius.circular(widget.isMe ? 20 : 6),
      bottomRight: Radius.circular(widget.isMe ? 6 : 20),
    );
  }

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
    final hasReactions = widget.comment.emotionCounts.isNotEmpty;

    return GestureDetector(
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(_dragOffset, 0, 0),
        child: Padding(
          key: widget.globalKey,
          padding: EdgeInsets.only(
            top: widget.showProfile ? 8 : 2,
            bottom: widget.showAuthorInfo ? 8 : 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isMe) ...[
                if (widget.showProfile)
                  _buildProfileImage(context)
                else
                  const SizedBox(width: 34),
                const SizedBox(width: 4),
              ],

              Expanded(
                child: Align(
                  alignment:
                      widget.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment:
                        widget.isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      // 댓글 버블 (답글인 경우 타겟도 포함)
                      _buildCommentBubble(context, hasReactions),

                      // 반응 표시
                      if (hasReactions) _buildReactions(context),

                      // 시간 표시
                      if (widget.showAuthorInfo) _buildTimeStamp(context),
                    ],
                  ),
                ),
              ),

              if (widget.isMe) ...[
                const SizedBox(width: 4),
                if (widget.showProfile)
                  _buildProfileImage(context)
                else
                  const SizedBox(width: 34),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImage(BuildContext context) {
    return CommonProfileAvatar(
      imageUrl: widget.comment.authorProfileImageUrl,
      username: widget.comment.author,
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
        widget.onLongPress(details.globalPosition, widget.comment);
      },
      child: Transform.scale(
        scale: widget.isAnimating ? widget.bounceAnimationValue : 1.0,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4,
          ),
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color:
                widget.isMe
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
              if (widget.targetComment != null) ...[
                GestureDetector(
                  onTap:
                      () => widget.onTapTargetComment(widget.targetComment!.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${widget.targetComment!.author}',
                          style: TextStyle(
                            color:
                                widget.isMe
                                    ? Colors.white.withOpacity(0.8)
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        Text(
                          widget.targetComment!.content,
                          style: TextStyle(
                            color:
                                widget.isMe
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
                  widget.targetComment != null ? 8 : 8,
                  12,
                  8,
                ),
                child: Text(
                  widget.comment.content,
                  style: TextStyle(
                    color:
                        widget.isMe
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
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in widget.comment.emotionCounts.entries)
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
        _formatRelativeTime(widget.comment.createdAt),
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
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '❤️',
              style: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: '👍',
        child: SizedBox(
          height: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '👍',
              style: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: '😆',
        child: SizedBox(
          height: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '😆',
              style: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: '😮',
        child: SizedBox(
          height: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '😮',
              style: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: '😢',
        child: SizedBox(
          height: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              '😢',
              style: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      const PopupMenuDivider(),
      // 답글
      PopupMenuItem<String>(
        value: 'reply',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            '답글',
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
