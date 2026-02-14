/// 서버 포스트 API 응답 (BlogResponse)
/// id, title, thumbnailImageUrl, content, author, accessLevel, commentCount, createdAt, updatedAt 등
class BlogResponse {
  final int id;
  final String title;
  final String? thumbnailImageUrl;
  final Map<String, dynamic>? content;
  final String author;
  final String? authorProfileImageUrl;
  final String accessLevel; // PUBLIC | PRIVATE | FRIENDS
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BlogResponse({
    required this.id,
    required this.title,
    this.thumbnailImageUrl,
    this.content,
    required this.author,
    this.authorProfileImageUrl,
    required this.accessLevel,
    this.createdAt,
    this.updatedAt,
  });

  factory BlogResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final id = _parseInt(data['id']);
    final title = (data['title'] ?? '').toString();
    final author = (data['author'] ?? '').toString();
    final accessLevel =
        (data['accessLevel'] ?? 'PUBLIC').toString().toUpperCase();

    DateTime? parseDateTime(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    Map<String, dynamic>? contentMap;
    final rawContent = data['content'];
    if (rawContent is Map<String, dynamic>) {
      contentMap = rawContent;
    } else if (rawContent is Map) {
      contentMap = Map<String, dynamic>.from(rawContent);
    }

    return BlogResponse(
      id: id,
      title: title,
      thumbnailImageUrl: (data['thumbnailImageUrl'] as String?).nullIfEmpty,
      content: contentMap,
      author: author,
      authorProfileImageUrl:
          (data['authorProfileImageUrl'] as String?).nullIfEmpty,
      accessLevel: accessLevel,
      createdAt: parseDateTime(data['createdAt']),
      updatedAt: parseDateTime(data['updatedAt']),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

extension _NullIfEmpty on String? {
  String? get nullIfEmpty {
    if (this == null || this!.trim().isEmpty) return null;
    return this;
  }
}
