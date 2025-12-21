import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/video_cache_service.dart';
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
              debugPrint('[CardView] 비디오 재생 오류: $e');
            }
          }
        } else if (_videoController != null) {
          _videoController!.addListener(_onVideoInitialized);
        }
      } catch (e) {
        debugPrint('[CardView] 비디오 컨트롤러 생성 오류: $e');
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
        debugPrint('[CardView] 비디오 초기화 후 재생 오류: $e');
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
        debugPrint('[CardView] build에서 컨트롤러 재획득 오류: $e');
      }
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
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.3,
                              ),
                              width: 0.8,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child:
                                _isVideo && _videoController != null
                                    ? _videoController!.value.isInitialized
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
                                        : Container(
                                          color: theme.colorScheme.surface
                                              .withOpacity(0.1),
                                          child: const ShimmerBox(
                                            width: double.infinity,
                                            height: 180,
                                            borderRadius: BorderRadius.zero,
                                          ),
                                        )
                                    : CachedNetworkImage(
                                      key: ValueKey(
                                        widget.post.thumbnailImageUrl,
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
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 요약
                      Text(
                        widget.post.summary,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),

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
                                fontWeight: FontWeight.w300,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
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
      // UTC 시간을 로컬 시간으로 변환
      final date = TimeUtils.toLocalTime(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes}분 전';
        }
        return '${difference.inHours}시간 전';
      } else if (difference.inDays == 1) {
        return '어제';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else if (difference.inDays < 30) {
        return '${difference.inDays ~/ 7}주 전';
      } else if (difference.inDays < 365) {
        return '${difference.inDays ~/ 30}개월 전';
      } else {
        return '${difference.inDays ~/ 365}년 전';
      }
    } catch (e) {
      return dateStr;
    }
  }
}
