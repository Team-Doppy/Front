import 'package:flutter/material.dart';
import 'package:doppy/editor/service/post_reader_service.dart';

class _PendingPreloadRequest {
  const _PendingPreloadRequest({
    required this.content,
    required this.context,
    required this.mounted,
    required this.onProgress,
  });

  final Map<String, dynamic> content;
  final BuildContext context;
  final bool Function() mounted;
  final void Function(int imageCount, int videoCount)? onProgress;
}

/// 🎯 스크롤 기반 비동기 프리로드 관리 서비스
/// PostReaderScreen의 프리로드 로직을 분리하여 관리
class PostReaderScrollPreloadService {
  final PostReaderService _postReaderService = PostReaderService();

  // 프리로드 상태 관리
  int _lastPreloadedMediaNodeIndex =
      3; // 마지막으로 프리로드한 미디어 노드 인덱스 (상위 3개는 동기 프리로드됨)
  bool _isPreloading = false; // 현재 프리로드 중인지 여부 (중복 방지)
  int _preloadOp = 0; // dispose 시 프리로드 중단 토큰
  DateTime? _lastPreloadTriggerTime; // 🎯 마지막 프리로드 트리거 시간 (throttling용)
  static const int _preloadBatchSize = 3; // 🎯 한 번에 프리로드할 미디어 노드 개수 (몰림 완화)
  static const int _maxImagesPerPreloadBatch = 4; // 🎯 UI 끊김 방지용 이미지 상한 (몰림 완화)
  static const Duration _initialAsyncPreloadDelay = Duration(
    milliseconds: 250,
  ); // 🎯 첫 프레임 이후에도 약간 양보 (로딩 애니메이션 안정화)
  static const Duration _preloadThrottleDuration = Duration(
    milliseconds: 500,
  ); // 🎯 프리로드 트리거 최소 간격
  bool _initialAsyncPreloadUnblocked = false;
  bool _initialAsyncPreloadScheduled = false;
  _PendingPreloadRequest? _pendingInitialRequest;

  /// 마지막 프리로드한 미디어 노드 인덱스 가져오기
  int get lastPreloadedMediaNodeIndex => _lastPreloadedMediaNodeIndex;

  /// 현재 프리로드 중인지 여부
  bool get isPreloading => _isPreloading;

  /// 프리로드 상태 초기화 (상위 3개는 동기 프리로드됨)
  void reset() {
    _lastPreloadedMediaNodeIndex = 3;
    _isPreloading = false;
    _preloadOp = 0;
    _lastPreloadTriggerTime = null;
    _initialAsyncPreloadUnblocked = false;
    _initialAsyncPreloadScheduled = false;
    _pendingInitialRequest = null;
  }

  /// dispose 시 호출 (모든 프리로드 중단)
  void dispose() {
    _preloadOp++;
    _isPreloading = false;
    _pendingInitialRequest = null;
  }

  /// 🎯 다음 미디어 배치를 비동기로 프리로드 (loadmore 방식)
  ///
  /// [content] 포스트 컨텐츠 데이터
  /// [context] BuildContext (mounted 체크용)
  /// [mounted] 위젯이 마운트되어 있는지 여부
  /// [onProgress] 프리로드 진행 상황 콜백 (선택적)
  void preloadNextBatch({
    required Map<String, dynamic> content,
    required BuildContext context,
    required bool Function() mounted,
    void Function(int imageCount, int videoCount)? onProgress,
  }) {
    // 🎯 첫 프레임(및 약간의 딜레이) 이후에만 "비동기" 프리로드를 시작해서
    // 로딩 UI(스피너) 초기 애니메이션과 프리캐시 디코딩 폭주가 겹치는 걸 피한다.
    if (!_initialAsyncPreloadUnblocked) {
      _pendingInitialRequest = _PendingPreloadRequest(
        content: content,
        context: context,
        mounted: mounted,
        onProgress: onProgress,
      );

      if (!_initialAsyncPreloadScheduled) {
        _initialAsyncPreloadScheduled = true;
        final int op = _preloadOp;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // reset/dispose로 op가 바뀌었거나 이미 언블록된 경우는 무시
          if (op != _preloadOp) return;
          await Future<void>.delayed(_initialAsyncPreloadDelay);
          if (op != _preloadOp) return;

          _initialAsyncPreloadUnblocked = true;
          _initialAsyncPreloadScheduled = false;

          final req = _pendingInitialRequest;
          _pendingInitialRequest = null;
          if (req == null) return;
          if (!req.mounted()) return;

          // 언블록 이후 실제 프리로드 실행
          preloadNextBatch(
            content: req.content,
            context: req.context,
            mounted: req.mounted,
            onProgress: req.onProgress,
          );
        });
      }
      return;
    }

    if (_isPreloading) return; // 이미 프리로드 중이면 스킵
    if (content['nodes'] == null) return;

    // 🎯 Throttling: 너무 자주 트리거되지 않도록 제한
    final now = DateTime.now();
    if (_lastPreloadTriggerTime != null &&
        now.difference(_lastPreloadTriggerTime!) < _preloadThrottleDuration) {
      // 🎯 throttling 로그
      debugPrint(
        '⏸️  [프리로드 스킵] 너무 자주 트리거됨 (${now.difference(_lastPreloadTriggerTime!).inMilliseconds}ms 전)',
      );
      return;
    }

    final int op = ++_preloadOp;
    _isPreloading = true;
    _lastPreloadTriggerTime = now;

    // 🎯 dispose 체크: Future.microtask 전에 먼저 확인
    if (!mounted() || op != _preloadOp) {
      _isPreloading = false;
      return;
    }

    // UI를 막지 않도록 백그라운드에서만 실행
    Future.microtask(() async {
      try {
        // 🎯 dispose 체크: Future.microtask 실행 후에도 다시 확인
        if (!mounted() || op != _preloadOp) {
          _isPreloading = false;
          return;
        }

        // 🎯 마지막 프리로드한 미디어 노드 다음부터 배치 크기만큼 추출
        final nextBatchUrls = _extractNextMediaBatch(
          content,
          startMediaNodeIndex: _lastPreloadedMediaNodeIndex,
          batchSize: _preloadBatchSize,
        );

        final imagesToPreloadAll = nextBatchUrls['images'] ?? [];
        final imagesToPreload = imagesToPreloadAll
            .take(_maxImagesPerPreloadBatch)
            .toList(growable: false);
        final skippedImages =
            imagesToPreloadAll.length - imagesToPreload.length;
        final clipsToPreload = nextBatchUrls['clips'] ?? [];

        if (imagesToPreload.isEmpty && clipsToPreload.isEmpty) {
          _isPreloading = false;
          return; // 프리로드할 미디어 없음
        }

        // 🎯 눈에 잘 띄는 프리로드 시작 로그
        debugPrint('');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
        debugPrint('🚀 [프리로드 시작] 다음 배치 미디어 프리로드');
        debugPrint(
          '   📸 이미지: ${imagesToPreload.length}개'
          '${skippedImages > 0 ? " (상한으로 ${skippedImages}개 스킵)" : ""}',
        );
        debugPrint('   🎬 비디오: ${clipsToPreload.length}개');
        debugPrint(
          '   📍 미디어 노드: ${_lastPreloadedMediaNodeIndex + 1}~${_lastPreloadedMediaNodeIndex + _preloadBatchSize}',
        );
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
        debugPrint('');

        // 진행 상황 콜백
        onProgress?.call(imagesToPreload.length, clipsToPreload.length);

        // 🎯 이미지와 비디오를 병렬로 프리로드
        final futures = <Future>[];

        // 이미지 프리로드
        if (imagesToPreload.isNotEmpty) {
          // 🎯 context.mounted 체크를 Future 내부에서 수행
          if (!context.mounted) {
            _isPreloading = false;
            return;
          }
          futures.add(
            _postReaderService
                .preloadImages(
                  context,
                  imagesToPreload,
                  maxCount: imagesToPreload.length,
                  shouldContinue: () => mounted() && op == _preloadOp,
                )
                .catchError((e) {
                  debugPrint('[ScrollPreload] 이미지 프리로드 실패: $e');
                }),
          );
        }

        // 비디오 프리로드 (순차 실행)
        if (clipsToPreload.isNotEmpty) {
          futures.add(
            Future(() async {
              for (final url in clipsToPreload) {
                // 🎯 중단 체크: dispose 후에는 프리로드 중단
                if (!mounted() || op != _preloadOp) {
                  debugPrint('🛑 [프리로드 중단] 비디오 프리로드 중단: dispose됨');
                  return;
                }

                try {
                  await PostReaderService.preloadVideoForReader(url);
                } catch (e) {
                  debugPrint('[ScrollPreload] 비디오 프리로드 실패: $url - $e');
                  // 개별 실패는 무시하고 계속 진행
                }
              }
            }),
          );
        }

        // 🎯 병렬 실행 (이미지와 비디오 동시에) - 중단 가능하게
        // Future.wait는 중단 불가능하므로, 각 Future를 개별적으로 체크하면서 실행
        for (final future in futures) {
          // 🎯 dispose 체크: 각 Future 전에 중단 확인
          if (!mounted() || op != _preloadOp) {
            debugPrint('🛑 [프리로드 중단] dispose됨 - 진행 중인 작업 취소');
            _isPreloading = false;
            return;
          }
          try {
            await future;
          } catch (e) {
            debugPrint('[ScrollPreload] 프리로드 Future 실패: $e');
            // 개별 실패는 무시하고 계속 진행
          }
        }

        // 🎯 최종 dispose 체크: 모든 Future 완료 후에도 유효한지 확인
        if (!mounted() || op != _preloadOp) {
          debugPrint('⚠️  [프리로드 취소] 완료 후 dispose됨 - 상태 업데이트 스킵');
          _isPreloading = false;
          return;
        }

        // 🎯 프리로드 완료: 다음 배치 시작 인덱스 업데이트 (dispose 체크 후에만)
        _lastPreloadedMediaNodeIndex += _preloadBatchSize;

        // 🎯 눈에 잘 띄는 프리로드 완료 로그
        debugPrint('');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
        debugPrint('✅ [프리로드 완료] 다음 배치 미디어 프리로드 완료');
        debugPrint('   📸 이미지: ${imagesToPreload.length}개');
        debugPrint('   🎬 비디오: ${clipsToPreload.length}개');
        debugPrint('   📍 다음 시작: 미디어 노드 ${_lastPreloadedMediaNodeIndex + 1}');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
        debugPrint('');
      } catch (e) {
        debugPrint('[ScrollPreload] 프리로드 중 오류: $e');
      } finally {
        _isPreloading = false;
      }
    });
  }

  /// 🎯 다음 미디어 배치의 URL 추출 (순차적)
  Map<String, List<String>> _extractNextMediaBatch(
    Map<String, dynamic> content, {
    required int startMediaNodeIndex,
    required int batchSize,
  }) {
    final List<String> imageUrls = [];
    final List<String> clipUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];

    int currentMediaNodeIndex = 0;
    int foundMediaNodeCount = 0;

    for (int i = 0; i < nodes.length; i++) {
      final raw = nodes[i];
      if (raw is! Map) continue;

      final m = raw.cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();
      final data = (m['data'] as Map?)?.cast<String, dynamic>();

      bool isMediaNode = false;

      // 이미지 노드 처리
      if (type == 'image' || type == 'img' || type == 'single_image') {
        isMediaNode = true;
        final url = (m['url'] ?? data?['url'] ?? '').toString();
        if (url.isNotEmpty && url.startsWith('http')) {
          imageUrls.add(url);
        }
      } else if (type == 'imageRow' ||
          type == 'image_row' ||
          type == 'row_image') {
        isMediaNode = true;
        final rawUrls =
            (m['urls'] as List?) ?? (data?['urls'] as List?) ?? const [];
        for (final u in rawUrls) {
          final url = (u ?? '').toString();
          if (url.isNotEmpty && url.startsWith('http')) {
            imageUrls.add(url);
          }
        }
      } else if (type == 'pageViewImage' ||
          type == 'page_view_image' ||
          type == 'pageviewImage') {
        isMediaNode = true;
        final rawUrls = (m['imageUrls'] as List?) ?? const [];
        for (final u in rawUrls) {
          final url = (u ?? '').toString();
          if (url.isNotEmpty && url.startsWith('http')) {
            imageUrls.add(url);
          }
        }
      }
      // 비디오 노드 처리
      else if (type == 'clip' || type == 'video') {
        isMediaNode = true;
        final url = (data?['url'] ?? m['url'] ?? '').toString();
        if (url.isNotEmpty && url.startsWith('http')) {
          clipUrls.add(url);
        }
      }

      if (isMediaNode) {
        // 🎯 startMediaNodeIndex 이후의 미디어 노드만 추출
        if (currentMediaNodeIndex >= startMediaNodeIndex) {
          foundMediaNodeCount++;
          if (foundMediaNodeCount > batchSize) {
            break; // 배치 크기만큼 추출 완료
          }
        }
        currentMediaNodeIndex++;
      }
    }

    return {'images': imageUrls, 'clips': clipUrls};
  }
}
