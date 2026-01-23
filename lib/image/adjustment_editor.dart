import 'dart:math' as math;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 조정 타입
enum AdjustmentType {
  brightness('밝기', Icons.brightness_6),
  contrast('대비', Icons.contrast),
  saturation('채도', Icons.palette),
  luminance('휘도', Icons.wb_sunny),
  exposure('노출', Icons.exposure),
  temperature('색온도', Icons.thermostat),
  blur('블러', Icons.blur_on);

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
  double temperature = 0.0; // -100 ~ 100 (차갑게 ~ 따뜻하게)
  double blur = 0.0; // 0 ~ 100

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
      case AdjustmentType.temperature:
        return temperature;
      case AdjustmentType.blur:
        return blur;
    }
  }

  void setValue(AdjustmentType type, double value) {
    // ✅ 0 근처 값은 정확히 0으로 스냅 (부동소수/ -0.0 방지)
    // 버튼 활성(보라색 테두리) 판정이 즉시 꺼지도록 보장
    final v = value.abs() < 0.01 ? 0.0 : value;
    switch (type) {
      case AdjustmentType.brightness:
        brightness = v;
        break;
      case AdjustmentType.contrast:
        contrast = v;
        break;
      case AdjustmentType.saturation:
        saturation = v;
        break;
      case AdjustmentType.luminance:
        luminance = v;
        break;
      case AdjustmentType.exposure:
        exposure = v;
        break;
      case AdjustmentType.temperature:
        temperature = v;
        break;
      case AdjustmentType.blur:
        blur = v;
        break;
    }
  }

  AdjustmentState copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? luminance,
    double? exposure,
    double? temperature,
    double? blur,
  }) {
    return AdjustmentState()
      ..brightness = brightness ?? this.brightness
      ..contrast = contrast ?? this.contrast
      ..saturation = saturation ?? this.saturation
      ..luminance = luminance ?? this.luminance
      ..exposure = exposure ?? this.exposure
      ..temperature = temperature ?? this.temperature
      ..blur = blur ?? this.blur;
  }
}

/// 조정(밝기/대비/채도 등) 행렬 계산 유틸
class AdjustmentUtils {
  const AdjustmentUtils._();

  /// ✅ 블러(0~100)를 "저장/노드 결과" 기준 sigma(px)로 변환한다.
  /// - 현재 저장(이미지) 및 FFmpeg(비디오) 모두 0~20 범위를 기준으로 사용 중
  static double blurSigmaForExport(double blur) {
    if (blur <= 0.01) return 0.0;
    return (blur / 100.0) * 20.0;
  }

  /// ✅ 프리뷰(화면 렌더)에서 "노드에 굽혀진 결과"와 동일하게 보이도록 sigma를 보정한다.
  ///
  /// 배경:
  /// - 저장/노드: 원본 해상도(px) 좌표계에서 sigma가 적용됨
  /// - 프리뷰: 화면에 축소된 좌표계에서 sigma가 적용되면 체감이 과해짐
  ///
  /// 따라서 \(sigma_{preview} = sigma_{export} * (displayWidth / sourceWidth)\) 로 스케일 보정한다.
  static double blurSigmaForPreview({
    required double blur,
    required double sourceWidthPx,
    required double displayWidthPx,
  }) {
    final sigmaExport = blurSigmaForExport(blur);
    if (sigmaExport <= 0.0) return 0.0;
    if (sourceWidthPx <= 0 || displayWidthPx <= 0) return sigmaExport;
    final s = (displayWidthPx / sourceWidthPx).clamp(0.0, 1.0);
    return (sigmaExport * s).clamp(0.0, sigmaExport);
  }

  /// 조정 상태를 ColorMatrix로 변환
  ///
  /// [brightness]: -100 ~ 100 (밝기)
  /// [contrast]: -100 ~ 100 (대비)
  /// [saturation]: -100 ~ 100 (채도)
  /// [luminance]: -100 ~ 100 (휘도)
  /// [exposure]: -100 ~ 100 (노출)
  /// [temperature]: -100 ~ 100 (색온도, 차갑게 ~ 따뜻하게)
  ///
  /// 모든 값이 0이면 null 반환 (변경 없음)
  static List<double>? getAdjustmentMatrix({
    required double brightness,
    required double contrast,
    required double saturation,
    double luminance = 0.0,
    double exposure = 0.0,
    double temperature = 0.0,
  }) {
    if (brightness == 0.0 &&
        contrast == 0.0 &&
        saturation == 0.0 &&
        luminance == 0.0 &&
        exposure == 0.0 &&
        temperature == 0.0) {
      return null;
    }

    // pro_image_editor의 ColorFilterAddons 참고하여 구현
    List<double>? resultMatrix;

    // 1. 밝기 (brightness)
    if (brightness != 0.0) {
      final brightnessValue = brightness / 100.0;
      final brightnessMatrix = [
        1.0,
        0.0,
        0.0,
        0.0,
        brightnessValue * 255,
        0.0,
        1.0,
        0.0,
        0.0,
        brightnessValue * 255,
        0.0,
        0.0,
        1.0,
        0.0,
        brightnessValue * 255,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ];
      // ✅ 첫 연산이므로 그대로 초기화 (flow 상 resultMatrix는 항상 null)
      resultMatrix = brightnessMatrix;
    }

    // 2. 대비 (contrast)
    if (contrast != 0.0) {
      final adj = contrast / 100.0 * 255;
      final factor = (259 * (adj + 255)) / (255 * (259 - adj));
      final offset = 128 * (1 - factor);
      final contrastMatrix = [
        factor,
        0.0,
        0.0,
        0.0,
        offset,
        0.0,
        factor,
        0.0,
        0.0,
        offset,
        0.0,
        0.0,
        factor,
        0.0,
        offset,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ];
      resultMatrix =
          resultMatrix != null
              ? _multiplyMatrices(resultMatrix, contrastMatrix)
              : contrastMatrix;
    }

    // 3. 채도 (saturation)
    if (saturation != 0.0) {
      final satValue = 1.0 + (saturation / 100.0);
      const lumR = 0.3086;
      const lumG = 0.6094;
      const lumB = 0.082;
      final xInverted = 1.0 - satValue;
      final saturationMatrix = [
        lumR * xInverted + satValue,
        lumG * xInverted,
        lumB * xInverted,
        0.0,
        0.0,
        lumR * xInverted,
        lumG * xInverted + satValue,
        lumB * xInverted,
        0.0,
        0.0,
        lumR * xInverted,
        lumG * xInverted,
        lumB * xInverted + satValue,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ];
      resultMatrix =
          resultMatrix != null
              ? _multiplyMatrices(resultMatrix, saturationMatrix)
              : saturationMatrix;
    }

    // 4. 노출 (exposure)
    if (exposure != 0.0) {
      // exposure는 -100 ~ 100 범위를 -2.0 ~ 2.0으로 변환
      final exposureValue = (exposure / 100.0) * 2.0;
      final exposureFactor = math.pow(2, exposureValue).toDouble();
      final exposureMatrix = [
        exposureFactor,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        exposureFactor,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        exposureFactor,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ];
      resultMatrix =
          resultMatrix != null
              ? _multiplyMatrices(resultMatrix, exposureMatrix)
              : exposureMatrix;
    }

    // 5. 색온도 (temperature)
    if (temperature != 0.0) {
      // temperature는 -100 ~ 100 범위를 -1.0 ~ 1.0으로 변환
      final tempValue = temperature / 100.0;
      final r = tempValue > 0 ? tempValue : 0.0;
      final b = tempValue < 0 ? -tempValue : 0.0;
      final temperatureMatrix = [
        1.0 + r,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0 + r * 0.5,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0 + b,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ];
      resultMatrix =
          resultMatrix != null
              ? _multiplyMatrices(resultMatrix, temperatureMatrix)
              : temperatureMatrix;
    }

    // 6. 휘도 (luminance)
    if (luminance != 0.0) {
      // luminance는 -100 ~ 100 범위를 -1.0 ~ 1.0으로 변환
      final lumValue = luminance / 100.0;
      const lumR = 0.2126;
      const lumG = 0.7152;
      const lumB = 0.0722;
      final adjustedValue = 1.0 - lumValue;
      final luminanceMatrix = [
        lumR * lumValue + adjustedValue,
        lumG * lumValue,
        lumB * lumValue,
        0.0,
        0.0,
        lumR * lumValue,
        lumG * lumValue + adjustedValue,
        lumB * lumValue,
        0.0,
        0.0,
        lumR * lumValue,
        lumG * lumValue,
        lumB * lumValue + adjustedValue,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ];
      resultMatrix =
          resultMatrix != null
              ? _multiplyMatrices(resultMatrix, luminanceMatrix)
              : luminanceMatrix;
    }

    return resultMatrix;
  }

  /// 두 개의 4x5 ColorMatrix를 곱셈
  static List<double> _multiplyMatrices(List<double> a, List<double> b) {
    final result = List<double>.filled(20, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[i * 5 + k] * b[k * 5 + j];
        }
        result[i * 5 + j] = sum;
      }
    }
    return result;
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
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount:
                                  AdjustmentType.values.length + 1, // 리셋 버튼 포함
                              separatorBuilder:
                                  (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                // 가장 좌측: 리셋 버튼
                                if (i == 0) {
                                  // 모든 조정 값이 0인지 확인
                                  final hasAnyAdjustment = AdjustmentType.values
                                      .any(
                                        (type) =>
                                            widget.state.getValue(type).abs() >
                                            0.01,
                                      );

                                  return _ResetButton(
                                    fgColor: fgColor,
                                    isActive: hasAnyAdjustment,
                                    onTap: () {
                                      // 모든 조정 값을 0으로 리셋
                                      final resetState = AdjustmentState();
                                      widget.onStateChanged(resetState);
                                      // 슬라이더 모드면 버튼 모드로 돌아가기
                                      if (_selectedType != null) {
                                        setState(() {
                                          _selectedType = null;
                                          widget.onSliderModeChanged?.call(
                                            false,
                                          );
                                        });
                                      }
                                    },
                                  );
                                }

                                // 조정 버튼들
                                final type = AdjustmentType.values[i - 1];
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
    final min = (type == AdjustmentType.blur) ? 0.0 : -100.0;
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

/// 리셋 버튼 (가장 좌측에 배치)
class _ResetButton extends StatelessWidget {
  const _ResetButton({
    required this.fgColor,
    required this.isActive,
    required this.onTap,
  });

  final Color fgColor;
  final bool isActive; // 조정이 하나라도 적용되어 있으면 활성
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: isActive ? onTap : null, // 조정이 없으면 비활성화
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
                color: isActive ? cs.primary : fgColor.withOpacity(0.3),
                width: isActive ? 2.5 : 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.block, // 금지 아이콘
                color: isActive ? cs.primary : fgColor.withOpacity(0.5),
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 라벨
          Text(
            '리셋',
            style: TextStyle(
              color: isActive ? cs.primary : fgColor.withOpacity(0.5),
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
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
    // ✅ 블러는 더 빠른 감도 적용: range / 0.8 (다른 조정보다 빠르게)
    // ✅ 일반 조정은 range / 1.5
    final sensitivity = widget.min == 0.0 ? (range / 0.8) : (range / 1.5);
    // ✅ 슬라이더 방향 반전: deltaX를 반대로 계산
    final deltaValue = (-deltaX / width) * sensitivity;
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
