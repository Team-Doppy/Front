import 'dart:ui';

/// 비디오 트림 스펙
///
/// 비디오의 시작 시간과 종료 시간을 지정합니다.
class VideoTrimSpec {
  /// 시작 시간 (초)
  final double startSeconds;

  /// 종료 시간 (초)
  final double endSeconds;

  const VideoTrimSpec({required this.startSeconds, required this.endSeconds});

  /// 트림 구간의 길이 (초)
  double get duration => endSeconds - startSeconds;
}

/// 비디오 편집 스펙
///
/// 비디오에 적용할 편집 옵션들을 포함합니다.
class VideoEditSpec {
  /// 90도 단위 회전 (0, 1, 2, 3 = 0도, 90도, 180도, 270도)
  final int rotationQuarterTurns;

  /// 미세 회전 (도 단위)
  final double rotation;

  /// 수평 플립
  final bool flipHorizontal;

  /// 수직 플립
  final bool flipVertical;

  /// 크롭 영역 (이미지 좌표 기준)
  final Rect? cropRectImage;

  /// 밝기 조정 (-100 ~ 100)
  final double brightness;

  /// 대비 조정 (-100 ~ 100)
  final double contrast;

  /// 채도 조정 (-100 ~ 100)
  final double saturation;

  /// 휘도 조정 (-100 ~ 100)
  final double luminance;

  /// 노출 조정 (-100 ~ 100)
  final double exposure;

  /// 선명도 조정 (0 ~ 100)
  final double sharpness;

  /// 색온도 조정 (-100 ~ 100, 음수=차갑게, 양수=따뜻하게)
  final double temperature;

  /// 흐림 효과 (0 ~ 100)
  final double blur;

  /// 비네팅 효과 (0 ~ 100)
  final double vignette;

  /// 재생 속도 (1.0 = 정상 속도)
  final double playbackSpeed;

  const VideoEditSpec({
    this.rotationQuarterTurns = 0,
    this.rotation = 0.0,
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
    this.playbackSpeed = 1.0,
  });
}
