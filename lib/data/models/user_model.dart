class User {
  final int id;
  final String username;
  final String? role;
  final String? alias; // alias 필드 추가
  final String? displayName;
  final String? profileImageUrl;
  final String? selfIntroduction;
  final int? friendCount;

  User({
    required this.id,
    required this.username,
    this.role,
    this.alias,
    this.displayName,
    this.profileImageUrl,
    this.selfIntroduction,
    this.friendCount,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'],
      alias: json['alias'],
      displayName: json['displayName'],
      profileImageUrl: json['profileImageUrl'],
      selfIntroduction: json['selfIntroduction'],
      friendCount: json['friendCount'],
    );
  }
}
