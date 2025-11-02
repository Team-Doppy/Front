import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).colorScheme.brightness == Brightness.dark;
    final Color baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final Color highlightColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F3F3);

    final BorderRadius resolvedRadius = borderRadius ?? BorderRadius.zero;

    final Widget child =
        (shape != null)
            ? DecoratedBox(
              decoration: ShapeDecoration(color: baseColor, shape: shape!),
              child: SizedBox(width: width, height: height),
            )
            : Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: resolvedRadius,
              ),
            );

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: child,
    );
  }
}
