import 'dart:ui';

/// 비디오 편집 값(비파괴) 스펙
///
/// - MediaPicker → SimpleVideoEditor → VideoTrim → Upload 단계에서 전달
/// - "최종 FFmpeg 1회"를 위해, 여기에는 **파일/bytes가 아니라 값만** 담는다.
class VideoEditSpec {
  const VideoEditSpec({
    this.rotation = 0,
    this.rotationQuarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRectImage,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.luminance = 0.0,
    this.exposure = 0.0,
    this.sharpness = 0.0,
    this.temperature = 0.0,
    this.blur = 0.0,
    this.vignette = 0.0,
    this.filterName,
    this.filterIntensity = 1.0,
  });

  /// 미세 회전(°): -45 ~ 45
  final int rotation;

  /// 90도 회전: 0..3
  final int rotationQuarterTurns;

  final bool flipHorizontal;
  final bool flipVertical;

  /// 이미지 좌표계(=원본 픽셀 기준) 크롭 rect.
  /// - VideoTrim/Upload에서 FFmpeg crop 필터로 변환하여 사용한다.
  final Rect? cropRectImage;

  // ===== adjustments =====
  /// -100 ~ 100
  final double brightness;

  /// -100 ~ 100
  final double contrast;

  /// -100 ~ 100
  final double saturation;

  /// -100 ~ 100
  final double luminance;

  /// -100 ~ 100
  final double exposure;

  /// 0 ~ 100
  final double sharpness;

  /// -100 ~ 100
  final double temperature;

  /// 0 ~ 100
  final double blur;

  /// 0 ~ 100
  final double vignette;

  // ===== filter preset =====
  /// FilterModel.name를 저장 (프리셋은 코드에서 매핑)
  final String? filterName;
  final double filterIntensity;

  VideoEditSpec copyWith({
    int? rotation,
    int? rotationQuarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
    Rect? cropRectImage,
    double? brightness,
    double? contrast,
    double? saturation,
    double? luminance,
    double? exposure,
    double? sharpness,
    double? temperature,
    double? blur,
    double? vignette,
    String? filterName,
    double? filterIntensity,
  }) {
    return VideoEditSpec(
      rotation: rotation ?? this.rotation,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      cropRectImage: cropRectImage ?? this.cropRectImage,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      luminance: luminance ?? this.luminance,
      exposure: exposure ?? this.exposure,
      sharpness: sharpness ?? this.sharpness,
      temperature: temperature ?? this.temperature,
      blur: blur ?? this.blur,
      vignette: vignette ?? this.vignette,
      filterName: filterName ?? this.filterName,
      filterIntensity: filterIntensity ?? this.filterIntensity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rotation': rotation,
      'rotationQuarterTurns': rotationQuarterTurns,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'cropRectImage':
          cropRectImage == null
              ? null
              : {
                'left': cropRectImage!.left,
                'top': cropRectImage!.top,
                'width': cropRectImage!.width,
                'height': cropRectImage!.height,
              },
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'luminance': luminance,
      'exposure': exposure,
      'sharpness': sharpness,
      'temperature': temperature,
      'blur': blur,
      'vignette': vignette,
      'filterName': filterName,
      'filterIntensity': filterIntensity,
    };
  }

  static VideoEditSpec fromJson(Map<String, dynamic> json) {
    final crop = json['cropRectImage'];
    Rect? cropRect;
    if (crop is Map) {
      final left = (crop['left'] as num?)?.toDouble();
      final top = (crop['top'] as num?)?.toDouble();
      final width = (crop['width'] as num?)?.toDouble();
      final height = (crop['height'] as num?)?.toDouble();
      if (left != null && top != null && width != null && height != null) {
        cropRect = Rect.fromLTWH(left, top, width, height);
      }
    }
    return VideoEditSpec(
      rotation: (json['rotation'] as num?)?.toInt() ?? 0,
      rotationQuarterTurns:
          (json['rotationQuarterTurns'] as num?)?.toInt() ?? 0,
      flipHorizontal: json['flipHorizontal'] == true,
      flipVertical: json['flipVertical'] == true,
      cropRectImage: cropRect,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
      luminance: (json['luminance'] as num?)?.toDouble() ?? 0.0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      blur: (json['blur'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
      filterName: json['filterName'] as String?,
      filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
