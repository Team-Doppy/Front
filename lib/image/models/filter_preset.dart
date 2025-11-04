import 'package:flutter/material.dart';

/// 필터 타입 정의
enum FilterType {
  none,
  original,
  vivid,
  warm,
  cool,
  dramatic,
  blackWhite,
  sepia,
  vintage,
}

/// 필터 프리셋 모델
class FilterPreset {
  final FilterType type;
  final String name;
  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;
  final double sepia;
  final double vignette;

  const FilterPreset({
    required this.type,
    required this.name,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.hue = 0.0,
    this.sepia = 0.0,
    this.vignette = 0.0,
  });
}

/// 기본 필터 프리셋 목록
class FilterPresets {
  static const List<FilterPreset> defaults = [
    FilterPreset(type: FilterType.none, name: '원본'),
    FilterPreset(
      type: FilterType.vivid,
      name: '비비드',
      brightness: 0.1,
      contrast: 0.2,
      saturation: 0.3,
    ),
    FilterPreset(
      type: FilterType.warm,
      name: '웜',
      brightness: 0.05,
      contrast: 0.1,
      saturation: 0.1,
      hue: 0.1,
    ),
    FilterPreset(
      type: FilterType.cool,
      name: '쿨',
      brightness: 0.05,
      contrast: 0.1,
      saturation: 0.1,
      hue: -0.1,
    ),
    FilterPreset(
      type: FilterType.dramatic,
      name: '드라마틱',
      brightness: -0.1,
      contrast: 0.3,
      saturation: 0.2,
    ),
    FilterPreset(
      type: FilterType.blackWhite,
      name: '흑백',
      brightness: 0.0,
      contrast: 0.2,
      saturation: -1.0,
    ),
    FilterPreset(
      type: FilterType.sepia,
      name: '세피아',
      brightness: 0.1,
      contrast: 0.1,
      sepia: 0.8,
    ),
    FilterPreset(
      type: FilterType.vintage,
      name: '빈티지',
      brightness: 0.1,
      contrast: 0.2,
      saturation: -0.2,
      hue: 0.05,
      vignette: 0.3,
    ),
  ];
}

/// 필터 적용 유틸리티
class FilterUtils {
  /// 필터 프리셋을 ColorFilter로 변환
  static ColorFilter? getColorFilter(
    FilterPreset preset, {
    double intensity = 1.0,
  }) {
    if (preset.type == FilterType.none) return null;

    final brightness = preset.brightness * intensity;
    final contrast = preset.contrast * intensity;

    // 매트릭스 조합 (간단한 버전)
    return ColorFilter.matrix([
      contrast + 1,
      0,
      0,
      0,
      brightness * 255,
      0,
      contrast + 1,
      0,
      0,
      brightness * 255,
      0,
      0,
      contrast + 1,
      0,
      brightness * 255,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}
