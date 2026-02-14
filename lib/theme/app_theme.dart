import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// 넷플릭스 스타일 앱 테마
class AppTheme {
  AppTheme._(); // private constructor

  // ===== Light Theme =====
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // ===== Color Scheme =====
      colorScheme: ColorScheme.light(
        primary: AppColors.primaryLight,
        primaryContainer: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: AppColors.lightSurface,
        surfaceContainerHighest: AppColors.lightSurfaceVariant,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: AppColors.lightTextPrimary,
        onSurface: AppColors.lightTextPrimary,
        onError: Colors.white,
        background: AppColors.lightBackground,
        surfaceVariant: AppColors.lightSurfaceVariant,
      ),

      // ===== Text Selection Theme =====
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryLight,
        selectionHandleColor: AppColors.primaryLight,
      ),

      // ===== Scaffold Background =====
      scaffoldBackgroundColor: AppColors.lightBackground,
    );
  }

  // ===== Dark Theme =====
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // ===== Color Scheme =====
      colorScheme: ColorScheme.dark(
        primary: AppColors.primaryDark,
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.accentDark,
        surface: AppColors.darkSurface,
        surfaceContainerHighest: AppColors.darkSurface,
        error: AppColors.error,
        onPrimary: Colors.black,
        onSecondary: AppColors.darkTextPrimary,
        onSurface: AppColors.darkTextPrimary,
        onError: Colors.black,
        background: AppColors.darkBackground,
        surfaceVariant: AppColors.darkSurfaceVariant,
      ),

      // ===== Text Selection Theme =====
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryDark,
        selectionHandleColor: AppColors.primaryDark,
      ),

      // ===== Scaffold Background =====
      scaffoldBackgroundColor: AppColors.darkBackground,
    );
  }
}
