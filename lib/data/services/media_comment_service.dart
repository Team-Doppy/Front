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

  MediaComment({
    required this.id,
    required this.text,
    this.author,
    this.authorProfileImageUrl,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory MediaComment.fromJson(Map<String, dynamic> json) => MediaComment(
    id: json['id']?.toString() ?? '',
    text: (json['text'] ?? json['content'] ?? '').toString(),
    author: json['author']?.toString(),
    authorProfileImageUrl: json['authorProfileImageUrl']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
    updatedAt: json['updatedAt']?.toString() ?? '',
  );
}
