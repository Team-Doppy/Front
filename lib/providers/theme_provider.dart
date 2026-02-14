import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
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

  bool isDarkMode() {
    return _themeMode == ThemeMode.dark;
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
          orElse: () => ThemeMode.light,
        );
        notifyListeners();
      } else {
        _themeMode = ThemeMode.light;
        notifyListeners();
      }
    } catch (e) {
      _themeMode = ThemeMode.light;
      notifyListeners();
    }
  }
}
