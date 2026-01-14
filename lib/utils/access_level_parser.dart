import '../data/models/system_category_keys.dart';

/// 공개범위 관련 파싱 유틸리티
class AccessLevelParser {
  /// accessLevel 문자열을 enum으로 변환
  static String? parseAccessLevelString(dynamic data) {
    final levelStr = data?.toString().toUpperCase();
    if (levelStr == SystemCategoryKeys.private ||
        levelStr == SystemCategoryKeys.public ||
        levelStr == SystemCategoryKeys.friends) {
      return levelStr;
    }
    // 그룹 기능 제거로 인해 'GROUPS' 제거
    return null;
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
