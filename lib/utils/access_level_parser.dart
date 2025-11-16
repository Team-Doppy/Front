/// 공개범위 관련 파싱 유틸리티
class AccessLevelParser {
  /// accessLevel 문자열을 enum으로 변환
  static String? parseAccessLevelString(dynamic data) {
    final levelStr = data?.toString().toUpperCase();
    if (levelStr == 'PRIVATE' ||
        levelStr == 'PUBLIC' ||
        levelStr == 'FRIENDS' ||
        levelStr == 'GROUPS') {
      return levelStr;
    }
    return null;
  }

  /// sharedGroupIds를 List<int>로 파싱
  static List<int>? parseSharedGroupIds(dynamic data) {
    if (data == null) return null;

    if (data is List) {
      final ids =
          data
              .map((e) {
                if (e is int) return e;
                if (e is String) return int.tryParse(e);
                return (e as num?)?.toInt();
              })
              .whereType<int>()
              .toList();
      return ids.isEmpty ? null : ids;
    }

    return null;
  }

  /// sharedGroupNames를 List<String>로 파싱
  static List<String>? parseSharedGroupNames(dynamic data) {
    if (data == null) return null;

    if (data is List) {
      final names = data.map((e) => e?.toString()).whereType<String>().toList();
      return names.isEmpty ? null : names;
    }

    return null;
  }

  /// 메타데이터에서 공개범위 정보 파싱 (accessLevel만, sharedGroupIds/Names는 메타데이터에 없음)
  static Map<String, dynamic> parseAccessLevelMetadata(
    Map<String, dynamic> metadata,
  ) {
    return {
      'accessLevel': parseAccessLevelString(metadata['accessLevel']),
      // 🎯 메타데이터에는 sharedGroupIds, sharedGroupNames 없음
      'sharedGroupIds': null,
      'sharedGroupNames': null,
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
      'sharedGroupIds': parseSharedGroupIds(accessLevelInfo['sharedGroupIds']),
      'sharedGroupNames': parseSharedGroupNames(
        accessLevelInfo['sharedGroupNames'],
      ),
    };
  }
}
