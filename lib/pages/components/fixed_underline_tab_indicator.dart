import 'package:flutter/material.dart';

/// 화면 너비 기준으로 길이를 고정하는 언더라인 인디케이터
class FixedUnderlineTabIndicator extends Decoration {
  final Color color;
  final double thickness;
  final double bottomInset;
  final double screenWidth; // 스크린 전체 폭
  final double fraction; // 스크린 폭 대비 길이 비율 (예: 0.375 = 37.5%)

  const FixedUnderlineTabIndicator({
    required this.color,
    required this.screenWidth,
    this.fraction = 0.375,
    this.thickness = 2.0,
    this.bottomInset = 0.0,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _FixedUnderlinePainter(
      color: color,
      thickness: thickness,
      bottomInset: bottomInset,
      indicatorWidth: screenWidth * fraction,
    );
  }
}

class _FixedUnderlinePainter extends BoxPainter {
  final Color color;
  final double thickness;
  final double bottomInset;
  final double indicatorWidth;

  _FixedUnderlinePainter({
    required this.color,
    required this.thickness,
    required this.bottomInset,
    required this.indicatorWidth,
  });

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    if (configuration.size == null) return;

    final Rect rect = offset & configuration.size!;
    final double cx = rect.center.dx; // 활성 탭 중앙
    final double half = indicatorWidth / 2;
    final double y = rect.bottom - bottomInset - thickness / 2;

    final Paint p =
        Paint()
          ..color = color
          ..strokeWidth = thickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.square;

    canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), p);
  }
}
