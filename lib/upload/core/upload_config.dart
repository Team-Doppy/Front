import 'upload_backend.dart';

/// 업로드 설정
///
/// 사용할 스토리지 백엔드 하나를 선택합니다.
/// R2, S3, GCS 등 [UploadBackend] 구현체를 주입하면 됩니다.
class UploadConfig {
  final UploadBackend backend;
  final int maxConcurrent;
  final Duration imageTimeout;
  final Duration videoTimeout;
  final Duration connectionRetryDelay;

  const UploadConfig({
    required this.backend,
    this.maxConcurrent = 5,
    this.imageTimeout = const Duration(minutes: 1),
    this.videoTimeout = const Duration(minutes: 5),
    this.connectionRetryDelay = const Duration(seconds: 2),
  });
}
