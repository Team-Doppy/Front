import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/r2_upload_service.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

enum UploadState { pending, uploading, success, failed, cancelled }

enum UploadKind { editorImage, thumbnail, profile, video, group }

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
  int maxConcurrent = 5; // 🎯 동시 업로드 수를 3에서 5로 증가
  bool _disposed = false;

  /// 에디터 관련 압축 취소 토큰 (에디터 종료 시 취소용)
  final Map<String, CancellationToken> _editorCompressionTokens = {};

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
    debugPrint(
      '[Upload] register id=${task.id} name=${task.fileName} kind=${task.kind} file=${task.file?.path} bytes=${task.bytes?.length}',
    );
    _tasks.add(task);
    _queue.add(task);
    notifyListeners();
    _pump();
  }

  // ===== 리스너 선등록 지원: Task 생성만 하고 시작은 나중에 =====
  UploadTask createTaskForFile(
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
    debugPrint('[Upload] createTask only id=${task.id} name=${task.fileName}');
    _tasks.add(task);
    notifyListeners();
    return task;
  }

  void startTask(UploadTask task) {
    if (!_tasks.contains(task)) {
      _tasks.add(task);
    }
    if (!_queue.contains(task) && task.state == UploadState.pending) {
      _queue.add(task);
    }
    notifyListeners();
    _pump();
  }

  void _pump() {
    debugPrint('[Upload] pump inflight=$_inflight queue=${_queue.length}');

    // 순차 처리: 큐에서 하나씩 꺼내서 처리
    while (_inflight < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      debugPrint('[Upload] dequeue id=${task.id}');
      _upload(task);
    }
  }

  Future<void> _upload(UploadTask task) async {
    _inflight++;
    task.attempt++;
    task._setState(UploadState.uploading);
    try {
      // 업로드 시작 전 토큰 유효성 검사 및 갱신
      debugPrint('[Upload] Validating token before upload id=${task.id}');
      final isValid = await _authService.validateAndRefreshToken();
      if (!isValid) {
        debugPrint('[Upload] Token expired or invalid, attempting refresh...');
        final refreshed = await _refreshToken();
        if (!refreshed) {
          debugPrint('[Upload] Token refresh failed, upload aborted');
          task.error = Exception('Token refresh failed');
          task._setState(UploadState.failed);
          return;
        }
        debugPrint('[Upload] Token refreshed successfully');
      } else {
        debugPrint('[Upload] Token is valid');
      }

      debugPrint('[Upload] start id=${task.id} attempt=${task.attempt}');

      // 🎯 프로필 이미지는 서버를 거치는 기존 방식 사용
      Map<String, dynamic> result;
      if (task.kind == UploadKind.profile) {
        // 프로필 이미지는 서버를 거치는 방식만 사용
        debugPrint('[Upload] 프로필 이미지 업로드: 서버를 거치는 기존 방식 사용');
        result = await _uploadProfileImage(task);
      } else {
        // 다른 종류는 R2 직접 업로드 사용
        try {
          result = await _uploadViaR2(task);
        } catch (e) {
          // R2 업로드 실패 시 기존 방식으로 폴백
          debugPrint('[Upload] R2 업로드 실패, 기존 방식으로 폴백: $e');
          result =
              task.kind == UploadKind.video
                  ? await _uploadVideo(task)
                  : await _uploadSingle(task); // group도 _uploadSingle 사용
        }
      }

      task.url = result['accessUrl'] as String?;
      task._setProgress(1);
      task._setState(UploadState.success);
    } catch (e) {
      // 사용자가 취소한 경우: 재시도/실패로 처리하지 않고 즉시 취소로 마무리
      if (e is DioException && e.type == DioExceptionType.cancel) {
        debugPrint('[Upload] cancelled by user/ref id=${task.id}');
        task._setState(UploadState.cancelled);
        return;
      }
      if (task.cancelToken.isCancelled) {
        debugPrint('[Upload] cancelToken marked cancelled id=${task.id}');
        task._setState(UploadState.cancelled);
        return;
      }
      task.error = e;
      debugPrint('[Upload] error id=${task.id} error=$e');

      // 재시도 금지: 어떤 오류든 즉시 실패 처리
      task._setState(UploadState.failed);
      debugPrint('[Upload] failed (no-retry) id=${task.id}');
    } finally {
      _inflight--;
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  /// 🎯 R2 직접 업로드 (단일 파일 - 프로필 등 개별 처리용)
  Future<Map<String, dynamic>> _uploadViaR2(UploadTask task) async {
    try {
      final r2Service = R2UploadService();
      final file = task.file;

      if (file == null) {
        throw Exception('파일이 없습니다');
      }

      // 진행률 콜백 설정
      task._setProgress(0.0);
      // task._setState(UploadState.uploading)는 _upload()에서 이미 설정되므로 중복 호출 제거

      debugPrint(
        '[Upload] R2 직접 업로드 시작: ${task.fileName} (kind: ${task.kind})',
      );

      // 🎯 댓글 이미지인 경우 chat/username 경로 사용
      String? pathPrefix;
      if (task.kind == UploadKind.editorImage &&
          task.fileName.startsWith('chat/')) {
        // 파일명에서 경로 추출 (chat/username/timestamp_filename.jpg)
        final pathParts = task.fileName.split('/');
        if (pathParts.length >= 2) {
          pathPrefix = '${pathParts[0]}/${pathParts[1]}'; // chat/username
        }
      }

      // R2 직접 업로드 실행
      final result = await r2Service.uploadMediaFiles(
        [file],
        onProgress: (message, progress) {
          task._setProgress(progress);
        },
        pathPrefix: pathPrefix, // 🎯 경로 prefix 전달
      );

      if (!result.success ||
          (result.imageUrls.isEmpty && result.videoUrls.isEmpty)) {
        throw Exception(result.error ?? 'R2 업로드 실패');
      }

      // 성공한 URL 가져오기
      final url =
          result.imageUrls.isNotEmpty
              ? result.imageUrls.first
              : result.videoUrls.first;

      debugPrint('[Upload] R2 업로드 성공: $url');

      // 응답 형식 맞추기 (기존 UploadService와 호환)
      return {'accessUrl': url, 'url': url};
    } catch (e) {
      debugPrint('[Upload] R2 직접 업로드 실패: $e');
      rethrow;
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

    debugPrint(
      '[Upload] POST /api/profile/image/upload size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );

    try {
      final response = await _dio.post(
        '/api/profile/image/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 200) {
        debugPrint('[Upload] 200 body=${response.data}');
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
            debugPrint(
              '[Upload] failed to fetch access url by imageId=$imageId: $e',
            );
          }
        }
        return {...decoded, 'imageId': imageId, 'accessUrl': accessUrl};
      } else {
        debugPrint(
          '[Upload] http ${response.statusCode} body=${response.data}',
        );
        throw HttpException(
          'upload failed ${response.statusCode}: ${response.data}',
        );
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.cancel) rethrow;
        debugPrint(
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

    debugPrint(
      '[Upload] POST /api/images/upload size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );

    try {
      final response = await _dio.post(
        '/api/images/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 200) {
        debugPrint('[Upload] 200 body=${response.data}');
        return response.data as Map<String, dynamic>;
      } else {
        debugPrint(
          '[Upload] http ${response.statusCode} body=${response.data}',
        );
        throw HttpException(
          'upload failed ${response.statusCode}: ${response.data}',
        );
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.cancel) rethrow;
        debugPrint(
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

    debugPrint(
      '[UploadVideo] POST /api/videos/upload size=${bytes.length} type=${mediaType.type}/${mediaType.subtype}',
    );

    try {
      final response = await _dio.post(
        '/api/videos/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 1),
          receiveTimeout: const Duration(minutes: 1),
        ),
        cancelToken: task.cancelToken,
      );

      if (response.statusCode == 200) {
        debugPrint('[UploadVideo] 200 body=${response.data}');
        final Map<String, dynamic> decoded = response.data;
        // 표준 필드 정규화
        final String? videoId =
            (decoded['videoId'] ?? decoded['id'])?.toString();
        final String? accessUrl =
            decoded['accessUrl']?.toString() ?? decoded['url']?.toString();
        debugPrint(
          '[UploadVideo] 정규화된 필드: videoId=$videoId, accessUrl=$accessUrl',
        );
        return {...decoded, 'imageId': videoId, 'accessUrl': accessUrl};
      } else {
        debugPrint(
          '[UploadVideo] http ${response.statusCode} body=${response.data}',
        );
        throw HttpException(
          'video upload failed ${response.statusCode}: ${response.data}',
        );
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw HttpException('video upload failed timeout');
      }
      if (e is DioException) {
        if (e.type == DioExceptionType.cancel) rethrow;
        debugPrint(
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
        'fileName': task.fileName, // 🎯 파일명 전달 (PNG 감지용)
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
    final String? fileName = args['fileName'] as String?;
    final bool isPng = fileName?.toLowerCase().endsWith('.png') ?? false;

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final w = decoded.width;
      final h = decoded.height;

      // 🎯 PNG 드로잉은 그대로 업로드 (투명도 유지)
      if (isPng && w <= maxSide && h <= maxSide) {
        debugPrint('[Upload] PNG 드로잉 원본 유지: ${w}x$h');
        return bytes; // 원본 그대로
      }

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

      // 🎯 PNG는 PNG로, 나머지는 JPG로 인코딩
      if (isPng) {
        return Uint8List.fromList(img.encodePng(resized, level: 6));
      } else {
        return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      }
    } catch (_) {
      return bytes;
    }
  }

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
    debugPrint('[UploadBatch] files=${files.length} batchSize=$batchSize');
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
      debugPrint(
        '[UploadBatch] chunk ${i ~/ batchSize + 1} size=${chunk.length}',
      );
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
            // 응답 정규화: accessUrl/url/data.* 대응
            String? accessUrl =
                r['accessUrl']?.toString() ?? r['url']?.toString();
            if ((accessUrl == null || accessUrl.isEmpty) &&
                r['data'] is Map<String, dynamic>) {
              final data = r['data'] as Map<String, dynamic>;
              accessUrl =
                  data['accessUrl']?.toString() ??
                  data['url']?.toString() ??
                  data['profileImageUrl']?.toString();
            }
            t.url = accessUrl;
            t._setProgress(1);
            t._setState(UploadState.success);
            debugPrint('[UploadBatch] success id=${t.id} url=${t.url}');
          } else {
            t.error = StateError('응답 매핑 누락');
            t._setState(UploadState.failed);
            debugPrint('[UploadBatch] map-miss id=${t.id}');
          }
        }
      } catch (e) {
        debugPrint('[UploadBatch] error $e');
        final bool isCancelled =
            e is DioException && e.type == DioExceptionType.cancel;
        for (final t in chunk) {
          t.error = e;
          t._setState(isCancelled ? UploadState.cancelled : UploadState.failed);
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

    debugPrint(
      '[UploadBatch] POST /api/images/upload-multiple files=${tasks.length}',
    );

    try {
      final response = await _dio.post(
        '/api/images/upload-multiple',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        debugPrint('[UploadBatch] 200 body=${response.data}');
        return List<Map<String, dynamic>>.from(response.data as List);
      }
      debugPrint(
        '[UploadBatch] http ${response.statusCode} body=${response.data}',
      );
      throw HttpException(
        'batch upload failed ${response.statusCode}: ${response.data}',
      );
    } catch (e) {
      if (e is DioException) {
        debugPrint(
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

  /// 토큰 갱신 (BaseApiService 사용 - 하지만 토큰 갱신 엔드포인트는 인증 불필요)
  /// 🎯 참고: validateAndRefreshToken()이 이미 토큰 갱신을 시도하므로,
  /// 이 메서드는 validateAndRefreshToken()이 실패했을 때만 호출됩니다.
  Future<bool> _refreshToken() async {
    final refreshToken = await _authService.getRefreshToken();
    if (refreshToken == null) {
      debugPrint('❌ [UploadService] 리프레시 토큰이 없습니다');
      return false;
    }

    try {
      // 🎯 BaseApiService의 dio를 사용 (토큰 갱신 엔드포인트는 인증 불필요하므로 인터셉터가 건너뜀)
      final response = await _dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>;
        final newToken = responseData['token'];
        final newRefreshToken = responseData['refreshToken'];

        // AuthService를 통해 새로운 토큰들 저장
        await _authService.saveToken(newToken);
        await _authService.saveRefreshToken(newRefreshToken);

        debugPrint('✅ [UploadService] 토큰 갱신 성공');
        return true;
      } else {
        debugPrint('❌ [UploadService] 토큰 갱신 실패: ${response.statusCode}');
        debugPrint('❌ [UploadService] 응답 내용: ${response.data}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [UploadService] 토큰 갱신 오류: $e');
      return false;
    }
  }

  /// 🎯 에디터 이미지 업로드 (전체 플로우)
  /// - 파일 선택부터 placeholder 생성, 업로드, 노드 교체까지 처리
  Future<void> uploadEditorImages({
    required List<File> files,
    required String Function(String localPath) onCreatePlaceholder,
    required Future<void> Function(String placeholderId, String url)
    onReplacePlaceholder,
    required void Function(String placeholderId) onDeletePlaceholder,
    required bool Function() isMounted,
    required BuildContext? context,
    required Future<void> Function(String title, String message)
    showErrorDialog,
  }) async {
    if (files.isEmpty) return;

    debugPrint('[UploadService] 📸 에디터 이미지 업로드 시작: ${files.length}개');

    int completed = 0;
    int failedCount = 0;
    bool summaryShown = false;
    final Set<String> handled = <String>{};

    for (final file in files) {
      // 1. Placeholder 생성
      final placeholderId = onCreatePlaceholder(file.path);

      // 2. 업로드 태스크 생성
      final task = enqueueFile(
        file,
        kind: UploadKind.editorImage,
        refId: placeholderId,
      );

      // 3. 업로드 완료 처리
      Future<void> handleTask() async {
        if (handled.contains(task.id)) return;
        if (task.state != UploadState.success &&
            task.state != UploadState.failed &&
            task.state != UploadState.cancelled) {
          return;
        }

        handled.add(task.id);

        if (task.state == UploadState.success && (task.url ?? '').isNotEmpty) {
          debugPrint(
            '[UploadService] ✅ 이미지 업로드 완료: placeholderId=$placeholderId, url=${task.url}',
          );
          await onReplacePlaceholder(placeholderId, task.url!);
          completed++;
        } else if (task.state == UploadState.failed ||
            task.state == UploadState.cancelled) {
          debugPrint(
            '[UploadService] ❌ 이미지 업로드 실패: placeholderId=$placeholderId',
          );
          onDeletePlaceholder(placeholderId);
          failedCount++;
          completed++;
        }

        // 실패 요약 다이얼로그
        if (completed == files.length &&
            failedCount > 0 &&
            !summaryShown &&
            isMounted()) {
          summaryShown = true;
          await showErrorDialog(
            '업로드 실패',
            '전체 중 ${failedCount}개의 업로드가 실패했습니다.\n네트워크 상태를 확인해주세요.',
          );
        }
      }

      task.addListener(handleTask);
      Future.microtask(handleTask);
    }
  }

  /// 🎯 에디터 영상 업로드 (전체 플로우)
  /// - 파일 선택부터 placeholder 생성, 썸네일 생성, 압축, 업로드, 노드 교체까지 처리
  /// - Placeholder는 즉시 생성하고, 압축은 비동기로 처리하여 UI 블로킹 방지
  Future<void> uploadEditorVideo({
    required File file,
    required String Function(
      String localPath,
      String fileName, {
      String? thumbnailPath,
    })
    onCreatePlaceholder,
    required void Function(String placeholderId, String thumbnailPath)
    onUpdateThumbnail,
    required Future<void> Function(
      String placeholderId,
      String url, {
      String? fallbackLocalPath,
    })
    onReplacePlaceholder,
    required void Function(String placeholderId) onDeletePlaceholder,
    required bool Function() isMounted,
    required BuildContext? context,
    required Future<void> Function(String title, String message)
    showErrorDialog,
    String? existingPlaceholderId, // 🎯 이미 생성된 플레이스홀더 ID (선택적)
    String? editorId, // 🎯 에디터 ID (압축 취소용)
  }) async {
    // 🎯 즉시 로그 출력 (메서드 진입 시점 확인)
    debugPrint('[UploadService] 🎬 에디터 영상 업로드 시작: ${file.path}');

    try {
      // 1. 확장자 검증
      if (!_validateVideoExtension(file.path)) {
        if (isMounted() && context != null) {
          await showErrorDialog(
            '지원하지 않는 형식',
            '영상 형식이 지원되지 않습니다. mp4/mov/m4v만 업로드 가능합니다.',
          );
        }
        return;
      }

      // 2. Placeholder 생성 (이미 생성된 경우 재사용)
      final originalFileName = file.path.split('/').last;
      final placeholderId =
          existingPlaceholderId ??
          onCreatePlaceholder(
            file.path,
            originalFileName,
            thumbnailPath: '', // 썸네일 없이 먼저 생성
          );
      debugPrint(
        '[UploadService] ✅ Placeholder ${existingPlaceholderId != null ? "재사용" : "생성"}: placeholderId=$placeholderId',
      );

      // 🎯 UI 업데이트를 위해 즉시 반환 (placeholder가 화면에 표시되도록)
      // 썸네일 생성, 압축, 업로드는 모두 백그라운드에서 비동기로 처리
      // 즉시 실행 시작 (await하지 않음)
      () async {
        // 3. 썸네일 생성 (비동기, 완료되면 플레이스홀더 업데이트)
        _generateThumbnailAsync(
          file.path,
          placeholderId,
          onUpdateThumbnail,
          isMounted,
        );

        // 4. 비디오 압축 및 업로드 (비동기로 처리하여 UI 블로킹 방지)
        await _compressAndUploadVideo(
          file: file,
          placeholderId: placeholderId,
          onDeletePlaceholder: onDeletePlaceholder,
          onReplacePlaceholder: onReplacePlaceholder,
          isMounted: isMounted,
          context: context,
          showErrorDialog: showErrorDialog,
          editorId: editorId,
        );
      }();

      // 메서드 즉시 반환 (placeholder가 UI에 즉시 표시되도록)
      return;
    } catch (e) {
      debugPrint('[UploadService] ❌ 영상 업로드 오류: $e');
    }
  }

  /// 비디오 압축 및 업로드 (비동기 처리)
  Future<void> _compressAndUploadVideo({
    required File file,
    required String placeholderId,
    required void Function(String placeholderId) onDeletePlaceholder,
    required Future<void> Function(
      String placeholderId,
      String url, {
      String? fallbackLocalPath,
    })
    onReplacePlaceholder,
    required bool Function() isMounted,
    required BuildContext? context,
    required Future<void> Function(String title, String message)
    showErrorDialog,
    String? editorId, // 🎯 에디터 ID (압축 취소용)
  }) async {
    try {
      // 비디오 압축 (시간이 오래 걸릴 수 있음)
      final mp4File = await _compressVideo(file.path, editorId: editorId);

      // 취소된 경우
      if (mp4File == null && editorId != null) {
        final token = _editorCompressionTokens[editorId];
        if (token != null && token.isCancelled) {
          debugPrint('[UploadService] 압축이 취소되어 업로드 중단');
          onDeletePlaceholder(placeholderId);
          return;
        }
      }
      if (mp4File == null) {
        onDeletePlaceholder(placeholderId);
        if (isMounted() && context != null) {
          await showErrorDialog('업로드 불가', '파일 용량이 너무 큽니다.');
        }
        return;
      }

      final mp4FileName = mp4File.path.split('/').last;
      debugPrint('[UploadService] MP4 변환 완료: ${mp4File.path}');

      // 업로드 태스크 생성 및 시작
      final task = createTaskForFile(
        mp4File,
        kind: UploadKind.video,
        overrideName: mp4FileName,
        refId: placeholderId,
      );

      // 업로드 완료 처리
      bool videoHandled = false;
      late VoidCallback listener;

      Future<void> handleOnce() async {
        if (videoHandled) return;

        if (task.state == UploadState.failed) {
          videoHandled = true;
          onDeletePlaceholder(placeholderId);
          if (isMounted() && context != null) {
            await _showVideoUploadFailedDialog(context, task.error);
          }
          try {
            task.removeListener(listener);
          } catch (_) {}
        } else if (task.state == UploadState.success && task.url != null) {
          videoHandled = true;
          await onReplacePlaceholder(
            placeholderId,
            task.url!,
            fallbackLocalPath: file.path,
          );
          try {
            task.removeListener(listener);
          } catch (_) {}
        }
      }

      listener = handleOnce;
      task.addListener(listener);
      startTask(task);

      // 즉시 확인 + 지연 확인
      await Future.microtask(handleOnce);
      Future.delayed(const Duration(milliseconds: 140), handleOnce);
      Future.delayed(const Duration(seconds: 2), handleOnce);
    } catch (e) {
      debugPrint('[UploadService] ❌ 비디오 압축/업로드 오류: $e');
      // 🎯 에러 발생 시 즉시 플레이스홀더 삭제 및 에러 다이얼로그 표시
      onDeletePlaceholder(placeholderId);
      if (isMounted() && context != null) {
        await _showVideoUploadFailedDialog(context, e);
      }
    }
  }

  // === Private Helper Methods ===

  bool _validateVideoExtension(String filePath) {
    final String ext = filePath.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v'}.contains(ext);
  }

  void _generateThumbnailAsync(
    String videoPath,
    String placeholderId,
    void Function(String placeholderId, String thumbnailPath) onUpdateThumbnail,
    bool Function() isMounted,
  ) {
    VideoUploadUtils.generateThumbnail(videoPath)
        .then((thumbnail) {
          if (thumbnail != null && isMounted()) {
            onUpdateThumbnail(placeholderId, thumbnail.path);
            debugPrint(
              '[UploadService] 썸네일 생성 완료: placeholderId=$placeholderId',
            );
          }
        })
        .catchError((e) {
          debugPrint('[UploadService] 썸네일 생성 실패 (계속 진행): $e');
        });
  }

  Future<File?> _compressVideo(String videoPath, {String? editorId}) async {
    // 에디터 ID가 있으면 취소 토큰 생성 및 추적
    CancellationToken? token;
    if (editorId != null) {
      token = CancellationToken();
      _editorCompressionTokens[editorId] = token;
    }

    try {
      return await VideoUploadUtils.compressVideo(
        videoPath,
        cancellationToken: token,
      );
    } finally {
      // 완료 후 토큰 제거
      if (editorId != null) {
        _editorCompressionTokens.remove(editorId);
      }
    }
  }

  /// 에디터 종료 시 해당 에디터의 압축 취소
  void cancelEditorCompressions(String editorId) {
    final token = _editorCompressionTokens[editorId];
    if (token != null) {
      debugPrint('[UploadService] 에디터 압축 취소: editorId=$editorId');
      token.cancel();
      _editorCompressionTokens.remove(editorId);
    }
  }

  Future<void> _showVideoUploadFailedDialog(
    BuildContext context,
    Object? error,
  ) async {
    await VideoUploadUtils.showUploadFailedDialog(context, error);
  }
}
