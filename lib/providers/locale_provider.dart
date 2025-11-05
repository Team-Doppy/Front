import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('ko', 'KR'); // 기본값: 한국어

  Locale get locale => _locale;

  /// 지역 코드 (JWT에 사용)
  String get regionCode {
    switch (_locale.languageCode) {
      case 'ko':
        return 'KR';
      case 'en':
        return 'US';
      default:
        return 'KR';
    }
  }

  LocaleProvider() {
    _loadLocale();
  }

  /// 저장된 언어 설정 로드
  Future<void> _loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('languageCode');
      final countryCode = prefs.getString('countryCode');

      if (languageCode != null) {
        _locale = Locale(languageCode, countryCode);
        notifyListeners();
      } else {
        // 저장된 설정이 없으면 시스템 언어 감지
        await _detectSystemLocale();
      }
    } catch (e) {
      print('[LocaleProvider] 언어 설정 로드 실패: $e');
    }
  }

  /// 시스템 언어 감지 (네이티브)
  Future<void> _detectSystemLocale() async {
    try {
      // Flutter가 감지한 시스템 언어
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;

      // 지원하는 언어인지 확인
      if (systemLocale.languageCode == 'ko') {
        _locale = const Locale('ko', 'KR');
      } else if (systemLocale.languageCode == 'en') {
        _locale = const Locale('en', 'US');
      } else {
        // 기타 언어는 영어로 폴백
        _locale = const Locale('en', 'US');
      }

      // 감지된 언어 저장
      await _saveLocale();
      notifyListeners();

      print('[LocaleProvider] 시스템 언어 감지: ${_locale.languageCode}');
    } catch (e) {
      print('[LocaleProvider] 시스템 언어 감지 실패: $e');
    }
  }

  /// 언어 변경
  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;

    _locale = locale;
    await _saveLocale();
    notifyListeners();

    print('[LocaleProvider] 언어 변경: ${locale.languageCode}');
  }

  /// 언어 설정 저장
  Future<void> _saveLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('languageCode', _locale.languageCode);
      if (_locale.countryCode != null) {
        await prefs.setString('countryCode', _locale.countryCode!);
      }
    } catch (e) {
      print('[LocaleProvider] 언어 설정 저장 실패: $e');
    }
  }

  /// 한국어로 전환
  Future<void> setKorean() async {
    await setLocale(const Locale('ko', 'KR'));
  }

  /// 영어로 전환
  Future<void> setEnglish() async {
    await setLocale(const Locale('en', 'US'));
  }

  /// 토글 (한/영 전환)
  Future<void> toggleLocale() async {
    if (_locale.languageCode == 'ko') {
      await setEnglish();
    } else {
      await setKorean();
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
