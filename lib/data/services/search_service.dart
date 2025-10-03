import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 검색 관련 비즈니스 로직을 담당하는 서비스
class SearchService extends ChangeNotifier {
  static final SearchService _instance = SearchService._internal();
  factory SearchService() => _instance;
  SearchService._internal();

  final AuthService _authService = AuthService();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (code) => true,
      receiveDataWhenStatusError: true,
    ),
  );

  // UI 상태 관리
  String _query = '';
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  String _selectedCategory = '추천'; // '추천', '계정'
  bool _isSearching = false; // 검색 중인지 여부
  bool _isFocused = false; // 검색창 포커스 여부
  bool _viewLocked = false; // 화면 전환 잠금 (네비게이션 중 레이아웃 고정)
  // 블로그 제목 검색 단발 결과 보관
  List<SearchContentItem> _blogResults = [];

  // 통합 컨텐츠 데이터
  List<SearchContentItem> _filteredItems = [];
  List<SearchContentItem> _allItems = [];
  // 최근 검색 결과(탭 전환용): 계정/블로그 각각 보관
  List<SearchContentItem> _lastAccountResults = [];
  List<SearchContentItem> _lastBlogResults = [];

  // 검색 최적화
  String _lastAccountQuery = '';
  int _lastAccountCount = -1;

  // 검색 기록 (사용자 객체 기반)
  List<_SearchHistoryEntry> _searchHistory = [];
  static const int _maxHistorySize = 10;
  static const String _searchHistoryKey = 'search_history';

  // 통합 컨텐츠 데이터 초기화
  late final List<SearchContentItem> _allContentItems = [];
  int _currentPage = 0;
  bool _hasMorePosts = true;
  bool isLoadingMore = false;

  // 최근 본 컨텐츠 관리
  final Set<String> _recentlyViewedIds = {};

  // 실제 포스트 데이터 저장
  final Map<String, Map<String, dynamic>> _postData = {};

  // Getters
  String get query => _query;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  bool get isSearching => _isSearching;
  bool get isFocused => _isFocused;
  bool get isViewLocked => _viewLocked;
  bool get hasSearched => _query.isNotEmpty && !_isSearching;
  List<SearchContentItem> get contentItems {
    if (!hasSearched) {
      // 검색 전에는 추천 컨텐츠(포스트)만 노출
      return _allItems.where((item) => !item.isAccount).toList();
    }

    // 검색 완료 후에는 선택된 카테고리에 따라 필터링
    if (_selectedCategory == '계정') {
      return _filteredItems.where((item) => item.isAccount).toList();
    } else if (_selectedCategory == '추천') {
      return _filteredItems.where((item) => !item.isAccount).toList();
    } else {
      return _filteredItems;
    }
  }

  // 검색 중일 때 계정 리스트 (프로필 형태)
  List<SearchContentItem> get searchingAccounts {
    final seen = <String>{};
    final uniques = <SearchContentItem>[];
    for (final item in _filteredItems) {
      if (!item.isAccount) continue;
      final u = item.username ?? '';
      if (u.isEmpty) continue;
      if (seen.add(u)) uniques.add(item);
    }
    return uniques;
  }

  // 블로그 제목 검색 결과 (단발)
  List<SearchContentItem> get blogResults => _blogResults;

  // 검색 기록 (계정 리스트 형태)
  List<SearchContentItem> get searchHistory => searchHistoryAsAccounts;

  // 검색 기록을 계정 형태로 변환
  List<SearchContentItem> get searchHistoryAsAccounts {
    final seen = <String>{};
    final result = <SearchContentItem>[];
    for (final e in _searchHistory) {
      if (seen.add(e.username)) {
        result.add(
          SearchContentItem.account(
            id: 'history_${e.username}',
            username: e.username,
            alias: e.title?.isNotEmpty == true ? e.title! : e.username,
            profileImageUrl: e.imageUrl ?? '',
            followers: 0,
          ),
        );
      }
    }
    return result;
  }

  // ---- 공통 로깅 유틸
  static String _maskToken(String token) {
    if (token.isEmpty) return '(empty)';
    final n = token.length;
    final tail = token.substring(n - (n >= 6 ? 6 : n));
    return '***$tail';
  }

  static String _prettyJson(dynamic data) {
    try {
      if (data is String) {
        final obj = json.decode(data);
        return const JsonEncoder.withIndent('  ').convert(obj);
      }
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data?.toString() ?? '';
    }
  }

  static String _trimLong(String s, {int max = 3000}) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '…(truncated)';
  }

  // ---- 사용자 검색
  Future<FriendSearchResult> searchUsers({
    required String query,
    CancelToken? cancelToken,
  }) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/friends/search';
    final sw = Stopwatch()..start();

    debugPrint('┌─[REQ] GET $uri?username=$query');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    final res = await _dio.get(
      uri,
      queryParameters: {'username': query},
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.json,
      ),
    );
    sw.stop();

    final status = res.statusCode;
    final body = res.data;
    final uriFinal = res.requestOptions.uri;
    final headers = res.headers.map.map((k, v) => MapEntry(k, v));

    debugPrint('┌─[RES] ${res.requestOptions.method} $uriFinal');
    debugPrint('│ status: $status');
    debugPrint('│ headers: ${_trimLong(headers.toString())}');
    debugPrint('│ body: ${_trimLong(_prettyJson(body))}');
    debugPrint('│ elapsed: ${sw.elapsedMilliseconds}ms');
    debugPrint('└────────────────────────────────');

    String? pickMessage(dynamic b) {
      try {
        if (b is Map<String, dynamic>) {
          return (b['message'] ?? b['error'] ?? b['detail'] ?? b['msg'])
              ?.toString();
        }
        if (b is String) return b;
      } catch (_) {}
      return null;
    }

    final usernames = <String>[];
    if (status == 200) {
      if (body is List) {
        for (final e in body) {
          if (e is Map<String, dynamic>) {
            final u = e['username']?.toString();
            if (u != null && u.isNotEmpty) usernames.add(u);
          }
        }
      } else {
        debugPrint('[-] WARN: 200인데 body가 List가 아님: ${body.runtimeType}');
      }
    }

    return FriendSearchResult(
      status: status,
      usernames: usernames,
      body: body,
      headers: headers,
      uri: uriFinal,
      elapsed: sw.elapsed,
      serverMessage: pickMessage(body),
    );
  }

  // ---- 사용자 정보 조회
  Future<UserDto?> getUserByUsername({
    required String username,
    CancelToken? cancelToken,
  }) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/auth/users/$username';
    final sw = Stopwatch()..start();

    debugPrint('┌─[REQ] GET $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    final res = await _dio.get(
      uri,
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.json,
      ),
    );
    sw.stop();

    final status = res.statusCode;
    final body = res.data;
    final uriFinal = res.requestOptions.uri;

    debugPrint('┌─[RES] ${res.requestOptions.method} $uriFinal');
    debugPrint('│ status: $status');
    debugPrint('│ body: ${_trimLong(_prettyJson(body))}');
    debugPrint('│ elapsed: ${sw.elapsedMilliseconds}ms');
    debugPrint('└────────────────────────────────');

    if (status == 200 && body is Map<String, dynamic>) {
      try {
        return UserDto(
          id: (body['id'] as num).toInt(),
          username: body['username']?.toString() ?? '',
          role: body['role']?.toString() ?? '',
        );
      } catch (e) {
        debugPrint('[-] parse error: $e');
        return null;
      }
    }

    debugPrint('[-] getUserByUsername failed | code=$status');
    return null;
  }

  // ---- 친구 신청
  Future<Response> requestFriend({required String targetUsername}) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/friends/request';
    debugPrint('┌─[REQ] POST $uri | body={"targetUsername":"$targetUsername"}');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    return _dio.post(
      uri,
      data: {'targetUsername': targetUsername},
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  // ---- 친구 수락
  Future<Response> acceptFriend({required String requesterUsername}) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/friends/accept/$requesterUsername';
    debugPrint('┌─[REQ] POST $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    return _dio.post(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ---- 친구 거절
  Future<Response> rejectFriend({required String requesterUsername}) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/friends/reject/$requesterUsername';
    debugPrint('┌─[REQ] POST $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    return _dio.post(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ---- 친구 차단
  Future<Response> blockUser({required String targetUsername}) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/friends/block/$targetUsername';
    debugPrint('┌─[REQ] POST $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    return _dio.post(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ---- 친구 삭제
  Future<Response> deleteFriend({required String targetUsername}) async {
    final baseUrl = ApiServiceBase.baseUrl;
    final token = await _getAuthToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인이 필요합니다(토큰 없음).');
    }

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (!jwtLike.hasMatch(token)) {
      throw Exception('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
    }

    final uri = '$baseUrl/api/friends/delete/$targetUsername';
    debugPrint('┌─[REQ] DELETE $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    return _dio.delete(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<String?> _getAuthToken() async {
    try {
      final t = await _authService.getToken();
      final trimmed = t?.trim();
      debugPrint('[AuthService] token(raw)="${trimmed ?? 'null'}"');
      return trimmed;
    } catch (e) {
      debugPrint('[AuthService] getToken failed: $e');
      return null;
    }
  }

  // ---- UI 로직 메서드들 ----

  /// 초기화
  Future<void> initialize() async {
    _allContentItems.clear();
    _currentPage = 0;
    _hasMorePosts = true;
    await _loadSearchHistory();
    await loadRecommendations();
    notifyListeners();
  }

  /// 추천 게시글 새로고침
  Future<void> refreshRecommendations() async {
    _allContentItems.clear();
    _currentPage = 0;
    _hasMorePosts = true;
    await loadRecommendations();
  }

  /// 최근 본 컨텐츠에 추가
  void addToRecentlyViewed(String id) {
    _recentlyViewedIds.add(id);
    notifyListeners();
  }

  /// 최근 본 컨텐츠인지 확인
  bool isRecentlyViewed(String id) {
    return _recentlyViewedIds.contains(id);
  }

  /// 포스트 데이터 가져오기
  Map<String, dynamic>? getPostData(String id) {
    return _postData[id];
  }

  /// 추천 게시글 불러오기
  Future<void> loadRecommendations() async {
    if (isLoadingMore || !_hasMorePosts) return;

    try {
      isLoadingMore = true;
      final baseUrl = ApiServiceBase.baseUrl;
      final token = await _getAuthToken();

      if (token == null || token.isEmpty) {
        throw Exception('로그인이 필요합니다(토큰 없음).');
      }

      final uri =
          '$baseUrl/api/posts/recommendation?page=$_currentPage&size=10';
      final res = await _dio.get(
        uri,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
      );

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data;
        final posts =
            (data['content'] as List? ?? []).map((post) {
              final id = post['id']?.toString() ?? '';
              final title = post['title']?.toString() ?? '';
              final author = post['author']?.toString() ?? '';
              final imageUrl = post['thumbnailImageUrl']?.toString() ?? '';
              final likes = (post['likeCount'] as num?)?.toInt() ?? 0;
              final comments = (post['commentCount'] as num?)?.toInt() ?? 0;
              final content = post['content']?.toString() ?? '';

              // PostData의 parsedContent getter를 활용
              final tempPostData = PostData.fromServer(post);
              final parsedContent = tempPostData.parsedContent;
              debugPrint(
                '[loadRecommendations] parsedContent: "$parsedContent"',
              );

              // 실제 포스트 데이터 저장
              _postData[id] = post;

              return SearchContentItem.post(
                id: id,
                title: title,
                author: author,
                imageUrl: imageUrl,
                likes: likes,
                comments: comments,
                content: content,
                parsedContent: parsedContent,
              );
            }).toList();

        if (posts.isEmpty) {
          _hasMorePosts = false;
        } else {
          _allContentItems.addAll(posts);
          _currentPage++;
        }

        _allItems = List.from(_allContentItems);
        _filteredItems = List.from(_allContentItems);
        _selectedCategory = '추천';
      }
    } catch (e) {
      debugPrint('[SearchService] Failed to load recommendations: $e');
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  /// 검색어 변경
  void onSearchChanged(String q) {
    debugPrint('[Search] onSearchChanged: $q');
    _query = q;
    _debounce?.cancel();

    if (q.isEmpty) {
      _filteredItems = List.from(_allContentItems);
      _selectedCategory = '추천';
      _isSearching = false;
    } else {
      // 포커스 여부와 관계없이 실시간 검색
      _isSearching = true;
      _performRealTimeSearch(q);
    }

    notifyListeners();
  }

  /// 실시간 검색 (계정만)
  Future<void> _performRealTimeSearch(String q) async {
    if (q.isEmpty) {
      _filteredItems = [];
      _lastAccountQuery = '';
      _lastAccountCount = -1;
      notifyListeners();
      return;
    }

    // 이전 검색 쿼리가 현재 쿼리의 접두사이고 결과가 0-1개면 요청하지 않음
    if (_lastAccountQuery.isNotEmpty &&
        q.startsWith(_lastAccountQuery) &&
        _lastAccountCount <= 1) {
      debugPrint(
        '[RealTime] skip - query "$q" starts with "$_lastAccountQuery" with ${_lastAccountCount} results',
      );
      return;
    }

    // 사용자가 텍스트를 삭제한 경우 (현재 쿼리가 이전 쿼리보다 짧음)
    if (_lastAccountQuery.isNotEmpty && q.length < _lastAccountQuery.length) {
      debugPrint(
        '[RealTime] reset - query "$q" is shorter than "$_lastAccountQuery", allowing new search',
      );
      _lastAccountQuery = '';
      _lastAccountCount = -1;
    }

    try {
      // 실제 서버에 계정 검색 요청
      final res = await searchUsers(query: q);
      List<SearchContentItem> accountResults = [];

      if (res.ok) {
        if (res.body is List) {
          final list = res.body as List;
          accountResults =
              list.map((e) {
                if (e is Map<String, dynamic>) {
                  final username = e['username']?.toString() ?? '';
                  final alias =
                      (e['alias']?.toString() ?? '').isNotEmpty
                          ? e['alias'].toString()
                          : username;
                  final imageUrl = e['profileImageUrl']?.toString() ?? '';
                  return SearchContentItem.account(
                    id: 'remote_$username',
                    username: username,
                    alias: alias,
                    profileImageUrl: imageUrl,
                    followers: 0,
                  );
                } else {
                  final u = e?.toString() ?? '';
                  return SearchContentItem.account(
                    id: 'remote_$u',
                    username: u,
                    alias: u,
                    profileImageUrl: '',
                    followers: 0,
                  );
                }
              }).toList();
        } else {
          // fallback: usernames만 있는 경우
          accountResults =
              res.usernames
                  .map(
                    (username) => SearchContentItem.account(
                      id: 'remote_$username',
                      username: username,
                      alias: username,
                      profileImageUrl: '',
                      followers: 0,
                    ),
                  )
                  .toList();
        }
      }

      _filteredItems = accountResults;
      _lastAccountResults = accountResults;
      _lastAccountQuery = q;
      _lastAccountCount = accountResults.length;

      debugPrint(
        '[RealTime] found ${accountResults.length} accounts from server',
      );
    } catch (e) {
      debugPrint('[RealTime] error: $e');
      _filteredItems = [];
      _lastAccountQuery = q;
      _lastAccountCount = 0;
    }

    notifyListeners();
  }

  /// 제목으로 블로그 단발 검색 (검색 버튼/엔터 콜백에서 호출)
  Future<void> searchBlogsByTitleOnce({
    required String keyword,
    int page = 0,
    int size = 10,
  }) async {
    if (keyword.isEmpty) return;
    try {
      final baseUrl = ApiServiceBase.baseUrl;
      final token = await _getAuthToken();
      if (token == null || token.isEmpty) {
        throw Exception('로그인이 필요합니다(토큰 없음).');
      }

      final uri = '$baseUrl/api/posts/search';
      final res = await _dio.get(
        uri,
        queryParameters: {'keyword': keyword, 'page': page, 'size': size},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
      );

      final List<SearchContentItem> posts = [];
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final content = (res.data['content'] as List?) ?? [];
        for (final e in content) {
          if (e is Map<String, dynamic>) {
            final id = e['id']?.toString() ?? '';
            final title = e['title']?.toString() ?? '';
            final author = e['author']?.toString() ?? '';
            final imageUrl = e['thumbnailImageUrl']?.toString() ?? '';
            final likes = (e['likeCount'] as num?)?.toInt() ?? 0;
            final comments = (e['commentCount'] as num?)?.toInt() ?? 0;
            final content = e['content']?.toString() ?? '';

            // PostData의 parsedContent getter를 활용
            final tempPostData = PostData.fromServer(e);
            final parsedContent = tempPostData.parsedContent;

            _postData[id] = e;
            posts.add(
              SearchContentItem.post(
                id: id,
                title: title,
                author: author,
                imageUrl: imageUrl,
                likes: likes,
                comments: comments,
                content: content,
                parsedContent: parsedContent,
              ),
            );
          }
        }
      }

      _blogResults = posts;
      notifyListeners();
    } catch (e) {
      debugPrint('[searchBlogsByTitleOnce] error: $e');
    }
  }

  /// 계정을 검색 기록에 추가 (객체 기반)
  void addHistoryFromAccount(SearchContentItem account) {
    if (!account.isAccount || (account.username?.isNotEmpty != true)) return;

    final entry = _SearchHistoryEntry(
      username: account.username!,
      title: account.alias ?? account.username!,
      imageUrl: account.profileImageUrl,
    );

    // 중복 제거 (username 기준)
    _searchHistory.removeWhere((e) => e.username == entry.username);

    // 맨 앞에 추가
    _searchHistory.insert(0, entry);

    // 최대 개수 제한
    if (_searchHistory.length > _maxHistorySize) {
      _searchHistory = _searchHistory.take(_maxHistorySize).toList();
    }

    _saveSearchHistory();
    notifyListeners();

    debugPrint(
      '[SearchHistory] added(username=${entry.username}) total=${_searchHistory.length}',
    );
  }

  /// 검색 기록에서 제거
  void removeFromSearchHistory(String username) {
    _searchHistory.removeWhere((e) => e.username == username);
    _saveSearchHistory();
    notifyListeners();
    debugPrint(
      '[SearchHistory] removed: $username, total: ${_searchHistory.length}',
    );
  }

  /// 검색 기록 전체 삭제
  void clearSearchHistory() {
    _searchHistory.clear();
    _saveSearchHistory();
    notifyListeners();
    debugPrint('[SearchHistory] cleared');
  }

  /// 검색 기록 불러오기
  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_searchHistoryKey);

      if (historyJson != null) {
        final List<dynamic> historyList = jsonDecode(historyJson);
        final loaded =
            historyList
                .whereType<Map<String, dynamic>>()
                .map((m) => _SearchHistoryEntry.fromJson(m))
                .toList();
        // username 기준 최신 우선 중복 제거
        final seen = <String>{};
        _searchHistory = [];
        for (final e in loaded) {
          final u = e.username;
          if (u.isEmpty) continue;
          if (!seen.contains(u)) {
            _searchHistory.add(e);
            seen.add(u);
          }
        }
        debugPrint(
          '[SearchHistory] loaded(objects): ${_searchHistory.length} items',
        );
      } else {
        _searchHistory = [];
        debugPrint('[SearchHistory] no saved history found');
      }
    } catch (e) {
      debugPrint('[SearchHistory] load error: $e');
      _searchHistory = [];
    }
  }

  /// 검색 기록 저장하기
  Future<void> _saveSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(
        _searchHistory.map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_searchHistoryKey, historyJson);
      debugPrint('[SearchHistory] saved: ${_searchHistory.length} items');
    } catch (e) {
      debugPrint('[SearchHistory] save error: $e');
    }
  }

  /// 검색어 지우기
  void clearSearch() {
    debugPrint('[Search] clear');
    _query = '';
    _filteredItems = List.from(_allContentItems);
    _isFocused = false;
    _isSearching = false;
    _selectedCategory = '추천';
    _lastAccountQuery = '';
    _lastAccountCount = -1;
    notifyListeners();
  }

  /// 초기화 (뒤로가기)
  void resetToInitial() {
    _query = '';
    _filteredItems = List.from(_allContentItems);
    _isFocused = false;
    _isSearching = false;
    _selectedCategory = '추천';
    _isLoading = false;
    _error = null;
    _debounce?.cancel();
    _lastAccountQuery = '';
    _lastAccountCount = -1;
    notifyListeners();
  }

  /// 카테고리 변경
  void changeCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
    debugPrint('[Category] changed to: $category');
    debugPrint('[Category] hasSearched: $hasSearched');
    debugPrint('[Category] filteredItems count: ${_filteredItems.length}');
    debugPrint('[Category] contentItems count: ${contentItems.length}');
  }

  /// 컨텐츠 아이템 탭
  void onTapContentItem(
    SearchContentItem item, {
    Function(String)? onNavigateToProfile,
  }) {
    if (item.isAccount) {
      // 계정 액션 - 검색 기록에 추가
      debugPrint('[Tap] Account: ${item.username}');
      addHistoryFromAccount(item);

      // 프로필로 네비게이션
      if (onNavigateToProfile != null) {
        onNavigateToProfile(item.username!);
      }
    } else {
      // 게시글 액션
      debugPrint('[Tap] Post: ${item.title}');
    }
  }

  /// 친구 액션 실행
  Future<bool> executeFriendAction({
    required String actionName,
    required Future<Response> Function() run,
  }) async {
    try {
      final res = await run();
      final code = res.statusCode ?? -1;
      debugPrint('[Friend:$actionName] code=$code');

      if (code >= 200 && code < 300) {
        return true;
      } else {
        return false;
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      debugPrint('[Friend:$actionName][DIO] code=$code');
      return false;
    } catch (e) {
      debugPrint('[Friend:$actionName][UNEXPECTED] $e');
      return false;
    }
  }

  /// 포커스 상태 업데이트
  void setFocused(bool v) {
    if (_viewLocked) return; // 잠금 중에는 포커스 변화 무시
    if (_isFocused == v) return;
    _isFocused = v;
    notifyListeners();
  }

  void lockView() {
    if (_viewLocked) return;
    _viewLocked = true;
    notifyListeners();
  }

  void unlockView() {
    if (!_viewLocked) return;
    _viewLocked = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// 데이터 모델들
class SearchContentItem {
  final String id;
  final bool isAccount;

  // 계정 관련 필드
  final String? username;
  final String? profileImageUrl;
  final String? alias;
  final int? followers;

  // 게시글 관련 필드
  final String? title;
  final String? author;
  final String? imageUrl;
  final int? likes;
  final int? comments;
  final String? content;
  final String? parsedContent;

  const SearchContentItem._({
    required this.id,
    required this.isAccount,
    this.username,
    this.profileImageUrl,
    this.alias,
    this.followers,
    this.title,
    this.author,
    this.imageUrl,
    this.likes,
    this.comments,
    this.content,
    this.parsedContent,
  });

  factory SearchContentItem.account({
    required String id,
    required String username,
    required String alias,
    required String profileImageUrl,
    required int followers,
  }) {
    return SearchContentItem._(
      id: id,
      isAccount: true,
      username: username,
      profileImageUrl: profileImageUrl,
      alias: alias,
      followers: followers,
    );
  }

  factory SearchContentItem.post({
    required String id,
    required String title,
    required String author,
    required String imageUrl,
    required int likes,
    required int comments,
    String? content,
    String? parsedContent,
  }) {
    return SearchContentItem._(
      id: id,
      isAccount: false,
      title: title,
      author: author,
      imageUrl: imageUrl,
      likes: likes,
      comments: comments,
      content: content,
      parsedContent: parsedContent,
    );
  }
}

class AccountItem {
  final String nickname;
  final String userId;
  final int neighbors;
  const AccountItem({
    required this.nickname,
    required this.userId,
    required this.neighbors,
  });
}

class PostItemData {
  final String title;
  final String author;
  final String preview;
  final String imageUrl;
  final int likes;
  const PostItemData({
    required this.title,
    required this.author,
    required this.preview,
    required this.imageUrl,
    required this.likes,
  });
}

class UserDto {
  final int id;
  final String username;
  final String role;
  const UserDto({required this.id, required this.username, required this.role});
}

class FriendSearchResult {
  final int? status;
  final List<String> usernames;
  final dynamic body;
  final Map<String, List<String>> headers;
  final Uri uri;
  final Duration elapsed;
  final String? serverMessage;
  bool get ok => status != null && status! >= 200 && status! < 300;
  const FriendSearchResult({
    required this.status,
    required this.usernames,
    required this.body,
    required this.headers,
    required this.uri,
    required this.elapsed,
    required this.serverMessage,
  });
}

class _SearchHistoryEntry {
  final String username;
  final String? title; // alias 또는 표시명
  final String? imageUrl;

  _SearchHistoryEntry({required this.username, this.title, this.imageUrl});

  factory _SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return _SearchHistoryEntry(
      username: json['username']?.toString() ?? '',
      title: json['title']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'title': title,
    'imageUrl': imageUrl,
  };
}
