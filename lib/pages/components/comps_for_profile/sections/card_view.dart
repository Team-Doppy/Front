import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';

class CardView extends StatelessWidget {
  const CardView({
    super.key,
    required this.post,
    this.showViewBadge = false,
    this.isLast = false,
    this.isFirst = false,
  });
  final PostData post;
  final bool showViewBadge;
  final bool isLast;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withOpacity(0.5),
      ),
      child: ClipRRect(
        child: Stack(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 125,

                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.3,
                              ),
                              width: 0.8,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: post.thumbnailImageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 150,
                              placeholder:
                                  (context, url) => Container(
                                    color: theme.colorScheme.surface
                                        .withOpacity(0.1),
                                    child: const ShimmerBox(
                                      width: double.infinity,
                                      height: 180,
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                              errorWidget:
                                  (context, url, error) =>
                                      const ImageErrorPlaceholder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showViewBadge)
                      Positioned(
                        left: 3,
                        bottom: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${post.viewCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 10),

                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 10),
                      // 제목
                      Text(
                        post.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 발행날짜
                      Text(
                        _formatDateString(post.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 요약
                      Text(
                        post.parsedContent,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w200,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),

                      // 하트수와 댓글수
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              Icons.favorite_border,
                              size: 16,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.4,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.likeCount}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w300,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateString(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes}분 전';
        }
        return '${difference.inHours}시간 전';
      } else if (difference.inDays == 1) {
        return '어제';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else if (difference.inDays < 30) {
        return '${difference.inDays ~/ 7}주 전';
      } else if (difference.inDays < 365) {
        return '${difference.inDays ~/ 30}개월 전';
      } else {
        return '${difference.inDays ~/ 365}년 전';
      }
    } catch (e) {
      return dateStr;
    }
  }
}
