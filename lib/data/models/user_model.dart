class User {
  final String username;
  final String? role;
  final String? alias; // alias 필드 추가
  final String? profileImageUrl;
  final String? selfIntroduction;
  final int? friendCount;

  User({
    required this.username,
    this.role,
    this.alias,
    this.profileImageUrl,
    this.selfIntroduction,
    this.friendCount,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: (json['username'] ?? json['userId'] ?? '').toString(),
      role: json['role']?.toString(),
      alias: json['alias']?.toString(),
      profileImageUrl:
          json['profileImageUrl']?.toString() ?? json['imageUrl']?.toString(),
      selfIntroduction: json['selfIntroduction']?.toString(),
      friendCount: (json['friendCount'] as num?)?.toInt(),
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? role,
    String? alias,
    String? profileImageUrl,
    String? selfIntroduction,
    int? friendCount,
  }) {
    return User(
      username: username ?? this.username,
      role: role ?? this.role,
      alias: alias ?? this.alias,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      selfIntroduction: selfIntroduction ?? this.selfIntroduction,
      friendCount: friendCount ?? this.friendCount,
    );
  }
}
