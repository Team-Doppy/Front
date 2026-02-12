import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final bool? isDarkMode;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.shape,
    this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark =
        isDarkMode ??
        (Theme.of(context).colorScheme.brightness == Brightness.dark);
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final highlight = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFEBEBEB);

    final child = shape != null
        ? DecoratedBox(
            decoration: ShapeDecoration(color: base, shape: shape!),
            child: SizedBox(width: width, height: height),
          )
        : Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: borderRadius ?? BorderRadius.zero,
            ),
          );

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 2000),
      child: child,
    );
  }
}
