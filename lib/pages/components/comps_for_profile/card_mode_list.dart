import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/category_provider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

class CardModeList extends StatelessWidget {
  const CardModeList({
    super.key,
    required this.title,
    required this.posts,
    required this.onPostTap,
    this.sectionMeta,
    this.feedbackBuilder,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final String title;
  final List<PostData> posts;
  final Function(BuildContext context, PostData post, int index) onPostTap;
  final dynamic sectionMeta;
  final Widget Function(BuildContext, dynamic)? feedbackBuilder;
  final VoidCallback? onDragStarted;
  final Function(DragUpdateDetails)? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catProvider = context.read<CategoryProvider>();
    bool isAllTab =
        catProvider.selectedCategoryId == null &&
        catProvider.selectedBase == BaseFilter.all;

    bool isSimpleVersion = (isAllTab && posts.length > 3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 타이틀 (비어있으면 표시하지 않음)
        if (title.trim().isNotEmpty)
          (sectionMeta != null && feedbackBuilder != null)
              ? LongPressDraggable(
                data: sectionMeta,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                onDragStarted: onDragStarted,
                onDragUpdate: onDragUpdate,
                onDragEnd: (_) => onDragEnd?.call(),
                feedback: feedbackBuilder!(context, sectionMeta),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.85,
                            ),
                          ),
                        ),
                        Spacer(),
                        Icon(
                          Icons.keyboard_arrow_right,
                          size: 20,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.85),
                        ),
                      ),
                      Spacer(),
                      if (isSimpleVersion)
                        GestureDetector(
                          onTap: () {},
                          child: Icon(
                            Icons.keyboard_arrow_right,
                            size: 20,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              )
              : Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.85),
                      ),
                    ),
                    Spacer(),
                    if (isSimpleVersion)
                      GestureDetector(
                        onTap: () {},
                        child: Icon(
                          Icons.keyboard_arrow_right,
                          size: 20,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                  ],
                ),
              ),

        // 포스트 리스트
        ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: (isSimpleVersion) ? 3 : posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                index == 0 ? 0 : 4,
                8,
                index == posts.length - 1 ? 4 : 0,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 150,
                child: _buildCardItem(context, post, index),
              ),
            );
          },
        ),
        SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCardItem(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => onPostTap(context, post, index),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              // 블러 배경 이미지
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: post.thumbnailImageUrl,
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => Container(
                        color: theme.colorScheme.surface.withOpacity(0.1),
                      ),
                  errorWidget:
                      (context, url, error) => Container(
                        color: theme.colorScheme.surface.withOpacity(0.1),
                      ),
                ),
              ),
              // 블러 효과
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.black.withOpacity(0.8)),
                ),
              ),
              // 콘텐츠
              Row(
                children: [
                  // 왼쪽: 이미지 영역
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        child: CachedNetworkImage(
                          imageUrl: post.thumbnailImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 150,
                          placeholder:
                              (context, url) => Container(
                                color: theme.colorScheme.surface.withOpacity(
                                  0.1,
                                ),
                                child: ShimmerBox(
                                  width: double.infinity,
                                  height: 180,
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                          errorWidget:
                              (context, url, error) => Container(
                                color: theme.colorScheme.surface.withOpacity(
                                  0.1,
                                ),
                                child: Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.3),
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  // 오른쪽: 콘텐츠 영역
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 16,
                        top: 16,
                        bottom: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 제목
                              Text(
                                post.title,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8),
                              // 요약 (하드코딩)
                              Text(
                                '이벤트에 대한 간단한 설명과 함께 참여자들의 관심을 끌 수 있는 내용을 포함합니다.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          // 좋아요, 조회수
                          Row(
                            children: [
                              Icon(
                                Icons.favorite_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${post.likeCount}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                              SizedBox(width: 12),
                              Icon(
                                Icons.visibility_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '${post.viewCount}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
