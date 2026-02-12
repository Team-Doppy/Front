import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final String? profileImageUrl;
  final String profileUsername;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.profileImageUrl,
    this.profileUsername = 'me',
  });

  static double getBottomNavBarHeight(BuildContext context) {
    final systemNavBarHeight = MediaQuery.of(context).viewPadding.bottom;
    final baseHeight = 50.0;
    final totalHeight = baseHeight + systemNavBarHeight;
    return totalHeight;
  }

  @override
  Widget build(BuildContext context) {
    final systemNavBarHeight = MediaQuery.of(context).viewPadding.bottom;

    const iconAssets = [
      'assets/icons/ic_home.svg',
      'assets/icons/ic_search.svg',
      'assets/icons/ic_write.svg',
    ];

    return Container(
      height: BottomNavBar.getBottomNavBarHeight(context),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: systemNavBarHeight,
          top: 12,
          right: 20,
          left: 20,
        ),
        child: Row(
          children: List.generate(3, (index) {
            final isSelected = index == currentIndex;
            final iconSize = index == 0 ? 25.0 : 28.0;

            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(index),
                behavior: HitTestBehavior.translucent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      iconAssets[index],
                      width: iconSize,
                      height: iconSize,
                      colorFilter: ColorFilter.mode(
                        isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
