import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';

/// ImageView의 shimmer 플레이스홀더
class ImageViewShimmer extends StatelessWidget {
  final bool isFirst;
  final bool isLast;

  const ImageViewShimmer({
    super.key,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
          bottomLeft: isFirst ? const Radius.circular(12) : Radius.zero,
          topRight: isLast ? const Radius.circular(12) : Radius.zero,
          bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
        ),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.1),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: isFirst ? const Radius.circular(11) : Radius.zero,
          bottomLeft: isFirst ? const Radius.circular(11) : Radius.zero,
          topRight: isLast ? const Radius.circular(11) : Radius.zero,
          bottomRight: isLast ? const Radius.circular(11) : Radius.zero,
        ),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: ShimmerBox(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }
}

/// CardView의 shimmer 플레이스홀더
class CardViewShimmer extends StatelessWidget {
  const CardViewShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withOpacity(0.5),
      ),
      child: Row(
        children: [
          // 썸네일 Shimmer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
            child: Container(
              width: 125,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ShimmerBox(
                  width: 125,
                  height: 120,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 텍스트 영역 Shimmer
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 제목 Shimmer (2줄)
                  ShimmerBox(
                    width: double.infinity,
                    height: 18,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  ShimmerBox(
                    width: MediaQuery.of(context).size.width * 0.5,
                    height: 18,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),
                  // 날짜 Shimmer
                  ShimmerBox(
                    width: 80,
                    height: 12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  // 요약 Shimmer (2줄)
                  ShimmerBox(
                    width: double.infinity,
                    height: 13,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  ShimmerBox(
                    width: MediaQuery.of(context).size.width * 0.4,
                    height: 13,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
