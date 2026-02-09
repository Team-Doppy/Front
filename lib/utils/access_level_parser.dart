import '../data/models/access_level.dart';

/// 공개범위 관련 파싱 유틸리티
class AccessLevelParser {
  /// accessLevel 문자열을 enum으로 변환 (하위 호환성 유지)
  /// @deprecated 새로운 코드에서는 AccessLevelExtension.fromServerValue를 직접 사용하세요.
  static String? parseAccessLevelString(dynamic data) {
    final levelStr = data?.toString().toUpperCase();
    // 새로운 AccessLevel enum의 모든 값 지원
    try {
      AccessLevelExtension.fromServerValue(levelStr ?? 'PUBLIC');
      return levelStr;
    } catch (_) {
      return null;
    }
  }

  /// accessLevel 문자열을 AccessLevel enum으로 변환
  static AccessLevel parseAccessLevel(dynamic data) {
    final levelStr = data?.toString() ?? 'PUBLIC';
    return AccessLevelExtension.fromServerValue(levelStr);
  }

  // 그룹 기능 제거로 인해 parseSharedGroupIds, parseSharedGroupNames 메서드 제거

  /// 메타데이터에서 공개범위 정보 파싱 (accessLevel만)
  static Map<String, dynamic> parseAccessLevelMetadata(
    Map<String, dynamic> metadata,
  ) {
    return {
      'accessLevel': parseAccessLevelString(metadata['accessLevel']),
      // 그룹 기능 제거로 인해 sharedGroupIds, sharedGroupNames 제거
    };
  }

  /// Content 포함 응답에서 공개범위 정보 파싱 (content.accessLevelInfo에서 추출)
  static Map<String, dynamic> parseAccessLevelFromContent(
    Map<String, dynamic> response,
  ) {
    // content.accessLevelInfo 확인
    final content = response['content'] as Map<String, dynamic>?;
    if (content == null) {
      // content가 없으면 메타데이터 레벨만 반환
      return parseAccessLevelMetadata(response);
    }

    final accessLevelInfo = content['accessLevelInfo'] as Map<String, dynamic>?;
    if (accessLevelInfo == null) {
      // accessLevelInfo가 없으면 메타데이터 레벨만 반환
      return parseAccessLevelMetadata(response);
    }

    // 🎯 content.accessLevelInfo에서 상세 정보 추출
    return {
      'accessLevel': parseAccessLevelString(accessLevelInfo['accessLevel']),
      // 그룹 기능 제거로 인해 sharedGroupIds, sharedGroupNames 제거
    };
  }
}
