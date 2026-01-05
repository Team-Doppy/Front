import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/r2_upload_service.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:doppy/image/video_trim_spec.dart';
import 'package:doppy/image/video_edit_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:video_player/video_player.dart';

enum UploadState { pending, uploading, success, failed, cancelled }

// UploadKind:
// - editorImage: 에디터 본문 이미지/드로잉 등 "글 작성" 컨텍스트에서 사용하는 업로드
// - chatImage: 댓글/채팅 등 에디터와 무관한 컨텍스트의 이미지 업로드 (에디터의 업로드 가드에 걸리지 않도록 분리)
// - drawing: 드로잉 오버레이에서 생성된 PNG 업로드 (에디터 본문 이미지 업로드와 분리)
enum UploadKind {
  editorImage,
  chatImage,
  drawing,
  thumbnail,
  profile,
  video,
  group,
}

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
  DateTime? finalizedAt; // ✅ success/failed/cancelled 시점 (태스크 정리용)

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
    // ✅ 최종 상태면 시각 기록, 진행 중 상태로 돌아가면 초기화
    if (s == UploadState.success ||
        s == UploadState.failed ||
        s == UploadState.cancelled) {
      finalizedAt ??= DateTime.now();
    } else {
      finalizedAt = null;
    }
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

  /// refId별 압축 토큰 추적 (개별 플레이스홀더 삭제 시 취소용)
  final Map<String, CancellationToken> _refIdCompressionTokens = {};

  /// ✅ 삭제/undo 등 "유저가 의도적으로 제거해서 취소된" refId를 짧게 기억한다.
  /// - 업로드/압축 취소로 인해 실패 다이얼로그가 뜨는 UX를 방지한다.
  /// - best-effort: 일정 시간 지나면 자동 정리
  final Map<String, DateTime> _recentlyCancelledRefIds = {};
  static const Duration _recentCancelTtl = Duration(seconds: 10);

  void _markRefCancelled(String refId) {
    if (refId.isEmpty) return;
    final now = DateTime.now();
    _recentlyCancelledRefIds[refId] = now;
    // 간단 정리 (O(n), n이 매우 작음)
    _recentlyCancelledRefIds.removeWhere(
      (_, at) => now.difference(at) > _recentCancelTtl,
    );
  }

  bool _wasRecentlyCancelledRef(String refId) {
    final at = _recentlyCancelledRefIds[refId];
    if (at == null) return false;
    return DateTime.now().difference(at) <= _recentCancelTtl;
  }

  final AuthService _authService = AuthService();
  final Dio _dio = BaseApiService().dio;

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  /// ✅ 완료된(성공/실패/취소) 태스크 정리
  /// - UploadService는 singleton이라 _tasks가 계속 쌓이면, 오래된 태스크가 다른 화면의 가드/판정에 영향을 주기 쉬움
  /// - 즉시 제거하면 UI/콜백이 완료 상태를 관찰할 시간이 부족할 수 있어, 일정 시간 이후 정리한다.
  /// - 🎯 성공한 태스크는 더 빠르게 정리 (30초)하여 false positive 방지
  void _pruneFinalizedTasks({Duration maxAge = const Duration(minutes: 2)}) {
    final now = DateTime.now();
    _tasks.removeWhere((t) {
      final at = t.finalizedAt;
      if (at == null) return false;

      // 🎯 성공한 태스크는 30초 후 정리 (더 빠른 정리로 false positive 방지)
      // 실패/취소된 태스크는 2분 후 정리 (에러 확인 시간 확보)
      final age = now.difference(at);
      if (t.state == UploadState.success) {
        return age > const Duration(seconds: 30);
      }
      return age > maxAge;
    });
  }

  /// 업로드 진행 중(pending|uploading) 작업이 있는지 여부
  /// ✅ 규칙: 전역 체크는 반드시 kinds를 좁혀서 명시해야 한다 (false positive 방지)
  bool hasActiveUploads({required Set<UploadKind> kinds}) {
    assert(
      kinds.isNotEmpty,
      '[UploadService] hasActiveUploads: kinds must not be empty',
    );
    final Set<UploadKind> targetKinds = kinds;
    return _tasks.any(
      (t) =>
          targetKinds.contains(t.kind) &&
          (t.state == UploadState.pending || t.state == UploadState.uploading),
    );
  }

  /// 특정 refId에 대한 활성 업로드가 있는지 확인
  bool hasActiveUploadForRef(String refId) {
    return _tasks.any(
      (t) =>
          t.refId == refId &&
          (t.state == UploadState.pending || t.state == UploadState.uploading),
    );
  }

  /// 특정 refId(예: Clip 노드 ID)에 대해 "압축(FFmpeg) 진행 중"인지 확인
  /// - 업로드 태스크가 없어도, 압축 중이면 ClipComponent에서 로딩 UI를 유지할 수 있게 함
  bool hasActiveCompressionForRef(String refId) {
    final token = _refIdCompressionTokens[refId];
    return token != null && !token.isCancelled;
  }

  /// ✅ 공용 헬퍼: 여러 refId 중 "업로드 진행 중(pending/uploading)"이 하나라도 있는지
  bool hasActiveUploadForAnyRef(Iterable<String> refIds) {
    final set = refIds is Set<String> ? refIds : refIds.toSet();
    if (set.isEmpty) return false;
    return _tasks.any(
      (t) =>
          t.refId != null &&
          set.contains(t.refId) &&
          (t.state == UploadState.pending || t.state == UploadState.uploading),
    );
  }

  /// ✅ 공용 헬퍼: 여러 refId 중 "압축 진행 중"이 하나라도 있는지
  bool hasActiveCompressionForAnyRef(Iterable<String> refIds) {
    final set = refIds is Set<String> ? refIds : refIds.toSet();
    if (set.isEmpty) return false;
    for (final id in set) {
      if (hasActiveCompressionForRef(id)) return true;
    }
    return false;
  }

  /// ✅ 공용 헬퍼: busy(refId) = 업로드 중 또는 압축 중
  bool isBusyRef(String refId) {
    return hasActiveUploadForRef(refId) || hasActiveCompressionForRef(refId);
  }

  /// ✅ 공용 헬퍼: 여러 refId 중 busy가 하나라도 있는지
  bool isBusyAnyRef(Iterable<String> refIds) {
    return hasActiveUploadForAnyRef(refIds) ||
        hasActiveCompressionForAnyRef(refIds);
  }

  /// ✅ 공용 헬퍼(디버그): 활성(pending/uploading) 태스크 덤프
  String debugDumpActiveTasks({Set<UploadKind>? kinds}) {
    final buf = StringBuffer();
    final active = _tasks.where(
      (t) =>
          (t.state == UploadState.pending ||
              t.state == UploadState.uploading) &&
          (kinds == null || kinds.contains(t.kind)),
    );
    for (final t in active) {
      buf.writeln(
        'id=${t.id} kind=${t.kind} state=${t.state} refId=${t.refId} file=${t.fileName}',
      );
    }
    return buf.toString().trimRight();
  }

  /// ✅ 공용 헬퍼(디버그): 특정 refId 집합에 속한 활성(pending/uploading) 태스크 덤프
  String debugDumpActiveTasksForRefs(
    Iterable<String> refIds, {
    Set<UploadKind>? kinds,
  }) {
    final set = refIds is Set<String> ? refIds : refIds.toSet();
    if (set.isEmpty) return '';
    final buf = StringBuffer();
    final active = _tasks.where(
      (t) =>
          t.refId != null &&
          set.contains(t.refId) &&
          (t.state == UploadState.pending ||
              t.state == UploadState.uploading) &&
          (kinds == null || kinds.contains(t.kind)),
    );
    for (final t in active) {
      buf.writeln(
        'id=${t.id} kind=${t.kind} state=${t.state} refId=${t.refId} file=${t.fileName}',
      );
    }
    // 압축 토큰도 함께 표시(원인 파악용)
    for (final id in set) {
      if (hasActiveCompressionForRef(id)) {
        buf.writeln('compression refId=$id');
      }
    }
    return buf.toString().trimRight();
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
    _pruneFinalizedTasks();
    notifyListeners();
  }

  /// refId(예: 노드ID)로 모든 태스크 취소
  void cancelByRef(String refId) {
    _markRefCancelled(refId);

    assert(() {
      final q = _queue.where((t) => t.refId == refId).length;
      final all = _tasks.where((t) => t.refId == refId).length;
      final uploading =
          _tasks
              .where(
                (t) =>
                    t.refId == refId &&
                    (t.state == UploadState.pending ||
                        t.state == UploadState.uploading),
              )
              .length;
      final hasComp = _refIdCompressionTokens[refId] != null;
      debugPrint(
        '[CancelDbg] cancelByRef: refId=$refId queue=$q tasks=$all active=$uploading hasCompressionToken=$hasComp',
      );
      return true;
    }());

    // 🎯 1. 압축 취소 (가장 먼저 - 리소스 낭비 방지)
    final compressionToken = _refIdCompressionTokens[refId];
    if (compressionToken != null) {
      debugPrint('[UploadService] 🚫 refId 기반 압축 취소: refId=$refId');
      compressionToken.cancel();
      // 🎯 FFmpeg 즉시 중단 (모든 압축 중단 - refId별 추적이 어려워서)
      // TODO: 나중에 refId별 추적이 가능하면 특정 압축만 취소하도록 개선
      FFmpegKit.cancel();
      _refIdCompressionTokens.remove(refId);
    }

    // 🎯 2. 큐에서 제거
    _queue.removeWhere((t) => t.refId == refId);
    final tasksToCancel = _tasks.where((t) => t.refId == refId).toList();

    // 🎯 3. 업로드 태스크 취소
    for (final task in tasksToCancel) {
      if (task.state == UploadState.uploading &&
          !task.cancelToken.isCancelled) {
        task.cancelToken.cancel('cancelled by refId');
      }
      // 🎯 pending 상태인 태스크도 취소 상태로 변경
      if (task.state == UploadState.pending ||
          task.state == UploadState.uploading) {
        task._setState(UploadState.cancelled);
      }
    }
    _pruneFinalizedTasks();
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

      // ✅ 업로드가 영원히 uploading에 머무는 것을 막기 위한 하드 타임아웃
      // (특히 R2/http PUT 경로는 타임아웃/취소가 약해 구조적으로 hang 가능성이 있음)
      // ✅ 요청 반영: 과도한 대기(=uploading 영구 잔존)를 막기 위해 타임아웃을 짧게 유지
      // - 이미지: 1분
      // - 비디오: 5분 (1분짜리 영상 기준으로 충분)
      final Duration hardTimeout =
          task.kind == UploadKind.video
              ? const Duration(minutes: 5)
              : const Duration(minutes: 1);

      // 🎯 프로필 이미지는 서버를 거치는 기존 방식 사용
      Map<String, dynamic> result;
      if (task.kind == UploadKind.profile) {
        // 프로필 이미지는 서버를 거치는 방식만 사용
        debugPrint('[Upload] 프로필 이미지 업로드: 서버를 거치는 기존 방식 사용');
        result = await _uploadProfileImage(task).timeout(hardTimeout);
      } else {
        // 다른 종류는 R2 직접 업로드 사용
        try {
          result = await _uploadViaR2(task).timeout(hardTimeout);
        } catch (e) {
          // R2 업로드 실패 시 기존 방식으로 폴백
          debugPrint('[Upload] R2 업로드 실패, 기존 방식으로 폴백: $e');
          result =
              task.kind == UploadKind.video
                  ? await _uploadVideo(task).timeout(hardTimeout)
                  : await _uploadSingle(
                    task,
                  ).timeout(hardTimeout); // group도 _uploadSingle 사용
        }
      }

      // ✅ 취소가 요청된 상태면 결과를 반영하지 않는다.
      // (특히 R2/http PUT 경로는 취소가 즉시 중단되지 않을 수 있어, 성공 응답이 와도 무시해야 한다)
      final refId = task.refId ?? '';
      final cancelledByRef =
          refId.isNotEmpty && _wasRecentlyCancelledRef(refId);
      if (cancelledByRef || task.cancelToken.isCancelled) {
        debugPrint(
          '[Upload] ignore success due to cancellation: id=${task.id} refId=$refId kind=${task.kind}',
        );
        task._setState(UploadState.cancelled);
        return;
      }

      task.url = result['accessUrl'] as String?;
      task._setProgress(1);
      task._setState(UploadState.success);
      debugPrint(
        '[Upload] ✅ 업로드 완료: id=${task.id} refId=${task.refId} kind=${task.kind} url=${task.url}',
      );
    } catch (e) {
      if (e is TimeoutException) {
        debugPrint('[Upload] ❌ timeout id=${task.id} kind=${task.kind}');
        task.error = e;
        task._setState(UploadState.failed);
        return;
      }
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
        _pruneFinalizedTasks();
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
      if ((task.kind == UploadKind.editorImage ||
              task.kind == UploadKind.chatImage) &&
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

      // 성공한 URL 가져오기 (task.kind에 따라 올바른 URL 선택)
      String? url;
      if (task.kind == UploadKind.video) {
        // 영상인 경우 videoUrls 우선
        if (result.videoUrls.isNotEmpty) {
          url = result.videoUrls.first;
        } else if (result.imageUrls.isNotEmpty) {
          // 폴백: videoUrls가 없으면 imageUrls 사용 (서버가 잘못 분류한 경우)
          url = result.imageUrls.first;
          debugPrint('[Upload] ⚠️ 영상이지만 imageUrls에서 URL 반환됨');
        }
      } else {
        // 이미지인 경우 imageUrls 우선
        if (result.imageUrls.isNotEmpty) {
          url = result.imageUrls.first;
        } else if (result.videoUrls.isNotEmpty) {
          // 폴백: imageUrls가 없으면 videoUrls 사용 (서버가 잘못 분류한 경우)
          url = result.videoUrls.first;
          debugPrint('[Upload] ⚠️ 이미지지만 videoUrls에서 URL 반환됨');
        }
      }

      if (url == null) {
        throw Exception('R2 업로드 성공했지만 URL을 찾을 수 없음');
      }

      debugPrint('[Upload] R2 업로드 성공 (kind: ${task.kind}): $url');

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

  // 이미지 리사이즈/압축: 긴 변 1440px, JPEG 75 (빠른 로드를 위한 최적화)
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
        'quality': 75, // 🚀 82 → 75 (파일 크기 약 30% 감소, 화질 저하 거의 없음)
        'fileName': task.fileName, // 🎯 파일명 전달 (PNG 감지용)
      });
      return out;
    } catch (_) {
      return task.bytes ?? await task.file!.readAsBytes();
    }
  }

  // compute용 워커(탑레벨)
  // 🚀 타겟 파일 크기 기반 적응형 압축 (모든 이미지가 비슷한 크기로)
  static Future<Uint8List> _resizeImageWorker(Map<String, Object?> args) async {
    final bytes = args['bytes'] as Uint8List;
    final int maxSide = (args['maxSide'] as int?) ?? 1440;
    final int baseQuality = (args['quality'] as int?) ?? 75;
    final String? fileName = args['fileName'] as String?;
    final bool isPng = fileName?.toLowerCase().endsWith('.png') ?? false;

    // 🚀 타겟 파일 크기: 약 500KB (로드 시간 균일화 목표)
    const int targetBytes = 500 * 1024;

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

      // 리사이즈 필요 여부 확인
      img.Image? resized;
      if (w > maxSide || h > maxSide) {
        final scale = w >= h ? maxSide / w : maxSide / h;
        final newW = (w * scale).round();
        final newH = (h * scale).round();
        resized = img.copyResize(
          decoded,
          width: newW,
          height: newH,
          interpolation: img.Interpolation.average,
        );
      } else {
        resized = decoded;
      }

      // 🎯 PNG는 PNG로, 나머지는 JPG로 인코딩 (적응형 품질 조정)
      if (isPng) {
        return Uint8List.fromList(img.encodePng(resized, level: 6));
      } else {
        // 🚀 타겟 크기에 맞게 quality 조정 (적응형 압축)
        int currentQuality = baseQuality;
        Uint8List result = Uint8List.fromList(
          img.encodeJpg(resized, quality: currentQuality),
        );

        // 타겟 크기보다 크면 quality를 낮춰서 재시도 (최소 60까지)
        if (result.length > targetBytes && currentQuality > 60) {
          int low = 60;
          int high = currentQuality;

          // 바이너리 서치로 타겟 크기에 가까운 quality 찾기
          while (low <= high) {
            currentQuality = (low + high) ~/ 2;
            result = Uint8List.fromList(
              img.encodeJpg(resized, quality: currentQuality),
            );

            if (result.length > targetBytes) {
              // 여전히 크면 quality를 더 낮춤
              high = currentQuality - 1;
            } else {
              // 타겟 이하면 quality를 높일 수 있는지 시도
              if (currentQuality < baseQuality) {
                final nextQuality = (currentQuality + high).clamp(
                  currentQuality + 1,
                  baseQuality,
                );
                final nextResult = Uint8List.fromList(
                  img.encodeJpg(resized, quality: nextQuality),
                );
                if (nextResult.length <= targetBytes) {
                  currentQuality = nextQuality;
                  result = nextResult;
                  break;
                }
              }
              break;
            }
          }
        }

        return result;
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
    required String refId,
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
                refId: refId,
              ),
            )
            .toList();
    _tasks.addAll(all);
    _pruneFinalizedTasks();
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
      if (!_disposed) {
        _pruneFinalizedTasks();
        notifyListeners();
      }
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
      // 🎯 실제 인코딩 형식에 맞게 파일명 수정
      // PNG가 아니면 JPEG로 인코딩되므로 파일명도 .jpg로 변경
      final fileNameParts = t.fileName.split('.');
      final originalExt =
          fileNameParts.length > 1 ? fileNameParts.last.toLowerCase() : '';
      final bool isPng = originalExt == 'png';
      final String adjustedFileName;
      if (isPng) {
        // PNG는 PNG로 유지
        adjustedFileName = t.fileName;
      } else {
        // 나머지는 JPEG로 인코딩되므로 .jpg 확장자로 변경
        if (fileNameParts.length > 1) {
          final baseName = t.fileName.substring(0, t.fileName.lastIndexOf('.'));
          adjustedFileName = '$baseName.jpg';
        } else {
          // 확장자가 없는 경우 .jpg 추가
          adjustedFileName = '${t.fileName}.jpg';
        }
      }
      final mediaType = _createMediaType(adjustedFileName);
      formData.files.add(
        MapEntry(
          'files',
          MultipartFile.fromBytes(
            bytes,
            filename: adjustedFileName,
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
  /// - 파일 선택부터 노드 생성, 업로드, 노드 업데이트까지 처리
  Future<void> uploadEditorImages({
    required List<File> files,
    required String Function(String localPath) onCreateNode,
    required Future<void> Function(String nodeId, String url) onUploadComplete,
    required void Function(String nodeId) onDeleteNode,
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
    final Set<String> createdNodes = <String>{}; // 🎯 생성된 노드 추적

    for (final file in files) {
      // 1. 노드 생성
      final nodeId = onCreateNode(file.path);

      // 🎯 같은 노드 ID가 이미 생성되었으면 재사용 (그룹 이미지용)
      final isNewNode = createdNodes.add(nodeId);

      if (isNewNode) {
        debugPrint('[UploadService] 🆕 새 노드 생성: $nodeId');
      } else {
        debugPrint('[UploadService] ♻️ 기존 노드 재사용: $nodeId');
      }

      // 2. 업로드 태스크 생성
      final task = enqueueFile(
        file,
        kind: UploadKind.editorImage,
        refId: nodeId,
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
            '[UploadService] ✅ 이미지 업로드 완료: nodeId=$nodeId, url=${task.url}',
          );
          await onUploadComplete(nodeId, task.url!);
          completed++;
        } else if (task.state == UploadState.cancelled) {
          // ✅ 취소(삭제/undo/사용자 취소 등)는 실패 다이얼로그 대상이 아니다.
          debugPrint('[UploadService] 🚫 이미지 업로드 취소: nodeId=$nodeId');
          // 🎯 그룹 이미지인 경우 전체 삭제를 한 번만 호출
          if (createdNodes.contains(nodeId)) {
            onDeleteNode(nodeId);
            createdNodes.remove(nodeId); // 중복 삭제 방지
          }
          completed++;
        } else if (task.state == UploadState.failed) {
          debugPrint('[UploadService] ❌ 이미지 업로드 실패: nodeId=$nodeId');
          // 🎯 그룹 이미지인 경우 전체 삭제를 한 번만 호출
          if (createdNodes.contains(nodeId)) {
            onDeleteNode(nodeId);
            createdNodes.remove(nodeId); // 중복 삭제 방지
          }
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
  /// - 파일 선택부터 노드 생성, 썸네일 생성, 압축, 업로드, 노드 업데이트까지 처리
  /// - 노드는 즉시 생성하고, 압축은 비동기로 처리하여 UI 블로킹 방지
  /// - 🎯 노드가 성공적으로 생성된 경우에만 압축/업로드 진행
  Future<void> uploadEditorVideo({
    required File file,
    required String Function(
      String localPath,
      String fileName, {
      String? thumbnailPath,
      double? aspectRatio,
    })
    onCreateNode,
    required void Function(String nodeId, String thumbnailPath)
    onUpdateThumbnail,
    required Future<void> Function(
      String nodeId,
      String url, {
      String? fallbackLocalPath,
      String? processedLocalPath, // 🎯 ffmpeg 처리된 비디오 경로
    })
    onUploadComplete,
    void Function(String nodeId, String processedLocalPath)?
    onCompressionComplete,
    required void Function(String nodeId) onDeleteNode,
    required bool Function() isMounted,
    required BuildContext? context,
    required Future<void> Function(String title, String message)
    showErrorDialog,
    String? existingNodeId, // 🎯 이미 생성된 노드 ID (선택적)
    String? editorId, // 🎯 에디터 ID (압축 취소용)
    String? initialThumbnailPath, // 🎯 트림 시 추출한 썸네일 경로 (선택적)
    VideoTrimSpec? trimSpec, // 🎯 트림 스펙 (FFmpeg 1회 처리를 위해)
    VideoEditSpec? editSpec, // 🎯 편집 스펙 (FFmpeg 1회 처리를 위해)
  }) async {
    // 🎯 즉시 로그 출력 (메서드 진입 시점 확인)
    debugPrint('[UploadService] 🎬 에디터 영상 업로드 시작: ${file.path}');
    debugPrint(
      '[UploadService] 📋 받은 스펙: trimSpec=${trimSpec != null ? "start=${trimSpec.startSeconds}, end=${trimSpec.endSeconds}" : "null"}, editSpec=${editSpec != null ? "crop=${editSpec.cropRectImage != null}, brightness=${editSpec.brightness}, contrast=${editSpec.contrast}" : "null"}',
    );

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

      // 2. 영상 비율 정보 가져오기 (노드 생성 전)
      double? aspectRatio;
      try {
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        if (controller.value.isInitialized) {
          final size = controller.value.size;
          if (size.height > 0) {
            aspectRatio = size.width / size.height;
            debugPrint(
              '[UploadService] 영상 비율: $aspectRatio (${size.width}x${size.height})',
            );
          }
        }
        await controller.dispose();
      } catch (e) {
        debugPrint('[UploadService] 영상 비율 가져오기 실패 (기본값 사용): $e');
      }

      // 🎯 편집 크롭이 있으면 "변환 결과" 비율을 우선 사용 (썸네일/레이아웃이 원본 비율로 보이는 문제 방지)
      // - cropRectImage는 변환 후 프레임(에디터 기준) 좌표로 저장되므로 rect 비율이 최종 출력 비율과 가장 일치함
      if (editSpec?.cropRectImage != null) {
        final rect = editSpec!.cropRectImage!;
        if (rect.height > 0) {
          aspectRatio = rect.width / rect.height;
          debugPrint('[UploadService] 🎯 크롭 기반 비율로 덮어씀: $aspectRatio');
        }
      } else if (editSpec != null && aspectRatio != null) {
        // 크롭이 없더라도 90/270도 회전이면 비율이 뒤집힘
        final turns = editSpec.rotationQuarterTurns % 4;
        if (turns == 1 || turns == 3) {
          if (aspectRatio != 0) {
            aspectRatio = 1.0 / aspectRatio;
            debugPrint('[UploadService] 🎯 회전 기반 비율로 덮어씀: $aspectRatio');
          }
        }
      }

      // 3. 노드 생성 (이미 생성된 경우 재사용)
      final originalFileName = file.path.split('/').last;
      String? nodeId;

      try {
        nodeId =
            existingNodeId ??
            onCreateNode(
              file.path,
              originalFileName,
              thumbnailPath: initialThumbnailPath ?? '', // 🎯 트림 시 추출한 썸네일 사용
              aspectRatio: aspectRatio, // 🎯 비율 정보 전달
            );

        // 🎯 노드 ID가 유효한지 확인
        if (nodeId.isEmpty) {
          debugPrint('[UploadService] ❌ 노드 ID가 비어있음');
          if (isMounted() && context != null) {
            await showErrorDialog('오류', '영상을 추가할 수 없습니다. 다시 시도해주세요.');
          }
          return;
        }

        debugPrint(
          '[UploadService] ✅ 노드 ${existingNodeId != null ? "재사용" : "생성"}: nodeId=$nodeId${initialThumbnailPath != null ? " (썸네일 포함)" : ""}',
        );
      } catch (e) {
        debugPrint('[UploadService] ❌ 노드 생성 실패: $e');
        if (isMounted() && context != null) {
          await showErrorDialog('오류', '영상을 추가할 수 없습니다. 다시 시도해주세요.');
        }
        return;
      }

      // 🎯 노드가 성공적으로 생성된 경우에만 압축/업로드 진행
      // UI 업데이트를 위해 즉시 반환 (노드가 화면에 표시되도록)
      // 썸네일 생성, 압축, 업로드는 모두 백그라운드에서 비동기로 처리
      Future.microtask(() async {
        // 🎯 노드가 여전히 유효한지 확인
        if (!isMounted() || nodeId == null || nodeId.isEmpty) {
          debugPrint('[UploadService] ⚠️ 노드가 유효하지 않아 압축/업로드 중단');
          return;
        }

        // 3. 썸네일 생성 (비동기, 완료되면 노드 업데이트)
        // 🎯 트림 시 이미 썸네일이 추출되었으면 스킵
        // 🎯 FFmpeg 전에 빠르게 썸네일 생성 (trim 구간 프레임 + 이미지 필터/크롭 적용)
        if (initialThumbnailPath == null || initialThumbnailPath.isEmpty) {
          _generateThumbnailAsync(
            file.path,
            nodeId,
            onUpdateThumbnail,
            isMounted,
            trimSpec: trimSpec,
            editSpec: editSpec,
          );
        } else {
          debugPrint('[UploadService] ⏭️ 썸네일 이미 있음 - 생성 스킵');
        }

        // 4. 비디오 압축 및 업로드 (비동기로 처리하여 UI 블로킹 방지)
        await _compressAndUploadVideo(
          file: file,
          nodeId: nodeId,
          onDeleteNode: onDeleteNode,
          onCompressionComplete: onCompressionComplete,
          onUploadComplete: onUploadComplete,
          isMounted: isMounted,
          context: context,
          showErrorDialog: showErrorDialog,
          editorId: editorId,
          // ✅ 핵심: 트림/편집 스펙을 압축 단계까지 전달해야 실제 업로드 파일에 반영됨
          trimSpec: trimSpec,
          editSpec: editSpec,
        );
      });

      // 메서드 즉시 반환 (노드가 UI에 즉시 표시되도록)
      return;
    } catch (e) {
      debugPrint('[UploadService] ❌ 영상 업로드 오류: $e');
      if (isMounted() && context != null) {
        await showErrorDialog('오류', '영상 업로드 중 오류가 발생했습니다. 다시 시도해주세요.');
      }
    }
  }

  /// 비디오 압축 및 업로드 (비동기 처리)
  /// 🎯 노드가 유효한 경우에만 압축/업로드 진행
  /// 🎯 trim+edit+압축을 한 번의 FFmpeg로 처리
  Future<void> _compressAndUploadVideo({
    required File file,
    required String nodeId,
    required void Function(String nodeId) onDeleteNode,
    void Function(String nodeId, String processedLocalPath)?
    onCompressionComplete,
    required Future<void> Function(
      String nodeId,
      String url, {
      String? fallbackLocalPath,
      String? processedLocalPath, // 🎯 ffmpeg 처리된 비디오 경로
    })
    onUploadComplete,
    required bool Function() isMounted,
    required BuildContext? context,
    required Future<void> Function(String title, String message)
    showErrorDialog,
    String? editorId, // 🎯 에디터 ID (압축 취소용)
    VideoTrimSpec? trimSpec, // 🎯 트림 스펙
    VideoEditSpec? editSpec, // 🎯 편집 스펙
  }) async {
    // 🎯 노드 유효성 확인
    if (nodeId.isEmpty) {
      debugPrint('[UploadService] ⚠️ 노드 ID가 비어있어 압축/업로드 중단');
      return;
    }

    try {
      // 🎯 취소 확인 (압축 시작 전) - refId와 editorId 모두 확인
      // 단, 토큰이 이미 생성되어 있고 취소된 경우에만 중단
      // 토큰이 아직 생성되지 않았으면 정상 진행 (압축 시작 시 토큰 생성됨)
      final refToken = _refIdCompressionTokens[nodeId];
      if (refToken != null && refToken.isCancelled) {
        debugPrint(
          '[UploadService] ⚠️ refId 기반 압축이 이미 취소되어 업로드 중단: refId=$nodeId',
        );
        _refIdCompressionTokens.remove(nodeId);
        onDeleteNode(nodeId);
        return;
      }

      if (editorId != null) {
        final token = _editorCompressionTokens[editorId];
        if (token != null && token.isCancelled) {
          debugPrint(
            '[UploadService] ⚠️ 에디터 압축이 이미 취소되어 업로드 중단: editorId=$editorId',
          );
          onDeleteNode(nodeId);
          return;
        }
      }

      File? mp4File;
      mp4File = await _compressVideo(
        file.path,
        editorId: editorId,
        refId: nodeId, // 🎯 refId 전달하여 개별 취소 가능하도록
        trimSpec: trimSpec,
        editSpec: editSpec,
      );

      // 🎯 취소 확인 (압축 완료 후)
      if (editorId != null) {
        final token = _editorCompressionTokens[editorId];
        if (token != null && token.isCancelled) {
          debugPrint('[UploadService] 압축이 취소되어 업로드 중단');
          if (mp4File != null && await mp4File.exists()) {
            try {
              await mp4File.delete();
            } catch (_) {}
          }
          onDeleteNode(nodeId);
          return;
        }
      }

      // 압축 실패 처리
      if (mp4File == null) {
        debugPrint('[UploadService] ⚠️ 비디오 압축 실패 또는 취소됨');

        // 🎯 취소된 경우가 아니면 노드 삭제 및 에러 다이얼로그 표시
        final wasCancelled =
            _wasRecentlyCancelledRef(nodeId) ||
            (editorId != null &&
                _editorCompressionTokens[editorId] != null &&
                _editorCompressionTokens[editorId]!.isCancelled);

        if (!wasCancelled) {
          onDeleteNode(nodeId);
          if (isMounted() && context != null) {
            // 🎯 압축 실패 원인에 따라 다른 메시지 표시
            // (실제로는 VideoUploadUtils에서 더 자세한 에러 메시지를 제공할 수 있음)
            await showErrorDialog(
              '업로드 불가',
              '영상 압축에 실패했습니다.\n파일이 손상되었거나 형식이 올바르지 않을 수 있습니다.',
            );
          }
        } else {
          // 취소된 경우 노드만 삭제 (다이얼로그 표시 안 함)
          onDeleteNode(nodeId);
        }
        return;
      }

      // ✅ 압축 완료 즉시: 노드 localPath를 processed mp4로 교체하여
      // video_player가 검정 화면 없이 바로 첫 프레임을 디코딩할 수 있게 함
      try {
        onCompressionComplete?.call(nodeId, mp4File.path);
      } catch (e) {
        debugPrint('[UploadService] onCompressionComplete 콜백 오류: $e');
      }

      final mp4FileName = mp4File.path.split('/').last;
      debugPrint('[UploadService] MP4 변환 완료: ${mp4File.path}');

      // 업로드 태스크 생성 및 시작
      final task = createTaskForFile(
        mp4File,
        kind: UploadKind.video,
        overrideName: mp4FileName,
        refId: nodeId,
      );

      // 업로드 완료 처리
      bool videoHandled = false;
      late VoidCallback listener;

      Future<void> handleOnce() async {
        if (videoHandled) return;

        final cancelledByRef = _wasRecentlyCancelledRef(nodeId);

        // 🎯 취소된 경우 리스너 제거하고 종료
        if (task.state == UploadState.cancelled) {
          videoHandled = true;
          try {
            task.removeListener(listener);
          } catch (_) {}
          return;
        }

        if (task.state == UploadState.failed) {
          videoHandled = true;
          onDeleteNode(nodeId);
          // ✅ 삭제/undo로 인한 취소면 실패 다이얼로그는 숨긴다.
          if (!cancelledByRef && isMounted() && context != null) {
            await _showVideoUploadFailedDialog(context, task.error);
          }
          try {
            task.removeListener(listener);
          } catch (_) {}
        } else if (task.state == UploadState.success && task.url != null) {
          videoHandled = true;
          await onUploadComplete(
            nodeId,
            task.url!,
            fallbackLocalPath: file.path,
            processedLocalPath:
                mp4File?.path, // 🎯 ffmpeg 처리된 경로 전달 (null일 수 있음)
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
      // 🎯 에러 발생 시 즉시 노드 삭제 및 에러 다이얼로그 표시
      onDeleteNode(nodeId);
      // ✅ 삭제/undo로 인한 취소면 실패 다이얼로그는 숨긴다.
      if (!_wasRecentlyCancelledRef(nodeId) && isMounted() && context != null) {
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
    bool Function() isMounted, {
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
  }) {
    VideoUploadUtils.generateThumbnail(
          videoPath,
          trimSpec: trimSpec,
          editSpec: editSpec,
        )
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

  Future<File?> _compressVideo(
    String videoPath, {
    String? editorId,
    String? refId,
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
  }) async {
    // 🎯 refId별 토큰 생성 (개별 취소용)
    // 이미 취소된 토큰이 있으면 즉시 null 반환
    CancellationToken? refToken;
    if (refId != null) {
      final existingRefToken = _refIdCompressionTokens[refId];
      if (existingRefToken != null && existingRefToken.isCancelled) {
        debugPrint('[UploadService] ⚠️ refId 기반 압축이 이미 취소됨: refId=$refId');
        _refIdCompressionTokens.remove(refId);
        notifyListeners();
        return null;
      }
      refToken = CancellationToken();
      _refIdCompressionTokens[refId] = refToken;
      notifyListeners(); // ✅ "압축 시작"을 UI에 즉시 반영
    }

    // 🎯 에디터 ID별 토큰 생성 (에디터 전체 취소용)
    // 여러 압축이 동시에 진행될 수 있으므로 리스트로 관리
    CancellationToken? editorToken;
    if (editorId != null) {
      editorToken = CancellationToken();
      // 🎯 기존 토큰이 있으면 취소하고 새로 생성 (에디터 전체 취소 시 모든 압축 취소)
      final existingToken = _editorCompressionTokens[editorId];
      if (existingToken != null) {
        existingToken.cancel();
      }
      _editorCompressionTokens[editorId] = editorToken;
    }

    // 🎯 두 토큰 중 하나라도 취소되면 압축 취소
    // refToken이 있으면 그것을 사용하고, editorToken이 취소되면 refToken도 취소
    // refToken이 없으면 editorToken 사용
    if (refToken != null && editorToken != null) {
      // editorToken이 취소되면 refToken도 취소
      final refTokenFinal = refToken; // 클로저를 위한 로컬 변수
      editorToken.addListener(() {
        if (editorToken!.isCancelled) {
          refTokenFinal.cancel();
        }
      });
    }
    final effectiveToken = refToken ?? editorToken;

    try {
      // ✅ FFmpeg/파일 I/O가 특정 환경에서 영구 대기(hang)할 수 있어 하드 타임아웃으로 보호
      return await VideoUploadUtils.compressVideo(
        videoPath,
        cancellationToken: effectiveToken,
        trimSpec: trimSpec,
        editSpec: editSpec,
        // ✅ 요청 반영: 압축도 무한 대기를 방지 (1분짜리 영상 기준으로 5분 충분)
      ).timeout(const Duration(minutes: 5));
    } on TimeoutException catch (e) {
      debugPrint('[UploadService] ❌ 비디오 압축 타임아웃: $e (refId=$refId)');
      try {
        effectiveToken?.cancel();
      } catch (_) {}
      return null;
    } finally {
      // 완료 후 토큰 제거
      if (refId != null) {
        _refIdCompressionTokens.remove(refId);
        notifyListeners(); // ✅ "압축 종료"를 UI에 즉시 반영
      }
      // 🎯 에디터 토큰은 유지 (다른 압축이 진행 중일 수 있음)
      // 대신 압축 완료 시 현재 토큰과 비교하여 제거
      if (editorId != null &&
          _editorCompressionTokens[editorId] == editorToken) {
        _editorCompressionTokens.remove(editorId);
      }
    }
  }

  /// 에디터 종료 시 해당 에디터의 압축 취소
  void cancelEditorCompressions(String editorId) {
    final token = _editorCompressionTokens[editorId];
    if (token != null) {
      debugPrint('[UploadService] 🚫 에디터 압축 취소: editorId=$editorId');
      token.cancel();
      _editorCompressionTokens.remove(editorId);
    }
    // 🎯 해당 에디터의 모든 refId 압축도 취소
    // (refId는 placeholderId이므로 직접 추적 불가, cancelByRef에서 처리)
  }

  Future<void> _showVideoUploadFailedDialog(
    BuildContext context,
    Object? error,
  ) async {
    await VideoUploadUtils.showUploadFailedDialog(context, error);
  }
}
