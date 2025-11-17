import 'package:doppy/utils/time_utils.dart';

enum FriendStatus { REQUESTED, ACCEPTED, BLOCKED, UNKNOWN }

class Friend {
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
              ? TimeUtils.toLocalTime(json['createdAt'] as String)
              : DateTime.fromMillisecondsSinceEpoch(0),
      isRequester: (json['requester'] as bool?) ?? false,
    );
  }
}
