import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';

class MediaCommentService {
  static final MediaCommentService _i = MediaCommentService._();
  factory MediaCommentService() => _i;
  MediaCommentService._();

  final Dio _dio = BaseApiService().dio;

  Future<List<MediaComment>> fetchImageComments({
    required String imageId,
    int page = 0,
    int size = 20,
  }) async {
    print(
      '[MediaCommentService] GET image comments id=$imageId page=$page size=$size',
    );
    final res = await _dio.get(
      '/api/media/image/$imageId/comments',
      queryParameters: {'page': page, 'size': size},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    final list = _parseList(res.data);
    print('[MediaCommentService] parsed image comments count=${list.length}');
    return list;
  }

  Future<List<MediaComment>> fetchVideoComments({
    required String videoId,
    int page = 0,
    int size = 20,
  }) async {
    print(
      '[MediaCommentService] GET video comments id=$videoId page=$page size=$size',
    );
    final res = await _dio.get(
      '/api/media/video/$videoId/comments',
      queryParameters: {'page': page, 'size': size},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    final list = _parseList(res.data);
    print('[MediaCommentService] parsed video comments count=${list.length}');
    return list;
  }

  Future<String> createImageComment({
    required String imageId,
    required String text,
  }) async {
    print('[MediaCommentService] POST image comment id=$imageId');
    final res = await _dio.post(
      '/api/media/image/$imageId/comments',
      data: {'text': text},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final id = data['id']?.toString();
      return id ?? '';
    }
    return '';
  }

  Future<String> createVideoComment({
    required String videoId,
    required String text,
  }) async {
    print('[MediaCommentService] POST video comment id=$videoId');
    final res = await _dio.post(
      '/api/media/video/$videoId/comments',
      data: {'text': text},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final id = data['id']?.toString();
      return id ?? '';
    }
    return '';
  }

  Future<void> deleteImageComment({
    required String imageId,
    required String commentId,
  }) async {
    print(
      '[MediaCommentService] DELETE image comment imageId=$imageId commentId=$commentId',
    );
    await _dio.delete(
      '/api/media/image/$imageId/comments/$commentId',
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] DELETE success');
  }

  Future<void> deleteVideoComment({
    required String videoId,
    required String commentId,
  }) async {
    print(
      '[MediaCommentService] DELETE video comment videoId=$videoId commentId=$commentId',
    );
    await _dio.delete(
      '/api/media/video/$videoId/comments/$commentId',
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] DELETE success');
  }

  Future<MediaComment> updateImageComment({
    required String imageId,
    required String commentId,
    required String text,
  }) async {
    print('[MediaCommentService] PUT image comment id=$commentId');
    final res = await _dio.put(
      '/api/media/image/$imageId/comments/$commentId',
      data: {'text': text},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MediaComment> updateVideoComment({
    required String videoId,
    required String commentId,
    required String text,
  }) async {
    print('[MediaCommentService] PUT video comment id=$commentId');
    final res = await _dio.put(
      '/api/media/video/$videoId/comments/$commentId',
      data: {'text': text},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  // ✅ 새로운 간단한 좋아요 API
  Future<MediaComment> toggleImageCommentLike({
    required String imageId,
    required String commentId,
  }) async {
    print('[MediaCommentService] POST like image comment id=$commentId');
    final res = await _dio.post(
      '/api/media/image/$imageId/comments/$commentId/like',
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MediaComment> toggleVideoCommentLike({
    required String videoId,
    required String commentId,
  }) async {
    print('[MediaCommentService] POST like video comment id=$commentId');
    final res = await _dio.post(
      '/api/media/video/$videoId/comments/$commentId/like',
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
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
