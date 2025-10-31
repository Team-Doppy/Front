import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/like_service.dart';

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

  String _formatRelativeTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      if (difference.inMinutes < 1) return '방금';
      if (difference.inHours < 1) return '${difference.inMinutes}분 전';
      if (difference.inDays < 1) return '${difference.inHours}시간 전';
      if (difference.inDays < 7) return '${difference.inDays}일 전';
      return '${(difference.inDays / 7).floor()}주 전';
    } catch (_) {
      return '방금';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 좋아요 버튼
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleLike,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            likeService.isPostLiked(postId)
                                ? Colors.redAccent.withOpacity(0.1)
                                : Theme.of(
                                  context,
                                ).colorScheme.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              likeService.isPostLiked(postId)
                                  ? Colors.redAccent.withOpacity(0.3)
                                  : Theme.of(
                                    context,
                                  ).colorScheme.outline.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              likeService.isPostLiked(postId)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              key: ValueKey(likeService.isPostLiked(postId)),
                              color:
                                  likeService.isPostLiked(postId)
                                      ? Colors.redAccent
                                      : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${likeService.getPostLikeCount(postId)}',
                            style: TextStyle(
                              color:
                                  likeService.isPostLiked(postId)
                                      ? Colors.redAccent
                                      : Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 댓글 정보
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onShowComments,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chat_bubble_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${commentService.getAllComments().length}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              commentService.isLoading &&
                      commentService.getAllComments().isEmpty
                  ? const SizedBox(
                    height: 72,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                  : Column(
                    children: () {
                      final comments = commentService.getRecentComments();
                      comments.sort(
                        (a, b) => a.createdAt.compareTo(b.createdAt),
                      );
                      return comments.take(5).map((comment) {
                        final currentUser =
                            context.read<UserProvider>().currentUser;
                        final isMe =
                            currentUser != null &&
                            comment.author == currentUser.username;
                        final hasReactions = comment.emotionCounts.isNotEmpty;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment:
                                isMe
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                            children: [
                              if (!isMe) ...[
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.surfaceVariant,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                      width: 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child:
                                      comment.authorProfileImageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                            imageUrl:
                                                comment.authorProfileImageUrl,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 80,
                                            maxWidthDiskCache: 80,
                                            fadeInDuration: Duration.zero,
                                            fadeOutDuration: Duration.zero,
                                            cacheKey:
                                                'comment_profile_${comment.authorProfileImageUrl}',
                                          )
                                          : Icon(
                                            Icons.person,
                                            size: 16,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Column(
                                  crossAxisAlignment:
                                      isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                  children: [
                                    if (comment.parentId != null &&
                                        comment.parentId != '0' &&
                                        comment.parentId != '')
                                      ...() {
                                        final allComments =
                                            commentService.getAllComments();
                                        dynamic targetComment;
                                        try {
                                          targetComment = allComments
                                              .firstWhere(
                                                (c) => c.id == comment.parentId,
                                              );
                                        } catch (e) {
                                          targetComment = null;
                                        }
                                        if (targetComment == null)
                                          return <Widget>[];
                                        return [
                                          GestureDetector(
                                            onTap: onShowComments,
                                            child: Container(
                                              constraints: BoxConstraints(
                                                maxWidth:
                                                    MediaQuery.of(
                                                      context,
                                                    ).size.width *
                                                    0.75,
                                              ),
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceVariant
                                                    .withOpacity(0.3),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline
                                                      .withOpacity(0.2),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${targetComment.author}',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.7),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    targetComment.content,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.6),
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ];
                                      }(),
                                    Container(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                            0.75,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            isMe
                                                ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                                : Theme.of(
                                                  context,
                                                ).colorScheme.surfaceVariant,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(
                                            isMe ? 16 : 4,
                                          ),
                                          bottomRight: Radius.circular(
                                            isMe ? 4 : 16,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        comment.content,
                                        style: TextStyle(
                                          color:
                                              isMe
                                                  ? Colors.white
                                                  : Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                          fontSize: 15,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    if (hasReactions)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (final entry
                                                in comment
                                                    .emotionCounts
                                                    .entries)
                                              if (entry.value != '0')
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    right: 4,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.surface,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.1),
                                                        blurRadius: 2,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    '${entry.key} ${entry.value}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${comment.author} • ${_formatRelativeTime(comment.createdAt)}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.6),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.surfaceVariant,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                      width: 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child:
                                      comment.authorProfileImageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                            imageUrl:
                                                comment.authorProfileImageUrl,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 80,
                                            maxWidthDiskCache: 80,
                                            fadeInDuration: Duration.zero,
                                            fadeOutDuration: Duration.zero,
                                            cacheKey:
                                                'comment_profile_${comment.authorProfileImageUrl}',
                                          )
                                          : Icon(
                                            Icons.person,
                                            size: 16,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList();
                    }(),
                  ),
              SizedBox(height: 50),
              if (commentService.getAllComments().length > 5)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: onShowComments,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '더 많은 댓글 보기',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }
}
