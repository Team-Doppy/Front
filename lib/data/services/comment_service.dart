import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/websocket_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/r2_upload_service.dart';
import 'package:doppy/utils/mention_parser.dart';

class Comment {
  final String id;
  final String author;
  final String content;
  final String authorProfileImageUrl;
  final String postId;
  final String? parentId; // 대댓글인 경우 부모 댓글 ID
  final String? imageUrl; // 이미지별 댓글인 경우 이미지 URL
  final String? localImagePath; // 🎯 로컬 이미지 파일 경로 (업로드 전 임시 표시용)
  final String visibility; // PUBLIC, FRIENDS, PRIVATE
  final Map<String, String> emotionCounts; // emoji -> count
  final Map<String, String> myEmotions; // 내가 누른 이모지
  final Map<String, List<Map<String, dynamic>>>
  emotionUsers; // 🎯 emoji -> 사용자 목록
  final List<Comment> replies; // 대댓글들
  final String createdAt;
  final String updatedAt;

  // 낙관적 업데이트 상태
  final bool isPending; // 서버 전송 대기 중
  final bool isFailed; // 서버 전송 실패

  // 🎯 채팅 기능 필드
  final List<String>? mentionedUsernames; // 언급된 사용자 목록
  final bool isSecret; // 비밀 메시지 여부
  final bool isRestricted; // 제한된 메시지 여부
  final String? visibleToUsername; // 비밀 메시지를 볼 수 있는 사용자 (1:1)

  Comment({
    required this.id,
    required this.author,
    required this.content,
    required this.authorProfileImageUrl,
    required this.postId,
    this.parentId,
    this.imageUrl,
    this.localImagePath, // 🎯 로컬 이미지 파일 경로
    this.visibility = 'PUBLIC',
    this.emotionCounts = const {},
    this.myEmotions = const {},
    this.emotionUsers = const {},
    this.replies = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPending = false,
    this.isFailed = false,
    this.mentionedUsernames,
    this.isSecret = false,
    this.isRestricted = false,
    this.visibleToUsername,
  });

  Comment copyWith({
    String? id,
    String? author,
    String? content,
    String? authorProfileImageUrl,
    String? postId,
    String? parentId,
    String? imageUrl,
    String? localImagePath, // 🎯 로컬 이미지 파일 경로
    String? visibility,
    Map<String, String>? emotionCounts,
    Map<String, String>? myEmotions,
    Map<String, List<Map<String, dynamic>>>? emotionUsers,
    List<Comment>? replies,
    String? createdAt,
    String? updatedAt,
    bool? isPending,
    bool? isFailed,
    List<String>? mentionedUsernames,
    bool? isSecret,
    bool? isRestricted,
    String? visibleToUsername,
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
      localImagePath: localImagePath ?? this.localImagePath, // 🎯 로컬 이미지 파일 경로
      visibility: visibility ?? this.visibility,
      emotionCounts: emotionCounts ?? this.emotionCounts,
      myEmotions: myEmotions ?? this.myEmotions,
      emotionUsers: emotionUsers ?? this.emotionUsers,
      replies: replies ?? this.replies,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
      mentionedUsernames: mentionedUsernames ?? this.mentionedUsernames,
      isSecret: isSecret ?? this.isSecret,
      isRestricted: isRestricted ?? this.isRestricted,
      visibleToUsername: visibleToUsername ?? this.visibleToUsername,
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
    // ✅ emotionCounts와 myEmotions는 서버에서 빈 배열 [] 또는 Map으로 올 수 있으므로 방어 처리
    final emotionCountsRaw = json['emotionCounts'];
    final emotionCounts =
        emotionCountsRaw is Map<String, dynamic>
            ? emotionCountsRaw
            : <String, dynamic>{}; // 배열이거나 null이면 빈 Map

    // 🎯 myEmotions는 배열([])로 옴: [❤️] → {❤️: '1'}
    final myEmotionsRaw = json['myEmotions'];
    final myEmotionsMap = <String, String>{};
    if (myEmotionsRaw is List) {
      // 배열인 경우: 각 이모지를 키로, '1'을 값으로 설정
      for (final emoji in myEmotionsRaw) {
        if (emoji != null) {
          myEmotionsMap[emoji.toString()] = '1';
        }
      }
    } else if (myEmotionsRaw is Map<String, dynamic>) {
      // Map인 경우 (호환성)
      myEmotionsRaw.forEach((key, value) {
        myEmotionsMap[key] = value.toString();
      });
    }

    final emotionCountsMap = <String, String>{};
    emotionCounts.forEach((key, value) {
      emotionCountsMap[key] = value.toString();
    });

    // 🎯 emotionUsers 파싱
    final emotionUsersRaw = json['emotionUsers'];
    final emotionUsers = <String, List<Map<String, dynamic>>>{};
    if (emotionUsersRaw is Map<String, dynamic>) {
      emotionUsersRaw.forEach((emoji, users) {
        if (users is List) {
          emotionUsers[emoji] =
              users.map((u) => Map<String, dynamic>.from(u)).toList();
        }
      });
    }

    // 대댓글 처리
    final repliesRaw = json['replies'] as List<dynamic>? ?? [];
    final replies =
        repliesRaw
            .where((r) => r is Map<String, dynamic>) // 🎯 타입 안전성 체크
            .map((r) => Comment.fromJson(r as Map<String, dynamic>))
            .toList();

    // 🎯 언급 및 비밀 채팅 필드 파싱
    final mentionedUsernames =
        json['mentionedUsernames'] != null
            ? (json['mentionedUsernames'] as List<dynamic>)
                .map((e) => e.toString())
                .toList()
            : null;
    // 명세서: visibility 필드로 비밀댓글 확인
    final visibility = json['visibility']?.toString() ?? 'PUBLIC';
    final isSecret = visibility == 'PRIVATE';
    final isRestricted = visibility == 'PRIVATE';
    final visibleToUsername =
        json['visibleToUsername']?.toString(); // 명세서에는 없지만 UI 호환성 유지

    return Comment(
      id: json['id']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      authorProfileImageUrl: json['authorProfileImageUrl']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      parentId: json['parentId']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      localImagePath: null, // 🎯 서버 응답에는 로컬 경로 없음
      visibility: json['visibility']?.toString() ?? 'PUBLIC',
      emotionCounts: emotionCountsMap,
      myEmotions: myEmotionsMap,
      emotionUsers: emotionUsers,
      replies: replies,
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      mentionedUsernames: mentionedUsernames,
      isSecret: isSecret,
      isRestricted: isRestricted,
      visibleToUsername: visibleToUsername,
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
  final AuthService _authService = AuthService();
  WebSocketService? _webSocketService;

  final List<Comment> _comments = [];

  // ✅ 정렬 캐시 (UI에서 sort 금지)
  // - reverse:false + createdAt 오름차순(오래된 → 최신) 기준
  // - 댓글 리스트 길이가 바뀌는 순간(추가/삭제/페이지 로드)만 재정렬
  // - reaction/content 업데이트처럼 길이가 유지되는 경우엔 캐시 재사용 (정렬 순서에도 영향 없음)
  List<Comment> _sortedCommentsCache = const [];
  int _sortedCacheLength = -1;
  String? _currentPostId;
  String? _currentPostAuthorUsername; // 🎯 현재 포스트 작성자 username
  String? _cachedCurrentUsername; // 🎯 현재 사용자명 캐시 (성능 최적화)

  /// 현재 사용자명 가져오기 (캐싱 적용)
  Future<String?> _getCurrentUsername() async {
    // 🎯 1순위: 인스턴스 캐시 확인
    if (_cachedCurrentUsername != null && _cachedCurrentUsername!.isNotEmpty) {
      return _cachedCurrentUsername;
    }

    // 🎯 2순위: AuthService의 동기 캐시 확인
    final cached = _authService.currentUsernameSync;
    if (cached != null && cached.isNotEmpty) {
      _cachedCurrentUsername = cached; // 인스턴스 캐시에 저장
      return cached;
    }

    // 🎯 3순위: 스토리지에서 직접 읽기 (최초 1회만)
    try {
      final username = await _authService.getUsername();
      _cachedCurrentUsername = username; // 인스턴스 캐시에 저장
      debugPrint('[CommentService] ✅ 스토리지에서 사용자명 읽기 (캐시 저장): $username');
      return username;
    } catch (e) {
      debugPrint('[CommentService] ❌ 사용자명 가져오기 실패: $e');
      return null;
    }
  }

  /// 🎯 사용자명 캐시 초기화 (로그아웃 등 시 호출)
  void clearUsernameCache() {
    _cachedCurrentUsername = null;
  }

  /// 포스트 작성자 username 설정
  void setPostAuthorUsername(String? postAuthorUsername) {
    _currentPostAuthorUsername = postAuthorUsername;
    debugPrint('[CommentService] 포스트 작성자 설정: $_currentPostAuthorUsername');
  }

  /// 🎯 비밀댓글 권한 체크 및 content 처리
  /// 서버가 이미 권한 체크를 하고 있으므로, originalContent가 있으면 그걸 사용
  Future<String> _checkPrivateCommentAccess(
    Map<String, dynamic> commentData,
    String originalContent,
  ) async {
    return originalContent;
  }

  bool _isLoading = false;
  bool _hasMoreComments = true;
  int _currentPage = 0;
  int _serverCommentCount = 0; // 🎯 서버에서 받아온 실제 댓글 총 개수

  // 🎯 댓글 페이지네이션 크기 (기본값)
  static const int defaultPageSize = 100;

  // 🎯 양방향 페이지네이션 상태
  // - page=0: 최신, page가 커질수록 과거 (서버 정렬: createdAt DESC, id DESC 기준)
  final Set<int> _loadedPages = <int>{};
  final Set<int> _loadingPages = <int>{};
  int? _minLoadedPage; // 로드된 페이지 중 가장 "최신"(가장 작은 page)
  int? _maxLoadedPage; // 로드된 페이지 중 가장 "과거"(가장 큰 page)
  int? _totalPages; // 서버가 제공하면 사용 (없으면 null)
  int _pageSize = defaultPageSize;

  // 타이밍 시어 관련
  bool _isTimingSheerActive = false;
  static const double _timingSheerThreshold = 200.0; // 200px 스크롤 시 댓글 로드

  // Getters
  List<Comment> get comments => List.unmodifiable(_comments);
  List<Comment> get sortedComments {
    final len = _comments.length;
    if (len == 0) {
      // 빈 리스트면 캐시도 즉시 비움
      if (_sortedCacheLength != 0) {
        _sortedCommentsCache = const [];
        _sortedCacheLength = 0;
      }
      return _sortedCommentsCache;
    }

    // 길이가 바뀐 경우에만 정렬 수행 (핫패스)
    if (_sortedCacheLength != len) {
      final sorted = List<Comment>.from(_comments)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _sortedCommentsCache = List.unmodifiable(sorted);
      _sortedCacheLength = len;
    }
    return _sortedCommentsCache;
  }

  bool get isLoading => _isLoading;
  bool get hasMoreComments => _hasMoreComments;
  bool get isTimingSheerActive => _isTimingSheerActive;
  String? get currentPostId => _currentPostId;
  bool get hasNewerComments => (_minLoadedPage ?? 0) > 0;
  bool get hasOlderComments {
    final maxPage = _maxLoadedPage;
    if (maxPage == null) return true; // 아직 아무 것도 안 로드했으면 true
    if (_totalPages != null) return maxPage < (_totalPages! - 1);
    return _hasMoreComments; // fallback
  }

  /// 🎯 전체 댓글 수 반환 (서버 값과 로드된 댓글 수 중 큰 값 사용)
  int getTotalCommentCount() {
    return _serverCommentCount > _comments.length
        ? _serverCommentCount
        : _comments.length;
  }

  /// 🎯 서버에서 받아온 초기 댓글 수 설정 (본문 로드 시)
  void setInitialCommentCount(int count) {
    _serverCommentCount = count;
    debugPrint('[CommentService] 초기 댓글 수 설정: $count');
    notifyListeners();
  }

  /// 포스트 ID 설정 및 댓글 초기화
  void setPostId(String postId, {List<Comment>? initialComments}) {
    if (_currentPostId != postId) {
      _currentPostId = postId;
      _comments.clear();
      _serverCommentCount = 0; // 🎯 서버 댓글 수도 초기화
      _loadedPages.clear();
      _loadingPages.clear();
      _minLoadedPage = null;
      _maxLoadedPage = null;
      _totalPages = null;
      _pageSize = defaultPageSize;

      // 초기 댓글 데이터가 있으면 사용 (page=0 재사용)
      if (initialComments != null && initialComments.isNotEmpty) {
        _comments.addAll(initialComments);
        _currentPage = 1; // 다음은 page=1부터 로드
        _loadedPages.add(0);
        _minLoadedPage = 0;
        _maxLoadedPage = 0;
        debugPrint(
          '[CommentService] 초기 댓글 ${initialComments.length}개 로드 (page=0 재사용)',
        );
      } else {
        _currentPage = 0;
      }

      _hasMoreComments = true;
      _isTimingSheerActive = false;

      notifyListeners();
    }
  }

  /// WebSocket 설정 및 구독
  Future<void> _setupWebSocket() async {
    debugPrint(
      '[CommentService] WebSocket 설정 시작 (current postId: $_currentPostId)',
    );

    // 이미 연결되어 있으면 콜백과 구독만 다시 설정
    if (_webSocketService != null && _webSocketService!.isConnected) {
      debugPrint('[CommentService] ✅ WebSocket이 이미 연결되어 있습니다 - 콜백과 구독만 재설정');

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
        debugPrint('[CommentService] 포스트 $_currentPostId 댓글 재구독');
        _webSocketService!.subscribeToPostComments(_currentPostId!);
      }
      return;
    }

    // 기존 서비스가 있지만 연결이 끊긴 경우
    if (_webSocketService != null && !_webSocketService!.isConnected) {
      debugPrint('[CommentService] 🔄 기존 WebSocket이 끊겨있음 - 재사용');

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
        debugPrint('[CommentService] ✅ WebSocket 재연결 완료');

        // 구독
        if (_currentPostId != null && _webSocketService!.isConnected) {
          debugPrint('[CommentService] 포스트 $_currentPostId 댓글 구독');
          _webSocketService!.subscribeToPostComments(_currentPostId!);
        }
        return;
      } catch (e) {
        debugPrint('[CommentService] ❌ 재연결 실패: $e - 새로 생성');
        _webSocketService = null; // 실패 시 null로 설정
      }
    }

    // 완전히 새로운 WebSocketService 생성
    debugPrint('[CommentService] 🆕 새로운 WebSocket 인스턴스 생성');
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
      debugPrint('[CommentService] ✅ WebSocket 신규 연결 완료');

      // 연결 완료 후 즉시 구독
      if (_currentPostId != null && _webSocketService!.isConnected) {
        debugPrint('[CommentService] 포스트 $_currentPostId 댓글 구독 시도');
        _webSocketService!.subscribeToPostComments(_currentPostId!);
      } else {
        debugPrint(
          '[CommentService] ⚠️ 구독 실패 - postId: $_currentPostId, isConnected: ${_webSocketService?.isConnected}',
        );
      }
    } catch (e) {
      debugPrint('[CommentService] ❌ WebSocket 연결 실패: $e');
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
    debugPrint('[CommentService] 타이밍 시어 활성화');

    // 초기 댓글이 이미 있으면 로드하지 않음 (page=0 재사용)
    if (_comments.isEmpty) {
      debugPrint('[CommentService] 초기 댓글 없음 - page=0 로드 시작');
      loadComments();
    } else {
      debugPrint('[CommentService] 초기 댓글 ${_comments.length}개 있음 - 로드 스킵');
    }
  }

  /// 댓글 창 열 때 호출: 웹소켓 연결 및 구독 시작
  Future<void> connectWebSocketForCurrentPost() async {
    if (_currentPostId == null || _currentPostId!.isEmpty) {
      debugPrint('[CommentService] ⚠️ currentPostId가 없어서 WebSocket 연결 중단');
      return;
    }
    debugPrint(
      '[CommentService] connectWebSocketForCurrentPost 호출 - postId: $_currentPostId',
    );
    await _setupWebSocket();
  }

  /// WebSocket 이벤트 핸들러들 (비동기로 처리하여 Hang 방지)
  void _handleCommentCreated(Map<String, dynamic> data) async {
    // 🎯 서버가 권한이 있는 사용자에게는 originalContent를 보내고, 없으면 content에 "비밀댓글입니다"를 보냄
    final serverContent = data['content']?.toString() ?? '';
    final originalContent =
        data['originalContent']?.toString() ?? serverContent;
    final finalContent =
        originalContent.isNotEmpty ? originalContent : serverContent;
    final author = data['author']?.toString() ?? '';

    final dataWithCheckedContent = Map<String, dynamic>.from(data);
    dataWithCheckedContent['content'] = finalContent;

    final comment = Comment.fromServer(dataWithCheckedContent);

    // 중복 댓글 방지
    final existingIndex = _comments.indexWhere((c) => c.id == comment.id);
    if (existingIndex != -1) {
      return;
    }

    // temp_로 시작하는 임시 댓글이 있으면 교체
    final tempIndex = _comments.indexWhere(
      (c) =>
          c.id.startsWith('temp_') &&
          (c.content == finalContent || c.content == serverContent) &&
          c.author == author,
    );

    if (tempIndex != -1) {
      // 🎯 로컬 이미지 경로 유지 (깜빡임 방지)
      final tempComment = _comments[tempIndex];
      _comments[tempIndex] = comment.copyWith(
        content: finalContent,
        localImagePath: tempComment.localImagePath, // 🎯 로컬 경로 유지
      );

      // 교체는 새 댓글이 아니므로 스크롤 안 함
      notifyListeners();
      return;
    }

    // 완전히 새로운 댓글 추가
    _comments.add(comment);
    _serverCommentCount++; // 🎯 전체 댓글 수 증가

    notifyListeners();
  }

  void _handleCommentUpdated(Map<String, dynamic> data) async {
    debugPrint('[CommentService] 댓글 수정 이벤트 수신 (검증용)');
    debugPrint('[CommentService] 🔍 WebSocket 데이터: $data');

    final commentId = data['commentId'].toString();
    final index = _comments.indexWhere((c) => c.id == commentId);

    if (index != -1) {
      final localComment = _comments[index];

      // 🎯 비밀댓글 권한 체크
      final originalContent = data['content']?.toString() ?? '';
      final checkedContent = await _checkPrivateCommentAccess(
        data,
        originalContent,
      );
      final dataWithCheckedContent = Map<String, dynamic>.from(data);
      dataWithCheckedContent['content'] = checkedContent;

      final serverComment = Comment.fromServer(dataWithCheckedContent);

      // 🎯 로컬 내용과 서버 내용 비교 (검증)
      if (localComment.content != serverComment.content) {
        debugPrint('[CommentService] ⚠️ 내용 불일치 감지!');
        debugPrint('[CommentService] 로컬: ${localComment.content}');
        debugPrint('[CommentService] 서버: ${serverComment.content}');

        // 서버가 진실이므로 서버 데이터로 교체 (다른 사용자가 수정했거나 동기화 문제)
        _comments[index] = serverComment;

        notifyListeners();

        debugPrint('[CommentService] 🔄 서버 데이터로 동기화 완료');
      } else {
        debugPrint('[CommentService] ✅ 검증 성공 - 로컬과 서버 일치');
        // emotionCounts 등 다른 필드만 업데이트
        // 🎯 비밀댓글인 경우 이모지 반응도 권한 체크 필요
        final isPrivate =
            localComment.isSecret || localComment.visibility == 'PRIVATE';
        final currentUsername = await _getCurrentUsername();
        final canViewPrivate =
            localComment.author == currentUsername ||
            (_currentPostAuthorUsername != null &&
                _currentPostAuthorUsername == currentUsername);

        _comments[index] = localComment.copyWith(
          emotionCounts:
              (isPrivate && !canViewPrivate)
                  ? <String, String>{}
                  : serverComment.emotionCounts,
          emotionUsers:
              (isPrivate && !canViewPrivate)
                  ? <String, List<Map<String, dynamic>>>{}
                  : serverComment.emotionUsers,
          updatedAt: serverComment.updatedAt,
        );

        notifyListeners();
      }
    } else {
      // 로컬에 없으면 추가 (다른 사용자가 작성한 댓글)
      final serverContent = data['content']?.toString() ?? '';
      final originalContent =
          data['originalContent']?.toString() ?? serverContent;
      final finalContent =
          originalContent.isNotEmpty ? originalContent : serverContent;
      final dataWithCheckedContent = Map<String, dynamic>.from(data);
      dataWithCheckedContent['content'] = finalContent;
      _comments.add(Comment.fromServer(dataWithCheckedContent));
      notifyListeners();
    }
  }

  void _handleCommentDeleted(Map<String, dynamic> data) {
    debugPrint('[CommentService] 댓글 삭제 이벤트 수신 (검증용)');
    debugPrint('[CommentService] 🔍 WebSocket 데이터: $data');

    final commentId = data['commentId'].toString();
    final index = _comments.indexWhere((c) => c.id == commentId);

    if (index != -1) {
      debugPrint('[CommentService] ⚠️ 로컬에 댓글이 남아있음 - 제거');
      debugPrint('[CommentService] 다른 사용자가 삭제했거나 동기화 지연');

      _comments.removeAt(index);
      _serverCommentCount--; // 🎯 전체 댓글 수 감소

      notifyListeners();
    } else {
      debugPrint('[CommentService] ✅ 검증 성공 - 로컬에서 이미 삭제됨');
    }
  }

  void _handleCommentLiked(Map<String, dynamic> data) async {
    // 🎯 비동기로 처리하여 UI 스레드 블로킹 방지
    await Future.microtask(() async {
      final commentId = data['commentId'].toString();
      final index = _comments.indexWhere((c) => c.id == commentId);
      if (index == -1) return;

      final comment = _comments[index];

      // 서버가 전체 emotionCounts를 보내주면 전체 교체
      if (data.containsKey('emotionCounts')) {
        // 🎯 비밀댓글인 경우 이모지 반응도 권한 체크
        final isPrivate = comment.isSecret || comment.visibility == 'PRIVATE';
        final currentUsername = await _getCurrentUsername();
        final canViewPrivate =
            comment.author == currentUsername ||
            (_currentPostAuthorUsername != null &&
                _currentPostAuthorUsername == currentUsername);

        final emotionCountsRaw = data['emotionCounts'];
        final emotionCounts =
            emotionCountsRaw is Map<String, dynamic>
                ? emotionCountsRaw
                : <String, dynamic>{};
        final emotionCountsMap = <String, String>{};
        if (!isPrivate || canViewPrivate) {
          emotionCounts.forEach((key, value) {
            emotionCountsMap[key] = value.toString();
          });
        }

        // 🎯 emotionUsers도 함께 업데이트
        final emotionUsersRaw = data['emotionUsers'];
        final emotionUsers = <String, List<Map<String, dynamic>>>{};
        if ((!isPrivate || canViewPrivate) &&
            emotionUsersRaw is Map<String, dynamic>) {
          emotionUsersRaw.forEach((emoji, users) {
            if (users is List) {
              emotionUsers[emoji] =
                  users.map((u) => Map<String, dynamic>.from(u)).toList();
            }
          });
        }

        _comments[index] = comment.copyWith(
          emotionCounts: emotionCountsMap,
          emotionUsers:
              emotionUsers.isNotEmpty ? emotionUsers : comment.emotionUsers,
        );

        // 🎯 notifyListeners를 다음 프레임에 실행하여 UI 블로킹 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
        return;
      }

      // 부분 정보만 있는 경우 (emoji, count)
      final emoji = data['emoji']?.toString() ?? '👍';
      final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
      final newEmotionCounts = Map<String, String>.from(comment.emotionCounts);

      if (count > 0) {
        newEmotionCounts[emoji] = count.toString();
        _comments[index] = comment.copyWith(emotionCounts: newEmotionCounts);
      } else {
        newEmotionCounts.remove(emoji);
        // 🎯 이모지 제거 시 emotionUsers에서도 제거
        final newEmotionUsers = Map<String, List<Map<String, dynamic>>>.from(
          comment.emotionUsers,
        );
        newEmotionUsers.remove(emoji);
        _comments[index] = comment.copyWith(
          emotionCounts: newEmotionCounts,
          emotionUsers: newEmotionUsers,
        );
      }

      // 🎯 notifyListeners를 다음 프레임에 실행하여 UI 블로킹 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    });
  }

  void _handleCommentUnliked(Map<String, dynamic> data) async {
    // 🎯 비동기로 처리하여 UI 스레드 블로킹 방지
    await Future.microtask(() async {
      final commentId = data['commentId'].toString();
      final index = _comments.indexWhere((c) => c.id == commentId);
      if (index == -1) return;

      final comment = _comments[index];

      // 서버가 전체 emotionCounts를 보내주면 전체 교체
      if (data.containsKey('emotionCounts')) {
        final emotionCountsRaw = data['emotionCounts'];
        final emotionCounts =
            emotionCountsRaw is Map<String, dynamic>
                ? emotionCountsRaw
                : <String, dynamic>{};
        final emotionCountsMap = <String, String>{};
        emotionCounts.forEach((key, value) {
          emotionCountsMap[key] = value.toString();
        });

        // 🎯 emotionUsers도 함께 업데이트
        final emotionUsersRaw = data['emotionUsers'];
        final emotionUsers = <String, List<Map<String, dynamic>>>{};
        if (emotionUsersRaw is Map<String, dynamic>) {
          emotionUsersRaw.forEach((emoji, users) {
            if (users is List) {
              emotionUsers[emoji] =
                  users.map((u) => Map<String, dynamic>.from(u)).toList();
            }
          });
        }

        _comments[index] = comment.copyWith(
          emotionCounts: emotionCountsMap,
          emotionUsers:
              emotionUsers.isNotEmpty ? emotionUsers : comment.emotionUsers,
        );

        // 🎯 notifyListeners를 다음 프레임에 실행하여 UI 블로킹 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
        return;
      }

      // 부분 정보만 있는 경우 (emoji, count)
      final emoji = data['emoji']?.toString() ?? '👍';
      final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
      final newEmotionCounts = Map<String, String>.from(comment.emotionCounts);

      if (count > 0) {
        newEmotionCounts[emoji] = count.toString();
        _comments[index] = comment.copyWith(emotionCounts: newEmotionCounts);
      } else {
        newEmotionCounts.remove(emoji);
        // 🎯 이모지 제거 시 emotionUsers에서도 제거
        final newEmotionUsers = Map<String, List<Map<String, dynamic>>>.from(
          comment.emotionUsers,
        );
        newEmotionUsers.remove(emoji);
        _comments[index] = comment.copyWith(
          emotionCounts: newEmotionCounts,
          emotionUsers: newEmotionUsers,
        );
      }

      // 🎯 notifyListeners를 다음 프레임에 실행하여 UI 블로킹 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    });
  }

  /// 🎯 새 댓글 확인 (기존 캐시 유지하면서 기존 캐시된 댓글을 만날 때까지 확인)
  Future<void> checkForNewComments() async {
    if (_currentPostId == null || _currentPostId!.isEmpty || _isLoading) {
      debugPrint(
        '[CommentService] 새 댓글 확인 건너뜀: postId=$_currentPostId, loading=$_isLoading',
      );
      return;
    }

    // 기존 댓글이 없으면 일반 로드 호출
    if (_comments.isEmpty) {
      await loadComments();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('[CommentService] 새 댓글 확인 시작 (기존 캐시된 댓글을 만날 때까지)');

      // 기존 댓글 ID 집합
      final existingIds = _comments.map((c) => c.id).toSet();
      final newComments = <Comment>[];
      int currentPage = 0;
      const pageSize = defaultPageSize; // 🎯 새 댓글 확인은 기본 크기 사용
      bool foundExistingComment = false; // 기존 캐시된 댓글을 만났는지 여부

      // 🎯 기존 캐시된 댓글을 만날 때까지 페이지 순회
      while (!foundExistingComment) {
        final response = await _dio.get(
          '/api/comments/post/$_currentPostId',
          queryParameters: {'page': currentPage, 'size': pageSize},
          options: Options(receiveTimeout: const Duration(seconds: 5)),
        );

        if (response.statusCode != 200) {
          debugPrint('[CommentService] 새 댓글 확인 실패: ${response.statusCode}');
          break;
        }

        final responseData = response.data;
        List<dynamic> commentsData = [];

        if (responseData is Map<String, dynamic>) {
          if (responseData.containsKey('content')) {
            commentsData = responseData['content'] as List<dynamic>? ?? [];
          } else if (responseData.containsKey('data')) {
            commentsData = responseData['data'] as List<dynamic>? ?? [];
          }
          // 마지막 페이지 확인
          final isLast = responseData['last'] as bool? ?? false;
          if (isLast && commentsData.isEmpty) {
            break; // 마지막 페이지이고 댓글이 없으면 종료
          }
        } else if (responseData is List) {
          commentsData = responseData;
          if (commentsData.isEmpty) {
            break; // 빈 리스트면 종료
          }
        }

        List<Comment> flatten(Comment root) {
          final out = <Comment>[];
          void walk(Comment c) {
            out.add(c);
            for (final r in c.replies) {
              walk(r);
            }
          }

          walk(root);
          return out;
        }

        // 현재 페이지의 댓글 처리
        for (final commentJson in commentsData) {
          if (commentJson is! Map<String, dynamic>) continue;

          try {
            final commentId = commentJson['id']?.toString() ?? '';

            // 새 댓글 파싱 (서버가 parent + replies 트리로 줄 수 있으므로 flat으로 펼침)
            final originalContent = commentJson['content']?.toString() ?? '';
            final commentContent = await _checkPrivateCommentAccess(
              commentJson,
              originalContent,
            );
            final visibility =
                commentJson['visibility']?.toString() ?? 'PUBLIC';
            final isPrivate = visibility == 'PRIVATE';

            final currentUsername = await _getCurrentUsername();
            final author =
                commentJson['author']?.toString() ??
                commentJson['authorUsername']?.toString() ??
                '';
            final canViewPrivate =
                author == currentUsername ||
                (_currentPostAuthorUsername != null &&
                    _currentPostAuthorUsername == currentUsername);

            final emotionCountsRaw = commentJson['emotionCounts'];
            Map<String, dynamic> emotionCounts =
                emotionCountsRaw is Map<String, dynamic>
                    ? emotionCountsRaw
                    : <String, dynamic>{};

            // 🎯 myEmotions는 배열([])로 옴: [❤️] → {❤️: '1'}
            final myEmotionsRaw = commentJson['myEmotions'];
            final myEmotionsMap = <String, String>{};
            if (myEmotionsRaw is List) {
              for (final emoji in myEmotionsRaw) {
                if (emoji != null) {
                  myEmotionsMap[emoji.toString()] = '1';
                }
              }
            } else if (myEmotionsRaw is Map<String, dynamic>) {
              myEmotionsRaw.forEach((key, value) {
                myEmotionsMap[key] = value.toString();
              });
            }
            Map<String, dynamic> myEmotions = myEmotionsMap;

            final emotionUsersRaw = commentJson['emotionUsers'];
            Map<String, dynamic> emotionUsers =
                emotionUsersRaw is Map<String, dynamic>
                    ? emotionUsersRaw
                    : <String, dynamic>{};

            if (isPrivate && !canViewPrivate) {
              emotionCounts = <String, dynamic>{};
              myEmotions = <String, dynamic>{};
              emotionUsers = <String, dynamic>{};
            }

            final mappedComment = {
              'id': commentId,
              'author': author,
              'content': commentContent,
              'authorProfileImageUrl':
                  commentJson['authorProfileImageUrl']?.toString() ?? '',
              'postId':
                  commentJson['postId']?.toString() ?? _currentPostId ?? '',
              'parentId': commentJson['parentId']?.toString(),
              'imageUrl': commentJson['imageUrl']?.toString(),
              'visibility': visibility,
              'emotionCounts': emotionCounts,
              'myEmotions': myEmotions,
              'emotionUsers': emotionUsers,
              'replies': commentJson['replies'] ?? <dynamic>[],
              'createdAt': commentJson['createdAt']?.toString() ?? '',
              'updatedAt': commentJson['updatedAt']?.toString() ?? '',
              'mentionedUsernames':
                  commentJson['mentionedUsernames'] as List<dynamic>?,
              'isSecret': isPrivate,
              'isRestricted': isPrivate,
              'visibleToUsername': null,
            };
            final parsed = Comment.fromJson(mappedComment);
            final flat = flatten(parsed);

            // 🎯 flat 중에 기존 캐시된 댓글을 만나면 중단 (reply 포함)
            final hit = flat.firstWhere(
              (c) => existingIds.contains(c.id),
              orElse:
                  () => Comment(
                    id: '',
                    author: '',
                    content: '',
                    authorProfileImageUrl: '',
                    postId: _currentPostId ?? '',
                    createdAt: '',
                    updatedAt: '',
                  ),
            );
            if (hit.id.isNotEmpty) {
              foundExistingComment = true;
              debugPrint(
                '[CommentService] 기존 캐시된 댓글 발견 (ID: ${hit.id}), 새 댓글 확인 중단',
              );
              break;
            }

            for (final c in flat) {
              if (!existingIds.contains(c.id)) {
                newComments.add(c);
              }
            }
          } catch (e) {
            debugPrint('[CommentService] 새 댓글 파싱 오류: $e');
          }
        }

        // 기존 캐시된 댓글을 만났거나, 마지막 페이지이거나, 빈 페이지면 종료
        if (foundExistingComment || commentsData.isEmpty) {
          break;
        }

        currentPage++;
      }

      if (newComments.isNotEmpty) {
        debugPrint(
          '[CommentService] 새 댓글 ${newComments.length}개 발견 (${currentPage + 1}페이지 확인), 기존 캐시에 추가',
        );
        _comments.addAll(newComments);
        notifyListeners();
      } else {
        debugPrint('[CommentService] 새 댓글 없음 (${currentPage + 1}페이지 확인)');
      }
    } catch (e) {
      debugPrint('[CommentService] 새 댓글 확인 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 댓글 로드 (API 호출)
  Future<void> loadComments({
    bool refresh = false,
    int? size,
    int? targetPage,
  }) async {
    if (_currentPostId == null || _currentPostId!.isEmpty) {
      debugPrint('[CommentService] 댓글 로드 건너뜀: postId=$_currentPostId');
      return;
    }

    int? pageToLoad;
    try {
      List<dynamic> lastTopLevelCommentsData = const [];
      final pageSize = size ?? _pageSize;
      _pageSize = pageSize;

      // refresh면 전체 상태를 초기화하고 최신(page=0)부터 다시 로드
      if (refresh) {
        _comments.clear();
        _loadedPages.clear();
        _loadingPages.clear();
        _minLoadedPage = null;
        _maxLoadedPage = null;
        _totalPages = null;
        _currentPage = 0;
        _hasMoreComments = true;
      }

      // 어떤 page를 로드할지 결정
      if (targetPage != null) {
        pageToLoad = targetPage;
      } else if (_maxLoadedPage != null) {
        // 기본 호출(loadComments())은 "더 과거" 방향으로 진행
        pageToLoad = _maxLoadedPage! + 1;
      } else {
        pageToLoad = _currentPage;
      }

      // 이미 로드한 페이지면 스킵
      if (_loadedPages.contains(pageToLoad)) {
        debugPrint('[CommentService] 이미 로드한 페이지 스킵: page=$pageToLoad');
        return;
      }

      // 이미 로딩 중인 페이지면 스킵
      if (_loadingPages.contains(pageToLoad) || _isLoading) {
        debugPrint('[CommentService] 로딩 중 스킵: page=$pageToLoad');
        return;
      }

      // older 방향(기본 호출)에서 더 이상 없으면 스킵 (totalPages가 없으면 기존 hasMore로 판단)
      if (targetPage == null &&
          !refresh &&
          !_hasMoreComments &&
          _totalPages == null) {
        debugPrint('[CommentService] 댓글 로드 건너뜀: hasMore=$_hasMoreComments');
        return;
      }

      _isLoading = true;
      _loadingPages.add(pageToLoad);
      notifyListeners();

      debugPrint('[CommentService] API 호출 시작');
      debugPrint('[CommentService] PostId: $_currentPostId');
      debugPrint('[CommentService] 로드할 페이지: $pageToLoad, pageSize: $pageSize');

      final response = await _dio.get(
        '/api/comments/post/$_currentPostId',
        queryParameters: {'page': pageToLoad, 'size': pageSize},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint('[CommentService] 댓글 조회 응답 상태: ${response.statusCode}');
      debugPrint('[CommentService] 댓글 조회 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final responseData = response.data;
        debugPrint('[CommentService] 파싱된 데이터: $responseData');

        // 🎯 댓글 API 응답 구조 확인
        List<dynamic> commentsData = [];
        Map<String, dynamic>? responseMap;

        if (responseData is Map<String, dynamic>) {
          responseMap = responseData;
          // 응답이 Map인 경우: { "content": [...], "totalElements": 10 } 또는 { "data": [...] }
          if (responseData.containsKey('content')) {
            commentsData = responseData['content'] as List<dynamic>? ?? [];
          } else if (responseData.containsKey('data')) {
            commentsData = responseData['data'] as List<dynamic>? ?? [];
          }
        } else if (responseData is List) {
          commentsData = responseData;
        }
        lastTopLevelCommentsData = commentsData;

        debugPrint('[CommentService] 댓글 데이터: ${commentsData.length}개');

        // 🎯 사용자명을 한 번만 읽어서 재사용 (성능 최적화 - 100개 댓글마다 100번 호출 방지)
        final currentUsername = await _getCurrentUsername();

        final newComments = <Comment>[];

        List<Comment> flatten(Comment root) {
          final out = <Comment>[];
          void walk(Comment c) {
            out.add(c);
            for (final r in c.replies) {
              walk(r);
            }
          }

          walk(root);
          return out;
        }

        // 댓글 데이터를 Comment 형식으로 변환
        for (int i = 0; i < commentsData.length; i++) {
          final commentJson = commentsData[i];
          // 🎯 타입 안전성 체크
          if (commentJson is! Map<String, dynamic>) {
            debugPrint(
              '[CommentService] ⚠️ 댓글 데이터[$i] 타입 오류: ${commentJson.runtimeType}, 값: $commentJson',
            );
            continue; // 잘못된 형식의 데이터는 건너뛰기
          }
          final commentData = commentJson;

          try {
            // 🎯 비밀댓글 권한 체크 (명세서: visibility: "PRIVATE"인 댓글은 작성자와 포스트 작성자만 볼 수 있음)
            final originalContent = commentData['content']?.toString() ?? '';
            final commentContent = await _checkPrivateCommentAccess(
              commentData,
              originalContent,
            );
            final visibility =
                commentData['visibility']?.toString() ?? 'PUBLIC';
            final isPrivate = visibility == 'PRIVATE';

            // 🎯 비밀댓글에 권한이 없으면 이모지 반응도 제거 (명세서: 비밀댓글의 경우 emotionCounts, myEmotions, emotionUsers는 빈 값)
            // currentUsername은 루프 밖에서 한 번만 읽음
            final author =
                commentData['author']?.toString() ??
                commentData['authorUsername']?.toString() ??
                '';
            final canViewPrivate =
                author == currentUsername ||
                (_currentPostAuthorUsername != null &&
                    _currentPostAuthorUsername == currentUsername);

            // 🎯 emotionCounts, myEmotions, emotionUsers는 배열([]) 또는 Map으로 올 수 있으므로 타입 체크
            final emotionCountsRaw = commentData['emotionCounts'];
            Map<String, dynamic> emotionCounts =
                emotionCountsRaw is Map<String, dynamic>
                    ? emotionCountsRaw
                    : <String, dynamic>{}; // 배열이거나 null이면 빈 Map

            // 🎯 myEmotions는 배열([])로 옴: [❤️] → {❤️: '1'}
            final myEmotionsRaw = commentData['myEmotions'];
            final myEmotionsMap = <String, String>{};
            if (myEmotionsRaw is List) {
              for (final emoji in myEmotionsRaw) {
                if (emoji != null) {
                  myEmotionsMap[emoji.toString()] = '1';
                }
              }
            } else if (myEmotionsRaw is Map<String, dynamic>) {
              myEmotionsRaw.forEach((key, value) {
                myEmotionsMap[key] = value.toString();
              });
            }
            Map<String, dynamic> myEmotions = myEmotionsMap;

            final emotionUsersRaw = commentData['emotionUsers'];
            Map<String, dynamic> emotionUsers =
                emotionUsersRaw is Map<String, dynamic>
                    ? emotionUsersRaw
                    : <String, dynamic>{}; // 배열이거나 null이면 빈 Map

            if (isPrivate && !canViewPrivate) {
              emotionCounts = <String, dynamic>{};
              myEmotions = <String, dynamic>{};
              emotionUsers = <String, dynamic>{};
            }

            // 댓글 데이터를 Comment 형식으로 변환
            final mappedComment = {
              'id': commentData['id']?.toString() ?? '',
              'author':
                  commentData['author']?.toString() ??
                  commentData['authorUsername']?.toString() ??
                  '',
              'content': commentContent,
              'authorProfileImageUrl':
                  commentData['authorProfileImageUrl']?.toString() ?? '',
              'postId':
                  commentData['postId']?.toString() ?? _currentPostId ?? '',
              'parentId': commentData['parentId']?.toString(),
              'imageUrl': commentData['imageUrl']?.toString(),
              'visibility': commentData['visibility']?.toString() ?? 'PUBLIC',
              'emotionCounts': emotionCounts,
              'myEmotions': myEmotions,
              'emotionUsers': emotionUsers,
              'replies': commentData['replies'] ?? <dynamic>[],
              'createdAt': commentData['createdAt']?.toString() ?? '',
              'updatedAt': commentData['updatedAt']?.toString() ?? '',
              'mentionedUsernames':
                  commentData['mentionedUsernames'] as List<dynamic>?,
              'isSecret': isPrivate, // visibility가 PRIVATE이면 isSecret
              'isRestricted': isPrivate, // visibility가 PRIVATE이면 isRestricted
              'visibleToUsername': null, // 명세서에는 없음
            };

            final comment = Comment.fromJson(mappedComment);
            // 🎯 서버가 parent + replies 트리로 줄 수 있으므로 flat으로 펼쳐서 chat UI에 맞춤
            newComments.addAll(flatten(comment));
          } catch (e, stackTrace) {
            debugPrint('[CommentService] ⚠️ 댓글[$i] 파싱 오류: $e');
            debugPrint('[CommentService] 스택 트레이스: $stackTrace');
            debugPrint('[CommentService] 댓글 데이터: $commentData');
            continue; // 파싱 실패한 댓글은 건너뛰기
          }
        }

        // 중복 제거: 이미 있는 댓글은 추가하지 않음
        final existingIds = _comments.map((c) => c.id).toSet();
        final uniqueNewComments =
            newComments.where((c) => !existingIds.contains(c.id)).toList();

        debugPrint(
          '[CommentService] 중복 제거: ${newComments.length}개 -> ${uniqueNewComments.length}개',
        );

        _comments.addAll(uniqueNewComments);

        // 🎯 페이지네이션 정보 확인 (댓글 API 응답 구조에 따라)
        if (responseMap != null) {
          final totalElements = responseMap['totalElements'] as int?;
          final totalPages = responseMap['totalPages'] as int?;
          final isLast = responseMap['last'] as bool?;
          final currentPageNum = responseMap['number'] as int?;

          if (isLast != null) {
            // 🎯 서버가 isLast를 제공하면 그것을 우선 사용
            _hasMoreComments = !isLast;
            debugPrint(
              '[CommentService] isLast 기반: isLast=$isLast, hasMore=$_hasMoreComments',
            );
          } else if (totalElements != null && totalPages != null) {
            _totalPages = totalPages;
            // 🎯 totalPages 기반 계산: 현재 페이지가 마지막 페이지보다 작으면 더 있음
            final currentPage = currentPageNum ?? pageToLoad;
            _hasMoreComments = currentPage < (totalPages - 1);
            debugPrint(
              '[CommentService] totalPages 기반: currentPage=$currentPage, totalPages=$totalPages, hasMore=$_hasMoreComments',
            );
          } else {
            // 🎯 기본값: 로드된 댓글이 size와 같거나 크면 더 있을 수 있음
            // 단, 정확하지 않으므로 서버 응답을 우선해야 함
            _hasMoreComments = lastTopLevelCommentsData.length >= pageSize;
            debugPrint(
              '[CommentService] 기본값 기반: loaded=${uniqueNewComments.length}, pageSize=$pageSize, hasMore=$_hasMoreComments',
            );
          }
        } else {
          // 기본값: 로드된 댓글이 size보다 적으면 더 이상 없음
          _hasMoreComments = lastTopLevelCommentsData.length >= pageSize;
          debugPrint(
            '[CommentService] responseMap 없음: loaded=${uniqueNewComments.length}, pageSize=$pageSize, hasMore=$_hasMoreComments',
          );
        }

        // 🎯 양방향 페이지네이션 상태 업데이트 (로드 성공 후)
        _loadedPages.add(pageToLoad);
        _minLoadedPage =
            _minLoadedPage == null
                ? pageToLoad
                : (_minLoadedPage! < pageToLoad ? _minLoadedPage : pageToLoad);
        _maxLoadedPage =
            _maxLoadedPage == null
                ? pageToLoad
                : (_maxLoadedPage! > pageToLoad ? _maxLoadedPage : pageToLoad);

        // 기본 호출은 과거 방향으로 진행하므로 currentPage는 "다음 과거 페이지"를 가리키게 유지
        _currentPage = (_maxLoadedPage ?? pageToLoad) + 1;

        debugPrint(
          '[CommentService] 댓글 로드 완료: ${uniqueNewComments.length}개 추가',
        );
        debugPrint(
          '[CommentService] 다음 페이지: $_currentPage, hasMore: $_hasMoreComments',
        );
      } else {
        debugPrint('[CommentService] 댓글 로드 실패: ${response.statusCode}');
        throw HttpException('댓글 로드 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[CommentService] 댓글 로드 오류: $e');
      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      // 오류 발생 시 빈 리스트 유지 (폴백 데이터 제거)
      // _loadFallbackComments();
    } finally {
      _isLoading = false;
      if (pageToLoad != null) {
        _loadingPages.remove(pageToLoad);
      }
      notifyListeners();
    }
  }

  /// 🎯 더 과거(older) 페이지 로드
  Future<void> loadOlderComments({int? size}) async {
    if (!hasOlderComments) return;
    await loadComments(size: size);
  }

  /// 🎯 더 최신(newer) 페이지 로드
  /// - minLoadedPage가 0보다 클 때만 가능
  Future<void> loadNewerComments({int? size}) async {
    final minPage = _minLoadedPage;
    if (minPage == null || minPage <= 0) return;
    await loadComments(targetPage: minPage - 1, size: size ?? _pageSize);
  }

  /// 🎯 가장 최신(page=0)만 빠르게 확보
  /// - 중간 페이지로 시작한 경우 "최신으로 이동" UX를 안정화하기 위함
  Future<void> loadNewestComments({int? size}) async {
    await loadComments(targetPage: 0, size: size ?? _pageSize);
  }

  /// 🎯 댓글 위치 찾기 (Comment Locate API)
  ///
  /// 딥링크/알림으로 들어온 commentId가 댓글 목록(page/size 기반, **부모 댓글 기준**)에서
  /// 어느 page인지 서버에서 계산해서 반환한다.
  ///
  /// ⚠️ size는 댓글 목록 조회 API와 동일해야 한다. (프론트 기본: 100)
  Future<CommentLocateResponse> locateCommentInPost({
    required String postId,
    required String commentId,
    int size = defaultPageSize,
  }) async {
    if (postId.isEmpty || commentId.isEmpty) {
      throw Exception('postId/commentId가 비어있습니다.');
    }
    if (size <= 0 || size > 200) {
      throw Exception('size는 1~200 사이여야 합니다.');
    }

    final response = await _dio.get(
      '/api/comments/post/$postId/locate',
      queryParameters: {'commentId': commentId, 'size': size},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );

    if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
      return CommentLocateResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    }

    throw Exception('댓글 위치 찾기 실패: ${response.statusCode} - ${response.data}');
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

  /// 🎯 로컬 이미지로만 댓글 추가 (서버 요청 없음, 낙관적 업데이트만) - 단일 이미지
  void addCommentLocalOnly({
    required String username,
    required String content,
    String? authorProfileImageUrl,
    String? parentId,
    required String localImagePath, // 🎯 단일 이미지 경로
    String? visibleToUsername,
    required String tempId,
  }) {
    if (_currentPostId == null) return;

    // 🎯 UTC 시간 사용
    final utcNow = DateTime.now().toUtc().toIso8601String();

    // 🎯 비밀댓글에 답장하는 경우 자동으로 PRIVATE로 설정
    bool isSecret = visibleToUsername != null && visibleToUsername.isNotEmpty;
    if (!isSecret && parentId != null) {
      final parentComment = _comments.firstWhere(
        (c) => c.id == parentId,
        orElse:
            () => Comment(
              id: '',
              author: '',
              content: '',
              authorProfileImageUrl: '',
              postId: _currentPostId!,
              createdAt: '',
              updatedAt: '',
            ),
      );
      if (parentComment.id.isNotEmpty &&
          (parentComment.isSecret || parentComment.visibility == 'PRIVATE')) {
        isSecret = true;
      }
    }

    // 🎯 이미지만 보낼 때 content에 [IMAGE] 마커 추가
    final trimmedContent = content.trim();
    final optimisticContent =
        trimmedContent.isEmpty ? '[IMAGE]' : trimmedContent;

    final optimisticComment = Comment(
      id: tempId,
      author: username,
      content: optimisticContent,
      authorProfileImageUrl: authorProfileImageUrl ?? '',
      postId: _currentPostId!,
      parentId: parentId,
      imageUrl: null, // 🎯 아직 업로드 전이므로 null
      localImagePath: localImagePath, // 🎯 로컬 파일 경로
      visibility: isSecret ? 'PRIVATE' : 'PUBLIC',
      createdAt: utcNow,
      updatedAt: utcNow,
      isPending: true, // 🎯 업로드 대기 중
      isFailed: false,
      isSecret: isSecret,
      isRestricted: isSecret,
      visibleToUsername: visibleToUsername,
    );

    _comments.add(optimisticComment);
    _serverCommentCount++;
    notifyListeners();
    debugPrint('[CommentService] 로컬 이미지 댓글 추가 (낙관적 업데이트): $tempId');
  }

  /// 🎯 이미지 URL 업로드 완료 후 서버에 댓글 전송 (단일 이미지)
  Future<void> addCommentWithImageUrl({
    required String tempCommentId,
    required String imageUrl,
  }) async {
    if (_currentPostId == null || imageUrl.isEmpty) return;

    // 🎯 R2 URL인지 확인 (pending://, 로컬 경로 제외)
    if (imageUrl.startsWith('pending://') ||
        imageUrl.startsWith('file://') ||
        imageUrl.startsWith('/') ||
        (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://'))) {
      debugPrint('[CommentService] ⚠️ 유효하지 않은 URL (R2 URL 아님): $imageUrl');
      return;
    }

    // 🎯 임시 댓글 찾기
    final commentIndex = _comments.indexWhere((c) => c.id == tempCommentId);
    if (commentIndex == -1) {
      debugPrint('[CommentService] ⚠️ 임시 댓글을 찾을 수 없음: $tempCommentId');
      return;
    }

    final tempComment = _comments[commentIndex];
    final originalContent = tempComment.content;

    // 🎯 content를 "[IMAGE] https://image-url" 형식으로 업데이트
    final finalContent =
        originalContent == '[IMAGE]'
            ? '[IMAGE] $imageUrl'
            : '$originalContent\n[IMAGE] $imageUrl';

    // 🎯 낙관적 업데이트: content와 imageUrl 업데이트
    // localImagePath는 명시적으로 유지 (로컬 이미지 계속 표시)
    _comments[commentIndex] = tempComment.copyWith(
      content: finalContent,
      imageUrl: imageUrl,
      localImagePath: tempComment.localImagePath, // 🎯 명시적으로 유지
    );
    notifyListeners();

    debugPrint(
      '[CommentService] 이미지 URL 업데이트 (로컬 이미지 유지): $tempCommentId -> $imageUrl',
    );

    // 🎯 서버에 댓글 전송
    try {
      // 🎯 언급 파싱
      var mentionedUsernames = MentionParser.extractMentions(finalContent);
      final currentUsername = await _getCurrentUsername();
      if (currentUsername != null) {
        mentionedUsernames =
            mentionedUsernames.where((u) => u != currentUsername).toList();
      }

      // 🎯 postId를 정수로 변환
      final postIdInt = int.tryParse(_currentPostId!);
      if (postIdInt == null) {
        throw Exception('postId를 정수로 변환할 수 없습니다: $_currentPostId');
      }

      // 🎯 parentId를 정수로 변환
      int? parentIdInt;
      if (tempComment.parentId != null) {
        parentIdInt = int.tryParse(tempComment.parentId!);
        if (parentIdInt == null) {
          throw Exception('parentId를 정수로 변환할 수 없습니다: ${tempComment.parentId}');
        }
      }

      final requestBody = <String, dynamic>{
        'content': finalContent, // 🎯 "[IMAGE] https://image-url" 형식
        'postId': postIdInt,
        if (parentIdInt != null) 'parentId': parentIdInt,
        'visibility': tempComment.visibility,
        'usedUrls': [imageUrl], // 🎯 R2 URL만 포함 (단일 이미지)
        if (mentionedUsernames.isNotEmpty)
          'mentionedUsernames': mentionedUsernames,
      };

      debugPrint('[CommentService] 이미지 댓글 전송 요청: $requestBody');

      final response = await _dio.post(
        '/api/comments',
        data: requestBody,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint(
        '[CommentService] 이미지 댓글 전송 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData =
            response.data is Map<String, dynamic>
                ? Map<String, dynamic>.from(response.data)
                : <String, dynamic>{};

        final serverComment = Comment.fromJson(responseData);

        // 같은 ID가 이미 있는지 확인 (WebSocket이 먼저 추가했을 수 있음)
        final existingServerCommentIndex = _comments.indexWhere(
          (c) => c.id == serverComment.id,
        );
        if (existingServerCommentIndex != -1) {
          debugPrint(
            '[CommentService] ⚠️ 서버 응답 댓글이 이미 존재함 (WebSocket 먼저 도착) - ID: ${serverComment.id}',
          );
          _comments.removeWhere((c) => c.id == tempCommentId);
          notifyListeners();
          return;
        }

        // 임시 댓글 찾아서 교체
        final tempIndex = _comments.indexWhere((c) => c.id == tempCommentId);
        if (tempIndex != -1) {
          debugPrint(
            '[CommentService] 🔄 임시 댓글 교체: $tempCommentId → ${serverComment.id}',
          );
          // 🎯 로컬 이미지 경로 유지 (깜빡임 방지)
          final tempComment = _comments[tempIndex];
          _comments[tempIndex] = serverComment.copyWith(
            localImagePath: tempComment.localImagePath,
          );
        } else {
          debugPrint('[CommentService] ⚠️ 임시 댓글이 없음 (이미 제거됨?)');
          return;
        }
        notifyListeners();
        debugPrint('[CommentService] 이미지 댓글 전송 성공: ${serverComment.id}');
      } else {
        // 실패: pending → failed로 변경 (즉시 UI 업데이트)
        final index = _comments.indexWhere((c) => c.id == tempCommentId);
        if (index != -1) {
          _comments[index] = _comments[index].copyWith(
            isPending: false,
            isFailed: true,
          );
          // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
          notifyListeners();
          debugPrint(
            '[CommentService] 이미지 댓글 전송 실패 - failed 상태로 변경 및 UI 업데이트: ${response.statusCode}',
          );
        }
        // 🎯 throw 하지 않고 바로 return (catch 블록에서 중복 처리 방지)
        return;
      }
    } catch (e) {
      debugPrint('[CommentService] 이미지 댓글 전송 오류 - failed 상태로 변경: $e');

      // 실패 시: pending → failed로 변경 (이미 실패 상태가 아닌 경우에만)
      final index = _comments.indexWhere((c) => c.id == tempCommentId);
      if (index != -1) {
        final comment = _comments[index];
        // 🎯 이미 실패 상태가 아니면 변경 (즉시 UI 업데이트)
        if (!comment.isFailed) {
          _comments[index] = comment.copyWith(isPending: false, isFailed: true);
          // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
          notifyListeners();
          debugPrint('[CommentService] 이미지 댓글 전송 오류 - failed 상태로 변경 및 UI 업데이트');
        }
      }

      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
    }
  }

  /// 🎯 여러 이미지 URL 업로드 완료 후 서버에 댓글 전송 (다중 이미지 - 다른 곳에서 사용 가능)
  Future<void> addCommentWithImageUrls({
    required String tempCommentId,
    required List<String> imageUrls,
  }) async {
    if (_currentPostId == null || imageUrls.isEmpty) return;

    // 🎯 R2 URL만 필터링 (pending://, 로컬 경로 제외)
    final validImageUrls =
        imageUrls.where((url) {
          final isValid =
              !url.startsWith('pending://') &&
              !url.startsWith('file://') &&
              !url.startsWith('/') &&
              (url.startsWith('http://') || url.startsWith('https://'));
          if (!isValid) {
            debugPrint('[CommentService] ⚠️ 유효하지 않은 URL 제외: $url');
          }
          return isValid;
        }).toList();

    if (validImageUrls.isEmpty) {
      debugPrint('[CommentService] ⚠️ 유효한 이미지 URL이 없음');
      return;
    }

    // 🎯 임시 댓글 찾기
    final commentIndex = _comments.indexWhere((c) => c.id == tempCommentId);
    if (commentIndex == -1) {
      debugPrint('[CommentService] ⚠️ 임시 댓글을 찾을 수 없음: $tempCommentId');
      return;
    }

    final tempComment = _comments[commentIndex];
    final originalContent = tempComment.content;

    // 🎯 content를 "[IMAGES:url1,url2,url3]" 형식으로 업데이트
    final imageUrlsString = validImageUrls.join(',');
    final finalContent =
        originalContent == '[IMAGES]' || originalContent == '[IMAGE]'
            ? '[IMAGES:$imageUrlsString]' // 🎯 여러 이미지 형식
            : '$originalContent\n[IMAGES:$imageUrlsString]';

    // 🎯 낙관적 업데이트: content와 imageUrl 업데이트 (첫 번째 이미지, 호환성)
    _comments[commentIndex] = tempComment.copyWith(
      content: finalContent,
      imageUrl: validImageUrls.first, // 🎯 첫 번째 이미지 (호환성)
    );
    notifyListeners();

    debugPrint(
      '[CommentService] ✅ 이미지 URL 업데이트 (R2 URL만): $tempCommentId -> $validImageUrls',
    );

    // 🎯 서버에 댓글 전송
    try {
      // 🎯 언급 파싱
      var mentionedUsernames = MentionParser.extractMentions(finalContent);
      final currentUsername = await _getCurrentUsername();
      if (currentUsername != null) {
        mentionedUsernames =
            mentionedUsernames.where((u) => u != currentUsername).toList();
      }

      // 🎯 postId를 정수로 변환
      final postIdInt = int.tryParse(_currentPostId!);
      if (postIdInt == null) {
        throw Exception('postId를 정수로 변환할 수 없습니다: $_currentPostId');
      }

      // 🎯 parentId를 정수로 변환
      int? parentIdInt;
      if (tempComment.parentId != null) {
        parentIdInt = int.tryParse(tempComment.parentId!);
        if (parentIdInt == null) {
          throw Exception('parentId를 정수로 변환할 수 없습니다: ${tempComment.parentId}');
        }
      }

      final requestBody = <String, dynamic>{
        'content': finalContent, // 🎯 "[IMAGES:url1,url2,url3]" 형식
        'postId': postIdInt,
        if (parentIdInt != null) 'parentId': parentIdInt,
        'visibility': tempComment.visibility,
        'usedUrls': validImageUrls, // 🎯 R2 URL만 포함 (여러 이미지 URL 목록)
        if (mentionedUsernames.isNotEmpty)
          'mentionedUsernames': mentionedUsernames,
      };

      debugPrint('[CommentService] 이미지 댓글 전송 요청: $requestBody');

      final response = await _dio.post(
        '/api/comments',
        data: requestBody,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint(
        '[CommentService] 이미지 댓글 전송 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData =
            response.data is Map<String, dynamic>
                ? Map<String, dynamic>.from(response.data)
                : <String, dynamic>{};

        final serverComment = Comment.fromJson(responseData);

        // 같은 ID가 이미 있는지 확인 (WebSocket이 먼저 추가했을 수 있음)
        final existingServerCommentIndex = _comments.indexWhere(
          (c) => c.id == serverComment.id,
        );
        if (existingServerCommentIndex != -1) {
          debugPrint(
            '[CommentService] ⚠️ 서버 응답 댓글이 이미 존재함 (WebSocket 먼저 도착) - ID: ${serverComment.id}',
          );
          _comments.removeWhere((c) => c.id == tempCommentId);
          notifyListeners();
          return;
        }

        // 임시 댓글 찾아서 교체
        final tempIndex = _comments.indexWhere((c) => c.id == tempCommentId);
        if (tempIndex != -1) {
          debugPrint(
            '[CommentService] 🔄 임시 댓글 교체: $tempCommentId → ${serverComment.id}',
          );
          // 🎯 로컬 이미지 경로 유지 (깜빡임 방지)
          final tempComment = _comments[tempIndex];
          _comments[tempIndex] = serverComment.copyWith(
            localImagePath: tempComment.localImagePath,
          );
        } else {
          debugPrint('[CommentService] ⚠️ 임시 댓글이 없음 (이미 제거됨?)');
          return;
        }
        notifyListeners();
        debugPrint('[CommentService] 이미지 댓글 전송 성공: ${serverComment.id}');
      } else {
        // 실패: pending → failed로 변경 (즉시 UI 업데이트)
        final index = _comments.indexWhere((c) => c.id == tempCommentId);
        if (index != -1) {
          _comments[index] = _comments[index].copyWith(
            isPending: false,
            isFailed: true,
          );
          // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
          notifyListeners();
          debugPrint(
            '[CommentService] 이미지 댓글 전송 실패 - failed 상태로 변경 및 UI 업데이트: ${response.statusCode}',
          );
        }
        // 🎯 throw 하지 않고 바로 return (catch 블록에서 중복 처리 방지)
        return;
      }
    } catch (e) {
      debugPrint('[CommentService] 이미지 댓글 전송 오류 - failed 상태로 변경: $e');

      // 실패 시: pending → failed로 변경 (이미 실패 상태가 아닌 경우에만)
      final index = _comments.indexWhere((c) => c.id == tempCommentId);
      if (index != -1) {
        final comment = _comments[index];
        // 🎯 이미 실패 상태가 아니면 변경 (즉시 UI 업데이트)
        if (!comment.isFailed) {
          _comments[index] = comment.copyWith(isPending: false, isFailed: true);
          // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
          notifyListeners();
          debugPrint('[CommentService] 이미지 댓글 전송 오류 - failed 상태로 변경 및 UI 업데이트');
        }
      }

      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
    }
  }

  /// 댓글 추가 (낙관적 업데이트) - 다중 이미지 지원
  Future<void> addComment({
    required String username,
    required String content,
    String? authorProfileImageUrl, // 🎯 프로필 이미지 URL 추가
    String? parentId,
    List<String>? imageUrls, // 🎯 여러 이미지 URL 목록
    List<String>? localImagePaths, // 🎯 여러 로컬 이미지 파일 경로
    String? visibleToUsername, // 🎯 비밀 메시지 대상 사용자 (1:1)
    // 🎯 하위 호환성을 위한 단일 이미지 파라미터 (deprecated)
    @Deprecated('Use imageUrls instead') String? imageUrl,
    @Deprecated('Use localImagePaths instead') String? localImagePath,
  }) async {
    if (_currentPostId == null) return;

    // 🎯 언급 파싱 (엣지 케이스 모두 고려)
    var mentionedUsernames = MentionParser.extractMentions(content);

    // 🎯 본인 언급 제외 (명세서: 본인을 언급해도 알림이 가지 않음)
    final currentUsername = await _getCurrentUsername();
    if (currentUsername != null) {
      mentionedUsernames =
          mentionedUsernames.where((u) => u != currentUsername).toList();
    }

    // 1️⃣ 임시 ID 생성 (pending 댓글 식별용)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // 2️⃣ 낙관적 업데이트: 즉시 로컬에 댓글 추가
    // 🎯 UTC 시간 사용 (서버 시간과 일치하도록)
    final utcNow = DateTime.now().toUtc().toIso8601String();

    // 🎯 비밀댓글에 답장하는 경우 자동으로 PRIVATE로 설정
    bool isSecret = visibleToUsername != null && visibleToUsername.isNotEmpty;
    if (!isSecret && parentId != null) {
      // 부모 댓글이 비밀댓글이면 자동으로 PRIVATE로 설정
      final parentComment = _comments.firstWhere(
        (c) => c.id == parentId,
        orElse:
            () => Comment(
              id: '',
              author: '',
              content: '',
              authorProfileImageUrl: '',
              postId: _currentPostId!,
              createdAt: '',
              updatedAt: '',
            ),
      );
      if (parentComment.id.isNotEmpty &&
          (parentComment.isSecret || parentComment.visibility == 'PRIVATE')) {
        isSecret = true;
        // visibleToUsername은 null로 유지 (서버에서 자동 처리)
      }
    }

    // 🎯 이미지 경로 처리 (하위 호환성 - 댓글에서는 단일 이미지만 사용)
    final finalLocalImagePath =
        localImagePath ??
        (localImagePaths != null && localImagePaths.isNotEmpty
            ? localImagePaths.first
            : null);
    final finalImageUrl =
        imageUrl ??
        (imageUrls != null && imageUrls.isNotEmpty ? imageUrls.first : null);

    // 🎯 이미지만 보낼 때 content에 [IMAGE] 마커 추가 (렌더링 시 참고용)
    final trimmedContent = content.trim();
    final hasImage = finalLocalImagePath != null || finalImageUrl != null;
    final optimisticContent =
        trimmedContent.isEmpty && hasImage
            ? '[IMAGE]' // 🎯 댓글은 단일 이미지만 지원
            : trimmedContent;

    final optimisticComment = Comment(
      id: tempId,
      author: username,
      content: optimisticContent, // 🎯 [IMAGE] 마커 포함
      authorProfileImageUrl: authorProfileImageUrl ?? '', // 🎯 프로필 이미지 즉시 설정
      postId: _currentPostId!,
      parentId: parentId,
      imageUrl: finalImageUrl, // 🎯 단일 이미지 URL
      localImagePath: finalLocalImagePath, // 🎯 단일 로컬 파일 경로
      visibility: isSecret ? 'PRIVATE' : 'PUBLIC', // 🎯 비밀댓글이면 PRIVATE
      createdAt: utcNow, // 🎯 UTC 시간 사용
      updatedAt: utcNow, // 🎯 UTC 시간 사용
      isPending: true, // 서버 전송 대기 중
      isFailed: false,
      mentionedUsernames:
          mentionedUsernames.isNotEmpty ? mentionedUsernames : null,
      isSecret: isSecret,
      isRestricted: isSecret,
      visibleToUsername: visibleToUsername,
    );

    _comments.add(optimisticComment);
    _serverCommentCount++; // 🎯 전체 댓글 수 증가
    notifyListeners(); // ⚡ UI 즉시 업데이트
    debugPrint(
      '[CommentService] 낙관적 댓글 추가: $tempId (언급: $mentionedUsernames, 비밀: $isSecret)',
    );

    // 3️⃣ 서버에 요청 전송 (댓글 API 사용)
    try {
      // 🎯 댓글 API 명세서에 따른 요청 Body
      // 🎯 단일 이미지 URL 처리 및 R2 URL만 필터링
      String? validImageUrl;
      if (finalImageUrl != null && finalImageUrl.isNotEmpty) {
        // 🎯 R2 URL인지 확인 (pending://, 로컬 경로 제외)
        if (!finalImageUrl.startsWith('pending://') &&
            !finalImageUrl.startsWith('file://') &&
            !finalImageUrl.startsWith('/') &&
            (finalImageUrl.startsWith('http://') ||
                finalImageUrl.startsWith('https://'))) {
          validImageUrl = finalImageUrl;
        } else {
          debugPrint('[CommentService] ⚠️ 유효하지 않은 URL 제외: $finalImageUrl');
        }
      }

      // 🎯 content 처리: 이미지가 있으면 [IMAGE] url 형식
      final trimmedContent = content.trim();
      String finalContent;
      if (trimmedContent.isEmpty && validImageUrl != null) {
        finalContent = '[IMAGE] $validImageUrl';
      } else if (validImageUrl != null) {
        finalContent = '$trimmedContent\n[IMAGE] $validImageUrl';
      } else {
        finalContent = trimmedContent;
      }

      debugPrint(
        '[CommentService] content 처리: original="$content", trimmed="$trimmedContent", final="$finalContent", imageUrl=$validImageUrl',
      );

      // 🎯 postId를 정수로 변환 (서버가 long 타입을 요구)
      final postIdInt = int.tryParse(_currentPostId!);
      if (postIdInt == null) {
        throw Exception('postId를 정수로 변환할 수 없습니다: $_currentPostId');
      }

      // 🎯 parentId를 정수로 변환 (대댓글인 경우)
      int? parentIdInt;
      if (parentId != null) {
        parentIdInt = int.tryParse(parentId);
        if (parentIdInt == null) {
          throw Exception('parentId를 정수로 변환할 수 없습니다: $parentId');
        }
      }

      final requestBody = <String, dynamic>{
        'content': finalContent, // 명세서: content 필드 사용
        'postId': postIdInt, // 포스트 ID (정수)
        if (parentIdInt != null) 'parentId': parentIdInt, // 대댓글인 경우
        'visibility': isSecret ? 'PRIVATE' : 'PUBLIC', // 명세서: visibility 필드 사용
        if (validImageUrl != null)
          'usedUrls': [validImageUrl], // 🎯 R2 URL만 포함 (단일 이미지)
        // 🎯 언급 기능: 명세서에 따라 mentionedUsernames 배열 포함
        if (mentionedUsernames.isNotEmpty)
          'mentionedUsernames': mentionedUsernames, // 언급된 사용자 목록
      };

      debugPrint('[CommentService] 채팅 메시지 전송 요청: $requestBody');
      debugPrint(
        '[CommentService] postId 타입: ${postIdInt.runtimeType}, 값: $postIdInt',
      );
      if (parentIdInt != null) {
        debugPrint(
          '[CommentService] parentId 타입: ${parentIdInt.runtimeType}, 값: $parentIdInt',
        );
      }

      final response = await _dio.post(
        '/api/comments',
        data: requestBody,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint(
        '[CommentService] 댓글 추가 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 성공: 서버 응답 데이터로 임시 댓글 교체
        // 🎯 비밀댓글 권한 체크
        final responseData =
            response.data is Map<String, dynamic>
                ? Map<String, dynamic>.from(response.data)
                : <String, dynamic>{};
        final originalContent = responseData['content']?.toString() ?? '';
        final checkedContent = await _checkPrivateCommentAccess(
          responseData,
          originalContent,
        );
        responseData['content'] = checkedContent;

        // 🎯 비밀댓글인 경우 이모지 반응도 권한 체크
        final visibility = responseData['visibility']?.toString() ?? 'PUBLIC';
        final isPrivate = visibility == 'PRIVATE';
        if (isPrivate) {
          final currentUsername = await _getCurrentUsername();
          final author =
              responseData['author']?.toString() ??
              responseData['authorUsername']?.toString() ??
              '';
          final canViewPrivate =
              author == currentUsername ||
              (_currentPostAuthorUsername != null &&
                  _currentPostAuthorUsername == currentUsername);
          if (!canViewPrivate) {
            responseData['emotionCounts'] = <String, dynamic>{};
            responseData['myEmotions'] = <String, dynamic>{};
            responseData['emotionUsers'] = <String, dynamic>{};
          }
        }

        final serverComment = Comment.fromJson(responseData);

        // 같은 ID가 이미 있는지 확인 (WebSocket이 먼저 추가했을 수 있음)
        final existingServerCommentIndex = _comments.indexWhere(
          (c) => c.id == serverComment.id,
        );
        if (existingServerCommentIndex != -1) {
          debugPrint(
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
          debugPrint(
            '[CommentService] 🔄 임시 댓글 교체: $tempId → ${serverComment.id}',
          );
          // 🎯 로컬 이미지 경로 유지 (아직 업로드 중일 수 있음)
          final tempComment = _comments[tempIndex];
          _comments[tempIndex] = serverComment.copyWith(
            localImagePath: tempComment.localImagePath, // 🎯 로컬 경로 유지
          );
        } else {
          debugPrint('[CommentService] ⚠️ 임시 댓글이 없음 (이미 제거됨?) - 서버 댓글 추가 안 함');
          // WebSocket이 이미 추가했으므로 여기선 추가하지 않음
          return;
        }
        notifyListeners();
        debugPrint('[CommentService] 댓글 추가 성공: ${serverComment.id}');
      } else {
        // 실패: pending → failed로 변경 (즉시 UI 업데이트)
        final index = _comments.indexWhere((c) => c.id == tempId);
        if (index != -1) {
          _comments[index] = _comments[index].copyWith(
            isPending: false,
            isFailed: true,
          );
          // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
          notifyListeners();
          debugPrint(
            '[CommentService] 댓글 추가 실패 - failed 상태로 변경 및 UI 업데이트: ${response.statusCode}',
          );
        }
        // 🎯 throw 하지 않고 바로 return (catch 블록에서 중복 처리 방지)
        return;
      }
    } catch (e) {
      debugPrint('[CommentService] 댓글 추가 오류 - failed 상태로 변경: $e');

      // 4️⃣ 실패 시: pending → failed로 변경 (이미 실패 상태가 아닌 경우에만)
      final index = _comments.indexWhere((c) => c.id == tempId);
      if (index != -1) {
        final comment = _comments[index];
        // 🎯 이미 실패 상태가 아니면 변경 (즉시 UI 업데이트)
        if (!comment.isFailed) {
          _comments[index] = comment.copyWith(isPending: false, isFailed: true);
          // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
          notifyListeners();
          debugPrint('[CommentService] 댓글 추가 오류 - failed 상태로 변경 및 UI 업데이트');
        }
      }

      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
    }
  }

  /// 🎯 댓글의 이미지 URL 업데이트 (확정 처리)
  Future<void> updateCommentImageUrl(
    String commentId,
    String newImageUrl,
  ) async {
    // 1️⃣ 낙관적 업데이트 (즉시 UI 반영)
    final commentIndex = _comments.indexWhere((c) => c.id == commentId);
    if (commentIndex == -1) {
      debugPrint('[CommentService] ⚠️ 이미지 URL을 업데이트할 댓글을 찾을 수 없음: $commentId');
      return;
    }

    final originalComment = _comments[commentIndex];
    _comments[commentIndex] = originalComment.copyWith(
      imageUrl: newImageUrl,
      updatedAt: DateTime.now().toIso8601String(),
    );

    notifyListeners(); // ⚡ UI 즉시 업데이트

    debugPrint(
      '[CommentService] 낙관적 댓글 이미지 URL 업데이트: $commentId -> $newImageUrl',
    );

    // 2️⃣ 서버에 요청 전송 (백그라운드)
    try {
      // 🎯 댓글 수정 API 명세서에 따른 요청 Body
      final requestData = {
        'content': originalComment.content,
        'postId': int.tryParse(originalComment.postId) ?? 0,
        'imageUrl': newImageUrl, // 🎯 이미지 URL 업데이트
      };
      debugPrint('[CommentService] 댓글 이미지 URL 업데이트 요청 데이터: $requestData');

      final response = await _dio.put(
        '/api/comments/$commentId',
        data: requestData,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint(
        '[CommentService] 댓글 이미지 URL 업데이트 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200) {
        debugPrint(
          '[CommentService] ✅ 댓글 이미지 URL 업데이트 성공 (WebSocket으로 최종 검증 대기)',
        );
        // 3️⃣ WebSocket이 최종 검증 데이터를 보내줄 것임
      } else {
        debugPrint(
          '[CommentService] ⚠️ 댓글 이미지 URL 업데이트 실패: ${response.statusCode}',
        );
        // 실패 시 원래 이미지 URL로 롤백
        final currentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (currentIndex != -1) {
          _comments[currentIndex] = originalComment;
          notifyListeners();
        }
        throw HttpException('댓글 이미지 URL 업데이트 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[CommentService] 댓글 이미지 URL 업데이트 오류 - 롤백: $e');

      // 4️⃣ 실패 시 원래 이미지 URL로 롤백
      final currentIndex = _comments.indexWhere((c) => c.id == commentId);
      if (currentIndex != -1) {
        _comments[currentIndex] = originalComment;
        notifyListeners();
      }

      if (e is DioException) {
        debugPrint(
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

    // 🎯 재시도 중 플래그 설정 (무한 루프 방지)
    if (comment.isPending) {
      debugPrint('[CommentService] ⚠️ 이미 재시도 중인 댓글: $tempId');
      return;
    }

    // failed → pending으로 변경
    _comments[index] = comment.copyWith(isPending: true, isFailed: false);
    notifyListeners();

    try {
      // 🎯 기존 댓글의 정보를 사용해서 직접 서버에 요청 (새로운 댓글 생성 방지)
      // 언급 파싱
      var mentionedUsernames = MentionParser.extractMentions(comment.content);
      final currentUsername = await _getCurrentUsername();
      if (currentUsername != null) {
        mentionedUsernames =
            mentionedUsernames.where((u) => u != currentUsername).toList();
      }

      // 🎯 postId를 정수로 변환
      final postIdInt = int.tryParse(_currentPostId!);
      if (postIdInt == null) {
        throw Exception('postId를 정수로 변환할 수 없습니다: $_currentPostId');
      }

      // 🎯 parentId를 정수로 변환
      int? parentIdInt;
      if (comment.parentId != null) {
        parentIdInt = int.tryParse(comment.parentId!);
        if (parentIdInt == null) {
          throw Exception('parentId를 정수로 변환할 수 없습니다: ${comment.parentId}');
        }
      }

      // 🎯 content 처리: 이미지가 있으면 [IMAGE] url 형식
      String finalContent = comment.content;
      String? validImageUrl = comment.imageUrl;

      // 🎯 R2 URL인지 확인
      if (validImageUrl != null && validImageUrl.isNotEmpty) {
        if (validImageUrl.startsWith('pending://') ||
            validImageUrl.startsWith('file://') ||
            validImageUrl.startsWith('/') ||
            (!validImageUrl.startsWith('http://') &&
                !validImageUrl.startsWith('https://'))) {
          debugPrint('[CommentService] ⚠️ 유효하지 않은 URL 제외: $validImageUrl');
          validImageUrl = null;
        }
      }

      if (validImageUrl != null) {
        final trimmedContent = comment.content.trim();
        if (trimmedContent.isEmpty || trimmedContent == '[IMAGE]') {
          finalContent = '[IMAGE] $validImageUrl';
        } else if (!trimmedContent.contains('[IMAGE]')) {
          finalContent = '$trimmedContent\n[IMAGE] $validImageUrl';
        }
      }

      final requestBody = <String, dynamic>{
        'content': finalContent,
        'postId': postIdInt,
        if (parentIdInt != null) 'parentId': parentIdInt,
        'visibility': comment.visibility,
        if (validImageUrl != null) 'usedUrls': [validImageUrl],
        if (mentionedUsernames.isNotEmpty)
          'mentionedUsernames': mentionedUsernames,
      };

      debugPrint('[CommentService] 재시도 댓글 전송 요청: $requestBody');

      final response = await _dio.post(
        '/api/comments',
        data: requestBody,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint(
        '[CommentService] 재시도 댓글 전송 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 성공: 서버 응답 데이터로 기존 댓글 교체
        final responseData =
            response.data is Map<String, dynamic>
                ? Map<String, dynamic>.from(response.data)
                : <String, dynamic>{};
        final originalContent = responseData['content']?.toString() ?? '';
        final checkedContent = await _checkPrivateCommentAccess(
          responseData,
          originalContent,
        );
        responseData['content'] = checkedContent;

        // 🎯 비밀댓글인 경우 이모지 반응도 권한 체크
        final visibility = responseData['visibility']?.toString() ?? 'PUBLIC';
        final isPrivate = visibility == 'PRIVATE';
        if (isPrivate) {
          final author =
              responseData['author']?.toString() ??
              responseData['authorUsername']?.toString() ??
              '';
          final canViewPrivate =
              author == currentUsername ||
              (_currentPostAuthorUsername != null &&
                  _currentPostAuthorUsername == currentUsername);
          if (!canViewPrivate) {
            responseData['emotionCounts'] = <String, dynamic>{};
            responseData['myEmotions'] = <String, dynamic>{};
            responseData['emotionUsers'] = <String, dynamic>{};
          }
        }

        final serverComment = Comment.fromJson(responseData);

        // 같은 ID가 이미 있는지 확인 (WebSocket이 먼저 추가했을 수 있음)
        final existingServerCommentIndex = _comments.indexWhere(
          (c) => c.id == serverComment.id,
        );
        if (existingServerCommentIndex != -1) {
          debugPrint(
            '[CommentService] ⚠️ 서버 응답 댓글이 이미 존재함 (WebSocket 먼저 도착) - ID: ${serverComment.id}',
          );
          // 기존 임시 댓글만 제거
          _comments.removeWhere((c) => c.id == tempId);
          notifyListeners();
          return;
        }

        // 기존 임시 댓글을 서버 댓글로 교체
        final tempIndex = _comments.indexWhere((c) => c.id == tempId);
        if (tempIndex != -1) {
          debugPrint(
            '[CommentService] 🔄 재시도 성공: 임시 댓글 교체: $tempId → ${serverComment.id}',
          );
          // 🎯 로컬 이미지 경로 유지 (깜빡임 방지)
          final tempComment = _comments[tempIndex];
          _comments[tempIndex] = serverComment.copyWith(
            localImagePath: tempComment.localImagePath,
          );
        } else {
          debugPrint('[CommentService] ⚠️ 임시 댓글이 없음 (이미 제거됨?)');
          return;
        }
        notifyListeners();
        debugPrint('[CommentService] 재시도 댓글 전송 성공: ${serverComment.id}');
      } else {
        // 실패: pending → failed로 변경
        final failedIndex = _comments.indexWhere((c) => c.id == tempId);
        if (failedIndex != -1) {
          _comments[failedIndex] = _comments[failedIndex].copyWith(
            isPending: false,
            isFailed: true,
          );
          notifyListeners();
        }
        debugPrint('[CommentService] 재시도 댓글 전송 실패: ${response.statusCode}');
        // 🎯 throw 하지 않고 바로 return (catch 블록에서 중복 처리 방지)
        return;
      }
    } catch (e) {
      debugPrint('[CommentService] 재시도 댓글 전송 오류 - failed 상태로 변경: $e');

      // 실패 시: pending → failed로 변경 (이미 실패 상태가 아닌 경우에만)
      final failedIndex = _comments.indexWhere((c) => c.id == tempId);
      if (failedIndex != -1) {
        final comment = _comments[failedIndex];
        // 🎯 이미 실패 상태가 아니면 변경 (중복 notifyListeners 방지)
        if (!comment.isFailed) {
          _comments[failedIndex] = comment.copyWith(
            isPending: false,
            isFailed: true,
          );
          notifyListeners();
        }
      }

      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
    }
  }

  /// 실패한 댓글 삭제
  void removeFailedComment(String tempId) {
    _comments.removeWhere((c) => c.id == tempId);
    notifyListeners();
  }

  /// 댓글을 실패 상태로 표시 (즉시 UI 업데이트)
  void markCommentAsFailed(String commentId) {
    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index != -1) {
      final comment = _comments[index];
      // 🎯 이미 실패 상태가 아니면 변경 (즉시 UI 업데이트)
      if (!comment.isFailed) {
        _comments[index] = comment.copyWith(isPending: false, isFailed: true);
        // ✅ 길이가 유지되어도 UI가 최신 Comment 객체를 보도록 정렬 캐시 무효화
        _sortedCacheLength = -1;
        // 🎯 즉시 UI 업데이트 (재시도 버튼 표시)
        notifyListeners();
        debugPrint('[CommentService] 댓글을 실패 상태로 표시 및 UI 업데이트: $commentId');
      }
    }
  }

  /// 댓글에 반응 추가/제거 (API 호출) - 서버가 자동으로 토글 처리
  Future<void> toggleReaction(String commentId, String emoji) async {
    try {
      debugPrint(
        '[CommentService] 반응 토글 요청 - commentId: $commentId, emoji: $emoji',
      );

      // 🎯 임시 댓글 ID 체크 (서버에 저장되지 않은 댓글)
      if (commentId.startsWith('temp_')) {
        debugPrint(
          '[CommentService] ⚠️ 임시 댓글에 대한 반응 추가는 서버 요청 건너뜀: $commentId',
        );
        // 낙관적 업데이트만 수행 (서버 요청 없음)
        final commentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (commentIndex != -1) {
          final comment = _comments[commentIndex];
          final hasThisReaction = comment.myEmotions.containsKey(emoji);
          final previousEmoji = comment.myEmotions.keys.firstOrNull;
          final newMyEmotions =
              hasThisReaction ? <String, String>{} : {emoji: '1'};
          final newEmotionCounts = Map<String, String>.from(
            comment.emotionCounts,
          );

          // 🎯 emotionUsers도 낙관적으로 업데이트
          final newEmotionUsers = Map<String, List<Map<String, dynamic>>>.from(
            comment.emotionUsers,
          );
          final currentUsername = await _getCurrentUsername();

          // 🎯 같은 이모지 제거인지 다른 이모지로 변경인지 먼저 확인
          if (hasThisReaction) {
            // 같은 이모지 제거: 카운트 감소 (낙관적 업데이트에서 바로 -1)
            final currentCount =
                int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
            // 🎯 이미 내가 단 경우 바로 감소 (3→1이 아니라 바로 1로)
            if (currentCount > 0) {
              newEmotionCounts[emoji] = (currentCount - 1).toString();
              if (newEmotionCounts[emoji] == '0') {
                newEmotionCounts.remove(emoji);
              }
            } else {
              newEmotionCounts.remove(emoji);
            }
            // 🎯 emotionUsers에서도 제거
            if (newEmotionUsers.containsKey(emoji) && currentUsername != null) {
              newEmotionUsers[emoji] =
                  newEmotionUsers[emoji]!
                      .where((user) => user['username'] != currentUsername)
                      .toList();
              if (newEmotionUsers[emoji]!.isEmpty) {
                newEmotionUsers.remove(emoji);
              }
            }
          } else {
            // 다른 이모지로 변경: 기존 이모지 제거 + 새 이모지 추가
            if (previousEmoji != null && previousEmoji != emoji) {
              // 기존 이모지 제거
              final oldCount =
                  int.tryParse(newEmotionCounts[previousEmoji] ?? '0') ?? 0;
              if (oldCount > 0) {
                newEmotionCounts[previousEmoji] = (oldCount - 1).toString();
                if (newEmotionCounts[previousEmoji] == '0') {
                  newEmotionCounts.remove(previousEmoji);
                }
              } else {
                newEmotionCounts.remove(previousEmoji);
              }
              // 🎯 emotionUsers에서도 제거
              if (newEmotionUsers.containsKey(previousEmoji) &&
                  currentUsername != null) {
                newEmotionUsers[previousEmoji] =
                    newEmotionUsers[previousEmoji]!
                        .where((user) => user['username'] != currentUsername)
                        .toList();
                if (newEmotionUsers[previousEmoji]!.isEmpty) {
                  newEmotionUsers.remove(previousEmoji);
                }
              }
            }
            // 새 이모지 추가: 카운트 증가
            final currentCount =
                int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
            newEmotionCounts[emoji] = (currentCount + 1).toString();
            // 🎯 emotionUsers에 현재 사용자 추가
            if (currentUsername != null) {
              if (!newEmotionUsers.containsKey(emoji)) {
                newEmotionUsers[emoji] = [];
              }
              // 이미 있는지 확인 후 추가
              final existingUser =
                  newEmotionUsers[emoji]!
                      .where((user) => user['username'] == currentUsername)
                      .firstOrNull;
              if (existingUser == null) {
                newEmotionUsers[emoji]!.add({
                  'username': currentUsername,
                  'profileImageUrl': '', // 프로필 이미지는 서버 응답에서 업데이트
                });
              }
            }
          }

          _comments[commentIndex] = comment.copyWith(
            myEmotions: newMyEmotions,
            emotionCounts: newEmotionCounts,
            emotionUsers: newEmotionUsers,
          );
          // ✅ 길이가 유지되어도 UI가 최신 Comment 객체를 보도록 정렬 캐시 무효화
          _sortedCacheLength = -1;
          notifyListeners();
        }
        return; // 🎯 임시 댓글이면 서버 요청 없이 종료
      }

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

        // 🎯 emotionUsers도 낙관적으로 업데이트
        final newEmotionUsers = Map<String, List<Map<String, dynamic>>>.from(
          comment.emotionUsers,
        );
        final currentUsername = await _getCurrentUsername();

        // 🎯 같은 이모지 제거인지 다른 이모지로 변경인지 먼저 확인
        if (hasThisReaction) {
          // 같은 이모지 제거: 카운트 감소 (낙관적 업데이트에서 바로 -1)
          final currentCount =
              int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
          // 🎯 이미 내가 단 경우 바로 감소 (3→1이 아니라 바로 1로)
          if (currentCount > 0) {
            newEmotionCounts[emoji] = (currentCount - 1).toString();
            if (newEmotionCounts[emoji] == '0') {
              newEmotionCounts.remove(emoji);
            }
          } else {
            newEmotionCounts.remove(emoji);
          }
          // 🎯 emotionUsers에서도 제거
          if (newEmotionUsers.containsKey(emoji) && currentUsername != null) {
            newEmotionUsers[emoji] =
                newEmotionUsers[emoji]!
                    .where((user) => user['username'] != currentUsername)
                    .toList();
            if (newEmotionUsers[emoji]!.isEmpty) {
              newEmotionUsers.remove(emoji);
            }
          }
        } else {
          // 다른 이모지로 변경: 기존 이모지 제거 + 새 이모지 추가
          if (previousEmoji != null && previousEmoji != emoji) {
            // 기존 이모지 제거
            final oldCount =
                int.tryParse(newEmotionCounts[previousEmoji] ?? '0') ?? 0;
            if (oldCount > 0) {
              newEmotionCounts[previousEmoji] = (oldCount - 1).toString();
              if (newEmotionCounts[previousEmoji] == '0') {
                newEmotionCounts.remove(previousEmoji);
              }
            } else {
              newEmotionCounts.remove(previousEmoji);
            }
            // 🎯 emotionUsers에서도 제거
            if (newEmotionUsers.containsKey(previousEmoji) &&
                currentUsername != null) {
              newEmotionUsers[previousEmoji] =
                  newEmotionUsers[previousEmoji]!
                      .where((user) => user['username'] != currentUsername)
                      .toList();
              if (newEmotionUsers[previousEmoji]!.isEmpty) {
                newEmotionUsers.remove(previousEmoji);
              }
            }
          }
          // 새 이모지 추가: 카운트 증가
          final currentCount =
              int.tryParse(newEmotionCounts[emoji] ?? '0') ?? 0;
          newEmotionCounts[emoji] = (currentCount + 1).toString();
          // 🎯 emotionUsers에 현재 사용자 추가
          if (currentUsername != null) {
            if (!newEmotionUsers.containsKey(emoji)) {
              newEmotionUsers[emoji] = [];
            }
            // 이미 있는지 확인 후 추가
            final existingUser =
                newEmotionUsers[emoji]!
                    .where((user) => user['username'] == currentUsername)
                    .firstOrNull;
            if (existingUser == null) {
              newEmotionUsers[emoji]!.add({
                'username': currentUsername,
                'profileImageUrl': '', // 프로필 이미지는 서버 응답에서 업데이트
              });
            }
          }
        }

        _comments[commentIndex] = comment.copyWith(
          myEmotions: newMyEmotions,
          emotionCounts: newEmotionCounts,
          emotionUsers: newEmotionUsers,
        );
        // ✅ 길이가 유지되어도 UI가 최신 Comment 객체를 보도록 정렬 캐시 무효화
        _sortedCacheLength = -1;

        // 🎯 즉시 UI 업데이트 (낙관적 업데이트)
        notifyListeners();
      }

      // 2️⃣ 서버 요청 (항상 POST - 서버가 알아서 토글 처리)
      await _addReactionToServer(commentId, emoji);

      // 3️⃣ WebSocket으로 정확한 상태 받아서 최종 동기화 (중복은 핸들러에서 방지)
      debugPrint('[CommentService] 반응 토글 요청 완료 (WebSocket 대기 중)');
    } catch (e) {
      debugPrint('[CommentService] 반응 토글 오류: $e');
      // 🎯 에러 발생 시에도 UI는 이미 업데이트되었으므로 rethrow하지 않음
      // rethrow;
    }
  }

  /// 서버에 반응 추가 (서버가 알아서 토글 처리)
  Future<void> _addReactionToServer(String commentId, String emoji) async {
    final response = await _dio.post(
      '/api/comments/$commentId/emotions?emoji=${Uri.encodeComponent(emoji)}',
      options: Options(receiveTimeout: const Duration(seconds: 5)),
    );

    debugPrint(
      '[CommentService] 반응 토글 응답: ${response.statusCode} - ${response.data}',
    );

    // 🎯 서버 응답으로 댓글 업데이트 (emotionUsers 포함)
    if (response.statusCode == 200 && response.data != null) {
      try {
        // 🎯 비밀댓글 권한 체크
        final responseData =
            response.data is Map<String, dynamic>
                ? Map<String, dynamic>.from(response.data)
                : <String, dynamic>{};
        final originalContent = responseData['content']?.toString() ?? '';
        final checkedContent = await _checkPrivateCommentAccess(
          responseData,
          originalContent,
        );
        responseData['content'] = checkedContent;
        final updatedComment = Comment.fromJson(responseData);
        final commentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (commentIndex != -1) {
          _comments[commentIndex] = updatedComment;
          notifyListeners();
          debugPrint('[CommentService] ✅ 댓글 반응 업데이트 완료 (emotionUsers 포함)');
        }
      } catch (e) {
        debugPrint('[CommentService] ⚠️ 서버 응답 파싱 오류: $e');
      }
    }
  }

  /// 댓글 삭제 (낙관적 업데이트)
  Future<void> deleteComment(String commentId) async {
    // 1️⃣ 낙관적 업데이트 (즉시 UI 반영)
    final commentIndex = _comments.indexWhere((c) => c.id == commentId);
    if (commentIndex == -1) {
      debugPrint('[CommentService] ⚠️ 삭제할 댓글을 찾을 수 없음: $commentId');
      return;
    }

    final deletedComment = _comments[commentIndex]; // 롤백용 백업
    final deletedImageUrl = deletedComment.imageUrl; // 🎯 삭제할 이미지 URL

    _comments.removeAt(commentIndex);
    _serverCommentCount--; // 🎯 전체 댓글 수 감소

    // 삭제는 스크롤 안 함

    notifyListeners(); // ⚡ UI 즉시 업데이트

    debugPrint('[CommentService] 낙관적 댓글 삭제: $commentId');

    // 🎯 이미지가 있으면 R2에서 비동기로 삭제 (낙관적 UI 삭제 후)
    if (deletedImageUrl != null &&
        deletedImageUrl.isNotEmpty &&
        !deletedImageUrl.startsWith('pending://')) {
      _deleteImageFromR2(deletedImageUrl);
    }

    // 2️⃣ 서버에 요청 전송 (백그라운드)
    try {
      final response = await _dio.delete(
        '/api/comments/$commentId',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );

      debugPrint('[CommentService] 댓글 삭제 응답: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[CommentService] ✅ 댓글 삭제 성공 (WebSocket으로 최종 검증 대기)');
        // 3️⃣ WebSocket이 최종 검증 데이터를 보내줄 것임
      } else {
        debugPrint('[CommentService] ⚠️ 댓글 삭제 실패: ${response.statusCode}');
        // 실패 시 복원
        _comments.insert(commentIndex, deletedComment);

        notifyListeners();

        throw HttpException('댓글 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[CommentService] 댓글 삭제 오류 - 복원: $e');

      // 4️⃣ 실패 시 복원
      if (_comments.indexWhere((c) => c.id == commentId) == -1) {
        _comments.insert(commentIndex, deletedComment);

        notifyListeners();
      }

      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 댓글 수정 (낙관적 업데이트)
  Future<void> updateComment(String commentId, String newContent) async {
    // 1️⃣ 낙관적 업데이트 (즉시 UI 반영)
    final commentIndex = _comments.indexWhere((c) => c.id == commentId);
    if (commentIndex == -1) {
      debugPrint('[CommentService] ⚠️ 수정할 댓글을 찾을 수 없음: $commentId');
      return;
    }

    final originalComment = _comments[commentIndex];
    _comments[commentIndex] = originalComment.copyWith(
      content: newContent,
      updatedAt: DateTime.now().toIso8601String(),
    );

    // 수정은 스크롤 안 함

    notifyListeners(); // ⚡ UI 즉시 업데이트

    debugPrint('[CommentService] 낙관적 댓글 수정: $commentId');

    // 2️⃣ 서버에 요청 전송 (백그라운드)
    try {
      // 🎯 댓글 수정 API 명세서에 따른 요청 Body
      final requestData = {
        'content': newContent,
        'postId': int.tryParse(originalComment.postId) ?? 0,
        // 명세서: content, postId만 필요 (parentId, imageUrl, visibility는 선택사항)
      };
      debugPrint('[CommentService] 댓글 수정 요청 데이터: $requestData');

      final response = await _dio.put(
        '/api/comments/$commentId',
        data: requestData,
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );

      debugPrint(
        '[CommentService] 댓글 수정 응답: ${response.statusCode} - ${response.data}',
      );

      if (response.statusCode == 200) {
        debugPrint('[CommentService] ✅ 댓글 수정 성공 (WebSocket으로 최종 검증 대기)');
        // 3️⃣ WebSocket이 최종 검증 데이터를 보내줄 것임
      } else {
        debugPrint('[CommentService] ⚠️ 댓글 수정 실패: ${response.statusCode}');
        // 실패 시 원래 내용으로 롤백
        final currentIndex = _comments.indexWhere((c) => c.id == commentId);
        if (currentIndex != -1) {
          _comments[currentIndex] = originalComment;

          notifyListeners();
        }
        throw HttpException('댓글 수정 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[CommentService] 댓글 수정 오류 - 롤백: $e');

      // 4️⃣ 실패 시 원래 내용으로 롤백
      final currentIndex = _comments.indexWhere((c) => c.id == commentId);
      if (currentIndex != -1) {
        _comments[currentIndex] = originalComment;

        notifyListeners();
      }

      if (e is DioException) {
        debugPrint(
          '[CommentService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 🎯 R2에서 이미지 비동기 삭제 (댓글 삭제 시)
  Future<void> _deleteImageFromR2(String imageUrl) async {
    try {
      // 🎯 R2UploadService를 통해 URL 기반 삭제
      final r2Service = R2UploadService();
      await r2Service.deleteFileFromR2ByUrl(imageUrl);
      debugPrint('[CommentService] ✅ R2 이미지 삭제 완료: $imageUrl');
    } catch (e) {
      debugPrint('[CommentService] R2 이미지 삭제 오류: $e');
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

/// 🎯 Comment Locate API 응답 DTO
class CommentLocateResponse {
  final String commentId;
  final String postId;
  final String anchorParentCommentId;
  final String? anchorParentCreatedAt;
  final bool isReply;
  final String? parentId;
  final int rank;
  final int page;
  final int indexInPage;
  final int size;
  final String direction;

  const CommentLocateResponse({
    required this.commentId,
    required this.postId,
    required this.anchorParentCommentId,
    required this.anchorParentCreatedAt,
    required this.isReply,
    required this.parentId,
    required this.rank,
    required this.page,
    required this.indexInPage,
    required this.size,
    required this.direction,
  });

  factory CommentLocateResponse.fromJson(Map<String, dynamic> json) {
    return CommentLocateResponse(
      commentId: json['commentId']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      anchorParentCommentId: json['anchorParentCommentId']?.toString() ?? '',
      anchorParentCreatedAt: json['anchorParentCreatedAt']?.toString(),
      isReply: json['isReply'] == true,
      parentId: json['parentId']?.toString(),
      rank: int.tryParse(json['rank']?.toString() ?? '') ?? 0,
      page: int.tryParse(json['page']?.toString() ?? '') ?? 0,
      indexInPage: int.tryParse(json['indexInPage']?.toString() ?? '') ?? 0,
      size:
          int.tryParse(json['size']?.toString() ?? '') ??
          CommentService.defaultPageSize,
      direction: json['direction']?.toString() ?? 'DESC',
    );
  }
}
