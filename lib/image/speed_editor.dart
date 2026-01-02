import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 속도(재생속도) 편집 바텀시트
///
/// - "조정 상세(슬라이더)"의 룰러/버블 스타일을 그대로 가져온 단일 슬라이더 UI
/// - 값은 VideoPlayerController.setPlaybackSpeed에 사용된다.
class SpeedEditorBottomSheet extends StatefulWidget {
  const SpeedEditorBottomSheet({
    super.key,
    required this.speed,
    required this.onSpeedChanged,
    this.onDragEnd,
    this.min = 0.5,
    this.max = 2.0,
  });

  final double speed;
  final double min;
  final double max;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback? onDragEnd;

  @override
  State<SpeedEditorBottomSheet> createState() => _SpeedEditorBottomSheetState();
}

class _SpeedEditorBottomSheetState extends State<SpeedEditorBottomSheet> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          child: SizedBox(
            height: 80,
            child: Center(
              child: _SpeedBubble(
                bgColor: bgColor,
                fgColor: fgColor,
                speed: widget.speed,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _SpeedRulerSlider(
            value: widget.speed,
            min: widget.min,
            max: widget.max,
            textColor: fgColor,
            isDragging: _isDragging,
            onChanged: (v) {
              // ✅ 1.0 근처는 정확히 1.0으로 스냅 (부동소수 오차 방지)
              final snapped = (v - 1.0).abs() < 0.01 ? 1.0 : v;
              widget.onSpeedChanged(snapped.clamp(widget.min, widget.max));
            },
            onDragStart: () => setState(() => _isDragging = true),
            onDragEnd: () {
              setState(() => _isDragging = false);
              widget.onDragEnd?.call();
            },
          ),
        ),
      ],
    );
  }
}

class _SpeedBubble extends StatelessWidget {
  const _SpeedBubble({
    required this.bgColor,
    required this.fgColor,
    required this.speed,
  });

  final Color bgColor;
  final Color fgColor;
  final double speed;

  String _label(double v) {
    // 0.5, 1, 1.5, 2 같은 표현을 깔끔하게
    final s = v.toStringAsFixed(2);
    final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), ''); // trailing zeros 제거
    return '${trimmed}x';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor.withOpacity(0.85),
        border: Border.all(color: fgColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          _label(speed),
          style: TextStyle(
            color: fgColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 룰러 슬라이더 (조정의 _AdjustmentRulerSlider 스타일)
class _SpeedRulerSlider extends StatefulWidget {
  const _SpeedRulerSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.textColor,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.isDragging,
  });

  final double value;
  final double min;
  final double max;
  final Color textColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final bool isDragging;

  @override
  State<_SpeedRulerSlider> createState() => _SpeedRulerSliderState();
}

class _SpeedRulerSliderState extends State<_SpeedRulerSlider> {
  double? _dragStartX;
  double? _dragStartValue;

  void _onPanStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValue = widget.value;
    widget.onDragStart();
  }

  void _onPanUpdate(DragUpdateDetails details, double width) {
    if (_dragStartX == null || _dragStartValue == null) return;

    final deltaX = details.localPosition.dx - _dragStartX!;
    final range = widget.max - widget.min;
    // ✅ 조정과 동일 감도 + 방향 반전
    final deltaValue = (-deltaX / width) * (range / 1.5);
    final newValue = (_dragStartValue! + deltaValue).clamp(
      widget.min,
      widget.max,
    );
    widget.onChanged(newValue);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragStartX = null;
    _dragStartValue = null;
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onPanStart,
          onHorizontalDragUpdate:
              (details) => _onPanUpdate(details, constraints.maxWidth),
          onHorizontalDragEnd: _onPanEnd,
          child: SizedBox(
            height: 50,
            child: CustomPaint(
              painter: _SpeedRulerPainter(
                currentValue: widget.value,
                min: widget.min,
                max: widget.max,
                textColor: widget.textColor,
              ),
              size: Size(constraints.maxWidth, 50),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedRulerPainter extends CustomPainter {
  _SpeedRulerPainter({
    required this.currentValue,
    required this.min,
    required this.max,
    required this.textColor,
  });

  final double currentValue;
  final double min;
  final double max;
  final Color textColor;

  String _format(double v) {
    final s = v.toStringAsFixed(1);
    return s.replaceFirst(RegExp(r'\.0$'), '');
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint =
        Paint()
          ..color = textColor.withOpacity(0.3)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    final majorTickPaint =
        Paint()
          ..color = textColor.withOpacity(0.5)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    final centerPaint =
        Paint()
          ..color = textColor
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final bottomY = size.height - 8;

    final range = max - min;
    final visibleRange = range / 4;
    final pixelsPerUnit = size.width / (visibleRange * 2);

    const tickInterval = 0.1;
    const majorInterval = 0.5;

    canvas.drawLine(
      Offset(centerX, bottomY),
      Offset(centerX, bottomY - 40),
      centerPaint,
    );

    // 0.1 단위 루프는 부동소수 누적 오차가 생기므로 정수 스텝으로 생성
    final steps = ((max - min) / tickInterval).round();
    for (int i = 0; i <= steps; i++) {
      final tickValue = min + tickInterval * i;
      final relative = tickValue - currentValue;
      if (relative.abs() > visibleRange) continue;

      final x = centerX + relative * pixelsPerUnit;
      if (relative.abs() < 0.01) continue;

      final isMajor =
          (((tickValue / majorInterval).round() * majorInterval) - tickValue)
              .abs() <
          0.001;

      if (isMajor) {
        canvas.drawLine(
          Offset(x, bottomY),
          Offset(x, bottomY - 16),
          majorTickPaint,
        );
        final textSpan = TextSpan(
          text: _format(tickValue),
          style: TextStyle(
            color: textColor.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, bottomY - 32),
        );
      } else {
        canvas.drawLine(Offset(x, bottomY), Offset(x, bottomY - 8), tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SpeedRulerPainter oldDelegate) {
    return oldDelegate.currentValue != currentValue ||
        oldDelegate.min != min ||
        oldDelegate.max != max;
  }
}
