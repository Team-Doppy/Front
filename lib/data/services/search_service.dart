import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
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

  // 통합 컨텐츠 데이터
  List<SearchContentItem> _filteredItems = [];
  List<SearchContentItem> _allItems = [];

  // 검색 최적화
  String _lastAccountQuery = '';
  int _lastAccountCount = -1;

  // 검색 기록
  List<String> _searchHistory = [];
  static const int _maxHistorySize = 10;
  static const String _searchHistoryKey = 'search_history';

  // 통합 컨텐츠 데이터 초기화
  late final List<SearchContentItem> _allContentItems = [];

  // Getters
  String get query => _query;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCategory => _selectedCategory;
  bool get isSearching => _isSearching;
  bool get isFocused => _isFocused;
  bool get hasSearched => _query.isNotEmpty && !_isSearching;
  List<SearchContentItem> get contentItems {
    if (!hasSearched) {
      // 검색 전에는 계정만 표시
      return _allItems.where((item) => item.isAccount).toList();
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
    return _filteredItems.where((item) => item.isAccount).toList();
  }

  // 검색 기록
  List<String> get searchHistory => _searchHistory;

  // 검색 기록을 계정 형태로 변환
  List<SearchContentItem> get searchHistoryAsAccounts {
    return _searchHistory
        .map(
          (query) => SearchContentItem.account(
            id: 'history_$query',
            username: query,
            alias: query,
            profileImageUrl: '',
            followers: 0,
          ),
        )
        .toList();
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
    _allItems = List.from(_allContentItems);
    _filteredItems = List.from(_allContentItems);
    _selectedCategory = '추천';
    await _loadSearchHistory();
    notifyListeners();
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

  // (사용 중지) 전체 컨텐츠 검색은 현재 비활성화

  /// 통합 컨텐츠 검색
  Future<void> _searchContent(String q) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 원격 계정 검색
      final res = await searchUsers(query: q);
      List<SearchContentItem> remoteAccounts = [];

      if (res.ok) {
        if (res.body is List) {
          final list = res.body as List;
          remoteAccounts =
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
          remoteAccounts =
              res.usernames
                  .map(
                    (u) => SearchContentItem.account(
                      id: 'remote_$u',
                      username: u,
                      alias: u,
                      profileImageUrl: '',
                      followers: 0,
                    ),
                  )
                  .toList();
        }
      }

      // 로컬 컨텐츠 필터링
      final lower = q.toLowerCase();
      final localFiltered =
          _allContentItems.where((item) {
            if (item.isAccount) {
              return item.username?.toLowerCase().contains(lower) ?? false;
            } else {
              return item.title?.toLowerCase().contains(lower) ?? false;
            }
          }).toList();

      // 원격 계정과 로컬 컨텐츠 합치기
      _filteredItems = [...remoteAccounts, ...localFiltered];
      _isLoading = false;
      _error = null;
      notifyListeners();

      debugPrint(
        '[Search] found ${_filteredItems.length} items (${remoteAccounts.length} remote, ${localFiltered.length} local)',
      );
    } catch (e) {
      _isLoading = false;
      _error = '검색 중 오류가 발생했습니다.';
      notifyListeners();
      debugPrint('[Search] error: $e');
    }
  }

  /// 검색 기록에 추가 (public)
  void addToSearchHistory(String query) {
    _addToSearchHistory(query);
  }

  /// 검색 기록에 추가 (private)
  void _addToSearchHistory(String query) {
    if (query.trim().isEmpty) return;

    final trimmedQuery = query.trim();

    // 이미 존재하는 경우 제거
    _searchHistory.remove(trimmedQuery);

    // 맨 앞에 추가
    _searchHistory.insert(0, trimmedQuery);

    // 최대 크기 제한
    if (_searchHistory.length > _maxHistorySize) {
      _searchHistory = _searchHistory.take(_maxHistorySize).toList();
    }

    // SharedPreferences에 저장
    _saveSearchHistory();

    debugPrint(
      '[SearchHistory] added: $trimmedQuery, total: ${_searchHistory.length}',
    );
  }

  /// 검색 기록에서 제거
  void removeFromSearchHistory(String query) {
    _searchHistory.remove(query);
    _saveSearchHistory();
    notifyListeners();
    debugPrint(
      '[SearchHistory] removed: $query, total: ${_searchHistory.length}',
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
        _searchHistory = historyList.cast<String>();
        debugPrint('[SearchHistory] loaded: ${_searchHistory.length} items');
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
      final historyJson = jsonEncode(_searchHistory);
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
      _addToSearchHistory(_query);

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
  }) {
    return SearchContentItem._(
      id: id,
      isAccount: false,
      title: title,
      author: author,
      imageUrl: imageUrl,
      likes: likes,
      comments: comments,
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
