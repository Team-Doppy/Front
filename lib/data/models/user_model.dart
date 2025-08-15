class User {
  final int id;
  final String username;
  final String? role;
  final String? alias; // alias 필드 추가

  User({
    required this.id,
    required this.username,
    this.role,
    this.alias,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'],
      alias: json['alias'],
    );
  }
}