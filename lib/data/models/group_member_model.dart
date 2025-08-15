// lib/data/models/group_member_model.dart
class GroupMember {
  final int id;
  final String username;
  final DateTime joinedAt;

  GroupMember({
    required this.id,
    required this.username,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'],
      username: json['username'],
      joinedAt: DateTime.parse(json['joinedAt']),
    );
  }
}