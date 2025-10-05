import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BlogCard extends StatelessWidget {
  final SearchContentItem item;
  final int index;

  const BlogCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchService>(
      builder: (context, searchService, _) {
        return GestureDetector(
          onTap: () {
            searchService.addToRecentlyViewed(item.id);
            final postData = searchService.getPostData(item.id);
            if (postData != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => PostReaderScreen(
                        exported: postData,
                        heroTag: 'search_blog_${item.id}_$index',
                      ),
                ),
              );
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 30),
            child: Padding(
              padding: const EdgeInsets.only(),
              child: SizedBox(
                height: 600,
                child: ClipRRect(
                  child: Stack(
                    children: [
                      // 콘텐츠
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Row(
                                children: [
                                  CommonProfileAvatar(
                                    imageUrl: item.profileImageUrl,
                                    username: item.author ?? '',
                                    size: 35,
                                    borderColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.3),
                                  ),
                                  const SizedBox(width: 8),

                                  // 작성자 이름
                                  Text(
                                    item.author ?? '',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w300,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const Spacer(),

                                  _buildStatChip(
                                    context,
                                    icon: Icons.favorite_border_rounded,
                                    label: '${item.likes ?? 0}',
                                  ),

                                  // 북마크/공유 등 확장 여지
                                ],
                              ),
                            ),

                            // 왼쪽: 텍스트 영역
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 상단: 작성자 프로필
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          fit: BoxFit.cover,
                                          item.imageUrl ?? '',
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return ShimmerBox(
                                              width: double.infinity,
                                              height: double.infinity,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 15),

                                  // 제목
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      item.title ?? '',
                                      style: TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                        height: 1,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // 내용 (미리보기)
                                  if (item.parsedContent != null &&
                                      item.parsedContent!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Text(
                                        item.parsedContent ?? '',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w200,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.8),
                                          height: 1.8,
                                        ),
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),

      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color, weight: 60),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
