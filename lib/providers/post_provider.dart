import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:doppy/data/models/blog_response.dart';
import 'package:doppy/data/services/post_service.dart';

/// WebSocket 분석 대기 결과 (성공 여부 + 실패 시 사유)
class AnalysisWaitResult {
  const AnalysisWaitResult({required this.ok, this.failureReason});
  final bool ok;
  final String? failureReason;
}

/// 포스트 발행·상태 관장
/// 발행 플로우: WebSocket 연결 → 동기 업로드 → WebSocket ANALYSIS_COMPLETE 대기 → 그래프 재로드
class PostProvider extends ChangeNotifier {
  static final PostProvider _instance = PostProvider._internal();
  factory PostProvider() => _instance;
  PostProvider._internal();

  final PostService _postService = PostService();

  BlogResponse? _lastPublishedPost;
  bool _publishing = false;
  String? _publishError;

  /// 마지막으로 발행 성공한 포스트 (발행 직후 화면 갱신용)
  BlogResponse? get lastPublishedPost => _lastPublishedPost;
  bool get publishing => _publishing;
  String? get publishError => _publishError;

  /// 발행 API 호출 (POST /api/posts)
  /// [content]는 export된 JSON의 content 객체. [timeout] 초과 시 null 반환(업로드 오류).
  Future<BlogResponse?> publish({
    required String title,
    required String author,
    String? thumbnailImageUrl,
    required Map<String, dynamic> content,
    required List<String> usedImageUrls,
    required String accessLevel,
    String? region,
    Duration? timeout,
  }) async {
    if (_publishing) return null;
    _publishing = true;
    _publishError = null;
    notifyListeners();

    try {
      final post = await _postService.create(
        title: title,
        author: author,
        thumbnailImageUrl: thumbnailImageUrl,
        content: content,
        usedImageUrls: usedImageUrls,
        accessLevel: accessLevel,
        region: region,
        timeout: timeout,
      );
      _lastPublishedPost = post;
      _publishError = null;
      if (kDebugMode) debugPrint('[Publish] 동기적 업로드 성공: id=${post.id}, title=${post.title}');
      return post;
    } catch (e) {
      _publishError = e.toString().replaceFirst('Exception: ', '');
      _lastPublishedPost = null;
      if (kDebugMode) debugPrint('[Publish] 동기적 업로드 실패: $e');
      return null;
    } finally {
      _publishing = false;
      notifyListeners();
    }
  }

  /// 발행 결과 초기화 (다음 발행 전 또는 화면 이탈 시)
  void clearLastPublish() {
    _lastPublishedPost = null;
    _publishError = null;
    notifyListeners();
  }

  // --- 분석 완료 WebSocket: 선연결 → 업로드 → 응답 대기 ---

  StreamSubscription<AnalysisEvent>? _analysisSubscription;
  Completer<void>? _subscribedCompleter;
  bool _didSubscribed = false;
  Completer<AnalysisWaitResult>? _analysisCompleteCompleter;
  int? _expectedPostId;

  /// 발행 전 호출. WebSocket 연결 후 SUBSCRIBED 수신 시 완료. 실패/타임아웃 시 예외.
  Future<void> ensureAnalysisConnection(Duration timeout) async {
    if (_didSubscribed) {
      if (kDebugMode) debugPrint('[Publish] WebSocket 이미 연결됨');
      return;
    }
    stopAnalysisEvents();
    _subscribedCompleter = Completer<void>();
    _analysisSubscription = _postService.connectAnalysisEvents().listen(
      (event) {
        if (event is AnalysisSubscribed) {
          _didSubscribed = true;
          _subscribedCompleter?.complete();
          _subscribedCompleter = null;
        } else if (event is AnalysisComplete) {
          if (_expectedPostId != null && event.postId == _expectedPostId) {
            _analysisCompleteCompleter?.complete(const AnalysisWaitResult(ok: true));
            _analysisCompleteCompleter = null;
            _expectedPostId = null;
          }
        } else if (event is AnalysisFailed) {
          if (_expectedPostId != null && event.postId == _expectedPostId) {
            _analysisCompleteCompleter?.complete(AnalysisWaitResult(ok: false, failureReason: event.reason));
            _analysisCompleteCompleter = null;
            _expectedPostId = null;
          }
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[Publish] WebSocket 스트림 오류: $e');
        _subscribedCompleter?.completeError(e);
        _analysisCompleteCompleter?.complete(const AnalysisWaitResult(ok: false));
      },
      onDone: () {
        if (kDebugMode) debugPrint('[Publish] WebSocket 스트림 종료');
        if (_subscribedCompleter != null && !_subscribedCompleter!.isCompleted) {
          _subscribedCompleter!.completeError(Exception('WebSocket 종료'));
        }
        _analysisCompleteCompleter?.complete(const AnalysisWaitResult(ok: false));
      },
      cancelOnError: false,
    );
    try {
      await _subscribedCompleter!.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('WebSocket 연결 대기 시간 초과', timeout),
      );
      if (kDebugMode) debugPrint('[Publish] WebSocket 연결 완료 (SUBSCRIBED)');
    } catch (e) {
      stopAnalysisEvents();
      _didSubscribed = false;
      rethrow;
    }
  }

  /// 업로드 성공 후 호출. ANALYSIS_COMPLETE 시 ok:true, ANALYSIS_FAILED/타임아웃/오류 시 ok:false + failureReason.
  Future<AnalysisWaitResult> waitForAnalysisComplete(int postId, Duration timeout) async {
    _expectedPostId = postId;
    _analysisCompleteCompleter = Completer<AnalysisWaitResult>();
    try {
      final result = await _analysisCompleteCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          if (kDebugMode) debugPrint('[Publish] WebSocket 응답 대기 타임아웃 postId=$postId');
          _analysisCompleteCompleter?.complete(const AnalysisWaitResult(ok: false));
          _expectedPostId = null;
          return const AnalysisWaitResult(ok: false, failureReason: '응답 대기 시간이 초과되었어요');
        },
      );
      if (kDebugMode) debugPrint('[Publish] WebSocket 응답 수신 완료 postId=$postId ok=${result.ok}');
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Publish] WebSocket 응답 대기 오류: $e');
      _analysisCompleteCompleter?.complete(const AnalysisWaitResult(ok: false));
      _expectedPostId = null;
      return const AnalysisWaitResult(ok: false, failureReason: null);
    }
  }

  /// 분석 이벤트 구독 시작 (레거시: 그래프 갱신은 waitForAnalysisComplete + loadGraph로 처리 권장)
  void startAnalysisEvents({void Function(int postId)? onAnalysisComplete}) {
    stopAnalysisEvents();
    _analysisSubscription = _postService
        .connectAnalysisEvents(onAnalysisComplete: onAnalysisComplete)
        .listen(
          (event) {
            if (event is AnalysisComplete && kDebugMode) {
              debugPrint('[Publish] ANALYSIS_COMPLETE postId=${event.postId}');
            }
          },
          onError: (e) {
            if (kDebugMode) debugPrint('[PostProvider] 분석 이벤트 스트림 오류: $e');
          },
          onDone: () {
            if (kDebugMode) debugPrint('[PostProvider] 분석 이벤트 스트림 종료');
          },
        );
  }

  void stopAnalysisEvents() {
    _analysisSubscription?.cancel();
    _analysisSubscription = null;
    _subscribedCompleter = null;
    _analysisCompleteCompleter = null;
    _expectedPostId = null;
    _didSubscribed = false;
  }
}
