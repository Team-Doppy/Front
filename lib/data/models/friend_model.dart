enum FriendStatus { REQUESTED, ACCEPTED, BLOCKED, UNKNOWN }

class Friend {
  final int id;
  final String username;
  final FriendStatus status;
  final DateTime createdAt;
  final bool isRequester; // 내가 보낸 요청인지 여부

  Friend({
    required this.id,
    required this.username,
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
      id: json['id'],
      username: json['username'],
      status: parsedStatus,
      createdAt: DateTime.parse(json['createdAt']),
      isRequester: json['requester'] ?? false,
    );
  }
}