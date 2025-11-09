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

  Future<void> deleteImageComment({required String commentId}) async {
    print('[MediaCommentService] DELETE image comment id=$commentId');
    await _dio.delete(
      '/api/media/image/comments/$commentId',
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] DELETE success');
  }

  Future<void> deleteVideoComment({required String commentId}) async {
    print('[MediaCommentService] DELETE video comment id=$commentId');
    await _dio.delete(
      '/api/media/video/comments/$commentId',
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

  Future<MediaComment> toggleImageCommentEmotion({
    required String imageId,
    required String commentId,
    required String emoji,
  }) async {
    print(
      '[MediaCommentService] POST emotion image comment id=$commentId emoji=$emoji',
    );
    final res = await _dio.post(
      '/api/media/image/$imageId/comments/$commentId/emotions',
      queryParameters: {'emoji': emoji},
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );
    print('[MediaCommentService] <- status=${res.statusCode}');
    return MediaComment.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MediaComment> toggleVideoCommentEmotion({
    required String videoId,
    required String commentId,
    required String emoji,
  }) async {
    print(
      '[MediaCommentService] POST emotion video comment id=$commentId emoji=$emoji',
    );
    final res = await _dio.post(
      '/api/media/video/$videoId/comments/$commentId/emotions',
      queryParameters: {'emoji': emoji},
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
  final Map<String, int> emotionCounts;
  final List<String> myEmotions;

  MediaComment({
    required this.id,
    required this.text,
    this.author,
    this.authorProfileImageUrl,
    this.createdAt = '',
    this.updatedAt = '',
    this.emotionCounts = const {},
    this.myEmotions = const [],
  });

  // 편의를 위한 getter: 좋아요 여부
  bool get isLiked => myEmotions.contains('❤️');

  // 편의를 위한 getter: 총 좋아요 수
  int get likeCount =>
      emotionCounts.values.fold(0, (sum, count) => sum + count);

  factory MediaComment.fromJson(Map<String, dynamic> json) {
    final emotionCountsRaw = json['emotionCounts'] as Map<String, dynamic>?;
    final emotionCounts = <String, int>{};
    if (emotionCountsRaw != null) {
      emotionCountsRaw.forEach((key, value) {
        emotionCounts[key] = value as int? ?? 0;
      });
    }

    final myEmotionsRaw = json['myEmotions'] as List<dynamic>?;
    final myEmotions = myEmotionsRaw?.map((e) => e.toString()).toList() ?? [];

    return MediaComment(
      id: json['id']?.toString() ?? '',
      text: (json['text'] ?? json['content'] ?? '').toString(),
      author: json['author']?.toString() ?? json['authorUsername']?.toString(),
      authorProfileImageUrl: json['authorProfileImageUrl']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      emotionCounts: emotionCounts,
      myEmotions: myEmotions,
    );
  }

  MediaComment copyWith({
    String? id,
    String? text,
    String? author,
    String? authorProfileImageUrl,
    String? createdAt,
    String? updatedAt,
    Map<String, int>? emotionCounts,
    List<String>? myEmotions,
  }) {
    return MediaComment(
      id: id ?? this.id,
      text: text ?? this.text,
      author: author ?? this.author,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      emotionCounts: emotionCounts ?? this.emotionCounts,
      myEmotions: myEmotions ?? this.myEmotions,
    );
  }
}
