import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  // OS 언어 기반으로 초기값 설정
  Locale _locale = _getSystemLocale();

  Locale get locale => _locale;

  /// 지역 코드 (JWT에 사용)
  /// 한국어면 KR, 아니면 다 US
  String get regionCode {
    if (_locale.languageCode == 'ko') {
      return 'KR';
    } else {
      return 'US';
    }
  }

  LocaleProvider() {
    // OS 언어 기반으로 초기화
    _initializeFromSystem();
  }

  /// OS 언어를 동기적으로 감지하여 초기 Locale 설정
  static Locale _getSystemLocale() {
    try {
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;

      // 한국어면 KR, 아니면 US
      if (systemLocale.languageCode == 'ko') {
        return const Locale('ko', 'KR');
      } else {
        return const Locale('en', 'US');
      }
    } catch (e) {
      print('[LocaleProvider] 시스템 언어 감지 실패: $e');
      // 기본값: 영어
      return const Locale('en', 'US');
    }
  }

  /// OS 언어 기반으로 초기화 (비동기로 저장)
  Future<void> _initializeFromSystem() async {
    try {
      // OS 언어 감지
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;

      if (systemLocale.languageCode == 'ko') {
        _locale = const Locale('ko', 'KR');
      } else {
        _locale = const Locale('en', 'US');
      }

      // 감지된 언어 저장
      await _saveLocale();
      notifyListeners();

      print('[LocaleProvider] OS 언어 기반 초기화: ${_locale.languageCode}');
    } catch (e) {
      print('[LocaleProvider] OS 언어 기반 초기화 실패: $e');
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
