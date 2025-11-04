import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ImageView extends StatefulWidget {
  const ImageView({
    super.key,
    required this.post,
    this.isFirst = false,
    this.isLast = false,
    this.showViewCount = false,
  });
  final PostData post;
  final bool isFirst;
  final bool isLast;
  final bool showViewCount;

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  String? _currentVideoUrl; // 현재 사용 중인 비디오 URL

  @override
  void initState() {
    super.initState();
    _checkIfVideo();
  }

  @override
  void didUpdateWidget(ImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 포스트가 변경되었을 때 비디오 컨트롤러 재초기화
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.thumbnailImageUrl != widget.post.thumbnailImageUrl) {
      _releaseVideoController();
      _checkIfVideo();
    }
  }

  @override
  void dispose() {
    _releaseVideoController();
    super.dispose();
  }

  void _releaseVideoController() {
    if (_currentVideoUrl != null) {
      VideoCacheService().releaseController(
        _currentVideoUrl!,
        namespace: 'profile',
      );
      _currentVideoUrl = null;
      _videoController = null;
    }
  }

  void _checkIfVideo() {
    final url = widget.post.thumbnailImageUrl.toLowerCase();
    _isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.contains('/videos/') ||
        url.contains('video');

    if (_isVideo) {
      _currentVideoUrl = widget.post.thumbnailImageUrl;
      _videoController = VideoCacheService().getOrCreateController(
        _currentVideoUrl!,
        namespace: 'profile',
      );

      // 이미 초기화된 경우 바로 재생, 아니면 리스너 등록 후 재생
      if (_videoController!.value.isInitialized) {
        _videoController!.setVolume(0);
        _videoController!.setLooping(true);
        _videoController!.play();
        if (mounted) setState(() {});
      } else {
        _videoController!.addListener(_onVideoInitialized);
      }
    }
  }

  void _onVideoInitialized() {
    if (_videoController?.value.isInitialized ?? false) {
      _videoController?.removeListener(_onVideoInitialized);
      try {
        _videoController?.setVolume(0);
        _videoController?.setLooping(true);
        _videoController?.play();
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 취소/해제 레이스로 캐시 컨트롤러가 사라졌다면 한 번만 안전 재획득
    if (_isVideo && _currentVideoUrl != null) {
      final cache = VideoCacheService();
      if (!cache.hasController(_currentVideoUrl!, namespace: 'profile')) {
        _videoController = cache.getOrCreateController(
          _currentVideoUrl!,
          namespace: 'profile',
        );
      }
    }
    final theme = Theme.of(context);
    return widget.post.id == 'padding'
        ? Container(width: 80, height: 180, color: theme.colorScheme.background)
        : Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: widget.isFirst ? const Radius.circular(12) : Radius.zero,
              bottomLeft:
                  widget.isFirst ? const Radius.circular(12) : Radius.zero,
              topRight: widget.isLast ? const Radius.circular(12) : Radius.zero,
              bottomRight:
                  widget.isLast ? const Radius.circular(12) : Radius.zero,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: widget.isFirst ? const Radius.circular(12) : Radius.zero,
              bottomLeft:
                  widget.isFirst ? const Radius.circular(12) : Radius.zero,
              topRight: widget.isLast ? const Radius.circular(12) : Radius.zero,
              bottomRight:
                  widget.isLast ? const Radius.circular(12) : Radius.zero,
            ),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 5,
                  child:
                      _isVideo && _videoController != null
                          ? _videoController!.value.isInitialized
                              ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoController!.value.size.width,
                                  height: _videoController!.value.size.height,
                                  child: VideoPlayer(_videoController!),
                                ),
                              )
                              : Container(
                                color: theme.colorScheme.surface.withOpacity(
                                  0.1,
                                ),
                                child: const ShimmerBox(
                                  width: double.infinity,
                                  height: 180,
                                  borderRadius: BorderRadius.zero,
                                ),
                              )
                          : CachedNetworkImage(
                            imageUrl: widget.post.thumbnailImageUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 180),
                            fadeOutDuration: const Duration(milliseconds: 80),
                            fadeInCurve: Curves.easeOut,
                            placeholder:
                                (context, url) => Container(
                                  color: theme.colorScheme.surface.withOpacity(
                                    0.1,
                                  ),
                                  child: const ShimmerBox(
                                    width: double.infinity,
                                    height: 180,
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                            errorWidget:
                                (context, url, error) =>
                                    const ImageErrorPlaceholder(),
                          ),
                ),
                // 좋아요와 조회수 (내 피드일 때만)
                if (widget.showViewCount)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.post.viewCount > 9 ? 4 : 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.post.viewCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
  }
}
