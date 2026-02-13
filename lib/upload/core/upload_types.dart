import 'package:flutter/foundation.dart';

/// 업로드 상태
enum UploadState { pending, uploading, success, failed, cancelled }

/// 업로드 종류
enum UploadKind {
  image,
  video,
}

/// 취소 토큰 (압축 등 장시간 작업 취소용)
class CancellationToken extends ChangeNotifier {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      notifyListeners();
    }
  }
}

/// 업로드 결과 (모든 백엔드 공통)
class UploadResult {
  final String? accessUrl;
  final String? url;
  final String? imageId;
  final Map<String, dynamic>? metadata;

  const UploadResult({this.accessUrl, this.url, this.imageId, this.metadata});

  String? get effectiveUrl => accessUrl ?? url;

  Map<String, dynamic> toMap() {
    return {
      if (accessUrl != null) 'accessUrl': accessUrl,
      if (url != null) 'url': url,
      if (imageId != null) 'imageId': imageId,
      if (metadata != null) ...metadata!,
    };
  }
}
