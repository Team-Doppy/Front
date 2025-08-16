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
    return GroupMember(
      id: json['id'],
      groupId: json['groupId'],
      userId: json['userId'] ?? '', // userId 파싱
      displayName: json['userId'] ?? '', // userId를 displayName으로 사용
      neighborCount: 0, // API 응답에 없으므로 기본값 0
      profileImageUrl: null, // API 응답에 없으므로 null
      joinedAt: DateTime.now(), // API 응답에 없으므로 현재 시간
    );
  }
}
