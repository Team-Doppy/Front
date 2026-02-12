/// GET /api/auth/me 응답 DTO (내 정보). Splash 시 이 API로 로드.
class User {
  final int? id;
  final String username;
  final String? email;
  final String? profileImageUrl;
  final bool? notificationEnabled;

  User({
    this.id,
    required this.username,
    this.email,
    this.profileImageUrl,
    this.notificationEnabled,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num?)?.toInt(),
      username: (json['username'] ?? '').toString(),
      email: json['email']?.toString(),
      profileImageUrl: json['profileImageUrl']?.toString(),
      notificationEnabled: json['notificationEnabled'] as bool?,
    );
  }

  User copyWith({
    int? id,
    String? username,
    String? email,
    String? profileImageUrl,
    bool? notificationEnabled,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
    );
  }
}
