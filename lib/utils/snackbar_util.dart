import 'dart:ui';

import 'package:flutter/material.dart';

/// 스낵바 종류: 정보 / 성공 / 로딩 (frosted 스타일 통일)
enum SnackBarVariant { info, loading }

class SnackbarUtil {
  static const _margin = EdgeInsets.only(bottom: 0, left: 16, right: 16);
  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  );

  /// onSurface 기반 반투명 + ClipRRect + blur 5 적용한 스낵바 공통 래퍼
  /// 등장 시 페이드인, 사라질 때 페이드아웃
  static Widget _frostedSnackbarContent(
    BuildContext context,
    Duration duration,
    Widget child,
  ) {
    return _AnimatedFrostedContent(
      duration: duration,
      child: child,
      builder: (context, child) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: onSurface.withOpacity(0.98),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// frosted 스타일 통일: [variant]로 info / success / loading 구분
  /// - loading: 스피너 + 메시지, 스와이프 불가, duration 기본 1분
  /// - success: 체크 아이콘 + 메시지
  /// - info: 정보 아이콘 + 메시지, [action] 지원
  static void show(
    BuildContext context,
    String message, {
    SnackBarVariant variant = SnackBarVariant.info,
    Duration? duration,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    final fg = Theme.of(context).colorScheme.surface;
    final isLoading = variant == SnackBarVariant.loading;

    Widget? leading;
    switch (variant) {
      case SnackBarVariant.loading:
        leading = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(fg),
          ),
        );
        break;
      case SnackBarVariant.info:
        leading = null;
        break;
    }

    final effectiveDuration =
        duration ??
        (isLoading ? const Duration(minutes: 1) : const Duration(seconds: 2));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _frostedSnackbarContent(
          context,
          effectiveDuration,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading ?? const SizedBox.shrink(),
              leading != null
                  ? const SizedBox(width: 12)
                  : const SizedBox(width: 4),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        dismissDirection:
            isLoading ? DismissDirection.none : DismissDirection.down,
        duration: effectiveDuration,
        margin: _margin,
        elevation: 0,
        action: isLoading ? null : action,
      ),
    );
  }

  /// 로딩 스낵바 (show(..., variant: SnackBarVariant.loading) 단축)
  static void showLoading(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context,
      message,
      variant: SnackBarVariant.loading,
      duration: duration,
    );
  }

  /// 정보 스낵바 (show(..., variant: SnackBarVariant.info) 단축)
  static void showInfo(
    BuildContext context,
    String message, {
    Duration? duration,
    SnackBarAction? action,
  }) {
    show(
      context,
      message,
      variant: SnackBarVariant.info,
      duration: duration,
      action: action,
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
    final message =
        customMessage ??
        (messageOrError is String
            ? messageOrError
            : _toUserMessage(messageOrError));

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
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
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
    if (s.contains('FormatException') ||
        s.contains('Unexpected') ||
        s.contains('jsonDecode') ||
        s.contains('JSON'))
      return serverErr;
    if (s.contains('SocketException') ||
        s.contains('NetworkException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection refused'))
      return '인터넷 연결을 확인해주세요.';
    if (s.contains('TimeoutException') || s.contains('timeout'))
      return '요청 시간이 초과되었습니다. 다시 시도해주세요.';
    if (s.contains('502') || s.contains('Bad Gateway'))
      return '서버 연결에 실패했습니다. 잠시 후 다시 시도해주세요.';
    if (s.contains('500') || s.contains('Internal Server Error'))
      return '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    if (s.contains('ExpiredJwtException') || s.contains('JWT expired'))
      return '로그인 세션이 만료되었습니다. 다시 로그인해주세요.';
    if (s.contains('토큰 갱신')) return '인증 정보를 갱신할 수 없습니다. 다시 로그인해주세요.';

    final codeMatch = RegExp(
      r'(?:error code:|status code:|code:)\s*(\d{3})',
      caseSensitive: false,
    ).firstMatch(s);
    if (codeMatch != null)
      return _httpMessage(int.tryParse(codeMatch.group(1)!));

    final httpMatch = RegExp(r'(\d{3})').firstMatch(s);
    if (s.contains('HttpException') && httpMatch != null)
      return _httpMessage(int.tryParse(httpMatch.group(1)!));

    if (s.startsWith('StateError: ') || s.startsWith('Exception: ')) {
      final msg = s.substring(s.indexOf(': ') + 2);
      return (msg.contains('FormatException') || msg.contains('Unexpected'))
          ? serverErr
          : msg;
    }
    if (s.length > 100 ||
        s.contains('Exception') ||
        s.contains('Error:') ||
        s.contains('at '))
      return '오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
    return s;
  }

  static String _httpMessage(int? code) {
    if (code == null) return '알 수 없는 오류가 발생했습니다.';
    switch (code) {
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
        return '오류가 발생했습니다. (코드: $code)';
    }
  }
}

/// 스낵바 표시 시간에 맞춰 페이드인 → 유지 → 페이드아웃
class _AnimatedFrostedContent extends StatefulWidget {
  final Duration duration;
  final Widget child;
  final Widget Function(BuildContext context, Widget child) builder;

  const _AnimatedFrostedContent({
    required this.duration,
    required this.child,
    required this.builder,
  });

  @override
  State<_AnimatedFrostedContent> createState() =>
      _AnimatedFrostedContentState();
}

class _AnimatedFrostedContentState extends State<_AnimatedFrostedContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final totalMs = widget.duration.inMilliseconds.toDouble();
    const fadeInMs = 380;
    const fadeOutMs = 350;
    final w1 = (fadeInMs / totalMs).clamp(0.0, 1.0);
    final w3 = (fadeOutMs / totalMs).clamp(0.0, 1.0);
    final w2 = (1.0 - w1 - w3).clamp(0.0, 1.0);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: w1,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: w2),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: w3,
      ),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      AnimatedBuilder(
        animation: _opacity,
        builder: (context, child) {
          return Opacity(opacity: _opacity.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
