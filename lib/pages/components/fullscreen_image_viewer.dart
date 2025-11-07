import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/media_comment_service.dart';
import 'package:doppy/pages/components/comment_item.dart';
import 'package:doppy/pages/components/comment_input_section.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

class FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final VoidCallback? onClose;
  final List<String> allImageUrls;
  final int initialIndex;
  final bool isVideo;
  final VideoPlayerController? preloadedController;
  final String? mediaId;
  final List<String> allMediaIds;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.onClose,
    this.allImageUrls = const [],
    this.initialIndex = 0,
    this.isVideo = false,
    this.preloadedController,
    this.mediaId,
    this.allMediaIds = const [],
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  final Map<String, List<Comment>> _commentsByImage = {};
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  late AnimationController _commentsController;
  double _dragOffset = 0.0;
  double _commentDragOffset = 0.0;
  List<AnimationController> _commentPreviewControllers = [];
  int _currentImageIndex = 0;
  bool _isSheetDraggingDown = false; // 바텀시트 드래그 방향 (내림 감지)
  double _hDragOffset = 0.0; // 오른쪽 스와이프로 닫기 제스처 오프셋
  // 확대/이동 제어용
  final Map<int, TransformationController> _imageZoomControllers = {};
  final TransformationController _videoZoomController =
      TransformationController();
  double _imageGestureMinScale = 1.0;

  @override
  void initState() {
    super.initState();

    _commentsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // 바텀시트 애니메이션을 Builder로 그리므로, 값 변화마다 수동으로 리빌드
    _commentsController.addListener(() {
      if (mounted) setState(() {});
    });

    // 현재 이미지 인덱스 초기화
    if (widget.allImageUrls.isNotEmpty) {
      final initialIndex = widget.allImageUrls.indexOf(widget.imageUrl);
      _currentImageIndex = initialIndex >= 0 ? initialIndex : 0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadImageComments();
      _initCommentPreviewAnimations();
    });
  }

  bool get _isMediaZoomed {
    try {
      if (widget.isVideo) {
        return _isVideoZoomed();
      }
      final ctrl = _imageZoomControllers[_currentImageIndex];
      if (ctrl == null) return false;
      return _isImageZoomed(ctrl);
    } catch (_) {
      return false;
    }
  }

  bool _isImageZoomed(TransformationController ctrl) {
    try {
      final m = ctrl.value;
      final sx = m.storage[0];
      final sy = m.storage[5];
      final s = (sx + sy) / 2.0;
      return s > 1.01;
    } catch (_) {
      return false;
    }
  }

  bool _isVideoZoomed() {
    try {
      final m = _videoZoomController.value;
      final sx = m.storage[0];
      final sy = m.storage[5];
      final s = (sx + sy) / 2.0;
      return s > 1.01;
    } catch (_) {
      return false;
    }
  }

  void showComments({Duration duration = const Duration(milliseconds: 260)}) {
    _resetMediaScale();
    _commentsController.animateTo(
      1.0,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  void hideComments({Duration duration = const Duration(milliseconds: 220)}) {
    _commentsController.animateTo(
      0.0,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  void _resetMediaScale() {
    try {
      for (final ctrl in _imageZoomControllers.values) {
        ctrl.value = Matrix4.identity();
      }
      _videoZoomController.value = Matrix4.identity();
    } catch (_) {}
  }

  String get _currentImageUrl {
    if (widget.allImageUrls.isNotEmpty) {
      return widget.allImageUrls[_currentImageIndex];
    }
    return widget.imageUrl;
  }

  List<Comment> get _imageComments {
    return _commentsByImage[_currentImageUrl] ?? [];
  }

  void _initCommentPreviewAnimations() {
    // 댓글 수만큼 애니메이션 컨트롤러 생성 (최대 2개)
    final commentCount = _imageComments.length > 2 ? 2 : _imageComments.length;
    for (int i = 0; i < commentCount; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      );
      _commentPreviewControllers.add(controller);

      // 시간차를 두고 시작 (더 빠르게)
      Future.delayed(Duration(milliseconds: 0), () {
        if (mounted) {
          controller.forward();
        }
      });
    }
  }

  void _disposeCommentPreviewControllers() {
    for (final controller in _commentPreviewControllers) {
      controller.dispose();
    }
    _commentPreviewControllers.clear();
  }

  Future<void> _loadImageComments() async {
    print(
      '[FIV] _loadImageComments() start: idx=$_currentImageIndex url=$_currentImageUrl isVideo=${widget.isVideo}',
    );
    try {
      // mediaId 추출: exported에서 metadata로 주입되어 있어야 함
      final mediaId = _extractCurrentMediaId();
      print('[FIV] extracted mediaId=$mediaId');
      if (mediaId == null) {
        print('[FIV] skip fetch: mediaId is null');
        setState(() => _commentsByImage[_currentImageUrl] = []);
        return;
      }
      final svc = MediaCommentService();
      final list =
          widget.isVideo
              ? await svc.fetchVideoComments(
                videoId: mediaId,
                page: 0,
                size: 20,
              )
              : await svc.fetchImageComments(
                imageId: mediaId,
                page: 0,
                size: 20,
              );
      print('[FIV] fetched list size=${list.length}');
      final mapped =
          list
              .map(
                (m) => Comment(
                  id: m.id,
                  author: m.author ?? '',
                  content: m.text,
                  authorProfileImageUrl: m.authorProfileImageUrl ?? '',
                  postId: '0',
                  imageUrl: _currentImageUrl,
                  createdAt: m.createdAt,
                  updatedAt: m.updatedAt,
                ),
              )
              .toList();
      setState(() {
        _commentsByImage[_currentImageUrl] = mapped;
        _disposeCommentPreviewControllers();
        _commentPreviewControllers.clear();
        _initCommentPreviewAnimations();
      });
    } catch (e) {
      print('[FIV] fetch failed: $e');
      setState(() => _commentsByImage[_currentImageUrl] = []);
    }
  }

  String? _extractCurrentMediaId() {
    if (widget.allMediaIds.isNotEmpty) {
      final idx =
          (_currentImageIndex >= 0 &&
                  _currentImageIndex < widget.allMediaIds.length)
              ? _currentImageIndex
              : 0;
      final id = widget.allMediaIds[idx];
      final result = id.isEmpty ? null : id;
      print('[FIV] mediaId from list idx=$idx -> $result');
      return result;
    }
    print('[FIV] mediaId from single -> ${widget.mediaId}');
    return widget.mediaId;
  }

  @override
  void dispose() {
    // 모든 컨트롤러와 리스너 정리
    try {
      _fadeController.dispose();
      _commentsController.dispose();
      _commentController.dispose();
      _commentFocus.dispose();
      _disposeCommentPreviewControllers();

      // 댓글 Map 초기화
      _commentsByImage.clear();
    } catch (e) {
      print('FullscreenImageViewer dispose 중 오류: $e');
    }
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final mediaId = _extractCurrentMediaId();
    if (mediaId == null || mediaId.isEmpty) {
      ErrorHandler.showError(context, '반응 추가중 오류가 발생했어요');
      return;
    }

    // 낙관적 추가
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final prev = List<Comment>.from(_imageComments);
    setState(() {
      _commentsByImage[_currentImageUrl] = [
        ..._imageComments,
        Comment(
          id: tempId,
          author: '나',
          content: text,
          authorProfileImageUrl: '',
          postId: '0',
          imageUrl: _currentImageUrl,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ];
      _commentController.clear();
    });

    try {
      print(
        '[FIV] POST comment mediaId=$mediaId text="$text" isVideo=${widget.isVideo}',
      );
      final svc = MediaCommentService();
      final newId =
          widget.isVideo
              ? await svc.createVideoComment(videoId: mediaId, text: text)
              : await svc.createImageComment(imageId: mediaId, text: text);
      print('[FIV] POST result id=$newId');

      if (!mounted) return;

      setState(() {
        final list = List<Comment>.from(_imageComments);
        final idx = list.indexWhere((c) => c.id == tempId);
        if (idx != -1 && newId.isNotEmpty) {
          list[idx] = list[idx].copyWith(id: newId);
          _commentsByImage[_currentImageUrl] = list;
        }
      });
    } catch (e) {
      print('[FIV] POST failed: $e');
      if (!mounted) return;

      setState(() {
        _commentsByImage[_currentImageUrl] = prev;
        _commentController.text = text;
      });
      ErrorHandler.showError(context, '댓글 전송에 실패했습니다');
    }
  }

  void _closeViewer() {
    if (widget.onClose != null) {
      widget.onClose!.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _downloadImage() async {
    try {
      // 이미지 다운로드
      final response = await http.get(Uri.parse(_currentImageUrl));

      if (response.statusCode == 200) {
        // 파일 저장
        final directory =
            Platform.isAndroid
                ? await getExternalStorageDirectory()
                : await getApplicationDocumentsDirectory();

        if (directory != null) {
          final file = File(
            '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await file.writeAsBytes(response.bodyBytes);

          if (mounted) {
            ErrorHandler.showInfo(context, '이미지 다운로드 성공');
          }
        }
      } else {
        if (mounted) {
          ErrorHandler.showError(context, '이미지 다운로드에 실패했습니다');
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '이미지 다운로드 중 오류가 발생했습니다');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool _zoomed = _isMediaZoomed;
    return GestureDetector(
      onVerticalDragUpdate:
          _zoomed
              ? null
              : (details) {
                // 전역 드래그에서도 방향 추적 → 임계값 자동복귀(내릴 때만) 적용
                _isSheetDraggingDown = details.primaryDelta! > 0;
                if (details.primaryDelta! < 0 &&
                    _commentsController.value < 1.0) {
                  // 위로 드래그: 댓글 열기
                  final delta = -details.primaryDelta! / 300; // 민감도 조절
                  setState(() {
                    _commentsController.value =
                        (_commentsController.value + delta).clamp(0.0, 1.0);
                  });
                } else if (details.primaryDelta! > 0 &&
                    _commentsController.value > 0.0) {
                  // 아래로 드래그: 댓글 닫기
                  final delta = details.primaryDelta! / 300;
                  setState(() {
                    _commentsController.value =
                        (_commentsController.value - delta).clamp(0.0, 1.0);
                  });
                } else if (details.primaryDelta! > 0 &&
                    _commentsController.value == 0.0) {
                  // 댓글 닫힌 상태에서 아래로 드래그: 뷰어 닫기
                  setState(() {
                    _dragOffset += details.primaryDelta!;
                  });
                }
              },
      onVerticalDragEnd:
          _zoomed
              ? null
              : (details) {
                // 아래로 당겨서 닫기 체크 (댓글이 닫혀있을 때)
                if (_commentsController.value == 0.0 && _dragOffset > 100) {
                  _closeViewer();
                  return;
                }

                // velocity가 있으면 방향에 따라 바로 완료
                if (details.primaryVelocity! < -300) {
                  // 위로 빠르게 스와이프: 완전히 열기
                  showComments();
                } else if (details.primaryVelocity! > 300) {
                  // 아래로 빠르게 스와이프
                  if (_commentsController.value > 0.5) {
                    // 이미 많이 열려있으면 닫기 (댓글만 닫기)
                    _commentsController.reverse();
                  } else if (_commentsController.value > 0) {
                    // 조금 열려있어도 닫기
                    _commentsController.reverse();
                  } else {
                    // 댓글 닫힌 상태에서 빠르게 아래로: 뷰어 닫기
                    _closeViewer();
                    return;
                  }
                } else {
                  // velocity가 작으면 현재 위치에 따라 결정
                  if (_commentsController.value > 0.5) {
                    showComments();
                  } else if (_commentsController.value > 0) {
                    // 댓글이 열려있으면 닫기
                    _commentsController.reverse();
                  }
                }

                // _dragOffset 리셋
                setState(() {
                  _dragOffset = 0.0;
                });
                _isSheetDraggingDown = false; // 방향 플래그 리셋
              },
      onHorizontalDragUpdate:
          _zoomed
              ? null
              : (details) {
                // 오른쪽으로 스와이프하여 닫기 (댓글 시트가 닫혀있을 때만)
                if (_commentsController.value == 0) {
                  final dx = details.primaryDelta ?? 0.0;
                  if (dx > 0) {
                    setState(() {
                      _hDragOffset = (_hDragOffset + dx).clamp(0.0, 300.0);
                    });
                  } else {
                    setState(() {
                      _hDragOffset = (_hDragOffset + dx).clamp(0.0, 300.0);
                    });
                  }
                }
              },
      onHorizontalDragEnd:
          _zoomed
              ? null
              : (details) {
                if (_commentsController.value == 0) {
                  if (_hDragOffset > 80 ||
                      (details.primaryVelocity ?? 0) > 600) {
                    _closeViewer();
                  } else {
                    setState(() {
                      _hDragOffset = 0.0;
                    });
                  }
                }
              },
      child: Opacity(
        opacity: (1.0 - _dragOffset / 300).clamp(0.0, 1.0),
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  widget.isVideo
                      ? Builder(
                        builder: (_) {
                          final c = widget.preloadedController;
                          if (c == null || !c.value.isInitialized) {
                            return Container(color: Colors.black);
                          }
                          return FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: c.value.size.width,
                              height: c.value.size.height,
                              child: IgnorePointer(child: VideoPlayer(c)),
                            ),
                          );
                        },
                      )
                      : CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                        errorWidget:
                            (context, url, error) => const Icon(Icons.error),
                      ),
            ),
            Positioned.fill(
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: const Color.fromARGB(
                      255,
                      35,
                      35,
                      35,
                    ).withOpacity(0.8),
                  ),
                ),
              ),
            ),

            // 이미지 (전면과 축소를 하나로 통합)
            Builder(
              builder: (context) {
                final p = _commentsController.value;
                final screenWidth = MediaQuery.of(context).size.width;
                final screenHeight = MediaQuery.of(context).size.height;

                final initialSize = screenWidth;
                final finalSize = (screenWidth - 40) * 0.5;
                final initialCenterY = screenHeight / 2;
                final finalCenterY = finalSize / 2 + 60;
                final p2 = p * p;
                final currentSize =
                    initialSize - p2 * (initialSize - finalSize);
                final currentCenterY =
                    initialCenterY - p2 * (initialCenterY - finalCenterY);
                final currentLeft = (screenWidth - currentSize) / 2;
                final currentTop =
                    (1 - p) * 0.0 + p * (currentCenterY - currentSize / 2);
                final currentWidth = currentSize;
                final currentHeight = (1 - p) * screenHeight + p * currentSize;

                // 이미지 Positioned
                return Positioned(
                  left: currentLeft,
                  top: currentTop,
                  width: currentWidth,
                  height: currentHeight,
                  child: Container(
                    // 시트가 올라왔을 때(p>0)도 이미지와 시트 사이 간격을 거의 없앰
                    margin: EdgeInsets.only(bottom: p > 0.05 ? 4.0 : 0.0),
                    child: // 더 과감한 라운드
                        GestureDetector(
                      onTap: () {
                        if (p > 0) {
                          _commentsController.reverse();
                        }
                      },
                      child: PageView.builder(
                        physics:
                            (_commentsController.value > 0.05 || _zoomed)
                                ? const NeverScrollableScrollPhysics()
                                : const BouncingScrollPhysics(),
                        itemCount:
                            widget.allImageUrls.isNotEmpty
                                ? widget.allImageUrls.length
                                : 1,
                        onPageChanged: (index) {
                          setState(() {
                            _currentImageIndex = index;
                          });
                          _loadImageComments();
                        },
                        controller: PageController(
                          initialPage: _currentImageIndex,
                        ),
                        itemBuilder: (context, index) {
                          final mediaUrl =
                              widget.allImageUrls.isNotEmpty
                                  ? widget.allImageUrls[index]
                                  : widget.imageUrl;
                          if (widget.isVideo && index == 0) {
                            return Center(
                              child: _VideoPlayerWidget(
                                url: mediaUrl,
                                autoPlay: true,
                                preloadedController: widget.preloadedController,
                                hideScrubber: _commentsController.value > 0.1,
                                zoomController: _videoZoomController,
                                lockInteraction:
                                    _commentsController.value > 0.05,
                              ),
                            );
                          }
                          return Center(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final ctrl = _imageZoomControllers.putIfAbsent(
                                  index,
                                  () => TransformationController(),
                                );
                                final bool sheetOpen =
                                    _commentsController.value > 0.05;
                                if (sheetOpen) {
                                  ctrl.value = Matrix4.identity();
                                }
                                final bool isZoomed = _isImageZoomed(ctrl);
                                return InteractiveViewer(
                                  minScale: sheetOpen ? 1.0 : 1.0,
                                  maxScale: sheetOpen ? 1.0 : 4.0,
                                  panEnabled: !sheetOpen && isZoomed,
                                  scaleEnabled: !sheetOpen,
                                  boundaryMargin:
                                      sheetOpen || !isZoomed
                                          ? EdgeInsets.zero
                                          : const EdgeInsets.all(200),
                                  clipBehavior: Clip.none,
                                  onInteractionStart: (_) {
                                    _imageGestureMinScale = 1.0;
                                  },
                                  onInteractionUpdate: (details) {
                                    _imageGestureMinScale =
                                        _imageGestureMinScale < details.scale
                                            ? _imageGestureMinScale
                                            : details.scale;
                                    setState(() {});
                                  },
                                  onInteractionEnd: (_) {
                                    if (_imageGestureMinScale < 0.98) {
                                      // 조금이라도 축소하면 정확히 원래 위치/크기로 리셋
                                      ctrl.value = Matrix4.identity();
                                    }
                                    _imageGestureMinScale = 1.0;
                                    setState(() {});
                                  },
                                  transformationController: ctrl,
                                  child: SizedBox(
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                    child: CachedNetworkImage(
                                      imageUrl: mediaUrl,
                                      fit: BoxFit.contain,
                                      errorWidget:
                                          (context, error, stack) =>
                                              const Center(
                                                child: Icon(
                                                  Icons.error,
                                                  color: Colors.white,
                                                  size: 50,
                                                ),
                                              ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

            // 댓글 섹션: 실시간 바텀시트 느낌 (AnimatedBuilder 없이)
            Builder(
              builder: (context) {
                final p = _commentsController.value;
                final screenWidth = MediaQuery.of(context).size.width;
                final screenHeight = MediaQuery.of(context).size.height;
                final initialSize = screenWidth;
                final finalSize = (screenWidth - 40) * 0.5;
                final initialCenterY = screenHeight / 2;
                final finalCenterY = finalSize / 2 + 60;
                final p2 = p * p;
                final currentSize =
                    initialSize - p2 * (initialSize - finalSize);
                final currentCenterY =
                    initialCenterY - p2 * (initialCenterY - finalCenterY);
                final currentTop =
                    (1 - p) * 0.0 + p * (currentCenterY - currentSize / 2);
                final currentHeight = (1 - p) * screenHeight + p * currentSize;

                final sheetTop =
                    currentTop + currentHeight + _commentDragOffset;

                if (p == 0) return const SizedBox.shrink();

                double _visibleHeight = screenHeight - sheetTop;
                // 임계값(100px) 이하이고, 사용자가 '내리는 중'일 때만 즉시 원상복귀
                if (_isSheetDraggingDown && _visibleHeight <= 100) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_commentsController.value > 0.0) {
                      // 애니메이션 없이 바로 복귀
                      _commentsController.value = 0.0;
                    }
                  });
                }

                return Positioned(
                  top: sheetTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onVerticalDragUpdate: (details) {
                      final dy = details.primaryDelta ?? 0.0;
                      _isSheetDraggingDown = dy > 0;
                      // 바텀시트를 끌면 p값을 직접 조정 → 이미지와 상호 연동
                      // 양수(down)일수록 p 감소(닫힘), 음수(up)일수록 p 증가(열림)
                      final sensitivity = 300.0; // 더 민감: 300px에 1.0 변화
                      final next = (_commentsController.value -
                              dy / sensitivity)
                          .clamp(0.0, 1.0);
                      _commentsController.value = next;
                      _commentDragOffset = 0.0;
                    },
                    onVerticalDragEnd: (details) {
                      final v = _commentsController.value;
                      final vy = details.primaryVelocity ?? 0.0;
                      const openThreshold = 0.6; // 열림은 약간 더 확실히
                      const closeThreshold = 0.25; // 닫힘은 더 쉽게

                      if (vy > 200) {
                        hideComments();
                      } else if (vy < -200) {
                        showComments();
                      } else if (v >= openThreshold) {
                        showComments();
                      } else if (v <= closeThreshold) {
                        hideComments();
                      } else {
                        // 중간 영역은 가까운 쪽으로 스냅
                        if ((v - closeThreshold) < (openThreshold - v)) {
                          hideComments();
                        } else {
                          showComments();
                        }
                      }
                      _commentDragOffset = 0.0;
                      _isSheetDraggingDown = false;
                    },
                    child:
                        _visibleHeight > 100
                            ? Container(
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                              ),

                              child: Column(
                                children: [
                                  SizedBox(height: 10),

                                  Expanded(
                                    child: Consumer<UserProvider>(
                                      builder: (context, userProvider, child) {
                                        if (_imageComments.isEmpty) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            child: Align(
                                              alignment: Alignment.topLeft,
                                              child: GestureDetector(
                                                onTap:
                                                    () =>
                                                        _commentFocus
                                                            .requestFocus(),
                                                child: AnimatedOpacity(
                                                  opacity: _commentsController
                                                      .value
                                                      .clamp(0.0, 1.0),
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 10,
                                                        ),

                                                    child: const Text(
                                                      '처음으로 반응을 남겨보세요!',
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.primary,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            itemCount: _imageComments.length,
                                            itemBuilder: (context, index) {
                                              final comment =
                                                  _imageComments[index];
                                              final currentUser =
                                                  userProvider.currentUser;
                                              final isMe =
                                                  comment.author ==
                                                  (currentUser?.id.toString() ??
                                                      '');

                                              return CommentItem(
                                                key: GlobalKey(),

                                                comment: comment,
                                                currentUser: currentUser,
                                                isMe: isMe,
                                                showProfile: true,
                                                showAuthorInfo: true,
                                                onReactionToggle: (
                                                  commentId,
                                                  emoji,
                                                ) {
                                                  // TODO: Implement reaction toggle
                                                },
                                                onLongPress: (
                                                  position,
                                                  comment,
                                                ) {
                                                  // TODO: Implement long press menu
                                                },
                                                bounceAnimationValue: 1.0,
                                                isAnimating: false,
                                                onTapTargetComment: (
                                                  commentId,
                                                ) {
                                                  // TODO: Implement tap target comment
                                                },
                                                targetComment: null,
                                                globalKey: GlobalKey(),
                                                onSwipeReply: () {
                                                  // TODO: Implement swipe reply
                                                },
                                                commentService:
                                                    CommentService(),
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  // 댓글 입력창
                                  if (_visibleHeight > 200)
                                    CommentInputSection(
                                      backgroundColor: const Color.fromARGB(
                                        255,
                                        243,
                                        243,
                                        243,
                                      ),
                                      foregroundColor:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      commentController: _commentController,
                                      focusNode: _commentFocus,
                                      replyTarget: null,
                                      editingComment: null,
                                      onSubmit: _submitComment,
                                      onCancelReply: () {},
                                      onCancelEdit: () {},
                                    ),
                                ],
                              ),
                            )
                            : const SizedBox.shrink(),
                  ),
                );
              },
            ),

            // 댓글 미리보기 (초반에만 나타남)
            AnimatedBuilder(
              animation: _commentsController,
              builder: (context, child) {
                if (_imageComments.isEmpty ||
                    _commentsController.value >= 0.1) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  bottom: 50,
                  left: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 댓글 미리보기 (최대 2개) - 애니메이션 적용
                      ...List.generate(
                        _imageComments.length > 2 ? 2 : _imageComments.length,
                        (index) {
                          if (index < _commentPreviewControllers.length) {
                            return AnimatedBuilder(
                              animation: _commentPreviewControllers[index],
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: Offset(
                                    0,
                                    20 *
                                        (1 -
                                            _commentPreviewControllers[index]
                                                .value),
                                  ),
                                  child: Opacity(
                                    opacity:
                                        _commentPreviewControllers[index].value,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: GestureDetector(
                                        onTap: () {
                                          showComments();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.4,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Text(
                                            _imageComments[index].content,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

            Positioned(
              top: MediaQuery.of(context).padding.top,
              left: 16,
              child: GestureDetector(
                onTap: _closeViewer,
                child: Container(
                  padding: const EdgeInsets.all(6),

                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),

            if (!widget.isVideo)
              Positioned(
                top: MediaQuery.of(context).padding.top,
                right: 16,
                child: GestureDetector(
                  onTap: _downloadImage,
                  child: Container(
                    padding: const EdgeInsets.all(6),

                    child: const Icon(
                      Icons.download_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),

            // 닷 인디케이터 (스와이프 가능 표시, 댓글이 열려있으면 숨김)
            if (widget.allImageUrls.length > 1)
              Builder(
                builder: (context) {
                  if (_commentsController.value > 0.1) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          widget.allImageUrls.length,
                          (index) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
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
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// 비디오 플레이어 위젯 (간단 버전)
class _VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final VideoPlayerController? preloadedController;
  final bool hideScrubber; // 댓글 올라왔을 때 시크바 숨김
  final TransformationController? zoomController; // 확대 제어 전달용
  final bool lockInteraction; // 상위 시트 열림 시 인터랙션 잠금

  const _VideoPlayerWidget({
    required this.url,
    this.autoPlay = true,
    this.preloadedController,
    this.hideScrubber = false,
    this.zoomController,
    this.lockInteraction = false,
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPreloaded = false; // 프리로드된 컨트롤러인지 여부
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isSeeking = false;
  bool _wasPlayingBeforeSeek = false;
  Duration? _targetSeekPosition; // 드래그 중 목표 위치
  double _gestureMinScale = 1.0; // 강한 축소 감지를 위한 최소 스케일

  bool _isVideoZoomed() {
    try {
      final ctrl = widget.zoomController;
      if (ctrl == null) return false;
      final m = ctrl.value;
      final sx = m.storage[0];
      final sy = m.storage[5];
      final s = (sx + sy) / 2.0;
      return s > 1.01;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() async {
    try {
      if (widget.preloadedController != null) {
        // 프리로드된 컨트롤러 사용 (이미 초기화됨)
        _controller = widget.preloadedController!;
        _isPreloaded = true;

        // 이미 초기화되어 있으므로 즉시 사용 가능
        if (_controller.value.isInitialized) {
          _isInitialized = true;

          // 볼륨만 복원 (프리로드 시 무음이었음)
          await _controller.setVolume(1.0);

          _duration = _controller.value.duration;
          _position = _controller.value.position;

          print(
            '[FullscreenVideo] 프리로드 컨트롤러 재사용 - 현재 위치: ${_position.inSeconds}초',
          );
        } else {
          // 혹시 초기화 안 되어 있으면 초기화
          await _controller.initialize();
          _duration = _controller.value.duration;
          _position = _controller.value.position;
        }
      } else {
        // 새 컨트롤러 생성 및 초기화
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        await _controller.initialize();
        _isPreloaded = false;
        _duration = _controller.value.duration;
        _position = _controller.value.position;
      }

      // 컨트롤러 상태 리스너로 진행도/재생 상태 갱신
      _controller.addListener(_onControllerTick);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // autoPlay가 true면 재생 시작
        if (widget.autoPlay && !_controller.value.isPlaying) {
          await _controller.play();
          print('[FullscreenVideo] 자동 재생 시작');
        }
      }
    } catch (e) {
      print('비디오 초기화 오류: $e');
    }
  }

  void _onControllerTick() {
    if (!mounted) return;
    if (_isSeeking) {
      // 드래그 중에는 타겟 포지션 사용
      if (_targetSeekPosition != null) {
        setState(() {
          _position = _targetSeekPosition!;
          _duration = _controller.value.duration;
        });
      }
      return;
    }
    final value = _controller.value;
    setState(() {
      _duration = value.duration;
      _position = value.position;
    });
  }

  @override
  void dispose() {
    // 리스너만 정리 (컨트롤러는 유지)
    try {
      if (_isInitialized) {
        _controller.removeListener(_onControllerTick);

        // 프리로드된 컨트롤러가 아닌 경우만 dispose
        // (직접 생성한 컨트롤러는 정리해야 함)
        if (!_isPreloaded) {
          _controller.pause();
          _controller.dispose();
          print('[FullscreenVideo] 새로 생성한 컨트롤러 dispose');
        } else {
          // 프리로드 컨트롤러는 아무것도 하지 않음
          // (재생 유지, PostReaderScreen에서만 dispose)
          print('[FullscreenVideo] 프리로드 컨트롤러 유지 (재생 계속)');
        }
      }
    } catch (e) {
      print('비디오 플레이어 정리 중 오류: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool isPlaying = _controller.value.isPlaying;
    final double maxMs =
        _duration.inMilliseconds > 0
            ? _duration.inMilliseconds.toDouble()
            : 1.0;
    final double posMs = _position.inMilliseconds.clamp(0, maxMs).toDouble();

    // 비디오 비율 계산 (16:9 이상이면 가로로 긴 영상)
    final double aspectRatio =
        _controller.value.size.width / _controller.value.size.height;
    final BoxFit videoFit =
        aspectRatio >= 16.0 / 9.0 ? BoxFit.contain : BoxFit.cover;

    return Stack(
      children: [
        // 영상
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_controller.value.isPlaying) {
                _controller.pause();
              } else {
                _controller.play();
              }
              setState(() {});
            },
            child: Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: widget.lockInteraction ? 1.0 : 4.0,
                panEnabled: !widget.lockInteraction && _isVideoZoomed(),
                scaleEnabled: !widget.lockInteraction,
                boundaryMargin:
                    widget.lockInteraction || !_isVideoZoomed()
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(200),
                clipBehavior: Clip.none,
                onInteractionStart: (_) {
                  _gestureMinScale = 1.0;
                },
                onInteractionUpdate: (details) {
                  _gestureMinScale =
                      _gestureMinScale < details.scale
                          ? _gestureMinScale
                          : details.scale;
                  setState(() {});
                },
                onInteractionEnd: (_) {
                  if (_gestureMinScale < 0.98) {
                    // 조금이라도 축소하면 정확히 원래 위치/크기로 리셋
                    final ctrl =
                        widget.zoomController ?? TransformationController();
                    ctrl.value = Matrix4.identity();
                  }
                  _gestureMinScale = 1.0;
                  setState(() {});
                },
                transformationController: widget.zoomController,
                child: FittedBox(
                  fit: videoFit,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 중앙 재생 아이콘 (일시정지 상태일 때만)
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
        // 댓글이 열려있지 않을 때만 시크바 표시
        if (!widget.hideScrubber)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _isSeeking = true;
                _wasPlayingBeforeSeek = _controller.value.isPlaying;
                // 첫 프레임 끊김 방지를 위해 첫 업데이트에서는 seek 건너뜀
                // 또한 드래그 시작 시 즉시 pause하지 않음(초기 끊김 완화)
              },
              onHorizontalDragUpdate: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final localPosition = details.localPosition.dx - 15; // 패딩 보정
                final width = box.size.width - 30; // 좌우 패딩 제외

                // 0.0 ~ 1.0 비율 계산
                final ratio = (localPosition / width).clamp(0.0, 1.0);
                final newMs = (maxMs * ratio).floor();
                final newPosition = Duration(milliseconds: newMs);

                _targetSeekPosition = newPosition;
                // 첫 업데이트에서는 seek 생략 → 첫 끊김 완화
                if (_isSeeking &&
                    _position == Duration.zero &&
                    _controller.value.position == Duration.zero) {
                  // UI만 먼저 갱신하고 다음 업데이트부터 seek 수행
                } else {
                  _controller.seekTo(newPosition);
                }

                setState(() {
                  _position = newPosition;
                });
              },
              onHorizontalDragEnd: (details) async {
                if (_targetSeekPosition != null) {
                  try {
                    // 최종 위치로 정확하게 seek
                    await _controller.seekTo(_targetSeekPosition!);
                  } catch (e) {
                    print('Seek 오류: $e');
                  }

                  setState(() {
                    _position = _targetSeekPosition!;
                  });
                }

                // seek 완료 후 재생 재개
                if (_wasPlayingBeforeSeek) {
                  _controller.play();
                }

                _isSeeking = false;
                _targetSeekPosition = null;
              },
              child: Container(
                height: 40, // 터치 영역 확대
                color: Colors.transparent,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 배경 트랙 (전체)
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // 진행 트랙 (현재 위치까지)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor:
                            maxMs > 0 ? (posMs / maxMs).clamp(0.0, 1.0) : 0.0,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
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
}
