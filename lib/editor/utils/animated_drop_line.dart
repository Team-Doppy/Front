import 'package:flutter/material.dart';

/// 🎯 드롭라인을 부드럽게 나타나게 하는 애니메이션 위젯
/// 담백하고 깔끔한 fade-in 애니메이션 적용
class AnimatedDropLine extends StatefulWidget {
  const AnimatedDropLine({required this.child, super.key});

  final Widget child;

  @override
  State<AnimatedDropLine> createState() => _AnimatedDropLineState();
}

class _AnimatedDropLineState extends State<AnimatedDropLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fadeAnimation, child: widget.child);
  }
}
