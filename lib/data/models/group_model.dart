// lib/data/models/group_model.dart
import 'user_model.dart'; // User 모델 사용

class Group {
  final int id;
  final String name;
  final String description;
  final String ownerId; // API 응답에 맞게 ownerId 추가
  final User owner; // 기존 owner 필드 유지
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId, // ownerId 추가
    required this.owner,
    required this.createdAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      ownerId: json['ownerId'] ?? '', // ownerId 파싱
      owner: User(
        // ownerId로 User 객체 생성
        id: 0, // 임시 ID
        username: json['ownerId'] ?? '', // ownerId를 username으로 사용
        alias: json['ownerId'] ?? '', // ownerId를 alias로 사용
      ),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
