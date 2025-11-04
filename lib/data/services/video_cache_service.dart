import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 비디오 플레이어 컨트롤러를 캐싱하여 재사용하는 싱글톤 서비스
class VideoCacheService {
  VideoCacheService._();
  static final VideoCacheService _instance = VideoCacheService._();
  factory VideoCacheService() => _instance;

  // 키는 "namespace|url"
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, int> _refCounts = {}; // 참조 카운트
  final Map<String, DateTime> _lastAccessed = {}; // 마지막 접근 시간 (LRU용)

  static const int maxCacheSize = 50; // 최대 캐시 크기 (10개 비디오)

  String _key(String namespace, String url) => '$namespace|$url';

  /// 비디오 컨트롤러 가져오기 (없으면 생성)
  VideoPlayerController getOrCreateController(
    String url, {
    String namespace = 'global',
  }) {
    final key = _key(namespace, url);
    if (_controllers.containsKey(key)) {
      _refCounts[key] = (_refCounts[key] ?? 0) + 1;
      _lastAccessed[key] = DateTime.now(); // LRU 업데이트
      print('[VideoCache] 재사용: $key (참조: ${_refCounts[key]})');
      return _controllers[key]!;
    }

    // 캐시 크기 제한 확인 - 참조 카운트가 0인 것만 정리 대상
    if (_controllers.length >= maxCacheSize) {
      _evictLeastRecentlyUsed();
    }

    print('[VideoCache] 새로 생성: $key');
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    controller.initialize().then((_) {
      // 초기화만 하고, 재생/정지는 각 위젯에서 결정
      controller.setLooping(true);
      controller.setVolume(0); // 기본 음소거
      // pause()를 호출하지 않음 - 각 위젯이 isVisible 상태에 따라 제어
    });

    _controllers[key] = controller;
    _refCounts[key] = 1;
    _lastAccessed[key] = DateTime.now();
    return controller;
  }

  /// LRU (Least Recently Used) 정책으로 가장 오래된 캐시 제거
  void _evictLeastRecentlyUsed() {
    // 참조 카운트가 0인 것만 제거 대상
    final candidates =
        _controllers.keys.where((url) => (_refCounts[url] ?? 0) == 0).toList();

    if (candidates.isEmpty) {
      return;
    }

    // 가장 오래 접근하지 않은 항목 찾기
    String? oldestUrl;
    DateTime? oldestTime;

    for (final url in candidates) {
      final time = _lastAccessed[url];
      if (time != null && (oldestTime == null || time.isBefore(oldestTime))) {
        oldestTime = time;
        oldestUrl = url;
      }
    }

    if (oldestUrl != null) {
      // 요구사항: 캐시 컨트롤러는 dispose하지 않는다.
      // LRU에서도 실제 dispose/remove를 수행하지 않고, 로그만 남긴다.
      print('[VideoCache] LRU 후보 발견(보존): $oldestUrl');
    }
  }

  /// 비디오 컨트롤러 참조 해제
  void releaseController(String url, {String namespace = 'global'}) {
    final key = _key(namespace, url);
    if (!_refCounts.containsKey(key)) return;

    _refCounts[key] = (_refCounts[key] ?? 1) - 1;
    print('[VideoCache] 참조 해제: $key (참조: ${_refCounts[key]})');

    // 요구사항: 컨트롤러는 dispose하거나 제거하지 않는다. refCount만 0으로 유지.
    if (_refCounts[key]! < 0) _refCounts[key] = 0;
  }

  /// 특정 URL의 컨트롤러가 초기화되었는지 확인
  bool isInitialized(String url, {String namespace = 'global'}) {
    final key = _key(namespace, url);
    return _controllers[key]?.value.isInitialized ?? false;
  }

  /// 해당 URL의 컨트롤러가 캐시에 존재하는지 여부
  bool hasController(String url, {String namespace = 'global'}) {
    final key = _key(namespace, url);
    return _controllers.containsKey(key);
  }

  /// 모든 컨트롤러 정리 (앱 종료 시)
  void disposeAll() {
    print('[VideoCache] 모든 컨트롤러 dispose (총 ${_controllers.length}개)');
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _refCounts.clear();
  }

  /// 캐시 상태 디버깅
  void printCacheStatus() {
    print('[VideoCache] ===== 캐시 상태 =====');
    print('[VideoCache] 총 컨트롤러 개수: ${_controllers.length}');
    for (final key in _controllers.keys) {
      final isInit = _controllers[key]?.value.isInitialized ?? false;
      final refCount = _refCounts[key] ?? 0;
      print('[VideoCache] - $key: 초기화=$isInit, 참조=$refCount');
    }
    print('[VideoCache] ====================');
  }
}

/// 전역 비디오 음소거 상태를 관리하는 싱글톤 서비스
class VideoMuteService extends ChangeNotifier {
  VideoMuteService._();
  static final VideoMuteService _instance = VideoMuteService._();
  factory VideoMuteService() => _instance;

  bool _isFeedMuted = true; // 홈 피드 음소거 (기본: 음소거)
  bool _isReaderMuted = true; // 포스트 읽기 음소거 (기본: 음소거)

  bool get isFeedMuted => _isFeedMuted;
  bool get isReaderMuted => _isReaderMuted;

  void setFeedMuted(bool muted) {
    if (_isFeedMuted != muted) {
      _isFeedMuted = muted;
      print(
        '[VideoMuteService] 피드 음소거 상태 변경: ${_isFeedMuted ? "음소거" : "소리 켜짐"}',
      );
      notifyListeners();
    }
  }

  void setReaderMuted(bool muted) {
    if (_isReaderMuted != muted) {
      _isReaderMuted = muted;
      print(
        '[VideoMuteService] 리더 음소거 상태 변경: ${_isReaderMuted ? "음소거" : "소리 켜짐"}',
      );
      notifyListeners();
    }
  }

  void toggleFeedMute() {
    setFeedMuted(!_isFeedMuted);
  }

  void toggleReaderMute() {
    setReaderMuted(!_isReaderMuted);
  }
}
