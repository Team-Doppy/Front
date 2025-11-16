class User {
  final String username;
  final String? role;
  final String? alias; // alias 필드 추가
  final String? profileImageUrl;
  final String? selfIntroduction;
  final List<String>? links; // 🎯 프로필 링크 목록 (최대 3개)
  final int? friendCount;

  User({
    required this.username,
    this.role,
    this.alias,
    this.profileImageUrl,
    this.selfIntroduction,
    this.links,
    this.friendCount,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // 🎯 links 필드 처리 (배열 또는 null)
    List<String>? links;
    if (json['links'] != null) {
      if (json['links'] is List) {
        links =
            (json['links'] as List)
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList();
      } else if (json['links'] is String) {
        // 문자열인 경우 파싱 시도
        final linksStr = json['links'] as String;
        if (linksStr.isNotEmpty) {
          links =
              linksStr
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
        }
      }
    }

    return User(
      username: (json['username'] ?? json['userId'] ?? '').toString(),
      role: json['role']?.toString(),
      alias: json['alias']?.toString(),
      profileImageUrl:
          json['profileImageUrl']?.toString() ?? json['imageUrl']?.toString(),
      selfIntroduction: json['selfIntroduction']?.toString(),
      links: links,
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
    List<String>? links,
    int? friendCount,
  }) {
    return User(
      username: username ?? this.username,
      role: role ?? this.role,
      alias: alias ?? this.alias,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      selfIntroduction: selfIntroduction ?? this.selfIntroduction,
      links: links ?? this.links,
      friendCount: friendCount ?? this.friendCount,
    );
  }
}
