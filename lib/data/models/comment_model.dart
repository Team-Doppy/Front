import 'package:doppy/utils/time_utils.dart';

// Comment 모델 (기존과 동일)
class Comment {
  final int id;
  final String content;
  final String author;
  final String authorProfileImageUrl;
  final int postId;
  final int? parentId;
  final String visibility;
  final Map<String, int> emotionCounts;
  final Map<String, int> myEmotions;
  final List<Comment> replies;
  final DateTime createdAt;
  final DateTime updatedAt;

  Comment({
    required this.id,
    required this.content,
    required this.author,
    required this.authorProfileImageUrl,
    required this.postId,
    this.parentId,
    required this.visibility,
    required this.emotionCounts,
    required this.myEmotions,
    required this.replies,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as int,
      content: json['content'] as String,
      author: json['author'] as String,
      authorProfileImageUrl: json['authorProfileImageUrl'] as String,
      postId: json['postId'] as int,
      parentId: json['parentId'] as int?,
      visibility: json['visibility'] as String,
      emotionCounts: Map<String, int>.from(json['emotionCounts'] ?? {}),
      myEmotions: Map<String, int>.from(json['myEmotions'] ?? {}),
      replies:
          (json['replies'] as List<dynamic>?)
              ?.map((reply) => Comment.fromJson(reply as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: TimeUtils.toLocalTime(json['createdAt'] as String),
      updatedAt: TimeUtils.toLocalTime(json['updatedAt'] as String),
    );
  }
}
