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
  final String? imageUrl; // 이미지별 댓글인 경우 이미지 URL
  final String visibility; // PUBLIC, FRIENDS, PRIVATE
  final Map<String, String> emotionCounts; // emoji -> count
  final Map<String, String> myEmotions; // 내가 누른 이모지
  final List<Comment> replies; // 대댓글들
  final String createdAt;
  final String updatedAt;

  // 낙관적 업데이트 상태
  final bool isPending; // 서버 전송 대기 중
  final bool isFailed; // 서버 전송 실패

  Comment({
    required this.id,
    required this.author,
    required this.content,
    required this.authorProfileImageUrl,
    required this.postId,
    this.parentId,
    this.imageUrl,
    this.visibility = 'PUBLIC',
    this.emotionCounts = const {},
    this.myEmotions = const {},
    this.replies = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPending = false,
    this.isFailed = false,
  });

  Comment copyWith({
    String? id,
    String? author,
    String? content,
    String? authorProfileImageUrl,
    String? postId,
    String? parentId,
    String? imageUrl,
    String? visibility,
    Map<String, String>? emotionCounts,
    Map<String, String>? myEmotions,
    List<Comment>? replies,
    String? createdAt,
    String? updatedAt,
    bool? isPending,
    bool? isFailed,
  }) {
    return Comment(
      id: id ?? this.id,
      author: author ?? this.author,
      content: content ?? this.content,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      postId: postId ?? this.postId,
      parentId: parentId ?? this.parentId,
      imageUrl: imageUrl ?? this.imageUrl,
      visibility: visibility ?? this.visibility,
      emotionCounts: emotionCounts ?? this.emotionCounts,
      myEmotions: myEmotions ?? this.myEmotions,
      replies: replies ?? this.replies,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
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
      'imageUrl': imageUrl,
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
    // ✅ emotionCounts와 myEmotions는 서버에서 빈 배열 []로 올 수 있으므로 방어 처리
    final emotionCountsRaw = json['emotionCounts'];
    final emotionCounts =
        emotionCountsRaw is Map<String, dynamic>
            ? emotionCountsRaw
            : <String, dynamic>{};

    final myEmotionsRaw = json['myEmotions'];
    final myEmotions =
        myEmotionsRaw is Map<String, dynamic>
            ? myEmotionsRaw
            : <String, dynamic>{};

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
      imageUrl: json['imageUrl']?.toString(),
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
  int _currentPage = 0;

  // 타이밍 시어 관련
  bool _isTimingSheerActive = false;
  static const double _timingSheerThreshold = 200.0; // 200px 스크롤 시 댓글 로드

  // 스크롤 제어 (이모지 업데이트 시 스크롤 안 함)
  bool shouldScrollOnNextUpdate = true;

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
      _currentPage = 0;

      notifyListeners();
    }
  }

  /// WebSocket 설정 및 구독
  Future<void> _setupWebSocket() async {
    print('[CommentService] WebSocket 설정 시작 (current postId: $_currentPostId)');

    // 이미 연결되어 있으면 콜백과 구독만 다시 설정
    if (_webSocketService != null && _webSocketService!.isConnected) {
      print('[CommentService] ✅ WebSocket이 이미 연결되어 있습니다 - 콜백과 구독만 재설정');

      // 콜백 재설정
      _webSocketService!.setCallbacks(
        onCommentCreated: _handleCommentCreated,
        onCommentUpdated: _handleCommentUpdated,
        onCommentDeleted: _handleCommentDeleted,
        onCommentLiked: _handleCommentLiked,
        onCommentUnliked: _handleCommentUnliked,
      );

      // 포스트 댓글 구독 (즉시)
      if (_currentPostId != null) {
        print('[CommentService] 포스트 $_currentPostId 댓글 재구독');
        _webSocketService!.subscribeToPostComments(_currentPostId!);
      }
      return;
    }

    // 기존 서비스가 있지만 연결이 끊긴 경우
    if (_webSocketService != null && !_webSocketService!.isConnected) {
      print('[CommentService] 🔄 기존 WebSocket이 끊겨있음 - 재사용');

      // 콜백 재설정
      _webSocketService!.setCallbacks(
        onCommentCreated: _handleCommentCreated,
        onCommentUpdated: _handleCommentUpdated,
        onCommentDeleted: _handleCommentDeleted,
        onCommentLiked: _handleCommentLiked,
        onCommentUnliked: _handleCommentUnliked,
      );

      // 재연결 시도
      try {
        await _webSocketService!.connect();
        print('[CommentService] ✅ WebSocket 재연결 완료');

        // 구독
        if (_currentPostId != null && _webSocketService!.isConnected) {
          print('[CommentService] 포스트 $_currentPostId 댓글 구독');
          _webSocketService!.subscribeToPostComments(_currentPostId!);
        }
        return;
      } catch (e) {
        print('[CommentService] ❌ 재연결 실패: $e - 새로 생성');
        _webSocketService = null; // 실패 시 null로 설정
      }
    }

    // 완전히 새로운 WebSocketService 생성
    print('[CommentService] 🆕 새로운 WebSocket 인스턴스 생성');
    _webSocketService = WebSocketService();

    // 콜백 먼저 설정 (연결 전)
    _webSocketService!.setCallbacks(
      onCommentCreated: _handleCommentCreated,
      onCommentUpdated: _handleCommentUpdated,
      onCommentDeleted: _handleCommentDeleted,
      onCommentLiked: _handleCommentLiked,
      onCommentUnliked: _handleCommentUnliked,
    );

    // WebSocket 연결 (await로 완료 대기)
    try {
      await _webSocketService!.connect();
      print('[CommentService] ✅ WebSocket 신규 연결 완료');

      // 연결 완료 후 즉시 구독
      if (_currentPostId != null && _webSocketService!.isConnected) {
        print('[CommentService] 포스트 $_currentPostId 댓글 구독 시도');
        _webSocketService!.subscribeToPostComments(_currentPostId!);
      } else {
        print(
          '[CommentService] ⚠️ 구독 실패 - postId: $_currentPostId, isConnected: ${_webSocketService?.isConnected}',
        );
      }
    } catch (e) {
      print('[CommentService] ❌ WebSocket 연결 실패: $e');
    }
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
  Future<void> connectWebSocketForCurrentPost() async {
    if (_currentPostId == null || _currentPostId!.isEmpty) {
      print('[CommentService] ⚠️ currentPostId가 없어서 WebSocket 연결 중단');
      return;
    }
    print(
      '[CommentService] connectWebSocketForCurrentPost 호출 - postId: $_currentPostId',
    );
    await _setupWebSocket();
  }

  /// WebSocket 이벤트 핸들러들
  void _handleCommentCreated(Map<String, dynamic> data) {
    print('[CommentService] 🔥 댓글 생성 이벤트 수신');
    print('[CommentService] 🔥 받은 데이터: $data');
    print('[CommentService] 🔥 현재 댓글 수: ${_comments.length}');

    // 새 댓글을 목록에 추가
    final comment = Comment.fromServer(data);
    print('[CommentService] 🔥 생성된 댓글: ${comment.id} - ${comment.content}');

    // 중복 댓글 방지 - 같은 ID가 이미 있으면 무시 (temp_ 포함 모든 ID)
    final existingIndex = _comments.indexWhere((c) => c.id == comment.id);
    if (existingIndex != -1) {
      print('[CommentService] ⚠️ 중복 댓글 감지! 이미 ID ${comment.id}가 존재함 - 무시');
      print(
        '[CommentService] 기존 댓글: ${_comments[existingIndex].id} (${_comments[existingIndex].content})',
      );
      return;
    }

    // temp_로 시작하는 임시 댓글이 있으면 교체 (같은 content+author)
    final tempIndex = _comments.indexWhere(
      (c) =>
          c.id.startsWith('temp_') &&
          c.content == comment.content &&
          c.author == comment.author,
    );

    if (tempIndex != -1) {
      print(
        '[CommentService] 🔄 임시 댓글을 서버 댓글로 교체: ${_comments[tempIndex].id} → ${comment.id}',
      );
      _comments[tempIndex] = comment;

      // 교체는 새 댓글이 아니므로 스크롤 안 함
      shouldScrollOnNextUpdate = false;
      notifyListeners();
      shouldScrollOnNextUpdate = true;
      return;
    }

    // 완전히 새로운 댓글 추가
    _comments.add(comment);
    print('[CommentService] 🔥 새 댓글 추가 완료: ${comment.id}');
    print('[CommentService] 🔥 추가 후 댓글 수: ${_comments.length}');

    // ✅ 새 댓글 추가 시에는 스크롤 (shouldScrollOnNextUpdate = true가 기본값)
    notifyListeners();
  }

  void _handleCommentUpdated(Map<String, dynamic> data) {
    print('[CommentService] 댓글 수정 이벤트 수신');
    final commentId = data['commentId'].toString();
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      _comments[index] = Comment.fromServer(data);

      // 수정은 스크롤 안 함
      shouldScrollOnNextUpdate = false;
      notifyListeners();
      shouldScrollOnNextUpdate = true;
    }
  }

  void _handleCommentDeleted(Map<String, dynamic> data) {
    print('[CommentService] 댓글 삭제 이벤트 수신');
    final commentId = data['commentId'].toString();
    _comments.removeWhere((c) => c.id == commentId);

    // 삭제는 스크롤 안 함
    shouldScrollOnNextUpdate = false;
    notifyListeners();
    shouldScrollOnNextUpdate = true;
  }

  void _handleCommentLiked(Map<String, dynamic> data) {
    print('[CommentService] 댓글 좋아요 이벤트 수신');
    print('[CommentService] 🔍 WebSocket 데이터: $data');
    print('[CommentService] 🔍 전체 키: ${data.keys.toList()}');

    final commentId = data['commentId'].toString();
    final emoji = data['emoji']?.toString() ?? '👍';
    final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
    print(
      '[CommentService] 🔍 commentId: $commentId, emoji: $emoji, count: $count',
    );

    // 로컬 상태 업데이트
    final index = _comments.indexWhere((c) => c.id == commentId);
    print(
      '[CommentService] 🔍 댓글 찾기 결과: index=$index, 전체 댓글 수=${_comments.length}',
    );
    if (index != -1) {
      final comment = _comments[index];

      //  서버가 전체 emotionCounts를 보내주면 전체 교체
      if (data.containsKey('emotionCounts')) {
        // emotionCounts 파싱
        final emotionCountsRaw = data['emotionCounts'];
        final emotionCounts =
            emotionCountsRaw is Map<String, dynamic>
                ? emotionCountsRaw
                : <String, dynamic>{};
        final emotionCountsMap = <String, String>{};
        emotionCounts.forEach((key, value) {
          emotionCountsMap[key] = value.toString();
        });

        print('[CommentService] 🔍 서버 emotionCounts: $emotionCountsMap');

        // myEmotions 파싱 (있으면 검증용)
        if (data.containsKey('myEmotions')) {
          final myEmotionsRaw = data['myEmotions'];
          final myEmotionsList = myEmotionsRaw is List ? myEmotionsRaw : [];
          final myEmotionsMap = <String, String>{};
          for (final e in myEmotionsList) {
            myEmotionsMap[e.toString()] = '1';
          }

          print('[CommentService] 🔍 서버 myEmotions: $myEmotionsMap (검증용)');
          print(
            '[CommentService] 🔍 로컬 myEmotions: ${comment.myEmotions} (진실)',
          );

          // 🎯 로컬 myEmotions가 절대 진실 (서버는 검증/로그만)
          final isMyEmotionsSame = _areMapsEqual(
            comment.myEmotions,
            myEmotionsMap,
          );
          if (isMyEmotionsSame) {
            print('[CommentService] ✅ 검증 성공 - 로컬과 서버 일치');
          } else {
            print('[CommentService] ⚠️ 검증 실패 - 로컬 우선 (서버는 아직 처리 중)');
          }
        }

        // ✅ emotionCounts는 전체 교체, myEmotions는 절대 변경 안 함!
        _comments[index] = comment.copyWith(
          emotionCounts: emotionCountsMap, // 다른 사람 카운트 반영 ✅
          // myEmotions는 절대 변경 안 함 (로컬이 진실!)
        );

        print(
          '[CommentService] 🎯 [LIKED] emotionCounts 업데이트 완료: $emotionCountsMap',
        );

        // 🎯 이모지 업데이트는 스크롤 안 함
        shouldScrollOnNextUpdate = false;
        notifyListeners();
        print('[CommentService] ✅ [LIKED] notifyListeners() 호출 완료');
        shouldScrollOnNextUpdate = true;
        return;
      } else {
        // 🎯 서버가 부분 정보만 보내주면 (emoji, count) → 로컬에서 계산
        print('[CommentService] 📊 [LIKED] 부분 정보 수신 - 로컬에서 카운트 업데이트');
        final newEmotionCounts = Map<String, String>.from(
          comment.emotionCounts,
        );

        // count가 0이면 제거, 아니면 설정
        if (count > 0) {
          newEmotionCounts[emoji] = count.toString();
        } else {
          newEmotionCounts.remove(emoji);
        }

        _comments[index] = comment.copyWith(
          emotionCounts: newEmotionCounts,
          // myEmotions는 절대 변경 안 함 (로컬이 진실!)
        );

        print(
          '[CommentService] 🎯 [LIKED] 부분 정보로 emotionCounts 업데이트: $newEmotionCounts',
        );

        // 🎯 이모지 업데이트는 스크롤 안 함
        shouldScrollOnNextUpdate = false;
        notifyListeners();
        print('[CommentService] ✅ [LIKED] notifyListeners() 호출 완료');
        shouldScrollOnNextUpdate = true;
      }
    } else {
      print('[CommentService] ❌ [LIKED] 댓글을 찾을 수 없음 - commentId: $commentId');
    }
  }

  // Map 비교 헬퍼
  bool _areMapsEqual(Map<String, String> map1, Map<String, String> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (map1[key] != map2[key]) return false;
    }
    for (final key in map2.keys) {
      if (!map1.containsKey(key)) return false;
    }
    return true;
  }

  void _handleCommentUnliked(Map<String, dynamic> data) {
    print('[CommentService] 댓글 좋아요 취소 이벤트 수신');
    print('[CommentService] 🔍 WebSocket 데이터: $data');
    print('[CommentService] 🔍 전체 키: ${data.keys.toList()}');

    final commentId = data['commentId'].toString();
    final emoji = data['emoji']?.toString() ?? '👍';
    final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
    print(
      '[CommentService] 🔍 commentId: $commentId, emoji: $emoji, count: $count',
    );

    // 로컬 상태 업데이트
    final index = _comments.indexWhere((c) => c.id == commentId);
    print(
      '[CommentService] 🔍 댓글 찾기 결과: index=$index, 전체 댓글 수=${_comments.length}',
    );
    if (index != -1) {
      final comment = _comments[index];

      // 🎯 서버가 전체 emotionCounts를 보내주면 전체 교체
      if (data.containsKey('emotionCounts')) {
        print('[CommentService] ✅ 서버에서 전체 상태 수신');

        // emotionCounts 파싱
        final emotionCountsRaw = data['emotionCounts'];
        final emotionCounts =
            emotionCountsRaw is Map<String, dynamic>
                ? emotionCountsRaw
                : <String, dynamic>{};
        final emotionCountsMap = <String, String>{};
        emotionCounts.forEach((key, value) {
          emotionCountsMap[key] = value.toString();
        });

        print('[CommentService] 🔍 서버 emotionCounts: $emotionCountsMap');

        // myEmotions 파싱 (있으면 검증용)
        if (data.containsKey('myEmotions')) {
          final myEmotionsRaw = data['myEmotions'];
          final myEmotionsList = myEmotionsRaw is List ? myEmotionsRaw : [];
          final myEmotionsMap = <String, String>{};
          for (final e in myEmotionsList) {
            myEmotionsMap[e.toString()] = '1';
          }

          print('[CommentService] 🔍 서버 myEmotions: $myEmotionsMap (검증용)');
          print(
            '[CommentService] 🔍 로컬 myEmotions: ${comment.myEmotions} (진실)',
          );

          // 🎯 로컬 myEmotions가 절대 진실 (서버는 검증/로그만)
          final isMyEmotionsSame = _areMapsEqual(
            comment.myEmotions,
            myEmotionsMap,
          );
          if (isMyEmotionsSame) {
            print('[CommentService] ✅ 검증 성공 - 로컬과 서버 일치');
          } else {
            print('[CommentService] ⚠️ 검증 실패 - 로컬 우선 (서버는 아직 처리 중)');
          }
        }

        // ✅ emotionCounts는 전체 교체, myEmotions는 절대 변경 안 함!
        _comments[index] = comment.copyWith(
          emotionCounts: emotionCountsMap, // 다른 사람 카운트 반영 ✅
          // myEmotions는 절대 변경 안 함 (로컬이 진실!)
        );

        print(
          '[CommentService] 🎯 [UNLIKED] emotionCounts 업데이트 완료: $emotionCountsMap',
        );

        // 🎯 이모지 업데이트는 스크롤 안 함
        shouldScrollOnNextUpdate = false;
        notifyListeners();
        print('[CommentService] ✅ [UNLIKED] notifyListeners() 호출 완료');
        shouldScrollOnNextUpdate = true;
        return;
      } else {
        // 🎯 서버가 부분 정보만 보내주면 (emoji, count) → 로컬에서 계산
        print('[CommentService] 📊 [UNLIKED] 부분 정보 수신 - 로컬에서 카운트 업데이트');
        final newEmotionCounts = Map<String, String>.from(
          comment.emotionCounts,
        );

        // count가 0이면 제거, 아니면 설정
        if (count > 0) {
          newEmotionCounts[emoji] = count.toString();
        } else {
          newEmotionCounts.remove(emoji);
        }

        _comments[index] = comment.copyWith(
          emotionCounts: newEmotionCounts,
          // myEmotions는 절대 변경 안 함 (로컬이 진실!)
        );

        print(
          '[CommentService] 🎯 [UNLIKED] 부분 정보로 emotionCounts 업데이트: $newEmotionCounts',
        );

        // 🎯 이모지 업데이트는 스크롤 안 함
        shouldScrollOnNextUpdate = false;
        notifyListeners();
        print('[CommentService] ✅ [UNLIKED] notifyListeners() 호출 완료');
        shouldScrollOnNextUpdate = true;
      }
    } else {
      print('[CommentService] ❌ [UNLIKED] 댓글을 찾을 수 없음 - commentId: $commentId');
    }
  }

  /// 댓글 로드 (API 호출)
  Future<void> loadComments({bool refresh = false, int? size}) async {
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

      final pageSize = size ?? 20;
      final response = await _dio.get(
        '/api/comments/post/$_currentPostId?page=$_currentPage&size=$pageSize',
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
          _currentPage = 0;
        }

        _comments.addAll(newComments);
        _hasMoreComments = !(data['last'] ?? true);

        // 다음 페이지를 위해 증가
        if (!refresh && _hasMoreComments) {
          _currentPage++;
        }

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

  /// 댓글 추가 (낙관적 업데이트)
  Future<void> addComment({
    required String username,
    required String content,
    String? parentId,
    String? imageUrl,
  }) async {
    if (_currentPostId == null) return;

    // 1️⃣ 임시 ID 생성 (pending 댓글 식별용)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // 2️⃣ 낙관적 업데이트: 즉시 로컬에 댓글 추가
    final optimisticComment = Comment(
      id: tempId,
      author: username,
      content: content,
      authorProfileImageUrl: '', // 내 프로필 이미지는 나중에 로드
      postId: _currentPostId!,
      parentId: parentId,
      imageUrl: imageUrl,
      visibility: 'PUBLIC',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      isPending: true, // 서버 전송 대기 중
      isFailed: false,
    );

    _comments.add(optimisticComment);
    notifyListeners(); // ⚡ UI 즉시 업데이트 (자동 스크롤도 트리거됨)
    print('[CommentService] 낙관적 댓글 추가: $tempId');

    // 3️⃣ 서버에 요청 전송 (백그라운드)
    try {
      final requestBody = {
        'content': content,
        'postId': int.parse(_currentPostId!),
        'parentId': parentId != null ? int.parse(parentId) : null,
        'imageUrl': imageUrl,
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
        // 성공: 서버 응답 데이터로 임시 댓글 교체
        final serverComment = Comment.fromJson(response.data);

        // 같은 ID가 이미 있는지 확인 (WebSocket이 먼저 추가했을 수 있음)
        final existingServerCommentIndex = _comments.indexWhere(
          (c) => c.id == serverComment.id,
        );
        if (existingServerCommentIndex != -1) {
          print(
            '[CommentService] ⚠️ 서버 응답 댓글이 이미 존재함 (WebSocket 먼저 도착) - ID: ${serverComment.id}',
          );
          // 임시 댓글만 제거
          _comments.removeWhere((c) => c.id == tempId);
          notifyListeners();
          return;
        }

        // 임시 댓글 찾아서 교체
        final tempIndex = _comments.indexWhere((c) => c.id == tempId);
        if (tempIndex != -1) {
          print('[CommentService] 🔄 임시 댓글 교체: $tempId → ${serverComment.id}');
          _comments[tempIndex] = serverComment;
        } else {
          print('[CommentService] ⚠️ 임시 댓글이 없음 (이미 제거됨?) - 서버 댓글 추가 안 함');
          // WebSocket이 이미 추가했으므로 여기선 추가하지 않음
          return;
        }
        notifyListeners();
        print('[CommentService] 댓글 추가 성공: ${serverComment.id}');
      } else {
        // 실패: pending → failed로 변경
        final index = _comments.indexWhere((c) => c.id == tempId);
        if (index != -1) {
          _comments[index] = _comments[index].copyWith(
            isPending: false,
            isFailed: true,
          );
          notifyListeners();
        }
        print('[CommentService] 댓글 추가 실패: ${response.statusCode}');
        throw HttpException('댓글 추가 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[CommentService] 댓글 추가 오류 - failed 상태로 변경: $e');

      // 4️⃣ 실패 시: pending → failed로 변경
      final index = _comments.indexWhere((c) => c.id == tempId);
      if (index != -1) {
        _comments[index] = _comments[index].copyWith(
          isPending: false,
          isFailed: true,
        );
        notifyListeners(); // UI에 실패 상태 표시
      }

      if (e is DioException) {
        print(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
    }
  }

  /// 실패한 댓글 재시도
  Future<void> retryComment(String tempId) async {
    final index = _comments.indexWhere((c) => c.id == tempId);
    if (index == -1) return;

    final comment = _comments[index];

    // failed → pending으로 변경
    _comments[index] = comment.copyWith(isPending: true, isFailed: false);
    notifyListeners();

    // 재시도
    await addComment(
      username: comment.author,
      content: comment.content,
      parentId: comment.parentId,
      imageUrl: comment.imageUrl,
    );

    // 기존 임시 댓글 제거
    _comments.removeWhere((c) => c.id == tempId);
    notifyListeners();
  }

  /// 실패한 댓글 삭제
  void removeFailedComment(String tempId) {
    _comments.removeWhere((c) => c.id == tempId);
    notifyListeners();
  }

  /// 댓글에 반응 추가/제거 (API 호출) - 서버가 자동으로 토글 처리
  Future<void> toggleReaction(String commentId, String emoji) async {
    try {
      print('[CommentService] 반응 토글 요청 - commentId: $commentId, emoji: $emoji');

      // 1️⃣ 낙관적 업데이트 (즉시 UI 반영)
      final commentIndex = _comments.indexWhere((c) => c.id == commentId);
      if (commentIndex != -1) {
        final comment = _comments[commentIndex];
        final hasThisReaction = comment.myEmotions.containsKey(emoji);
        final previousEmoji =
            comment.myEmotions.keys.firstOrNull; // 기존에 달았던 이모지

        // 🎯 한 사람당 하나의 이모지만 가능
        // - 같은 이모지 클릭: 제거
        // - 다른 이모지 클릭: 기존 이모지 제거 + 새 이모지 추가
        final newMyEmotions =
            hasThisReaction ? <String, String>{} : {emoji: '1'};

        // emotionCounts도 낙관적으로 업데이트
        final newEmotionCounts = Map<String, String>.from(
          comment.emotionCounts,
        );

        // 기존 이모지가 있고, 새 이모지와 다르면 기존 이모지 카운트 감소
        if (previousEmoji != null && previousEmoji != emoji) {
          final oldCount =
              int.tryParse(newEmotionCounts[previousEmoji] ?? '0') ?? 0;
          if (oldCount > 1) {
            newEmotionCounts[previousEmoji] = (oldCount - 1).toString();
          } else {
            newEmotionCounts.remove(previousEmoji);
          }
        }

        if (hasThisReaction) {
          // 같은 이모지 제거: 카운트 감소
          final currentCount =
              int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
          if (currentCount > 1) {
            newEmotionCounts[emoji] = (currentCount - 1).toString();
          } else {
            newEmotionCounts.remove(emoji);
          }
        } else {
          // 새 이모지 추가: 카운트 증가
          final currentCount =
              int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
          newEmotionCounts[emoji] = (currentCount + 1).toString();
        }

        _comments[commentIndex] = comment.copyWith(
          myEmotions: newMyEmotions,
          emotionCounts: newEmotionCounts,
        );

        // 🎯 이모지 업데이트는 스크롤 안 함
        shouldScrollOnNextUpdate = false;
        notifyListeners(); // 즉시 UI 업데이트
        shouldScrollOnNextUpdate = true;
      }

      // 2️⃣ 서버 요청 (항상 POST - 서버가 알아서 토글 처리)
      await _addReactionToServer(commentId, emoji);

      // 3️⃣ WebSocket으로 정확한 상태 받아서 최종 동기화 (중복은 핸들러에서 방지)
      print('[CommentService] 반응 토글 요청 완료 (WebSocket 대기 중)');
    } catch (e) {
      print('[CommentService] 반응 토글 오류: $e');
      rethrow;
    }
  }

  /// 서버에 반응 추가 (서버가 알아서 토글 처리)
  Future<void> _addReactionToServer(String commentId, String emoji) async {
    final response = await _dio.post(
      '/api/comments/$commentId/emotions?emoji=${Uri.encodeComponent(emoji)}',
      options: Options(receiveTimeout: const Duration(seconds: 5)),
    );

    print(
      '[CommentService] 반응 토글 응답: ${response.statusCode} - ${response.data}',
    );
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
