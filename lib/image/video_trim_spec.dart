/// 비디오 트림 스펙 (비파괴)
///
/// - FFmpeg로 실제 트림을 굽지 않고, start/end 값만 전달한다.
class VideoTrimSpec {
  const VideoTrimSpec({required this.startSeconds, required this.endSeconds});

  final double startSeconds;
  final double endSeconds;

  Map<String, dynamic> toJson() => {
    'startSeconds': startSeconds,
    'endSeconds': endSeconds,
  };

  static VideoTrimSpec fromJson(Map<String, dynamic> json) {
    return VideoTrimSpec(
      startSeconds: (json['startSeconds'] as num?)?.toDouble() ?? 0.0,
      endSeconds: (json['endSeconds'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
