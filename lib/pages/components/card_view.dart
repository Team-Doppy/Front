import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/utils/format_utils.dart';
import 'package:doppy/utils/time_utils.dart';

class CardView extends StatefulWidget {
  const CardView({
    super.key,
    required this.post,
    this.showViewBadge = false,
    this.isLast = false,
    this.isFirst = false,
  });
  final PostData post;
  final bool showViewBadge;
  final bool isLast;
  final bool isFirst;

  @override
  State<CardView> createState() => _CardViewState();
}

class _CardViewState extends State<CardView> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  String? _currentVideoUrl; // 현재 사용 중인 비디오 URL
  bool _videoGaveUp = false;
  Timer? _videoTimeoutTimer;
  Timer? _retryTimer;
  DateTime? _firstAttemptAt;
  int _retryCount = 0;

  String get _logKey => 'postId=${widget.post.id}';

  @override
  void initState() {
    super.initState();
    _checkIfVideo();
  }

  @override
  void didUpdateWidget(CardView oldWidget) {
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
    if (_videoController != null) {
      try {
        _videoController!.removeListener(_onVideoStateChanged);
        if (_videoController!.value.isInitialized) {
          _videoController!.pause();
        }
        _videoController!.dispose();
      } catch (e) {
        debugPrint('[CardView] 컨트롤러 dispose 오류: $e');
      }
      _videoController = null;
      _currentVideoUrl = null;
    }
  }

  bool _isRecentPost({Duration window = const Duration(minutes: 3)}) {
    final createdAtStr = widget.post.createdAt.trim();
    final createdAt = DateTime.tryParse(createdAtStr);
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt).abs() <= window;
  }

  Duration _initializationTimeout() {
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
          '[CardView] timeout $_logKey '
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
          _scheduleTimeoutIfNeeded();
          return;
        }

        _fallbackToVideoPlaceholder();
      }
    });
  }

  void _scheduleRetry() {
    if (!mounted) return;
    final now = DateTime.now();
    _firstAttemptAt ??= now;
    final elapsed = now.difference(_firstAttemptAt!);
    if (elapsed > const Duration(seconds: 15)) return;
    if (_retryCount >= 2) return;

    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_currentVideoUrl == null) return;
      _retryCount++;
      debugPrint(
        '[CardView] retry fire $_logKey '
        'retry=$_retryCount '
        'recent=${_isRecentPost()} '
        'elapsedMs=${DateTime.now().difference(_firstAttemptAt!).inMilliseconds} '
        'url=$_currentVideoUrl',
      );
      _videoController?.removeListener(_onVideoStateChanged);
      try {
        _videoController?.dispose();
      } catch (_) {}
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
        '[CardView] init start $_logKey '
        'resetWindow=$resetAttemptWindow '
        'recent=${_isRecentPost()} '
        'retry=$_retryCount '
        'url=$_currentVideoUrl',
      );

      try {
        // 🎯 표준 방식: 직접 컨트롤러 생성
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(_currentVideoUrl!),
          httpHeaders: const {'Accept': 'video/*', 'Connection': 'keep-alive'},
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: false,
          ),
        );
        debugPrint(
          '[CardView] controller created $_logKey url=$_currentVideoUrl',
        );

        // 리스너 추가
        _videoController!.addListener(_onVideoStateChanged);

        // 초기화 시작
        _videoController!
            .initialize()
            .then((_) {
              if (!mounted) return;
              if (_videoController == null) return;

              try {
                _videoController!.setVolume(0);
                _videoController!.setLooping(true);
                if (mounted) {
                  setState(() {});
                }
              } catch (e) {
                debugPrint('[CardView] 초기화 후 설정 오류: $e');
              }
            })
            .catchError((e) {
              debugPrint('[CardView] 초기화 실패: $e');
              if (mounted) {
                setState(() {
                  _videoController = null;
                  _currentVideoUrl = null;
                  _isVideo = false;
                });
              }
            });

        _scheduleTimeoutIfNeeded();
      } catch (e) {
        debugPrint(
          '[CardView] controller create error $_logKey url=$_currentVideoUrl err=$e',
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
      '[CardView] giveUp -> placeholder $_logKey '
      'recent=${_isRecentPost()} url=$_currentVideoUrl',
    );
    if (mounted) setState(() {});
  }

  Widget _buildVideoPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        if (!mounted) return;
        debugPrint(
          '[CardView] placeholder tap -> retry $_logKey url=$_currentVideoUrl',
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
        '[CardView] error $_logKey '
        'recent=${_isRecentPost()} '
        'retry=$_retryCount '
        'url=$_currentVideoUrl '
        'desc=${controller.value.errorDescription}',
      );
      controller.removeListener(_onVideoStateChanged);
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
          '[CardView] initialized -> play $_logKey url=$_currentVideoUrl',
        );
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint(
          '[CardView] play error (after init) $_logKey url=$_currentVideoUrl err=$e',
        );
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 표준 방식: 컨트롤러가 없으면 재초기화 시도
    if (_isVideo && _currentVideoUrl != null && _videoController == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentVideoUrl != null && _videoController == null) {
          _attemptInit(resetAttemptWindow: false);
        }
      });
    }
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withOpacity(0.5),
      ),
      child: ClipRRect(
        child: Stack(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 125,

                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: theme.colorScheme.surfaceVariant,
                              width: 0.8,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child:
                                _isVideo
                                    ? (_videoController != null &&
                                            _videoController!
                                                .value
                                                .isInitialized &&
                                            !_videoController!.value.hasError
                                        ? FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width:
                                                _videoController!
                                                    .value
                                                    .size
                                                    .width,
                                            height:
                                                _videoController!
                                                    .value
                                                    .size
                                                    .height,
                                            child: VideoPlayer(
                                              _videoController!,
                                            ),
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
                                      width: double.infinity,
                                      height: 150,
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                      useOldImageOnUrlChange:
                                          true, // 🎯 URL 변경 시 이전 이미지 유지 (깜빡임 방지)
                                      memCacheWidth: 800, // 메모리 캐시 최적화
                                      maxWidthDiskCache: 800, // 디스크 캐시 최적화
                                      placeholder:
                                          (context, url) => Container(
                                            color: theme.colorScheme.surface
                                                .withOpacity(0.1),
                                            child: const ShimmerBox(
                                              width: double.infinity,
                                              height: 180,
                                              borderRadius: BorderRadius.zero,
                                            ),
                                          ),
                                      errorWidget:
                                          (context, url, error) => Builder(
                                            builder:
                                                (context) =>
                                                    ImageErrorPlaceholder(),
                                          ),
                                    ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.showViewBadge)
                      Positioned(
                        left: 5,
                        bottom: 0,
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.post.accessLevel ==
                                  AccessLevel.private)
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
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 10),

                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 10),
                      // 제목
                      Text(
                        widget.post.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 발행날짜
                      Text(
                        _formatDateString(widget.post.createdAt),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 하트수와 댓글수
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              // 🎯 "내가 좋아한" 화면에서는 항상 빨간색 채운 하트 표시
                              widget.post.isLiked == true
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 16,
                              color:
                                  widget.post.isLiked == true
                                      ? const Color(0xFFFF5959) // 🎯 빨간색
                                      : theme.colorScheme.onSurface.withOpacity(
                                        0.4,
                                      ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatCount(widget.post.likeCount),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateString(String dateStr) {
    try {
      return TimeUtils.formatRelativeTimeFromUtc(context, dateStr);
    } catch (e) {
      return dateStr;
    }
  }
}
