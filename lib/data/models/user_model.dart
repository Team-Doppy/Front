class User {
  final int id;
  final String username;
  final String? role; // 역할 정보는 선택적으로 포함될 수 있음
  final String? alias; // 사용자 별명/표시명

  User({required this.id, required this.username, this.role, this.alias});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'],
      alias: json['alias'],
    );
  }
}