// lib/data/models/group_model.dart
import 'dart:ui';

import 'user_model.dart'; // User 모델 사용
import 'group_member_model.dart';
import 'package:flutter/foundation.dart';

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
  // ✅ UTC 문자열을 UTC DateTime으로 파싱 (로컬 변환 없이)
  static DateTime _parseUtcDateTime(String? value) {
    if (value == null || value.isEmpty)
      return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    try {
      final dateTime = DateTime.parse(value);
      // UTC가 아니면 UTC로 변환
      return dateTime.isUtc ? dateTime : dateTime.toUtc();
    } catch (e) {
      debugPrint('[Group] UTC 시간 파싱 실패: $value, 에러: $e');
      return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    }
  }

  final int id;
  final String name;
  final String description;
  final String ownerId; // API 응답에 맞게 ownerId 추가
  final User owner; // 기존 owner 필드 유지
  final DateTime createdAt;
  final List<GroupMember> members; // 선택적으로 포함되는 멤버 목록
  final String? profileImageUrl; // 그룹 프로필 이미지
  final int? memberCount; // 🎯 멤버 수
  final int? postCount; // 🎯 포스트 수
  final List<String>? memberThumbnails; // 🎯 멤버 썸네일 URL 리스트
  final bool? isSystem; // 🎯 시스템 그룹 여부 (전체 친구 등)

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
    this.postCount,
    this.memberThumbnails,
    this.isSystem,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    final dynamic membersData = json['members'];
    final List<GroupMember> parsedMembers =
        (membersData is List)
            ? membersData
                .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
                .toList()
            : const <GroupMember>[];

    // 🎯 이미지 URL 파싱 로그
    final profileImageUrl =
        (json['profileImageUrl'] ??
                json['profile_image_url'] ??
                json['groupImage'] ??
                json['group_image'])
            ?.toString();

    return Group(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      ownerId: (json['ownerId'] ?? json['owner_id'] ?? '').toString(),
      owner: User(
        username: (json['ownerId'] ?? json['owner_id'] ?? '').toString(),
        alias: (json['ownerId'] ?? json['owner_id'] ?? '').toString(),
      ),
      createdAt: _parseUtcDateTime((json['createdAt'] ?? '').toString()),
      members: parsedMembers,
      profileImageUrl: profileImageUrl,
      memberCount: (json['memberCount'] as num?)?.toInt(),
      postCount: (json['postCount'] as num?)?.toInt(),
      memberThumbnails:
          (json['memberThumbnails'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((url) => url.isNotEmpty)
              .toList(),
      isSystem: json['isSystem'] as bool? ?? false,
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
    int? postCount,
    List<String>? memberThumbnails,
    bool? isSystem,
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
      postCount: postCount ?? this.postCount,
      memberThumbnails: memberThumbnails ?? this.memberThumbnails,
      isSystem: isSystem ?? this.isSystem,
    );
  }
}
