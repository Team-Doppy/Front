import '../config/emum_config.dart';

class DraftData {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AccessLevel? visibility;
  final String? thumbnailUrl;

  DraftData({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.visibility,
    this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'thumbnailUrl': thumbnailUrl,
      'visibility': visibility?.name,
      'createdAt': (createdAt).toIso8601String(),
      'updatedAt': (updatedAt).toIso8601String(),
    };
  }

  factory DraftData.fromJson(Map<String, dynamic> json) {
    AccessLevel? visibility;
    final visibilityValue = json['visibility'];
    if (visibilityValue is String) {
      visibility = AccessLevel.values.firstWhere(
        (e) => e.name == visibilityValue,
        orElse: () => AccessLevel.public,
      );
    } else if (visibilityValue is AccessLevel) {
      visibility = visibilityValue;
    } else {
      visibility = AccessLevel.public;
    }

    return DraftData(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      thumbnailUrl: json['thumbnailUrl'],
      visibility: visibility,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}
