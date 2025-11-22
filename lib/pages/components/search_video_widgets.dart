import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';

/// 썸네일 비디오 플레이어
class ThumbnailVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double width;
  final double height;

  const ThumbnailVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.width,
    required this.height,
  });

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
      _disposeVideo();
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint('[ThumbnailVideoPlayer] 초기화 시작: ${widget.videoUrl}');

      // 🎯 VideoCacheService에서 컨트롤러 가져오기 (프리로드)
      _controller = VideoCacheService().getOrCreateController(
        widget.videoUrl,
        namespace: 'search_trending',
      );

      // 이미 초기화된 경우
      if (_controller!.value.isInitialized) {
        debugPrint('[ThumbnailVideoPlayer] 초기화 완료 (캐시에서)');
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          // 🎯 음소거 및 자동 재생
          await _controller!.setVolume(0.0);
          await _controller!.setLooping(true);
          await _controller!.play();
          debugPrint('[ThumbnailVideoPlayer] 재생 시작');
        }
      } else {
        // 초기화 대기
        _controller!.addListener(_onVideoInitialized);
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

  void _onVideoInitialized() {
    if (_controller?.value.isInitialized ?? false) {
      _controller?.removeListener(_onVideoInitialized);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // 🎯 음소거 및 자동 재생
        _controller!.setVolume(0.0);
        _controller!.setLooping(true);
        _controller!.play();
        debugPrint('[ThumbnailVideoPlayer] 재생 시작');
      }
    }
  }

  void _disposeVideo() {
    _controller?.removeListener(_onVideoInitialized);
    if (_controller != null) {
      VideoCacheService().releaseController(
        widget.videoUrl,
        namespace: 'search_trending',
      );
      _controller = null;
    }
  }

  @override
  void dispose() {
    debugPrint('[ThumbnailVideoPlayer] dispose - ${widget.videoUrl}');
    _disposeVideo();
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
    // 🎯 VideoCacheService에서 컨트롤러 가져오기 (프리로드)
    _videoController = VideoCacheService().getOrCreateController(
      widget.videoUrl,
      namespace: 'search_background',
    );

    // 이미 초기화된 경우
    if (_videoController!.value.isInitialized) {
      setState(() {
        _isInitialized = true;
      });
      // 첫 프레임에서 멈춤 (배경으로 사용)
      _videoController!.seekTo(Duration.zero);
      _videoController!.pause();
      _videoController!.setVolume(0);
    } else {
      // 초기화 대기
      _videoController!.addListener(_onVideoInitialized);
    }
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
      VideoCacheService().releaseController(
        widget.videoUrl,
        namespace: 'search_background',
      );
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
