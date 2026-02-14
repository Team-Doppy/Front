import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:doppy/data/models/blog_response.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/base_api_service.dart';

/// 포스트 발행·조회·수정·삭제 API 및 분석 완료 WebSocket
/// 인증: Bearer 토큰 (BaseApiService의 AuthInterceptor가 첨부)
class PostService {
  final Dio _dio = BaseApiService().dio;
  static const String _basePath = '/api/posts';

  // --- Create (발행) ---

  /// POST /api/posts
  /// 응답 201 Created + BlogResponse. 실패 시 예외.
  /// [timeout] 초과 시 DioException (예: 업로드 오류 다이얼로그용).
  Future<BlogResponse> create({
    required String title,
    required String author,
    String? thumbnailImageUrl,
    required Map<String, dynamic> content,
    required List<String> usedImageUrls,
    required String accessLevel, // PUBLIC | PRIVATE | FRIENDS
    String? region,
    Duration? timeout,
  }) async {
    final headers = <String, dynamic>{};
    if (region != null) headers['Region'] = region;

    final body = <String, dynamic>{
      'title': title,
      'author': author,
      'content': content,
      'usedImageUrls': usedImageUrls,
      'accessLevel': accessLevel.toUpperCase(),
    };
    if (thumbnailImageUrl != null && thumbnailImageUrl.isNotEmpty) {
      body['thumbnailImageUrl'] = thumbnailImageUrl;
    }

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _basePath,
        data: body,
        options: Options(
          headers: headers,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      if (res.statusCode != 201 && res.statusCode != 200) {
        throw Exception('포스트 발행 실패: ${res.statusCode}');
      }
      final data = res.data;
      if (data == null) throw Exception('포스트 발행 응답 없음');
      return BlogResponse.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 && kDebugMode) {
        final respData = e.response?.data;
        debugPrint('[Publish] 400 응답 본문: $respData');
        if (respData is Map && respData['message'] != null) {
          debugPrint('[Publish] 400 message: ${respData['message']}');
        }
      }
      rethrow;
    }
  }

  // --- Read ---

  /// GET /api/posts/{postId}
  Future<BlogResponse> get(int postId) async {
    final res = await _dio.get<Map<String, dynamic>>('$_basePath/$postId');
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('포스트 조회 실패: ${res.statusCode}');
    }
    return BlogResponse.fromJson(res.data!);
  }

  /// GET /api/posts/{postId}/content
  Future<BlogResponse> getContent(int postId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_basePath/$postId/content',
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('본문 조회 실패: ${res.statusCode}');
    }
    return BlogResponse.fromJson(res.data!);
  }

  /// GET /api/posts/{postId}/metadata
  Future<BlogResponse> getMetadata(int postId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_basePath/$postId/metadata',
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('메타데이터 조회 실패: ${res.statusCode}');
    }
    return BlogResponse.fromJson(res.data!);
  }

  /// GET /api/posts/my?page=0&size=20
  Future<PostListResponse> getMyPosts({int page = 0, int size = 20}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_basePath/my',
      queryParameters: {'page': page, 'size': size},
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('내 포스트 목록 조회 실패: ${res.statusCode}');
    }
    return PostListResponse.fromJson(res.data!);
  }

  // --- Update ---

  /// PUT /api/posts/{postId}/content
  Future<BlogResponse> updateContent(
    int postId, {
    String? title,
    required Map<String, dynamic> content,
    required List<String> usedImageUrls,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'usedImageUrls': usedImageUrls,
    };
    if (title != null) body['title'] = title;

    final res = await _dio.put<Map<String, dynamic>>(
      '$_basePath/$postId/content',
      data: body,
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('본문 수정 실패: ${res.statusCode}');
    }
    return BlogResponse.fromJson(res.data!);
  }

  /// PATCH /api/posts/access-level
  Future<List<BlogResponse>> updateAccessLevel({
    required List<int> postIds,
    required String accessLevel,
  }) async {
    final res = await _dio.patch<dynamic>(
      '$_basePath/access-level',
      data: {'postIds': postIds, 'accessLevel': accessLevel.toUpperCase()},
    );
    if (res.statusCode != 200) {
      throw Exception('공개 범위 변경 실패: ${res.statusCode}');
    }
    final list = res.data;
    if (list is! List) return [];
    return list
        .map((e) => e is Map<String, dynamic> ? BlogResponse.fromJson(e) : null)
        .whereType<BlogResponse>()
        .toList();
  }

  // --- Delete ---

  /// DELETE /api/posts/{postId}
  Future<void> delete(int postId) async {
    final res = await _dio.delete<void>('$_basePath/$postId');
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('포스트 삭제 실패: ${res.statusCode}');
    }
  }

  // --- 분석 완료 WebSocket (선택, 그래프 갱신 UX용) ---

  /// ws(s)://{host}/ws/analysis-events?token={accessToken}
  /// 연결 성공 시 SUBSCRIBED, 분석 완료 시 ANALYSIS_COMPLETE + postId 수신.
  /// [onAnalysisComplete]에 postId가 전달되면 그래프 재조회하면 됨.
  Stream<AnalysisEvent> connectAnalysisEvents({
    void Function(int postId)? onAnalysisComplete,
  }) async* {
    final token = await AuthService().getToken();
    if (token == null || token.isEmpty) {
      if (kDebugMode) debugPrint('[Publish] WebSocket: 토큰 없음');
      return;
    }
    final base = BaseApiService.baseUrl
        .replaceFirst(RegExp(r'^http'), 'ws')
        .replaceFirst('https', 'wss');
    final uri = Uri.parse(
      '$base/ws/analysis-events?token=${Uri.encodeComponent(token)}',
    );
    if (kDebugMode) debugPrint('[Publish] WebSocket 연결 시도: $uri');

    final channel = WebSocketChannel.connect(uri);
    if (kDebugMode) debugPrint('[Publish] WebSocket 연결됨, SUBSCRIBED 대기');

    await for (final message in channel.stream) {
      final text = message is String ? message : null;
      if (text == null || text.isEmpty) continue;

      try {
        final map = jsonDecode(text) as Map<String, dynamic>?;
        if (map == null) continue;
        final event = (map['event'] ?? '').toString();
        if (event == 'SUBSCRIBED') {
          if (kDebugMode) debugPrint('[Publish] WebSocket 응답: SUBSCRIBED');
          yield AnalysisEvent.subscribed();
        } else if (event == 'ANALYSIS_COMPLETE') {
          final postIdRaw = map['postId'];
          final postId = _parseId(postIdRaw);
          if (postId > 0) {
            if (kDebugMode) {
              debugPrint(
                '[Publish] WebSocket 응답: ANALYSIS_COMPLETE postId=$postId',
              );
            }
            onAnalysisComplete?.call(postId);
            yield AnalysisEvent.analysisComplete(postId);
          }
        } else if (event == 'ANALYSIS_FAILED') {
          final postIdRaw = map['postId'];
          final postId = _parseId(postIdRaw);
          final reason = (map['reason'] as String?)?.trim() ?? '';
          if (kDebugMode) {
            debugPrint(
              '[Publish] WebSocket 응답: ANALYSIS_FAILED postId=$postId reason=$reason',
            );
          }
          yield AnalysisEvent.analysisFailed(postId, reason);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Publish] WebSocket 메시지 파싱 오류: $e');
      }
    }
  }

  static int _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// 내 포스트 목록 응답 (페이징된 BlogResponse 목록)
class PostListResponse {
  final List<BlogResponse> content;
  final int totalPages;
  final int totalElements;
  final int number;
  final int size;

  const PostListResponse({
    required this.content,
    this.totalPages = 0,
    this.totalElements = 0,
    this.number = 0,
    this.size = 20,
  });

  factory PostListResponse.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as List<dynamic>? ?? [];
    final list =
        content
            .map(
              (e) =>
                  e is Map<String, dynamic> ? BlogResponse.fromJson(e) : null,
            )
            .whereType<BlogResponse>()
            .toList();
    return PostListResponse(
      content: list,
      totalPages: (json['totalPages'] is int) ? json['totalPages'] as int : 0,
      totalElements:
          (json['totalElements'] is int) ? json['totalElements'] as int : 0,
      number: (json['number'] is int) ? json['number'] as int : 0,
      size: (json['size'] is int) ? json['size'] as int : 20,
    );
  }
}

/// 분석 이벤트 WebSocket 이벤트
/// - SUBSCRIBED: 연결 직후
/// - ANALYSIS_COMPLETE: 분석+그래프 캐시 성공 → GET /api/graph 재조회
/// - ANALYSIS_FAILED: 분석 또는 그래프 캐시 실패 → 그래프 재로드 하지 않음, reason 표시
sealed class AnalysisEvent {
  const AnalysisEvent();
  factory AnalysisEvent.subscribed() = AnalysisSubscribed;
  factory AnalysisEvent.analysisComplete(int postId) = AnalysisComplete;
  factory AnalysisEvent.analysisFailed(int postId, String reason) =
      AnalysisFailed;
}

class AnalysisSubscribed extends AnalysisEvent {
  const AnalysisSubscribed();
}

class AnalysisComplete extends AnalysisEvent {
  final int postId;
  const AnalysisComplete(this.postId);
}

class AnalysisFailed extends AnalysisEvent {
  final int postId;
  final String reason;
  const AnalysisFailed(this.postId, this.reason);
}
