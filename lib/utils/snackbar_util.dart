import 'package:flutter/material.dart';

class SnackbarUtil {
  static const _margin = EdgeInsets.only(bottom: 24, left: 16, right: 16);
  static final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));

  /// 정보 스낵바
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    Color? bgColor,
    Color? fgColor,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = bgColor ?? (isDark ? Colors.white : Colors.black);
    final fg = fgColor ?? (isDark ? Colors.black87 : Colors.white);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _buildContent(message, Icons.info_outline, fg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        shape: _shape,
        elevation: 12,
        duration: duration,
        action: action,
        margin: _margin,
      ),
    );
  }

  /// 에러 스낵바 (문자열 또는 Exception)
  static void showError(
    BuildContext context,
    dynamic messageOrError, {
    String? customMessage,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    final message = customMessage ??
        (messageOrError is String ? messageOrError : _toUserMessage(messageOrError));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _buildContent(message, Icons.error_outline, Colors.white),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        shape: _shape,
        elevation: 12,
        duration: duration,
        action: action,
        margin: _margin,
      ),
    );
    debugPrint('❌ $message');
  }

  static Widget _buildContent(String message, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  static String _toUserMessage(dynamic e) {
    if (e == null) return '알 수 없는 오류가 발생했습니다.';
    final s = e.toString();

    const serverErr = '서버 응답을 처리하는 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    if (s.contains('FormatException') || s.contains('Unexpected') || s.contains('jsonDecode') || s.contains('JSON')) return serverErr;
    if (s.contains('SocketException') || s.contains('NetworkException') || s.contains('Failed host lookup') || s.contains('Connection refused')) return '인터넷 연결을 확인해주세요.';
    if (s.contains('TimeoutException') || s.contains('timeout')) return '요청 시간이 초과되었습니다. 다시 시도해주세요.';
    if (s.contains('502') || s.contains('Bad Gateway')) return '서버 연결에 실패했습니다. 잠시 후 다시 시도해주세요.';
    if (s.contains('500') || s.contains('Internal Server Error')) return '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    if (s.contains('ExpiredJwtException') || s.contains('JWT expired')) return '로그인 세션이 만료되었습니다. 다시 로그인해주세요.';
    if (s.contains('토큰 갱신')) return '인증 정보를 갱신할 수 없습니다. 다시 로그인해주세요.';

    final codeMatch = RegExp(r'(?:error code:|status code:|code:)\s*(\d{3})', caseSensitive: false).firstMatch(s);
    if (codeMatch != null) return _httpMessage(int.tryParse(codeMatch.group(1)!));

    final httpMatch = RegExp(r'(\d{3})').firstMatch(s);
    if (s.contains('HttpException') && httpMatch != null) return _httpMessage(int.tryParse(httpMatch.group(1)!));

    if (s.startsWith('StateError: ') || s.startsWith('Exception: ')) {
      final msg = s.substring(s.indexOf(': ') + 2);
      return (msg.contains('FormatException') || msg.contains('Unexpected')) ? serverErr : msg;
    }
    if (s.length > 100 || s.contains('Exception') || s.contains('Error:') || s.contains('at ')) return '오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    return s;
  }

  static String _httpMessage(int? code) {
    if (code == null) return '알 수 없는 오류가 발생했습니다.';
    switch (code) {
      case 400: return '잘못된 요청입니다.';
      case 401: return '인증이 필요합니다. 다시 로그인해주세요.';
      case 403: return '접근 권한이 없습니다.';
      case 404: return '요청한 리소스를 찾을 수 없습니다.';
      case 409: return '중복된 요청입니다.';
      case 429: return '너무 많은 요청을 보냈습니다. 잠시 후 다시 시도해주세요.';
      case 500: return '서버 오류가 발생했습니다.';
      case 502: return '서버 연결에 실패했습니다.';
      case 503: return '서비스를 일시적으로 사용할 수 없습니다.';
      default: return '오류가 발생했습니다. (코드: $code)';
    }
  }
}
