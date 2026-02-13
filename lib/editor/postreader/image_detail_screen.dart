import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import '../utils/edit_image_cache_manager.dart';

/// URL이 비디오인지 확장자로 판별
bool _isVideoUrl(String url) {
  final path = url.split('?').first.toLowerCase();
  return path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm');
}

/// 이미지/영상 자세히 보기 풀스크린 화면.
/// - 이미지: CachedNetworkImage(캐시 활용) 또는 FileImage 사용
/// - 영상: VideoPlayer + 하단 시킹바
class ImageDetailScreen extends StatefulWidget {
  const ImageDetailScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  /// 이미지 또는 영상 URL 목록 (확장자로 타입 판별)
  final List<String> imageUrls;
  final int initialIndex;

  static Future<void> push(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return Future.value();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ImageDetailScreen(
          imageUrls: imageUrls,
          initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
        ),
      ),
    );
  }

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final url = widget.imageUrls[index];
              if (_isVideoUrl(url)) {
                return _VideoDetailPage(url: url);
              }
              return _ImageDetailPage(url: url);
            },
          ),
          Positioned(
            top: safePadding.top + 8,
            left: 16,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              top: safePadding.top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 이미지 상세 페이지 - CachedNetworkImage로 캐시된 이미지 그대로 사용
class _ImageDetailPage extends StatelessWidget {
  const _ImageDetailPage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isNetwork = url.startsWith('http://') || url.startsWith('https://');

    Widget child;
    if (isNetwork) {
      child = CachedNetworkImage(
        imageUrl: url,
        cacheKey: url,
        cacheManager: EditImageCacheManager.instance,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.error_outline, color: Colors.white54, size: 48),
        ),
      );
    } else {
      final path = url.startsWith('file://')
          ? url.replaceFirst('file://', '')
          : url;
      child = Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.error_outline, color: Colors.white54, size: 48),
        ),
      );
    }

    return PhotoView.customChild(
      childSize: Size(size.width, size.height),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4.0,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      child: SizedBox(width: size.width, height: size.height, child: child),
    );
  }
}

/// 영상 상세 페이지 - VideoPlayer + 하단 시킹바
class _VideoDetailPage extends StatefulWidget {
  const _VideoDetailPage({required this.url});

  final String url;

  @override
  State<_VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<_VideoDetailPage> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final isNetwork =
        widget.url.startsWith('http://') || widget.url.startsWith('https://');
    final VideoPlayerController c;
    if (isNetwork) {
      c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );
    } else {
      final path = widget.url.startsWith('file://')
          ? widget.url.replaceFirst('file://', '')
          : widget.url;
      c = VideoPlayerController.file(
        File(path),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );
    }
    await c.initialize();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() => _controller = c);
    await c.setVolume(1.0);
    await c.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    final safePadding = MediaQuery.paddingOf(context);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: safePadding.bottom + 16,
            top: 8,
          ),
          child: _VideoSeekBar(controller: _controller!),
        ),
      ],
    );
  }
}

/// 영상 시킹바 (재생/일시정지 + 프로그레스)
class _VideoSeekBar extends StatefulWidget {
  const _VideoSeekBar({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<_VideoSeekBar> {
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void didUpdateWidget(_VideoSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onUpdate);
      widget.controller.addListener(_onUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!_isDragging && mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.controller.value.position;
    final dur = widget.controller.value.duration;
    final totalMs = dur.inMilliseconds;
    final currentMs = pos.inMilliseconds;
    final progress = totalMs > 0 ? currentMs / totalMs : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white38,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            value: _isDragging ? _dragValue : progress.clamp(0.0, 1.0),
            onChanged: (v) {
              if (!_isDragging) {
                _dragValue = v;
                setState(() => _isDragging = true);
              }
              _dragValue = v;
              setState(() {});
            },
            onChangeEnd: (v) {
              final ms = (v * dur.inMilliseconds).round();
              widget.controller.seekTo(Duration(milliseconds: ms));
              setState(() => _isDragging = false);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(pos),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              GestureDetector(
                onTap: () {
                  if (widget.controller.value.isPlaying) {
                    widget.controller.pause();
                  } else {
                    widget.controller.play();
                  }
                  setState(() {});
                },
                child: Icon(
                  widget.controller.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              Text(
                _formatDuration(dur),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _dragValue = 0.0;
}
