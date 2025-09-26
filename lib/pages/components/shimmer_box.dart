import 'package:flutter/material.dart';

/// Lightweight shimmer without external packages.
/// Uses an animated sweeping gradient.
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
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceVariant;
    final highlight = base.withOpacity(0.6);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final double t = _ctrl.value; // 0..1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            shape:
                widget.shape ??
                RoundedRectangleBorder(
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
                ),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, -1),
              end: Alignment(1 + 2 * t, 1),
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}
