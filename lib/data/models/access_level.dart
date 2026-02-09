/// 공개 범위(접근 레벨) Enum
///
/// 서버 API와 클라이언트 간 공개 범위를 통일된 enum으로 관리합니다.
enum AccessLevel {
  /// 전체 공개
  public,

  /// 나만 보기
  private,

  /// 친구에게만
  friends,

  /// 곰신이 남친에게만
  girlfriendToBoyfriend,

  /// 남친이 곰신에게만
  boyfriendToGirlfriend,

  /// 친구 중 군인만
  soldiersOnly,
}

/// AccessLevel 확장 메서드
extension AccessLevelExtension on AccessLevel {
  /// 서버 API에서 사용하는 문자열 값 반환
  String get serverValue {
    switch (this) {
      case AccessLevel.public:
        return 'PUBLIC';
      case AccessLevel.private:
        return 'PRIVATE';
      case AccessLevel.friends:
        return 'FRIENDS';
      case AccessLevel.girlfriendToBoyfriend:
        return 'GIRLFRIEND_TO_BOYFRIEND';
      case AccessLevel.boyfriendToGirlfriend:
        return 'BOYFRIEND_TO_GIRLFRIEND';
      case AccessLevel.soldiersOnly:
        return 'SOLDIERS_ONLY';
    }
  }

  /// 서버 문자열 값으로부터 AccessLevel 생성
  static AccessLevel fromServerValue(String value) {
    final upper = value.toUpperCase();
    switch (upper) {
      case 'PUBLIC':
        return AccessLevel.public;
      case 'PRIVATE':
        return AccessLevel.private;
      case 'FRIENDS':
        return AccessLevel.friends;
      case 'GIRLFRIEND_TO_BOYFRIEND':
        return AccessLevel.girlfriendToBoyfriend;
      case 'BOYFRIEND_TO_GIRLFRIEND':
        return AccessLevel.boyfriendToGirlfriend;
      case 'SOLDIERS_ONLY':
        return AccessLevel.soldiersOnly;
      default:
        // 기본값: PUBLIC
        return AccessLevel.public;
    }
  }

  /// 로컬라이제이션 키 반환
  String get localizationKey {
    switch (this) {
      case AccessLevel.public:
        return 'visibility_public';
      case AccessLevel.private:
        return 'visibility_private';
      case AccessLevel.friends:
        return 'visibility_friends';
      case AccessLevel.girlfriendToBoyfriend:
        return 'visibility_girlfriend_to_boyfriend';
      case AccessLevel.boyfriendToGirlfriend:
        return 'visibility_boyfriend_to_girlfriend';
      case AccessLevel.soldiersOnly:
        return 'visibility_soldiers_only';
    }
  }
}
