import 'package:flutter/foundation.dart';

enum FriendStatus { REQUESTED, ACCEPTED, BLOCKED, UNKNOWN }

class Friend {
  // ✅ UTC 문자열을 UTC DateTime으로 파싱 (로컬 변환 없이)
  static DateTime _parseUtcDateTime(String? value) {
    if (value == null || value.isEmpty)
      return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    try {
      final dateTime = DateTime.parse(value);
      // UTC가 아니면 UTC로 변환
      return dateTime.isUtc ? dateTime : dateTime.toUtc();
    } catch (e) {
      debugPrint('[Friend] UTC 시간 파싱 실패: $value, 에러: $e');
      return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    }
  }

  final int id;
  final String username;
  final String alias;
  final String? profileImageUrl;
  final FriendStatus status;
  final DateTime createdAt;
  final bool isRequester; // 내가 보낸 요청인지 여부

  Friend({
    required this.id,
    required this.username,
    required this.alias,
    this.profileImageUrl,
    required this.status,
    required this.createdAt,
    required this.isRequester,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    FriendStatus parsedStatus;
    switch (json['status']) {
      case 'REQUESTED':
        parsedStatus = FriendStatus.REQUESTED;
        break;
      case 'ACCEPTED':
        parsedStatus = FriendStatus.ACCEPTED;
        break;
      case 'BLOCKED':
        parsedStatus = FriendStatus.BLOCKED;
        break;
      default:
        parsedStatus = FriendStatus.UNKNOWN;
    }

    return Friend(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: (json['username'] ?? '').toString(),
      alias: (json['alias'] ?? '').toString(),
      profileImageUrl:
          (json['profileImageUrl'] ?? json['profile_image_url']) as String?,
      status: parsedStatus,
      createdAt:
          (json['createdAt'] != null &&
                  (json['createdAt'] as String).isNotEmpty)
              ? _parseUtcDateTime(json['createdAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
      isRequester: (json['requester'] as bool?) ?? false,
    );
  }
}
