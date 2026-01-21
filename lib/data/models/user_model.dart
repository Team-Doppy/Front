class User {
  final String username;
  final String? role;
  final String? alias; // alias 필드 추가
  final String? profileImageUrl;
  final List<String>? links; // 🎯 프로필 링크 목록
  final Map<String, String>? linkTitles; // 🎯 링크 타이틀 (URL -> 타이틀)
  final Map<String, String>? linkThumbnails; // 🎯 링크 썸네일 (URL -> thumbnailUrl)
  final int? friendCount;
  final bool? onboardingCompleted; // 🎯 서버에서 온보딩 완료 여부

  User({
    required this.username,
    this.role,
    this.alias,
    this.profileImageUrl,
    this.links,
    this.linkTitles,
    this.linkThumbnails,
    this.friendCount,
    this.onboardingCompleted,
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

    // 🎯 linkTitles 필드 처리 (Map<String, String> 또는 null)
    Map<String, String>? linkTitles;
    if (json['linkTitles'] != null) {
      if (json['linkTitles'] is Map) {
        linkTitles = Map<String, String>.from(
          (json['linkTitles'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );
      }
    }

    // 🎯 linkThumbnails 필드 처리 (Map<String, String> 또는 null)
    Map<String, String>? linkThumbnails;
    if (json['linkThumbnails'] != null) {
      if (json['linkThumbnails'] is Map) {
        linkThumbnails = Map<String, String>.from(
          (json['linkThumbnails'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );
      }
    }

    return User(
      username: (json['username'] ?? json['userId'] ?? '').toString(),
      role: json['role']?.toString(),
      alias: json['alias']?.toString(),
      profileImageUrl:
          json['profileImageUrl']?.toString() ?? json['imageUrl']?.toString(),

      links: links,
      linkTitles: linkTitles,
      linkThumbnails: linkThumbnails,
      friendCount: (json['friendCount'] as num?)?.toInt(),
      onboardingCompleted: json['onboardingCompleted'] as bool?,
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
    Map<String, String>? linkTitles,
    Map<String, String>? linkThumbnails,
    int? friendCount,
    bool? onboardingCompleted,
  }) {
    return User(
      username: username ?? this.username,
      role: role ?? this.role,
      alias: alias ?? this.alias,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,

      links: links ?? this.links,
      linkTitles: linkTitles ?? this.linkTitles,
      linkThumbnails: linkThumbnails ?? this.linkThumbnails,
      friendCount: friendCount ?? this.friendCount,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }
}
