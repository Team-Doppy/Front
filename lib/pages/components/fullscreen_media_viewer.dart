import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show videoPlayerControllers, videoPlayerProxyKey;

/// 전체 화면 미디어 뷰어 (이미지/비디오)
/// - 핀치 확대/축소 지원
/// - 축소 시 자동 원복
/// - 확대 시 경계 처리
/// - 비디오 재생 지원
class FullscreenMediaViewer extends StatefulWidget {
  final String imageUrl;
  final VoidCallback? onClose;
  final List<String> allImageUrls;
  final int initialIndex;
  final bool isVideo;
  final VideoPlayerController? preloadedController;
  final String? postTitle;
  final String? postAuthor;
  final String? postAuthorProfileUrl;
  final ImageProvider? imageProvider;
  final String? postId;
  final LikeService? likeService;
  final String? videoUrl; // ✅ 비디오 URL (컨트롤러 찾기용)
  final String? videoLocalPath; // ✅ 비디오 로컬 경로 (컨트롤러 찾기용)

  const FullscreenMediaViewer({
    super.key,
    required this.imageUrl,
    this.onClose,
    this.allImageUrls = const [],
    this.initialIndex = 0,
    this.isVideo = false,
    this.preloadedController,
    this.postTitle,
    this.postAuthor,
    this.postAuthorProfileUrl,
    this.imageProvider,
    this.postId,
    this.likeService,
    this.videoUrl,
    this.videoLocalPath,
  });

  @override
  State<FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<FullscreenMediaViewer> {
  // 이미지 상태
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // 핀치 제스처 추적
  double? _initialScale;
  Offset? _initialOffset;
  Offset? _lastPanPosition;
  double _gestureMinScale = 1.0;

  // 비디오 상태
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoPreloaded = false;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
  bool _isVideoSeeking = false;
  bool _wasVideoPlayingBeforeSeek = false;
  Duration? _targetSeekPosition;
  double _videoGestureMinScale = 1.0;

  // 기타 상태
  int _currentImageIndex = 0;
  double _dragOffset = 0.0;
  double _hDragOffset = 0.0;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    if (widget.allImageUrls.isNotEmpty) {
      _currentImageIndex =
          widget.initialIndex >= 0 &&
                  widget.initialIndex < widget.allImageUrls.length
              ? widget.initialIndex
              : 0;
    }
    if (widget.isVideo) {
      _initializeVideo();
    }
  }

  void _initializeVideo() async {
    try {
      // ✅ videoPlayerControllers 맵에서 기존 컨트롤러 찾기
      if (widget.videoUrl != null || widget.videoLocalPath != null) {
        final key = videoPlayerProxyKey(
          namespace: 'reader',
          url: widget.videoUrl ?? '',
          localPath: widget.videoLocalPath ?? '',
        );
        final proxy = videoPlayerControllers[key];

        if (proxy?.controller != null) {
          // ✅ 기존 컨트롤러 재사용
          _videoController = proxy!.controller;
          _isVideoPreloaded = true;
          debugPrint('[FullscreenMedia] 기존 비디오 컨트롤러 재사용: $key');
        } else {
          debugPrint('[FullscreenMedia] 컨트롤러를 찾을 수 없음: $key');
        }
      }

      // ✅ preloadedController가 있으면 사용
      if (_videoController == null && widget.preloadedController != null) {
        _videoController = widget.preloadedController;
        _isVideoPreloaded = true;
      }

      // ✅ 컨트롤러를 찾지 못했으면 새로 생성
      if (_videoController == null) {
        final url =
            widget.allImageUrls.isNotEmpty
                ? widget.allImageUrls[_currentImageIndex]
                : widget.imageUrl;
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
        _isVideoPreloaded = false;
      }

      if (!_videoController!.value.isInitialized) {
        await _videoController!.initialize();
      }

      await _videoController!.setVolume(1.0);
      _videoDuration = _videoController!.value.duration;
      _videoPosition = _videoController!.value.position;

      _videoController!.addListener(_onVideoControllerTick);

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        if (!_videoController!.value.isPlaying) {
          await _videoController!.play();
        }
      }
    } catch (e) {
      debugPrint('[FullscreenMedia] 비디오 초기화 오류: $e');
    }
  }

  void _onVideoControllerTick() {
    if (!mounted) return;
    if (_isVideoSeeking && _targetSeekPosition != null) {
      setState(() {
        _videoPosition = _targetSeekPosition!;
        _videoDuration = _videoController!.value.duration;
      });
      return;
    }
    final value = _videoController!.value;
    setState(() {
      _videoDuration = value.duration;
      _videoPosition = value.position;
    });
  }

  @override
  void dispose() {
    if (widget.isVideo && _videoController != null) {
      _videoController!.removeListener(_onVideoControllerTick);
      // ✅ 기존 컨트롤러를 재사용한 경우 dispose하지 않음
      // ✅ 새로 생성한 컨트롤러만 dispose
      if (!_isVideoPreloaded) {
        _videoController!.pause();
        _videoController!.dispose();
      } else {
        // ✅ 기존 컨트롤러는 일시정지만 (dispose하지 않음)
        _videoController!.pause();
      }
    }
    super.dispose();
  }

  void _closeViewer() {
    if (widget.onClose != null) {
      widget.onClose!.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _resetTransform() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  bool get _isZoomed {
    return _scale > 1.01;
  }

  /// 오프셋 클램핑: 이미지가 화면 밖으로 나가지 않도록
  Offset _clampOffset(
    Offset offset,
    double scale,
    Size imageSize,
    Size screenSize,
  ) {
    if (scale <= 1.0) {
      return Offset.zero;
    }

    final scaledWidth = imageSize.width * scale;
    final scaledHeight = imageSize.height * scale;

    final maxOffsetX = (scaledWidth - screenSize.width) / 2;
    final maxOffsetY = (scaledHeight - screenSize.height) / 2;

    return Offset(
      offset.dx.clamp(-maxOffsetX, maxOffsetX),
      offset.dy.clamp(-maxOffsetY, maxOffsetY),
    );
  }

  /// 이미지 크기 계산 (화면에 맞춤 - 적어도 한쪽 끝에는 붙음)
  /// ✅ 표준 방식: 이미지가 화면을 완전히 덮도록 하되, 한쪽 끝에는 반드시 붙음
  Size _getImageDisplaySize(Size imageSize, Size screenSize) {
    final imageAspect = imageSize.width / imageSize.height;
    final screenAspect = screenSize.width / screenSize.height;

    // ✅ 이미지가 더 넓으면 높이에 맞춤 (좌우 잘림, 상하 끝에 붙음)
    // ✅ 이미지가 더 높으면 너비에 맞춤 (상하 잘림, 좌우 끝에 붙음)
    if (imageAspect > screenAspect) {
      // 이미지가 더 넓음: 높이 기준으로 맞춤 (상하 끝에 붙음)
      return Size(screenSize.height * imageAspect, screenSize.height);
    } else {
      // 이미지가 더 높음: 너비 기준으로 맞춤 (좌우 끝에 붙음)
      return Size(screenSize.width, screenSize.width / imageAspect);
    }
  }

  Future<void> _downloadImage() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      final url =
          widget.allImageUrls.isNotEmpty
              ? widget.allImageUrls[_currentImageIndex]
              : widget.imageUrl;
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final result = await ImageGallerySaver.saveImage(
          response.bodyBytes,
          quality: 100,
          name: 'doppy_image_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          setState(() => _isDownloading = false);
          if (result != null && result['isSuccess'] == true) {
            ErrorHandler.showInfo(context, context.tr('image_saved'));
          } else {
            ErrorHandler.showError(context, context.tr('image_save_failed'));
          }
        }
      } else {
        if (mounted) {
          setState(() => _isDownloading = false);
          ErrorHandler.showError(context, context.tr('image_download_failed'));
        }
      }
    } catch (e) {
      debugPrint('[FullscreenMedia] 다운로드 실패: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ErrorHandler.showError(context, context.tr('image_save_failed'));
      }
    }
  }

  Widget _buildVideoPlayer() {
    if (!_isVideoInitialized || _videoController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isPlaying = _videoController!.value.isPlaying;
    final maxMs =
        _videoDuration.inMilliseconds > 0
            ? _videoDuration.inMilliseconds.toDouble()
            : 1.0;
    final posMs = _videoPosition.inMilliseconds.clamp(0, maxMs).toDouble();

    final aspectRatio =
        _videoController!.value.size.width /
        _videoController!.value.size.height;
    final videoFit = aspectRatio >= 16.0 / 9.0 ? BoxFit.contain : BoxFit.cover;

    return Stack(
      children: [
        // 비디오 영역
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
              setState(() {});
            },
            onScaleStart: (details) {
              _initialScale = _scale;
              _initialOffset = _offset;
              _lastPanPosition = details.focalPoint;
              _videoGestureMinScale = _scale;
            },
            onScaleUpdate: (details) {
              if (_initialScale == null || _initialOffset == null) return;

              const double pinchScaleSensitivity = 0.70;
              final dampedScale =
                  math.pow(details.scale, pinchScaleSensitivity).toDouble();
              double newScale = (_initialScale! * dampedScale).clamp(1.0, 4.0);

              if (newScale < _videoGestureMinScale) {
                _videoGestureMinScale = newScale;
              }

              final scaleRatio = newScale / _scale;
              Offset newOffset = _offset * scaleRatio;

              if (_lastPanPosition != null) {
                final delta = details.focalPoint - _lastPanPosition!;
                final dragSensitivity = 1.0 / newScale;
                newOffset =
                    newOffset +
                    Offset(
                      delta.dx * dragSensitivity,
                      delta.dy * dragSensitivity,
                    );
                _lastPanPosition = details.focalPoint;
              }

              final screenSize = MediaQuery.of(context).size;
              final videoSize = _videoController!.value.size;
              final imageSize = _getImageDisplaySize(videoSize, screenSize);
              newOffset = _clampOffset(
                newOffset,
                newScale,
                imageSize,
                screenSize,
              );

              setState(() {
                _scale = newScale;
                _offset = newOffset;
              });
            },
            onScaleEnd: (_) {
              if (_videoGestureMinScale < 0.98) {
                _resetTransform();
              } else {
                final screenSize = MediaQuery.of(context).size;
                final videoSize = _videoController!.value.size;
                final imageSize = _getImageDisplaySize(videoSize, screenSize);
                setState(() {
                  _offset = _clampOffset(
                    _offset,
                    _scale,
                    imageSize,
                    screenSize,
                  );
                });
              }

              _initialScale = null;
              _initialOffset = null;
              _lastPanPosition = null;
              _videoGestureMinScale = 1.0;
            },
            child: Center(
              child: Transform.scale(
                scale: _scale,
                child: Transform.translate(
                  offset: _offset,
                  child: FittedBox(
                    fit: videoFit,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 재생 아이콘 (일시정지 상태일 때만)
        if (!isPlaying)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

        // 시크바
        Positioned(
          bottom: widget.postTitle != null ? 74 : 60, // ✅ 더 위로
          left: 24,
          right: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _isVideoSeeking = true;
              _wasVideoPlayingBeforeSeek = _videoController!.value.isPlaying;
            },
            onHorizontalDragUpdate: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final localPosition = details.localPosition.dx - 15;
              final width = box.size.width - 30;
              final ratio = (localPosition / width).clamp(0.0, 1.0);
              final newMs = (maxMs * ratio).floor();
              final newPosition = Duration(milliseconds: newMs);

              _targetSeekPosition = newPosition;
              setState(() {
                _videoPosition = newPosition;
              });
            },
            onHorizontalDragEnd: (_) async {
              if (_targetSeekPosition != null) {
                try {
                  final wasPlaying = _videoController!.value.isPlaying;
                  if (wasPlaying) {
                    await _videoController!.pause();
                  }

                  await _videoController!.seekTo(_targetSeekPosition!);

                  if (wasPlaying || _wasVideoPlayingBeforeSeek) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    await _videoController!.play();
                  }

                  setState(() {
                    _videoPosition = _targetSeekPosition!;
                  });
                } catch (e) {
                  debugPrint('[FullscreenMedia] Seek 오류: $e');
                  if (_wasVideoPlayingBeforeSeek) {
                    _videoController!.play();
                  }
                }
              }

              _isVideoSeeking = false;
              _targetSeekPosition = null;
            },
            child: Container(
              height: 80,
              color: Colors.transparent,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 4, // ✅ 더 두껍게 (6 -> 8)
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(
                        4,
                      ), // ✅ 더 두껍게 (3 -> 4)
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor:
                          maxMs > 0 ? (posMs / maxMs).clamp(0.0, 1.0) : 0.0,
                      child: Container(
                        height: 4, // ✅ 더 두껍게 (6 -> 8)
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            4,
                          ), // ✅ 더 두껍게 (3 -> 4)
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageViewer() {
    final screenSize = MediaQuery.of(context).size;

    return GestureDetector(
      onScaleStart: (details) {
        _initialScale = _scale;
        _initialOffset = _offset;
        _lastPanPosition = details.focalPoint;
        _gestureMinScale = _scale;
      },
      onScaleUpdate: (details) {
        if (_initialScale == null || _initialOffset == null) return;

        const double pinchScaleSensitivity = 0.70;
        final dampedScale =
            math.pow(details.scale, pinchScaleSensitivity).toDouble();
        double newScale = (_initialScale! * dampedScale).clamp(1.0, 5.0);

        if (newScale < _gestureMinScale) {
          _gestureMinScale = newScale;
        }

        final scaleRatio = newScale / _scale;
        Offset newOffset = _offset * scaleRatio;

        if (_lastPanPosition != null) {
          final delta = details.focalPoint - _lastPanPosition!;
          final dragSensitivity = 1.0 / newScale;
          newOffset =
              newOffset +
              Offset(delta.dx * dragSensitivity, delta.dy * dragSensitivity);
          _lastPanPosition = details.focalPoint;
        }

        final imageSize = _getImageDisplaySize(screenSize, screenSize);
        newOffset = _clampOffset(newOffset, newScale, imageSize, screenSize);

        setState(() {
          _scale = newScale;
          _offset = newOffset;
        });
      },
      onScaleEnd: (_) {
        if (_gestureMinScale < 0.98) {
          _resetTransform();
        } else {
          final imageSize = _getImageDisplaySize(screenSize, screenSize);
          setState(() {
            _offset = _clampOffset(_offset, _scale, imageSize, screenSize);
          });
        }

        _initialScale = null;
        _initialOffset = null;
        _lastPanPosition = null;
        _gestureMinScale = 1.0;
      },
      child: Center(
        child: Transform.scale(
          scale: _scale,
          child: Transform.translate(
            offset: _offset,
            child: PageView.builder(
              physics:
                  _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
              itemCount:
                  widget.allImageUrls.isNotEmpty
                      ? widget.allImageUrls.length
                      : 1,
              onPageChanged: (index) {
                setState(() {
                  _currentImageIndex = index;
                  _resetTransform();
                });
              },
              controller: PageController(
                initialPage: _currentImageIndex,
                viewportFraction: 1.0,
              ),
              padEnds: false,
              itemBuilder: (context, index) {
                final mediaUrl =
                    widget.allImageUrls.isNotEmpty
                        ? widget.allImageUrls[index]
                        : widget.imageUrl;

                return widget.imageProvider != null &&
                        index == widget.initialIndex
                    ? Image(
                      image: widget.imageProvider!,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (context, error, stack) => const Icon(
                            Icons.error,
                            color: Colors.white,
                            size: 50,
                          ),
                    )
                    : Builder(
                      builder: (context) {
                        final decodeWidth = (screenSize.width *
                                MediaQuery.of(context).devicePixelRatio)
                            .round()
                            .clamp(1, 1000000);
                        final imageProviderResult = EditorImageProvider.build(
                          url: mediaUrl,
                          isEditing: false,
                          decodeWidth: decodeWidth,
                        );
                        return Image(
                          image: imageProviderResult.effectiveProvider,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (context, error, stack) => const Icon(
                                Icons.error,
                                color: Colors.white,
                                size: 50,
                              ),
                        );
                      },
                    );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// ✅ 배경 블러 이미지 빌드
  Widget _buildBlurredBackground() {
    if (widget.isVideo) {
      // ✅ 비디오: 비디오 자체를 배경으로 사용 (블러 처리됨)
      if (_isVideoInitialized && _videoController != null) {
        final aspectRatio =
            _videoController!.value.size.width /
            _videoController!.value.size.height;
        final videoFit =
            aspectRatio >= 16.0 / 9.0 ? BoxFit.contain : BoxFit.cover;

        return FittedBox(
          fit: videoFit,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        );
      }
      // 비디오가 초기화되지 않았으면 기본 배경
      return Container(color: Colors.black);
    } else {
      // ✅ 이미지: 현재 이미지 사용
      final mediaUrl =
          widget.allImageUrls.isNotEmpty
              ? widget.allImageUrls[_currentImageIndex]
              : widget.imageUrl;

      if (widget.imageProvider != null &&
          _currentImageIndex == widget.initialIndex) {
        return Image(
          image: widget.imageProvider!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      } else {
        return Builder(
          builder: (context) {
            final screenSize = MediaQuery.of(context).size;
            final decodeWidth = (screenSize.width *
                    MediaQuery.of(context).devicePixelRatio)
                .round()
                .clamp(1, 1000000);
            final imageProviderResult = EditorImageProvider.build(
              url: mediaUrl,
              isEditing: false,
              decodeWidth: decodeWidth,
            );
            return Image(
              image: imageProviderResult.effectiveProvider,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // ✅ 블러 배경이 보이도록 검은색
      body: Stack(
        children: [
          // ✅ 배경 블러 이미지
          Positioned.fill(child: _buildBlurredBackground()),
          // ✅ 백필터 블러 적용
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.6), // ✅ 약간의 어둡게 처리
              ),
            ),
          ),
          // ✅ 메인 컨텐츠
          GestureDetector(
            onVerticalDragUpdate:
                _isZoomed
                    ? null
                    : (details) {
                      if (details.primaryDelta! > 0) {
                        setState(() {
                          _dragOffset += details.primaryDelta!;
                        });
                      }
                    },
            onVerticalDragEnd:
                _isZoomed
                    ? null
                    : (details) {
                      if (_dragOffset > 100) {
                        _closeViewer();
                        return;
                      }
                      if (details.primaryVelocity! > 300) {
                        _closeViewer();
                        return;
                      }
                      setState(() {
                        _dragOffset = 0.0;
                      });
                    },
            onHorizontalDragUpdate:
                _isZoomed
                    ? null
                    : (details) {
                      final dx = details.primaryDelta ?? 0.0;
                      setState(() {
                        _hDragOffset = (_hDragOffset + dx).clamp(0.0, 300.0);
                      });
                    },
            onHorizontalDragEnd:
                _isZoomed
                    ? null
                    : (details) {
                      if (_hDragOffset > 80 ||
                          (details.primaryVelocity ?? 0) > 600) {
                        _closeViewer();
                      } else {
                        setState(() {
                          _hDragOffset = 0.0;
                        });
                      }
                    },
            child: Opacity(
              opacity: (1.0 - _dragOffset / 300).clamp(0.0, 1.0),
              child: Stack(
                children: [
                  // 미디어 영역
                  Positioned.fill(
                    child:
                        widget.isVideo
                            ? _buildVideoPlayer()
                            : _buildImageViewer(),
                  ),

                  // 상단 닫기 버튼
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _closeViewer,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(shape: BoxShape.circle),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 다운로드 버튼 (이미지만)
                  if (!widget.isVideo)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _downloadImage,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                child:
                                    _isDownloading
                                        ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                        : SvgPicture.asset(
                                          'assets/icons/download.svg',
                                          color: Colors.white,
                                          width: 24,
                                          height: 24,
                                        ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 하단 정보
                  if (widget.postTitle != null || widget.postAuthor != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(),
                        padding: const EdgeInsets.only(
                          bottom: 38,
                          left: 20,
                          right: 20,
                        ),
                        child: Row(
                          children: [
                            if (widget.postAuthorProfileUrl != null)
                              GestureDetector(
                                onTap:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => UserProfileScreen(
                                              otherUser: User(
                                                username: widget.postAuthor!,
                                                profileImageUrl:
                                                    widget
                                                        .postAuthorProfileUrl!,
                                              ),
                                            ),
                                      ),
                                    ),
                                child: CommonProfileAvatar(
                                  imageUrl: widget.postAuthorProfileUrl!,
                                  username: widget.postAuthor!,
                                  size: 52,
                                  borderWidth: 1,
                                ),
                              ),
                            if (widget.postAuthorProfileUrl != null)
                              const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.postTitle != null)
                                    Text(
                                      widget.postTitle!,
                                      style: TextStyle(
                                        color: AppColors.darkTextPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (widget.postAuthor != null)
                                    Text(
                                      widget.postAuthor!,
                                      style: TextStyle(
                                        color: AppColors.darkTextPrimary
                                            .withOpacity(0.7),
                                        fontSize: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 닷 인디케이터
                  if (widget.allImageUrls.length > 1)
                    SafeArea(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: widget.postTitle != null ? 120 : 30,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              widget.allImageUrls.length,
                              (index) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color:
                                        index == _currentImageIndex
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
