import 'dart:async';

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
  bool _videoGaveUp = false; // 발행 직후 등으로 초기화가 오래 걸릴 때 무한 쉬머 방지용
  Timer? _videoTimeoutTimer; // 비디오 초기화 타임아웃 타이머
  Timer? _retryTimer; // 발행 직후 처리 지연 대응용 짧은 재시도 타이머
  DateTime? _firstAttemptAt; // 최초 시도 시각 (짧은 윈도우 내 재시도 제한)
  int _retryCount = 0;

  String get _logKey => 'postId=${widget.post.id}';

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
    _videoTimeoutTimer?.cancel();
    _videoTimeoutTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_videoController != null) {
      _videoController!.removeListener(_onVideoStateChanged);
    }
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

  bool _isRecentPost({Duration window = const Duration(minutes: 3)}) {
    final createdAtStr = widget.post.createdAt.trim();
    final createdAt = DateTime.tryParse(createdAtStr);
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt).abs() <= window;
  }

  Duration _initializationTimeout() {
    // 발행 직후에는 서버/스토리지/전파 지연이 있을 수 있으니 더 길게 쉬머 유지
    return _isRecentPost()
        ? const Duration(seconds: 12)
        : const Duration(seconds: 12);
  }

  bool _canAutoRetry() {
    final now = DateTime.now();
    _firstAttemptAt ??= now;
    final elapsed = now.difference(_firstAttemptAt!);
    if (elapsed > const Duration(seconds: 15)) return false;
    return _retryCount < 2;
  }

  void _scheduleTimeoutIfNeeded() {
    _videoTimeoutTimer?.cancel();
    _videoTimeoutTimer = Timer(_initializationTimeout(), () {
      if (!mounted) return;
      if (_isVideo &&
          _videoController != null &&
          !_videoController!.value.isInitialized) {
        final hasError = _videoController?.value.hasError ?? false;
        debugPrint(
          '[ImageView] timeout $_logKey '
          'recent=${_isRecentPost()} '
          'timeout=${_initializationTimeout().inMilliseconds}ms '
          'url=$_currentVideoUrl '
          'isInit=${_videoController?.value.isInitialized} '
          'hasError=$hasError '
          'retry=$_retryCount',
        );

        // ✅ 느린 초기화(에러 없음)는 포기하지 않고 쉬머 유지 + 필요 시 제한적 재시도
        if (!hasError && _canAutoRetry()) {
          _scheduleRetry();
          _scheduleTimeoutIfNeeded(); // 다음 윈도우도 계속 감시
          return;
        }

        // 에러가 있거나 재시도 윈도우를 넘기면 플레이스홀더로
        _fallbackToVideoPlaceholder();
      }
    });
  }

  void _scheduleRetry() {
    if (!mounted) return;
    final now = DateTime.now();
    _firstAttemptAt ??= now;
    final elapsed = now.difference(_firstAttemptAt!);
    if (elapsed > const Duration(seconds: 15)) return; // 재시도 윈도우 제한
    if (_retryCount >= 2) return; // 과도한 재시도 방지 (수동 탭 재시도는 별도)

    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_currentVideoUrl == null) return;
      _retryCount++;
      debugPrint(
        '[ImageView] retry fire $_logKey '
        'retry=$_retryCount '
        'recent=${_isRecentPost()} '
        'elapsedMs=${DateTime.now().difference(_firstAttemptAt!).inMilliseconds} '
        'url=$_currentVideoUrl',
      );
      // refCount 누수 방지: 재시도 전 현재 참조를 해제하고 다시 획득
      VideoCacheService().releaseController(
        _currentVideoUrl!,
        namespace: 'profile',
      );
      _videoController?.removeListener(_onVideoStateChanged);
      _videoController = null;
      _videoGaveUp = false;
      _attemptInit(resetAttemptWindow: false);
    });
  }

  void _attemptInit({required bool resetAttemptWindow}) {
    if (!mounted) return;
    _videoTimeoutTimer?.cancel();
    _videoTimeoutTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    if (resetAttemptWindow) {
      _firstAttemptAt = DateTime.now();
      _retryCount = 0;
    }
    _videoGaveUp = false;

    final url = widget.post.thumbnailImageUrl.toLowerCase();
    _isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.contains('/videos/') ||
        url.contains('video');

    if (_isVideo && widget.post.thumbnailImageUrl.isNotEmpty) {
      _currentVideoUrl = widget.post.thumbnailImageUrl;
      debugPrint(
        '[ImageView] init start $_logKey '
        'resetWindow=$resetAttemptWindow '
        'recent=${_isRecentPost()} '
        'retry=$_retryCount '
        'url=$_currentVideoUrl',
      );

      try {
        _videoController = VideoCacheService().getOrCreateController(
          _currentVideoUrl!,
          namespace: 'profile',
        );
        debugPrint(
          '[ImageView] controller acquired $_logKey '
          'url=$_currentVideoUrl '
          'isInit=${_videoController?.value.isInitialized} '
          'hasError=${_videoController?.value.hasError}',
        );

        if (_videoController != null) {
          // 이미 초기화된 경우 바로 재생
          if (_videoController!.value.isInitialized) {
            if (mounted) {
              try {
                _videoController!.setVolume(0);
                _videoController!.setLooping(true);
                _videoController!.play();
                debugPrint(
                  '[ImageView] play (already initialized) $_logKey url=$_currentVideoUrl',
                );
                setState(() {});
              } catch (e) {
                debugPrint(
                  '[ImageView] play error (already initialized) $_logKey url=$_currentVideoUrl err=$e',
                );
              }
            }
          } else {
            // 초기화 대기 중 - 리스너 추가
            _videoController!.addListener(_onVideoStateChanged);
            // 초기화가 이미 진행 중일 수 있으므로 한 번 확인
            if (_videoController!.value.isInitialized) {
              _onVideoStateChanged();
            }
            _scheduleTimeoutIfNeeded();
          }
        }
      } catch (e) {
        debugPrint(
          '[ImageView] controller create error $_logKey url=$_currentVideoUrl err=$e',
        );
        _videoController = null;
        _currentVideoUrl = null;
        _isVideo = false;
        if (mounted) setState(() {});
      }
    } else {
      _isVideo = false;
    }
  }

  void _checkIfVideo() => _attemptInit(resetAttemptWindow: true);

  void _fallbackToVideoPlaceholder() {
    _videoTimeoutTimer?.cancel();
    _videoTimeoutTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_videoController != null) {
      _videoController!.removeListener(_onVideoStateChanged);
    }
    _videoController = null;
    _videoGaveUp = true;
    debugPrint(
      '[ImageView] giveUp -> placeholder $_logKey '
      'recent=${_isRecentPost()} url=$_currentVideoUrl',
    );
    if (mounted) setState(() {});
  }

  Widget _buildVideoPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final showText = _isRecentPost();
    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        debugPrint(
          '[ImageView] placeholder tap -> retry $_logKey url=$_currentVideoUrl',
        );
        _videoGaveUp = false;
        _attemptInit(resetAttemptWindow: true);
      },
      child: Container(
        color: theme.colorScheme.surface.withOpacity(0.1),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 34,
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
              if (showText) ...[
                const SizedBox(height: 6),
                Text(
                  '영상 처리 중',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onVideoStateChanged() {
    if (!mounted || _videoController == null) {
      _videoController?.removeListener(_onVideoStateChanged);
      return;
    }

    final controller = _videoController!;

    // 에러가 발생한 경우
    if (controller.value.hasError) {
      debugPrint(
        '[ImageView] error $_logKey '
        'recent=${_isRecentPost()} '
        'retry=$_retryCount '
        'url=$_currentVideoUrl '
        'desc=${controller.value.errorDescription}',
      );
      controller.removeListener(_onVideoStateChanged);
      // ✅ 잠깐 기다리면 정상화될 수 있어, 제한적으로 자동 재시도/쉬머 유지
      if (_canAutoRetry()) {
        _videoController = null;
        if (mounted) setState(() {});
        _scheduleRetry();
      } else {
        _fallbackToVideoPlaceholder();
      }
      return;
    }

    // 초기화 완료된 경우
    if (controller.value.isInitialized) {
      _videoTimeoutTimer?.cancel();
      _videoTimeoutTimer = null;
      controller.removeListener(_onVideoStateChanged);
      try {
        controller.setVolume(0);
        controller.setLooping(true);
        controller.play();
        debugPrint(
          '[ImageView] initialized -> play $_logKey url=$_currentVideoUrl',
        );
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint(
          '[ImageView] play error (after init) $_logKey url=$_currentVideoUrl err=$e',
        );
        if (mounted) setState(() {});
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
                      _isVideo
                          ? (_videoController != null &&
                                  _videoController!.value.isInitialized &&
                                  !_videoController!.value.hasError
                              ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoController!.value.size.width,
                                  height: _videoController!.value.size.height,
                                  child: VideoPlayer(_videoController!),
                                ),
                              )
                              : (_videoGaveUp
                                  ? _buildVideoPlaceholder(context)
                                  : Container(
                                    color: theme.colorScheme.surface
                                        .withOpacity(0.1),
                                    child: const ShimmerBox(
                                      width: double.infinity,
                                      height: 180,
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  )))
                          : CachedNetworkImage(
                            key: ValueKey(
                              'cached-image-${widget.post.id}-${widget.post.thumbnailImageUrl}',
                            ),
                            imageUrl: widget.post.thumbnailImageUrl,
                            cacheKey: widget.post.thumbnailImageUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            useOldImageOnUrlChange:
                                true, // 🎯 URL 변경 시 이전 이미지 유지 (깜빡임 방지)
                            memCacheWidth: 800, // 메모리 캐시 최적화
                            maxWidthDiskCache: 800, // 디스크 캐시 최적화
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
