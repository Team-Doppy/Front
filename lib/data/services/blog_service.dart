import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/utils/access_level_parser.dart';

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

  /// content(JSON or raw string)에서 최대 5줄 요약을 생성
  String _buildSummaryFromContent(dynamic content) {
    try {
      String raw = '';
      if (content is Map) {
        // SuperEditor exported structure: { nodes: [ {text: ...}, ... ] }
        final nodes = (content['nodes'] as List?) ?? const [];
        final lines = <String>[];
        for (final n in nodes) {
          if (n is Map) {
            final t = (n['text'] ?? n['label'] ?? '').toString().trim();
            if (t.isNotEmpty) lines.add(t);
            if (lines.length >= 5) break;
          }
        }
        raw = lines.join('\n');
      } else if (content is String) {
        raw = content;
      }
      if (raw.isEmpty) return '';
      final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final parts =
          normalized.split('\n').where((e) => e.trim().isNotEmpty).toList();
      return parts.take(5).join('\n');
    } catch (_) {
      return '';
    }
  }

  /// 새로운 프로필 피드 API 호출
  Future<Map<String, dynamic>> getProfileFeed(String username) async {
    debugPrint('[BlogService] 프로필 피드 요청: $username');

    try {
      final response = await _dio.get('/api/profile/$username/feed');

      debugPrint('[BlogService] 프로필 피드 응답 상태: ${response.statusCode}');
      debugPrint('[BlogService] 프로필 피드 응답 전체: ${response.data}');
      debugPrint(
        '[BlogService] 프로필 피드 로드 성공: ${response.data['data']?['categories']?.length ?? 0}개 카테고리',
      );

      return response.data;
    } catch (e) {
      debugPrint('[BlogService] 프로필 피드 로드 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          throw Exception('사용자를 찾을 수 없습니다.');
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 프로필 스키마 조회 (카테고리/매핑 전용)
  Future<Map<String, dynamic>> getProfileSchema(String username) async {
    try {
      final response = await _dio.get('/api/profile/feed/schema/$username');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[BlogService] 프로필 스키마 로드 실패: $e');

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

  /// 프로필 포스트 페이지 조회 (페이지네이션)
  Future<Map<String, dynamic>> getProfilePosts(
    String username, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/profile/feed/posts/$username',
        queryParameters: {'page': page, 'size': size},
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[BlogService] 프로필 포스트 로드 실패: $e');

      if (e is DioException) {
        // 네트워크 연결 오류는 DioException을 그대로 전달
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          rethrow; // DioException 그대로 전달
        }
        
        // 400 에러인 경우, 서버 응답을 확인하여 빈 상태로 처리
        if (e.response?.statusCode == 400) {
          final responseData = e.response?.data;
          if (responseData is Map<String, dynamic>) {
            final message = responseData['message']?.toString() ?? '';
            // "포스트 데이터 조회 중 오류" 메시지인 경우 빈 응답 반환 (회원가입 직후 포스트 없음)
            if (message.contains('포스트 데이터 조회 중 오류') || 
                message.contains('포스트') && message.contains('오류')) {
              debugPrint('[BlogService] 포스트 없음으로 빈 응답 반환');
              return {
                'success': true,
                'data': {
                  'posts': [],
                  'totalPages': 0,
                  'totalElements': 0,
                  'pageNumber': page,
                  'pageSize': size,
                },
              };
            }
          }
          // 기타 400 에러는 그대로 전달
          rethrow;
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

  /// 특정 포스트 중심 오프셋 조회
  /// 포스트 ID를 중심으로 앞뒤 포스트를 조회합니다.
  Future<Map<String, dynamic>> getProfilePostsAround(
    String username,
    String postId, {
    int size = 20,
  }) async {
    debugPrint(
      '[BlogService] 프로필 포스트 오프셋 조회: $username postId=$postId size=$size',
    );

    try {
      final response = await _dio.get(
        '/api/profile/feed/posts/$username/around/$postId',
        queryParameters: {'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data as Map<String, dynamic>;

      debugPrint('[BlogService] 오프셋 조회 응답 상태: ${response.statusCode}');
      if (data.containsKey('data') && data['data'] is Map) {
        final dataMap = data['data'] as Map<String, dynamic>;
        if (dataMap.containsKey('posts') && dataMap['posts'] is List) {
          final posts = dataMap['posts'] as List;
          debugPrint('[BlogService] 오프셋 조회 포스트 개수: ${posts.length}');
        }
      }

      return data;
    } catch (e) {
      debugPrint('[BlogService] 프로필 포스트 오프셋 조회 실패: $e');

      if (e is DioException) {
        if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          rethrow;
        }
        if (e.response?.statusCode == 404) {
          throw Exception('포스트를 찾을 수 없습니다.');
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// 사용자의 카테고리 목록 조회
  Future<List<Map<String, dynamic>>> getUserCategories(String username) async {
    debugPrint('[BlogService] 카테고리 목록 조회 요청: $username');

    try {
      final response = await _dio.get('/api/categories/user/$username');

      final data = response.data;
      debugPrint('[BlogService] 카테고리 목록 조회 성공: ${data.length}개');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[BlogService] 카테고리 목록 조회 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('사용자를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 카테고리 생성
  Future<Map<String, dynamic>> createCategory({
    required String name,
    required bool isPrivate,
    required String description,
  }) async {
    debugPrint('[BlogService] 카테고리 생성 요청: $name');

    try {
      final response = await _dio.post(
        '/api/categories',
        data: {
          'name': name,
          'is_private': isPrivate,
          'description': description,
        },
      );

      final data = response.data;
      debugPrint('[BlogService] 카테고리 생성 성공: ${data['data']?['name']}');
      return data;
    } catch (e) {
      debugPrint('[BlogService] 카테고리 생성 실패: $e');

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

  /// 카테고리 삭제
  Future<void> deleteCategory(int categoryId) async {
    debugPrint('[BlogService] 카테고리 삭제 요청: $categoryId');

    try {
      await _dio.delete('/api/categories/$categoryId');

      debugPrint('[BlogService] 카테고리 삭제 성공: $categoryId');
    } catch (e) {
      debugPrint('[BlogService] 카테고리 삭제 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '카테고리를 삭제할 수 없습니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('카테고리를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 카테고리 이름 수정
  Future<void> updateCategoryName({
    required int categoryId,
    required String name,
  }) async {
    debugPrint('[BlogService] 카테고리 이름 수정 요청: id=$categoryId, name=$name');
    try {
      await _dio.put('/api/categories/$categoryId', data: {'name': name});
      debugPrint('[BlogService] 카테고리 이름 수정 성공: $categoryId');
    } catch (e) {
      debugPrint('[BlogService] 카테고리 이름 수정 실패: $e');
      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('카테고리를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 카테고리 순서 변경
  Future<void> reorderCategories(List<int> orderedIds) async {
    debugPrint('[BlogService] 카테고리 순서 변경 요청: $orderedIds');

    try {
      final response = await _dio.put(
        '/api/categories/reorder',
        data: json.encode({'orderedIds': orderedIds}),
      );

      debugPrint('[BlogService] 카테고리 순서 변경 성공');
      if (response.data != null && response.data.toString().isNotEmpty) {
        debugPrint('[BlogService] 서버 응답 본문: ${response.data}');
      }
    } catch (e) {
      debugPrint('[BlogService] 카테고리 순서 변경 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          if (e.response?.data != null) {
            debugPrint('[BlogService] 실패 응답 본문: ${e.response?.data}');
          }
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 포스트를 다른 카테고리로 이동 (명세 반영)
  Future<void> movePostToCategory({
    required int postId,
    required int targetCategoryId,
    int? targetPosition,
  }) async {
    debugPrint(
      '[BlogService] 포스트 이동 요청: $postId -> $targetCategoryId (pos=$targetPosition)',
    );

    try {
      await _dio.put(
        '/api/categories/posts/$postId/move',
        data: {
          'targetCategoryId': targetCategoryId,
          if (targetPosition != null) 'targetPosition': targetPosition,
        },
      );

      debugPrint('[BlogService] 포스트 이동 성공: $postId -> $targetCategoryId');
    } catch (e) {
      debugPrint('[BlogService] 포스트 이동 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('포스트 또는 카테고리를 찾을 수 없습니다.');
        } else {
          throw Exception('서버 오류가 발생했습니다. (${e.response?.statusCode})');
        }
      }
      rethrow;
    }
  }

  /// 카테고리 내 포스트 순서 변경
  Future<void> reorderPostsInCategory({
    required int categoryId,
    required List<int> orderedIds,
  }) async {
    debugPrint('[BlogService] 포스트 순서 변경 요청: 카테고리 $categoryId');

    try {
      await _dio.put(
        '/api/categories/$categoryId/posts/reorder',
        data: {'orderedIds': orderedIds},
      );

      debugPrint('[BlogService] 포스트 순서 변경 성공: 카테고리 $categoryId');
    } catch (e) {
      debugPrint('[BlogService] 포스트 순서 변경 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else if (e.response?.statusCode == 404) {
          throw Exception('카테고리를 찾을 수 없습니다.');
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
    required String accessLevel, // 'PRIVATE', 'PUBLIC', 'GROUPS'
    List<int>? sharedGroupIds, // GROUPS일 때만 필요
  }) async {
    debugPrint('[BlogService] 공개범위 변경 요청: $postId -> $accessLevel');

    try {
      final data = <String, dynamic>{'accessLevel': accessLevel};

      if (accessLevel == 'GROUPS' && sharedGroupIds != null) {
        data['sharedGroupIds'] = sharedGroupIds;
      }

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
  /// [accessLevel] - 변경할 공개범위 ('PUBLIC', 'PRIVATE', 'FRIENDS', 'GROUPS')
  /// [sharedGroupIds] - GROUPS일 때만 필요한 그룹 ID 리스트
  ///
  /// 응답: 변경된 포스트 목록
  Future<List<Map<String, dynamic>>> batchUpdatePostsAccessLevel({
    required List<int> postIds,
    required String accessLevel,
    List<int>? sharedGroupIds,
  }) async {
    try {
      debugPrint(
        '[BlogService] 여러 포스트 공개범위 배치 변경 시작 - 포스트 수: ${postIds.length}, accessLevel: $accessLevel',
      );

      final data = <String, dynamic>{
        'postIds': postIds,
        'accessLevel': accessLevel,
      };

      // GROUPS일 때만 sharedGroupIds 추가
      if (accessLevel == 'GROUPS' && sharedGroupIds != null) {
        data['sharedGroupIds'] = sharedGroupIds;
      }

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

  /// 포스트 썸네일, 타이틀, 요약 수정
  ///
  /// [postId] - 수정할 포스트 ID
  /// [thumbnailImageUrl] - 새 썸네일 이미지 URL (선택사항)
  /// [title] - 새 제목 (선택사항)
  /// [summary] - 새 요약 (선택사항)
  ///
  /// 제공된 값만 업데이트되고, null인 값은 변경되지 않습니다.
  Future<void> updatePostThumbnail({
    required int postId,
    String? thumbnailImageUrl,
    String? title,
    String? summary,
  }) async {
    debugPrint('[BlogService] 썸네일/타이틀/요약 수정 요청: $postId');

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

      if (summary != null && summary.isNotEmpty) {
        queryParams['summary'] = summary;
        debugPrint('[BlogService] - 요약: $summary');
      }

      // 변경할 내용이 없으면 에러
      if (queryParams.isEmpty) {
        throw Exception('수정할 내용이 없습니다.');
      }

      await _dio.put(
        '/api/posts/$postId/thumbnail',
        queryParameters: queryParams,
      );

      debugPrint('[BlogService] 썸네일/타이틀/요약 수정 성공: $postId');
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
  ///
  /// 참고: summary(요약)는 썸네일 수정 API에서만 변경 가능
  Future<void> updatePostContent({
    required int postId,
    required Map<String, dynamic> content,
    String? title,
    required List<String> usedImageUrls,
    required List<String> mentionedUsernames,
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
    // accessLevel은 PostExporter에서 직접 설정한 값만 사용 (PUBLIC | PRIVATE | FRIENDS | GROUPS)
    // visibility 객체는 사용하지 않음
    // 🎯 공통 파싱 유틸리티 사용
    final accessLevel =
        AccessLevelParser.parseAccessLevelString(postData['accessLevel']) ??
        'PUBLIC';
    final sharedGroupIds = AccessLevelParser.parseSharedGroupIds(
      postData['sharedGroupIds'],
    );

    // content(JsonNode) 전송: 문자열이면 decode, 맵/리스트면 그대로 사용
    dynamic contentJson = postData['content'];
    if (contentJson is String && contentJson.isNotEmpty) {
      try {
        contentJson = json.decode(contentJson);
      } catch (_) {
        contentJson = <String, dynamic>{'raw': contentJson};
      }
    }

    // summary 생성: postData에 이미 있으면 사용, 없으면 content로부터 최대 5줄 추출
    final String summary =
        (postData['summary'] as String?)?.trim().toString() ??
        _buildSummaryFromContent(contentJson);

    final requestBody = <String, dynamic>{
      'title': postData['title'] ?? '',
      'author': postData['author'] ?? '',
      'thumbnailImageUrl': postData['thumbnailImageUrl'] ?? '',
      'content': contentJson ?? const <String, dynamic>{'nodes': []},
      'accessLevel': accessLevel,
      'summary': summary,
      'categoryId': postData['categoryId'] ?? 0,

      if (postData['usedImageUrls'] != null)
        'usedImageUrls': List<String>.from(postData['usedImageUrls'] as List),
      // ✅ mentionedUsernames는 항상 포함 (없으면 빈 배열)
      'mentionedUsernames':
          (postData['mentionedUsernames'] is List)
              ? List<String>.from(postData['mentionedUsernames'] as List)
              : <String>[],
      // GROUPS인 경우에만 sharedGroupIds 추가
      if (accessLevel == 'GROUPS' &&
          sharedGroupIds != null &&
          sharedGroupIds.isNotEmpty)
        'sharedGroupIds': sharedGroupIds,
    };

    debugPrint('[UploadPost] ===== 최종 요청 본문 =====');
    debugPrint('[UploadPost] accessLevel: $accessLevel');
    if (accessLevel == 'GROUPS' && sharedGroupIds != null) {
      debugPrint('[UploadPost] sharedGroupIds: $sharedGroupIds');
    }
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

  /// 단일 포스트 전체 조회 (스키마 + 내용 + 메타데이터, isLiked, likeCount, commentCount 포함)
  Future<Map<String, dynamic>> getPost(String postId) async {
    try {
      final response = await _dio.get(
        '/api/posts/$postId',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );

      final decoded = response.data;
      if (decoded is Map<String, dynamic>) {
        // 🎯 전체 응답 반환 (title, author, thumbnailImageUrl, content, isLiked, likeCount, commentCount 모두 포함)
        return decoded;
      }
      return <String, dynamic>{};
    } catch (e) {
      if (e is DioException) {
        throw HttpException(
          'get post failed ${e.response?.statusCode}: ${e.response?.data}',
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
  /// title, thumbnailImageUrl, summary, author,
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
        debugPrint('  - 요약: ${data['summary']}');
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

  /// 포스트를 업데이트합니다.
  ///
  /// [postId] - 업데이트할 포스트의 ID
  /// [postData] - 업데이트할 포스트 데이터
  Future<Map<String, dynamic>> updatePost({
    required String postId,
    required Map<String, dynamic> postData,
  }) async {
    debugPrint('[UpdatePost] updating post $postId');

    // 서버 DTO 규격에 맞게 업데이트 바디 구성
    // accessLevel은 postData에서 직접 읽기 (visibility 객체 사용 안 함)
    // 🎯 공통 파싱 유틸리티 사용
    final accessLevel =
        AccessLevelParser.parseAccessLevelString(postData['accessLevel']) ??
        'PUBLIC';
    final sharedGroupIds = AccessLevelParser.parseSharedGroupIds(
      postData['sharedGroupIds'],
    );

    dynamic contentJson = postData['content'];
    if (contentJson is String && contentJson.isNotEmpty) {
      try {
        contentJson = json.decode(contentJson);
      } catch (_) {
        contentJson = <String, dynamic>{'raw': contentJson};
      }
    }

    final String summary =
        (postData['summary'] as String?)?.trim().toString() ??
        _buildSummaryFromContent(contentJson);

    final requestBody = <String, dynamic>{
      'title': postData['title'] ?? '',
      'author': postData['author'] ?? '',
      'thumbnailImageUrl': postData['thumbnailImageUrl'] ?? '',
      'content': contentJson ?? const <String, dynamic>{'nodes': []},
      'accessLevel': accessLevel,
      'summary': summary,
      // GROUPS인 경우에만 sharedGroupIds 추가
      if (accessLevel == 'GROUPS' &&
          sharedGroupIds != null &&
          sharedGroupIds.isNotEmpty)
        'sharedGroupIds': sharedGroupIds,
    };

    debugPrint('[UpdatePost] ===== 최종 요청 본문 =====');
    debugPrint('[UpdatePost] accessLevel: $accessLevel');
    if (accessLevel == 'GROUPS' && sharedGroupIds != null) {
      debugPrint('[UpdatePost] sharedGroupIds: $sharedGroupIds');
    }

    debugPrint('[UpdatePost] request body: ${json.encode(requestBody)}');

    try {
      final response = await _dio.put(
        '/api/posts/$postId',
        data: requestBody,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint('[UpdatePost] success body=${response.data}');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException) {
        debugPrint(
          '[UpdatePost] error ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'post update failed ${e.response?.statusCode}: ${e.response?.data}',
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

  /// 내가 작성한 FRIENDS 공개 범위 포스트 조회 (allFriends 그룹용)
  ///
  /// [page] - 페이지 번호 (0부터 시작)
  /// [size] - 페이지 크기
  /// [includeContent] - content 포함 여부
  ///
  /// Returns: 포스트 목록 (Map<String, dynamic> 리스트)
  Future<List<Map<String, dynamic>>> getMyFriendsPosts({
    int page = 0,
    int size = 10,
    bool includeContent = false,
  }) async {
    try {
      debugPrint(
        '[BlogService] 내 FRIENDS 포스트 조회 시작 - page: $page, size: $size, includeContent: $includeContent',
      );

      final response = await _dio.get(
        '/api/posts/my-friends-posts',
        queryParameters: {
          'page': page,
          'size': size,
          'includeContent': includeContent,
        },
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint(
        '[BlogService] 내 FRIENDS 포스트 조회 응답 상태: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        // 🎯 서버 응답 구조: { "posts": { "content": [...] } }
        final postsData = data['posts'] as Map<String, dynamic>?;
        final postsList = (postsData?['content'] as List?) ?? [];
        debugPrint(
          '[BlogService] 내 FRIENDS 포스트 조회 성공 - 포스트 수: ${postsList.length}',
        );
        return postsList.cast<Map<String, dynamic>>();
      } else {
        throw Exception('내 FRIENDS 포스트 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BlogService] 내 FRIENDS 포스트 조회 에러: $e');
      if (e is DioException) {
        debugPrint(
          '[BlogService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
        throw Exception('내 FRIENDS 포스트 조회 실패: ${e.response?.statusCode}');
      }
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

  /// 홈 피드 데이터를 가져옵니다 (친구글 + 추천글 통합)
  ///
  /// [page] - 페이지 번호 (0부터 시작)
  /// [size] - 페이지 크기
  ///
  /// Returns: {friends: [...], all: [...]} 형태의 Map
  Future<Map<String, List<Map<String, dynamic>>>> getHomeFeedData({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/posts/home',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data as Map<String, dynamic>;

      // 응답 구조 확인: 통합 API는 친구글과 추천글이 분리되어 올 수 있음
      // 가능한 응답 구조:
      // 1. {friends: {content: [...]}, all: {content: [...]}}
      // 2. {friendsPosts: [...], recommendedPosts: [...]}
      // 3. {content: [...]} (단일 리스트로 합쳐진 경우)

      List<Map<String, dynamic>> friendsPosts = [];
      List<Map<String, dynamic>> allPosts = [];

      // 구조 1: friends와 all이 각각 Page 형태
      if (data.containsKey('friends') && data.containsKey('all')) {
        final friendsData = data['friends'] as Map<String, dynamic>?;
        final allData = data['all'] as Map<String, dynamic>?;

        if (friendsData != null) {
          friendsPosts = List<Map<String, dynamic>>.from(
            friendsData['content'] ?? [],
          );
        }
        if (allData != null) {
          allPosts = List<Map<String, dynamic>>.from(allData['content'] ?? []);
        }
      }
      // 구조 2: friendsPosts와 recommendedPosts로 직접 제공
      else if (data.containsKey('friendsPosts') ||
          data.containsKey('recommendedPosts')) {
        friendsPosts = List<Map<String, dynamic>>.from(
          data['friendsPosts'] ?? [],
        );
        allPosts = List<Map<String, dynamic>>.from(
          data['recommendedPosts'] ?? [],
        );
      }
      // 구조 3: 단일 content 리스트 (친구글과 추천글이 합쳐진 경우)
      else if (data.containsKey('content')) {
        final allContent = List<Map<String, dynamic>>.from(
          data['content'] ?? [],
        );
        // 단일 리스트인 경우, 친구글과 추천글을 구분할 방법이 없으므로
        // 전체를 추천글로 처리하고 친구글은 빈 배열로 설정
        // 또는 서버에서 구분 필드(예: isFriendPost)를 제공하는 경우 그에 따라 분리
        allPosts = allContent;
        friendsPosts = [];
      }
      // 기본 구조: content가 직접 있는 경우
      else {
        final content = data['content'] as List?;
        if (content != null) {
          allPosts = content.cast<Map<String, dynamic>>();
        }
      }

      return {'friends': friendsPosts, 'all': allPosts};
    } catch (e) {
      debugPrint('[BlogService] getHomeFeedData 에러: $e');
      // 네트워크 에러는 상위로 전파
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

  /// 특정 사용자의 블로그 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getUserPosts({
    required String username,
    int page = 0,
    int size = 10,
  }) async {
    try {
      debugPrint(
        '[BlogService] Fetching user posts: username=$username page=$page, size=$size',
      );

      final response = await _dio.get(
        '/api/posts/user/$username',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(
        data['content'] ?? data as List? ?? [],
      );
      debugPrint(
        '[BlogService] Successfully fetched ${posts.length} user posts',
      );
      return posts;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          // 사용자 포스트가 없거나 API 엔드포인트가 존재하지 않는 경우
          debugPrint(
            '[BlogService] User posts not found (404) for username: $username',
          );
          return []; // 빈 리스트 반환
        }
        debugPrint(
          '[BlogService] Error ${e.response?.statusCode}: ${e.response?.data}',
        );
        throw Exception(
          'Failed to fetch user posts: ${e.response?.statusCode}',
        );
      }

      debugPrint('[BlogService] Exception: $e');
      // 404 에러인 경우 빈 리스트 반환 (서버 문제 대응)
      if (e.toString().contains('404')) {
        debugPrint('[BlogService] Returning empty list due to 404 error');
        return [];
      }
      throw Exception('Failed to fetch user posts: $e');
    }
  }

  /// 그룹별 포스트 조회
  ///
  /// [groupId] - 그룹 ID
  /// [page] - 페이지 번호 (기본값: 0)
  /// [size] - 페이지 크기 (기본값: 10)
  /// [includeContent] - content 포함 여부 (기본값: false)
  ///
  /// 응답 구조:
  /// {
  ///   "group": { ... },
  ///   "posts": {
  ///     "content": [...],
  ///     "totalElements": 50,
  ///     "totalPages": 5,
  ///     ...
  ///   },
  ///   "friends": [...]
  /// }
  Future<Map<String, dynamic>> getGroupPosts({
    required int groupId,
    int page = 0,
    int size = 10,
    bool includeContent = false,
  }) async {
    try {
      debugPrint(
        '[BlogService] 그룹별 포스트 조회 시작 - 그룹ID: $groupId, page: $page, size: $size, includeContent: $includeContent',
      );

      final response = await _dio.get(
        '/api/posts/group/$groupId',
        queryParameters: {
          'page': page,
          'size': size,
          'includeContent': includeContent,
        },
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint('[BlogService] 그룹별 포스트 조회 응답 상태: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        debugPrint(
          '[BlogService] 그룹별 포스트 조회 성공 - 포스트 수: ${(data['posts']?['content'] as List?)?.length ?? 0}',
        );
        return data;
      } else {
        throw Exception('그룹별 포스트 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[BlogService] 그룹별 포스트 조회 에러: $e');
      if (e is DioException) {
        debugPrint(
          '[BlogService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
        throw Exception('그룹별 포스트 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 포스트 조회자 정보 조회
  ///
  /// [postId] - 포스트 ID
  ///
  /// 응답 구조:
  /// {
  ///   "postId": 123,
  ///   "postTitle": "포스트 제목",
  ///   "viewers": [
  ///     {
  ///       "userId": 1,
  ///       "username": "viewer1",
  ///       "profileImageUrl": "url",
  ///       "viewedAt": "2024-01-01T00:00:00",
  ///       "hasLiked": true
  ///     },
  ///     ...
  ///   ],
  ///   "totalViewerCount": 10
  /// }
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
}
