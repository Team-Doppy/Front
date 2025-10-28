import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/comment_service.dart';
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
  final Duration? initialPosition; // 비디오 초기 재생 위치
  final VideoPlayerController? preloadedController; // 이미 초기화된 컨트롤러 주입

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.onClose,
    this.allImageUrls = const [],
    this.initialIndex = 0,
    this.isVideo = false,
    this.initialPosition,
    this.preloadedController,
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

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _fadeController.forward();

    _commentsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

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

  void _loadImageComments() {
    // 현재 이미지에 대한 댓글이 없으면 초기화
    if (!_commentsByImage.containsKey(_currentImageUrl)) {
      _commentsByImage[_currentImageUrl] = [
        Comment(
          id: '1',
          author: 'testuser1',
          content: '이미지 정말 예쁘네요! 👏',
          authorProfileImageUrl: '',
          postId: '0',
          imageUrl: _currentImageUrl,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
        Comment(
          id: '2',
          author: 'testuser2',
          content: '저도 이런 곳 가고 싶어요',
          authorProfileImageUrl: '',
          postId: '0',
          imageUrl: _currentImageUrl,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ];
    }

    setState(() {
      // 애니메이션 다시 초기화
      _disposeCommentPreviewControllers();
      _commentPreviewControllers.clear();
    });

    // 애니메이션 다시 실행
    _initCommentPreviewAnimations();
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

    setState(() {
      final newComment = Comment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        author: '내 댓글',
        content: text,
        authorProfileImageUrl: '',
        postId: '0',
        imageUrl: _currentImageUrl,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      _commentsByImage[_currentImageUrl] = [..._imageComments, newComment];
      _commentController.clear();
    });
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta! < 0 && _commentsController.value < 1.0) {
          // 위로 드래그: 댓글 열기
          final delta = -details.primaryDelta! / 300; // 민감도 조절
          setState(() {
            _commentsController.value = (_commentsController.value + delta)
                .clamp(0.0, 1.0);
          });
        } else if (details.primaryDelta! > 0 &&
            _commentsController.value > 0.0) {
          // 아래로 드래그: 댓글 닫기
          final delta = details.primaryDelta! / 300;
          setState(() {
            _commentsController.value = (_commentsController.value - delta)
                .clamp(0.0, 1.0);
          });
        } else if (details.primaryDelta! > 0 &&
            _commentsController.value == 0) {
          // 댓글이 완전히 닫혀있을 때만 화면 닫기
          setState(() {
            _dragOffset += details.primaryDelta!;
          });
        }
      },
      onVerticalDragEnd: (details) {
        // velocity가 있으면 방향에 따라 바로 완료
        if (details.primaryVelocity! < -300) {
          // 위로 빠르게 스와이프: 완전히 열기
          _commentsController.forward();
        } else if (details.primaryVelocity! > 300) {
          // 아래로 빠르게 스와이프
          if (_commentsController.value > 0.5) {
            // 이미 많이 열려있으면 닫기 (댓글만 닫기)
            _commentsController.reverse();
          } else if (_commentsController.value > 0) {
            // 조금 열려있어도 닫기
            _commentsController.reverse();
          } else if (_commentsController.value == 0) {
            // 댓글이 닫혀있으면 바로 화면 닫기
            _closeViewer();
          }
        } else {
          // velocity가 작으면 현재 위치에 따라 결정
          if (_commentsController.value > 0.5) {
            _commentsController.forward();
          } else if (_commentsController.value > 0) {
            // 댓글이 열려있으면 닫기
            _commentsController.reverse();
          } else if (_commentsController.value == 0 && _dragOffset > 80) {
            // 댓글이 완전히 닫혀있고 아래로 충분히 드래그했을 때만 화면 닫기
            _closeViewer();
          }
        }

        // _dragOffset 리셋
        setState(() {
          _dragOffset = 0.0;
        });
      },
      child: Opacity(
        opacity: (1.0 - _dragOffset / 300).clamp(0.0, 1.0),
        child: Stack(
          children: [
            Container(color: Theme.of(context).colorScheme.surface),

            // 이미지 (전면과 축소를 하나로 통합)
            AnimatedBuilder(
              animation: _commentsController,
              builder: (context, child) {
                final p = _commentsController.value;

                final screenWidth = MediaQuery.of(context).size.width;
                final screenHeight = MediaQuery.of(context).size.height;

                // 초기 이미지 크기 (전체 화면 너비)
                final initialSize = screenWidth;

                // 최종 크기
                final finalSize = (screenWidth - 40) * 0.5;

                // 초기 이미지가 있는 위치 (가운데)
                final initialCenterY = screenHeight / 2;
                final finalCenterY = finalSize / 2 + 60; // 위로 이동

                // 현재 위치 계산 (p^2를 적용하여 더 빠른 이동)
                // p가 0일 때: left=0, top=0, width=screenWidth, height=screenHeight
                // p가 1일 때: left=가운데, top=finalCenterY, width=finalSize, height=finalSize
                final p2 = p * p; // p를 제곱하여 더 빠르게 이동
                final currentSize =
                    initialSize - p2 * (initialSize - finalSize);
                final currentCenterY =
                    initialCenterY - p2 * (initialCenterY - finalCenterY);

                // currentLeft: 중앙 정렬
                final currentLeft = (screenWidth - currentSize) / 2;

                final currentTop =
                    (1 - p) * 0.0 + p * (currentCenterY - currentSize / 2);
                final currentWidth = currentSize;
                final currentHeight = (1 - p) * screenHeight + p * currentSize;

                // p == 0이면 전체 화면 채우기

                return Positioned(
                  left: currentLeft,
                  top: currentTop,
                  width: currentWidth,
                  height: currentHeight,

                  child: Container(
                    margin: EdgeInsets.only(bottom: 40 - (p * 40)),
                    child: ClipRRect(
                      child: GestureDetector(
                        onTap: () {
                          if (p > 0) {
                            // 댓글이 열려있으면 이미지 클릭 시 닫기
                            _commentsController.reverse();
                          }
                        },
                        child: PageView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount:
                              widget.allImageUrls.isNotEmpty
                                  ? widget.allImageUrls.length
                                  : 1,
                          onPageChanged: (index) {
                            setState(() {
                              _currentImageIndex = index;
                            });
                            _loadImageComments(); // 댓글 다시 로드
                          },
                          controller: PageController(
                            initialPage: _currentImageIndex,
                          ),
                          itemBuilder: (context, index) {
                            final mediaUrl =
                                widget.allImageUrls.isNotEmpty
                                    ? widget.allImageUrls[index]
                                    : widget.imageUrl;

                            // 비디오인 경우 VideoPlayer 표시
                            if (widget.isVideo && index == 0) {
                              return Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: _VideoPlayerWidget(
                                      url: mediaUrl,
                                      autoPlay: true,
                                      initialPosition: widget.initialPosition,
                                      preloadedController:
                                          widget.preloadedController,
                                      hideScrubber:
                                          _commentsController.value > 0.1,
                                    ),
                                  ),
                                ),
                              );
                            }

                            // 이미지인 경우
                            return Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: mediaUrl,
                                    fit: BoxFit.contain,
                                    errorWidget:
                                        (context, error, stack) => const Center(
                                          child: Icon(
                                            Icons.error,
                                            color: Colors.white,
                                            size: 50,
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // 댓글 섹션: 위로 스와이프하면 나타남
            AnimatedBuilder(
              animation: _commentsController,
              builder: (context, child) {
                final p = _commentsController.value;

                if (p == 0) return const SizedBox.shrink();

                final screenWidth = MediaQuery.of(context).size.width;

                final finalSize = (screenWidth - 40) * 0.5; // 이미지 크기와 동일하게

                final finalCenterY = finalSize / 2 + 60; // 위로 이동 (이미지 크기와 동일하게)

                // 축소된 이미지의 bottom (고정 위치, 페이드인만)
                final imageBottom = finalCenterY + finalSize / 2;

                return Positioned(
                  top:
                      imageBottom +
                      _commentDragOffset, // 최종 축소된 이미지 바로 아래에 댓글 섹션
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity:
                        (p - 0.9).clamp(0.0, 1.0) /
                        0.1, // p가 0.3 이상일 때부터 나타나기 시작
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.primaryDelta! > 0) {
                          // 아래로 드래그
                          setState(() {
                            _commentDragOffset += details.primaryDelta!;
                          });
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (_commentDragOffset > 100) {
                          // 충분히 내렸으면 댓글 닫기
                          _commentsController.reverse();
                        }
                        // 드래그 오프셋 리셋
                        setState(() {
                          _commentDragOffset = 0.0;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).colorScheme.surface
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),

                        child: Column(
                          children: [
                            SizedBox(height: 15),
                            Container(
                              height: 5,
                              width: 80,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            SizedBox(height: 20),
                            Expanded(
                              child: Consumer<UserProvider>(
                                builder: (context, userProvider, child) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      itemCount: _imageComments.length,
                                      itemBuilder: (context, index) {
                                        final comment = _imageComments[index];
                                        final currentUser =
                                            userProvider.currentUser;
                                        final isMe =
                                            comment.author ==
                                            (currentUser?.id.toString() ?? '');

                                        return CommentItem(
                                          key: GlobalKey(),
                                          comment: comment,
                                          currentUser: currentUser,
                                          isMe: isMe,
                                          showProfile: true,
                                          showAuthorInfo: true,
                                          onReactionToggle: (commentId, emoji) {
                                            // TODO: Implement reaction toggle
                                          },
                                          onLongPress: (position, comment) {
                                            // TODO: Implement long press menu
                                          },
                                          bounceAnimationValue: 1.0,
                                          isAnimating: false,
                                          onTapTargetComment: (commentId) {
                                            // TODO: Implement tap target comment
                                          },
                                          targetComment: null,
                                          globalKey: GlobalKey(),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                            // 댓글 입력창
                            CommentInputSection(
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
                      ),
                    ),
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
                                          setState(() {
                                            _commentsController.forward();
                                          });
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
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: GestureDetector(
                onTap: _closeViewer,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:
                        isDarkMode
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: _downloadImage,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:
                        isDarkMode
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.file_download,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // 닷 인디케이터 (스와이프 가능 표시, 댓글이 열려있으면 숨김)
            if (widget.allImageUrls.length > 1)
              AnimatedBuilder(
                animation: _commentsController,
                builder: (context, child) {
                  if (_commentsController.value > 0.1)
                    return const SizedBox.shrink();

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
                                        ? isDarkMode
                                            ? Colors.white
                                            : Colors.black
                                        : isDarkMode
                                        ? Colors.white.withOpacity(0.3)
                                        : Colors.black.withOpacity(0.2),
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
  final Duration? initialPosition;
  final VideoPlayerController? preloadedController;
  final bool hideScrubber; // 댓글 올라왔을 때 시크바 숨김

  const _VideoPlayerWidget({
    required this.url,
    this.autoPlay = true,
    this.initialPosition,
    this.preloadedController,
    this.hideScrubber = false,
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isSeeking = false;
  bool _wasPlayingBeforeSeek = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() async {
    try {
      if (widget.preloadedController != null) {
        _controller = widget.preloadedController!;
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        await _controller.initialize();
      }

      if (widget.initialPosition != null) {
        await _controller.seekTo(widget.initialPosition!);
      }

      // 컨트롤러 상태 리스너로 진행도/재생 상태 갱신
      _duration = _controller.value.duration;
      _position = _controller.value.position;
      _controller.addListener(_onControllerTick);

      if (mounted && widget.autoPlay) {
        _controller.play();
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('비디오 초기화 오류: $e');
    }
  }

  void _onControllerTick() {
    if (!mounted) return;
    if (_isSeeking) return; // 드래그 중에는 컨트롤러 tick 반영 보류
    final value = _controller.value;
    setState(() {
      _duration = value.duration;
      _position = value.position;
    });
  }

  @override
  void dispose() {
    // 리스너 정리 및 컨트롤러 정지 (dispose하지 않음 - 재사용을 위해)
    try {
      if (_isInitialized) {
        _controller.removeListener(_onControllerTick);
        _controller.pause();
      }
      // dispose하지 않음 - 컨트롤러는 재사용되어야 하므로
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
            child: FittedBox(
              fit: videoFit,
              child: Column(
                children: [
                  SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ],
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
            left: 15,
            right: 15,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
              child: SizedBox(
                width: _controller.value.size.width,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 0,
                    ),
                    activeTrackColor: Theme.of(context).colorScheme.onSurface,
                    inactiveTrackColor: Theme.of(
                      context,
                    ).colorScheme.surface.withOpacity(0.5),
                  ),
                  child: Slider(
                    min: 0,
                    max: maxMs,
                    value: posMs,
                    onChangeStart: (_) {
                      _isSeeking = true;
                      _wasPlayingBeforeSeek = _controller.value.isPlaying;
                      if (_wasPlayingBeforeSeek) {
                        _controller.pause();
                      }
                    },
                    onChanged: (v) {
                      setState(() {
                        _position = Duration(milliseconds: v.floor());
                      });
                    },
                    onChangeEnd: (v) async {
                      try {
                        await _controller.seekTo(
                          Duration(milliseconds: v.floor()),
                        );
                      } catch (_) {}
                      if (_wasPlayingBeforeSeek) {
                        _controller.play();
                      }
                      _isSeeking = false;
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
