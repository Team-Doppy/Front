import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';

class PostListItem extends StatelessWidget {
  final int index;
  final String title;
  final String author;
  final String preview;
  final String imageUrl;
  final int likes;
  final bool selected;
  final VoidCallback onTap;

  const PostListItem({
    super.key,
    required this.index,
    required this.title,
    required this.author,
    required this.preview,
    required this.imageUrl,
    required this.likes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 144,
                  height: 108,
                  decoration: ShapeDecoration(
                    image: DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 20,
                        child: Text(
                          title,
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodyLarge, 15),
                            FontWeight.w500,
                          ).copyWith(color: Colors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: Text(
                          '$author · ♥$likes',
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodySmall, 10),
                            FontWeight.w500,
                          ).copyWith(color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: Text(
                          preview,
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodySmall, 11),
                            FontWeight.w400,
                          ).copyWith(color: Colors.black54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
