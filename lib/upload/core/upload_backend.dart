import 'dart:io';

import 'upload_types.dart';

/// 업로드 백엔드 인터페이스
///
/// R2, S3, GCS, Firebase 등 어떤 스토리지든 이 인터페이스만 구현하면
/// [UploadService]에서 동일하게 사용할 수 있습니다.
///
/// ## 확장 예시
///
/// ```dart
/// class S3UploadBackend implements UploadBackend { ... }
/// class GcsUploadBackend implements UploadBackend { ... }
/// ```
abstract class UploadBackend {
  Future<UploadResult> uploadFile({
    required File file,
    String? fileName,
    String? pathPrefix,
    void Function(double progress)? onProgress,
    dynamic cancelToken,
  });

  Future<List<UploadResult>> uploadFiles({
    required List<File> files,
    String? pathPrefix,
    void Function(int current, int total, double progress)? onProgress,
    dynamic cancelToken,
  });

  Future<UploadResult> uploadBytes({
    required List<int> bytes,
    required String fileName,
    String? pathPrefix,
    void Function(double progress)? onProgress,
    dynamic cancelToken,
  });

  Future<void> initialize(Map<String, dynamic> settings);
  Future<void> dispose();
}

/// 백엔드 공통: 연결 실패 시 재시도 등
extension UploadBackendExtension on UploadBackend {
  Future<bool> checkConnection({Duration? retryDelay}) => Future.value(true);

  Future<T> retryOnConnectionFailure<T>({
    required Future<T> Function() action,
    Duration retryDelay = const Duration(seconds: 2),
    int maxRetries = 1,
  }) async {
    int attempts = 0;
    while (attempts <= maxRetries) {
      try {
        return await action();
      } catch (e) {
        attempts++;
        if (attempts > maxRetries) rethrow;
        await Future.delayed(retryDelay);
      }
    }
    throw StateError('Max retries exceeded');
  }
}
