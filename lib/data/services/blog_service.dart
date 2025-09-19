import 'dart:convert';
import 'dart:io';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:http/http.dart' as http;

class BlogService {
  static final String _baseUrl = ApiServiceBase.baseUrl;

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

    final requestBody = {
      'title': postData['title'] ?? '',
      'content': postData['content'] ?? '',
      'tags': postData['tags'] ?? <String>[],
      'isPublic': postData['isPublic'] ?? true,
      'thumbnailImageUrl': postData['thumbnailUrl'],
      'metadata': postData['metadata'] ?? {},
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

    final requestBody = <String, dynamic>{
      'title': postData['title'] ?? '',
      'content': postData['content'] ?? '',
      'tags': postData['tags'] ?? <String>[],
      'isPublic': postData['isPublic'] ?? true,
      'metadata': postData['metadata'] ?? {},
    };

    if (thumbnailImageId != null) {
      requestBody['thumbnailImageId'] = thumbnailImageId;
    }

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

  /// 홈 화면용 추천 블로그 포스트 목록을 가져옵니다.
  /// 블로그 ID를 순차적으로 가져와서 홈 추천을 구현
  Future<List<Map<String, dynamic>>> getHomePosts({
    int page = 0,
    int size = 10,
  }) async {
    try {
      print(
        '[BlogService] Fetching home posts by sequential IDs: page=$page, size=$size',
      );

      final List<Map<String, dynamic>> posts = [];
      final int startId = page * size + 1; // 1부터 시작
      final int endId = startId + size - 1;

      // 블로그 ID를 순차적으로 가져오기
      for (int id = startId; id <= endId; id++) {
        try {
          final post = await getPostDetail(id.toString());
          posts.add(post);
        } catch (e) {
          print('[BlogService] Failed to fetch post $id: $e');
          // 해당 ID의 포스트가 없으면 건너뛰기
          continue;
        }
      }

      print('[BlogService] Successfully fetched ${posts.length} home posts');

      // 포스트가 없으면 fallback 데이터 반환
      if (posts.isEmpty) {
        print('[BlogService] No posts found, returning fallback data');
        return _getFallbackPosts();
      }

      return posts;
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
        final data = json.decode(response.body);
        print('[BlogService] Successfully fetched post detail');
        return data;
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
  List<Map<String, dynamic>> _getFallbackPosts() {
    return [
      {
        'id': '1',
        'title': '모태솔로지만연애를해야할까///',
        'content': '안녕하세여..오늘은 모태솔로지만연애는하고싶어후 기로돌아왓어요다들키스씬은보셧나요저는보다가…',
        'author': '수최영',
        'username': 'affection-jk',
        'thumbnailImageId': '1',
        'thumbnailImageUrl': 'assets/images/feed2.png',
        'accessLevel': 'PUBLIC',
        'createdAt': DateTime.now().toIso8601String(),
        'likeCount': 123,
        'commentCount': 45,
        'viewCount': 256,
      },
      {
        'id': '2',
        'title': '새로운 시작',
        'content': '오늘부터 새로운 마음으로 시작해보려고 합니다. 여러분의 응원 부탁드려요!',
        'author': '김철수',
        'username': 'kimcs123',
        'thumbnailImageId': '2',
        'thumbnailImageUrl': 'assets/images/feed3.png',
        'accessLevel': 'PUBLIC',
        'createdAt':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'likeCount': 67,
        'commentCount': 23,
        'viewCount': 134,
      },
      {
        'id': '3',
        'title': '여행 후기',
        'content': '제주도 여행 다녀왔습니다! 정말 아름다운 풍경이었어요.',
        'author': '이영희',
        'username': 'leeyh456',
        'thumbnailImageId': '3',
        'thumbnailImageUrl': 'assets/images/feed4.png',
        'accessLevel': 'PUBLIC',
        'createdAt':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'likeCount': 89,
        'commentCount': 34,
        'viewCount': 189,
      },
      {
        'id': '4',
        'title': '오늘 날씨가 너무 좋아서 산책했어요',
        'content': '오늘 날씨가 정말 좋아서 산책을 다녀왔어요. 햇살이 따뜻하고 바람도 시원해서 정말 기분이 좋았어요.',
        'author': '김여름',
        'username': 'kimsummer',
        'thumbnailImageId': '4',
        'thumbnailImageUrl': 'assets/images/feed1.jpg',
        'accessLevel': 'PUBLIC',
        'createdAt':
            DateTime.now().subtract(const Duration(hours: 4)).toIso8601String(),
        'likeCount': 45,
        'commentCount': 12,
        'viewCount': 98,
      },
      {
        'id': '5',
        'title': '새로운 카페를 발견했어요!',
        'content': '새로운 카페를 발견했어요! 분위기도 좋고 커피도 맛있어서 정말 만족스러웠어요.',
        'author': '박카페',
        'username': 'parkcafe',
        'thumbnailImageId': '5',
        'thumbnailImageUrl': 'assets/images/feed5.jpg',
        'accessLevel': 'PUBLIC',
        'createdAt':
            DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
        'likeCount': 78,
        'commentCount': 19,
        'viewCount': 156,
      },
    ];
  }
}
