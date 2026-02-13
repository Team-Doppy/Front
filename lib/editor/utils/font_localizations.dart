/// 폰트 선택 위젯 로케일 설정
///
/// 폰트 선택 UI에 사용되는 모든 문자열을 중앙에서 관리합니다.
class FontSelectionLocalizations {
  FontSelectionLocalizations._();

  /// 한국어 번역
  static const Map<String, String> ko = {
    'search_hint': '폰트 검색',
    'category_all': '전체',
    'category_handwriting': '손글씨',
    'category_sans_serif': '산세리프',
    'category_serif': '세리프',
    'category_display': '디스플레이',
    'category_monospace': '모노스페이스',
    'default_font': '기본 산세리프',
    'preview_korean': '가나다 ABCD 1234',
    'preview_english': 'ABCD 1234 !?',
  };

  /// 영어 번역
  static const Map<String, String> en = {
    'search_hint': 'Search fonts',
    'category_all': 'All',
    'category_handwriting': 'Handwriting',
    'category_sans_serif': 'Sans Serif',
    'category_serif': 'Serif',
    'category_display': 'Display',
    'category_monospace': 'Monospace',
    'default_font': 'Default Sans Serif',
    'preview_korean': '가나다 ABCD 1234',
    'preview_english': 'ABCD 1234 !?',
  };

  /// 현재 로케일에 맞는 번역 반환
  static String translate(String key, {required bool isEnglish}) {
    final translations = isEnglish ? en : ko;
    return translations[key] ?? key;
  }

  /// 카테고리 이름 반환
  static String getCategoryName(String category, {required bool isEnglish}) {
    final categoryKey =
        'category_${category.toLowerCase().replaceAll(' ', '_')}';
    return translate(categoryKey, isEnglish: isEnglish);
  }
}
