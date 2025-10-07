import 'package:doppy/providers/category_provider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:provider/provider.dart';

class CardModeList extends StatelessWidget {
  const CardModeList({
    super.key,
    required this.title,
    required this.posts,
    required this.onPostTap,
  });

  final String title;
  final List<PostData> posts;
  final Function(BuildContext context, PostData post, int index) onPostTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catProvider = context.read<CategoryProvider>();
    bool isAllTab =
        catProvider.selectedCategoryId == null &&
        catProvider.selectedBase == BaseFilter.all;

    bool isSimpleVersion = (isAllTab && posts.length > 3 && title != '다른 글');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 타이틀 (비어있으면 표시하지 않음)
        if (title.trim().isNotEmpty)
          Padding(
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
                height: 200,
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200,
            placeholder:
                (context, url) => Container(
                  color: theme.colorScheme.surface.withOpacity(0.1),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            errorWidget:
                (context, url, error) => Container(
                  color: theme.colorScheme.surface.withOpacity(0.1),
                  child: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
