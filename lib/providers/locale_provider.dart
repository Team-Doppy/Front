import 'package:flutter/material.dart';
import 'package:doppy/main.dart' show kTestForceKorean;

class LocaleProvider extends ChangeNotifier {
  // OS 언어 기반으로 초기값 설정
  Locale _locale = _getSystemLocale();

  Locale get locale => _locale;

  /// 지역 코드 (JWT에 사용)
  /// 🎯 기기 로케일의 국가 코드 우선 사용, 없으면 언어 코드로 판단
  /// - 국가 코드가 'KR'이면 → 'KR'
  /// - 국가 코드가 'US', 'GB', 'CA', 'AU', 'NZ' 등 영어권이면 → 'US'
  /// - 국가 코드가 없으면 언어 코드로 판단 (ko → KR, 그 외 → US)
  String get regionCode {
    // 🎯 1순위: 국가 코드 활용 (더 정확)
    if (_locale.countryCode != null && _locale.countryCode!.isNotEmpty) {
      final countryCode = _locale.countryCode!.toUpperCase();

      // 한국
      if (countryCode == 'KR') {
        return 'KR';
      }

      // 영어권 국가들 (US, GB, CA, AU, NZ, IE, SG 등)
      // 이들은 모두 'US' region으로 그룹화
      if (['US', 'GB', 'CA', 'AU', 'NZ', 'IE', 'SG'].contains(countryCode)) {
        return 'US';
      }

      // 기타 국가는 언어 코드로 판단
      // (예: 'JP', 'CN' 등은 언어 코드 확인)
    }

    // 🎯 2순위: 언어 코드로 판단 (국가 코드가 없거나 위에 없는 경우)
    if (_locale.languageCode == 'ko') {
      return 'KR';
    } else {
      return 'US';
    }
  }

  LocaleProvider() {
    // OS 언어만 사용 (언어 변경 불가)
    _initialize();
  }

  /// OS 언어를 동기적으로 감지하여 초기 Locale 설정
  /// 🎯 테스트 플래그(kTestForceKorean)가 있으면 우선 사용
  static Locale _getSystemLocale() {
    try {
      // 🎯 테스트용 플래그 확인
      if (kTestForceKorean == true) {
        debugPrint('[LocaleProvider] 테스트 플래그: 한국어 강제');
        return const Locale('ko', 'KR');
      } else if (kTestForceKorean == false) {
        debugPrint('[LocaleProvider] 테스트 플래그: 영어 강제');
        return const Locale('en', 'US');
      }

      // 실제 OS 로케일 사용 (언어 + 국가 코드)
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;

      debugPrint(
        '[LocaleProvider] OS 로케일: language=${systemLocale.languageCode}, country=${systemLocale.countryCode ?? "없음"}',
      );

      // 🎯 기기 로케일 그대로 사용 (언어 코드 + 국가 코드 모두 포함)
      // Locale 객체는 이미 languageCode와 countryCode를 모두 가지고 있음
      return systemLocale;
    } catch (e) {
      debugPrint('[LocaleProvider] 시스템 언어 감지 실패: $e');
      // 기본값: 영어
      return const Locale('en', 'US');
    }
  }

  /// OS 언어 기반으로 초기화 (언어 변경 불가)
  Future<void> _initialize() async {
    try {
      // 🎯 항상 OS 언어 사용 (저장된 언어 무시)
      _locale = _getSystemLocale();
      debugPrint('[LocaleProvider] OS 언어 기반 초기화: ${_locale.languageCode}');
      notifyListeners();
    } catch (e) {
      debugPrint('[LocaleProvider] 초기화 실패: $e');
    }
  }

  /// 현재 언어가 한국어인지 확인
  bool get isKorean => _locale.languageCode == 'ko';

  /// 현재 언어가 영어인지 확인
  bool get isEnglish => _locale.languageCode == 'en';

  /// 간단한 번역 헬퍼 (context 없이 사용 가능)
  String translate(String key, Map<String, Map<String, String>> translations) {
    final langCode = _locale.languageCode;
    return translations[langCode]?[key] ?? key;
  }
}
