// lib/data/models/group_model.dart
import 'user_model.dart'; // User 모델 사용
import 'group_member_model.dart';

class Group {
  final int id;
  final String name;
  final String description;
  final String ownerId; // API 응답에 맞게 ownerId 추가
  final User owner; // 기존 owner 필드 유지
  final DateTime createdAt;
  final List<GroupMember> members; // 선택적으로 포함되는 멤버 목록

  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId, // ownerId 추가
    required this.owner,
    required this.createdAt,
    this.members = const [],
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    final dynamic membersData = json['members'];
    final List<GroupMember> parsedMembers =
        (membersData is List)
            ? membersData
                .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
                .toList()
            : const <GroupMember>[];

    return Group(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      ownerId: (json['ownerId'] ?? json['owner_id'] ?? '').toString(),
      owner: User(
        id: 0,
        username: (json['ownerId'] ?? json['owner_id'] ?? '').toString(),
        alias: (json['ownerId'] ?? json['owner_id'] ?? '').toString(),
      ),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      members: parsedMembers,
    );
  }
}
