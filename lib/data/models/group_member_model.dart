// lib/data/models/group_member_model.dart
class GroupMember {
  final int id;
  final int groupId;
  final String userId; // API 응답의 userId 필드
  final String displayName;
  final int neighborCount;
  final String? profileImageUrl;
  final DateTime joinedAt;

  GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.neighborCount,
    this.profileImageUrl,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final dynamic createdAt = json['joinedAt'] ?? json['createdAt'];
    return GroupMember(
      id: (json['id'] as num?)?.toInt() ?? 0,
      groupId:
          (json['groupId'] as num?)?.toInt() ??
          (json['group_id'] as num?)?.toInt() ??
          0,
      userId: (json['userId'] ?? json['username'] ?? '').toString(),
      displayName:
          (json['displayName'] ??
                  json['alias'] ??
                  json['username'] ??
                  json['userId'] ??
                  '')
              .toString(),
      neighborCount: (json['neighborCount'] as num?)?.toInt() ?? 0,
      profileImageUrl:
          (json['profileImageUrl'] ?? json['profile_image_url']) as String?,
      joinedAt:
          (createdAt is String && createdAt.isNotEmpty)
              ? DateTime.tryParse(createdAt) ?? DateTime.now()
              : DateTime.now(),
    );
  }
}
