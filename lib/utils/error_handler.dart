import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 앱 전역에서 사용하는 에러 핸들러
class ErrorHandler {
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
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
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
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: duration,
        action: action,
      ),
    );
  }

  /// 경고 스낵바 표시
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_amber_outlined, color: Colors.white, size: 20),
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
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: duration,
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
  }) {
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final _bgColor = bgColor ?? (isDark ? Colors.white : Colors.black);
    final _fgColor = fgColor ?? (isDark ? Colors.black87 : Colors.white);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: _fgColor, size: 20),
              const SizedBox(width: 12),
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
        backgroundColor: _bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: duration,
        margin: const EdgeInsets.only(
          bottom: 22, // ← 올릴 높이 (px)
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  /// HTTP 에러 코드에 따른 메시지 반환
  static String getHttpErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return '잘못된 요청입니다.';
      case 401:
        return '인증이 필요합니다. 다시 로그인해주세요.';
      case 403:
        return '접근 권한이 없습니다.';
      case 404:
        return '요청한 리소스를 찾을 수 없습니다.';
      case 409:
        return '중복된 요청입니다.';
      case 429:
        return '너무 많은 요청을 보냈습니다. 잠시 후 다시 시도해주세요.';
      case 500:
        return '서버 오류가 발생했습니다.';
      case 502:
        return '서버 연결에 실패했습니다.';
      case 503:
        return '서비스를 일시적으로 사용할 수 없습니다.';
      default:
        return '오류가 발생했습니다. (코드: $statusCode)';
    }
  }

  /// Exception을 사용자 친화적인 메시지로 변환
  static String getErrorMessage(dynamic error) {
    if (error == null) return '알 수 없는 오류가 발생했습니다.';

    final errorString = error.toString();

    // 네트워크 오류
    if (errorString.contains('SocketException') ||
        errorString.contains('NetworkException')) {
      return '인터넷 연결을 확인해주세요.';
    }

    // 타임아웃 오류
    if (errorString.contains('TimeoutException')) {
      return '요청 시간이 초과되었습니다. 다시 시도해주세요.';
    }

    // JWT 토큰 만료
    if (errorString.contains('ExpiredJwtException') ||
        errorString.contains('JWT expired')) {
      return '로그인 세션이 만료되었습니다. 다시 로그인해주세요.';
    }

    // 토큰 갱신 실패
    if (errorString.contains('토큰 갱신')) {
      return '인증 정보를 갱신할 수 없습니다. 다시 로그인해주세요.';
    }

    // HTTP 에러
    if (errorString.contains('HttpException')) {
      final statusCodeMatch = RegExp(r'(\d{3})').firstMatch(errorString);
      if (statusCodeMatch != null) {
        final statusCode = int.parse(statusCodeMatch.group(1)!);
        return getHttpErrorMessage(statusCode);
      }
    }

    // Exception 메시지 추출
    if (errorString.startsWith('Exception: ')) {
      return errorString.substring('Exception: '.length);
    }

    // 기본 메시지
    return errorString.length > 100 ? '오류가 발생했습니다.' : errorString;
  }

  /// 에러를 처리하고 스낵바 표시
  static void handleError(
    BuildContext context,
    dynamic error, {
    String? customMessage,
    SnackBarAction? action,
  }) {
    String message = customMessage ?? getErrorMessage(error);

    // 🎯 세션 만료 에러는 로케일 적용
    final errorString = error.toString();
    if (errorString.contains('ExpiredJwtException') ||
        errorString.contains('JWT expired')) {
      message = AppLocalizations.of(context).translate('session_expired_error');
    }

    showError(context, message, action: action);

    // 에러 로깅
    print('❌ [ErrorHandler] $message');
    print('❌ [ErrorHandler] Original error: $error');
  }

  /// 토큰 갱신 실패 시 재로그인 유도
  static void handleTokenRefreshFailure(BuildContext context) {
    final localization = AppLocalizations.of(context);
    showError(
      context,
      localization.translate('session_expired_snackbar'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: localization.translate('login'),
        textColor: Colors.white,
        onPressed: () {
          // TODO: 로그인 화면으로 이동
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        },
      ),
    );
  }
}
