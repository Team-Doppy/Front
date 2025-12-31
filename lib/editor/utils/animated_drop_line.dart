import 'package:flutter/material.dart';

/// 🎯 드롭라인을 부드럽게 나타나게 하는 애니메이션 위젯
/// 단순 페이드인/페이드아웃 애니메이션
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
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
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

/// 🎯 선택 테두리를 부드럽게 나타나게 하는 애니메이션 위젯
/// 단순 페이드인/페이드아웃 애니메이션
class AnimatedSelectionBorder extends StatefulWidget {
  const AnimatedSelectionBorder({
    required this.isVisible,
    required this.child,
    super.key,
  });

  final bool isVisible;
  final Widget child;

  @override
  State<AnimatedSelectionBorder> createState() =>
      _AnimatedSelectionBorderState();
}

class _AnimatedSelectionBorderState extends State<AnimatedSelectionBorder>
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
      curve: Curves.easeInOut,
    );
    if (widget.isVisible) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedSelectionBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
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
