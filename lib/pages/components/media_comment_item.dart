import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/media_comment_service.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 미디어(이미지/비디오) 댓글 아이템 (일반 댓글 스타일)
class MediaCommentItem extends StatelessWidget {
  final MediaComment comment;
  final bool isMe;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final VoidCallback? onProfileTap;
  final bool isLast;

  const MediaCommentItem({
    super.key,
    required this.comment,
    this.isMe = false,
    this.onReply,
    this.onLike,
    this.onProfileTap,
    this.isLast = false,
  });

  String _formatTime(BuildContext context, String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dateTime);
      final loc = AppLocalizations.of(context);

      if (diff.inSeconds < 60) {
        return loc.translate('just_now');
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes} ${loc.translate('min_ago')}';
      } else if (diff.inHours < 24) {
        return '${diff.inHours} ${loc.translate('hr_ago')}';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} ${loc.translate('days_ago')}';
      } else {
        return '${dateTime.month}/${dateTime.day}';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프로필 사진 (탭 가능)
              GestureDetector(
                onTap: onProfileTap,
                child: CommonProfileAvatar(
                  imageUrl: comment.authorProfileImageUrl,
                  username: comment.author ?? '',
                  size: 47,
                  borderWidth: 1,
                ),
              ),
              const SizedBox(width: 12),
              // 댓글 내용
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 작성자 + 시간
                    Row(
                      children: [
                        Text(
                          comment.author ?? '',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 댓글 내용
                    Text(
                      comment.text,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Reply + Like 버튼
                    Row(
                      children: [
                        if (onLike != null)
                          GestureDetector(
                            onTap: onLike,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  comment.isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 16,
                                  color:
                                      comment.isLiked
                                          ? Colors.red
                                          : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  comment.likeCount.toString(),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  _formatTime(context, comment.createdAt),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 구분선 (마지막 요소가 아닐 때만 표시)
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 70, right: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
            ),
          ),
      ],
    );
  }
}
