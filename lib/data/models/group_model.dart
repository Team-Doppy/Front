import 'user_model.dart'; // User 모델 import

class Group {
  final int id;
  final String name;
  final User owner;

  Group({required this.id, required this.name, required this.owner});

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      owner: User.fromJson(json['owner']),
    );
  }
}