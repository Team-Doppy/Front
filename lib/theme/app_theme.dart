import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

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
        primary: AppColors.primaryLight, // Light theme: 어두운 청록색
        primaryContainer: AppColors.primaryLight,
        secondary: AppColors.accent,
        surface: AppColors.lightSurface,
        surfaceVariant: AppColors.lightSurfaceVariant,
        background: AppColors.lightBackground,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: AppColors.lightTextPrimary,
        onSurface: AppColors.lightTextPrimary,
        onBackground: AppColors.lightTextPrimary,
        onError: Colors.white,
      ),

      // ===== Text Theme =====
      textTheme: TextTheme(
        // displayLarge: AppTextStyles.withThemeColor(
        //   AppTextStyles.displayLarge,
        //   false,
        // ),
        // displayMedium: AppTextStyles.withThemeColor(
        //   AppTextStyles.displayMedium,
        //   false,
        // ),
        // displaySmall: AppTextStyles.withThemeColor(
        //   AppTextStyles.displaySmall,
        //   false,
        // ),
        headlineLarge: AppTextStyles.withThemeColor(
          AppTextStyles.headlineLarge,
          false,
        ),
        headlineMedium: AppTextStyles.withThemeColor(
          AppTextStyles.headlineMedium,
          false,
        ),
        headlineSmall: AppTextStyles.withThemeColor(
          AppTextStyles.headlineSmall,
          false,
        ),
        bodyLarge: AppTextStyles.withThemeColor(AppTextStyles.bodyLarge, false),
        bodyMedium: AppTextStyles.withThemeColor(
          AppTextStyles.bodyMedium,
          false,
        ),
        bodySmall: AppTextStyles.withThemeColor(
          AppTextStyles.bodySmall,
          false,
          isSecondary: true,
        ),
        labelLarge: AppTextStyles.withThemeColor(
          AppTextStyles.labelLarge,
          false,
        ),
        labelMedium: AppTextStyles.withThemeColor(
          AppTextStyles.labelMedium,
          false,
        ),
        labelSmall: AppTextStyles.withThemeColor(
          AppTextStyles.labelSmall,
          false,
          isSecondary: true,
        ),
      ),

      // ===== AppBar Theme =====
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: AppColors.primaryLight,
        titleTextStyle: AppTextStyles.withThemeColor(
          AppTextStyles.headlineMedium,
          false,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ===== Text Selection Theme =====
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryLight,
        selectionHandleColor: AppColors.primaryLight,
      ),

      // ===== PopupMenu Theme =====
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.lightBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        primary: AppColors.primaryDark, // Dark theme: 밝은 청록색
        primaryContainer: AppColors.primaryDark,
        secondary: AppColors.accentDark,
        surface: AppColors.darkSurface,
        surfaceVariant: AppColors.darkSurfaceVariant,
        background: AppColors.darkBackground,
        error: AppColors.error,
        onPrimary: Colors.black,
        onSecondary: AppColors.darkTextPrimary,
        onSurface: AppColors.darkTextPrimary,
        onBackground: AppColors.darkTextPrimary,
        onError: Colors.black,
      ),

      // ===== Text Theme =====
      textTheme: TextTheme(
        // displayLarge: AppTextStyles.withThemeColor(
        //   AppTextStyles.displayLarge,
        //   true,
        // ),
        // displayMedium: AppTextStyles.withThemeColor(
        //   AppTextStyles.displayMedium,
        //   true,
        // ),
        // displaySmall: AppTextStyles.withThemeColor(
        //   AppTextStyles.displaySmall,
        //   true,
        // ),
        headlineLarge: AppTextStyles.withThemeColor(
          AppTextStyles.headlineLarge,
          true,
        ),
        headlineMedium: AppTextStyles.withThemeColor(
          AppTextStyles.headlineMedium,
          true,
        ),
        headlineSmall: AppTextStyles.withThemeColor(
          AppTextStyles.headlineSmall,
          true,
        ),
        bodyLarge: AppTextStyles.withThemeColor(AppTextStyles.bodyLarge, true),
        bodyMedium: AppTextStyles.withThemeColor(
          AppTextStyles.bodyMedium,
          true,
        ),
        bodySmall: AppTextStyles.withThemeColor(
          AppTextStyles.bodySmall,
          true,
          isSecondary: true,
        ),
        labelLarge: AppTextStyles.withThemeColor(
          AppTextStyles.labelLarge,
          true,
        ),
        labelMedium: AppTextStyles.withThemeColor(
          AppTextStyles.labelMedium,
          true,
        ),
        labelSmall: AppTextStyles.withThemeColor(
          AppTextStyles.labelSmall,
          true,
          isSecondary: true,
        ),
      ),

      // ===== AppBar Theme =====
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: AppColors.primaryDark,
        titleTextStyle: AppTextStyles.withThemeColor(
          AppTextStyles.headlineMedium,
          true,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // ===== Text Selection Theme =====
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryDark,
        selectionHandleColor: AppColors.primaryDark,
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
