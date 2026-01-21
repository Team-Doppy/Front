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
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
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
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down, // 아래로 스와이프하여 닫기
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 12.0, // 🎯 바텀 네비게이션 바 위에 표시되도록 높은 elevation
        duration: duration,
        margin: const EdgeInsets.only(
          bottom: 24, // ← 올릴 높이 (px)
          left: 16,
          right: 16,
        ),
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
        backgroundColor: _bgColor,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down, // 아래로 스와이프하여 닫기
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 12.0, // 🎯 바텀 네비게이션 바 위에 표시되도록 높은 elevation
        duration: duration,
        action: action,
        margin: const EdgeInsets.only(
          bottom: 24, // ← 올릴 높이 (px)
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

    // FormatException (JSON 파싱 에러 등)
    if (errorString.contains('FormatException') ||
        errorString.contains('Unexpected character')) {
      return '서버 응답을 처리하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }

    // JSON 파싱 에러
    if (errorString.contains('jsonDecode') || errorString.contains('JSON')) {
      return '서버 응답을 처리하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }

    // 네트워크 오류
    if (errorString.contains('SocketException') ||
        errorString.contains('NetworkException') ||
        errorString.contains('Failed host lookup') ||
        errorString.contains('Connection refused')) {
      return '인터넷 연결을 확인해주세요.';
    }

    // 타임아웃 오류
    if (errorString.contains('TimeoutException') ||
        errorString.contains('timeout')) {
      return '요청 시간이 초과되었습니다. 다시 시도해주세요.';
    }

    // 502 Bad Gateway 에러
    if (errorString.contains('502') || errorString.contains('Bad Gateway')) {
      return '서버 연결에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }

    // 500 Internal Server Error
    if (errorString.contains('500') ||
        errorString.contains('Internal Server Error')) {
      return '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
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

    // HTTP 에러 코드 추출 (예: "error code: 502")
    final statusCodeMatch = RegExp(
      r'(?:error code:|status code:|code:)\s*(\d{3})',
      caseSensitive: false,
    ).firstMatch(errorString);
    if (statusCodeMatch != null) {
      final statusCode = int.tryParse(statusCodeMatch.group(1)!);
      if (statusCode != null) {
        return getHttpErrorMessage(statusCode);
      }
    }

    // HTTP 에러
    if (errorString.contains('HttpException')) {
      final statusCodeMatch = RegExp(r'(\d{3})').firstMatch(errorString);
      if (statusCodeMatch != null) {
        final statusCode = int.tryParse(statusCodeMatch.group(1)!);
        if (statusCode != null) {
          return getHttpErrorMessage(statusCode);
        }
      }
    }

    // StateError 메시지 추출 (기술적 메시지 제거)
    if (errorString.startsWith('StateError: ')) {
      final msg = errorString.substring('StateError: '.length);
      // 기술적 메시지면 일반 메시지로 변환
      if (msg.contains('FormatException') || msg.contains('Unexpected')) {
        return '서버 응답을 처리하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
      }
      return msg;
    }

    // Exception 메시지 추출 (기술적 메시지 제거)
    if (errorString.startsWith('Exception: ')) {
      final msg = errorString.substring('Exception: '.length);
      // 기술적 메시지면 일반 메시지로 변환
      if (msg.contains('FormatException') || msg.contains('Unexpected')) {
        return '서버 응답을 처리하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
      }
      return msg;
    }

    // 기술적 에러 메시지 필터링
    if (errorString.contains('FormatException') ||
        errorString.contains('Unexpected character') ||
        errorString.contains('at character') ||
        errorString.contains('jsonDecode')) {
      return '서버 응답을 처리하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }

    // 기본 메시지 (너무 길거나 기술적이면 일반 메시지로)
    if (errorString.length > 100 ||
        errorString.contains('Exception') ||
        errorString.contains('Error:') ||
        errorString.contains('at ')) {
      return '오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }

    return errorString;
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
    debugPrint('❌ [ErrorHandler] $message');
    debugPrint('❌ [ErrorHandler] Original error: $error');
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
