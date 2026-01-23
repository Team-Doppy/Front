import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final bool? isDarkMode; // 🎯 외부에서 테마 주입 가능

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.shape,
    this.isDarkMode, // 🎯 null이면 Theme.of(context)로 자동 감지
  });

  @override
  Widget build(BuildContext context) {
    // 🎯 외부 주입 테마가 있으면 사용, 없으면 컨텍스트 테마로 자동 감지
    final bool isDark =
        isDarkMode ??
        (Theme.of(context).colorScheme.brightness == Brightness.dark);
    // 🎯 무광 느낌의 단순한 쉬머: 색상 대비를 최소화
    final Color baseColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final Color highlightColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFEBEBEB);

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
      period: const Duration(milliseconds: 2000), // 🎯 더 느린 애니메이션으로 부드럽게
      child: child,
    );
  }
}
