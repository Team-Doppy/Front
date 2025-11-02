import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:convert';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;

enum UploadState { pending, uploading, success, failed, cancelled }

enum UploadKind { editorImage, thumbnail, profile, video }

class UploadTask extends ChangeNotifier {
  final String id;
  final UploadKind kind;
  final File? file;
  final Uint8List? bytes;
  final String fileName;

  /// 노드/플레이스홀더 등 상위 객체를 식별하기 위한 참조 ID (선택)
  final String? refId;

  /// 네트워크 요청 취소용 토큰
  final CancelToken cancelToken = CancelToken();
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
    this.refId,
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
  // Singleton
  static final UploadService _instance = UploadService._internal();
  factory UploadService() => _instance;
  UploadService._internal();
  final List<UploadTask> _tasks = [];
  final Queue<UploadTask> _queue = Queue<UploadTask>();
  int _inflight = 0;
  int maxConcurrent = 3;
  bool _disposed = false;

  final AuthService _authService = AuthService();
  final Dio _dio = BaseApiService().dio;

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  /// 업로드 진행 중(pending|uploading) 작업이 있는지 여부
  /// kinds를 지정하지 않으면 에디터 관련(kind: editorImage, video, thumbnail)을 기본으로 검사
  bool hasActiveUploads({Set<UploadKind>? kinds}) {
    final Set<UploadKind> targetKinds =
        kinds ??
        {UploadKind.editorImage, UploadKind.video, UploadKind.thumbnail};
    return _tasks.any(
      (t) =>
          targetKinds.contains(t.kind) &&
          (t.state == UploadState.pending || t.state == UploadState.uploading),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  UploadTask enqueueFile(
    File file, {
    required UploadKind kind,
    String? overrideName,
    String? refId,
  }) {
    final String name = overrideName ?? file.path.split('/').last;
    final task = UploadTask(
      id: _genId(),
      kind: kind,
      fileName: name,
      file: file,
      refId: refId,
    );
    _register(task);
    return task;
  }

  UploadTask enqueueBytes(
    Uint8List bytes, {
    required UploadKind kind,
    required String fileName,
    String? refId,
  }) {
    final task = UploadTask(
      id: _genId(),
      kind: kind,
      fileName: fileName,
      bytes: bytes,
      refId: refId,
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
      // 실제 네트워크 요청 취소 시도
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel('cancelled by user');
      }
    }
    task._setState(UploadState.cancelled);
  }

  /// refId(예: 노드ID)로 모든 태스크 취소
  void cancelByRef(String refId) {
    // 큐에서 제거
    _queue.removeWhere((t) => t.refId == refId);
    for (final task in _tasks.where((t) => t.refId == refId)) {
      if (task.state == UploadState.uploading &&
          !task.cancelToken.isCancelled) {
        task.cancelToken.cancel('cancelled by refId');
      }
      task._setState(UploadState.cancelled);
    }
    notifyListeners();
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
      // 업로드 시작 전 토큰 유효성 검사 및 갱신
      print('[Upload] Validating token before upload id=${task.id}');
      final isValid = await _authService.validateAndRefreshToken();
      if (!isValid) {
        print('[Upload] Token expired or invalid, attempting refresh...');
        final refreshed = await _refreshToken();
        if (!refreshed) {
          print('[Upload] Token refresh failed, upload aborted');
          task.error = Exception('Token refresh failed');
          task._setState(UploadState.failed);
          return;
        }
        print('[Upload] Token refreshed successfully');
      } else {
        print('[Upload] Token is valid');
      }

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
      // 매핑 사용 제거됨
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
    final bytes = await _prepareImageBytes(task);
    final mediaType = _createMediaType(task.fileName);

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: task.fileName,
        contentType: mediaType,
      ),
    });

    print(
      '[Upload] POST /api/profile/image/upload size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );

    try {
      final response = await _dio.post(
        '/api/profile/image/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 200) {
        print('[Upload] 200 body=${response.data}');
        final Map<String, dynamic> decoded = response.data;
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
        print('[Upload] http ${response.statusCode} body=${response.data}');
        throw HttpException(
          'upload failed ${response.statusCode}: ${response.data}',
        );
      }
    } catch (e) {
      if (e is DioException) {
        print(
          '[Upload] DioException ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'upload failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _uploadSingle(UploadTask task) async {
    final username = await _authService.getUsername();
    if (username == null) {
      throw HttpException('username is null');
    }

    final bytes = await _prepareImageBytes(task);
    final mediaType = _createMediaType(task.fileName);

    final formData = FormData.fromMap({
      'uid': username,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: task.fileName,
        contentType: mediaType,
      ),
    });

    print(
      '[Upload] POST /api/images/upload size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );

    try {
      final response = await _dio.post(
        '/api/images/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45),
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 200) {
        print('[Upload] 200 body=${response.data}');
        return response.data as Map<String, dynamic>;
      } else {
        print('[Upload] http ${response.statusCode} body=${response.data}');
        throw HttpException(
          'upload failed ${response.statusCode}: ${response.data}',
        );
      }
    } catch (e) {
      if (e is DioException) {
        print(
          '[Upload] DioException ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'upload failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _uploadVideo(UploadTask task) async {
    final username = await _authService.getUsername();
    if (username == null) {
      throw HttpException('username is null');
    }

    final bytes = task.bytes ?? await task.file!.readAsBytes();
    final mediaType = _createMediaType(task.fileName);

    final formData = FormData.fromMap({
      'uid': username,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: task.fileName,
        contentType: mediaType,
      ),
    });

    print(
      '[UploadVideo] POST /api/videos/upload size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );

    try {
      final response = await _dio.post(
        '/api/videos/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 200) {
        print('[UploadVideo] 200 body=${response.data}');
        final Map<String, dynamic> decoded = response.data;
        // 표준 필드 정규화
        final String? videoId =
            (decoded['videoId'] ?? decoded['id'])?.toString();
        final String? accessUrl =
            decoded['accessUrl']?.toString() ?? decoded['url']?.toString();
        print('[UploadVideo] 정규화된 필드: videoId=$videoId, accessUrl=$accessUrl');
        return {...decoded, 'imageId': videoId, 'accessUrl': accessUrl};
      } else {
        print(
          '[UploadVideo] http ${response.statusCode} body=${response.data}',
        );
        throw HttpException(
          'video upload failed ${response.statusCode}: ${response.data}',
        );
      }
    } catch (e) {
      if (e is DioException) {
        print(
          '[UploadVideo] DioException ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'video upload failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
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
            // 매핑 사용 제거됨
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

    final formData = FormData();
    formData.fields.add(MapEntry('uid', username));

    for (final t in tasks) {
      final bytes = await _prepareImageBytes(t);
      final mediaType = _createMediaType(t.fileName);
      formData.files.add(
        MapEntry(
          'files',
          MultipartFile.fromBytes(
            bytes,
            filename: t.fileName,
            contentType: mediaType,
          ),
        ),
      );
    }

    print(
      '[UploadBatch] POST /api/images/upload-multiple files=${tasks.length}',
    );

    try {
      final response = await _dio.post(
        '/api/images/upload-multiple',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        print('[UploadBatch] 200 body=${response.data}');
        return List<Map<String, dynamic>>.from(response.data as List);
      }
      print('[UploadBatch] http ${response.statusCode} body=${response.data}');
      throw HttpException(
        'batch upload failed ${response.statusCode}: ${response.data}',
      );
    } catch (e) {
      if (e is DioException) {
        print(
          '[UploadBatch] DioException ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'batch upload failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  Future<String?> _getAccessUrlByImageId(String imageId) async {
    try {
      final response = await _dio.get(
        '/api/images/$imageId/url',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final decoded = response.data;
        if (decoded is String) return decoded;
        if (decoded is Map<String, dynamic>) {
          return decoded['url']?.toString();
        }
      }
      throw HttpException(
        'failed to get access url for imageId=$imageId (${response.statusCode})',
      );
    } catch (e) {
      if (e is DioException) {
        throw HttpException(
          'failed to get access url for imageId=$imageId (${e.response?.statusCode})',
        );
      }
      rethrow;
    }
  }

  /// 토큰 갱신
  Future<bool> _refreshToken() async {
    final refreshToken = await _authService.getRefreshToken();
    if (refreshToken == null) {
      print('❌ [UploadService] 리프레시 토큰이 없습니다');
      return false;
    }

    try {
      final url = Uri.parse('https://api.doppy.me/api/auth/refresh');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final newToken = responseData['token'];
        final newRefreshToken = responseData['refreshToken'];

        // AuthService를 통해 새로운 토큰들 저장
        await _authService.saveToken(newToken);
        await _authService.saveRefreshToken(newRefreshToken);

        print('✅ [UploadService] 토큰 갱신 성공');
        return true;
      } else {
        print('❌ [UploadService] 토큰 갱신 실패: ${response.statusCode}');
        print('❌ [UploadService] 응답 내용: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ [UploadService] 토큰 갱신 오류: $e');
      return false;
    }
  }
}
