import 'package:flutter/material.dart';

/// 이미지 조정 타입
enum AdjustmentType {
  exposure, // 조도
  brightness, // 밝기
  contrast, // 대비
  temperature, // 온도
  saturation, // 채도
  highlight, // 하이라이트
  shadow, // 그림자
}

/// 조정 타입 유틸리티
class AdjustmentTypeUtils {
  /// 조정 타입의 표시 이름
  static String getLabel(AdjustmentType type) {
    switch (type) {
      case AdjustmentType.exposure:
        return '조도';
      case AdjustmentType.brightness:
        return '밝기';
      case AdjustmentType.contrast:
        return '대비';
      case AdjustmentType.temperature:
        return '온도';
      case AdjustmentType.saturation:
        return '채도';
      case AdjustmentType.highlight:
        return '하이라이트';
      case AdjustmentType.shadow:
        return '그림자';
    }
  }

  /// 조정 타입의 아이콘
  static IconData getIcon(AdjustmentType type) {
    switch (type) {
      case AdjustmentType.exposure:
        return Icons.exposure;
      case AdjustmentType.brightness:
        return Icons.brightness_6;
      case AdjustmentType.contrast:
        return Icons.contrast;
      case AdjustmentType.temperature:
        return Icons.thermostat;
      case AdjustmentType.saturation:
        return Icons.water_drop;
      case AdjustmentType.highlight:
        return Icons.highlight;
      case AdjustmentType.shadow:
        return Icons.wb_shade;
    }
  }

  /// 조정 값의 최소값
  static double getMinValue(AdjustmentType type) {
    return -100.0;
  }

  /// 조정 값의 최대값
  static double getMaxValue(AdjustmentType type) {
    return 100.0;
  }

  /// 조정 값의 기본값
  static double getDefaultValue(AdjustmentType type) {
    return 0.0;
  }

  /// 모든 조정 타입 목록
  static const List<AdjustmentType> allTypes = [
    AdjustmentType.exposure,
    AdjustmentType.brightness,
    AdjustmentType.contrast,
    AdjustmentType.temperature,
    AdjustmentType.saturation,
    AdjustmentType.highlight,
    AdjustmentType.shadow,
  ];
}

/// 이미지 조정 상태
class ImageAdjustmentState {
  final double exposure;
  final double brightness;
  final double contrast;
  final double temperature;
  final double saturation;
  final double highlight;
  final double shadow;

  const ImageAdjustmentState({
    this.exposure = 0.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.temperature = 0.0,
    this.saturation = 0.0,
    this.highlight = 0.0,
    this.shadow = 0.0,
  });

  /// 특정 조정 값 가져오기
  double getValue(AdjustmentType type) {
    switch (type) {
      case AdjustmentType.exposure:
        return exposure;
      case AdjustmentType.brightness:
        return brightness;
      case AdjustmentType.contrast:
        return contrast;
      case AdjustmentType.temperature:
        return temperature;
      case AdjustmentType.saturation:
        return saturation;
      case AdjustmentType.highlight:
        return highlight;
      case AdjustmentType.shadow:
        return shadow;
    }
  }

  /// 특정 조정 값 설정하여 새 상태 반환
  ImageAdjustmentState setValue(AdjustmentType type, double value) {
    switch (type) {
      case AdjustmentType.exposure:
        return copyWith(exposure: value);
      case AdjustmentType.brightness:
        return copyWith(brightness: value);
      case AdjustmentType.contrast:
        return copyWith(contrast: value);
      case AdjustmentType.temperature:
        return copyWith(temperature: value);
      case AdjustmentType.saturation:
        return copyWith(saturation: value);
      case AdjustmentType.highlight:
        return copyWith(highlight: value);
      case AdjustmentType.shadow:
        return copyWith(shadow: value);
    }
  }

  /// 모든 값이 기본값인지 확인
  bool get isDefault {
    return exposure == 0.0 &&
        brightness == 0.0 &&
        contrast == 0.0 &&
        temperature == 0.0 &&
        saturation == 0.0 &&
        highlight == 0.0 &&
        shadow == 0.0;
  }

  ImageAdjustmentState copyWith({
    double? exposure,
    double? brightness,
    double? contrast,
    double? temperature,
    double? saturation,
    double? highlight,
    double? shadow,
  }) {
    return ImageAdjustmentState(
      exposure: exposure ?? this.exposure,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      temperature: temperature ?? this.temperature,
      saturation: saturation ?? this.saturation,
      highlight: highlight ?? this.highlight,
      shadow: shadow ?? this.shadow,
    );
  }
}

/// 이미지 조정 유틸리티
class ImageAdjustmentUtils {
  /// 조정 값을 ColorFilter로 변환
  static ColorFilter? getColorFilter(ImageAdjustmentState state) {
    if (state.isDefault) return null;

    // 각 조정을 독립적으로 계산 (값 범위: -100 ~ 100)

    // 1. 밝기 (전체적인 밝기) - 정규화: -100~100 → -255~255
    final brightnessOffset = (state.brightness / 100.0) * 255;

    // 2. 대비 (명암 차이) - 정규화: -100~100 → -1~1
    final contrastNorm = state.contrast / 100.0;
    final contrastScale = 1.0 + contrastNorm;
    final contrastOffset = -(contrastNorm * 128);

    // 3. 채도 (색상 강도) - 정규화: -100~100 → -1~1
    final satNorm = state.saturation / 100.0;
    final satScale = 1.0 + satNorm;
    final lumR = 0.2989;
    final lumG = 0.5870;
    final lumB = 0.1140;
    final sr = (1.0 - satScale) * lumR;
    final sg = (1.0 - satScale) * lumG;
    final sb = (1.0 - satScale) * lumB;

    // 4. 온도 (따뜻함/차가움) - 정규화: -100~100 → -0.3~0.3
    final tempNorm = state.temperature / 100.0;
    final tempR = 1.0 + (tempNorm > 0 ? tempNorm * 0.3 : 0);
    final tempG = 1.0 - (tempNorm.abs() * 0.1);
    final tempB = 1.0 + (tempNorm < 0 ? -tempNorm * 0.3 : 0);

    // 5. 조도 (전체 노출) - 정규화: -100~100 → -0.5~0.5
    final exposureScale = 1.0 + ((state.exposure / 100.0) * 0.5);

    // 6. 하이라이트 (밝은 부분만) - 정규화: -100~100 → -60~60
    final highlightBoost = (state.highlight / 100.0) * 60;

    // 7. 그림자 (어두운 부분만) - 정규화: -100~100 → -60~60
    final shadowBoost = (state.shadow / 100.0) * 60;

    // 전체 조합
    final totalBrightness = brightnessOffset + highlightBoost + shadowBoost;

    return ColorFilter.matrix([
      // R
      (sr + satScale) * contrastScale * exposureScale * tempR,
      sg * contrastScale * exposureScale,
      sb * contrastScale * exposureScale,
      0,
      totalBrightness + contrastOffset,

      // G
      sr * contrastScale * exposureScale,
      (sg + satScale) * contrastScale * exposureScale * tempG,
      sb * contrastScale * exposureScale,
      0,
      totalBrightness + contrastOffset,

      // B
      sr * contrastScale * exposureScale,
      sg * contrastScale * exposureScale,
      (sb + satScale) * contrastScale * exposureScale * tempB,
      0,
      totalBrightness + contrastOffset,

      // A
      0, 0, 0, 1, 0,
    ]);
  }
}
