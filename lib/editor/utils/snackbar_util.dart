import 'package:flutter/material.dart';

/// 스낵바 표시 유틸리티
class SnackbarUtil {
  SnackbarUtil._();

  /// 에러 스낵바 표시
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 12.0,
        duration: duration,
        action: action,
        margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      ),
    );
  }

  /// 정보 스낵바 표시
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    Color? bgColor,
    Color? fgColor,
    SnackBarAction? action,
    Widget? leading,
  }) {
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final _bgColor = bgColor ?? (isDark ? Colors.white : Colors.black);
    final _fgColor = fgColor ?? (isDark ? Colors.black87 : Colors.white);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: 12),
              ] else ...[
                Icon(Icons.info_outline, color: _fgColor, size: 20),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: _fgColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: _bgColor.withOpacity(0.5),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 12.0,
        duration: duration,
        action: action,
        margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      ),
    );
  }
}
