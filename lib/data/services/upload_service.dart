import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:doppy/editor/service/node_component_service.dart';

enum UploadState { pending, uploading, success, failed, cancelled }

enum UploadKind { editorImage, thumbnail, profile, video }

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

  final AuthService _authService = AuthService();

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
              : task.kind == UploadKind.video
              ? await _uploadVideo(task)
              : await _uploadSingle(task);
      task.url = result['accessUrl'] as String?;
      task.imageId = result['imageId']?.toString();
      task._setProgress(1);
      task._setState(UploadState.success);
      // URL ↔ imageId 매핑 등록: 최종 페이로드에서 문서에 존재하는 URL만 매핑 조회
      if (task.kind == UploadKind.editorImage &&
          (task.url ?? '').isNotEmpty &&
          (task.imageId ?? '').isNotEmpty) {
        try {
          NodeComponentService().registerImageUrlId(task.url!, task.imageId!);
        } catch (_) {}
      }
      print(
        '[Upload] success id=${task.id} url=${task.url} imageId=${task.imageId} durMs=${DateTime.now().difference(started).inMilliseconds}',
      );
    } catch (e) {
      task.error = e;
      print('[Upload] error id=${task.id} error=$e');

      // 400/500 에러 감지: 즉시 중단 (재시도 안 함)
      bool isClientOrServerError = false;
      if (e is HttpException) {
        final msg = e.message.toLowerCase();
        // "upload failed 400:" 또는 "upload failed 500:" 패턴 감지
        if (msg.contains('400') ||
            msg.contains('401') ||
            msg.contains('403') ||
            msg.contains('404') ||
            msg.contains('500') ||
            msg.contains('502') ||
            msg.contains('503')) {
          isClientOrServerError = true;
          print('[Upload] 400/500 에러 감지 - 재시도 중단: $e');
        }
      }

      if (isClientOrServerError || task.attempt >= 3) {
        task._setState(UploadState.failed);
        print('[Upload] failed id=${task.id}');
      } else {
        // 네트워크 오류 등의 경우만 재시도
        final delayMs = 400 * (1 << (task.attempt - 1));
        print('[Upload] retry id=${task.id} in ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
        _queue.add(task);
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
    return await _requestWithTokenRefresh(() async {
      final uri = Uri.parse('$_baseUrl/api/profile/image/upload');
      final token = await _authService.getToken();
      print('[UploadService] token: $token');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token';

      final bytes = await _prepareImageBytes(task);
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
            decoded['accessUrl']?.toString() ??
            decoded['url']?.toString() ??
            decoded['profileImageUrl']?.toString();
        if ((imageId == null || accessUrl == null) &&
            decoded['data'] is Map<String, dynamic>) {
          final data = decoded['data'] as Map<String, dynamic>;
          imageId ??= (data['imageId'] ?? data['id'])?.toString();
          accessUrl ??=
              data['accessUrl']?.toString() ??
              data['url']?.toString() ??
              data['profileImageUrl']?.toString();
        }
        if ((accessUrl == null || accessUrl.isEmpty) &&
            imageId != null &&
            imageId.isNotEmpty) {
          try {
            accessUrl = await _getAccessUrlByImageId(imageId);
          } catch (e) {
            print(
              '[Upload] failed to fetch access url by imageId=$imageId: $e',
            );
          }
        }
        return {...decoded, 'imageId': imageId, 'accessUrl': accessUrl};
      } else {
        print('[Upload] http ${streamResp.statusCode} body=${body}');
        throw HttpException('upload failed ${streamResp.statusCode}: $body');
      }
    });
  }

  Future<Map<String, dynamic>> _uploadSingle(UploadTask task) async {
    final username = await _authService.getUsername();
    if (username == null) {
      throw HttpException('username is null');
    }
    return await _requestWithTokenRefresh(() async {
      final uri = Uri.parse('$_baseUrl/api/images/upload');
      final token = await _authService.getToken();
      print('[UploadService] token: $token');
      final request =
          http.MultipartRequest('POST', uri)
            ..fields['uid'] = username
            ..headers['Authorization'] = 'Bearer $token'; // 임시 토큰

      final bytes = await _prepareImageBytes(task);
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
        const Duration(seconds: 45),
      );
      final body = await streamResp.stream.bytesToString();
      if (streamResp.statusCode == 200) {
        print('[Upload] 200 body=${body}');
        return json.decode(body) as Map<String, dynamic>;
      } else {
        print('[Upload] http ${streamResp.statusCode} body=${body}');
        throw HttpException('upload failed ${streamResp.statusCode}: $body');
      }
    });
  }

  Future<Map<String, dynamic>> _uploadVideo(UploadTask task) async {
    return await _requestWithTokenRefresh(() async {
      final username = await _authService.getUsername();
      if (username == null) {
        throw HttpException('username is null');
      }
      final uri = Uri.parse('$_baseUrl/api/videos/upload');
      final token = await _authService.getToken();
      final request =
          http.MultipartRequest('POST', uri)
            ..fields['uid'] = username
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
        '[UploadVideo] POST ${uri.toString()} size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
      );
      final streamResp = await request.send().timeout(
        const Duration(minutes: 2),
      );
      final body = await streamResp.stream.bytesToString();
      if (streamResp.statusCode == 200) {
        print('[UploadVideo] 200 body=${body}');
        final Map<String, dynamic> decoded =
            json.decode(body) as Map<String, dynamic>;
        // 표준 필드 정규화
        final String? videoId =
            (decoded['videoId'] ?? decoded['id'])?.toString();
        final String? accessUrl =
            decoded['accessUrl']?.toString() ?? decoded['url']?.toString();
        return {...decoded, 'imageId': videoId, 'accessUrl': accessUrl};
      } else {
        print('[UploadVideo] http ${streamResp.statusCode} body=${body}');
        throw HttpException(
          'video upload failed ${streamResp.statusCode}: $body',
        );
      }
    });
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
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'm4v':
        return MediaType('video', 'x-m4v');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  // 이미지 리사이즈/압축: 긴 변 1440px, JPEG 82 (사진 품질용)
  Future<Uint8List> _prepareImageBytes(UploadTask task) async {
    try {
      final raw = task.bytes ?? await task.file!.readAsBytes();
      final ext = task.fileName.split('.').last.toLowerCase();
      final isImage = const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic',
        'heif',
      ].contains(ext);
      if (!isImage) return raw;
      // 별도 isolate에서 리사이즈 → 즉시 로컬 미리보기 가능
      final out = await compute(_resizeImageWorker, {
        'bytes': raw,
        'maxSide': 1440,
        'quality': 82,
      });
      return out;
    } catch (_) {
      return task.bytes ?? await task.file!.readAsBytes();
    }
  }

  // compute용 워커(탑레벨)
  static Future<Uint8List> _resizeImageWorker(Map<String, Object?> args) async {
    final bytes = args['bytes'] as Uint8List;
    final int maxSide = (args['maxSide'] as int?) ?? 1440;
    final int quality = (args['quality'] as int?) ?? 82;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final w = decoded.width;
      final h = decoded.height;
      if (w <= maxSide && h <= maxSide) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
      }
      final scale = w >= h ? maxSide / w : maxSide / h;
      final newW = (w * scale).round();
      final newH = (h * scale).round();
      final resized = img.copyResize(
        decoded,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.average,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    } catch (_) {
      return bytes;
    }
  }

  // 이미지 리사이즈/압축: 긴 변 1440px, JPEG 82 (사진 품질용)
  // (중복 정의 제거됨)

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
            // URL ↔ imageId 매핑 등록 (배치 업로드에서도 usedImageIds 수집 가능하도록)
            if (t.kind == UploadKind.editorImage &&
                (t.url ?? '').isNotEmpty &&
                (t.imageId ?? '').isNotEmpty) {
              try {
                NodeComponentService().registerImageUrlId(t.url!, t.imageId!);
              } catch (_) {}
            }
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
    final username = await _authService.getUsername();
    if (username == null) {
      throw HttpException('username is null');
    }
    return await _requestWithTokenRefresh(() async {
      final uri = Uri.parse('$_baseUrl/api/images/upload-multiple');
      final token = await _authService.getToken();
      print('[UploadService] batch upload token: $token');
      final request =
          http.MultipartRequest('POST', uri)
            ..fields['uid'] = username
            ..headers['Authorization'] = 'Bearer $token';
      for (final t in tasks) {
        final bytes = await _prepareImageBytes(t);
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
    });
  }

  Future<String?> _getAccessUrlByImageId(String imageId) async {
    return await _requestWithTokenRefresh(() async {
      final uri = Uri.parse('$_baseUrl/api/images/$imageId/url');
      final token = await _authService.getToken();
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
    });
  }

  Future<T> _requestWithTokenRefresh<T>(Future<T> Function() request) async {
    try {
      // 첫 번째 시도
      return await request();
    } catch (e) {
      // 401 또는 JWT 만료 관련 오류인지 확인
      if (e is HttpException) {
        final errorMessage = e.toString();
        if (errorMessage.contains('401') ||
            errorMessage.contains('ExpiredJwtException') ||
            errorMessage.contains('JWT expired')) {
          debugPrint('[UploadService] Token expired, attempting refresh...');

          try {
            // 토큰 갱신 시도
            await _authService.refreshToken();
            debugPrint('[UploadService] Token refreshed successfully');

            // 갱신된 토큰으로 재시도
            return await request();
          } catch (refreshError) {
            debugPrint('[UploadService] Token refresh failed: $refreshError');
            rethrow;
          }
        }
      }
      rethrow;
    }
  }
}
