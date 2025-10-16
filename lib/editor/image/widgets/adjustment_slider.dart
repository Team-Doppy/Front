import 'package:flutter/material.dart';
import 'package:doppy/editor/image/models/image_adjustment.dart';

/// 조정 슬라이더 위젯
class AdjustmentSlider extends StatelessWidget {
  const AdjustmentSlider({
    super.key,
    required this.type,
    required this.value,
    required this.onChanged,
    required this.onReset,
  });

  final AdjustmentType type;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final minValue = AdjustmentTypeUtils.getMinValue(type);
    final maxValue = AdjustmentTypeUtils.getMaxValue(type);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 현재 값 표시 텍스트
        Text(
          value.round().toString(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        // 슬라이더
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.2),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withOpacity(0.2),
            trackHeight: 2.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value,
            min: minValue,
            max: maxValue,
            divisions: (maxValue - minValue).toInt(),
            onChanged: (newValue) {
              // 정수로 반올림하여 전달
              onChanged(newValue.roundToDouble());
            },
          ),
        ),
      ],
    );
  }
}
