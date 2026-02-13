import 'package:flutter/material.dart';
import 'editor_localization.dart';

/// 앱 전역에서 사용하는 다이얼로그 유틸리티
class DialogUtils {
  /// 확인/취소 다이얼로그
  ///
  /// [title] - 다이얼로그 제목
  /// [message] - 다이얼로그 내용
  /// [confirmText] - 확인 버튼 텍스트 (기본: "확인")
  /// [cancelText] - 취소 버튼 텍스트 (기본: "취소")
  /// [isDestructive] - 확인 버튼을 빨간색(위험)으로 표시할지 여부
  ///
  /// 반환: 확인 버튼 클릭 시 true, 취소 버튼 클릭 시 false, 바깥 클릭 시 null
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    bool isDestructive = false,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = confirmText ?? context.tr('editor_confirm');
    final cancel = cancelText ?? context.tr('editor_cancel');

    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 270,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title and Message
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        _buildMessageWidget(message, isDark),
                      ],
                    ),
                  ),

                  // Divider
                  Container(
                    height: 0.5,
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.2),
                  ),

                  // Buttons
                  Row(
                    children: [
                      // Cancel Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(false),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(20),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                cancel,
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF0A84FF)
                                      : const Color(0xFF007AFF),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Vertical Divider
                      Container(
                        width: 0.5,
                        height: 44,
                        color: isDark
                            ? Colors.white.withOpacity(0.2)
                            : Colors.black.withOpacity(0.2),
                      ),

                      // Confirm Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(true),
                          child: Container(
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(20),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                confirm,
                                style: TextStyle(
                                  color: isDestructive
                                      ? const Color(0xFFFF3B30)
                                      : isDark
                                      ? const Color(0xFF0A84FF)
                                      : const Color(0xFF007AFF),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.1, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 정보 알림 다이얼로그 (확인 버튼만)
  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = '확인',
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 270,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title and Message
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withOpacity(0.6)
                                : Colors.black.withOpacity(0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  Container(
                    height: 0.5,
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.2),
                  ),

                  // Button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 44,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          buttonText,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF0A84FF)
                                : const Color(0xFF007AFF),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.1, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// 메시지 위젯 빌드 (밑줄 지원)
  static Widget _buildMessageWidget(String message, bool isDark) {
    // 🎯 밑줄이 필요한 텍스트 감지 (예: "나만보기로 전환됩니다")
    if (message.contains('나만보기로 전환됩니다')) {
      final parts = message.split('나만보기로 전환됩니다');
      if (parts.length == 2) {
        return RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            children: [
              TextSpan(text: parts[0]),
              TextSpan(
                text: '나만보기로 전환됩니다',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: isDark
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.6),
                ),
              ),
              TextSpan(text: parts[1]),
            ],
          ),
        );
      }
    }

    // 🎯 일반 텍스트
    return Text(
      message,
      style: TextStyle(
        color: isDark
            ? Colors.white.withOpacity(0.6)
            : Colors.black.withOpacity(0.6),
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 텍스트 입력 다이얼로그 (공통 디자인)
  /// 반환: 확인 시 입력 문자열, 취소/바깥 클릭 시 null
  static Future<String?> showTextInputDialog(
    BuildContext context, {
    required String title,
    String? hintText,
    String? initialText,
    String? confirmText,
    String? cancelText,
    int? maxLines, // 🎯 여러 줄 입력 지원 (null이면 1줄)
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: initialText ?? '');
    final confirm = confirmText ?? context.tr('editor_confirm');
    final cancel = cancelText ?? context.tr('editor_cancel');

    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: TextField(
                            controller: controller,
                            autofocus: true,
                            maxLines: maxLines,
                            minLines: maxLines != null
                                ? (maxLines > 1 ? 3 : 1)
                                : 1,
                            textInputAction: maxLines != null && maxLines > 1
                                ? TextInputAction.newline
                                : TextInputAction.done,
                            cursorColor: isDark
                                ? Colors.white
                                : const Color(0xFF007AFF),
                            decoration: InputDecoration(
                              hintText: hintText,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF3A3A3C)
                                  : Colors.white,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 15,
                            ),
                            onSubmitted: maxLines == null || maxLines == 1
                                ? (v) {
                                    Navigator.of(context).pop(v.trim());
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Divider
                  Container(
                    height: 0.5,
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.2),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(null),
                          child: Container(
                            height: 44,
                            child: Center(
                              child: Text(
                                cancel,
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF0A84FF)
                                      : const Color(0xFF007AFF),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 0.5,
                        height: 44,
                        color: isDark
                            ? Colors.white.withOpacity(0.2)
                            : Colors.black.withOpacity(0.2),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              Navigator.of(context).pop(controller.text.trim()),
                          child: Container(
                            height: 44,
                            child: Center(
                              child: Text(
                                confirm,
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF0A84FF)
                                      : const Color(0xFF007AFF),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.1, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
