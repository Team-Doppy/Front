import 'dart:ui' as ui;

/// 비디오 트림 스펙 (비파괴)
///
/// - FFmpeg로 실제 트림을 굽지 않고, start/end 값만 전달한다.
class VideoTrimSpec {
  const VideoTrimSpec({
    required this.startSeconds,
    required this.endSeconds,
    this.cropRect,
  });

  final double startSeconds;
  final double endSeconds;
  final ui.Rect? cropRect; // 크롭 영역 (이미지 좌표계, 픽셀 기준)

  Map<String, dynamic> toJson() => {
    'startSeconds': startSeconds,
    'endSeconds': endSeconds,
    if (cropRect != null) ...{
      'cropLeft': cropRect!.left,
      'cropTop': cropRect!.top,
      'cropWidth': cropRect!.width,
      'cropHeight': cropRect!.height,
    },
  };

  static VideoTrimSpec fromJson(Map<String, dynamic> json) {
    ui.Rect? cropRect;
    if (json['cropLeft'] != null &&
        json['cropTop'] != null &&
        json['cropWidth'] != null &&
        json['cropHeight'] != null) {
      cropRect = ui.Rect.fromLTWH(
        (json['cropLeft'] as num).toDouble(),
        (json['cropTop'] as num).toDouble(),
        (json['cropWidth'] as num).toDouble(),
        (json['cropHeight'] as num).toDouble(),
      );
    }
    return VideoTrimSpec(
      startSeconds: (json['startSeconds'] as num?)?.toDouble() ?? 0.0,
      endSeconds: (json['endSeconds'] as num?)?.toDouble() ?? 0.0,
      cropRect: cropRect,
    );
  }
}
