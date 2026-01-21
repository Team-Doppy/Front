import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark; // 🎯 기본값: 다크 테마
  static const String _themeKey = 'theme_mode';

  ThemeProvider() {
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;

  /// 테마 모드 변경 및 저장
  void setThemeMode(ThemeMode themeMode) {
    _themeMode = themeMode;
    _saveThemeMode();
    notifyListeners();
  }

  /// 라이트/다크 테마를 단순 토글합니다.
  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _saveThemeMode();
    notifyListeners();
  }

  /// SharedPreferences에 테마 모드 저장
  Future<void> _saveThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, _themeMode.name);
    } catch (e) {
      debugPrint('[ThemeProvider] 테마 모드 저장 실패: $e');
    }
  }

  /// SharedPreferences에서 테마 모드 로드
  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themeKey);
      if (savedTheme != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == savedTheme,
          orElse: () => ThemeMode.dark, // 🎯 저장된 테마가 유효하지 않을 때 기본값: 다크 테마
        );
        notifyListeners();
      } else {
        // 🎯 저장된 테마가 없을 때 기본값: 다크 테마 (처음 설치 시)
        _themeMode = ThemeMode.dark;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ThemeProvider] 테마 모드 로드 실패: $e');
      // 에러 발생 시에도 기본값: 다크 테마
      _themeMode = ThemeMode.dark;
      notifyListeners();
    }
  }
}
