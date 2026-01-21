import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/pages/components/shimmer_box.dart';

// =============================================================================
// ✅ 홈/리스트용 비디오 컨트롤러 풀 (프리로드/재사용)
// - 영상은 precacheImage로는 절대 빨라지지 않음: VideoPlayerController.initialize()가 병목
// - 같은 URL은 컨트롤러를 재사용해서 "페이지 넘김" 시 즉시 재생되도록 한다.
// =============================================================================
class _VideoControllerPool {
  static final Map<String, _VideoEntry> _entries = {};
  static const int _maxEntries = 6; // 홈에서 동시에 필요한 정도만 유지
  static bool _globalPaused = false;

  static bool get globalPaused => _globalPaused;

  /// ✅ 전역 토글: true면 풀 컨트롤러는 어떤 경우에도 play()를 시도하지 않도록 한다.
  /// (MediaPicker처럼 "다른 화면이 최상단"일 때 백그라운드 재생 방지)
  static void setGlobalPaused(bool value) {
    _globalPaused = value;
  }

  static Future<VideoPlayerController?> acquire(String url) async {
    try {
      final now = DateTime.now();

      var entry = _entries[url];
      if (entry == null) {
        // LRU 정리
        if (_entries.length >= _maxEntries) {
          _evictOne();
        }

        final controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: const {'Accept': 'video/*', 'Connection': 'keep-alive'},
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: false,
          ),
        );

        entry = _VideoEntry(controller: controller);
        _entries[url] = entry;

        entry.initFuture = controller.initialize().then((_) async {
          await controller.setVolume(0.0);
          await controller.setLooping(true);
        });
      }

      entry.refCount += 1;
      entry.lastUsed = now;
      await entry.initFuture;

      // ✅ 전역 pause 상태면: acquire 직후에도 재생되지 않도록 강제 pause
      if (_globalPaused) {
        try {
          if (entry.controller.value.isInitialized) {
            await entry.controller.pause();
            await entry.controller.setVolume(0.0);
            await entry.controller.seekTo(Duration.zero);
          }
        } catch (_) {}
      }
      return entry.controller;
    } catch (e) {
      debugPrint('[VideoControllerPool] acquire 실패: $url - $e');
      return null;
    }
  }

  static void release(String url) {
    final entry = _entries[url];
    if (entry == null) return;

    entry.refCount = (entry.refCount - 1).clamp(0, 1 << 30);
    entry.lastUsed = DateTime.now();

    // refCount 0이어도 바로 dispose하지 않고 유지 (다음 스와이프 히트용)
    // maxEntries 초과 시 LRU로 정리
    if (_entries.length > _maxEntries) {
      _evictOne();
    }
  }

  static Future<void> preload(String url) async {
    final c = await acquire(url);
    if (c != null) {
      // 첫 프레임만 잡고 멈춰두면 전환 시 체감이 좋아짐
      try {
        await c.seekTo(Duration.zero);
        await c.pause();
      } catch (_) {}
      release(url);
    }
  }

  /// ✅ 전역: 풀에 잡혀있는 모든 썸네일 비디오를 일시정지한다.
  /// - MediaPicker 등 "다른 화면 진입" 시 백그라운드 재생/리소스 사용을 막기 위함
  static Future<void> pauseAll({
    bool seekToStart = true,
    bool mute = true,
  }) async {
    final entries = _entries.values.toList();
    for (final e in entries) {
      final c = e.controller;
      try {
        if (c.value.isInitialized) {
          await c.pause();
          if (seekToStart) {
            await c.seekTo(Duration.zero);
          }
          if (mute) {
            await c.setVolume(0.0);
          }
        }
      } catch (_) {}
    }
  }

  /// ✅ 전역: 풀에 잡혀있는 모든 컨트롤러를 dispose하고 비운다.
  /// - 강제 메모리 회수/오디오 세션 정리용 (필요할 때만 호출)
  static void disposeAll() {
    final entries = _entries.values.toList();
    for (final e in entries) {
      try {
        e.controller.dispose();
      } catch (_) {}
    }
    _entries.clear();
  }

  static void _evictOne() {
    if (_entries.isEmpty) return;
    // refCount==0인 것 중 가장 오래된 것부터 제거
    final candidates =
        _entries.entries.where((e) => e.value.refCount == 0).toList();
    if (candidates.isEmpty) return;

    candidates.sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    final victim = candidates.first;
    try {
      victim.value.controller.dispose();
    } catch (_) {}
    _entries.remove(victim.key);
  }
}

class _VideoEntry {
  _VideoEntry({required this.controller});
  final VideoPlayerController controller;
  int refCount = 0;
  DateTime lastUsed = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? initFuture;
}

/// 썸네일 비디오 플레이어
class ThumbnailVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double width;
  final double height;
  final bool autoPlay;

  const ThumbnailVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.width,
    required this.height,
    this.autoPlay = true,
  });

  /// ✅ 외부에서 영상 프리로드(컨트롤러 초기화) 호출용
  static Future<void> preload(String url) => _VideoControllerPool.preload(url);

  /// ✅ 외부에서 "현재 풀에 잡힌" 썸네일 비디오 전부 일시정지 (피커 진입 등)
  static Future<void> pauseAll({bool seekToStart = true, bool mute = true}) =>
      _VideoControllerPool.pauseAll(seekToStart: seekToStart, mute: mute);

  /// ✅ 외부에서 썸네일 비디오 "전역 일시정지 상태" 토글
  static void setGlobalPaused(bool value) =>
      _VideoControllerPool.setGlobalPaused(value);

  /// ✅ 외부에서 썸네일 비디오 풀 전체 dispose
  static void disposeAllPool() => _VideoControllerPool.disposeAll();

  @override
  State<ThumbnailVideoPlayer> createState() => _ThumbnailVideoPlayerState();
}

class _ThumbnailVideoPlayerState extends State<ThumbnailVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(ThumbnailVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeVideo(oldUrl: oldWidget.videoUrl);
      _initializeVideo();
      return;
    }

    // 같은 URL인데 autoPlay만 바뀐 경우 (PageView active 전환)
    if (_controller != null && _isInitialized) {
      if (widget.autoPlay && !_VideoControllerPool.globalPaused) {
        _controller!.play();
      } else {
        _controller!.pause();
        _controller!.seekTo(Duration.zero);
      }
    }
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint('[ThumbnailVideoPlayer] 초기화 시작(acquire): ${widget.videoUrl}');

      final acquired = await _VideoControllerPool.acquire(widget.videoUrl);
      if (!mounted) return;
      if (acquired == null) {
        setState(() => _hasError = true);
        return;
      }

      _controller = acquired;
      setState(() => _isInitialized = true);

      // ✅ MediaPicker 등에서 전역 pause가 걸려있으면 play를 절대 시도하지 않는다.
      if (widget.autoPlay && !_VideoControllerPool.globalPaused) {
        await _controller!.play();
      } else {
        await _controller!.pause();
        await _controller!.seekTo(Duration.zero);
      }
    } catch (e) {
      debugPrint('[ThumbnailVideoPlayer] error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _disposeVideo({required String oldUrl}) {
    if (_controller != null) {
      try {
        if (_controller!.value.isInitialized) {
          _controller!.pause();
        }
      } catch (_) {}
      _controller = null;
    }

    // ✅ 풀에 반환 (dispose는 풀에서 LRU로 처리)
    _VideoControllerPool.release(oldUrl);
  }

  @override
  void dispose() {
    debugPrint('[ThumbnailVideoPlayer] dispose - ${widget.videoUrl}');
    _disposeVideo(oldUrl: widget.videoUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🎯 AutomaticKeepAliveClientMixin 필수

    if (_hasError) {
      return Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 40,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withOpacity(0.3),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(color: Theme.of(context).colorScheme.surfaceVariant);
    }

    // 🎯 안전 장치: 비디오 사이즈 체크
    final videoSize = _controller!.value.size;
    if (videoSize.width <= 0 || videoSize.height <= 0) {
      debugPrint('[ThumbnailVideoPlayer] ⚠️ 유효하지 않은 비디오 사이즈');
      return Container(color: Theme.of(context).colorScheme.surfaceVariant);
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: videoSize.width,
          height: videoSize.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}

/// 배경 비디오 위젯 (VideoCacheService로 프리로드) - 검색 화면용
class SearchBackgroundVideoWidget extends StatefulWidget {
  final String videoUrl;

  const SearchBackgroundVideoWidget({super.key, required this.videoUrl});

  @override
  State<SearchBackgroundVideoWidget> createState() =>
      _SearchBackgroundVideoWidgetState();
}

class _SearchBackgroundVideoWidgetState
    extends State<SearchBackgroundVideoWidget> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(SearchBackgroundVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeVideo();
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _initializeVideo() {
    // 🎯 표준 방식: 직접 컨트롤러 생성
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      httpHeaders: const {'Accept': 'video/*', 'Connection': 'keep-alive'},
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
    );

    // 리스너 추가
    _videoController!.addListener(_onVideoInitialized);

    // 초기화 시작
    _videoController!
        .initialize()
        .then((_) {
          if (mounted && _videoController != null) {
            setState(() {
              _isInitialized = true;
            });
            // 첫 프레임에서 멈춤 (배경으로 사용)
            _videoController!.seekTo(Duration.zero);
            _videoController!.pause();
            _videoController!.setVolume(0);
          }
        })
        .catchError((e) {
          debugPrint('[SearchBackgroundVideoWidget] 초기화 실패: $e');
        });
  }

  void _onVideoInitialized() {
    if (_videoController?.value.isInitialized ?? false) {
      _videoController?.removeListener(_onVideoInitialized);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // 첫 프레임에서 멈춤 (배경으로 사용)
        _videoController!.seekTo(Duration.zero);
        _videoController!.pause();
        _videoController!.setVolume(0);
      }
    }
  }

  void _disposeVideo() {
    _videoController?.removeListener(_onVideoInitialized);
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized) {
          _videoController!.pause();
        }
        _videoController!.dispose();
      } catch (e) {
        debugPrint('[SearchBackgroundVideoWidget] dispose 오류: $e');
      }
      _videoController = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _videoController == null) {
      return ShimmerBox(width: double.infinity, height: double.infinity);
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController!.value.size.width,
          height: _videoController!.value.size.height,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }
}
