import 'package:doppy/pages/components/card_view_shimmer.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:flutter/material.dart';

/// 피드 로딩용 Shimmer (Sliver)
/// - 카드 모드: CardViewShimmer 5개
/// - 그리드 모드: ImageViewShimmer 9개
class FeedLoadingShimmerSliver extends StatelessWidget {
  const FeedLoadingShimmerSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final displayMode = FeedDisplayModeManager().value;
    final isCardView = displayMode == FeedDisplayMode.card;

    if (isCardView) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 1.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 2.0),
              child: CardViewShimmer(),
            );
          }, childCount: 5),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2.5,
          childAspectRatio: 4 / 5,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          return ImageViewShimmer(isFirst: index == 0, isLast: index == 8);
        }, childCount: 9),
      ),
    );
  }
}
