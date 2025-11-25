import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:flutter/material.dart';

class MediaCommentService {
  static final MediaCommentService _i = MediaCommentService._();
  factory MediaCommentService() => _i;
  MediaCommentService._();

  final Dio _dio = BaseApiService().dio;

  Future<List<MediaComment>> fetchImageComments({
    required String imageUrl, // 🎯 imageId → imageUrl로 변경
    int page = 0,
    int size = 20,
  }) async {
    debugPrint(
      '[MediaCommentService] GET image comments url=$imageUrl page=$page size=$size',
    );
    final res = await _dio.get(
      '/api/media/image/comments', // 🎯 URL 기반 엔드포인트
      queryParameters: {
        'url': imageUrl, // 🎯 URL 파라미터로 전달
        'page': page,
        'size': size,
      },
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    final list = _parseList(res.data);
    debugPrint(
      '[MediaCommentService] parsed image comments count=${list.length}',
    );
    return list;
  }

  Future<List<MediaComment>> fetchVideoComments({
    required String videoUrl, // 🎯 videoId → videoUrl로 변경
    int page = 0,
    int size = 20,
  }) async {
    debugPrint(
      '[MediaCommentService] GET video comments url=$videoUrl page=$page size=$size',
    );
    final res = await _dio.get(
      '/api/media/video/comments', // 🎯 URL 기반 엔드포인트
      queryParameters: {
        'url': videoUrl, // 🎯 URL 파라미터로 전달
        'page': page,
        'size': size,
      },
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    final list = _parseList(res.data);
    debugPrint(
      '[MediaCommentService] parsed video comments count=${list.length}',
    );
    return list;
  }

  Future<String> createImageComment({
    required String imageUrl, // 🎯 imageId → imageUrl로 변경
    required String text,
  }) async {
    debugPrint('[MediaCommentService] POST image comment url=$imageUrl');
    final res = await _dio.post(
      '/api/media/image/comments', // 🎯 URL 기반 엔드포인트
      queryParameters: {
        'url': imageUrl, // 🎯 URL은 query parameter로
      },
      data: {
        'text': text, // 🎯 body에는 text만
      },
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final id = data['id']?.toString();
      return id ?? '';
    }
    return '';
  }

  Future<String> createVideoComment({
    required String videoUrl, // 🎯 videoId → videoUrl로 변경
    required String text,
  }) async {
    debugPrint('[MediaCommentService] POST video comment url=$videoUrl');
    final res = await _dio.post(
      '/api/media/video/comments', // 🎯 URL 기반 엔드포인트
      queryParameters: {
        'url': videoUrl, // 🎯 URL은 query parameter로
      },
      data: {
        'text': text, // 🎯 body에는 text만
      },
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final id = data['id']?.toString();
      return id ?? '';
    }
    return '';
  }

  Future<void> deleteImageComment({
    required String imageUrl, // 🎯 imageId → imageUrl로 변경 (사용하지 않지만 호환성을 위해 유지)
    required String commentId,
  }) async {
    debugPrint(
      '[MediaCommentService] DELETE image comment commentId=$commentId',
    );
    await _dio.delete(
      '/api/media/image/comments/$commentId', // 🎯 commentId만 path에
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] DELETE success');
  }

  Future<void> deleteVideoComment({
    required String videoUrl, // 🎯 videoId → videoUrl로 변경 (사용하지 않지만 호환성을 위해 유지)
    required String commentId,
  }) async {
    debugPrint(
      '[MediaCommentService] DELETE video comment commentId=$commentId',
    );
    await _dio.delete(
      '/api/media/video/comments/$commentId', // 🎯 commentId만 path에
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] DELETE success');
  }

  Future<MediaComment> updateImageComment({
    required String imageUrl, // 🎯 imageId → imageUrl로 변경 (사용하지 않지만 호환성을 위해 유지)
    required String commentId,
    required String text,
  }) async {
    debugPrint('[MediaCommentService] PUT image comment commentId=$commentId');
    final res = await _dio.put(
      '/api/media/image/comments/$commentId', // 🎯 commentId만 path에
      data: {'text': text}, // 🎯 body에는 text만
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MediaComment> updateVideoComment({
    required String videoUrl, // 🎯 videoId → videoUrl로 변경 (사용하지 않지만 호환성을 위해 유지)
    required String commentId,
    required String text,
  }) async {
    debugPrint('[MediaCommentService] PUT video comment commentId=$commentId');
    final res = await _dio.put(
      '/api/media/video/comments/$commentId', // 🎯 commentId만 path에
      data: {'text': text}, // 🎯 body에는 text만
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  // ✅ 새로운 간단한 좋아요 API
  Future<MediaComment> toggleImageCommentLike({
    required String imageUrl, // 🎯 imageId → imageUrl로 변경 (사용하지 않지만 호환성을 위해 유지)
    required String commentId,
  }) async {
    debugPrint(
      '[MediaCommentService] POST like image comment commentId=$commentId',
    );
    final res = await _dio.post(
      '/api/media/image/comments/$commentId/like', // 🎯 commentId만 path에
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MediaComment> toggleVideoCommentLike({
    required String videoUrl, // 🎯 videoId → videoUrl로 변경 (사용하지 않지만 호환성을 위해 유지)
    required String commentId,
  }) async {
    debugPrint(
      '[MediaCommentService] POST like video comment commentId=$commentId',
    );
    final res = await _dio.post(
      '/api/media/video/comments/$commentId/like', // 🎯 commentId만 path에
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    debugPrint('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  List<MediaComment> _parseList(dynamic data) {
    final List<dynamic> arr =
        data is Map<String, dynamic>
            ? (data['content'] as List<dynamic>? ?? const [])
            : (data as List<dynamic>? ?? const []);
    return arr
        .map((e) => MediaComment.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}

class MediaComment {
  final String id;
  final String text;
  final String? author;
  final String? authorProfileImageUrl;
  final String createdAt;
  final String updatedAt;
  final int likeCount; // ✅ 좋아요 개수
  final bool isLiked; // ✅ 내가 좋아요 눌렀는지

  MediaComment({
    required this.id,
    required this.text,
    this.author,
    this.authorProfileImageUrl,
    this.createdAt = '',
    this.updatedAt = '',
    this.likeCount = 0,
    this.isLiked = false,
  });

  factory MediaComment.fromJson(Map<String, dynamic> json) {
    return MediaComment(
      id: json['id']?.toString() ?? '',
      text: (json['text'] ?? json['content'] ?? '').toString(),
      author: json['author']?.toString() ?? json['authorUsername']?.toString(),
      authorProfileImageUrl: json['authorProfileImageUrl']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      likeCount: json['likeCount'] as int? ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
    );
  }

  MediaComment copyWith({
    String? id,
    String? text,
    String? author,
    String? authorProfileImageUrl,
    String? createdAt,
    String? updatedAt,
    int? likeCount,
    bool? isLiked,
  }) {
    return MediaComment(
      id: id ?? this.id,
      text: text ?? this.text,
      author: author ?? this.author,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}
