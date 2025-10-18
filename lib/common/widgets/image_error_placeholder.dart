import 'package:flutter/material.dart';

class ImageErrorPlaceholder extends StatelessWidget {
  const ImageErrorPlaceholder({
    this.width,
    this.height,
    this.backgroundColor,
    this.iconColor,
    this.iconSize = 28,
    super.key,
  });

  final Color? backgroundColor;
  final Color? iconColor;
  final double iconSize;
  final double? width;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width ?? 100,
      height: height ?? 150,
      color: backgroundColor,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface.withOpacity(0.03),
      ),
      child: Icon(
        Icons.error_outline,
        color: theme.colorScheme.surface.withOpacity(1),
        size: iconSize,
      ),
    );
  }
}
