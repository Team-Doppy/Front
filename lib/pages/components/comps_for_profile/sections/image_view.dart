import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';

class ImageView extends StatelessWidget {
  const ImageView({
    super.key,
    required this.post,
    this.isFirst = false,
    this.isLast = false,
  });
  final PostData post;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return post.id == 'padding'
        ? Container(width: 80, height: 180, color: theme.colorScheme.background)
        : Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
              bottomLeft: isFirst ? const Radius.circular(12) : Radius.zero,
              topRight: isLast ? const Radius.circular(12) : Radius.zero,
              bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
            ),
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
              bottomLeft: isFirst ? const Radius.circular(12) : Radius.zero,
              topRight: isLast ? const Radius.circular(12) : Radius.zero,
              bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
            ),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: CachedNetworkImage(
                imageUrl: post.thumbnailImageUrl,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => Container(
                      color: theme.colorScheme.surface.withOpacity(0.1),
                      child: const ShimmerBox(
                        width: double.infinity,
                        height: 180,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                errorWidget:
                    (context, url, error) => const ImageErrorPlaceholder(),
              ),
            ),
          ),
        );
  }
}
