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

  // 내 포스트 캐시 (page/size 별)
  static final Map<String, List<Map<String, dynamic>>> _myPostsCache = {};
  static DateTime? _myPostsCachedAt;
  static const Duration _myPostsExpiry = Duration(minutes: 30);

  // 홈 캐시 제거됨

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
    _invalidateMyPostsCache();
    print('[BlogService] 로그아웃 - 모든 캐시 초기화 완료');
  }

  /// 토큰 만료 시 자동 갱신 및 재시도 헬퍼
  Future<http.Response> _requestWithTokenRefresh(
    Future<http.Response> Function(String token) requestFn,
  ) async {
    final token = await AuthService().getToken();
    var response = await requestFn(token ?? '');

    // 401 또는 500 (JWT 만료) 에러 시 토큰 갱신 후 재시도
    if (response.statusCode == 401 ||
        (response.statusCode == 500 &&
            response.body.contains('ExpiredJwtException'))) {
      print('[BlogService] Token expired, refreshing...');

      final refreshed = await AuthService().refreshToken();
      if (!refreshed) {
        throw Exception('토큰 갱신에 실패했습니다. 다시 로그인해주세요.');
      }

      final newToken = await AuthService().getToken();
      print('[BlogService] Retrying with new token...');

      response = await requestFn(newToken ?? '');
    }

    return response;
  }

  /// 새로운 프로필 피드 API 호출
  Future<Map<String, dynamic>> getProfileFeed(String username) async {
    final uri = Uri.parse('$_baseUrl/api/profile/$username/feed');

    print('[BlogService] 프로필 피드 요청: $username');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      print('[BlogService] 프로필 피드 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[BlogService] 프로필 피드 응답 전체: $data');
        print(
          '[BlogService] 프로필 피드 로드 성공: ${data['data']?['categories']?.length ?? 0}개 카테고리',
        );
        return data;
      } else if (response.statusCode == 404) {
        throw Exception('사용자를 찾을 수 없습니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 프로필 피드 로드 실패: $e');
      rethrow;
    }
  }

  /// 프로필 스키마 조회 (카테고리/매핑 전용)
  Future<Map<String, dynamic>> getProfileSchema(String username) async {
    final uri = Uri.parse('$_baseUrl/api/profile/feed/schema/$username');

    print('[BlogService] 프로필 스키마 요청: $username');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      print('[BlogService] 프로필 스키마 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 404) {
        throw Exception('사용자를 찾을 수 없습니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 프로필 스키마 로드 실패: $e');
      rethrow;
    }
  }

  /// 프로필 포스트 페이지 조회 (페이지네이션)
  Future<Map<String, dynamic>> getProfilePosts(
    String username, {
    int page = 0,
    int size = 20,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/profile/feed/posts/$username?page=$page&size=$size',
    );

    print('[BlogService] 프로필 포스트 요청: $username page=$page size=$size');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      print('[BlogService] 프로필 포스트 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 404) {
        throw Exception('사용자를 찾을 수 없습니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 프로필 포스트 로드 실패: $e');
      rethrow;
    }
  }

  /// 사용자의 카테고리 목록 조회
  Future<List<Map<String, dynamic>>> getUserCategories(String username) async {
    final uri = Uri.parse('$_baseUrl/api/categories/user/$username');

    print('[BlogService] 카테고리 목록 조회 요청: $username');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[BlogService] 카테고리 목록 조회 성공: ${data.length}개');
        return List<Map<String, dynamic>>.from(data);
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else if (response.statusCode == 404) {
        throw Exception('사용자를 찾을 수 없습니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 카테고리 목록 조회 실패: $e');
      rethrow;
    }
  }

  /// 카테고리 생성
  Future<Map<String, dynamic>> createCategory({
    required String name,
    required bool isPrivate,
    required String description,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/categories');

    print('[BlogService] 카테고리 생성 요청: $name');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'name': name,
            'is_private': isPrivate,
            'description': description,
          }),
        ),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[BlogService] 카테고리 생성 성공: ${data['data']?['name']}');
        return data;
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? '잘못된 요청입니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 카테고리 생성 실패: $e');
      rethrow;
    }
  }

  /// 카테고리 삭제
  Future<void> deleteCategory(int categoryId) async {
    final uri = Uri.parse('$_baseUrl/api/categories/$categoryId');

    print('[BlogService] 카테고리 삭제 요청: $categoryId');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.delete(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        print('[BlogService] 카테고리 삭제 성공: $categoryId');
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? '카테고리를 삭제할 수 없습니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else if (response.statusCode == 404) {
        throw Exception('카테고리를 찾을 수 없습니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 카테고리 삭제 실패: $e');
      rethrow;
    }
  }

  /// 카테고리 순서 변경
  Future<void> reorderCategories(List<int> orderedIds) async {
    final uri = Uri.parse('$_baseUrl/api/categories/reorder');

    print('[BlogService] 카테고리 순서 변경 요청: $orderedIds');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.put(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: json.encode({'orderedIds': orderedIds}),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('[BlogService] 카테고리 순서 변경 성공');
        try {
          if (response.body.isNotEmpty) {
            print('[BlogService] 서버 응답 본문: ' + response.body);
          }
        } catch (_) {}
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? '잘못된 요청입니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else {
        try {
          if (response.body.isNotEmpty) {
            print('[BlogService] 실패 응답 본문: ' + response.body);
          }
        } catch (_) {}
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 카테고리 순서 변경 실패: $e');
      rethrow;
    }
  }

  /// 포스트를 다른 카테고리로 이동 (명세 반영)
  Future<void> movePostToCategory({
    required int postId,
    required int targetCategoryId,
    int? targetPosition,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/categories/posts/$postId/move');

    print(
      '[BlogService] 포스트 이동 요청: $postId -> $targetCategoryId (pos=$targetPosition)',
    );

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.put(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'targetCategoryId': targetCategoryId,
            if (targetPosition != null) 'targetPosition': targetPosition,
          }),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('[BlogService] 포스트 이동 성공: $postId -> $targetCategoryId');
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? '잘못된 요청입니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else if (response.statusCode == 404) {
        throw Exception('포스트 또는 카테고리를 찾을 수 없습니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 포스트 이동 실패: $e');
      rethrow;
    }
  }

  /// 카테고리 내 포스트 순서 변경
  Future<void> reorderPostsInCategory({
    required int categoryId,
    required List<int> orderedIds,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/categories/$categoryId/posts/reorder');

    print('[BlogService] 포스트 순서 변경 요청: 카테고리 $categoryId');

    try {
      final response = await _requestWithTokenRefresh(
        (token) => http.put(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: json.encode({'orderedIds': orderedIds}),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('[BlogService] 포스트 순서 변경 성공: 카테고리 $categoryId');
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? '잘못된 요청입니다.');
      } else if (response.statusCode == 401) {
        throw Exception('인증이 필요합니다.');
      } else if (response.statusCode == 404) {
        throw Exception('카테고리를 찾을 수 없습니다.');
      } else {
        throw Exception('서버 오류가 발생했습니다. (${response.statusCode})');
      }
    } catch (e) {
      print('[BlogService] 포스트 순서 변경 실패: $e');
      rethrow;
    }
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

    final response = await _requestWithTokenRefresh(
      (token) => http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30)),
    );

    final responseBody = response.body;

    if (response.statusCode == 200 || response.statusCode == 201) {
      print('[UploadPost] success ${response.statusCode} body=$responseBody');
      final decoded = json.decode(responseBody) as Map<String, dynamic>;

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

    final response = await _requestWithTokenRefresh(
      (token) => http
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30)),
    );

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

        // 포스트가 없으면 fallback 데이터 반환
        if (posts.isEmpty) {
          print('[BlogService] No posts found, returning fallback data');
          return await _getFallbackPosts();
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

  /// 친구(팔로우한 사용자)의 게시물을 가져옵니다. (실제로는 getHomePosts 사용)
  Future<List<Map<String, dynamic>>> getFriendsPosts({
    int page = 0,
    int size = 10,
  }) async {
    // 친구 게시물은 home 엔드포인트 사용
    return getHomePosts(page: page, size: size);
  }

  /// 추천 게시물을 가져옵니다.
  Future<List<Map<String, dynamic>>> getRecommendedPosts({
    int page = 0,
    int size = 10,
  }) async {
    try {
      print('[BlogService] Fetching recommended posts: page=$page, size=$size');

      final token = await AuthService().getToken();
      final uri = Uri.parse(
        '$_baseUrl/api/posts/recommendation?page=$page&size=$size',
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
        print(
          '[BlogService] Successfully fetched ${posts.length} recommended posts',
        );

        // 포스트가 없으면 home으로 fallback
        if (posts.isEmpty) {
          print('[BlogService] No recommended posts, falling back to home');
          return getHomePosts(page: page, size: size);
        }

        return posts;
      } else {
        print('[BlogService] Error ${response.statusCode}: ${response.body}');
        // 추천 게시물이 없으면 home으로 fallback
        return getHomePosts(page: page, size: size);
      }
    } catch (e) {
      print('[BlogService] Exception: $e');
      // 오류 시 home으로 fallback
      return getHomePosts(page: page, size: size);
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
