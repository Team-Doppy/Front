import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/websocket_service.dart';

class Comment {
  final String id;
  final String author;
  final String content;
  final String authorProfileImageUrl;
  final String postId;
  final String? parentId; // 대댓글인 경우 부모 댓글 ID
  final String visibility; // PUBLIC, FRIENDS, PRIVATE
  final Map<String, String> emotionCounts; // emoji -> count
  final Map<String, String> myEmotions; // 내가 누른 이모지
  final List<Comment> replies; // 대댓글들
  final String createdAt;
  final String updatedAt;

  Comment({
    required this.id,
    required this.author,
    required this.content,
    required this.authorProfileImageUrl,
    required this.postId,
    this.parentId,
    this.visibility = 'PUBLIC',
    this.emotionCounts = const {},
    this.myEmotions = const {},
    this.replies = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Comment copyWith({
    String? id,
    String? author,
    String? content,
    String? authorProfileImageUrl,
    String? postId,
    String? parentId,
    String? visibility,
    Map<String, String>? emotionCounts,
    Map<String, String>? myEmotions,
    List<Comment>? replies,
    String? createdAt,
    String? updatedAt,
  }) {
    return Comment(
      id: id ?? this.id,
      author: author ?? this.author,
      content: content ?? this.content,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      postId: postId ?? this.postId,
      parentId: parentId ?? this.parentId,
      visibility: visibility ?? this.visibility,
      emotionCounts: emotionCounts ?? this.emotionCounts,
      myEmotions: myEmotions ?? this.myEmotions,
      replies: replies ?? this.replies,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author,
      'content': content,
      'authorProfileImageUrl': authorProfileImageUrl,
      'postId': postId,
      'parentId': parentId,
      'visibility': visibility,
      'emotionCounts': emotionCounts,
      'myEmotions': myEmotions,
      'replies': replies.map((r) => r.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    // 명세서에 따른 필드 매핑
    final emotionCounts = json['emotionCounts'] as Map<String, dynamic>? ?? {};
    final myEmotions = json['myEmotions'] as Map<String, dynamic>? ?? {};

    final emotionCountsMap = <String, String>{};
    emotionCounts.forEach((key, value) {
      emotionCountsMap[key] = value.toString();
    });

    final myEmotionsMap = <String, String>{};
    myEmotions.forEach((key, value) {
      myEmotionsMap[key] = value.toString();
    });

    // 대댓글 처리
    final replies =
        (json['replies'] as List<dynamic>? ?? [])
            .map((r) => Comment.fromJson(r))
            .toList();

    return Comment(
      id: json['id']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      authorProfileImageUrl: json['authorProfileImageUrl']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      parentId: json['parentId']?.toString(),
      visibility: json['visibility']?.toString() ?? 'PUBLIC',
      emotionCounts: emotionCountsMap,
      myEmotions: myEmotionsMap,
      replies: replies,
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }

  factory Comment.fromServer(Map<String, dynamic> data) {
    // WebSocket 데이터는 commentId 필드를 사용하므로 id로 매핑
    final mappedData = Map<String, dynamic>.from(data);
    if (data.containsKey('commentId') && !data.containsKey('id')) {
      mappedData['id'] = data['commentId'];
    }
    return Comment.fromJson(mappedData);
  }
}

class CommentService extends ChangeNotifier {
  static final CommentService _instance = CommentService._internal();
  factory CommentService() => _instance;
  CommentService._internal();

  final Dio _dio = BaseApiService().dio;
  WebSocketService? _webSocketService;

  final List<Comment> _comments = [];
  String? _currentPostId;
  bool _isLoading = false;
  bool _hasMoreComments = true;

  // 타이밍 시어 관련
  bool _isTimingSheerActive = false;
  static const double _timingSheerThreshold = 200.0; // 200px 스크롤 시 댓글 로드

  // Getters
  List<Comment> get comments => List.unmodifiable(_comments);
  bool get isLoading => _isLoading;
  bool get hasMoreComments => _hasMoreComments;
  bool get isTimingSheerActive => _isTimingSheerActive;

  /// 포스트 ID 설정 및 댓글 초기화
  void setPostId(String postId) {
    if (_currentPostId != postId) {
      _currentPostId = postId;
      _comments.clear();
      _hasMoreComments = true;
      _isTimingSheerActive = false;

      notifyListeners();
    }
  }

  /// WebSocket 설정 및 구독
  void _setupWebSocket() {
    print('[CommentService] WebSocket 설정 시작');

    // 이미 연결되어 있으면 중복 연결 방지
    if (_webSocketService != null && _webSocketService!.isConnected) {
      print('[CommentService] ⚠️ WebSocket이 이미 연결되어 있습니다 - 중복 연결 방지');
      return;
    }

    // 기존 연결이 있으면 먼저 해제
    if (_webSocketService != null) {
      print('[CommentService] 기존 WebSocket 연결 해제');
      _webSocketService!.disconnect();
    }

    // 새로운 WebSocketService 인스턴스 생성
    _webSocketService = WebSocketService();

    // WebSocket 연결
    _webSocketService!.connect();

    // 콜백 설정
    _webSocketService!.setCallbacks(
      onCommentCreated: _handleCommentCreated,
      onCommentUpdated: _handleCommentUpdated,
      onCommentDeleted: _handleCommentDeleted,
      onCommentLiked: _handleCommentLiked,
      onCommentUnliked: _handleCommentUnliked,
    );

    // 포스트 댓글 구독 (연결 후)
    Timer(Duration(seconds: 1), () {
      if (_currentPostId != null && _webSocketService != null) {
        print('[CommentService] 포스트 $_currentPostId 댓글 구독 시도');
        _webSocketService!.subscribeToPostComments(_currentPostId!);
      }
    });
  }

  /// 스크롤 위치 업데이트 (타이밍 시어)
  void updateScrollPosition(double scrollPosition) {
    // 타이밍 시어 활성화 조건: 200px 이상 스크롤했고, 아직 댓글을 로드하지 않았을 때
    if (!_isTimingSheerActive &&
        scrollPosition > _timingSheerThreshold &&
        _currentPostId != null) {
      _activateTimingSheer();
    }
  }

  /// 타이밍 시어 활성화
  void _activateTimingSheer() {
    if (_isTimingSheerActive) return;

    _isTimingSheerActive = true;
    print('[CommentService] 타이밍 시어 활성화 - 댓글 로드 시작');

    loadComments();
  }

  /// 댓글 창 열 때 호출: 웹소켓 연결 및 구독 시작
  void connectWebSocketForCurrentPost() {
    if (_currentPostId == null || _currentPostId!.isEmpty) return;
    _setupWebSocket();
  }

  /// WebSocket 이벤트 핸들러들
  void _handleCommentCreated(Map<String, dynamic> data) {
    print('[CommentService] 🔥 댓글 생성 이벤트 수신');
    print('[CommentService] 🔥 받은 데이터: $data');
    print('[CommentService] 🔥 현재 댓글 수: ${_comments.length}');

    // 새 댓글을 목록에 추가
    final comment = Comment.fromServer(data);
    print('[CommentService] 🔥 생성된 댓글: ${comment.id} - ${comment.content}');

    // 중복 댓글 방지 (ID와 내용 모두 체크)
    final existingIndex = _comments.indexWhere(
      (c) =>
          c.id == comment.id ||
          (c.content == comment.content && c.author == comment.author),
    );
    if (existingIndex != -1) {
      print('[CommentService] ⚠️ 중복 댓글 감지! ID: ${comment.id} - 무시합니다');
      return;
    }

    _comments.add(comment);
    print('[CommentService] 🔥 추가 후 댓글 수: ${_comments.length}');

    notifyListeners();
  }

  void _handleCommentUpdated(Map<String, dynamic> data) {
    print('[CommentService] 댓글 수정 이벤트 수신');
    final commentId = data['commentId'].toString();
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      _comments[index] = Comment.fromServer(data);
      notifyListeners();
    }
  }

  void _handleCommentDeleted(Map<String, dynamic> data) {
    print('[CommentService] 댓글 삭제 이벤트 수신');
    final commentId = data['commentId'].toString();
    _comments.removeWhere((c) => c.id == commentId);
    notifyListeners();
  }

  void _handleCommentLiked(Map<String, dynamic> data) {
    print('[CommentService] 댓글 좋아요 이벤트 수신');
    final commentId = data['commentId'].toString();
    final emoji = data['emoji']?.toString() ?? '👍';

    // 로컬 상태 업데이트
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      final comment = _comments[index];
      final newEmotionCounts = Map<String, String>.from(comment.emotionCounts);
      final newMyEmotions = Map<String, String>.from(comment.myEmotions);

      // 이모지 카운트 증가
      final currentCount = int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
      newEmotionCounts[emoji] = (currentCount + 1).toString();

      // 내 이모지 상태 추가
      newMyEmotions[emoji] = '1';

      _comments[index] = comment.copyWith(
        emotionCounts: newEmotionCounts,
        myEmotions: newMyEmotions,
      );
      notifyListeners();
    }
  }

  void _handleCommentUnliked(Map<String, dynamic> data) {
    print('[CommentService] 댓글 좋아요 취소 이벤트 수신');
    final commentId = data['commentId'].toString();
    final emoji = data['emoji']?.toString() ?? '👍';

    // 로컬 상태 업데이트
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      final comment = _comments[index];
      final newEmotionCounts = Map<String, String>.from(comment.emotionCounts);
      final newMyEmotions = Map<String, String>.from(comment.myEmotions);

      // 이모지 카운트 감소
      final currentCount = int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
      if (currentCount > 0) {
        newEmotionCounts[emoji] = (currentCount - 1).toString();
      }

      // 내 이모지 상태 제거
      newMyEmotions.remove(emoji);

      _comments[index] = comment.copyWith(
        emotionCounts: newEmotionCounts,
        myEmotions: newMyEmotions,
      );
      notifyListeners();
    }
  }

  /// 댓글 로드 (API 호출)
  Future<void> loadComments({bool refresh = false}) async {
    if (_currentPostId == null ||
        _currentPostId!.isEmpty ||
        _isLoading ||
        (!refresh && !_hasMoreComments)) {
      print(
        '[CommentService] 댓글 로드 건너뜀: postId=$_currentPostId, loading=$_isLoading, hasMore=$_hasMoreComments',
      );
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      print('[CommentService] API 호출 시작');
      print('[CommentService] PostId: $_currentPostId');

      final response = await _dio.get(
        '/api/comments/post/$_currentPostId?page=0&size=20',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      print('[CommentService] 응답 상태: ${response.statusCode}');
      print('[CommentService] 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        print('[CommentService] 파싱된 데이터: $data');

        // 명세서에 따른 페이지네이션 응답 구조
        final commentsData = data['content'] as List<dynamic>? ?? [];
        print('[CommentService] 댓글 데이터: $commentsData');

        final newComments = <Comment>[];

        // 댓글과 대댓글을 평면화하여 처리
        for (final commentJson in commentsData) {
          final comment = Comment.fromJson(commentJson as Map<String, dynamic>);
          newComments.add(comment);

          // 대댓글도 추가
          final replies = commentJson['replies'] as List<dynamic>? ?? [];
          for (final replyJson in replies) {
            final reply = Comment.fromJson(replyJson as Map<String, dynamic>);
            newComments.add(reply);
          }
        }

        if (refresh) {
          _comments.clear();
        }

        _comments.addAll(newComments);
        _hasMoreComments = !(data['last'] ?? true);

        print('[CommentService] 댓글 로드 완료: ${newComments.length}개');
      } else {
        print('[CommentService] 댓글 로드 실패: ${response.statusCode}');
        throw HttpException('댓글 로드 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[CommentService] 댓글 로드 오류: $e');
      if (e is DioException) {
        print(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      // 오류 발생 시 빈 리스트 유지 (폴백 데이터 제거)
      // _loadFallbackComments();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 최근 댓글 3개 가져오기 (최신순으로 아래에서 5개)
  List<Comment> getRecentComments() {
    final sortedComments = List<Comment>.from(_comments);
    sortedComments.sort((a, b) => a.id.compareTo(b.id)); // 시간순 정렬
    return sortedComments.reversed.take(5).toList();
  }

  /// 모든 댓글 가져오기 (최신순으로 아래에서)
  List<Comment> getAllComments() {
    final sortedComments = List<Comment>.from(_comments);
    sortedComments.sort((a, b) => a.id.compareTo(b.id)); // 시간순 정렬
    return sortedComments;
  }

  /// WebSocket 연결 해제
  void disconnectWebSocket() {
    if (_webSocketService != null) {
      _webSocketService!.disconnect();
      _webSocketService = null;
    }
  }

  /// 댓글 추가 (API 호출)
  Future<void> addComment({
    required String username,
    required String content,
    String? parentId,
  }) async {
    if (_currentPostId == null) return;

    try {
      final requestBody = {
        'content': content,
        'postId': int.parse(_currentPostId!),
        'parentId': parentId != null ? int.parse(parentId) : null,
        'visibility': 'PUBLIC',
      };

      print('[CommentService] 댓글 추가 요청: $requestBody');

      final response = await _dio.post(
        '/api/comments',
        data: requestBody,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      print(
        '[CommentService] 댓글 추가 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // API 응답에서는 댓글을 추가하지 않음 - WebSocket 이벤트에서 처리
        print('[CommentService] 댓글 추가 성공 - WebSocket 이벤트 대기 중');
      } else {
        print('[CommentService] 댓글 추가 실패: ${response.statusCode}');
        throw HttpException('댓글 추가 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[CommentService] 댓글 추가 오류: $e');
      if (e is DioException) {
        print(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
    }
  }

  /// 댓글에 반응 추가/제거 (API 호출) - 사용자당 하나의 이모지만
  Future<void> toggleReaction(String commentId, String emoji) async {
    try {
      // 현재 반응 상태 확인
      final commentIndex = _comments.indexWhere((c) => c.id == commentId);
      if (commentIndex == -1) return;

      final comment = _comments[commentIndex];
      final hasThisReaction = comment.myEmotions.containsKey(emoji);
      final hasAnyReaction = comment.myEmotions.isNotEmpty;

      // 기존 반응이 있고 다른 이모지인 경우, 기존 반응 제거 후 새 반응 추가
      if (hasAnyReaction && !hasThisReaction) {
        // 기존 반응 제거
        final existingEmoji = comment.myEmotions.keys.first;
        await _removeReactionFromServer(commentId, existingEmoji);

        // 새 반응 추가
        await _addReactionToServer(commentId, emoji);
      } else if (hasThisReaction) {
        // 같은 이모지인 경우 제거
        await _removeReactionFromServer(commentId, emoji);
      } else {
        // 반응이 없는 경우 새 반응 추가
        await _addReactionToServer(commentId, emoji);
      }

      // 로컬 상태 업데이트
      _updateLocalReactionSingle(commentId, emoji);
      print('[CommentService] 반응 토글 성공');
    } catch (e) {
      print('[CommentService] 반응 토글 오류: $e');
      // 오류 발생 시 로컬에서만 토글
      _updateLocalReactionSingle(commentId, emoji);
    }
  }

  /// 서버에 반응 추가
  Future<void> _addReactionToServer(String commentId, String emoji) async {
    final response = await _dio.post(
      '/api/comments/$commentId/emotions?emoji=${Uri.encodeComponent(emoji)}',
      options: Options(receiveTimeout: const Duration(seconds: 5)),
    );

    print(
      '[CommentService] 반응 추가 응답: ${response.statusCode} - ${response.data}',
    );
  }

  /// 서버에서 반응 제거
  Future<void> _removeReactionFromServer(String commentId, String emoji) async {
    final response = await _dio.delete(
      '/api/comments/$commentId/emotions?emoji=${Uri.encodeComponent(emoji)}',
      options: Options(receiveTimeout: const Duration(seconds: 5)),
    );

    print(
      '[CommentService] 반응 제거 응답: ${response.statusCode} - ${response.data}',
    );
  }

  /// 로컬 반응 상태 업데이트 (사용자당 하나의 이모지만)
  void _updateLocalReactionSingle(String commentId, String emoji) {
    final commentIndex = _comments.indexWhere((c) => c.id == commentId);
    if (commentIndex == -1) return;

    final comment = _comments[commentIndex];
    var newReactions = <String, String>{};

    // 기존 반응이 있는지 확인
    final hasThisReaction = comment.myEmotions.containsKey(emoji);

    if (hasThisReaction) {
      // 같은 이모지인 경우 제거 (빈 맵으로 설정)
      newReactions = {};
    } else {
      // 다른 이모지이거나 반응이 없는 경우 새 이모지로 교체
      newReactions[emoji] = '1';
    }

    _comments[commentIndex] = comment.copyWith(myEmotions: newReactions);
    notifyListeners();
  }

  /// 댓글 삭제 (API 호출)
  Future<void> deleteComment(String commentId) async {
    try {
      final response = await _dio.delete(
        '/api/comments/$commentId',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        _comments.removeWhere((c) => c.id == commentId);
        notifyListeners();
        print('[CommentService] 댓글 삭제 성공');
      } else {
        print('[CommentService] 댓글 삭제 실패: ${response.statusCode}');
        throw HttpException('댓글 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[CommentService] 댓글 삭제 오류: $e');
      if (e is DioException) {
        print(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      // 오류 발생 시 로컬에서만 삭제
      _comments.removeWhere((c) => c.id == commentId);
      notifyListeners();
    }
  }

  /// 댓글 수정 (API 호출)
  Future<void> updateComment(String commentId, String newContent) async {
    try {
      final response = await _dio.put(
        '/api/comments/$commentId',
        data: {'content': newContent},
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200) {
        final commentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (commentIndex != -1) {
          _comments[commentIndex] = _comments[commentIndex].copyWith(
            content: newContent,
          );
          notifyListeners();
        }
        print('[CommentService] 댓글 수정 성공');
      } else {
        print('[CommentService] 댓글 수정 실패: ${response.statusCode}');
        throw HttpException('댓글 수정 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[CommentService] 댓글 수정 오류: $e');
      if (e is DioException) {
        print(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      // 오류 발생 시 로컬에서만 수정
      final commentIndex = _comments.indexWhere((c) => c.id == commentId);
      if (commentIndex != -1) {
        _comments[commentIndex] = _comments[commentIndex].copyWith(
          content: newContent,
        );
        notifyListeners();
      }
    }
  }

  /// 댓글 새로고침
  Future<void> refreshComments() async {
    _hasMoreComments = true;
    await loadComments(refresh: true);
  }

  /// 서비스 초기화
  void reset() {
    _comments.clear();
    _currentPostId = null;
    _isLoading = false;
    _hasMoreComments = true;
    _isTimingSheerActive = false;
    notifyListeners();
  }
}
