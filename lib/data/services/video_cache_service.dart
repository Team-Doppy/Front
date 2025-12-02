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

  // 🎯 재사용을 막는 플래그 (피드 업데이트 중)
  bool _isReuseBlocked = false;

  String _key(String namespace, String url) => '$namespace|$url';

  /// 비디오 컨트롤러 가져오기 (없으면 생성)
  VideoPlayerController getOrCreateController(
    String url, {
    String namespace = 'global',
  }) {
    final key = _key(namespace, url);

    // 🎯 기존 컨트롤러가 있는 경우
    if (_controllers.containsKey(key)) {
      // 🎯 재사용이 막혀있으면 기존 컨트롤러를 무시하고 새로 생성
      if (_isReuseBlocked) {
        debugPrint('[VideoCache] 재사용 차단됨 - 새로 생성: $key');
        // 기존 컨트롤러는 그대로 두고 (다른 곳에서 사용 중일 수 있음)
        // 참조 카운트가 0이면 일시정지하여 안전하게 처리
        final existingController = _controllers[key];
        if (existingController != null) {
          final refCount = _refCounts[key] ?? 0;
          if (refCount == 0) {
            try {
              // dispose 여부 확인
              if (existingController.value.isInitialized) {
                if (existingController.value.isPlaying) {
                  existingController.pause();
                }
              }
            } catch (e) {
              debugPrint('[VideoCache] 재사용 차단 시 일시정지 오류: $e');
              // dispose된 컨트롤러는 맵에서 제거
              _controllers.remove(key);
              _refCounts.remove(key);
              _lastAccessed.remove(key);
            }
          }
        }
        // 아래에서 새로 생성
      } else {
        final existingController = _controllers[key];
        if (existingController == null) {
          // 다른 스레드에서 제거되었을 수 있음, 새로 생성
        } else {
          try {
            // 🎯 컨트롤러가 dispose되었거나 초기화에 실패한 경우, 새로 생성
            if (existingController.value.hasError) {
              debugPrint(
                '[VideoCache] ⚠️ 기존 컨트롤러에 에러가 있어 새로 생성: $key (에러: ${existingController.value.errorDescription})',
              );
              // 기존 컨트롤러 정리
              try {
                existingController.dispose();
              } catch (_) {}
              _controllers.remove(key);
              _refCounts.remove(key);
              _lastAccessed.remove(key);
              // 아래에서 새로 생성
            } else {
              // 정상적인 경우 재사용
              _refCounts[key] = (_refCounts[key] ?? 0) + 1;
              _lastAccessed[key] = DateTime.now(); // LRU 업데이트
              debugPrint('[VideoCache] 재사용: $key (참조: ${_refCounts[key]})');
              return existingController;
            }
          } catch (e) {
            // dispose된 컨트롤러 접근 시도
            debugPrint('[VideoCache] ⚠️ dispose된 컨트롤러 접근, 새로 생성: $key - $e');
            _controllers.remove(key);
            _refCounts.remove(key);
            _lastAccessed.remove(key);
            // 아래에서 새로 생성
          }
        }
      }
    }

    // 캐시 크기 제한 확인 - 참조 카운트가 0인 것만 정리 대상
    if (_controllers.length >= maxCacheSize) {
      _evictLeastRecentlyUsed();
    }

    // 🎯 재사용 차단 시 기존 컨트롤러가 있으면 임시 키 사용 (충돌 방지)
    final actualKey =
        _isReuseBlocked && _controllers.containsKey(key)
            ? '${key}_new_${DateTime.now().millisecondsSinceEpoch}'
            : key;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    controller
        .initialize()
        .then((_) {
          // 🎯 초기화 완료 후에도 맵에 있는지 확인 (다른 스레드에서 제거되었을 수 있음)
          if (_controllers[actualKey] == controller) {
            try {
              // 초기화만 하고, 재생/정지는 각 위젯에서 결정
              if (controller.value.isInitialized) {
                controller.setLooping(true);
                controller.setVolume(0); // 기본 음소거
                debugPrint('[VideoCache] ✅ 초기화 성공: $actualKey');
              }
            } catch (e) {
              debugPrint('[VideoCache] ⚠️ 초기화 후 설정 오류: $actualKey - $e');
              // dispose된 경우 맵에서 제거
              if (_controllers[actualKey] == controller) {
                _controllers.remove(actualKey);
                _refCounts.remove(actualKey);
                _lastAccessed.remove(actualKey);
              }
            }
          } else {
            // 다른 스레드에서 제거되었으므로 dispose
            try {
              controller.dispose();
            } catch (_) {}
            debugPrint('[VideoCache] ⚠️ 초기화 완료되었으나 맵에서 제거됨: $actualKey');
          }
        })
        .catchError((e, stackTrace) {
          // 초기화 실패 시 맵에서 제거
          if (_controllers[actualKey] == controller) {
            _controllers.remove(actualKey);
            _refCounts.remove(actualKey);
            _lastAccessed.remove(actualKey);
          }
          // dispose 시도
          try {
            controller.dispose();
          } catch (_) {}
          debugPrint('[VideoCache] ⚠️ 초기화 실패: $actualKey - $e');
        });

    _controllers[actualKey] = controller;
    _refCounts[actualKey] = 1;
    _lastAccessed[actualKey] = DateTime.now();
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
      debugPrint('[VideoCache] LRU 후보 발견(보존): $oldestUrl');
    }
  }

  /// 비디오 컨트롤러 참조 해제
  void releaseController(String url, {String namespace = 'global'}) {
    final key = _key(namespace, url);

    // 🎯 임시 키로 생성된 컨트롤러도 찾아서 해제
    final matchingKeys =
        _controllers.keys.where((k) {
          // 정확한 키 매칭 또는 임시 키 매칭 (key로 시작하는 경우)
          return k == key ||
              (k.startsWith('${key}_new_') && _refCounts[k] != null);
        }).toList();

    if (matchingKeys.isEmpty) {
      debugPrint('[VideoCache] ⚠️ 참조 해제 실패: $key (컨트롤러 없음)');
      return;
    }

    // 가장 최근에 생성된 컨트롤러부터 해제 (임시 키가 있으면 그것부터)
    matchingKeys.sort((a, b) {
      final timeA = _lastAccessed[a] ?? DateTime(1970);
      final timeB = _lastAccessed[b] ?? DateTime(1970);
      return timeB.compareTo(timeA); // 최신 것부터
    });

    for (final k in matchingKeys) {
      if (!_refCounts.containsKey(k)) continue;

      _refCounts[k] = (_refCounts[k] ?? 1) - 1;
      debugPrint('[VideoCache] 참조 해제: $k (참조: ${_refCounts[k]})');

      // 요구사항: 컨트롤러는 dispose하거나 제거하지 않는다. refCount만 0으로 유지.
      if (_refCounts[k]! < 0) _refCounts[k] = 0;

      // 참조 카운트가 0이 되면 일시정지
      if (_refCounts[k] == 0) {
        final controller = _controllers[k];
        if (controller != null && controller.value.isInitialized) {
          try {
            if (controller.value.isPlaying) {
              controller.pause();
            }
          } catch (e) {
            debugPrint('[VideoCache] 참조 해제 시 일시정지 오류 ($k): $e');
          }
        }
      }

      // 첫 번째 매칭된 키만 처리 (가장 최근 것)
      break;
    }
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

  /// 특정 namespace의 모든 컨트롤러를 일시정지한다.
  void pauseAllInNamespace(String namespace) {
    debugPrint('[VideoCache] 네임스페이스 "$namespace"의 모든 컨트롤러 일시정지 시작');
    // 🎯 맵을 복사하여 순회 중 변경 방지
    final keysToPause = List<String>.from(
      _controllers.keys.where((key) => key.startsWith('$namespace|')),
    );
    int pausedCount = 0;
    for (final key in keysToPause) {
      final controller = _controllers[key];
      if (controller != null) {
        try {
          // dispose 여부 확인
          if (controller.value.isInitialized) {
            if (controller.value.isPlaying) {
              controller.pause();
              pausedCount++;
              debugPrint('[VideoCache] 일시정지: $key');
            }
          }
        } catch (e) {
          debugPrint('[VideoCache] 일시정지 오류 ($key): $e');
          // dispose된 컨트롤러는 맵에서 제거
          if (_controllers[key] == controller) {
            _controllers.remove(key);
            _refCounts.remove(key);
            _lastAccessed.remove(key);
          }
        }
      }
    }
    debugPrint(
      '[VideoCache] 네임스페이스 "$namespace"의 모든 컨트롤러 일시정지 완료 ($pausedCount개)',
    );
  }

  /// 모든 namespace의 모든 컨트롤러를 일시정지한다.
  void pauseAll() {
    debugPrint('[VideoCache] 모든 컨트롤러 일시정지 시작 (총 ${_controllers.length}개)');
    // 🎯 맵을 복사하여 순회 중 변경 방지
    final entries = List<MapEntry<String, VideoPlayerController>>.from(
      _controllers.entries,
    );
    int pausedCount = 0;
    final keysToRemove = <String>[];

    for (final entry in entries) {
      final controller = entry.value;
      try {
        // dispose 여부 확인
        if (controller.value.isInitialized) {
          if (controller.value.isPlaying) {
            controller.pause();
            pausedCount++;
          }
        }
      } catch (e) {
        debugPrint('[VideoCache] 일시정지 오류 (${entry.key}): $e');
        // dispose된 컨트롤러는 나중에 제거
        if (_controllers[entry.key] == controller) {
          keysToRemove.add(entry.key);
        }
      }
    }

    // dispose된 컨트롤러 제거
    for (final key in keysToRemove) {
      _controllers.remove(key);
      _refCounts.remove(key);
      _lastAccessed.remove(key);
    }

    debugPrint(
      '[VideoCache] 모든 컨트롤러 일시정지 완료 ($pausedCount개, 제거: ${keysToRemove.length}개)',
    );
  }

  /// 재사용을 막는다 (피드 업데이트 중)
  void blockReuse() {
    if (_isReuseBlocked) {
      debugPrint('[VideoCache] ⚠️ 재사용 차단이 이미 활성화되어 있음');
      return;
    }
    _isReuseBlocked = true;
    debugPrint('[VideoCache] 재사용 차단 시작');

    // 🎯 모든 컨트롤러 일시정지하여 안전한 상태로 전환
    pauseAll();
  }

  /// 재사용 차단을 해제한다
  void unblockReuse() {
    if (!_isReuseBlocked) {
      debugPrint('[VideoCache] ⚠️ 재사용 차단이 이미 해제되어 있음');
      return;
    }
    _isReuseBlocked = false;
    debugPrint('[VideoCache] 재사용 차단 해제');

    // 🎯 임시 키로 생성된 컨트롤러 정리 (참조 카운트가 0인 것만)
    _cleanupTemporaryControllers();
  }

  /// 임시 키로 생성된 컨트롤러 정리
  void _cleanupTemporaryControllers() {
    final temporaryKeys =
        _controllers.keys
            .where(
              (key) => key.contains('_new_') && (_refCounts[key] ?? 0) == 0,
            )
            .toList();

    if (temporaryKeys.isEmpty) return;

    debugPrint('[VideoCache] 임시 컨트롤러 정리 시작: ${temporaryKeys.length}개');
    for (final key in temporaryKeys) {
      final controller = _controllers[key];
      if (controller != null) {
        try {
          if (controller.value.isInitialized) {
            controller.pause();
          }
          // 참조 카운트가 0이므로 dispose 가능
          controller.dispose();
        } catch (e) {
          debugPrint('[VideoCache] 임시 컨트롤러 정리 오류 ($key): $e');
        }
      }
      _controllers.remove(key);
      _refCounts.remove(key);
      _lastAccessed.remove(key);
    }
    debugPrint('[VideoCache] 임시 컨트롤러 정리 완료');
  }

  /// 모든 컨트롤러 정리 (앱 종료 시)
  void disposeAll() {
    debugPrint('[VideoCache] 모든 컨트롤러 dispose (총 ${_controllers.length}개)');
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _refCounts.clear();
  }

  /// 캐시 상태 디버깅
  void printCacheStatus() {
    debugPrint('[VideoCache] ===== 캐시 상태 =====');
    debugPrint('[VideoCache] 총 컨트롤러 개수: ${_controllers.length}');
    for (final key in _controllers.keys) {
      final isInit = _controllers[key]?.value.isInitialized ?? false;
      final refCount = _refCounts[key] ?? 0;
      debugPrint('[VideoCache] - $key: 초기화=$isInit, 참조=$refCount');
    }
    debugPrint('[VideoCache] ====================');
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
      debugPrint(
        '[VideoMuteService] 피드 음소거 상태 변경: ${_isFeedMuted ? "음소거" : "소리 켜짐"}',
      );
      notifyListeners();
    }
  }

  void setReaderMuted(bool muted) {
    if (_isReaderMuted != muted) {
      _isReaderMuted = muted;
      debugPrint(
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
