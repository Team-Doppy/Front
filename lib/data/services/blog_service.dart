import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:doppy/data/models/system_category_keys.dart';

class BlogService {
  static final BlogService _instance = BlogService._internal();
  factory BlogService() => _instance;
  BlogService._internal();

  final Dio _dio = BaseApiService().dio;

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
    debugPrint('[BlogService] 로그아웃 - 모든 캐시 초기화 완료');
  }

  // 🎯 _buildSummaryFromContent 메서드 제거됨 (summary 필드 제거)

  /// 프로필 피드 조회 (통합 API: 스키마 + 포스트)
  /// 응답: { success, data: ProfileFeedSchemaAndPostsResponse, message }
  Future<Map<String, dynamic>> getProfileFeed(
    String username, {
    int page = 0,
    int size = 20,
    String? phase,
    String? lifePhase,
    String? accessLevel,
    bool preview = false,
  }) async {
    try {
      final queryParameters = <String, dynamic>{'page': page, 'size': size};
      if (phase != null && phase.isNotEmpty) queryParameters['phase'] = phase;
      if (lifePhase != null && lifePhase.isNotEmpty) {
        queryParameters['lifePhase'] = lifePhase;
      }
      if (accessLevel != null && accessLevel.isNotEmpty) {
        queryParameters['accessLevel'] = accessLevel;
      }
      if (preview) queryParameters['preview'] = true;

      debugPrint(
        '[BlogService] getProfileFeed 요청: username=$username, '
        'queryParameters=$queryParameters',
      );

      final response = await _dio.get(
        '/api/profile/feed/$username',
        queryParameters: queryParameters,
      );

      final responseData = response.data as Map<String, dynamic>;
      // { success, data, message } 형태에서 data 추출
      Map<String, dynamic> result;
      if (responseData.containsKey('data')) {
        result = responseData['data'] as Map<String, dynamic>;
      } else {
        // data 필드가 없으면 전체 응답 반환 (하위 호환성)
        result = responseData;
      }

      // ✅ 디버그 로그: 서버 응답 확인
      final postsData = result['posts'] as Map<String, dynamic>?;
      final postsList = postsData?['posts'] as List?;
      debugPrint(
        '[BlogService] getProfileFeed 응답: '
        'totalElements=${postsData?['totalElements']}, '
        'posts.length=${postsList?.length ?? 0}, '
        'hasNext=${postsData?['hasNext']}',
      );

      return result;
    } catch (e) {
      debugPrint('[BlogService] 프로필 피드 로드 실패: $e');

      if (e is DioException) {
        // 네트워크 연결 오류는 DioException을 그대로 전달
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          rethrow; // DioException 그대로 전달
        }
        // HTTP 상태 코드가 있는 경우에만 Exception 변환
        if (e.response?.statusCode == 404) {
          throw Exception('사용자를 찾을 수 없습니다.');
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          rethrow; // 기타 네트워크 에러도 그대로 전달
        }
      }
      rethrow;
    }
  }

  /// 프로필 피드 섹션 조회 (전체 탭: phase별 6개 + 더보기)
  /// 응답: { success, data: ProfileFeedSectionsResponse, message }
  ///
  /// - endpoint: GET /api/profile/feed/{username}/sections
  Future<Map<String, dynamic>> getProfileFeedSections(String username) async {
    try {
      final response = await _dio.get('/api/profile/feed/$username/sections');

      final responseData = response.data as Map<String, dynamic>;
      // { success, data, message } 형태에서 data 추출
      if (responseData.containsKey('data')) {
        return responseData['data'] as Map<String, dynamic>;
      }
      // data 필드가 없으면 전체 응답 반환 (하위 호환성)
      return responseData;
    } catch (e) {
      debugPrint('[BlogService] 프로필 피드 섹션 로드 실패: $e');

      if (e is DioException) {
        // 네트워크 연결 오류는 DioException을 그대로 전달
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          rethrow; // DioException 그대로 전달
        }
        // HTTP 상태 코드가 있는 경우에만 Exception 변환
        if (e.response?.statusCode == 404) {
          throw Exception('사용자를 찾을 수 없습니다.');
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          rethrow; // 기타 네트워크 에러도 그대로 전달
        }
      }
      rethrow;
    }
  }

  /// 섹션(phase) 표시 순서 저장 (본인만)
  /// PUT /api/profile/feed/section-order
  Future<void> saveProfileFeedSectionOrder(List<String> phaseOrder) async {
    try {
      await _dio.put(
        '/api/profile/feed/section-order',
        data: <String, dynamic>{'phaseOrder': phaseOrder},
      );
    } catch (e) {
      debugPrint('[BlogService] 섹션 순서 저장 실패: $e');
      rethrow;
    }
  }

  /// 포스트 순서 변경
  Future<Map<String, dynamic>> reorderPosts(List<int> postIds) async {
    debugPrint('[BlogService] 포스트 순서 변경 요청: ${postIds.length}개');

    try {
      final response = await _dio.put(
        '/api/posts/reorder',
        data: {'postIds': postIds},
      );

      debugPrint('[BlogService] 포스트 순서 변경 성공');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[BlogService] 포스트 순서 변경 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 포스트 공개범위 변경
  Future<void> updatePostAccessLevel({
    required int postId,
    required String accessLevel, // SystemCategoryKeys.public, private, friends
    // 그룹 기능 제거로 인해 sharedGroupIds 파라미터 제거
  }) async {
    debugPrint('[BlogService] 공개범위 변경 요청: $postId -> $accessLevel');

    try {
      final data = <String, dynamic>{'accessLevel': accessLevel};

      // 그룹 기능 제거로 인해 GROUPS 처리 제거

      await _dio.patch('/api/posts/$postId/access-level', data: data);

      debugPrint('[BlogService] 공개범위 변경 성공: $postId -> $accessLevel');
    } catch (e) {
      debugPrint('[BlogService] 공개범위 변경 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('포스트를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 여러 포스트의 공개범위를 배치로 변경
  ///
  /// [postIds] - 변경할 포스트 ID 리스트
  /// [accessLevel] - 변경할 공개범위 (SystemCategoryKeys.public, private, friends)
  ///
  /// 응답: 변경된 포스트 목록
  Future<List<Map<String, dynamic>>> batchUpdatePostsAccessLevel({
    required List<int> postIds,
    required String accessLevel,
    // 그룹 기능 제거로 인해 sharedGroupIds 파라미터 제거
  }) async {
    try {
      debugPrint(
        '[BlogService] 여러 포스트 공개범위 배치 변경 시작 - 포스트 수: ${postIds.length}, accessLevel: $accessLevel',
      );

      final data = <String, dynamic>{
        'postIds': postIds,
        'accessLevel': accessLevel,
      };

      // 그룹 기능 제거로 인해 GROUPS 처리 제거

      final response = await _dio.patch(
        '/api/posts/batch/access-level',
        data: data,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint(
        '[BlogService] 여러 포스트 공개범위 배치 변경 응답 상태: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        List<Map<String, dynamic>> updatedPosts;

        if (responseData is List) {
          updatedPosts = responseData.cast<Map<String, dynamic>>();
        } else if (responseData is Map<String, dynamic>) {
          final postsData =
              responseData['posts'] ??
              responseData['data'] ??
              responseData['content'] ??
              [];
          if (postsData is List) {
            updatedPosts = postsData.cast<Map<String, dynamic>>();
          } else {
            updatedPosts = [];
          }
        } else {
          updatedPosts = [];
        }

        debugPrint(
          '[BlogService] 여러 포스트 공개범위 배치 변경 성공 - 변경된 포스트 수: ${updatedPosts.length}',
        );
        return updatedPosts;
      } else {
        throw Exception('여러 포스트 공개범위 배치 변경 실패: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('[BlogService] 여러 포스트 공개범위 배치 변경 에러: $e');
      debugPrint('[BlogService] StackTrace: $stackTrace');

      if (e is DioException) {
        debugPrint('[BlogService] DioException Type: ${e.type}');
        debugPrint('[BlogService] Status Code: ${e.response?.statusCode}');
        debugPrint('[BlogService] Response Data: ${e.response?.data}');
        debugPrint('[BlogService] Request Path: ${e.requestOptions.path}');
        debugPrint('[BlogService] Request Data: ${e.requestOptions.data}');
        debugPrint(
          '[BlogService] Request Headers: ${e.requestOptions.headers}',
        );

        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('요청한 리소스를 찾을 수 없습니다.');
        } else {
          final statusCode = e.response?.statusCode ?? 0;
          final errorMessage = e.response?.data?['message'] ?? '서버 오류가 발생했습니다.';
          throw Exception('$errorMessage (상태 코드: $statusCode)');
        }
      }
      rethrow;
    }
  }

  /// 여러 포스트를 배치로 PRIVATE(나만보기)로 변경
  ///
  /// [postIds] - 변경할 포스트 ID 리스트
  ///
  /// 응답: 변경된 포스트 목록
  /// @deprecated batchUpdatePostsAccessLevel을 사용하세요
  Future<List<Map<String, dynamic>>> batchMakePostsPrivate(
    List<int> postIds,
  ) async {
    try {
      debugPrint(
        '[BlogService] 여러 포스트 배치로 나만보기 변경 시작 - 포스트 수: ${postIds.length}',
      );

      final response = await _dio.patch(
        '/api/posts/batch/make-private',
        data: {'postIds': postIds},
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint(
        '[BlogService] 여러 포스트 배치로 나만보기 변경 응답 상태: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        List<Map<String, dynamic>> updatedPosts;

        if (data is List) {
          updatedPosts = data.cast<Map<String, dynamic>>();
        } else if (data is Map<String, dynamic>) {
          final postsData =
              data['posts'] ?? data['data'] ?? data['content'] ?? [];
          if (postsData is List) {
            updatedPosts = postsData.cast<Map<String, dynamic>>();
          } else {
            updatedPosts = [];
          }
        } else {
          updatedPosts = [];
        }

        debugPrint(
          '[BlogService] 여러 포스트 배치로 나만보기 변경 성공 - 변경된 포스트 수: ${updatedPosts.length}',
        );
        return updatedPosts;
      } else {
        throw Exception('여러 포스트 배치로 나만보기 변경 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BlogService] 여러 포스트 배치로 나만보기 변경 에러: $e');
      if (e is DioException) {
        debugPrint(
          '[BlogService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
        throw Exception('여러 포스트 배치로 나만보기 변경 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 포스트 썸네일, 타이틀 수정
  ///
  /// [postId] - 수정할 포스트 ID
  /// [thumbnailImageUrl] - 새 썸네일 이미지 URL (선택사항)
  /// [title] - 새 제목 (선택사항)
  ///
  /// 제공된 값만 업데이트되고, null인 값은 변경되지 않습니다.
  Future<void> updatePostThumbnail({
    required int postId,
    String? thumbnailImageUrl,
    String? title,
  }) async {
    debugPrint('[BlogService] 썸네일/타이틀 수정 요청: $postId');

    try {
      // 쿼리 파라미터 구성
      final queryParams = <String, String>{};

      if (thumbnailImageUrl != null && thumbnailImageUrl.isNotEmpty) {
        queryParams['thumbnailImageUrl'] = thumbnailImageUrl;
        debugPrint('[BlogService] - 썸네일: $thumbnailImageUrl');
      }

      if (title != null && title.isNotEmpty) {
        queryParams['title'] = title;
        debugPrint('[BlogService] - 타이틀: $title');
      }

      // 🎯 summary 필드 제거됨

      // 변경할 내용이 없으면 에러
      if (queryParams.isEmpty) {
        throw Exception('수정할 내용이 없습니다.');
      }

      await _dio.put(
        '/api/posts/$postId/thumbnail',
        queryParameters: queryParams,
      );

      debugPrint('[BlogService] 썸네일/타이틀 수정 성공: $postId');
    } catch (e) {
      debugPrint('[BlogService] 썸네일/타이틀/요약 수정 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('포스트를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 포스트 본문(content), 타이틀 수정
  ///
  /// [postId] - 수정할 포스트 ID
  /// [content] - 새 본문 content (blocks 구조)
  /// [title] - 새 제목 (선택사항)
  /// [usedImageUrls] - 사용된 이미지/비디오 URL 목록
  /// [year] - 연도 (선택사항)
  /// [nthWeek] - 주차 (선택사항)
  ///
  // 🎯 summary 필드 제거됨
  Future<void> updatePostContent({
    required int postId,
    required Map<String, dynamic> content,
    String? title,
    required List<String> usedImageUrls,
    required List<String> mentionedUsernames,
    int? year,
    int? nthWeek,
  }) async {
    debugPrint('[BlogService] 본문/타이틀 수정 요청: $postId');

    try {
      final requestBody = <String, dynamic>{
        'content': content,
        'usedImageUrls': usedImageUrls,
        // ✅ 항상 포함 (서버 스펙: [] 또는 null 허용)
        'mentionedUsernames': mentionedUsernames,
      };

      if (title != null && title.isNotEmpty) {
        requestBody['title'] = title;
        debugPrint('[BlogService] - 타이틀: $title');
      }

      // 🎯 연도와 주차 정보 추가 (변경된 경우만)
      if (year != null && nthWeek != null) {
        requestBody['year'] = year;
        requestBody['weekOfYear'] = nthWeek; // 서버 DTO: weekOfYear
        debugPrint('[BlogService] - 연도/주차: year=$year, weekOfYear=$nthWeek');
      }

      debugPrint('[BlogService] - 사용된 미디어: ${usedImageUrls.length}개');

      await _dio.put(
        '/api/posts/$postId/content',
        data: requestBody,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint('[BlogService] 본문/타이틀 수정 성공: $postId');
    } catch (e) {
      debugPrint('[BlogService] 본문/타이틀 수정 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('포스트를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 블로그 포스트를 서버에 업로드합니다.
  ///
  /// [postData] - 포스트 데이터 (제목, 내용, 썸네일 URL, 태그 등)
  /// 반환: 업로드된 포스트의 ID와 메타데이터
  Future<Map<String, dynamic>> uploadPost({
    required Map<String, dynamic> postData,
  }) async {
    debugPrint('[UploadPost] uploading post');

    // 서버 DTO에 맞춰 매핑: title, author, thumbnailImageUrl, content(JsonNode), accessLevel
    // accessLevel은 PostExporter에서 직접 설정한 값만 사용 (PUBLIC | PRIVATE | FRIENDS)
    // visibility 객체는 사용하지 않음
    // 🎯 공통 파싱 유틸리티 사용
    final accessLevel =
        AccessLevelParser.parseAccessLevelString(postData['accessLevel']) ??
        SystemCategoryKeys.public;
    // 그룹 기능 제거로 인해 sharedGroupIds 파싱 제거

    // content(JsonNode) 전송: 문자열이면 decode, 맵/리스트면 그대로 사용
    dynamic contentJson = postData['content'];
    if (contentJson is String && contentJson.isNotEmpty) {
      try {
        contentJson = json.decode(contentJson);
      } catch (_) {
        contentJson = <String, dynamic>{'raw': contentJson};
      }
    }

    // 🎯 summary 필드 제거됨

    final requestBody = <String, dynamic>{
      'title': postData['title'] ?? '',
      'author': postData['author'] ?? '',
      'thumbnailImageUrl': postData['thumbnailImageUrl'] ?? '',
      'content': contentJson ?? const <String, dynamic>{'nodes': []},
      'accessLevel': accessLevel,
      'categoryId': postData['categoryId'] ?? 0,

      if (postData['usedImageUrls'] != null)
        'usedImageUrls': List<String>.from(postData['usedImageUrls'] as List),
      // ✅ mentionedUsernames는 항상 포함 (없으면 빈 배열)
      'mentionedUsernames':
          (postData['mentionedUsernames'] is List)
              ? List<String>.from(postData['mentionedUsernames'] as List)
              : <String>[],

      // 🎯 그리드 셀 지정 (우선순위: phase+slotIndex > year+weekOfYear > postedAt > 생략)
      // 1. phase + slotIndex (최우선)
      if (postData['phase'] != null) 'phase': postData['phase'] as String,
      if (postData['slotIndex'] != null)
        'slotIndex': postData['slotIndex'] as int,
      // 2. year + weekOfYear
      if (postData['year'] != null) 'year': postData['year'] as int,
      if (postData['weekOfYear'] != null)
        'weekOfYear': postData['weekOfYear'] as int,
      // 3. postedAt
      if (postData['postedAt'] != null)
        'postedAt': postData['postedAt'] as String,

      // 🎯 작성 모드 (lifePhase)
      if (postData['lifePhase'] != null)
        'lifePhase': postData['lifePhase'] as String,

      // ✅ API 명세: 편지 모드 - recipientUserId
      if (postData['recipientUserId'] != null)
        'recipientUserId': postData['recipientUserId'] as int,

      // ✅ 편지 모드 - recipientUsername (클라에서 username을 그대로 보내기)
      if (postData['recipientUsername'] != null)
        'recipientUsername': postData['recipientUsername'] as String,

      // ✅ API 명세: 글 타입 (writingType)
      if (postData['writingType'] != null)
        'writingType': postData['writingType'] as String,

      // 그룹 기능 제거로 인해 GROUPS 처리 제거
    };

    debugPrint('[UploadPost] ===== 최종 요청 본문 =====');
    debugPrint('[UploadPost] accessLevel: $accessLevel');
    // 그룹 기능 제거로 인해 GROUPS 디버그 로그 제거
    debugPrint('[UploadPost] request body: ${json.encode(requestBody)}');

    try {
      final response = await _dio.post(
        '/api/posts',
        data: requestBody,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint(
        '[UploadPost] success ${response.statusCode} body=${response.data}',
      );

      _invalidateMyPostsCache();

      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException) {
        debugPrint(
          '[UploadPost] error ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'post upload failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 단일 포스트의 content + 메타데이터 조회 (isLiked, likeCount, commentCount 포함)
  Future<Map<String, dynamic>> getPostContent(String postId) async {
    try {
      final response = await _dio.get(
        '/api/posts/$postId/content',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );

      final decoded = response.data;
      if (decoded is Map<String, dynamic>) {
        debugPrint('[BlogService] getPostContent 응답 키: ${decoded.keys}');

        // 🎯 전체 응답 반환 (isLiked, likeCount, commentCount, content 모두 포함)
        return decoded;
      }
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('[BlogService] getPostContent error: $e');

      if (e is DioException) {
        throw HttpException(
          'get content failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 블로그 메타데이터만 조회 (content 제외)
  ///
  /// title, thumbnailImageUrl, author,
  /// accessLevel, viewCount, likeCount, isLiked, createdAt, updatedAt 등의 정보만 반환.
  /// 조회수 증가 안함.
  Future<Map<String, dynamic>> getPostMetadata(String postId) async {
    try {
      debugPrint('[BlogService] 메타데이터 조회: postId=$postId');

      final response = await _dio.get(
        '/api/posts/$postId/metadata',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        debugPrint('[BlogService] 메타데이터 로드 성공');
        debugPrint('  - 제목: ${data['title']}');
        debugPrint('  - 썸네일: ${data['thumbnailImageUrl']}');
        // 🎯 summary 필드 제거됨
        return data;
      }

      return <String, dynamic>{};
    } catch (e) {
      debugPrint('[BlogService] getPostMetadata error: $e');

      if (e is DioException) {
        throw HttpException(
          'get metadata failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 포스트를 삭제합니다.
  ///
  /// [postId] - 삭제할 포스트의 ID
  Future<void> deletePost(String postId) async {
    debugPrint('[DeletePost] deleting post $postId');

    try {
      await _dio.delete(
        '/api/posts/$postId',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint('[DeletePost] success');
    } catch (e) {
      if (e is DioException) {
        debugPrint(
          '[DeletePost] error ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'post delete failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 홈 화면용 블로그 포스트 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getFriendsPosts({
    int page = 0,
    int size = 10,
    bool forceRefresh = false,
  }) async {
    try {
      final response = await _dio.get(
        '/api/posts/friends',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);

      return posts;
    } catch (e) {
      // 네트워크 에러는 상위로 전파 (빈 배열 반환하지 않음)
      rethrow;
    }
  }

  /// 추천 게시물을 가져옵니다.
  Future<List<Map<String, dynamic>>> getRecommendedPosts({
    int page = 0,
    int size = 10,
  }) async {
    try {
      final response = await _dio.get(
        '/api/posts/recommendation',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);

      // 🎯 fallback 제거: 전체글 새로고침 시 친구글 API 호출 방지
      // 포스트가 없어도 빈 배열 반환 (친구글 API 호출하지 않음)
      return posts;
    } catch (e) {
      // 네트워크 에러는 상위로 전파 (fallback 하지 않음)
      rethrow;
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
        debugPrint('[BlogService] Using cached my posts: key=$cacheKey');
        return _myPostsCache[cacheKey]!;
      }

      debugPrint('[BlogService] Fetching my posts: page=$page, size=$size');

      final response = await _dio.get(
        '/api/posts/my',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
      debugPrint('[BlogService] Successfully fetched ${posts.length} my posts');

      // 캐시 저장
      _myPostsCache[cacheKey] = posts;
      _myPostsCachedAt = DateTime.now();
      return posts;
    } catch (e) {
      if (e is DioException) {
        debugPrint(
          '[BlogService] Error ${e.response?.statusCode}: ${e.response?.data}',
        );
        throw Exception('Failed to fetch my posts: ${e.response?.statusCode}');
      }
      debugPrint('[BlogService] Exception: $e');
      throw Exception('Failed to fetch my posts: $e');
    }
  }

  /// 내가 좋아요한 게시물 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getMyLikedPosts({
    int page = 0,
    int size = 20,
  }) async {
    try {
      debugPrint(
        '[BlogService] Fetching my liked posts: page=$page, size=$size',
      );

      final response = await _dio.get(
        '/api/posts/my/liked',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(
        data['content'] ?? data['posts'] ?? data as List? ?? [],
      );
      debugPrint(
        '[BlogService] Successfully fetched ${posts.length} liked posts',
      );
      return posts;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          debugPrint('[BlogService] No liked posts found (404)');
          return []; // 빈 리스트 반환
        }
        debugPrint(
          '[BlogService] Error ${e.response?.statusCode}: ${e.response?.data}',
        );
        throw Exception(
          'Failed to fetch liked posts: ${e.response?.statusCode}',
        );
      }

      debugPrint('[BlogService] Exception: $e');
      // 404 에러인 경우 빈 리스트 반환 (서버 문제 대응)
      if (e.toString().contains('404')) {
        debugPrint('[BlogService] Returning empty list due to 404 error');
        return [];
      }
      throw Exception('Failed to fetch liked posts: $e');
    }
  }

  Future<Map<String, dynamic>> getPostViewers(
    String postId, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      debugPrint(
        '[BlogService] 포스트 조회자 정보 조회 시작 - 포스트ID: $postId, page: $page, size: $size',
      );

      final response = await _dio.get(
        '/api/posts/$postId/viewers',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint('[BlogService] 포스트 조회자 정보 조회 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final viewerCount = (data['viewers'] as List?)?.length ?? 0;
        debugPrint('[BlogService] 포스트 조회자 정보 조회 성공 - 조회자 수: $viewerCount');
        return data;
      } else {
        throw Exception('포스트 조회자 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BlogService] 포스트 조회자 정보 조회 에러: $e');
      if (e is DioException) {
        debugPrint(
          '[BlogService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
        throw Exception('포스트 조회자 정보 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 블로그 조르기
  ///
  /// [targetUsername] - 조르기를 받을 사용자의 username
  ///
  /// 응답 구조:
  /// {
  ///   "success": true,
  ///   "message": "블로그 조르기가 전송되었습니다."
  /// }
  Future<Map<String, dynamic>> nudge(String targetUsername) async {
    try {
      debugPrint('[BlogService] 블로그 조르기 요청: $targetUsername');

      final response = await _dio.post(
        '/api/blog/nudge',
        data: {'targetUsername': targetUsername},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint('[BlogService] 블로그 조르기 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        debugPrint('[BlogService] 블로그 조르기 성공: ${data['message']}');
        return data;
      } else {
        throw Exception('블로그 조르기 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BlogService] 블로그 조르기 에러: $e');
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data as Map<String, dynamic>?;
        final errorMessage = responseData?['message'] ?? '블로그 조르기 실패';

        debugPrint('[BlogService] Dio 에러: $statusCode - $errorMessage');

        if (statusCode == 400) {
          throw Exception(errorMessage);
        } else if (statusCode == 404) {
          throw Exception(errorMessage);
        } else if (statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          throw Exception('$errorMessage (상태 코드: $statusCode)');
        }
      }
      rethrow;
    }
  }

  /// 군인 그리드 셀 포스트 목록 조회 (GET /api/military/postlist)
  /// 요청: phase, slotIndex 필수
  /// 응답: { data: { posts: BlogResponse[], phase: string, slotIndex: int } }
  Future<List<Map<String, dynamic>>> getMilitaryPostList({
    required String phase,
    required int slotIndex,
  }) async {
    try {
      debugPrint(
        '[BlogService] 군인 그리드 포스트 목록 조회: phase=$phase, slotIndex=$slotIndex',
      );

      final queryParams = <String, dynamic>{
        'phase': phase,
        'slotIndex': slotIndex,
      };

      final response = await _dio.get(
        '/api/military/postlist',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>;

        // { success, data, message } 형태에서 data 추출
        final data =
            responseData.containsKey('data')
                ? responseData['data'] as Map<String, dynamic>
                : responseData;

        // posts 배열 추출
        final posts = data['posts'] as List<dynamic>? ?? [];
        final postsList =
            posts.map((post) => post as Map<String, dynamic>).toList();

        debugPrint('[BlogService] 군인 그리드 포스트 목록 조회 성공: ${postsList.length}개');
        return postsList;
      }

      throw Exception('군인 그리드 포스트 목록 조회 실패: ${response.statusCode}');
    } catch (e) {
      debugPrint('[BlogService] 군인 그리드 포스트 목록 조회 실패: $e');

      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data as Map<String, dynamic>?;
        final errorMessage = responseData?['message'] ?? '주차 포스트 목록 조회 실패';

        if (statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (statusCode == 404) {
          throw Exception('데이터를 찾을 수 없습니다.');
        } else {
          throw Exception('$errorMessage (상태 코드: $statusCode)');
        }
      }
      rethrow;
    }
  }
}
