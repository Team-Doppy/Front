import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/utils/format_utils.dart';

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
    if (!mounted) return;

    final url = widget.post.thumbnailImageUrl.toLowerCase();
    _isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.contains('/videos/') ||
        url.contains('video');

    if (_isVideo && widget.post.thumbnailImageUrl.isNotEmpty) {
      _currentVideoUrl = widget.post.thumbnailImageUrl;

      try {
        _videoController = VideoCacheService().getOrCreateController(
          _currentVideoUrl!,
          namespace: 'profile',
        );

        // 이미 초기화된 경우 바로 재생, 아니면 리스너 등록 후 재생
        if (_videoController != null && _videoController!.value.isInitialized) {
          if (mounted) {
            try {
              _videoController!.setVolume(0);
              _videoController!.setLooping(true);
              _videoController!.play();
              setState(() {});
            } catch (e) {
              debugPrint('[ImageView] 비디오 재생 오류: $e');
            }
          }
        } else if (_videoController != null) {
          _videoController!.addListener(_onVideoInitialized);
        }
      } catch (e) {
        debugPrint('[ImageView] 비디오 컨트롤러 생성 오류: $e');
        _videoController = null;
        _currentVideoUrl = null;
      }
    }
  }

  void _onVideoInitialized() {
    if (!mounted) {
      _videoController?.removeListener(_onVideoInitialized);
      return;
    }

    if (_videoController?.value.isInitialized ?? false) {
      _videoController?.removeListener(_onVideoInitialized);
      try {
        if (_videoController != null && mounted) {
          _videoController!.setVolume(0);
          _videoController!.setLooping(true);
          _videoController!.play();
          setState(() {});
        }
      } catch (e) {
        debugPrint('[ImageView] 비디오 초기화 후 재생 오류: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 취소/해제 레이스로 캐시 컨트롤러가 사라졌다면 한 번만 안전 재획득
    if (_isVideo && _currentVideoUrl != null && _videoController == null) {
      try {
        final cache = VideoCacheService();
        if (cache.hasController(_currentVideoUrl!, namespace: 'profile')) {
          _videoController = cache.getOrCreateController(
            _currentVideoUrl!,
            namespace: 'profile',
          );
        }
      } catch (e) {
        debugPrint('[ImageView] build에서 컨트롤러 재획득 오류: $e');
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
                            key: ValueKey(
                              '${widget.post.thumbnailImageUrl}-${theme.brightness}',
                            ),
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
                                (context, url, error) => Builder(
                                  builder: (context) => ImageErrorPlaceholder(),
                                ),
                          ),
                ),
                // 좋아요와 조회수 (내 피드일 때만)
                if (widget.showViewCount)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            widget.post.accessLevel == AccessLevel.private
                                ? 6
                                : (widget.post.viewCount > 9 ? 4 : 8),
                        vertical:
                            widget.post.accessLevel == AccessLevel.private
                                ? 6
                                : 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.post.accessLevel == AccessLevel.private)
                            SvgPicture.asset(
                              'assets/icons/lock.svg',
                              width: 14,
                              height: 14,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            )
                          else
                            Text(
                              formatViewCount(widget.post.viewCount),
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
