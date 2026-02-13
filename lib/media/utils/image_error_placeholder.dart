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
    return Container(
      width: width ?? 100,
      height: height ?? 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
      ),
      child: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        size: iconSize,
      ),
    );
  }
}
