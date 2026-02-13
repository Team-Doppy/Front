import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'upload_types.dart';

/// 업로드 태스크 (진행률·상태 추적)
class UploadTask extends ChangeNotifier {
  final String id;
  final UploadKind kind;
  final File? file;
  final Uint8List? bytes;
  final String fileName;
  final String? refId;
  final dynamic cancelToken;

  UploadState state = UploadState.pending;
  double progress = 0.0;
  String? url;
  String? imageId;
  Object? error;
  int attempt = 0;
  DateTime? finalizedAt;

  UploadTask({
    required this.id,
    required this.kind,
    required this.fileName,
    this.file,
    this.bytes,
    this.refId,
    this.cancelToken,
  });

  void _setProgress(double value) {
    progress = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void _setState(UploadState s) {
    state = s;
    if (s == UploadState.success ||
        s == UploadState.failed ||
        s == UploadState.cancelled) {
      finalizedAt ??= DateTime.now();
    } else {
      finalizedAt = null;
    }
    notifyListeners();
  }

  void setProgress(double value) => _setProgress(value);
  void setState(UploadState s) => _setState(s);
}
