import 'package:flutter/foundation.dart';

class ChatMessage {
  // ✅ UTC 문자열을 UTC DateTime으로 파싱 (로컬 변환 없이)
  static DateTime _parseUtcDateTime(String? value) {
    if (value == null || value.isEmpty) return DateTime.now().toUtc();
    try {
      final dateTime = DateTime.parse(value);
      // UTC가 아니면 UTC로 변환
      return dateTime.isUtc ? dateTime : dateTime.toUtc();
    } catch (e) {
      debugPrint('[ChatMessage] UTC 시간 파싱 실패: $value, 에러: $e');
      return DateTime.now().toUtc();
    }
  }

  final String messageId;
  final String chatRoomId;
  final String message;
  final int? authorId;
  final String? authorUsername;
  final String? authorAlias;
  final String? authorProfileImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSecret;
  final bool isRestricted;
  final List<int>? visibleToUserIds;
  final List<String>? visibleToUsernames;
  final List<String>? mentionedUsernames; // 🎯 언급된 사용자 목록

  ChatMessage({
    required this.messageId,
    required this.chatRoomId,
    required this.message,
    this.authorId,
    this.authorUsername,
    this.authorAlias,
    this.authorProfileImageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isSecret = false,
    this.isRestricted = false,
    this.visibleToUserIds,
    this.visibleToUsernames,
    this.mentionedUsernames,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      messageId: json['messageId'] as String? ?? '',
      chatRoomId: json['chatRoomId'] as String? ?? '',
      message: json['message'] as String? ?? '',
      authorId: json['authorId'] as int?,
      authorUsername: json['authorUsername'] as String?,
      authorAlias: json['authorAlias'] as String?,
      authorProfileImageUrl: json['authorProfileImageUrl'] as String?,
      // ✅ UTC 문자열을 UTC DateTime으로 파싱 (로컬 변환 없이)
      createdAt: _parseUtcDateTime(json['createdAt'] as String?),
      updatedAt: _parseUtcDateTime(json['updatedAt'] as String?),
      isSecret: json['isSecret'] as bool? ?? false,
      isRestricted: json['isRestricted'] as bool? ?? false,
      visibleToUserIds:
          json['visibleToUserIds'] != null
              ? (json['visibleToUserIds'] as List<dynamic>)
                  .map((e) => e as int)
                  .toList()
              : null,
      visibleToUsernames:
          json['visibleToUsernames'] != null
              ? (json['visibleToUsernames'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : null,
      mentionedUsernames:
          json['mentionedUsernames'] != null
              ? (json['mentionedUsernames'] as List<dynamic>)
                  .map((e) => e as String)
                  .toList()
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'chatRoomId': chatRoomId,
      'message': message,
      'authorId': authorId,
      'authorUsername': authorUsername,
      'authorAlias': authorAlias,
      'authorProfileImageUrl': authorProfileImageUrl,
      // ✅ UTC로 저장 (UTC가 아니면 변환)
      'createdAt':
          (createdAt.isUtc ? createdAt : createdAt.toUtc()).toIso8601String(),
      'updatedAt':
          (updatedAt.isUtc ? updatedAt : updatedAt.toUtc()).toIso8601String(),
      'isSecret': isSecret,
      'isRestricted': isRestricted,
      'visibleToUserIds': visibleToUserIds,
      'visibleToUsernames': visibleToUsernames,
      'mentionedUsernames': mentionedUsernames,
    };
  }

  ChatMessage copyWith({
    String? messageId,
    String? chatRoomId,
    String? message,
    int? authorId,
    String? authorUsername,
    String? authorAlias,
    String? authorProfileImageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSecret,
    bool? isRestricted,
    List<int>? visibleToUserIds,
    List<String>? visibleToUsernames,
    List<String>? mentionedUsernames,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      message: message ?? this.message,
      authorId: authorId ?? this.authorId,
      authorUsername: authorUsername ?? this.authorUsername,
      authorAlias: authorAlias ?? this.authorAlias,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSecret: isSecret ?? this.isSecret,
      isRestricted: isRestricted ?? this.isRestricted,
      visibleToUserIds: visibleToUserIds ?? this.visibleToUserIds,
      visibleToUsernames: visibleToUsernames ?? this.visibleToUsernames,
      mentionedUsernames: mentionedUsernames ?? this.mentionedUsernames,
    );
  }
}
