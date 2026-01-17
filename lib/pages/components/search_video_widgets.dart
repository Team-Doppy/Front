import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
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

      // 🎯 표준 방식: 직접 컨트롤러 생성
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: const {'Accept': 'video/*', 'Connection': 'keep-alive'},
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // 리스너 추가
      _controller!.addListener(_onVideoInitialized);

      // 초기화 시작
      await _controller!.initialize();

      if (mounted && _controller != null) {
        setState(() {
          _isInitialized = true;
        });
        // 🎯 음소거 및 자동 재생
        await _controller!.setVolume(0.0);
        await _controller!.setLooping(true);
        await _controller!.play();
        debugPrint('[ThumbnailVideoPlayer] 재생 시작');
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
      try {
        if (_controller!.value.isInitialized) {
          _controller!.pause();
        }
        _controller!.dispose();
      } catch (e) {
        debugPrint('[ThumbnailVideoPlayer] dispose 오류: $e');
      }
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
