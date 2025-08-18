import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DoppyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const DoppyTopBar({
    super.key,
    required this.title,
    this.showBack = false,
    this.showMore = true,
    this.onBack,
    this.onMore,
  });

  final String title;
  final bool showBack;
  final bool showMore;
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    const double slot = 48;

    Widget leading = SizedBox(width: slot);

    leading = SizedBox(
      width: slot,
      child: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: onBack ?? () => Navigator.maybePop(context),
      ),
    );

    Widget trailing = SizedBox(width: slot);
    if (showMore) {
      trailing = SizedBox(
        width: slot,
        child: IconButton(
          icon: SvgPicture.asset(
            'assets/icons/menu.svg',
            width: 24,
            height: 24,
          ),
          onPressed: onMore,
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            leading,
            Expanded(
              child: Center(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
