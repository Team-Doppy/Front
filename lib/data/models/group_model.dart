// lib/data/models/group_model.dart
import 'user_model.dart'; // User 모델 사용

class Group {
  final int id;
  final String name;
  final User owner;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    required this.owner,
    required this.createdAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      owner: User.fromJson(json['owner']),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}