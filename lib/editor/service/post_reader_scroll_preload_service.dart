import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../editor/data/draft.dart';

/// 스크롤 기반 비동기 프리로드 관리 서비스
/// DraftData 기반으로 작동하며, 문서 내용을 스크롤에 맞춰 효율적으로 프리로드합니다.
class PostReaderScrollPreloadService {
  // 프리로드 상태
  int _lastPreloadedMediaNodeIndex = 3;
  bool _isPreloading = false;
  int _preloadOp = 0;
  DateTime? _lastPreloadTriggerTime;

  // 설정
  static const int _preloadBatchSize = 3;
  static const int _maxImagesPerBatch = 4;
  static const int _maxVideosPerBatch = 2;
  static const Duration _throttleDuration = Duration(milliseconds: 300);

  int get lastPreloadedMediaNodeIndex => _lastPreloadedMediaNodeIndex;
  bool get isPreloading => _isPreloading;

  /// 상태 초기화
  void reset() {
    _lastPreloadedMediaNodeIndex = 3;
    _isPreloading = false;
    _preloadOp = 0;
    _lastPreloadTriggerTime = null;
  }

  /// 진입 시 초기 프리로드 (첫 화면 미디어부터 배치 단위로 로드)
  /// 완료 시 Future가 끝나며, 이후 스크롤 시 preloadNextBatch로 이어서 호출하면 됨.
  Future<void> preloadInitialBatch({
    required DraftData draft,
    required BuildContext context,
    required bool Function() mounted,
    void Function(int imageCount, int videoCount)? onProgress,
  }) async {
    _lastPreloadedMediaNodeIndex = 0;
    _lastPreloadTriggerTime = null;
    await preloadNextBatch(
      draft: draft,
      context: context,
      mounted: mounted,
      onProgress: onProgress,
    );
  }

  /// dispose 시 호출
  void dispose() {
    _preloadOp++;
    _isPreloading = false;
  }

  /// 다음 배치 프리로드 (스크롤 시 호출 또는 초기 배치 후 이어서 호출)
  /// 초기 진입 시에는 [preloadInitialBatch]를 먼저 호출하면 됨.
  Future<void> preloadNextBatch({
    required DraftData draft,
    required BuildContext context,
    required bool Function() mounted,
    void Function(int imageCount, int videoCount)? onProgress,
  }) async {
    if (_isPreloading) return;

    // Throttling (스크롤 트리거 시에만; 초기 배치는 _lastPreloadTriggerTime null이라 통과)
    final now = DateTime.now();
    if (_lastPreloadTriggerTime != null &&
        now.difference(_lastPreloadTriggerTime!) < _throttleDuration) {
      return;
    }

    final int op = ++_preloadOp;
    _isPreloading = true;
    _lastPreloadTriggerTime = now;

    if (!mounted() || op != _preloadOp) {
      _isPreloading = false;
      return;
    }

    Map<String, dynamic> content;
    try {
      content = json.decode(draft.content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ScrollPreload] Content 파싱 실패: $e');
      _isPreloading = false;
      return;
    }

    try {
      if (!mounted() || op != _preloadOp) {
        _isPreloading = false;
        return;
      }

      final mediaUrls = _extractMediaUrls(
        content,
        startIndex: _lastPreloadedMediaNodeIndex,
        batchSize: _preloadBatchSize,
      );

      final images =
          mediaUrls['images']
              ?.take(_maxImagesPerBatch)
              .toList(growable: false) ??
          <String>[];
      final videos =
          mediaUrls['videos']
              ?.take(_maxVideosPerBatch)
              .toList(growable: false) ??
          <String>[];

      if (images.isEmpty && videos.isEmpty) {
        _isPreloading = false;
        return;
      }

      onProgress?.call(images.length, videos.length);

      final futures = <Future>[];

      if (images.isNotEmpty && context.mounted) {
        futures.add(_preloadImages(context, images, mounted, op));
      }
      if (videos.isNotEmpty) {
        futures.add(_preloadVideos(videos, mounted, op));
      }

      if (futures.isNotEmpty) {
        if (!mounted() || op != _preloadOp) {
          _isPreloading = false;
          return;
        }
        await Future.wait(futures, eagerError: false);
      }

      if (!mounted() || op != _preloadOp) {
        _isPreloading = false;
        return;
      }

      _lastPreloadedMediaNodeIndex += _preloadBatchSize;
    } catch (e) {
      debugPrint('[ScrollPreload] 프리로드 오류: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// 이미지 프리로드
  Future<void> _preloadImages(
    BuildContext context,
    List<String> urls,
    bool Function() mounted,
    int op,
  ) async {
    for (final url in urls) {
      if (!mounted() || op != _preloadOp) return;
      if (!context.mounted) return;

      try {
        await precacheImage(NetworkImage(url), context);
      } catch (e) {
        debugPrint('[ScrollPreload] 이미지 프리로드 실패: $url - $e');
      }
    }
  }

  /// 비디오 프리로드 (메타데이터만 로드)
  Future<void> _preloadVideos(
    List<String> urls,
    bool Function() mounted,
    int op,
  ) async {
    for (final url in urls) {
      if (!mounted() || op != _preloadOp) return;

      try {
        // 비디오는 HTTP HEAD 요청으로 메타데이터만 확인
        final client = HttpClient();
        try {
          final request = await client.headUrl(Uri.parse(url));
          await request.close();
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('[ScrollPreload] 비디오 프리로드 실패: $url - $e');
      }
    }
  }

  /// 미디어 URL 추출
  Map<String, List<String>> _extractMediaUrls(
    Map<String, dynamic> content, {
    required int startIndex,
    required int batchSize,
  }) {
    final imageUrls = <String>[];
    final videoUrls = <String>[];
    final nodes = (content['nodes'] as List?) ?? [];

    int mediaNodeIndex = 0;
    int foundCount = 0;

    for (final node in nodes) {
      if (node is! Map) continue;

      final data = node.cast<String, dynamic>();
      final type = (data['type'] ?? '').toString().toLowerCase();
      final nodeData = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};

      bool isMedia = false;

      // 이미지 노드
      if (type == 'image' || type == 'img' || type == 'single_image') {
        isMedia = true;
        final url = (data['url'] ?? nodeData['url'] ?? '').toString();
        if (_isValidUrl(url)) imageUrls.add(url);
      } else if (type == 'imagerow' ||
          type == 'image_row' ||
          type == 'row_image') {
        isMedia = true;
        final urls =
            (data['urls'] as List?) ?? (nodeData['urls'] as List?) ?? [];
        for (final u in urls) {
          final url = u.toString();
          if (_isValidUrl(url)) imageUrls.add(url);
        }
      } else if (type == 'pageviewimage' ||
          type == 'page_view_image' ||
          type == 'pageviewimage') {
        isMedia = true;
        final urls = (data['imageUrls'] as List?) ?? [];
        for (final u in urls) {
          final url = u.toString();
          if (_isValidUrl(url)) imageUrls.add(url);
        }
      }
      // 비디오 노드
      else if (type == 'clip' || type == 'video') {
        isMedia = true;
        final url = (nodeData['url'] ?? data['url'] ?? '').toString();
        if (_isValidUrl(url)) videoUrls.add(url);
      }

      if (isMedia) {
        if (mediaNodeIndex >= startIndex) {
          foundCount++;
          if (foundCount > batchSize) break;
        }
        mediaNodeIndex++;
      }
    }

    return {'images': imageUrls, 'videos': videoUrls};
  }

  /// 유효한 URL인지 확인
  bool _isValidUrl(String url) {
    return url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://'));
  }

  /// 첫 배치(초기 화면) 네트워크 이미지 URL 목록.
  /// 로딩 스킵 여부 판단용(페이로드 없음 체크·디스크 캐시 체크).
  List<String> getInitialBatchImageUrls(DraftData draft) {
    try {
      final content = json.decode(draft.content) as Map<String, dynamic>;
      final mediaUrls = _extractMediaUrls(
        content,
        startIndex: 0,
        batchSize: _preloadBatchSize,
      );
      final list = mediaUrls['images'] ?? <String>[];
      return list.take(_maxImagesPerBatch).toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }
}
