import 'package:flutter/foundation.dart';

// Comment 모델 (채팅 기능 확장)
class Comment {
  // ✅ UTC 문자열을 UTC DateTime으로 파싱 (로컬 변환 없이)
  static DateTime _parseUtcDateTime(String? value) {
    if (value == null || value.isEmpty) return DateTime.now().toUtc();
    try {
      final dateTime = DateTime.parse(value);
      // UTC가 아니면 UTC로 변환
      return dateTime.isUtc ? dateTime : dateTime.toUtc();
    } catch (e) {
      debugPrint('[Comment] UTC 시간 파싱 실패: $value, 에러: $e');
      return DateTime.now().toUtc();
    }
  }

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

  // 🎯 채팅 기능 필드
  final List<String>? mentionedUsernames; // 언급된 사용자 목록
  final bool isSecret; // 비밀 메시지 여부
  final bool isRestricted; // 제한된 메시지 여부
  final String? visibleToUsername; // 비밀 메시지를 볼 수 있는 사용자 (1:1)

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
    this.mentionedUsernames,
    this.isSecret = false,
    this.isRestricted = false,
    this.visibleToUsername,
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
      // ✅ UTC 문자열을 UTC DateTime으로 파싱 (로컬 변환 없이)
      createdAt: _parseUtcDateTime(json['createdAt'] as String?),
      updatedAt: _parseUtcDateTime(json['updatedAt'] as String?),
      mentionedUsernames:
          json['mentionedUsernames'] != null
              ? (json['mentionedUsernames'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : null,
      isSecret: json['isSecret'] as bool? ?? false,
      isRestricted: json['isRestricted'] as bool? ?? false,
      visibleToUsername: json['visibleToUsername'] as String?,
    );
  }

  Comment copyWith({
    int? id,
    String? content,
    String? author,
    String? authorProfileImageUrl,
    int? postId,
    int? parentId,
    String? visibility,
    Map<String, int>? emotionCounts,
    Map<String, int>? myEmotions,
    List<Comment>? replies,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? mentionedUsernames,
    bool? isSecret,
    bool? isRestricted,
    String? visibleToUsername,
  }) {
    return Comment(
      id: id ?? this.id,
      content: content ?? this.content,
      author: author ?? this.author,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      postId: postId ?? this.postId,
      parentId: parentId ?? this.parentId,
      visibility: visibility ?? this.visibility,
      emotionCounts: emotionCounts ?? this.emotionCounts,
      myEmotions: myEmotions ?? this.myEmotions,
      replies: replies ?? this.replies,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mentionedUsernames: mentionedUsernames ?? this.mentionedUsernames,
      isSecret: isSecret ?? this.isSecret,
      isRestricted: isRestricted ?? this.isRestricted,
      visibleToUsername: visibleToUsername ?? this.visibleToUsername,
    );
  }
}
