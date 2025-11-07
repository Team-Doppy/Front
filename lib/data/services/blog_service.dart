import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/base_api_service.dart';

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
    print('[BlogService] 로그아웃 - 모든 캐시 초기화 완료');
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
    print('[BlogService] 프로필 피드 요청: $username');

    try {
      final response = await _dio.get('/api/profile/$username/feed');

      print('[BlogService] 프로필 피드 응답 상태: ${response.statusCode}');
      print('[BlogService] 프로필 피드 응답 전체: ${response.data}');
      print(
        '[BlogService] 프로필 피드 로드 성공: ${response.data['data']?['categories']?.length ?? 0}개 카테고리',
      );

      return response.data;
    } catch (e) {
      print('[BlogService] 프로필 피드 로드 실패: $e');

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
    print('[BlogService] 프로필 스키마 요청: $username');

    try {
      final response = await _dio.get('/api/profile/feed/schema/$username');

      print('[BlogService] 프로필 스키마 응답 상태: ${response.statusCode}');
      print('[BlogService] 프로필 스키마 응답 데이터: ${response.data}');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('[BlogService] 프로필 스키마 로드 실패: $e');

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
    print('[BlogService] 프로필 포스트 요청: $username page=$page size=$size');

    try {
      final response = await _dio.get(
        '/api/profile/feed/posts/$username',
        queryParameters: {'page': page, 'size': size},
      );

      final data = response.data as Map<String, dynamic>;

      // 디버깅: 서버 응답 데이터 구조 확인
      print('[BlogService] 서버 응답 데이터 구조:');
      if (data.containsKey('data') && data['data'] is Map) {
        final dataMap = data['data'] as Map<String, dynamic>;
        if (dataMap.containsKey('posts') && dataMap['posts'] is List) {
          final posts = dataMap['posts'] as List;
          print('[BlogService] 포스트 개수: ${posts.length}');
          if (posts.isNotEmpty) {
            final firstPost = posts.first as Map<String, dynamic>;
            print('[BlogService] 첫 번째 포스트 필드들: ${firstPost.keys.toList()}');
            print('[BlogService] 첫 번째 포스트 데이터: $firstPost');
          }
        }
      }

      return data;
    } catch (e) {
      print('[BlogService] 프로필 포스트 로드 실패: $e');

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

  /// 사용자의 카테고리 목록 조회
  Future<List<Map<String, dynamic>>> getUserCategories(String username) async {
    print('[BlogService] 카테고리 목록 조회 요청: $username');

    try {
      final response = await _dio.get('/api/categories/user/$username');

      final data = response.data;
      print('[BlogService] 카테고리 목록 조회 성공: ${data.length}개');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print('[BlogService] 카테고리 목록 조회 실패: $e');

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
    print('[BlogService] 카테고리 생성 요청: $name');

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
      print('[BlogService] 카테고리 생성 성공: ${data['data']?['name']}');
      return data;
    } catch (e) {
      print('[BlogService] 카테고리 생성 실패: $e');

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
    print('[BlogService] 카테고리 삭제 요청: $categoryId');

    try {
      await _dio.delete('/api/categories/$categoryId');

      print('[BlogService] 카테고리 삭제 성공: $categoryId');
    } catch (e) {
      print('[BlogService] 카테고리 삭제 실패: $e');

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
    print('[BlogService] 카테고리 이름 수정 요청: id=$categoryId, name=$name');
    try {
      await _dio.put('/api/categories/$categoryId', data: {'name': name});
      print('[BlogService] 카테고리 이름 수정 성공: $categoryId');
    } catch (e) {
      print('[BlogService] 카테고리 이름 수정 실패: $e');
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
    print('[BlogService] 카테고리 순서 변경 요청: $orderedIds');

    try {
      final response = await _dio.put(
        '/api/categories/reorder',
        data: json.encode({'orderedIds': orderedIds}),
      );

      print('[BlogService] 카테고리 순서 변경 성공');
      if (response.data != null && response.data.toString().isNotEmpty) {
        print('[BlogService] 서버 응답 본문: ${response.data}');
      }
    } catch (e) {
      print('[BlogService] 카테고리 순서 변경 실패: $e');

      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          final message = e.response?.data?['message'] ?? '잘못된 요청입니다.';
          throw Exception(message);
        } else if (e.response?.statusCode == 401) {
          throw Exception('인증이 필요합니다.');
        } else {
          if (e.response?.data != null) {
            print('[BlogService] 실패 응답 본문: ${e.response?.data}');
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
    print(
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

      print('[BlogService] 포스트 이동 성공: $postId -> $targetCategoryId');
    } catch (e) {
      print('[BlogService] 포스트 이동 실패: $e');

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
    print('[BlogService] 포스트 순서 변경 요청: 카테고리 $categoryId');

    try {
      await _dio.put(
        '/api/categories/$categoryId/posts/reorder',
        data: {'orderedIds': orderedIds},
      );

      print('[BlogService] 포스트 순서 변경 성공: 카테고리 $categoryId');
    } catch (e) {
      print('[BlogService] 포스트 순서 변경 실패: $e');

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
    print('[BlogService] 공개범위 변경 요청: $postId -> $accessLevel');

    try {
      final data = <String, dynamic>{'accessLevel': accessLevel};

      if (accessLevel == 'GROUPS' && sharedGroupIds != null) {
        data['sharedGroupIds'] = sharedGroupIds;
      }

      await _dio.put('/api/posts/$postId/access-level', data: data);

      print('[BlogService] 공개범위 변경 성공: $postId -> $accessLevel');
    } catch (e) {
      print('[BlogService] 공개범위 변경 실패: $e');

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
    print('[BlogService] 썸네일/타이틀/요약 수정 요청: $postId');

    try {
      // 쿼리 파라미터 구성
      final queryParams = <String, String>{};

      if (thumbnailImageUrl != null && thumbnailImageUrl.isNotEmpty) {
        queryParams['thumbnailImageUrl'] = thumbnailImageUrl;
        print('[BlogService] - 썸네일: $thumbnailImageUrl');
      }

      if (title != null && title.isNotEmpty) {
        queryParams['title'] = title;
        print('[BlogService] - 타이틀: $title');
      }

      if (summary != null && summary.isNotEmpty) {
        queryParams['summary'] = summary;
        print('[BlogService] - 요약: $summary');
      }

      // 변경할 내용이 없으면 에러
      if (queryParams.isEmpty) {
        throw Exception('수정할 내용이 없습니다.');
      }

      await _dio.put(
        '/api/posts/$postId/thumbnail',
        queryParameters: queryParams,
      );

      print('[BlogService] 썸네일/타이틀/요약 수정 성공: $postId');
    } catch (e) {
      print('[BlogService] 썸네일/타이틀/요약 수정 실패: $e');

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
  }) async {
    print('[BlogService] 본문/타이틀 수정 요청: $postId');

    try {
      final requestBody = <String, dynamic>{
        'content': content,
        'usedImageUrls': usedImageUrls,
      };

      if (title != null && title.isNotEmpty) {
        requestBody['title'] = title;
        print('[BlogService] - 타이틀: $title');
      }

      print('[BlogService] - 사용된 미디어: ${usedImageUrls.length}개');

      await _dio.put('/api/posts/$postId/content', data: requestBody);

      print('[BlogService] 본문/타이틀 수정 성공: $postId');
    } catch (e) {
      print('[BlogService] 본문/타이틀 수정 실패: $e');

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
  /// [thumbnailImageId] - 썸네일 이미지 ID (선택사항)
  ///
  /// 반환: 업로드된 포스트의 ID와 메타데이터
  Future<Map<String, dynamic>> uploadPost({
    required Map<String, dynamic> postData,
    String? thumbnailImageId,
  }) async {
    print(
      '[UploadPost] uploading post with thumbnailImageId: $thumbnailImageId',
    );

    // 서버 DTO에 맞춰 매핑: title, author, thumbnailImageUrl, content(JsonNode), accessLevel
    // accessLevel은 PostExporter에서 직접 설정한 값만 사용 (PUBLIC | PRIVATE | FRIENDS | GROUPS)
    // visibility 객체는 사용하지 않음
    final dynamic accessLevelRaw = postData['accessLevel'];
    String accessLevel;
    if (accessLevelRaw != null) {
      accessLevel = accessLevelRaw.toString().toUpperCase();
      // 유효한 값인지 검증
      if (accessLevel != 'PRIVATE' &&
          accessLevel != 'GROUPS' &&
          accessLevel != 'FRIENDS') {
        accessLevel = 'PUBLIC'; // 기본값
      }
      debugPrint('[UploadPost] accessLevel: $accessLevel');
    } else {
      // accessLevel이 없으면 기본값으로 PUBLIC 설정
      accessLevel = 'PUBLIC';
      debugPrint('[UploadPost] accessLevel not found, using default: PUBLIC');
    }

    // sharedGroupIds 추출
    List<int>? sharedGroupIds;
    if (postData['sharedGroupIds'] != null) {
      final dynamic sgIds = postData['sharedGroupIds'];
      if (sgIds is List) {
        sharedGroupIds =
            sgIds
                .map((e) {
                  if (e is int) return e;
                  if (e is String) return int.tryParse(e) ?? 0;
                  return (e as num?)?.toInt() ?? 0;
                })
                .where((id) => id > 0)
                .toList();
      }
      debugPrint('[UploadPost] sharedGroupIds: $sharedGroupIds');
    }

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
      if (thumbnailImageId != null) 'thumbnailImageId': thumbnailImageId,
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

      print(
        '[UploadPost] success ${response.statusCode} body=${response.data}',
      );

      _invalidateMyPostsCache();

      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException) {
        print(
          '[UploadPost] error ${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'post upload failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }

  /// 단일 포스트의 content만 조회한다 (피드에서 메타만 있을 때 본문 로딩용)
  Future<Map<String, dynamic>> getPostContent(String postId) async {
    try {
      final response = await _dio.get(
        '/api/posts/$postId/content',
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      );

      final decoded = response.data;
      if (decoded is Map<String, dynamic>) {
        // 서버가 { content: {...} } 형태로 줄 수도 있고, content 자체를 줄 수도 있음
        final dynamic c = decoded['content'] ?? decoded;
        if (c is String) {
          try {
            final m = json.decode(c);
            return (m is Map<String, dynamic>) ? m : <String, dynamic>{};
          } catch (_) {
            return <String, dynamic>{};
          }
        }
        if (c is Map<String, dynamic>) return c;
      }
      return <String, dynamic>{};
    } catch (e) {
      print('[BlogService] getPostContent error: $e');

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
  /// title, thumbnailImageUrl, thumbnailImageId, summary, author,
  /// accessLevel, viewCount, likeCount, isLiked, createdAt, updatedAt 등의 정보만 반환.
  /// 조회수 증가 안함.
  Future<Map<String, dynamic>> getPostMetadata(String postId) async {
    try {
      print('[BlogService] 메타데이터 조회: postId=$postId');

      final response = await _dio.get(
        '/api/posts/$postId/metadata',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        print('[BlogService] 메타데이터 로드 성공');
        print('  - 제목: ${data['title']}');
        print('  - 썸네일: ${data['thumbnailImageUrl']}');
        print('  - 요약: ${data['summary']}');
        return data;
      }

      return <String, dynamic>{};
    } catch (e) {
      print('[BlogService] getPostMetadata error: $e');

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
  /// [thumbnailImageId] - 새로운 썸네일 이미지 ID (선택사항)
  Future<Map<String, dynamic>> updatePost({
    required String postId,
    required Map<String, dynamic> postData,
    String? thumbnailImageId,
  }) async {
    print(
      '[UpdatePost] updating post $postId with thumbnailImageId: $thumbnailImageId',
    );

    // 서버 DTO 규격에 맞게 업데이트 바디 구성
    // accessLevel은 postData에서 직접 읽기 (visibility 객체 사용 안 함)
    final dynamic accessLevelRaw = postData['accessLevel'];
    String accessLevel;
    if (accessLevelRaw != null) {
      accessLevel = accessLevelRaw.toString().toUpperCase();
      // 유효한 값인지 검증
      if (accessLevel != 'PRIVATE' &&
          accessLevel != 'GROUPS' &&
          accessLevel != 'FRIENDS') {
        accessLevel = 'PUBLIC'; // 기본값
      }
      debugPrint('[UpdatePost] accessLevel: $accessLevel');
    } else {
      // accessLevel이 없으면 기본값으로 PUBLIC 설정
      accessLevel = 'PUBLIC';
      debugPrint('[UpdatePost] accessLevel not found, using default: PUBLIC');
    }

    // sharedGroupIds 추출
    List<int>? sharedGroupIds;
    if (postData['sharedGroupIds'] != null) {
      final dynamic sgIds = postData['sharedGroupIds'];
      if (sgIds is List) {
        sharedGroupIds =
            sgIds
                .map((e) {
                  if (e is int) return e;
                  if (e is String) return int.tryParse(e) ?? 0;
                  return (e as num?)?.toInt() ?? 0;
                })
                .where((id) => id > 0)
                .toList();
      }
      debugPrint('[UpdatePost] sharedGroupIds: $sharedGroupIds');
    }

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
      if (thumbnailImageId != null) 'thumbnailImageId': thumbnailImageId,
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

    print('[UpdatePost] request body: ${json.encode(requestBody)}');

    try {
      final response = await _dio.put(
        '/api/posts/$postId',
        data: requestBody,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      print('[UpdatePost] success body=${response.data}');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException) {
        print(
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
    print('[DeletePost] deleting post $postId');

    try {
      await _dio.delete(
        '/api/posts/$postId',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      print('[DeletePost] success');
    } catch (e) {
      if (e is DioException) {
        print(
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
      print('[BlogService] Fetching home posts: page=$page, size=$size');

      final response = await _dio.get(
        '/api/posts/friends',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
      print('[BlogService] Successfully fetched ${posts.length} home posts');

      return posts;
    } catch (e) {
      print('[BlogService] Exception: $e');
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
      print('[BlogService] Fetching recommended posts: page=$page, size=$size');

      final response = await _dio.get(
        '/api/posts/recommendation',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
      print(
        '[BlogService] Successfully fetched ${posts.length} recommended posts',
      );

      // 포스트가 없으면 home으로 fallback
      if (posts.isEmpty) {
        print('[BlogService] No recommended posts, falling back to home');
        return getFriendsPosts(page: page, size: size);
      }

      return posts;
    } catch (e) {
      print('[BlogService] Exception: $e');
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
        print('[BlogService] Using cached my posts: key=$cacheKey');
        return _myPostsCache[cacheKey]!;
      }

      print('[BlogService] Fetching my posts: page=$page, size=$size');

      final response = await _dio.get(
        '/api/posts/my',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(data['content'] ?? []);
      print('[BlogService] Successfully fetched ${posts.length} my posts');

      // 캐시 저장
      _myPostsCache[cacheKey] = posts;
      _myPostsCachedAt = DateTime.now();
      return posts;
    } catch (e) {
      if (e is DioException) {
        print(
          '[BlogService] Error ${e.response?.statusCode}: ${e.response?.data}',
        );
        throw Exception('Failed to fetch my posts: ${e.response?.statusCode}');
      }
      print('[BlogService] Exception: $e');
      throw Exception('Failed to fetch my posts: $e');
    }
  }

  /// 내가 좋아요한 게시물 목록을 가져옵니다.
  Future<List<Map<String, dynamic>>> getMyLikedPosts({
    int page = 0,
    int size = 20,
  }) async {
    try {
      print('[BlogService] Fetching my liked posts: page=$page, size=$size');

      final response = await _dio.get(
        '/api/posts/my/liked',
        queryParameters: {'page': page, 'size': size},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final data = response.data;
      final posts = List<Map<String, dynamic>>.from(
        data['content'] ?? data['posts'] ?? data as List? ?? [],
      );
      print('[BlogService] Successfully fetched ${posts.length} liked posts');
      return posts;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          print('[BlogService] No liked posts found (404)');
          return []; // 빈 리스트 반환
        }
        print(
          '[BlogService] Error ${e.response?.statusCode}: ${e.response?.data}',
        );
        throw Exception(
          'Failed to fetch liked posts: ${e.response?.statusCode}',
        );
      }

      print('[BlogService] Exception: $e');
      // 404 에러인 경우 빈 리스트 반환 (서버 문제 대응)
      if (e.toString().contains('404')) {
        print('[BlogService] Returning empty list due to 404 error');
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
      print(
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
      print('[BlogService] Successfully fetched ${posts.length} user posts');
      return posts;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          // 사용자 포스트가 없거나 API 엔드포인트가 존재하지 않는 경우
          print(
            '[BlogService] User posts not found (404) for username: $username',
          );
          return []; // 빈 리스트 반환
        }
        print(
          '[BlogService] Error ${e.response?.statusCode}: ${e.response?.data}',
        );
        throw Exception(
          'Failed to fetch user posts: ${e.response?.statusCode}',
        );
      }

      print('[BlogService] Exception: $e');
      // 404 에러인 경우 빈 리스트 반환 (서버 문제 대응)
      if (e.toString().contains('404')) {
        print('[BlogService] Returning empty list due to 404 error');
        return [];
      }
      throw Exception('Failed to fetch user posts: $e');
    }
  }
}
