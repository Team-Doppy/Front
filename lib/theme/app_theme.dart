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
        primary: AppColors.primary,
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

      // ===== AppBar Theme =====
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: AppColors.primary,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ===== Text Selection Theme =====
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
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
        primary: AppColors.primary,
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

      // ===== AppBar Theme =====
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: AppColors.primary,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // ===== Text Selection Theme =====
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
      ),

      // ===== PopupMenu Theme =====
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.darkBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ===== Scaffold Background =====
      scaffoldBackgroundColor: AppColors.darkBackground,
    );
  }
}
