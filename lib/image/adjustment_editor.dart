import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 조정 타입
enum AdjustmentType {
  brightness('밝기', Icons.brightness_6),
  contrast('대비', Icons.contrast),
  saturation('채도', Icons.palette),
  luminance('휘도', Icons.wb_sunny),
  exposure('노출', Icons.exposure),
  sharpness('선명도', Icons.blur_off),
  temperature('색온도', Icons.thermostat),
  blur('블러', Icons.blur_on),
  vignette('비네팅', Icons.vignette);

  const AdjustmentType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 조정 상태 모델
class AdjustmentState {
  double brightness = 0.0; // -100 ~ 100
  double contrast = 0.0; // -100 ~ 100
  double saturation = 0.0; // -100 ~ 100
  double luminance = 0.0; // -100 ~ 100
  double exposure = 0.0; // -100 ~ 100
  double sharpness = 0.0; // 0 ~ 100
  double temperature = 0.0; // -100 ~ 100 (차갑게 ~ 따뜻하게)
  double blur = 0.0; // 0 ~ 100
  double vignette = 0.0; // 0 ~ 100

  double getValue(AdjustmentType type) {
    switch (type) {
      case AdjustmentType.brightness:
        return brightness;
      case AdjustmentType.contrast:
        return contrast;
      case AdjustmentType.saturation:
        return saturation;
      case AdjustmentType.luminance:
        return luminance;
      case AdjustmentType.exposure:
        return exposure;
      case AdjustmentType.sharpness:
        return sharpness;
      case AdjustmentType.temperature:
        return temperature;
      case AdjustmentType.blur:
        return blur;
      case AdjustmentType.vignette:
        return vignette;
    }
  }

  void setValue(AdjustmentType type, double value) {
    switch (type) {
      case AdjustmentType.brightness:
        brightness = value;
      case AdjustmentType.contrast:
        contrast = value;
      case AdjustmentType.saturation:
        saturation = value;
      case AdjustmentType.luminance:
        luminance = value;
      case AdjustmentType.exposure:
        exposure = value;
      case AdjustmentType.sharpness:
        sharpness = value;
      case AdjustmentType.temperature:
        temperature = value;
      case AdjustmentType.blur:
        blur = value;
      case AdjustmentType.vignette:
        vignette = value;
    }
  }

  AdjustmentState copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? luminance,
    double? exposure,
    double? sharpness,
    double? temperature,
    double? blur,
    double? vignette,
  }) {
    return AdjustmentState()
      ..brightness = brightness ?? this.brightness
      ..contrast = contrast ?? this.contrast
      ..saturation = saturation ?? this.saturation
      ..luminance = luminance ?? this.luminance
      ..exposure = exposure ?? this.exposure
      ..sharpness = sharpness ?? this.sharpness
      ..temperature = temperature ?? this.temperature
      ..blur = blur ?? this.blur
      ..vignette = vignette ?? this.vignette;
  }
}

/// 조정(밝기/대비/채도) 행렬 계산 유틸
class AdjustmentUtils {
  const AdjustmentUtils._();

  /// 조정 상태를 ColorMatrix로 변환
  ///
  /// [brightness]: -100 ~ 100 (밝기)
  /// [contrast]: -100 ~ 100 (대비)
  /// [saturation]: -100 ~ 100 (채도)
  ///
  /// 모든 값이 0이면 null 반환 (변경 없음)
  static List<double>? getAdjustmentMatrix({
    required double brightness,
    required double contrast,
    required double saturation,
  }) {
    if (brightness == 0.0 && contrast == 0.0 && saturation == 0.0) {
      return null;
    }

    // 밝기: +value는 밝게, -value는 어둡게
    final brightnessValue = brightness / 100.0;
    // 대비: +value는 대비 증가, -value는 대비 감소
    final contrastValue = 1.0 + (contrast / 100.0);
    // 채도: +value는 채도 증가, -value는 채도 감소
    final saturationValue = 1.0 + (saturation / 100.0);

    // 간단한 행렬 계산 (채도 포함)
    const lumR = 0.299;
    const lumG = 0.587;
    const lumB = 0.114;
    final sr = (1.0 - saturationValue) * lumR;
    final sg = (1.0 - saturationValue) * lumG;
    final sb = (1.0 - saturationValue) * lumB;

    return [
      (sr + saturationValue) * contrastValue,
      sg * contrastValue,
      sb * contrastValue,
      0.0,
      brightnessValue * 255,
      sr * contrastValue,
      (sg + saturationValue) * contrastValue,
      sb * contrastValue,
      0.0,
      brightnessValue * 255,
      sr * contrastValue,
      sg * contrastValue,
      (sb + saturationValue) * contrastValue,
      0.0,
      brightnessValue * 255,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    ];
  }
}

/// 조정 편집 바텀시트 (2단계 UI)
class AdjustmentEditorBottomSheet extends StatefulWidget {
  const AdjustmentEditorBottomSheet({
    super.key,
    required this.state,
    required this.onStateChanged,
    this.onSliderModeChanged,
    this.onDragEnd,
  });

  final AdjustmentState state;
  final ValueChanged<AdjustmentState> onStateChanged;

  /// 슬라이더 모드 변경 콜백 (true: 슬라이더 모드, false: 버튼 모드)
  final ValueChanged<bool>? onSliderModeChanged;

  /// 슬라이더 드래그 종료 시 호출 (히스토리 저장용)
  final VoidCallback? onDragEnd;

  @override
  State<AdjustmentEditorBottomSheet> createState() =>
      AdjustmentEditorBottomSheetState();
}

/// 조정 편집 바텀시트의 State (외부에서 접근 가능하도록)
class AdjustmentEditorBottomSheetState
    extends State<AdjustmentEditorBottomSheet> {
  AdjustmentType? _selectedType; // null이면 기본 버튼 단계, 값이 있으면 슬라이더 단계
  bool _isAdjustmentDragging = false; // 슬라이더 드래그 중 여부

  void resetToButtonMode() {
    if (_selectedType != null) {
      setState(() {
        _selectedType = null;
        widget.onSliderModeChanged?.call(false);
      });
    }
  }

  /// 현재 선택된 조정 타입 반환 (슬라이더 모드일 때)
  AdjustmentType? get selectedType => _selectedType;

  Widget adjustmentBubble(BuildContext context) {
    if (_selectedType == null) return const SizedBox.shrink();

    final value = widget.state.getValue(_selectedType!);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Container(
      width: 56,
      height: 56,
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
          value.round().toString(),
          style: TextStyle(
            color: fgColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ 상단: 드래그 중일 때 수치 칩, 아닐 때 조정 항목 버튼들 (고정 높이)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SizedBox(
            height: 80, // ✅ 높이 증가로 오버플로우 해결
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child:
                  _selectedType != null && _isAdjustmentDragging
                      ? Center(
                        key: const ValueKey('adjustment_bubble'),
                        child: adjustmentBubble(context),
                      )
                      : _selectedType != null
                      ? Center(
                        key: const ValueKey('adjustment_bubble_always'),
                        child: adjustmentBubble(context),
                      )
                      : Row(
                        key: const ValueKey('button_mode'),
                        children: [
                          // 조정 항목 버튼들 (가로 스크롤)
                          Expanded(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: AdjustmentType.values.length,
                              separatorBuilder:
                                  (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final type = AdjustmentType.values[i];
                                final value = widget.state.getValue(type);
                                // ✅ 0으로 돌렸는데도 "활성(프라이머리)"이 남는 문제 방지 (부동소수 오차/ -0.0)
                                final isActive = value.abs() > 0.01;
                                final isSelected = _selectedType == type;

                                return _AdjustmentButton(
                                  type: type,
                                  isActive: isActive,
                                  isSelected: isSelected,
                                  fgColor: fgColor,
                                  onTap: () {
                                    setState(() {
                                      _selectedType = type;
                                      widget.onSliderModeChanged?.call(true);
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),

        // ✅ 하단: 슬라이더는 항상 노출 (슬라이더 모드일 때만, AnimatedSize로 부드럽게)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child:
              _selectedType != null
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: _buildSliderView(fgColor, _selectedType!),
                      ),
                    ],
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// 슬라이더 조절 화면
  Widget _buildSliderView(Color fgColor, AdjustmentType type) {
    final value = widget.state.getValue(type);
    final min =
        (type == AdjustmentType.sharpness ||
                type == AdjustmentType.blur ||
                type == AdjustmentType.vignette)
            ? 0.0
            : -100.0;
    final max = 100.0;

    return _AdjustmentRulerSlider(
      value: value,
      min: min,
      max: max,
      textColor: fgColor,
      onChanged: (newValue) {
        final newState = widget.state.copyWith();
        newState.setValue(type, newValue);
        widget.onStateChanged(newState);
      },
      onDragStart: () => setState(() => _isAdjustmentDragging = true),
      onDragEnd: () {
        setState(() => _isAdjustmentDragging = false);
        // ✅ 슬라이더 드래그 종료 시 히스토리 저장 콜백 호출
        widget.onDragEnd?.call();
      },
      isDragging: _isAdjustmentDragging,
    );
  }
}

/// 조정 버튼 (crop_editor 스타일 - 원형 버튼)
class _AdjustmentButton extends StatelessWidget {
  const _AdjustmentButton({
    required this.type,
    required this.isActive,
    required this.isSelected,
    required this.fgColor,
    required this.onTap,
  });

  final AdjustmentType type;
  final bool isActive;
  final bool isSelected;
  final Color fgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 원형 아이콘 버튼
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    isSelected
                        ? cs.primary
                        : isActive
                        ? cs
                            .primary // ✅ 적용된 조정은 프라이머리 테두리
                        : fgColor.withOpacity(0.3),
                width:
                    (isSelected || isActive) ? 2.5 : 1.5, // ✅ 적용된 조정도 두꺼운 테두리
              ),
            ),
            child: Center(
              child: Icon(
                type.icon,
                color:
                    (isSelected || isActive)
                        ? cs.primary
                        : fgColor, // ✅ 적용된 조정도 프라이머리 색상
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 라벨
          Text(
            type.label,
            style: TextStyle(
              color:
                  (isSelected || isActive)
                      ? cs.primary
                      : fgColor, // ✅ 적용된 조정도 프라이머리 색상
              fontSize: 11,
              fontWeight:
                  (isSelected || isActive) ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 조정 룰러 슬라이더 (crop_editor의 RotationRulerSlider 스타일 적용)
class _AdjustmentRulerSlider extends StatefulWidget {
  const _AdjustmentRulerSlider({
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
  State<_AdjustmentRulerSlider> createState() => _AdjustmentRulerSliderState();
}

class _AdjustmentRulerSliderState extends State<_AdjustmentRulerSlider> {
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
    // ✅ 필터 편집기와 동일한 감도: range / 1.5
    final deltaValue = (deltaX / width) * (range / 1.5);
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
              painter: _AdjustmentRulerPainter(
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

/// 조정 룰러 페인터
class _AdjustmentRulerPainter extends CustomPainter {
  final double currentValue;
  final double min;
  final double max;
  final Color textColor;

  _AdjustmentRulerPainter({
    required this.currentValue,
    required this.min,
    required this.max,
    required this.textColor,
  });

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
    // ✅ 필터 편집기처럼 화면에 표시할 범위를 더 작게 (중앙 기준 좌우 range/8씩)
    final visibleRange = range / 4; // 좌우 각각 range/8
    final pixelsPerUnit = size.width / (visibleRange * 2);

    // ✅ 틱 간격을 더 촘촘하게 (10 -> 5)
    const tickInterval = 5.0;

    // ✅ 가운데 바는 항상 표시 (거의 위에 수치칩과 닿을 정도로 길게)
    canvas.drawLine(
      Offset(centerX, bottomY),
      Offset(centerX, bottomY - 40), // ✅ 더 길게 (24 -> 40)
      centerPaint,
    );

    for (double tickValue = min; tickValue <= max; tickValue += tickInterval) {
      final relative = tickValue - currentValue;

      if (relative.abs() > visibleRange) continue;

      final x = centerX + relative * pixelsPerUnit;
      // ✅ 25 단위마다 주요 틱 (tickInterval 변경에 맞춰 조정)
      final isMajor = (tickValue / 25).round() * 25 == tickValue;

      // ✅ 현재 값 위치는 건너뛰기 (가운데 바가 이미 그려졌으므로)
      if ((relative.abs() < 0.5)) continue;

      if (isMajor) {
        canvas.drawLine(
          Offset(x, bottomY),
          Offset(x, bottomY - 16),
          majorTickPaint,
        );
        // 숫자 표시
        final textSpan = TextSpan(
          text: tickValue.toInt().toString(),
          style: TextStyle(
            color: textColor.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
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
  bool shouldRepaint(_AdjustmentRulerPainter oldDelegate) {
    return oldDelegate.currentValue != currentValue ||
        oldDelegate.min != min ||
        oldDelegate.max != max;
  }
}
