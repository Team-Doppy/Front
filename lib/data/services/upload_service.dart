import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

enum UploadState { pending, uploading, success, failed, cancelled }

enum UploadKind { editorImage, thumbnail, profile }

class UploadTask extends ChangeNotifier {
  final String id;
  final UploadKind kind;
  final File? file;
  final Uint8List? bytes;
  final String fileName;
  UploadState state = UploadState.pending;
  double progress = 0.0;
  String? url;
  String? imageId;
  Object? error;
  int attempt = 0;

  UploadTask({
    required this.id,
    required this.kind,
    required this.fileName,
    this.file,
    this.bytes,
  });

  void _setProgress(double value) {
    progress = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void _setState(UploadState s) {
    state = s;
    notifyListeners();
  }
}

class UploadService with ChangeNotifier {
  static final String _baseUrl = ApiServiceBase.baseUrl;

  final List<UploadTask> _tasks = [];
  final Queue<UploadTask> _queue = Queue<UploadTask>();
  int _inflight = 0;
  int maxConcurrent = 3;
  bool _disposed = false;

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  UploadTask enqueueFile(
    File file, {
    required UploadKind kind,
    String? overrideName,
  }) {
    final String name = overrideName ?? file.path.split('/').last;
    final task = UploadTask(
      id: _genId(),
      kind: kind,
      fileName: name,
      file: file,
    );
    _register(task);
    return task;
  }

  UploadTask enqueueBytes(
    Uint8List bytes, {
    required UploadKind kind,
    required String fileName,
  }) {
    final task = UploadTask(
      id: _genId(),
      kind: kind,
      fileName: fileName,
      bytes: bytes,
    );
    _register(task);
    return task;
  }

  void retry(String taskId) {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('task not found'),
    );
    if (task.state == UploadState.uploading) return;
    task.error = null;
    task._setProgress(0);
    task._setState(UploadState.pending);
    _queue.add(task);
    _pump();
  }

  void cancel(String taskId) {
    _queue.removeWhere((t) => t.id == taskId);
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('task not found'),
    );
    if (task.state == UploadState.uploading) {
      // 간단화: 현재 http.MultipartRequest는 취소 API 없음. 상태만 표시.
    }
    task._setState(UploadState.cancelled);
  }

  // 내부
  void _register(UploadTask task) {
    print(
      '[Upload] register id=${task.id} name=${task.fileName} kind=${task.kind} file=${task.file?.path} bytes=${task.bytes?.length}',
    );
    _tasks.add(task);
    _queue.add(task);
    notifyListeners();
    _pump();
  }

  void _pump() {
    print('[Upload] pump inflight=$_inflight queue=${_queue.length}');
    while (_inflight < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      print('[Upload] dequeue id=${task.id}');
      _upload(task);
    }
  }

  Future<void> _upload(UploadTask task) async {
    _inflight++;
    task.attempt++;
    task._setState(UploadState.uploading);
    try {
      final started = DateTime.now();
      print('[Upload] start id=${task.id} attempt=${task.attempt}');
      final Map<String, dynamic> result =
          task.kind == UploadKind.profile
              ? await _uploadProfileImage(task)
              : await _uploadSingle(task);
      task.url = result['accessUrl'] as String?;
      task.imageId = result['imageId']?.toString();
      task._setProgress(1);
      task._setState(UploadState.success);
      print(
        '[Upload] success id=${task.id} url=${task.url} imageId=${task.imageId} durMs=${DateTime.now().difference(started).inMilliseconds}',
      );
    } catch (e) {
      task.error = e;
      print('[Upload] error id=${task.id} error=$e');
      if (task.attempt < 3) {
        // 지수 백오프 재시도
        final delayMs = 400 * (1 << (task.attempt - 1));
        print('[Upload] retry id=${task.id} in ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
        _queue.add(task);
      } else {
        task._setState(UploadState.failed);
        print('[Upload] failed id=${task.id}');
      }
    } finally {
      _inflight--;
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  Future<Map<String, dynamic>> _uploadProfileImage(UploadTask task) async {
    final uri = Uri.parse('$_baseUrl/api/profile/image/upload');
    final token = await AuthService().getToken();
    print('[UploadService] token: $token');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token';

    final bytes = task.bytes ?? await task.file!.readAsBytes();
    final mediaType = _createMediaType(task.fileName);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: task.fileName,
        contentType: mediaType,
      ),
    );

    print(
      '[Upload] POST ${uri.toString()} size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );
    final streamResp = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final body = await streamResp.stream.bytesToString();
    if (streamResp.statusCode == 200) {
      print('[Upload] 200 body=${body}');
      final Map<String, dynamic> decoded =
          json.decode(body) as Map<String, dynamic>;
      String? imageId = (decoded['imageId'] ?? decoded['id'])?.toString();
      String? accessUrl =
          decoded['accessUrl']?.toString() ?? decoded['url']?.toString();
      if ((imageId == null || accessUrl == null) &&
          decoded['data'] is Map<String, dynamic>) {
        final data = decoded['data'] as Map<String, dynamic>;
        imageId ??= (data['imageId'] ?? data['id'])?.toString();
        accessUrl ??= data['accessUrl']?.toString() ?? data['url']?.toString();
      }
      if ((accessUrl == null || accessUrl.isEmpty) &&
          imageId != null &&
          imageId.isNotEmpty) {
        try {
          accessUrl = await _getAccessUrlByImageId(imageId);
        } catch (e) {
          print('[Upload] failed to fetch access url by imageId=$imageId: $e');
        }
      }
      return {...decoded, 'imageId': imageId, 'accessUrl': accessUrl};
    } else {
      print('[Upload] http ${streamResp.statusCode} body=${body}');
      throw HttpException('upload failed ${streamResp.statusCode}: $body');
    }
  }

  Future<Map<String, dynamic>> _uploadSingle(UploadTask task) async {
    final uri = Uri.parse('$_baseUrl/api/images/upload');
    final token = await AuthService().getToken();
    print('[UploadService] token: $token');
    final request =
        http.MultipartRequest('POST', uri)
          ..fields['uid'] = 'user1234'
          ..headers['Authorization'] = 'Bearer $token'; // 임시 토큰

    final bytes = task.bytes ?? await task.file!.readAsBytes();
    final mediaType = _createMediaType(task.fileName);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: task.fileName,
        contentType: mediaType,
      ),
    );

    print(
      '[Upload] POST ${uri.toString()} size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );
    final streamResp = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final body = await streamResp.stream.bytesToString();
    if (streamResp.statusCode == 200) {
      print('[Upload] 200 body=${body}');
      return json.decode(body) as Map<String, dynamic>;
    } else {
      print('[Upload] http ${streamResp.statusCode} body=${body}');
      throw HttpException('upload failed ${streamResp.statusCode}: $body');
    }
  }

  MediaType _createMediaType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
      case 'heif':
        return MediaType('image', 'heic');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  // enqueueFilesInBatches: 현재 사용처 없음(단순화 차원에서 제거)

  /// 서버 다중 업로드 API를 활용해 파일을 배치 단위로 한 요청으로 업로드합니다.
  /// - 서버 응답이 입력 순서를 보존한다는 가정 하에 index 기반으로 매핑합니다.
  /// - 각 Task의 state/url을 한 번에 갱신합니다.
  /// - 기존 단건 파이프라인과 별도로 동작합니다(필요 시 혼용 가능).
  Future<List<UploadTask>> uploadFilesViaServerBatches(
    List<File> files, {
    required UploadKind kind,
    int batchSize = 10,
    Duration interBatchDelay = const Duration(milliseconds: 500),
  }) async {
    print('[UploadBatch] files=${files.length} batchSize=$batchSize');
    final List<UploadTask> all =
        files
            .map(
              (f) => UploadTask(
                id: _genId(),
                kind: kind,
                fileName: f.path.split('/').last,
                file: f,
              ),
            )
            .toList();
    _tasks.addAll(all);
    notifyListeners();

    for (int i = 0; i < all.length; i += batchSize) {
      final end = (i + batchSize < all.length) ? i + batchSize : all.length;
      final chunk = all.sublist(i, end);
      print('[UploadBatch] chunk ${i ~/ batchSize + 1} size=${chunk.length}');
      for (final t in chunk) {
        t._setState(UploadState.uploading);
        t._setProgress(0.1);
      }
      try {
        final results = await _uploadMultiple(chunk);
        for (int k = 0; k < chunk.length; k++) {
          final t = chunk[k];
          if (k < results.length) {
            final r = results[k];
            t.url = r['accessUrl'] as String?;
            t.imageId = r['imageId']?.toString();
            t._setProgress(1);
            t._setState(UploadState.success);
            print('[UploadBatch] success id=${t.id} url=${t.url}');
          } else {
            t.error = StateError('응답 매핑 누락');
            t._setState(UploadState.failed);
            print('[UploadBatch] map-miss id=${t.id}');
          }
        }
      } catch (e) {
        print('[UploadBatch] error $e');
        for (final t in chunk) {
          t.error = e;
          t._setState(UploadState.failed);
        }
      }
      if (end < all.length) {
        await Future.delayed(interBatchDelay);
      }
      if (!_disposed) notifyListeners();
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> _uploadMultiple(
    List<UploadTask> tasks,
  ) async {
    final uri = Uri.parse('$_baseUrl/api/images/upload-multiple');
    final token = await AuthService().getToken();
    print('[UploadService] batch upload token: $token');
    final request =
        http.MultipartRequest('POST', uri)
          ..fields['uid'] = 'user1234'
          ..headers['Authorization'] = 'Bearer $token';
    for (final t in tasks) {
      final bytes = t.bytes ?? await t.file!.readAsBytes();
      final mediaType = _createMediaType(t.fileName);
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          bytes,
          filename: t.fileName,
          contentType: mediaType,
        ),
      );
    }
    print('[UploadBatch] POST ${uri.toString()} files=${tasks.length}');
    final resp = await request.send().timeout(const Duration(seconds: 60));
    final body = await resp.stream.bytesToString();
    if (resp.statusCode == 200) {
      print('[UploadBatch] 200 body=${body}');
      final decoded = json.decode(body);
      return List<Map<String, dynamic>>.from(decoded as List);
    }
    print('[UploadBatch] http ${resp.statusCode} body=${body}');
    throw HttpException('batch upload failed ${resp.statusCode}: $body');
  }

  Future<String?> _getAccessUrlByImageId(String imageId) async {
    final uri = Uri.parse('$_baseUrl/api/images/$imageId/url');
    final token = await AuthService().getToken();
    final resp = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final decoded = json.decode(resp.body);
      if (decoded is String) return decoded;
      if (decoded is Map<String, dynamic>) {
        return decoded['url']?.toString();
      }
    }
    throw HttpException(
      'failed to get access url for imageId=$imageId (${resp.statusCode})',
    );
  }
}
