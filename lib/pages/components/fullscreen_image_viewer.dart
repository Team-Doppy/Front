import 'dart:ui';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/media_comment_service.dart';
import 'package:doppy/pages/components/media_comment_item.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:doppy/pages/components/fullscreen_video_player.dart';

class FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final VoidCallback? onClose;
  final List<String> allImageUrls;
  final int initialIndex;
  final bool isVideo;
  final VideoPlayerController? preloadedController;
  final String? postTitle;
  final String? postAuthor;
  final String? postAuthorProfileUrl;
  final int? commentCount;
  final ImageProvider? imageProvider; // 이미지 객체 직접 전달

  const FullscreenImageViewer({
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
    this.commentCount,
    this.imageProvider,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  final Map<String, List<MediaComment>> _commentsByImage = {};
  final Map<String, int> _commentPageByImage = {}; // 각 이미지별 현재 페이지
  final Map<String, bool> _hasMoreCommentsByImage = {}; // 각 이미지별 더 가져올 댓글 여부
  final Map<String, bool> _isLoadingMoreByImage = {}; // 각 이미지별 로딩 상태
  final Map<String, bool> _isCommentsLoaded = {}; // 각 이미지별 댓글 로딩 완료 여부
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _commentScrollController = ScrollController();

  // 수정 모드 관련
  MediaComment? _editingComment; // 현재 수정 중인 댓글

  late AnimationController _commentsController;
  late AnimationController _bottomBarController; // 🎯 바텀바 페이드 애니메이션
  late Animation<double> _bottomBarFade;
  double _dragOffset = 0.0;
  double _commentDragOffset = 0.0;
  List<AnimationController> _commentPreviewControllers = [];
  int _currentImageIndex = 0;
  bool _isSheetDraggingDown = false; // 바텀시트 드래그 방향 (내림 감지)
  double _hDragOffset = 0.0; // 오른쪽 스와이프로 닫기 제스처 오프셋
  bool _isDownloading = false; // 이미지 다운로드 중 상태
  final Set<String> _previewShownForImages = {}; // 🎯 댓글 미리보기를 이미 보여준 이미지들
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

      // 🎯 바텀시트가 완전히 닫히면 바텀바 페이드 인
      if (_commentsController.value == 0.0) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _commentsController.value == 0.0) {
            _bottomBarController.forward();
          }
        });
      } else {
        // 바텀시트가 조금이라도 열리면 바텀바 즉시 숨김
        _bottomBarController.value = 0.0;
      }
    });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // 🎯 바텀바 페이드 애니메이션 초기화
    _bottomBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bottomBarFade = CurvedAnimation(
      parent: _bottomBarController,
      curve: Curves.easeOut,
    );

    // 초기 바텀바 표시
    _bottomBarController.value = 1.0;

    // 현재 미디어 인덱스 초기화
    if (widget.allImageUrls.isNotEmpty) {
      final initialIndex = widget.allImageUrls.indexOf(widget.imageUrl);
      _currentImageIndex = initialIndex >= 0 ? initialIndex : 0;
    }

    // 스크롤 리스너 추가 (페이지네이션)
    _commentScrollController.addListener(_onCommentScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadImageComments();
      // 🎯 첫 번째 이미지는 initState에서 미리보기 표시 시도
      _initCommentPreviewAnimations();
    });
  }

  void _onCommentScroll() {
    if (_commentScrollController.position.pixels >=
        _commentScrollController.position.maxScrollExtent - 200) {
      // 하단 200px 남았을 때 다음 페이지 로드
      _loadMoreComments();
    }
  }

  Future<void> _loadMoreComments() async {
    final url = _currentImageUrl;
    final isLoading = _isLoadingMoreByImage[url] ?? false;
    final hasMore = _hasMoreCommentsByImage[url] ?? true;

    if (isLoading || !hasMore) return;

    _isLoadingMoreByImage[url] = true;

    try {
      // 🎯 URL 기반으로 변경
      if (url.isEmpty) return;

      final currentPage = _commentPageByImage[url] ?? 0;
      final nextPage = currentPage + 1;

      debugPrint('[FIV] Loading more comments page=$nextPage url=$url');

      final svc = MediaCommentService();
      final list =
          widget.isVideo
              ? await svc.fetchVideoComments(
                videoUrl: url, // 🎯 URL 사용
                page: nextPage,
                size: 20,
              )
              : await svc.fetchImageComments(
                imageUrl: url, // 🎯 URL 사용
                page: nextPage,
                size: 20,
              );

      // 🎯 서버에서 이미 정렬되어 오므로 클라이언트 정렬 불필요

      if (mounted) {
        setState(() {
          // reverse:true이므로 오래된 댓글(list)을 뒤에 추가
          _commentsByImage[url] = [...(_commentsByImage[url] ?? []), ...list];
          _commentPageByImage[url] = nextPage;
          _hasMoreCommentsByImage[url] = list.length >= 20;
          _isLoadingMoreByImage[url] = false;
        });
      }
    } catch (e) {
      debugPrint('[FIV] Load more failed: $e');
      if (mounted) {
        setState(() {
          _isLoadingMoreByImage[url] = false;
        });
      }
    }
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

    // 🎯 바텀시트 올라갈 때 미리보기 즉시 숨기기
    for (final controller in _commentPreviewControllers) {
      controller.reverse();
    }

    _commentsController.animateTo(
      1.0,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  void hideComments({Duration duration = const Duration(milliseconds: 220)}) {
    // 수정 모드 취소
    if (_editingComment != null) {
      _cancelEdit();
    }

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

  List<MediaComment> get _imageComments {
    final comments = _commentsByImage[_currentImageUrl] ?? [];
    return comments;
  }

  void _initCommentPreviewAnimations() {
    // 🎯 이미 미리보기를 본 이미지면 표시하지 않음
    if (_previewShownForImages.contains(_currentImageUrl)) {
      debugPrint('[FIV] 이미 미리보기를 본 이미지: $_currentImageUrl');
      return;
    }

    // 댓글이 없으면 미리보기 표시 안 함
    if (_imageComments.isEmpty) {
      return;
    }

    // 🎯 미리보기 표시 기록
    _previewShownForImages.add(_currentImageUrl);
    debugPrint('[FIV] 미리보기 표시: $_currentImageUrl');

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

    // 4초 후 댓글 미리보기 숨기기
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted && _commentsController.value < 0.1) {
        for (final controller in _commentPreviewControllers) {
          controller.reverse();
        }
      }
    });
  }

  void _disposeCommentPreviewControllers() {
    for (final controller in _commentPreviewControllers) {
      controller.dispose();
    }
    _commentPreviewControllers.clear();
  }

  Future<void> _loadImageComments() async {
    debugPrint(
      '[FIV] _loadImageComments() start: idx=$_currentImageIndex url=$_currentImageUrl isVideo=${widget.isVideo}',
    );
    try {
      // 🎯 URL 기반으로 변경 - mediaId 없이 URL로 직접 요청
      if (_currentImageUrl.isEmpty) {
        debugPrint('[FIV] skip fetch: url is null or empty');
        setState(() => _commentsByImage[_currentImageUrl] = []);
        return;
      }

      final svc = MediaCommentService();
      final list =
          widget.isVideo
              ? await svc.fetchVideoComments(
                videoUrl: _currentImageUrl, // 🎯 URL 사용
                page: 0,
                size: 20,
              )
              : await svc.fetchImageComments(
                imageUrl: _currentImageUrl, // 🎯 URL 사용
                page: 0,
                size: 20,
              );
      debugPrint('[FIV] fetched list size=${list.length}');

      // 🎯 서버에서 이미 정렬되어 오므로 클라이언트 정렬 불필요
      // (API: sort=createdAt,desc)

      setState(() {
        _commentsByImage[_currentImageUrl] = list;
        _commentPageByImage[_currentImageUrl] = 0;
        _hasMoreCommentsByImage[_currentImageUrl] = list.length >= 20;
        _isLoadingMoreByImage[_currentImageUrl] = false;
        _isCommentsLoaded[_currentImageUrl] = true; // 🎯 로딩 완료 플래그
      });

      // 🎯 미리보기 초기화 (이미 본 이미지가 아닐 때만)
      _disposeCommentPreviewControllers();
      _commentPreviewControllers.clear();
      _initCommentPreviewAnimations();
    } catch (e) {
      debugPrint('[FIV] fetch failed: $e');
      setState(() {
        _commentsByImage[_currentImageUrl] = [];
        _commentPageByImage[_currentImageUrl] = 0;
        _hasMoreCommentsByImage[_currentImageUrl] = false;
        _isLoadingMoreByImage[_currentImageUrl] = false;
        _isCommentsLoaded[_currentImageUrl] = true; // 🎯 로딩 완료 플래그 (실패해도)
      });
    }
  }

  Future<void> _toggleCommentLike(MediaComment comment) async {
    try {
      // 🎯 URL 기반으로 변경
      if (_currentImageUrl.isEmpty) return;

      final svc = MediaCommentService();

      // 🎯 낙관적 업데이트 (즉시 UI 반영)
      final newIsLiked = !comment.isLiked;
      final newLikeCount =
          comment.isLiked ? comment.likeCount - 1 : comment.likeCount + 1;

      setState(() {
        final currentComments = _commentsByImage[_currentImageUrl] ?? [];
        final index = currentComments.indexWhere((c) => c.id == comment.id);
        if (index != -1) {
          currentComments[index] = currentComments[index].copyWith(
            isLiked: newIsLiked,
            likeCount: newLikeCount,
          );
        }
      });

      // 🎯 서버 요청 (간소화된 API)
      final updatedComment =
          widget.isVideo
              ? await svc.toggleVideoCommentLike(
                videoUrl: _currentImageUrl, // 🎯 URL 사용
                commentId: comment.id,
              )
              : await svc.toggleImageCommentLike(
                imageUrl: _currentImageUrl, // 🎯 URL 사용
                commentId: comment.id,
              );

      // 서버 응답으로 최종 확정
      if (mounted) {
        setState(() {
          final currentComments = _commentsByImage[_currentImageUrl] ?? [];
          final index = currentComments.indexWhere((c) => c.id == comment.id);
          if (index != -1) {
            currentComments[index] = currentComments[index].copyWith(
              isLiked: updatedComment.isLiked,
              likeCount: updatedComment.likeCount,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('[FIV] toggle like failed: $e');
      // 롤백
      if (mounted) {
        setState(() {
          final currentComments = _commentsByImage[_currentImageUrl] ?? [];
          final index = currentComments.indexWhere((c) => c.id == comment.id);
          if (index != -1) {
            currentComments[index] = comment; // 원본으로 복구
          }
        });
      }
    }
  }

  void _navigateToProfile(BuildContext context, String? username) {
    if (username == null || username.isEmpty) return;

    // User 객체로 변환
    final user = User(username: username, profileImageUrl: '');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(otherUser: user),
      ),
    );
  }

  Future<void> _deleteComment(MediaComment comment) async {
    // 롤백용 백업
    final backupComments = List<MediaComment>.from(_imageComments);

    try {
      // 🎯 URL 기반으로 변경
      if (_currentImageUrl.isEmpty) return;

      // 낙관적 삭제
      setState(() {
        _commentsByImage[_currentImageUrl] =
            _imageComments.where((c) => c.id != comment.id).toList();
      });

      debugPrint('[FIV] 댓글 낙관적 삭제 - 새 개수: ${_imageComments.length}');

      // 서버 요청
      final svc = MediaCommentService();
      widget.isVideo
          ? await svc.deleteVideoComment(
            videoUrl: _currentImageUrl, // 🎯 URL 사용
            commentId: comment.id,
          )
          : await svc.deleteImageComment(
            imageUrl: _currentImageUrl, // 🎯 URL 사용
            commentId: comment.id,
          );

      debugPrint('[FIV] delete comment success id=${comment.id}');
    } catch (e) {
      debugPrint('[FIV] delete comment failed: $e');
      // 롤백
      if (mounted) {
        setState(() {
          _commentsByImage[_currentImageUrl] = backupComments;
        });
        ErrorHandler.showError(context, context.tr('comment_delete_failed'));
      }
    }
  }

  void _startEditComment(MediaComment comment) {
    setState(() {
      _editingComment = comment;
      _commentController.text = comment.text;
    });
    _commentFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingComment = null;
      _commentController.clear();
    });
  }

  Future<void> _saveEdit() async {
    if (_editingComment == null) return;

    final newText = _commentController.text.trim();
    if (newText.isEmpty || newText == _editingComment!.text) {
      _cancelEdit();
      return;
    }

    final comment = _editingComment!;
    // 롤백용 백업
    final backupComments = List<MediaComment>.from(_imageComments);

    setState(() {
      _editingComment = null;
      _commentController.clear();
    });

    try {
      // 🎯 URL 기반으로 변경
      if (_currentImageUrl.isEmpty) return;

      // 낙관적 업데이트
      setState(() {
        final currentComments = _commentsByImage[_currentImageUrl] ?? [];
        final index = currentComments.indexWhere((c) => c.id == comment.id);
        if (index != -1) {
          currentComments[index] = currentComments[index].copyWith(
            text: newText,
            updatedAt: DateTime.now().toIso8601String(),
          );
        }
      });

      // 서버 요청
      final svc = MediaCommentService();
      final updatedComment =
          widget.isVideo
              ? await svc.updateVideoComment(
                videoUrl: _currentImageUrl, // 🎯 URL 사용
                commentId: comment.id,
                text: newText,
              )
              : await svc.updateImageComment(
                imageUrl: _currentImageUrl, // 🎯 URL 사용
                commentId: comment.id,
                text: newText,
              );

      // 서버 응답으로 최종 업데이트
      if (mounted) {
        setState(() {
          final currentComments = _commentsByImage[_currentImageUrl] ?? [];
          final index = currentComments.indexWhere((c) => c.id == comment.id);
          if (index != -1) {
            currentComments[index] = updatedComment;
          }
        });
      }
      debugPrint('[FIV] update comment success id=${comment.id}');
    } catch (e) {
      debugPrint('[FIV] update comment failed: $e');
      // 롤백
      if (mounted) {
        setState(() {
          _commentsByImage[_currentImageUrl] = backupComments;
        });
        ErrorHandler.showError(context, context.tr('comment_edit_failed'));
      }
    }
  }

  @override
  void dispose() {
    // 모든 컨트롤러와 리스너 정리
    try {
      _commentScrollController.removeListener(_onCommentScroll);
      _commentScrollController.dispose();
      _fadeController.dispose();
      _commentsController.dispose();
      _bottomBarController.dispose();
      _commentController.dispose();
      _commentFocus.dispose();
      _disposeCommentPreviewControllers();

      // 댓글 Map 초기화
      _commentsByImage.clear();
      _commentPageByImage.clear();
      _hasMoreCommentsByImage.clear();
      _isLoadingMoreByImage.clear();
    } catch (e) {
      debugPrint('FullscreenImageViewer dispose 중 오류: $e');
    }
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    // 🎯 URL 기반으로 변경
    if (_currentImageUrl.isEmpty) {
      ErrorHandler.showError(context, context.tr('message_send_error'));
      return;
    }

    // 낙관적 추가 (맨 앞에 삽입 - reverse:true이므로 맨 아래에 표시됨)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final prev = List<MediaComment>.from(_imageComments);
    final currentUser = context.read<UserProvider>().currentUser;

    final utcNow = DateTime.now().toUtc().toIso8601String();

    setState(() {
      _commentsByImage[_currentImageUrl] = [
        MediaComment(
          id: tempId,
          author: currentUser?.username ?? '',
          text: text,
          authorProfileImageUrl: currentUser?.profileImageUrl ?? '',
          createdAt: utcNow, // 🎯 UTC 시간 사용
          updatedAt: utcNow, // 🎯 UTC 시간 사용
        ),
        ..._imageComments,
      ];
      _commentController.clear();
    });

    try {
      debugPrint(
        '[FIV] POST message url=$_currentImageUrl text="$text" isVideo=${widget.isVideo}',
      );
      final svc = MediaCommentService();
      final newId =
          widget.isVideo
              ? await svc.createVideoComment(
                videoUrl: _currentImageUrl,
                text: text,
              ) // 🎯 URL 사용
              : await svc.createImageComment(
                imageUrl: _currentImageUrl,
                text: text,
              ); // 🎯 URL 사용
      debugPrint('[FIV] POST result id=$newId');

      if (!mounted) return;

      setState(() {
        final list = List<MediaComment>.from(_imageComments);
        final idx = list.indexWhere((c) => c.id == tempId);
        if (idx != -1 && newId.isNotEmpty) {
          list[idx] = list[idx].copyWith(id: newId);
          _commentsByImage[_currentImageUrl] = list;
        }
      });

      // 🎯 댓글 제출 후에는 미리보기 재초기화 안 함 (한 번만 표시)
    } catch (e) {
      debugPrint('[FIV] POST failed: $e');
      if (!mounted) return;

      setState(() {
        _commentsByImage[_currentImageUrl] = prev;
        _commentController.text = text;
      });
      ErrorHandler.showError(context, context.tr('comment_send_failed'));
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
    if (_isDownloading) return; // 중복 클릭 방지

    setState(() => _isDownloading = true);

    try {
      // 이미지 다운로드
      final response = await http.get(Uri.parse(_currentImageUrl));

      if (response.statusCode == 200) {
        // 🎯 갤러리에 직접 저장
        final result = await ImageGallerySaver.saveImage(
          response.bodyBytes,
          quality: 100,
          name: 'doppy_image_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          setState(() => _isDownloading = false);

          // 저장 성공 여부 확인
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
      debugPrint('[FIV] download failed: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ErrorHandler.showError(context, context.tr('image_save_failed'));
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

                // 아래로 드래그 시작 시 수정 모드 취소
                if (details.primaryDelta! > 0 && _editingComment != null) {
                  _cancelEdit();
                }

                if (details.primaryDelta! < 0 &&
                    _commentsController.value < 1.0) {
                  // 🎯 위로 드래그 시작하면 미리보기 즉시 숨기기
                  if (_commentsController.value < 0.05) {
                    for (final controller in _commentPreviewControllers) {
                      controller.reverse();
                    }
                  }

                  // 위로 드래그: 메시지 창 열기 (둔감하게: 600으로 증가)
                  final delta =
                      -details.primaryDelta! / 600; // 🎯 민감도 낮춤 (300 → 600)
                  setState(() {
                    _commentsController.value =
                        (_commentsController.value + delta).clamp(0.0, 1.0);
                  });
                } else if (details.primaryDelta! > 0 &&
                    _commentsController.value > 0.0) {
                  // 아래로 드래그: 메시지 창 닫기 (둔감하게: 600으로 증가)
                  final delta =
                      details.primaryDelta! / 600; // 🎯 민감도 낮춤 (300 → 600)
                  setState(() {
                    _commentsController.value =
                        (_commentsController.value - delta).clamp(0.0, 1.0);
                  });
                } else if (details.primaryDelta! > 0 &&
                    _commentsController.value == 0.0) {
                  // 메시지 창 닫힌 상태에서 아래로 드래그: 뷰어 닫기
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
                      : widget.imageProvider != null
                      ? Image(
                        image: widget.imageProvider!,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stack) => const Icon(Icons.error),
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
            // 🎯 키보드 상태에 따라 BackdropFilter 최적화
            AnimatedBuilder(
              animation: _commentsController,
              builder: (context, child) {
                final baseColor = Colors.black.withOpacity(0.75);
                final keyboardVisible =
                    MediaQuery.of(context).viewInsets.bottom > 0;

                // 🎯 키보드가 올라와 있을 때는 blur를 줄여서 성능 개선
                final blurSigma = keyboardVisible ? 5.0 : 10.0;

                // 🎯 RepaintBoundary로 감싸서 불필요한 repaint 방지
                return Positioned.fill(
                  child: RepaintBoundary(
                    child: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blurSigma,
                          sigmaY: blurSigma,
                        ),
                        child: Container(
                          // 🎯 AnimatedContainer 대신 일반 Container 사용 (애니메이션이 필요 없음)
                          color: baseColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
              // 🎯 child를 사용하여 불필요한 rebuild 방지
              child: RepaintBoundary(
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(color: Colors.black.withOpacity(0.75)),
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
                    // 시트와의 간격 제거 (오버플로우 방지)
                    margin: EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () {
                        if (p > 0) {
                          _commentsController.reverse();
                        }
                      },
                      child: PageView.builder(
                        physics:
                            (_commentsController.value > 0.05 || _zoomed)
                                ? const NeverScrollableScrollPhysics()
                                : const ClampingScrollPhysics(),
                        itemCount:
                            widget.allImageUrls.isNotEmpty
                                ? widget.allImageUrls.length
                                : 1,
                        onPageChanged: (index) {
                          // 🎯 페이지 전환 시 미리보기 즉시 숨기기
                          for (final controller in _commentPreviewControllers) {
                            controller.reverse();
                          }

                          setState(() {
                            _currentImageIndex = index;
                          });

                          _loadImageComments();
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
                          if (widget.isVideo && index == 0) {
                            return Center(
                              child: FullscreenVideoPlayer(
                                url: mediaUrl,
                                autoPlay: true,
                                preloadedController: widget.preloadedController,
                                hideScrubber: _commentsController.value > 0.1,
                                zoomController: _videoZoomController,
                                lockInteraction:
                                    _commentsController.value > 0.05,
                                hasBottomBar:
                                    widget.postTitle != null, // 바텀바 유무 전달
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
                                    child:
                                        index == widget.initialIndex &&
                                                widget.imageProvider != null
                                            ? Image(
                                              image: widget.imageProvider!,
                                              fit: BoxFit.contain,
                                              errorBuilder:
                                                  (context, error, stack) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons.error,
                                                          color: Colors.white,
                                                          size: 50,
                                                        ),
                                                      ),
                                            )
                                            : CachedNetworkImage(
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
                    currentTop +
                    currentHeight +
                    _commentDragOffset; // 오버플로우 방지: 간격 제거

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

                      // 🎯 위로 드래그 시작하면 미리보기 즉시 숨기기
                      if (dy < 0 && _commentsController.value < 0.05) {
                        for (final controller in _commentPreviewControllers) {
                          controller.reverse();
                        }
                      }

                      // 아래로 드래그 시작 시 수정 모드 취소
                      if (dy > 0 && _editingComment != null) {
                        _cancelEdit();
                      }

                      // 바텀시트를 끌면 p값을 직접 조정 → 이미지와 상호 연동
                      // 양수(down)일수록 p 감소(닫힘), 음수(up)일수록 p 증가(열림)
                      final sensitivity =
                          600.0; // 🎯 둔감하게: 600px에 1.0 변화 (300 → 600)
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
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(30),
                                  topRight: Radius.circular(30),
                                ),
                              ),

                              child: Column(
                                children: [
                                  SizedBox(height: 10),
                                  Container(
                                    width: 50,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 10),

                                        Text(
                                          '${context.tr('comments')} (${_imageComments.length})',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(1),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),

                                        const Spacer(),
                                        GestureDetector(
                                          onTap: hideComments,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Icon(
                                              Icons.close,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.9),
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Expanded(
                                    child:
                                        _imageComments.isEmpty
                                            ? Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                                      child: Text(
                                                        context.tr(
                                                          'first_comment',
                                                        ),
                                                        style: TextStyle(
                                                          color: Colors.white70,
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
                                            )
                                            : GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                // 리스트 영역 탭하면 키보드 내리기
                                                FocusScope.of(
                                                  context,
                                                ).unfocus();
                                              },
                                              child: RawScrollbar(
                                                controller:
                                                    _commentScrollController,
                                                thumbColor: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.5),
                                                thickness: 3,
                                                radius: const Radius.circular(
                                                  2,
                                                ),
                                                child: ListView.builder(
                                                  controller:
                                                      _commentScrollController,
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                        bottom: 8,
                                                      ),
                                                  itemCount:
                                                      _imageComments.length +
                                                      (_hasMoreCommentsByImage[_currentImageUrl] ??
                                                              false
                                                          ? 1
                                                          : 0),
                                                  itemBuilder: (
                                                    context,
                                                    index,
                                                  ) {
                                                    // 로딩 인디케이터
                                                    if (index ==
                                                        _imageComments.length) {
                                                      return const Padding(
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              vertical: 16,
                                                            ),
                                                        child: Center(
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        ),
                                                      );
                                                    }

                                                    final comment =
                                                        _imageComments[index];
                                                    final currentUser =
                                                        context
                                                            .read<
                                                              UserProvider
                                                            >()
                                                            .currentUser;
                                                    final isMe =
                                                        currentUser != null &&
                                                        comment.author ==
                                                            currentUser
                                                                .username;

                                                    return MediaCommentItem(
                                                      comment: comment,
                                                      isMe: isMe,
                                                      isLast:
                                                          index ==
                                                              _imageComments
                                                                      .length -
                                                                  1 &&
                                                          !(_hasMoreCommentsByImage[_currentImageUrl] ??
                                                              false),
                                                      onReply: () {
                                                        // TODO: 답글 기능
                                                      },
                                                      onLike:
                                                          () =>
                                                              _toggleCommentLike(
                                                                comment,
                                                              ),
                                                      onProfileTap:
                                                          () =>
                                                              _navigateToProfile(
                                                                context,
                                                                comment.author,
                                                              ),
                                                      onEdit:
                                                          () =>
                                                              _startEditComment(
                                                                comment,
                                                              ),
                                                      onDelete:
                                                          () => _deleteComment(
                                                            comment,
                                                          ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                  ),
                                  // 댓글 입력창 (p값이 0.3 이상일 때만 표시 - 안정적)
                                  if (p >= 0.95)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 0,
                                      ),
                                      child: SafeArea(
                                        top: false,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Divider(
                                              height: 0.5,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.1),
                                            ),
                                            // 수정 중 헤더
                                            if (_editingComment != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 16,
                                                  right: 0,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      context.tr(
                                                        'editing_comment',
                                                      ),
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.6),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    IconButton(
                                                      onPressed: _cancelEdit,
                                                      icon: Icon(
                                                        Icons.close,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.6),
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            // 입력 필드
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    cursorColor:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                    controller:
                                                        _commentController,
                                                    focusNode: _commentFocus,
                                                    style: TextStyle(
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onBackground,
                                                      fontSize: 14,
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          _editingComment !=
                                                                  null
                                                              ? AppLocalizations.of(
                                                                context,
                                                              ).translate(
                                                                'write_comment',
                                                              )
                                                              : AppLocalizations.of(
                                                                context,
                                                              ).translate(
                                                                'leave_reaction',
                                                              ),
                                                      hintStyle: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onBackground
                                                            .withOpacity(0.5),
                                                        fontSize: 14,
                                                      ),
                                                      filled: false,
                                                      border: InputBorder.none,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 16,
                                                            vertical: 0,
                                                          ),
                                                    ),
                                                    // ✅ 여러 줄 입력 설정
                                                    keyboardType:
                                                        TextInputType.multiline,
                                                    textInputAction:
                                                        TextInputAction
                                                            .newline, // 엔터 시 줄바꿈
                                                    maxLines: null, // 무제한 줄
                                                    // ❌ onSubmitted 제거 (엔터를 줄바꿈으로 쓰기 위해)
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap:
                                                      _editingComment != null
                                                          ? _saveEdit
                                                          : _submitComment,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 12,
                                                        ),
                                                    child: Icon(
                                                      Icons.send,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurface,
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                            : const SizedBox.shrink(),
                  ),
                );
              },
            ),

            // 메시지 미리보기 (초반에만 나타남)
            AnimatedBuilder(
              animation: _commentsController,
              builder: (context, child) {
                if (_commentsController.value >= 0.1) {
                  return const SizedBox.shrink();
                }

                final bottomOffset = widget.postTitle != null ? 100 : 60;

                return Positioned(
                  bottom: bottomOffset.toDouble() + 18,
                  left: 10,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 댓글 미리보기 (최대 2개) - 애니메이션 적용
                      ...List.generate(
                        _imageComments.length > 2 ? 2 : _imageComments.length,
                        (index) {
                          if (index < _commentPreviewControllers.length) {
                            final comment = _imageComments[index];
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
                                        onTap: () => showComments(),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 15,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            comment.text,
                                            style: const TextStyle(
                                              color: Colors.black,
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

                  child: const Icon(Icons.close, color: Colors.white, size: 26),
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
                    child:
                        _isDownloading
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
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

            // 포스트 정보 바텀바 (댓글이 열려있지 않을 때만 표시, 페이드 애니메이션)
            if (widget.postTitle != null || widget.postAuthor != null)
              Builder(
                builder: (context) {
                  if (_commentsController.value > 0.1) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _bottomBarFade,
                      child: Container(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                          bottom: MediaQuery.of(context).padding.bottom + 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            // 프로필 사진
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
                                  size: 45,
                                  borderWidth: 1,
                                ),
                              ),
                            const SizedBox(width: 12),
                            // 제목 + 저자
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.postTitle != null)
                                    Text(
                                      widget.postTitle!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (widget.postAuthor != null)
                                    Text(
                                      widget.postAuthor!,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 댓글 아이콘 + 개수 (로드 완료 후에만 표시)
                            if (_isCommentsLoaded[_currentImageUrl] == true)
                              GestureDetector(
                                onTap: showComments,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SvgPicture.asset(
                                      'assets/icons/comment.svg',
                                      color: Colors.white,
                                      width: 24,
                                      height: 24,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_imageComments.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // 닷 인디케이터 (스와이프 가능 표시, 댓글이 열려있으면 숨김, 페이드 애니메이션)
            if (widget.allImageUrls.length > 1)
              Builder(
                builder: (context) {
                  if (_commentsController.value > 0.1) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: widget.postTitle != null ? 120 : 30,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _bottomBarFade,
                      child: Center(
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
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
