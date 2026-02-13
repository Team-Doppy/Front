import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../core/upload_config.dart';
import '../core/upload_types.dart';
import '../core/upload_task.dart';
import 'upload_service_interface.dart';

/// 업로드 오케스트레이션 서비스
///
/// [UploadConfig]로 주입된 백엔드(R2, S3 등)를 사용해
/// enqueue → 처리 → 완료/실패 알림을 담당합니다.
class UploadService extends ChangeNotifier implements IUploadService {
  UploadConfig? _config;
  final Map<String, UploadTask> _tasks = {};
  final Set<String> _processingRefIds = {};

  Future<void> initialize(UploadConfig config) async {
    _config = config;
    await config.backend.initialize({});
  }

  @override
  void dispose() {
    cancelAllUploads();
    _config?.backend.dispose().ignore();
    _config = null;
    _tasks.clear();
    _processingRefIds.clear();
    super.dispose();
  }

  @override
  bool hasActiveUploadForRef(String refId) {
    return _tasks.values.any(
      (t) => t.refId == refId && t.state == UploadState.uploading,
    );
  }

  @override
  bool hasActiveUploadForAnyRef(Iterable<String> refIds) {
    final refIdSet = refIds.toSet();
    return _tasks.values.any(
      (task) =>
          task.refId != null &&
          refIdSet.contains(task.refId) &&
          task.state == UploadState.uploading,
    );
  }

  @override
  bool isBusyRef(String refId) {
    return _processingRefIds.contains(refId) || hasActiveUploadForRef(refId);
  }

  @override
  bool isBusyAnyRef(Iterable<String> refIds) {
    final refIdSet = refIds.toSet();
    return _processingRefIds.any(refIdSet.contains) ||
        hasActiveUploadForAnyRef(refIds);
  }

  @override
  bool hasActiveCompressionForRef(String refId) {
    return _processingRefIds.contains(refId);
  }

  @override
  UploadTask enqueueFile(
    File file, {
    required UploadKind kind,
    String? refId,
    String? pathPrefix,
  }) {
    if (_config == null) {
      throw StateError(
        'UploadService not initialized. Call initialize() first.',
      );
    }
    final task = UploadTask(
      id: 'upload_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}',
      kind: kind,
      file: file,
      fileName: file.path.split('/').last,
      refId: refId,
    );
    _tasks[task.id] = task;
    _processTask(task, pathPrefix: pathPrefix);
    notifyListeners();
    return task;
  }

  @override
  UploadTask enqueueBytes(
    List<int> bytes,
    String fileName, {
    required UploadKind kind,
    String? refId,
    String? pathPrefix,
  }) {
    if (_config == null) {
      throw StateError(
        'UploadService not initialized. Call initialize() first.',
      );
    }
    final task = UploadTask(
      id: 'upload_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}',
      kind: kind,
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      refId: refId,
    );
    _tasks[task.id] = task;
    _processTask(task, pathPrefix: pathPrefix);
    notifyListeners();
    return task;
  }

  @override
  Future<List<UploadTask>> enqueueFiles(
    List<File> files, {
    required UploadKind kind,
    String? refId,
    String? Function(File file)? refIdMapper,
    String? pathPrefix,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_config == null) {
      throw StateError(
        'UploadService not initialized. Call initialize() first.',
      );
    }
    if (files.isEmpty) return [];
    final tasks = files
        .map(
          (file) => enqueueFile(
            file,
            kind: kind,
            refId: refId ?? (refIdMapper != null ? refIdMapper(file) : null),
            pathPrefix: pathPrefix,
          ),
        )
        .toList();
    await Future.wait(
      tasks.map((task) async {
        while (task.state == UploadState.pending ||
            task.state == UploadState.uploading) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }),
    ).timeout(
      timeout,
      onTimeout: () => throw TimeoutException('배치 업로드 시간이 초과되었습니다.', timeout),
    );
    return tasks.where((task) => task.state == UploadState.success).toList();
  }

  @override
  Future<bool> waitForTask(
    UploadTask task, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final startTime = DateTime.now();
      while (task.state == UploadState.pending ||
          task.state == UploadState.uploading) {
        if (DateTime.now().difference(startTime) > timeout) {
          throw TimeoutException('업로드 시간이 초과되었습니다.', timeout);
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return task.state == UploadState.success;
    } on TimeoutException {
      return false;
    }
  }

  @override
  void cancelUploadForRef(String refId) {
    for (final task in _tasks.values.where((t) => t.refId == refId)) {
      _cancelTask(task);
    }
  }

  @override
  void cancelUploadsForRefs(Iterable<String> refIds) {
    final refIdSet = refIds.toSet();
    for (final task in _tasks.values.where(
      (t) => t.refId != null && refIdSet.contains(t.refId),
    )) {
      _cancelTask(task);
    }
  }

  @override
  void cancelAllUploads() {
    for (final task in _tasks.values.toList()) {
      _cancelTask(task);
    }
  }

  @override
  UploadTask? getTaskForRef(String refId) {
    try {
      return _tasks.values.firstWhere((t) => t.refId == refId);
    } catch (_) {
      return null;
    }
  }

  @override
  List<UploadTask> getActiveTasks() {
    return _tasks.values
        .where(
          (t) =>
              t.state == UploadState.uploading ||
              t.state == UploadState.pending,
        )
        .toList();
  }

  @override
  String debugDumpActiveTasksForRefs(
    Iterable<String> refIds, {
    Set<UploadKind>? kinds,
  }) {
    final refIdSet = refIds.toSet();
    final tasks = _tasks.values.where((task) {
      if (task.refId == null || !refIdSet.contains(task.refId)) return false;
      if (kinds != null && !kinds.contains(task.kind)) return false;
      return task.state == UploadState.uploading ||
          task.state == UploadState.pending;
    }).toList();
    if (tasks.isEmpty) return 'No active tasks';
    final buffer = StringBuffer();
    for (final task in tasks) {
      buffer.writeln(
        'Task ${task.id}: refId=${task.refId}, kind=${task.kind}, state=${task.state}, progress=${task.progress}',
      );
    }
    return buffer.toString();
  }

  Future<void> _processTask(UploadTask task, {String? pathPrefix}) async {
    if (_config == null) return;
    task.setState(UploadState.uploading);
    try {
      UploadResult result;
      if (task.file != null) {
        result = await _config!.backend.uploadFile(
          file: task.file!,
          fileName: task.fileName,
          pathPrefix: pathPrefix,
          onProgress: (p) => task.setProgress(p),
          cancelToken: task.cancelToken,
        );
      } else if (task.bytes != null) {
        result = await _config!.backend.uploadBytes(
          bytes: task.bytes!,
          fileName: task.fileName,
          pathPrefix: pathPrefix,
          onProgress: (p) => task.setProgress(p),
          cancelToken: task.cancelToken,
        );
      } else {
        throw StateError('Task has neither file nor bytes');
      }
      task.url = result.accessUrl ?? result.url;
      task.imageId = result.imageId;
      task.setState(UploadState.success);
      task.setProgress(1.0);
    } catch (e, stackTrace) {
      task.error = e;
      task.setState(UploadState.failed);
      debugPrint(
        '[UploadService] 업로드 실패: taskId=${task.id}, refId=${task.refId}, '
        'fileName=${task.fileName}, error=$e',
      );
      debugPrint('[UploadService] stackTrace: $stackTrace');
    } finally {
      notifyListeners();
    }
  }

  void _cancelTask(UploadTask task) {
    task.setState(UploadState.cancelled);
    _tasks.remove(task.id);
    if (task.refId != null) _processingRefIds.remove(task.refId);
    notifyListeners();
  }

  void markRefAsProcessing(String refId) {
    _processingRefIds.add(refId);
    notifyListeners();
  }

  void markRefAsProcessed(String refId) {
    _processingRefIds.remove(refId);
    notifyListeners();
  }

  @override
  void cancelByRef(String refId) {
    cancelUploadForRef(refId);
  }
}
