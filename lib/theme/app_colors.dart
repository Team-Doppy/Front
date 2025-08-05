import 'package:flutter/material.dart';

/// 넷플릭스 스타일 앱 색상 정의 (다크/라이트 테마 지원)
class AppColors {
  AppColors._(); // private constructor

  // ===== Primary Colors (연한 푸른색) =====
  static const Color primary = Color.fromARGB(255, 91, 181, 255); // 연한 푸른색
  static const Color primaryDark = Color(0xFF1976D2); // 진한 푸른색
  static const Color primaryLight = Color(0xFF90CAF9); // 더 연한 푸른색

  // ===== Accent Colors =====
  static const Color accent = Color(0xFFE0E0E0); // 중성 회색
  static const Color accentDark = Color(0xFF424242); // 진한 회색

  // ===== Light Theme Colors =====
  static const Color lightBackground = Color(0xFFFFFFFF); // 순백
  static const Color lightSurface = Color(0xFFFAFAFA); // 약간 회색 배경
  static const Color lightSurfaceVariant = Color(0xFFF5F5F5); // 더 진한 회색
  static const Color lightTextPrimary = Color(0xFF1A1A1A); // 거의 검정
  static const Color lightTextSecondary = Color(0xFF666666); // 중간 회색
  static const Color lightBorder = Color(0xFFE5E5E5); // 연한 테두리

  // ===== Dark Theme Colors (넷플릭스 스타일) =====
  static const Color darkBackground = Color(0xFF0F0F0F); // 넷플릭스 배경
  static const Color darkSurface = Color(0xFF1A1A1A); // 카드/패널 배경
  static const Color darkSurfaceVariant = Color(0xFF2A2A2A); // 더 밝은 패널
  static const Color darkTextPrimary = Color(0xFFFFFFFF); // 순백 텍스트
  static const Color darkTextSecondary = Color(0xFFB3B3B3); // 회색 텍스트
  static const Color darkBorder = Color(0xFF333333); // 진한 테두리

  // ===== UI State Colors =====
  static const Color error = Color(0xFFFF5252); // 에러 색상

  // ===== Utility Methods =====
  /// 테마에 따른 배경색 반환
  static Color getBackground(bool isDark) =>
      isDark ? darkBackground : lightBackground;

  /// 테마에 따른 표면색 반환
  static Color getSurface(bool isDark) => isDark ? darkSurface : lightSurface;

  /// 테마에 따른 텍스트색 반환
  static Color getTextPrimary(bool isDark) =>
      isDark ? darkTextPrimary : lightTextPrimary;

  /// 테마에 따른 보조 텍스트색 반환
  static Color getTextSecondary(bool isDark) =>
      isDark ? darkTextSecondary : lightTextSecondary;

  /// 테마에 따른 테두리색 반환
  static Color getBorder(bool isDark) => isDark ? darkBorder : lightBorder;
}
