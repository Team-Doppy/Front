import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Modern shimmer effect with smooth wave animation
class ShimmerBox extends StatefulWidget {
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
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 화이트 모드에서도 잘 보이도록 색상 조정
    final baseColor =
        isDark ? theme.colorScheme.surfaceVariant : Colors.grey[300]!;
    final highlightColor = isDark ? theme.colorScheme.surface : Colors.white;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 펄스 효과를 위한 투명도 계산
        final double pulseValue =
            (1.0 + math.sin(2 * math.pi * _controller.value)) / 2.0;
        final double opacity = 0.2 + (0.6 * pulseValue);

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            color: baseColor,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
              color: highlightColor.withOpacity(opacity),
            ),
          ),
        );
      },
    );
  }
}
