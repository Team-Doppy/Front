/// 프로필 피드 공개범위(access level) 키/라벨 유틸
///
/// - 서버/클라이언트 간에는 **항상 서버 문자열**을 그대로 사용합니다.
/// - 화면 표시만 한글 라벨로 매핑합니다.
abstract class ProfileAccessLevel {
  ProfileAccessLevel._();

  static const String public = 'PUBLIC';
  static const String private = 'PRIVATE';
  static const String friends = 'FRIENDS';

  /// 탭/피커 순서 (명세): PUBLIC → FRIENDS → PRIVATE
  static const List<String> tabOrder = [public, friends, private];

  static bool isValid(String? value) {
    if (value == null || value.isEmpty) return false;
    final upper = value.toUpperCase();
    return upper == public || upper == private || upper == friends;
  }

  /// 서버 값 → 화면 라벨(한글)
  static String toDisplayLabel(String? serverValue) {
    if (serverValue == null || serverValue.isEmpty) return '전체';
    switch (serverValue.toUpperCase()) {
      case public:
        return '전체공개';
      case private:
        return '나만보기';
      case friends:
        return '친구공개';
      default:
        return serverValue;
    }
  }
}
