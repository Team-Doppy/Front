import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/comment_item.dart';

class CommentPreviewSection extends StatelessWidget {
  const CommentPreviewSection({
    super.key,
    required this.commentService,
    required this.likeService,
    required this.postId,
    required this.onToggleLike,
    required this.onShowComments,
  });

  final CommentService commentService;
  final LikeService likeService;
  final String postId;
  final VoidCallback onToggleLike;
  final VoidCallback onShowComments;

  Comment? _findTargetComment(String? parentId, List<Comment> allComments) {
    if (parentId == null || parentId == '0' || parentId.isEmpty) return null;
    try {
      return allComments.firstWhere((c) => c.id == parentId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allComments = commentService.getAllComments();
    final recentComments = commentService.getRecentComments();

    // 시간순 정렬
    recentComments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final previewComments = recentComments.take(5).toList();

    final currentUser = context.read<UserProvider>().currentUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...previewComments.asMap().entries.map((entry) {
            final index = entry.key;
            final comment = entry.value;

            final isMe =
                currentUser != null && comment.author == currentUser.username;

            // 이전 댓글과 같은 작성자인지
            final isSameAuthorAsPrevious =
                index > 0 &&
                previewComments[index - 1].author == comment.author;
            final showProfile = !isSameAuthorAsPrevious;

            // 다음 댓글과 같은 작성자인지
            final isSameAuthorAsNext =
                index < previewComments.length - 1 &&
                previewComments[index + 1].author == comment.author;
            final showAuthorInfo = !isSameAuthorAsNext;

            // 답글 대상 찾기
            final targetComment = _findTargetComment(
              comment.parentId,
              allComments,
            );

            return GestureDetector(
              // 🎯 프리뷰에서 댓글 전체를 탭하면 댓글 시트로 이동
              onTap: onShowComments,
              child: CommentItem(
                key: ValueKey(
                  '${comment.id}_${comment.createdAt}_preview_$index',
                ),
                comment: comment,
                commentService: commentService,
                currentUser: currentUser,
                isMe: isMe,
                showProfile: showProfile,
                showAuthorInfo: showAuthorInfo,
                // 🎯 프리뷰에서는 Hero 제거 (댓글 시트로 이동 시 이미지가 따라오는 문제 방지)
                enableImageHero: false,
                // 🎯 이미지 클릭 시 댓글 시트로 이동
                onImageTap: onShowComments,
                onReactionToggle: (commentId, emoji) {
                  commentService.toggleReaction(commentId, emoji);
                },
                onLongPress: (offset, comment) {
                  // 미리보기에서는 롱프레스 동작 없음
                },
                bounceAnimationValue: 1.0,
                isAnimating: false,
                onTapTargetComment: (commentId) {
                  // 답글 대상 클릭 시 댓글창 열기
                  onShowComments();
                },
                targetComment: targetComment,
                globalKey: null,
                onSwipeReply: () {
                  // 미리보기에서는 스와이프 답글 없음
                },
                dragOffset: 0,
              ),
            );
          }),

          // "모든 댓글 보기" 또는 "채팅하기" 버튼
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: onShowComments,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  previewComments.isEmpty
                      ? context.tr('write_comment')
                      : context.tr('all_comments'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 70),
        ],
      ),
    );
  }
}
