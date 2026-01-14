import 'package:flutter/foundation.dart';

/// 알림 타입
enum NotificationType {
  POST_CREATED, // 새 포스트 작성
  POST_MENTION, // 포스트에서 언급
  CHAT_MENTION, // 채팅에서 언급
  LIKE_CREATED, // 좋아요
  FRIEND_REQUEST, // 친구 요청
  FRIEND_ACCEPTED, // 친구 요청 수락
  CUSTOM, // 커스텀 알림
  BLOG_NUDGE, // 블로그 작성 요청
  UNKNOWN, // 알 수 없음
}

/// 알림 모델
class NotificationData {
  final String documentId; // Firestore 문서 ID
  final int userId; // 알림을 받은 사용자 ID
  final NotificationType type;
  final String title;
  final String? body;
  final String? deepLink; // 딥링크 URL
  final bool read; // 읽음 여부 (Firestore 필드명과 일치)
  final DateTime createdAt;

  // 타입별 추가 필드
  final String? postId;
  final String? authorId;
  final String? authorUsername;
  final String? likerId;
  final String? likerUsername;
  final String? requesterId;
  final String? requesterUsername;
  final String? accepterId;
  final String? accepterUsername;
  final Map<String, dynamic>? extraData; // 기타 추가 데이터

  NotificationData({
    required this.documentId,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.deepLink,
    required this.read,
    required this.createdAt,
    this.postId,
    this.authorId,
    this.authorUsername,
    this.likerId,
    this.likerUsername,
    this.requesterId,
    this.requesterUsername,
    this.accepterId,
    this.accepterUsername,
    this.extraData,
  });

  // 편의 getter
  String? get relatedUserId {
    switch (type) {
      case NotificationType.POST_CREATED:
      case NotificationType.POST_MENTION:
      case NotificationType.CHAT_MENTION:
        return authorId;
      case NotificationType.LIKE_CREATED:
        return likerId;
      case NotificationType.FRIEND_REQUEST:
        return requesterId;
      case NotificationType.FRIEND_ACCEPTED:
        return accepterId;
      default:
        return null;
    }
  }

  String? get relatedUsername {
    switch (type) {
      case NotificationType.POST_CREATED:
      case NotificationType.POST_MENTION:
      case NotificationType.CHAT_MENTION:
        return authorUsername;
      case NotificationType.LIKE_CREATED:
        return likerUsername;
      case NotificationType.FRIEND_REQUEST:
        return requesterUsername;
      case NotificationType.FRIEND_ACCEPTED:
        return accepterUsername;
      default:
        return null;
    }
  }

  String? get relatedPostId => postId;

  bool get isRead => read;

  /// Firestore 문서에서 생성
  factory NotificationData.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    // 타입 파싱
    NotificationType parsedType;
    final typeStr = (data['type'] as String? ?? '').toUpperCase();
    switch (typeStr) {
      case 'POST_CREATED':
        parsedType = NotificationType.POST_CREATED;
        break;
      case 'POST_MENTION':
        parsedType = NotificationType.POST_MENTION;
        break;
      case 'CHAT_MENTION':
        parsedType = NotificationType.CHAT_MENTION;
        break;
      case 'LIKE_CREATED':
        parsedType = NotificationType.LIKE_CREATED;
        break;
      case 'FRIEND_REQUEST':
        parsedType = NotificationType.FRIEND_REQUEST;
        break;
      case 'FRIEND_ACCEPTED':
        parsedType = NotificationType.FRIEND_ACCEPTED;
        break;
      case 'CUSTOM':
        parsedType = NotificationType.CUSTOM;
        break;
      case 'BLOG_NUDGE':
        parsedType = NotificationType.BLOG_NUDGE;
        break;
      default:
        parsedType = NotificationType.UNKNOWN;
    }

    // 시간 파싱 (Firestore Timestamp)
    DateTime parsedCreatedAt;
    try {
      final createdAt = data['createdAt'];
      if (createdAt == null) {
        parsedCreatedAt = DateTime.now().toUtc();
      } else if (createdAt is Map) {
        // Firestore Timestamp 형식: {_seconds: 123, _nanoseconds: 456}
        final seconds = createdAt['_seconds'] as int? ?? 0;
        parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      } else if (createdAt is String) {
        parsedCreatedAt = DateTime.parse(createdAt).toUtc();
      } else {
        parsedCreatedAt = DateTime.now().toUtc();
      }
    } catch (e) {
      debugPrint('[NotificationData] 시간 파싱 실패: ${data['createdAt']}, 에러: $e');
      parsedCreatedAt = DateTime.now().toUtc();
    }

    return NotificationData(
      documentId: documentId,
      userId: (data['userId'] as num?)?.toInt() ?? 0,
      type: parsedType,
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      deepLink: data['deepLink'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: parsedCreatedAt,
      postId: data['postId'] as String?,
      authorId: data['authorId'] as String?,
      authorUsername: data['authorUsername'] as String?,
      likerId: data['likerId'] as String?,
      likerUsername: data['likerUsername'] as String?,
      requesterId: data['requesterId'] as String?,
      requesterUsername: data['requesterUsername'] as String?,
      accepterId: data['accepterId'] as String?,
      accepterUsername: data['accepterUsername'] as String?,
      extraData: data,
    );
  }

  /// JSON에서 생성 (API 호환성)
  factory NotificationData.fromJson(Map<String, dynamic> json) {
    return NotificationData.fromFirestore(json['id']?.toString() ?? '', json);
  }

  Map<String, dynamic> toJson() {
    String typeStr;
    switch (type) {
      case NotificationType.POST_CREATED:
        typeStr = 'POST_CREATED';
        break;
      case NotificationType.POST_MENTION:
        typeStr = 'POST_MENTION';
        break;
      case NotificationType.CHAT_MENTION:
        typeStr = 'CHAT_MENTION';
        break;
      case NotificationType.LIKE_CREATED:
        typeStr = 'LIKE_CREATED';
        break;
      case NotificationType.FRIEND_REQUEST:
        typeStr = 'FRIEND_REQUEST';
        break;
      case NotificationType.FRIEND_ACCEPTED:
        typeStr = 'FRIEND_ACCEPTED';
        break;
      case NotificationType.CUSTOM:
        typeStr = 'CUSTOM';
        break;
      case NotificationType.BLOG_NUDGE:
        typeStr = 'BLOG_NUDGE';
        break;
      default:
        typeStr = 'UNKNOWN';
    }

    return {
      'documentId': documentId,
      'userId': userId,
      'type': typeStr,
      'title': title,
      'body': body,
      'deepLink': deepLink,
      'read': read,
      'createdAt': createdAt.toIso8601String(),
      'postId': postId,
      'authorId': authorId,
      'authorUsername': authorUsername,
      'likerId': likerId,
      'likerUsername': likerUsername,
      'requesterId': requesterId,
      'requesterUsername': requesterUsername,
      'accepterId': accepterId,
      'accepterUsername': accepterUsername,
      ...?extraData,
    };
  }
}
