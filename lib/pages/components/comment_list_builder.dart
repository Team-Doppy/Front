import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comment_item.dart';

/// 댓글 리스트 빌더 (ListView.builder 로직 분리)
class CommentListBuilder extends StatelessWidget {
  const CommentListBuilder({
    super.key,
    required this.scrollController,
    required this.comments,
    required this.bounceAnimationValue,
    required this.isAnimating,
    required this.findTargetComment,
    required this.onReactionToggle,
    required this.onLongPress,
    required this.onTapTargetComment,
    required this.commentKeys,
  });

  final ScrollController scrollController;
  final List<Comment> comments;
  final double bounceAnimationValue;
  final bool Function(String) isAnimating;
  final Comment? Function(String?) findTargetComment;
  final Function(String, String) onReactionToggle;
  final Function(Offset, Comment) onLongPress;
  final Function(String) onTapTargetComment;
  final Map<String, GlobalKey> commentKeys;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 30),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        final currentUser = context.read<UserProvider>().currentUser;
        final isMe =
            currentUser != null && comment.author == currentUser.username;

        // 이전 댓글과 같은 사람인지 확인
        final bool isSameAuthorAsPrevious =
            index > 0 && comments[index - 1].author == comment.author;
        final bool showProfile = !isSameAuthorAsPrevious;

        // 다음 댓글도 같은 사람인지 확인
        final bool isSameAuthorAsNext =
            index < comments.length - 1 &&
            comments[index + 1].author == comment.author;
        final bool showAuthorInfo = !isSameAuthorAsNext;

        final targetComment = _findTargetComment(comment);

        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            );
          },
          child: CommentItem(
            comment: comment,
            currentUser: currentUser,
            isMe: isMe,
            showProfile: showProfile,
            showAuthorInfo: showAuthorInfo,
            onReactionToggle: onReactionToggle,
            onLongPress: onLongPress,
            bounceAnimationValue: bounceAnimationValue,
            isAnimating: isAnimating(comment.id),
            onTapTargetComment: onTapTargetComment,
            targetComment: targetComment,
            globalKey: commentKeys[comment.id],
          ),
        );
      },
    );
  }

  Comment? _findTargetComment(Comment comment) {
    if (comment.parentId == null ||
        comment.parentId == '0' ||
        comment.parentId == '') {
      return null;
    }
    return findTargetComment(comment.parentId);
  }
}
