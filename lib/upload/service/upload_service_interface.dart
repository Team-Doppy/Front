import 'dart:io';
import 'package:flutter/foundation.dart';

import '../core/upload_types.dart';
import '../core/upload_task.dart';

/// 업로드 서비스 인터페이스
///
/// 에디터 등에서 [IUploadService]만 의존하고,
/// 실제 구현([UploadService])과 백엔드(R2, S3 등)는 주입받습니다.
abstract class IUploadService extends ChangeNotifier {
  bool hasActiveUploadForRef(String refId);
  bool hasActiveUploadForAnyRef(Iterable<String> refIds);
  bool isBusyRef(String refId);
  bool isBusyAnyRef(Iterable<String> refIds);
  bool hasActiveCompressionForRef(String refId);

  UploadTask enqueueFile(
    File file, {
    required UploadKind kind,
    String? refId,
    String? pathPrefix,
  });

  UploadTask enqueueBytes(
    List<int> bytes,
    String fileName, {
    required UploadKind kind,
    String? refId,
    String? pathPrefix,
  });

  Future<List<UploadTask>> enqueueFiles(
    List<File> files, {
    required UploadKind kind,
    String? refId,
    String? Function(File file)? refIdMapper,
    String? pathPrefix,
    Duration timeout = const Duration(seconds: 60),
  });

  Future<bool> waitForTask(
    UploadTask task, {
    Duration timeout = const Duration(seconds: 60),
  });

  void cancelUploadForRef(String refId);
  void cancelUploadsForRefs(Iterable<String> refIds);
  @Deprecated('Use cancelUploadForRef instead')
  void cancelByRef(String refId) => cancelUploadForRef(refId);
  void cancelAllUploads();

  UploadTask? getTaskForRef(String refId);
  List<UploadTask> getActiveTasks();
  String debugDumpActiveTasksForRefs(
    Iterable<String> refIds, {
    Set<UploadKind>? kinds,
  });
}
