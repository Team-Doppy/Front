import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/media_comment_service.dart';
import 'package:doppy/data/models/user_model.dart';

/// 풀스크린 이미지 뷰어에서 미디어 댓글을 관리하는 컨트롤러
class FullscreenMediaCommentController extends ChangeNotifier {
  final bool isVideo;
  final String Function() getCurrentImageUrl;

  final Map<String, List<MediaComment>> _commentsByImage = {};
  final Map<String, int> _commentPageByImage = {};
  final Map<String, bool> _hasMoreCommentsByImage = {};
  final Map<String, bool> _isLoadingMoreByImage = {};
  final Map<String, bool> _isCommentsLoaded = {};

  final MediaCommentService _commentService = MediaCommentService();

  FullscreenMediaCommentController({
    required this.isVideo,
    required this.getCurrentImageUrl,
  });

  // Getters
  Map<String, List<MediaComment>> get commentsByImage =>
      Map.unmodifiable(_commentsByImage);
  Map<String, int> get commentPageByImage =>
      Map.unmodifiable(_commentPageByImage);
  Map<String, bool> get hasMoreCommentsByImage =>
      Map.unmodifiable(_hasMoreCommentsByImage);
  Map<String, bool> get isLoadingMoreByImage =>
      Map.unmodifiable(_isLoadingMoreByImage);
  Map<String, bool> get isCommentsLoaded => Map.unmodifiable(_isCommentsLoaded);

  List<MediaComment> getCommentsForUrl(String url) {
    return _commentsByImage[url] ?? [];
  }

  bool hasMoreComments(String url) {
    return _hasMoreCommentsByImage[url] ?? true;
  }

  bool isLoadingMore(String url) {
    return _isLoadingMoreByImage[url] ?? false;
  }

  bool isCommentsLoadedForUrl(String url) {
    return _isCommentsLoaded[url] ?? false;
  }

  /// 댓글 초기 로드
  Future<void> loadComments() async {
    final url = getCurrentImageUrl();

    // 🎯 URL 기반으로 변경
    if (url.isEmpty) {
      _commentsByImage[url] = [];
      _isCommentsLoaded[url] = true;
      notifyListeners();
      return;
    }

    try {
      final list =
          isVideo
              ? await _commentService.fetchVideoComments(
                videoUrl: url, // 🎯 URL 사용
                page: 0,
                size: 20,
              )
              : await _commentService.fetchImageComments(
                imageUrl: url, // 🎯 URL 사용
                page: 0,
                size: 20,
              );

      _commentsByImage[url] = list;
      _commentPageByImage[url] = 0;
      _hasMoreCommentsByImage[url] = list.length >= 20;
      _isLoadingMoreByImage[url] = false;
      _isCommentsLoaded[url] = true;

      notifyListeners();
    } catch (e) {
      debugPrint('[FullscreenMediaCommentController] Load failed: $e');
      _commentsByImage[url] = [];
      _commentPageByImage[url] = 0;
      _hasMoreCommentsByImage[url] = false;
      _isLoadingMoreByImage[url] = false;
      _isCommentsLoaded[url] = true;
      notifyListeners();
    }
  }

  /// 더 많은 댓글 로드
  Future<void> loadMoreComments() async {
    final url = getCurrentImageUrl();
    final isLoading = _isLoadingMoreByImage[url] ?? false;
    final hasMore = _hasMoreCommentsByImage[url] ?? true;

    if (isLoading || !hasMore) return;

    // 🎯 URL 기반으로 변경
    if (url.isEmpty) return;

    _isLoadingMoreByImage[url] = true;
    notifyListeners();

    try {
      final currentPage = _commentPageByImage[url] ?? 0;
      final nextPage = currentPage + 1;

      final list =
          isVideo
              ? await _commentService.fetchVideoComments(
                videoUrl: url, // 🎯 URL 사용
                page: nextPage,
                size: 20,
              )
              : await _commentService.fetchImageComments(
                imageUrl: url, // 🎯 URL 사용
                page: nextPage,
                size: 20,
              );

      _commentsByImage[url] = [...(_commentsByImage[url] ?? []), ...list];
      _commentPageByImage[url] = nextPage;
      _hasMoreCommentsByImage[url] = list.length >= 20;
      _isLoadingMoreByImage[url] = false;

      notifyListeners();
    } catch (e) {
      debugPrint('[FullscreenMediaCommentController] Load more failed: $e');
      _isLoadingMoreByImage[url] = false;
      notifyListeners();
    }
  }

  /// 댓글 추가
  Future<String?> submitComment(String text, User? currentUser) async {
    final url = getCurrentImageUrl();

    // 🎯 URL 기반으로 변경
    if (text.isEmpty || url.isEmpty) {
      return null;
    }

    // 낙관적 추가
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final utcNow = DateTime.now().toUtc().toIso8601String();

    final tempComment = MediaComment(
      id: tempId,
      author: currentUser?.username ?? '',
      text: text,
      authorProfileImageUrl: currentUser?.profileImageUrl ?? '',
      createdAt: utcNow,
      updatedAt: utcNow,
    );

    final currentComments = _commentsByImage[url] ?? [];
    _commentsByImage[url] = [tempComment, ...currentComments];
    notifyListeners();

    try {
      final newId =
          isVideo
              ? await _commentService.createVideoComment(
                videoUrl: url, // 🎯 URL 사용
                text: text,
              )
              : await _commentService.createImageComment(
                imageUrl: url, // 🎯 URL 사용
                text: text,
              );

      if (newId.isNotEmpty) {
        final list = List<MediaComment>.from(_commentsByImage[url] ?? []);
        final idx = list.indexWhere((c) => c.id == tempId);
        if (idx != -1) {
          list[idx] = list[idx].copyWith(id: newId);
          _commentsByImage[url] = list;
          notifyListeners();
        }
      }

      return newId;
    } catch (e) {
      debugPrint('[FullscreenMediaCommentController] Submit failed: $e');
      // 롤백
      _commentsByImage[url] = currentComments;
      notifyListeners();
      rethrow;
    }
  }

  /// 댓글 좋아요 토글
  Future<void> toggleCommentLike(MediaComment comment) async {
    final url = getCurrentImageUrl();
    // 🎯 URL 기반으로 변경
    if (url.isEmpty) return;

    // 낙관적 업데이트
    final newIsLiked = !comment.isLiked;
    final newLikeCount =
        comment.isLiked ? comment.likeCount - 1 : comment.likeCount + 1;

    final currentComments = _commentsByImage[url] ?? [];
    final index = currentComments.indexWhere((c) => c.id == comment.id);
    if (index != -1) {
      currentComments[index] = currentComments[index].copyWith(
        isLiked: newIsLiked,
        likeCount: newLikeCount,
      );
      _commentsByImage[url] = currentComments;
      notifyListeners();
    }

    try {
      final updatedComment =
          isVideo
              ? await _commentService.toggleVideoCommentLike(
                videoUrl: url, // 🎯 URL 사용
                commentId: comment.id,
              )
              : await _commentService.toggleImageCommentLike(
                imageUrl: url, // 🎯 URL 사용
                commentId: comment.id,
              );

      // 서버 응답으로 최종 확정
      final finalComments = _commentsByImage[url] ?? [];
      final finalIndex = finalComments.indexWhere((c) => c.id == comment.id);
      if (finalIndex != -1) {
        finalComments[finalIndex] = finalComments[finalIndex].copyWith(
          isLiked: updatedComment.isLiked,
          likeCount: updatedComment.likeCount,
        );
        _commentsByImage[url] = finalComments;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[FullscreenMediaCommentController] Toggle like failed: $e');
      // 롤백
      final rollbackComments = _commentsByImage[url] ?? [];
      final rollbackIndex = rollbackComments.indexWhere(
        (c) => c.id == comment.id,
      );
      if (rollbackIndex != -1) {
        rollbackComments[rollbackIndex] = comment;
        _commentsByImage[url] = rollbackComments;
        notifyListeners();
      }
    }
  }

  /// 댓글 삭제
  Future<void> deleteComment(MediaComment comment) async {
    final url = getCurrentImageUrl();
    // 🎯 URL 기반으로 변경
    if (url.isEmpty) return;

    // 롤백용 백업
    final backupComments = List<MediaComment>.from(_commentsByImage[url] ?? []);

    // 낙관적 삭제
    _commentsByImage[url] =
        (_commentsByImage[url] ?? []).where((c) => c.id != comment.id).toList();
    notifyListeners();

    try {
      if (isVideo) {
        await _commentService.deleteVideoComment(
          videoUrl: url, // 🎯 URL 사용
          commentId: comment.id,
        );
      } else {
        await _commentService.deleteImageComment(
          imageUrl: url, // 🎯 URL 사용
          commentId: comment.id,
        );
      }
    } catch (e) {
      debugPrint('[FullscreenMediaCommentController] Delete failed: $e');
      // 롤백
      _commentsByImage[url] = backupComments;
      notifyListeners();
      rethrow;
    }
  }

  /// 댓글 수정
  Future<void> updateComment(MediaComment comment, String newText) async {
    final url = getCurrentImageUrl();
    // 🎯 URL 기반으로 변경
    if (url.isEmpty) return;

    // 롤백용 백업
    final backupComments = List<MediaComment>.from(_commentsByImage[url] ?? []);

    // 낙관적 업데이트
    final currentComments = _commentsByImage[url] ?? [];
    final index = currentComments.indexWhere((c) => c.id == comment.id);
    if (index != -1) {
      currentComments[index] = currentComments[index].copyWith(
        text: newText,
        updatedAt: DateTime.now().toIso8601String(),
      );
      _commentsByImage[url] = currentComments;
      notifyListeners();
    }

    try {
      final updatedComment =
          isVideo
              ? await _commentService.updateVideoComment(
                videoUrl: url, // 🎯 URL 사용
                commentId: comment.id,
                text: newText,
              )
              : await _commentService.updateImageComment(
                imageUrl: url, // 🎯 URL 사용
                commentId: comment.id,
                text: newText,
              );

      // 서버 응답으로 최종 업데이트
      final finalComments = _commentsByImage[url] ?? [];
      final finalIndex = finalComments.indexWhere((c) => c.id == comment.id);
      if (finalIndex != -1) {
        finalComments[finalIndex] = updatedComment;
        _commentsByImage[url] = finalComments;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[FullscreenMediaCommentController] Update failed: $e');
      // 롤백
      _commentsByImage[url] = backupComments;
      notifyListeners();
      rethrow;
    }
  }

  /// 특정 이미지 URL의 댓글 초기화
  void clearCommentsForUrl(String url) {
    _commentsByImage.remove(url);
    _commentPageByImage.remove(url);
    _hasMoreCommentsByImage.remove(url);
    _isLoadingMoreByImage.remove(url);
    _isCommentsLoaded.remove(url);
    notifyListeners();
  }

  @override
  void dispose() {
    _commentsByImage.clear();
    _commentPageByImage.clear();
    _hasMoreCommentsByImage.clear();
    _isLoadingMoreByImage.clear();
    _isCommentsLoaded.clear();
    super.dispose();
  }
}
