import 'dart:math' as math;

import 'package:doppy/pages/components/recap/recap_doc.dart';
import 'package:flutter/material.dart';

class RevealOnScroll extends StatefulWidget {
  const RevealOnScroll({
    super.key,
    required this.scrollController,
    required this.motion,
    required this.child,
  });

  final ScrollController scrollController;
  final RecapMotionPreset motion;
  final Widget child;

  @override
  State<RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<RevealOnScroll> {
  final GlobalKey _measureKey = GlobalKey();
  double _t = 1.0; // 0..1, 초기값을 1.0으로 설정하여 즉시 보이도록
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant RevealOnScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    final ctx = _measureKey.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderBox) {
      // 🎯 RenderBox가 아직 없으면 초기 로드 중이므로 완전히 보이도록 설정
      if (_t < 1.0) {
        setState(() => _t = 1.0);
      }
      return;
    }

    final screenH = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.paddingOf(context).top;

    final globalTop = ro.localToGlobal(Offset.zero).dy;
    final h = ro.size.height;

    // 뷰포트 기준 (상단 앱바/상단 inset을 대략 보정)
    final viewportTop = topInset + kToolbarHeight;
    final viewportBottom = screenH;

    final itemTop = globalTop;
    final itemBottom = globalTop + h;

    final visibleTop = math.max(itemTop, viewportTop);
    final visibleBottom = math.min(itemBottom, viewportBottom);
    final visible = math.max(0.0, visibleBottom - visibleTop);
    final visibleFrac = (h <= 0) ? 0.0 : (visible / h).clamp(0.0, 1.0);

    // 🎯 초기 로드 시 아이템이 뷰포트 위에 있으면 (아직 스크롤 안 했으면) 즉시 표시
    // 아이템이 뷰포트 위에 있으면 (itemBottom < viewportTop) 완전히 보이도록 설정
    double nextT;
    if (itemBottom < viewportTop) {
      // 아직 뷰포트에 도달하지 않았지만, 스크롤하면 보일 예정이므로 완전히 표시
      nextT = 1.0;
    } else if (visibleFrac > 0) {
      // 뷰포트에 일부라도 보이면 완전히 표시 (초기 로드 시 즉시 보이도록)
      nextT = 1.0;
    } else {
      // 완전히 뷰포트 밖에 있으면 애니메이션 적용
      // 애니메이션 촉발 타이밍을 늦추기: 아이템이 뷰포트 하단에서 30% 들어왔을 때 시작
      // visibleFrac가 0.3 이상일 때만 애니메이션 시작 (0.3 -> 0.0, 1.0 -> 1.0으로 매핑)
      final adjustedFrac =
          visibleFrac < 0.3 ? 0.0 : ((visibleFrac - 0.5) / 0.5).clamp(0.0, 1.0);

      // 노출률을 약간 과장(리캡 느낌)해서 0..1로 매핑
      nextT = (adjustedFrac * 1.25).clamp(0.0, 1.0);
    }

    if ((nextT - _t).abs() < 0.01) return;
    setState(() => _t = nextT);
  }

  @override
  Widget build(BuildContext context) {
    final (dy, scale, duration) = switch (widget.motion) {
      RecapMotionPreset.hero => (18.0, 0.985, 520),
      RecapMotionPreset.punchy => (22.0, 0.99, 320),
      RecapMotionPreset.soft => (14.0, 0.995, 420),
    };

    final curved = Curves.easeOutCubic.transform(_t);
    final opacity = curved;
    final translateY = (1 - curved) * dy;
    final s = scale + (1 - scale) * curved;

    return KeyedSubtree(
      key: _measureKey,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: Duration(milliseconds: duration),
        curve: Curves.easeOutCubic,
        child: Transform.translate(
          offset: Offset(0, translateY),
          child: Transform.scale(
            scale: s,
            alignment: Alignment.topCenter,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
