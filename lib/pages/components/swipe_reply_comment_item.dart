import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/pages/components/comment_item.dart';
import 'package:flutter/material.dart';

/// ✅ MediaCommentItem 패턴: 아이템이 스와이프 상태를 직접 들고 처리
/// - 우측(→) 스와이프하면 답글 트리거
/// - 실제 렌더링은 기존 `CommentItem`을 그대로 사용
class SwipeReplyCommentItem extends StatefulWidget {
  const SwipeReplyCommentItem({
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
    this.onProfileTap,
    this.postAuthorUsername,
    this.enableImageHero = true,
    this.customBottomPadding,
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
  final Function(String username)? onProfileTap;
  final String? postAuthorUsername;
  final bool enableImageHero;
  final double? customBottomPadding;

  @override
  State<SwipeReplyCommentItem> createState() => _SwipeReplyCommentItemState();
}

class _SwipeReplyCommentItemState extends State<SwipeReplyCommentItem> {
  double _dragOffset = 0.0;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;
    if (dx == 0) return;

    setState(() {
      // ✅ 우측(→) 스와이프만 허용
      if (dx > 0) {
        _dragOffset = (_dragOffset + dx).clamp(0.0, 90.0);
      } else if (dx < 0 && _dragOffset > 0) {
        // 왼쪽으로 되돌리기
        _dragOffset = (_dragOffset + dx).clamp(0.0, 90.0);
      }
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    // 임계값 초과 시 트리거, 아니면 원위치
    if (_dragOffset >= 60.0) {
      setState(() => _dragOffset = 0.0);
      widget.onSwipeReply();
      return;
    }
    setState(() => _dragOffset = 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return CommentItem(
      key: ValueKey(widget.comment.id),
      comment: widget.comment,
      commentService: widget.commentService,
      currentUser: widget.currentUser,
      isMe: widget.isMe,
      showProfile: widget.showProfile,
      showAuthorInfo: widget.showAuthorInfo,
      onReactionToggle: widget.onReactionToggle,
      onLongPress: widget.onLongPress,
      bounceAnimationValue: widget.bounceAnimationValue,
      isAnimating: widget.isAnimating,
      onTapTargetComment: widget.onTapTargetComment,
      targetComment: widget.targetComment,
      globalKey: widget.globalKey,
      onSwipeReply: widget.onSwipeReply,
      dragOffset: _dragOffset,
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onProfileTap: widget.onProfileTap,
      postAuthorUsername: widget.postAuthorUsername,
      enableImageHero: widget.enableImageHero,
      customBottomPadding: widget.customBottomPadding,
    );
  }
}
