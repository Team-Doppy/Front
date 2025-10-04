import 'dart:convert';
import 'dart:io';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:http/http.dart' as http;

class BlogService {
  static final BlogService _instance = BlogService._internal();
  factory BlogService() => _instance;
  BlogService._internal();

  static final String _baseUrl = ApiServiceBase.baseUrl;

  // 포스트 캐시
  static List<Map<String, dynamic>> _cachedPosts = [];
  static DateTime? _lastCacheTime;
  static const Duration _cacheExpiry = Duration(hours: 12);

  // 내 포스트 캐시 (page/size 별)
  static final Map<String, List<Map<String, dynamic>>> _myPostsCache = {};
  static DateTime? _myPostsCachedAt;
  static const Duration _myPostsExpiry = Duration(minutes: 30);

  /// 캐시가 유효한지 확인
  static bool _isCacheValid() {
    if (_lastCacheTime == null || _cachedPosts.isEmpty) {
      return false;
    }
    return DateTime.now().difference(_lastCacheTime!) < _cacheExpiry;
  }

  /// 캐시 무효화
  static void _invalidateCache() {
    _cachedPosts.clear();
    _lastCacheTime = null;
  }

  static bool _isMyPostsCacheValid() {
    if (_myPostsCachedAt == null || _myPostsCache.isEmpty) return false;
    return DateTime.now().difference(_myPostsCachedAt!) < _myPostsExpiry;
  }

  static void _invalidateMyPostsCache() {
    _myPostsCache.clear();
    _myPostsCachedAt = null;
  }

  /// 로그아웃 시 모든 캐시 초기화
  static void clearAllCache() {
    _invalidateCache();
    _invalidateMyPostsCache();
    print('[BlogService] 로그아웃 - 모든 캐시 초기화 완료');
  }

  /// 블로그 포스트를 서버에 업로드합니다.
  ///
  /// [postData] - 포스트 데이터 (제목, 내용, 썸네일 URL, 태그 등)
  /// [thumbnailImageId] - 썸네일 이미지 ID (선택사항)
  ///
  /// 반환: 업로드된 포스트의 ID와 메타데이터
  Future<Map<String, dynamic>> uploadPost({
    required Map<String, dynamic> postData,
    String? thumbnailImageId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/posts');
    final token = await AuthService().getToken();

    print(
      '[UploadPost] uploading post with thumbnailImageId: $thumbnailImageId',
    );

    // 서버 DTO에 맞춰 매핑: title, author, thumbnailImageUrl, content(JsonNode), accessLevel
    // accessLevel 매핑 (PUBLIC | PRIVATE | GROUPS)
    final Map<String, dynamic> visibility =
        (postData['visibility'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{'type': 'public'};
    final String vType =
        (visibility['type'] ?? 'public').toString().toUpperCase();
    final String accessLevel =
        (vType == 'PRIVATE')
            ? 'PRIVATE'
            : (vType == 'GROUPS' ? 'GROUPS' : 'PUBLIC');

    // content(JsonNode) 전송: 문자열이면 decode, 맵/리스트면 그대로 사용
    dynamic contentJson = postData['content'];
    if (contentJson is String && contentJson.isNotEmpty) {
      try {
        contentJson = json.decode(contentJson);
      } catch (_) {
        contentJson = <String, dynamic>{'raw': contentJson};
      }
    }

    final requestBody = <String, dynamic>{
      'title': postData['title'] ?? '',
      'author': postData['author'] ?? '',
      'thumbnailImageUrl': postData['thumbnailImageUrl'] ?? '',
      'content': contentJson ?? const <String, dynamic>{'nodes': []},
      'accessLevel': accessLevel,
    };

    print('[UploadPost] request body: ${json.encode(requestBody)}');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(requestBody),
        )
        .timeout(const Duration(seconds: 30));

    final responseBody = response.body;

    if (response.statusCode == 200 || response.statusCode == 201) {
      print('[UploadPost] success ${response.statusCode} body=$responseBody');
      final decoded = json.decode(responseBody) as Map<String, dynamic>;

      // 새 포스트 업로드 시 캐시 무효화
      _invalidateCache();
      _invalidateMyPostsCache();

      return decoded;
    } else {
      print('[UploadPost] error ${response.statusCode} body=$responseBody');
      throw HttpException(
        'post upload failed ${response.statusCode}: $responseBody',
      );
    }
  }

  /// 포스트를 업데이트합니다.
  ///
  /// [postId] - 업데이트할 포스트의 ID
  /// [postData] - 업데이트할 포스트 데이터
  /// [thumbnailImageId] - 새로운 썸네일 이미지 ID (선택사항)
  Future<Map<String, dynamic>> updatePost({
    required String postId,
    required Map<String, dynamic> postData,
    String? thumbnailImageId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/posts/$postId');
    final token = await AuthService().getToken();

    print(
      '[UpdatePost] updating post $postId with thumbnailImageId: $thumbnailImageId',
    );

    // 서버 DTO 규격에 맞게 업데이트 바디 구성
    final Map<String, dynamic> visibility =
        (postData['visibility'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{'type': 'public'};
    final String vType =
        (visibility['type'] ?? 'public').toString().toUpperCase();
    final String accessLevel =
        (vType == 'PRIVATE')
            ? 'PRIVATE'
            : (vType == 'GROUPS' ? 'GROUPS' : 'PUBLIC');

    dynamic contentJson = postData['content'];
    if (contentJson is String && contentJson.isNotEmpty) {
      try {
        contentJson = json.decode(contentJson);
      } catch (_) {
        contentJson = <String, dynamic>{'raw': contentJson};
      }
    }

    final requestBody = <String, dynamic>{
      'title': postData['title'] ?? '',
      'author': postData['author'] ?? '',
      'thumbnailImageUrl': postData['thumbnailImageUrl'] ?? '',
      'content': contentJson ?? const <String, dynamic>{'nodes': []},
      'accessLevel': accessLevel,
      if (thumbnailImageId != null) 'thumbnailImageId': thumbnailImageId,
    };

    print('[UpdatePost] request body: ${json.encode(requestBody)}');

    final response = await http
        .put(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(requestBody),
        )
        .timeout(const Duration(seconds: 30));

    final responseBody = response.body;

    if (response.statusCode == 200) {
      print('[UpdatePost] success body=$responseBody');
      final decoded = json.decode(responseBody) as Map<String, dynamic>;
      return decoded;
    } else {
      print('[UpdatePost] error ${response.statusCode} body=$responseBody');
      throw HttpException(
        'post update failed ${response.statusCode}: $responseBody',
      );
    }
  }

  /// 포스트를 삭제합니다.
  ///
  /// [postId] - 삭제할 포스트의 ID
  Future<void> deletePost(String postId) async {
    final uri = Uri.parse('$_baseUrl/api/posts/$postId');
    final token = await AuthService().getToken();

    print('[DeletePost] deleting post $postId');

    final response = await http
        .delete(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200 || response.statusCode == 204) {
      print('[DeletePost] success');
    } else {
      final responseBody = response.body;
      print('[DeletePost] error ${response.statusCode} body=$responseBody');
      throw HttpException(
        'post delete failed ${response.statusCode}: $responseBody',
      );
    }
  }

  /// 좋아요 추가
  Future<void> likePost(String postId) async {
    final uri = Uri.parse('$_baseUrl/api/posts/$postId/like');
    final token = await AuthService().getToken();
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw HttpException('Failed to like post: ${response.statusCode}');
    }
  }

  /// 좋아요 취소
  Future<void> unlikePost(String postId) async {
    final uri = Uri.parse('$_baseUrl/api/posts/$postId/unlike');
    final token = await AuthService().getToken();
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw HttpException('Failed to unlike post: ${response.statusCode}');
    }
  }

  /// 홈 화면용 블로그 포스트 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getHomePosts({
    int page = 0,
    int size = 10,
    bool forceRefresh = false,
  }) async {
    try {
      // 캐시 확인 (첫 페이지만 캐시 사용)
      if (page == 0 && !forceRefresh && _isCacheValid()) {
        print(
          '[BlogService] Using cached posts (${_cachedPosts.length} posts)',
        );
        return _cachedPosts.take(size).toList();
      }

      print('[BlogService] Fetching home posts: page=$page, size=$size');

      final token = await AuthService().getToken();
      final uri = Uri.parse('$_baseUrl/api/posts/home?page=$page&size=$size');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
        print('[BlogService] Successfully fetched ${posts.length} home posts');

        // 첫 페이지면 캐시 업데이트
        if (page == 0) {
          _cachedPosts = posts;
          _lastCacheTime = DateTime.now();
          print('[BlogService] Cache updated with ${posts.length} posts');
        }

        // 포스트가 없으면 fallback 데이터 반환
        if (posts.isEmpty) {
          print('[BlogService] No posts found, returning fallback data');
          return _getFallbackPosts();
        }

        return posts;
      } else {
        print('[BlogService] Error ${response.statusCode}: ${response.body}');
        throw Exception('Failed to fetch home posts: ${response.statusCode}');
      }
    } catch (e) {
      print('[BlogService] Exception: $e');
      // 서버 오류 시 임시 데이터 반환
      return _getFallbackPosts();
    }
  }

  /// 특정 포스트의 상세 정보를 가져옵니다.
  Future<Map<String, dynamic>> getPostDetail(String postId) async {
    try {
      final token = await AuthService().getToken();
      final uri = Uri.parse('$_baseUrl/api/posts/$postId');

      print('[BlogService] Fetching post detail: $postId');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        print('[BlogService] Successfully fetched post detail');

        if (decoded is Map<String, dynamic>) {
          return decoded;
        } else if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is Map<String, dynamic>) {
            return first;
          }
        }

        throw Exception(
          'Unexpected post detail response type: ${decoded.runtimeType}',
        );
      } else {
        print('[BlogService] Error ${response.statusCode}: ${response.body}');
        throw Exception('Failed to fetch post detail: ${response.statusCode}');
      }
    } catch (e) {
      print('[BlogService] Exception: $e');
      throw Exception('Failed to fetch post detail: $e');
    }
  }

  /// 내가 쓴 블로그 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getMyPosts({
    int page = 0,
    int size = 10,
  }) async {
    try {
      // 캐시 키: page|size
      final String cacheKey = '$page|$size';
      if (_isMyPostsCacheValid() && _myPostsCache.containsKey(cacheKey)) {
        print('[BlogService] Using cached my posts: key=$cacheKey');
        return _myPostsCache[cacheKey]!;
      }

      final token = await AuthService().getToken();
      final uri = Uri.parse('$_baseUrl/api/posts/my?page=$page&size=$size');

      print('[BlogService] Fetching my posts: page=$page, size=$size');

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
        print('[BlogService] Successfully fetched ${posts.length} my posts');
        // 캐시 저장
        _myPostsCache[cacheKey] = posts;
        _myPostsCachedAt = DateTime.now();
        return posts;
      } else {
        print('[BlogService] Error ${response.statusCode}: ${response.body}');
        throw Exception('Failed to fetch my posts: ${response.statusCode}');
      }
    } catch (e) {
      print('[BlogService] Exception: $e');
      throw Exception('Failed to fetch my posts: $e');
    }
  }

  /// 특정 사용자의 블로그 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getUserPosts({
    required String username,
    int page = 0,
    int size = 10,
  }) async {
    try {
      final token = await AuthService().getToken();
      final uri = Uri.parse(
        '$_baseUrl/api/posts/user/$username?page=$page&size=$size',
      );

      print(
        '[BlogService] Fetching user posts: username=$username page=$page, size=$size',
      );

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final posts = List<Map<String, dynamic>>.from(
          data['content'] ?? data as List? ?? [],
        );
        print('[BlogService] Successfully fetched ${posts.length} user posts');
        return posts;
      } else if (response.statusCode == 404) {
        // 사용자 포스트가 없거나 API 엔드포인트가 존재하지 않는 경우
        print(
          '[BlogService] User posts not found (404) for username: $username',
        );
        return []; // 빈 리스트 반환
      } else {
        print('[BlogService] Error ${response.statusCode}: ${response.body}');
        throw Exception('Failed to fetch user posts: ${response.statusCode}');
      }
    } catch (e) {
      print('[BlogService] Exception: $e');
      // 404 에러인 경우 빈 리스트 반환 (서버 문제 대응)
      if (e.toString().contains('404')) {
        print('[BlogService] Returning empty list due to 404 error');
        return [];
      }
      throw Exception('Failed to fetch user posts: $e');
    }
  }

  /// 제목으로 블로그를 검색합니다.
  Future<List<Map<String, dynamic>>> searchPosts({
    required String keyword,
    int page = 0,
    int size = 10,
  }) async {
    try {
      final token = await AuthService().getToken();
      final uri = Uri.parse(
        '$_baseUrl/api/posts/search?keyword=${Uri.encodeComponent(keyword)}&page=$page&size=$size',
      );

      print(
        '[BlogService] Searching posts: keyword=$keyword, page=$page, size=$size',
      );

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
        print('[BlogService] Successfully found ${posts.length} posts');
        return posts;
      } else {
        print('[BlogService] Error ${response.statusCode}: ${response.body}');
        throw Exception('Failed to search posts: ${response.statusCode}');
      }
    } catch (e) {
      print('[BlogService] Exception: $e');
      throw Exception('Failed to search posts: $e');
    }
  }

  /// 썸네일 이미지 URL을 가져옵니다.
  Future<String?> getThumbnailUrl(String imageId) async {
    try {
      final token = await AuthService().getToken();
      final uri = Uri.parse('$_baseUrl/api/images/$imageId');

      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['url'] as String?;
      } else {
        print('[BlogService] Error fetching thumbnail: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[BlogService] Exception fetching thumbnail: $e');
      return null;
    }
  }

  /// 서버 오류 시 사용할 임시 데이터
  Future<List<Map<String, dynamic>>> _getFallbackPosts() {
    return getMyPosts().then((value) => value);
  }
}
