import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 검색 관련 비즈니스 로직을 담당하는 서비스
class SearchService extends ChangeNotifier {
  static final SearchService _instance = SearchService._internal();
  factory SearchService() => _instance;
  SearchService._internal();

  final Dio _dio = BaseApiService().dio;

  // UI 상태 관리
  String _query = '';
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  String _selectedCategory = '추천'; // '추천', '계정'
  bool _isSearching = false; // 검색 중인지 여부
  bool _isFocused = false; // 검색창 포커스 여부
  bool _isKeyboardVisible = false; // 키보드 표시 여부
  bool _viewLocked = false; // 화면 전환 잠금 (네비게이션 중 레이아웃 고정)
  // 블로그 제목 검색 단발 결과 보관
  List<SearchContentItem> _blogResults = [];

  // 통합 컨텐츠 데이터
  List<SearchContentItem> _filteredItems = [];
  List<SearchContentItem> _allItems = [];

  // 검색 최적화
  String _lastAccountQuery = '';
  int _lastAccountCount = -1;

  // 검색 기록 (사용자 객체 기반)
  List<_SearchHistoryEntry> _searchHistory = [];
  static const int _maxHistorySize = 30; // 🎯 최대 30개로 변경
  static const String _searchHistoryKey = 'search_history';

  // 🎯 글 검색 키워드 기록
  List<String> _blogSearchHistory = [];
  static const String _blogSearchHistoryKey = 'blog_search_history';
  static const int _maxBlogHistorySize = 10;

  // 🎯 실시간 검색어 (서버)
  List<String> _trendingKeywords = [];
  bool _isTrendingLoading = false;
  bool _isRefreshing = false; // 🎯 새로고침 중인지 여부

  // 🎯 추천 포스트 (서버)
  List<SearchContentItem> _recommendedPosts = [];

  // 🎯 마지막 fetch 시간 (캐싱용)
  DateTime? _lastTrendingFetchTime;

  // 통합 컨텐츠 데이터 초기화
  late final List<SearchContentItem> _allContentItems = [];

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
  bool get isKeyboardVisible => _isKeyboardVisible;
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
  // Paged blogs
  bool _blogsHasMore = true;
  int _blogsPage = 0;
  String _blogsKeyword = '';
  bool get blogsHasMore => _blogsHasMore;

  // 검색 기록 (계정 리스트 형태)
  List<SearchContentItem> get searchHistory => searchHistoryAsAccounts;

  // 🎯 실시간 검색어 getter
  List<String> get trendingKeywords => _trendingKeywords;
  bool get isTrendingLoading => _isTrendingLoading;
  bool get isRefreshing => _isRefreshing; // 🎯 새로고침 중인지 여부

  // 🎯 shimmer를 표시할지 여부 (로딩 중이면 즉시 표시)
  bool get shouldShowShimmer {
    return _isTrendingLoading; // 로딩 중이면 즉시 shimmer 표시
  }

  // 🎯 추천 포스트 getter
  List<SearchContentItem> get recommendedPosts => _recommendedPosts;

  // 검색 기록을 계정 형태로 변환
  List<SearchContentItem> get searchHistoryAsAccounts {
    final me = AuthService().currentUsernameSync;
    final seen = <String>{};
    final result = <SearchContentItem>[];

    // 🎯 글 검색 키워드 추가 (맨 위에)
    for (final keyword in _blogSearchHistory) {
      if (keyword.trim().isNotEmpty) {
        result.add(
          SearchContentItem.blogKeyword(
            id: 'blog_history_$keyword',
            keyword: keyword,
          ),
        );
      }
    }

    // 계정 검색 기록
    for (final e in _searchHistory) {
      debugPrint('e.username: ${e.username}');
      debugPrint('me: $me');

      if (seen.add(e.username) && e.username != me) {
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
    final sw = Stopwatch()..start();

    debugPrint('┌─[REQ] GET /api/friends/search?username=$query');
    debugPrint('└────────────────────────────────');

    try {
      final res = await _dio.get(
        '/api/friends/search',
        queryParameters: {'username': query},
        cancelToken: cancelToken,
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
    } catch (e) {
      sw.stop();
      debugPrint('[SearchService] searchUsers error: $e');
      if (e is DioException) {
        return FriendSearchResult(
          status: e.response?.statusCode ?? -1,
          usernames: [],
          body: e.response?.data,
          headers: e.response?.headers.map ?? {},
          uri: e.requestOptions.uri,
          elapsed: sw.elapsed,
          serverMessage: e.message,
        );
      }
      rethrow;
    }
  }

  // ---- 사용자 정보 조회
  Future<UserDto?> getUserByUsername({
    required String username,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();

    debugPrint('┌─[REQ] GET /api/auth/users/$username');
    debugPrint('└────────────────────────────────');

    try {
      final res = await _dio.get(
        '/api/auth/users/$username',
        cancelToken: cancelToken,
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
    } catch (e) {
      sw.stop();
      debugPrint('[SearchService] getUserByUsername error: $e');
      return null;
    }
  }

  // ---- UI 로직 메서드들 ----

  /// 초기화 (검색 기록만 로드, 트렌딩은 검색 화면 진입 시 로드)
  Future<void> initialize({bool forceRefresh = false}) async {
    _allContentItems.clear();

    // 🎯 UI 업데이트 기회 제공을 위해 지연 후 실행
    await Future.delayed(const Duration(milliseconds: 50));
    await _loadSearchHistory();

    // 🎯 각 작업 사이에 지연 추가
    await Future.delayed(const Duration(milliseconds: 16));
    await _loadBlogSearchHistory(); // 🎯 글 검색 기록도 로드

    // 🎯 notifyListeners를 지연시켜 UI 블로킹 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// 🎯 배열에서 실제 검색어만 추출하는 헬퍼
  List<String> _extractKeywords(List<dynamic> data) {
    return data
        .map((e) {
          if (e is Map) {
            // 🎯 객체인 경우 keyword 필드 추출
            return (e['keyword'] ?? e['k'] ?? e['query'] ?? e['text'] ?? '')
                .toString();
          } else if (e is String) {
            // 🎯 문자열인 경우 그대로 사용
            return e;
          }
          return '';
        })
        .where((k) => k.isNotEmpty)
        .toList();
  }

  /// 🎯 트렌딩 데이터가 없으면 캐시 체크 후 로드 (캐시 우선 사용)
  Future<void> ensureTrendingData() async {
    // 🎯 이미 데이터가 있으면 로드하지 않음
    if (_trendingKeywords.isNotEmpty || _recommendedPosts.isNotEmpty) {
      debugPrint('[SearchService] 트렌딩 데이터가 이미 있음');
      return;
    }

    // 🎯 데이터가 비어있으면 캐시 시간 체크
    final now = DateTime.now();
    final hasValidCache =
        _lastTrendingFetchTime != null &&
        now.difference(_lastTrendingFetchTime!).inMinutes < 5;

    if (hasValidCache) {
      // 🎯 캐시가 유효하면 API 호출하되, shimmer 표시 없이 로드
      debugPrint(
        '[SearchService] 캐시가 유효하지만 데이터가 비어있어서 다시 로드 (${now.difference(_lastTrendingFetchTime!).inSeconds}초 전 캐시, shimmer 없음)',
      );
      // 캐시 시간을 유지하면서 데이터만 다시 로드 (shimmer 없이)
      await fetchTrendingKeywords(showShimmer: false);
      return;
    }

    // 🎯 캐시가 없거나 만료되었으면 새로 로드
    debugPrint('[SearchService] 캐시가 없거나 만료되어 트렌딩 데이터 새로 로드');
    await fetchTrendingKeywords();
  }

  /// 🎯 실시간 검색어 및 추천 포스트 가져오기
  Future<void> fetchTrendingKeywords({
    int limit = 5,
    bool forceRefresh = false,
    bool showShimmer = true, // 🎯 shimmer 표시 여부 (기본값 true)
  }) async {
    try {
      // 🎯 forceRefresh가 true이거나 데이터가 없으면 로딩 표시 (showShimmer가 true일 때만)
      final hasExistingData =
          _trendingKeywords.isNotEmpty || _recommendedPosts.isNotEmpty;
      if (showShimmer && (forceRefresh || !hasExistingData)) {
        _isTrendingLoading = true;
        if (forceRefresh) {
          _isRefreshing = true; // 🎯 새로고침 중 상태 설정
        }
        notifyListeners(); // 즉시 shimmer 표시
      }

      // 🎯 forceRefresh일 때는 캐시 시간 무시
      if (forceRefresh) {
        _lastTrendingFetchTime = null;
      }

      debugPrint('[TrendingKeywords] Fetching with limit: $limit');

      final response = await _dio.get(
        '/api/search/trending',
        queryParameters: {'limit': limit},
      );

      debugPrint(
        '[TrendingKeywords] Request headers: ${response.requestOptions.headers}',
      );
      debugPrint('[TrendingKeywords] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('[TrendingKeywords] raw response: ${response.data}');

        final Map<String, dynamic> responseData =
            response.data as Map<String, dynamic>;

        // 🔍 recommendedPosts 필드 존재 여부 확인
        if (responseData.containsKey('data')) {
          final dataCheck = responseData['data'] as Map<String, dynamic>;
          debugPrint(
            '[TrendingKeywords] data keys: ${dataCheck.keys.toList()}',
          );
          debugPrint(
            '[TrendingKeywords] recommendedPosts type: ${dataCheck['recommendedPosts']?.runtimeType}',
          );
          debugPrint(
            '[TrendingKeywords] recommendedPosts length: ${dataCheck['recommendedPosts'] is List ? (dataCheck['recommendedPosts'] as List).length : 0}',
          );
        }

        // 🎯 data 객체 추출
        if (responseData.containsKey('data') && responseData['data'] is Map) {
          final Map<String, dynamic> data =
              responseData['data'] as Map<String, dynamic>;

          // 🎯 keywords 추출
          if (data.containsKey('keywords') && data['keywords'] is List) {
            final List<dynamic> keywords = data['keywords'] as List<dynamic>;
            _trendingKeywords = _extractKeywords(keywords);
          } else {
            _trendingKeywords = [];
          }

          // 🎯 recommendedPosts 추출
          if (data.containsKey('recommendedPosts') &&
              data['recommendedPosts'] is List) {
            final List<dynamic> posts =
                data['recommendedPosts'] as List<dynamic>;
            _recommendedPosts =
                posts.map((post) {
                  return SearchContentItem.post(
                    id: post['id']?.toString() ?? '',
                    title: post['title'] ?? '',
                    author: post['author'] ?? '',
                    imageUrl: post['thumbnailImageUrl'] ?? '',
                    likes: post['likeCount'] ?? 0,
                    comments: post['commentCount'] ?? 0,
                    summary: post['summary'],
                    content: post['content'],
                    parsedContent: post['parsedContent'],
                    profileImageUrl: post['authorProfileImageUrl'],
                    createdAt: post['createdAt'],
                  );
                }).toList();
          } else {
            _recommendedPosts = [];
          }
        } else {
          _trendingKeywords = [];
          _recommendedPosts = [];
        }

        debugPrint(
          '[TrendingKeywords] loaded: ${_trendingKeywords.length} keywords',
        );
        debugPrint(
          '[TrendingKeywords] loaded: ${_recommendedPosts.length} recommended posts',
        );
        debugPrint('[TrendingKeywords] keywords: $_trendingKeywords');

        // 🎯 성공적으로 로드했으면 시간 기록
        _lastTrendingFetchTime = DateTime.now();
      } else {
        _trendingKeywords = [];
        _recommendedPosts = [];
        debugPrint('[TrendingKeywords] failed: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('[TrendingKeywords] error: $e');
      debugPrint('[TrendingKeywords] stackTrace: $stackTrace');
      _trendingKeywords = [];
      _recommendedPosts = [];
    } finally {
      _isTrendingLoading = false;
      _isRefreshing = false; // 🎯 새로고침 상태 초기화
      notifyListeners();
    }
  }

  /// 추천 게시글 새로고침
  Future<void> refreshRecommendations() async {
    _allContentItems.clear();
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

  /// 검색어 변경
  void onSearchChanged(String q) {
    debugPrint('[Search] onSearchChanged: $q');
    _query = q;
    _debounce?.cancel();

    if (q.isEmpty) {
      _filteredItems = List.from(_allContentItems);
      _selectedCategory = '추천';
      _isSearching = false;

      // 🎯 검색어가 비어있고 트렌딩 데이터도 비어있으면 캐시 체크 후 로드
      if (_trendingKeywords.isEmpty && _recommendedPosts.isEmpty) {
        debugPrint('[Search] 검색어가 비어있고 트렌딩 데이터가 없어서 캐시 체크 후 로드');
        ensureTrendingData();
      }

      // 🎯 notifyListeners를 지연시켜 UI 블로킹 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } else {
      // 포커스 여부와 관계없이 실시간 검색 (debounce 적용)
      _isSearching = true;

      // 🎯 notifyListeners를 지연시켜 UI 블로킹 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      // 🎯 debounce를 적용하여 중복 호출 방지 (300ms)
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _performRealTimeSearch(q);
      });
    }
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

  /// 제목으로 블로그 단발 검색 (검색 버튼/엔터 콜백에서 호출)
  Future<void> searchBlogsByTitleOnce({
    required String keyword,
    int page = 0,
    int size = 10,
  }) async {
    if (keyword.isEmpty) return;
    try {
      final res = await _dio.get(
        '/api/posts/search',
        queryParameters: {'keyword': keyword, 'page': page, 'size': size},
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
            final authorProfile = e['authorProfileImageUrl']?.toString() ?? '';
            final createdAt = e['createdAt']?.toString();
            final likes = (e['likeCount'] as num?)?.toInt() ?? 0;
            final comments = (e['commentCount'] as num?)?.toInt() ?? 0;
            final content = e['content']?.toString() ?? '';
            final summaryFromServer = e['summary']?.toString();

            // PostData의 parsedContent getter를 활용
            final tempPostData = PostData.fromServer(e);
            final parsedContent = tempPostData.parsedContent;
            final summary =
                (summaryFromServer != null && summaryFromServer.isNotEmpty)
                    ? summaryFromServer
                    : parsedContent;

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
                summary: summary,
                profileImageUrl: authorProfile,
                createdAt: createdAt,
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

  // --- Paged blog search helpers ---
  Future<List<SearchContentItem>> fetchBlogsByTitlePage({
    required String keyword,
    required int page,
    int size = 20,
  }) async {
    debugPrint(
      '[SearchService] 시맨틱 검색: query=$keyword, page=$page, size=$size',
    );

    final res = await _dio.get(
      '/api/search/semantic',
      queryParameters: {'query': keyword, 'page': page, 'size': size},
    );

    debugPrint('[SearchService] 시맨틱 검색 응답: ${res.statusCode}');
    debugPrint(
      '[SearchService] 시맨틱 검색 응답 데이터 키: ${res.data is Map ? (res.data as Map).keys.toList() : 'not a map'}',
    );
    debugPrint('[SearchService] 시맨틱 검색 응답 데이터 구조: ${res.data}');

    final List<SearchContentItem> posts = [];
    if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
      final responseData = res.data as Map<String, dynamic>;

      // 🎯 여러 가능한 응답 구조 처리
      List<dynamic>? content;

      // 1. 직접 content 필드
      if (responseData.containsKey('content') &&
          responseData['content'] is List) {
        content = responseData['content'] as List;
        debugPrint('[SearchService] content 필드에서 파싱: ${content.length}개');
      }
      // 2. data.content 구조
      else if (responseData.containsKey('data') &&
          responseData['data'] is Map) {
        final data = responseData['data'] as Map<String, dynamic>;
        if (data.containsKey('content') && data['content'] is List) {
          content = data['content'] as List;
          debugPrint('[SearchService] data.content에서 파싱: ${content.length}개');
        } else if (data.containsKey('posts') && data['posts'] is List) {
          content = data['posts'] as List;
          debugPrint('[SearchService] data.posts에서 파싱: ${content.length}개');
        }
      }
      // 3. posts 필드
      else if (responseData.containsKey('posts') &&
          responseData['posts'] is List) {
        content = responseData['posts'] as List;
        debugPrint('[SearchService] posts 필드에서 파싱: ${content.length}개');
      }

      if (content == null) {
        debugPrint('[SearchService] ⚠️ 시맨틱 검색 응답에서 포스트 목록을 찾을 수 없음');
        debugPrint('[SearchService] 전체 응답: $responseData');
        return posts;
      }

      for (final e in content) {
        if (e is Map<String, dynamic>) {
          final id = e['id']?.toString() ?? '';
          final title = e['title']?.toString() ?? '';
          final author = e['author']?.toString() ?? '';
          final imageUrl = e['thumbnailImageUrl']?.toString() ?? '';
          final authorProfile = e['authorProfileImageUrl']?.toString() ?? '';
          final createdAt = e['createdAt']?.toString();
          final likes = (e['likeCount'] as num?)?.toInt() ?? 0;
          final comments = (e['commentCount'] as num?)?.toInt() ?? 0;
          final contentStr = e['content']?.toString() ?? '';
          final summaryFromServer = e['summary']?.toString();

          final tempPostData = PostData.fromServer(e);
          final parsedContent = tempPostData.parsedContent;
          final summary =
              (summaryFromServer != null && summaryFromServer.isNotEmpty)
                  ? summaryFromServer
                  : parsedContent;

          _postData[id] = e;
          posts.add(
            SearchContentItem.post(
              id: id,
              title: title,
              author: author,
              imageUrl: imageUrl,
              likes: likes,
              comments: comments,
              content: contentStr,
              parsedContent: parsedContent,
              summary: summary,
              profileImageUrl: authorProfile,
              createdAt: createdAt,
            ),
          );
        }
      }

      debugPrint('[SearchService] 시맨틱 검색 파싱 완료: ${posts.length}개 포스트');
      if (posts.isEmpty && content.isNotEmpty) {
        debugPrint(
          '[SearchService] ⚠️ content는 ${content.length}개인데 파싱된 포스트는 0개',
        );
        debugPrint('[SearchService] 첫 번째 content 아이템: ${content.first}');
      }
    } else {
      debugPrint('[SearchService] ⚠️ 시맨틱 검색 응답이 Map이 아니거나 statusCode가 200이 아님');
      debugPrint(
        '[SearchService] statusCode: ${res.statusCode}, data type: ${res.data.runtimeType}',
      );
    }
    return posts;
  }

  Future<void> startBlogsSearch(String keyword, {int size = 20}) async {
    if (keyword.trim().isEmpty) return;
    _blogsKeyword = keyword;
    final posts = await fetchBlogsByTitlePage(
      keyword: keyword,
      page: 0,
      size: size,
    );
    _blogResults = posts;
    _blogsPage = 1;
    _blogsHasMore = posts.length == size;
    notifyListeners();
  }

  Future<List<SearchContentItem>> loadMoreBlogs({int size = 20}) async {
    if (_blogsKeyword.isEmpty || !_blogsHasMore) return const [];
    final posts = await fetchBlogsByTitlePage(
      keyword: _blogsKeyword,
      page: _blogsPage,
      size: size,
    );
    if (posts.isNotEmpty) {
      _blogResults.addAll(posts);
      _blogsPage += 1;
      _blogsHasMore = posts.length == size;
      notifyListeners();
    } else {
      _blogsHasMore = false;
    }
    return posts;
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

  /// 🎯 글 검색 키워드를 검색 기록에 추가
  void addBlogSearchKeyword(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    // 중복 제거
    _blogSearchHistory.remove(trimmed);

    // 맨 앞에 추가
    _blogSearchHistory.insert(0, trimmed);

    // 최대 개수 제한
    if (_blogSearchHistory.length > _maxBlogHistorySize) {
      _blogSearchHistory =
          _blogSearchHistory.take(_maxBlogHistorySize).toList();
    }

    _saveBlogSearchHistory();
    notifyListeners();

    debugPrint(
      '[BlogSearchHistory] added: $trimmed, total: ${_blogSearchHistory.length}',
    );
  }

  /// 🎯 글 검색 기록에서 제거
  void removeBlogSearchKeyword(String keyword) {
    _blogSearchHistory.remove(keyword);
    _saveBlogSearchHistory();
    notifyListeners();
    debugPrint('[BlogSearchHistory] removed: $keyword');
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
  /// 검색 기록 로드 (외부에서 호출 가능)
  Future<void> loadSearchHistory() async {
    await _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    try {
      // 🎯 SharedPreferences 작업 전 지연
      await Future.delayed(const Duration(milliseconds: 8));
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_searchHistoryKey);

      if (historyJson != null) {
        // 🎯 jsonDecode 전 지연 (큰 데이터 파싱 시 블로킹 방지)
        await Future.delayed(const Duration(milliseconds: 8));
        final List<dynamic> historyList = jsonDecode(historyJson);

        // 🎯 데이터 처리 전 지연
        await Future.delayed(const Duration(milliseconds: 8));
        final loaded =
            historyList
                .whereType<Map<String, dynamic>>()
                .map((m) => _SearchHistoryEntry.fromJson(m))
                .toList();
        // username 기준 최신 우선 중복 제거 + 개수 제한
        final seen = <String>{};
        _searchHistory = [];
        for (final e in loaded) {
          final u = e.username;
          if (u.isEmpty) continue;
          if (!seen.contains(u)) {
            _searchHistory.add(e);
            seen.add(u);
            // 🎯 최대 30개까지만 로드
            if (_searchHistory.length >= _maxHistorySize) {
              break;
            }
          }
          // 🎯 각 항목 처리 후 간헐적으로 지연 (큰 리스트 처리 시 블로킹 방지)
          if (_searchHistory.length % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 4));
          }
        }
        debugPrint(
          '[SearchHistory] loaded(objects): ${_searchHistory.length} items (max: $_maxHistorySize)',
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

  /// 🎯 글 검색 기록 불러오기
  Future<void> _loadBlogSearchHistory() async {
    try {
      // 🎯 SharedPreferences 작업 전 지연
      await Future.delayed(const Duration(milliseconds: 8));
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_blogSearchHistoryKey);

      if (historyJson != null) {
        // 🎯 jsonDecode 전 지연
        await Future.delayed(const Duration(milliseconds: 8));
        final List<dynamic> historyList = jsonDecode(historyJson);
        _blogSearchHistory = historyList.whereType<String>().toList();
        debugPrint(
          '[BlogSearchHistory] loaded: ${_blogSearchHistory.length} items',
        );
      } else {
        _blogSearchHistory = [];
        debugPrint('[BlogSearchHistory] no saved history found');
      }
    } catch (e) {
      debugPrint('[BlogSearchHistory] load error: $e');
      _blogSearchHistory = [];
    }
  }

  /// 🎯 글 검색 기록 저장하기
  Future<void> _saveBlogSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = jsonEncode(_blogSearchHistory);
      await prefs.setString(_blogSearchHistoryKey, historyJson);
      debugPrint(
        '[BlogSearchHistory] saved: ${_blogSearchHistory.length} items',
      );
    } catch (e) {
      debugPrint('[BlogSearchHistory] save error: $e');
    }
  }

  /// 트렌딩 데이터 지우기
  void clearTrendingData() {
    debugPrint('[SearchService] 트렌딩 데이터 지우기');
    _trendingKeywords = [];
    _recommendedPosts = [];
    _isTrendingLoading = false;
    notifyListeners();
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

    // 🎯 검색어를 지웠을 때 트렌딩 데이터가 비어있으면 캐시 체크 후 로드
    if (_trendingKeywords.isEmpty && _recommendedPosts.isEmpty) {
      debugPrint('[Search] clearSearch - 트렌딩 데이터가 없어서 캐시 체크 후 로드');
      ensureTrendingData().then((_) {
        notifyListeners();
      });
      return; // ensureTrendingData가 완료된 후 notifyListeners 호출
    }

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

    // 🎯 뒤로가기를 눌렀을 때 항상 트렌딩 데이터가 표시되도록 보장
    // 트렌딩 데이터가 비어있으면 캐시 체크 후 로드
    if (_trendingKeywords.isEmpty && _recommendedPosts.isEmpty) {
      debugPrint('[Search] resetToInitial - 트렌딩 데이터가 없어서 캐시 체크 후 로드');
      ensureTrendingData().then((_) {
        notifyListeners();
      });
      return; // ensureTrendingData가 완료된 후 notifyListeners 호출
    }

    // 🎯 트렌딩 데이터가 있어도 항상 보장하도록 (이미 있는 경우에도 화면 갱신)
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

    // 🎯 notifyListeners를 지연시켜 UI 블로킹 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// 키보드 표시 상태 업데이트
  void setKeyboardVisible(bool v) {
    if (_isKeyboardVisible == v) return;
    _isKeyboardVisible = v;
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
  final bool isBlogKeyword; // 🎯 글 검색 키워드인지 여부

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
  final String? createdAt;
  final String? summary;

  // 🎯 Getter
  bool get isBlog => !isAccount && isBlogKeyword;

  const SearchContentItem._({
    required this.id,
    required this.isAccount,
    this.isBlogKeyword = false,
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
    this.createdAt,
    this.summary,
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
    String? summary,
    String? profileImageUrl,
    String? createdAt,
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
      summary: summary,
      profileImageUrl: profileImageUrl,
      createdAt: createdAt,
    );
  }

  /// 🎯 글 검색 키워드 (검색 기록용)
  factory SearchContentItem.blogKeyword({
    required String id,
    required String keyword,
  }) {
    return SearchContentItem._(
      id: id,
      isAccount: false,
      isBlogKeyword: true,
      title: keyword,
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
