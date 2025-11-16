import 'package:flutter/material.dart';
import '../../providers/feed_provider/base_feed_provider.dart';
import '../../l10n/app_localizations.dart';

/// 시스템 카테고리 키 상수 클래스
///
/// 서버의 `systemCategoryMappings`에서 사용되는 키 값들을 정의합니다.
/// 이 키들은 서버 응답에서 그대로 사용되므로 변경하지 마세요.
///
/// UI 표시 텍스트는 `app_localizations.dart`의 로컬라이제이션 키를 사용합니다.
class SystemCategoryKeys {
  SystemCategoryKeys._(); // 상수 클래스이므로 인스턴스화 방지

  /// 전체공개 카테고리 키 (서버 응답 키)
  /// UI 표시: `context.tr('visibility_public')` 또는 `context.tr('public')`
  static const String public = 'PUBLIC';

  /// 나만보기 카테고리 키 (서버 응답 키)
  /// UI 표시: `context.tr('visibility_private')` 또는 `context.tr('private')`
  static const String private = 'PRIVATE';

  /// 친구공유 카테고리 키 (서버 응답 키)
  /// UI 표시: `context.tr('visibility_friends')` 또는 `context.tr('friends')`
  static const String friends = 'FRIENDS';

  /// 그룹공유 카테고리 키 (서버 응답 키)
  /// UI 표시: `context.tr('visibility_group')` 또는 `context.tr('group')`
  static const String groups = 'GROUPS';

  /// 모든 시스템 카테고리 키 목록
  static const List<String> allKeys = [public, private, friends, groups];

  /// 특정 키가 유효한 시스템 카테고리 키인지 확인
  /// 대소문자 구분 없이 확인 (서버는 대문자지만 호환성을 위해)
  static bool isValid(String key) {
    return allKeys.contains(key) ||
        allKeys.contains(key.toUpperCase()) ||
        // 하위 호환성: 이전 한국어 키도 지원
        ['전체공개', '나만보기', '친구공유', '그룹공유'].contains(key);
  }

  /// BaseFilter에 해당하는 시스템 카테고리 키 반환
  ///
  /// 매핑:
  /// - BaseFilter.public → SystemCategoryKeys.public ('PUBLIC')
  /// - BaseFilter.private → SystemCategoryKeys.private ('PRIVATE')
  /// - BaseFilter.friends → SystemCategoryKeys.friends ('FRIENDS')
  /// - BaseFilter.groups → SystemCategoryKeys.groups ('GROUPS')
  /// - BaseFilter.all → null (해당 없음)
  static String? fromBaseFilter(BaseFilter filter) {
    switch (filter) {
      case BaseFilter.public:
        return public;
      case BaseFilter.private:
        return private;
      case BaseFilter.friends:
        return friends;
      case BaseFilter.groups:
        return groups;
      case BaseFilter.all:
        return null;
    }
  }

  /// 시스템 카테고리 키에 해당하는 BaseFilter 반환
  ///
  /// 매핑:
  /// - 'PUBLIC' → BaseFilter.public
  /// - 'PRIVATE' → BaseFilter.private
  /// - 'FRIENDS' → BaseFilter.friends
  /// - 'GROUPS' → BaseFilter.groups
  /// - 그 외 → null
  ///
  /// 하위 호환성: 이전 한국어 키('전체공개', '나만보기', '친구공유', '그룹공유')도 지원
  static BaseFilter? toBaseFilter(String key) {
    final upperKey = key.toUpperCase();

    switch (upperKey) {
      case 'PUBLIC':
        return BaseFilter.public;
      case 'PRIVATE':
        return BaseFilter.private;
      case 'FRIENDS':
        return BaseFilter.friends;
      case 'GROUPS':
        return BaseFilter.groups;
      default:
        // 하위 호환성: 이전 한국어 키도 지원
        switch (key) {
          case '전체공개':
            return BaseFilter.public;
          case '나만보기':
            return BaseFilter.private;
          case '친구공유':
            return BaseFilter.friends;
          case '그룹공유':
            return BaseFilter.groups;
          default:
            return null;
        }
    }
  }

  /// 시스템 카테고리 키의 로컬라이제이션 키 반환
  ///
  /// UI에서 이 값을 `context.tr()`로 사용하면 됩니다.
  static String getLocalizationKey(String key) {
    switch (key.toUpperCase()) {
      case 'PUBLIC':
        return 'visibility_public'; // '전체공개'
      case 'PRIVATE':
        return 'visibility_private'; // '나만보기'
      case 'FRIENDS':
        return 'visibility_friends'; // '친구공개'
      case 'GROUPS':
        return 'visibility_group'; // '그룹공개'
      default:
        // 하위 호환성: 이전 한국어 키도 지원
        if (key == '전체공개') return 'visibility_public';
        if (key == '나만보기') return 'visibility_private';
        if (key == '친구공유') return 'visibility_friends';
        if (key == '그룹공유') return 'visibility_group';
        return key; // 기본값으로 원본 키 반환
    }
  }

  /// 시스템 카테고리 키의 로컬라이제이션된 표시 텍스트 반환
  ///
  /// UI에서 직접 텍스트가 필요할 때 사용합니다.
  /// 예: `SystemCategoryKeys.getDisplayText(context, SystemCategoryKeys.public)`
  static String getDisplayText(BuildContext context, String key) {
    final locKey = getLocalizationKey(key);
    return AppLocalizations.of(context)?.translate(locKey) ?? key;
  }

  /// 모든 시스템 카테고리 키와 로컬라이제이션 키의 매핑
  static Map<String, String> get localizationKeyMap => {
    public: 'visibility_public',
    private: 'visibility_private',
    friends: 'visibility_friends',
    groups: 'visibility_group',
  };
}
