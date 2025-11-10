// lib/data/models/group_model.dart
import 'dart:ui';

import 'user_model.dart'; // User 모델 사용
import 'group_member_model.dart';

/// 그룹 컬러 파레트
class GroupColorPalette {
  static const List<Color> colors = [
    Color(0xFF8B7FFF), // 진한 보라 (프라이머리)
    Color(0xFFA599FF), // 중간 보라
    Color(0xFFBFB3FF), // 연보라
    Color(0xFFD9CDFF), // 연한 보라-핑크 (전환 색상)
    Color.fromARGB(255, 241, 194, 240), // 보라핑크 (전환 색상)
    Color(0xFFFCACA9), // 연분홍
    Color(0xFFFFBCB9), // 중간 분홍
    Color(0xFFFFD5D3), // 연한 분홍
  ];

  static Color getColor(int index) {
    return colors[index % colors.length];
  }
}

class Group {
  final int id;
  final String name;
  final String description;
  final String ownerId; // API 응답에 맞게 ownerId 추가
  final User owner; // 기존 owner 필드 유지
  final DateTime createdAt;
  final List<GroupMember> members; // 선택적으로 포함되는 멤버 목록
  final String? profileImageUrl; // 그룹 프로필 이미지
  final int? memberCount; // 🎯 멤버 수
  final List<String>? memberThumbnails; // 🎯 멤버 썸네일 URL 리스트

  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId, // ownerId 추가
    required this.owner,
    required this.createdAt,
    this.members = const [],
    this.profileImageUrl,
    this.memberCount,
    this.memberThumbnails,
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
      profileImageUrl:
          (json['profileImageUrl'] ??
                  json['profile_image_url'] ??
                  json['groupImage'] ??
                  json['group_image'])
              ?.toString(),
      memberCount: (json['memberCount'] as num?)?.toInt(),
      memberThumbnails:
          (json['memberThumbnails'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((url) => url.isNotEmpty)
              .toList(),
    );
  }

  // 🎯 copyWith 메서드 추가
  Group copyWith({
    int? id,
    String? name,
    String? description,
    String? ownerId,
    User? owner,
    DateTime? createdAt,
    List<GroupMember>? members,
    String? profileImageUrl,
    int? memberCount,
    List<String>? memberThumbnails,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      owner: owner ?? this.owner,
      createdAt: createdAt ?? this.createdAt,
      members: members ?? this.members,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      memberCount: memberCount ?? this.memberCount,
      memberThumbnails: memberThumbnails ?? this.memberThumbnails,
    );
  }
}
