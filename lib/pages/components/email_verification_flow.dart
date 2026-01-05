import 'dart:async';

import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/locale_provider.dart';

class EmailVerificationFlow extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? initialEmail;
  final bool enabledEmailEdit;
  final Future<void> Function(String verifiedEmail) onVerified;

  const EmailVerificationFlow({
    super.key,
    required this.title,
    required this.subtitle,
    this.initialEmail,
    this.enabledEmailEdit = true,
    required this.onVerified,
  });

  @override
  State<EmailVerificationFlow> createState() => _EmailVerificationFlowState();
}

class _EmailVerificationFlowState extends State<EmailVerificationFlow> {
  final AuthService _authService = AuthService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _sending = false;
  bool _verifying = false;

  bool _codeSent = false;
  DateTime? _cooldownUntil;
  Timer? _timer;
  Duration _remaining = Duration.zero;

  int _failedAttempts = 0;
  static const int _maxAttempts = 5;

  String? _emailError;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final s = email.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
  }

  void _startCooldown(Duration duration) {
    _timer?.cancel();
    _cooldownUntil = DateTime.now().add(duration);
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final until = _cooldownUntil;
    if (until == null) return;
    final now = DateTime.now();
    final remain = until.difference(now);
    setState(() {
      _remaining = remain.isNegative ? Duration.zero : remain;
    });
    if (remain.isNegative || remain == Duration.zero) {
      _timer?.cancel();
      _timer = null;
    }
  }

  String _mmss(Duration d) {
    final s = d.inSeconds.clamp(0, 24 * 3600);
    final m = (s ~/ 60).toString().padLeft(1, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    setState(() {
      _emailError = null;
      _pinError = null;
    });

    if (!_isValidEmail(email)) {
      setState(() {
        _emailError = context.tr('email_verification_invalid_email');
      });
      return;
    }

    // 5분 쿨다운(서버 레이트리밋) 중이면 막기
    if (_remaining > Duration.zero) return;

    setState(() {
      _sending = true;
    });

    try {
      final region = context.read<LocaleProvider>().regionCode;
      final result = await _authService.sendEmailVerificationCode(
        email: email,
        region: region,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _codeSent = true;
          _failedAttempts = 0;
          _codeController.clear();
        });

        // 서버에서 만료시간을 받았으면 사용, 없으면 기본값 5분
        Duration cooldownDuration = const Duration(minutes: 5);
        if (result.expiresAt != null) {
          final now = DateTime.now();
          final expiresAt = result.expiresAt!;
          if (expiresAt.isAfter(now)) {
            cooldownDuration = expiresAt.difference(now);
          }
        } else if (result.expiresIn != null && result.expiresIn! > 0) {
          cooldownDuration = Duration(seconds: result.expiresIn!);
        }

        _startCooldown(cooldownDuration);
        // 인증번호 발송 성공 메시지는 스낵바로 표시하지 않음 (화면 전환으로 충분)
      } else {
        final code = result.error?.error;
        // 사용자 친화적인 메시지로 변환
        final msg =
            result.error?.message ??
            result.message ??
            ErrorHandler.getHttpErrorMessage(result.statusCode ?? 400);

        // 서버 에러코드에 맞춘 UX
        if (code == 'SEND_CODE_FAILED') {
          setState(() {
            _emailError = msg;
          });
        } else {
          // 기술적 에러 메시지 필터링
          final userFriendlyMsg = ErrorHandler.getErrorMessage(msg);
          ErrorHandler.showError(context, userFriendlyMsg);
        }
      }
    } catch (e) {
      if (!mounted) return;
      // catch 블록의 에러도 사용자 친화적으로 변환
      ErrorHandler.handleError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    setState(() {
      _emailError = null;
      _pinError = null;
    });

    if (!_codeSent) {
      setState(() {
        _pinError = context.tr('email_verification_send_first');
      });
      return;
    }
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _pinError = context.tr('email_verification_enter_6_digits');
      });
      return;
    }

    if (_failedAttempts >= _maxAttempts) {
      setState(() {
        _pinError = context.tr('email_verification_too_many_attempts');
      });
      return;
    }

    setState(() {
      _verifying = true;
    });

    try {
      final result = await _authService.verifyEmailCode(
        email: email,
        code: _codeController.text.trim(),
      );
      if (!mounted) return;

      if (result.success && (result.verified ?? true)) {
        // 인증 성공 메시지는 스낵바로 표시하지 않음 (다음 단계로 진행)
        await widget.onVerified(email);
      } else {
        final code = result.error?.error;
        // 사용자 친화적인 메시지로 변환
        final rawMsg =
            result.error?.message ??
            result.message ??
            ErrorHandler.getHttpErrorMessage(result.statusCode ?? 400);
        final msg = ErrorHandler.getErrorMessage(rawMsg);

        if (code == 'INVALID_VERIFICATION_CODE') {
          setState(() {
            _failedAttempts += 1;
            final remain = (_maxAttempts - _failedAttempts).clamp(
              0,
              _maxAttempts,
            );
            _pinError =
                remain > 0
                    ? context
                        .tr('email_verification_code_mismatch')
                        .replaceAll('{count}', '$remain')
                    : context.tr('email_verification_too_many_attempts');
          });
        } else if (code == 'VERIFICATION_CODE_EXPIRED' ||
            code == 'VERIFICATION_CODE_NOT_FOUND') {
          setState(() {
            _codeController.clear();
            _codeSent = false;
            _pinError = msg;
          });
        } else {
          setState(() {
            _pinError = msg;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      // catch 블록의 에러도 사용자 친화적으로 변환
      ErrorHandler.handleError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // 스크롤 가능한 컨텐츠 영역
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 36),
                Text(
                  widget.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),

                // 이메일 입력 필드
                TextField(
                  controller: _emailController,
                  enabled: widget.enabledEmailEdit && !_sending && !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  cursorColor: theme.colorScheme.onSurface,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: context.tr('email_verification_email_label'),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    hintText: context.tr('email_verification_email_hint'),
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    filled: true,
                    fillColor:
                        _codeSent
                            ? theme.colorScheme.surfaceVariant.withOpacity(0.5)
                            : theme.colorScheme.surfaceVariant,
                    prefixIcon: Icon(
                      Icons.alternate_email_rounded,
                      size: 20,
                      color:
                          _emailError != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color:
                            _emailError != null
                                ? theme.colorScheme.error
                                : Colors.transparent,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color:
                            _emailError != null
                                ? theme.colorScheme.error
                                : Colors.transparent,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color:
                            _emailError != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    errorText: _emailError,
                    errorStyle: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                  onSubmitted: (_) {
                    final canSend =
                        !_sending && _remaining == Duration.zero && !_codeSent;
                    if (canSend) _sendCode();
                  },
                ),

                // 인증번호 입력 필드 (코드 발송 후 표시)
                if (_codeSent) ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeController,
                    enabled: !_sending && !_verifying,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    cursorColor: theme.colorScheme.onSurface,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: context.tr('email_verification_code_label'),
                      labelStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      hintText: context.tr('email_verification_code_hint'),
                      hintStyle: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceVariant,
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color:
                            _pinError != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                      ),
                      suffixIcon:
                          _remaining > Duration.zero
                              ? Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 18,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _mmss(_remaining),
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              : null,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color:
                              _pinError != null
                                  ? theme.colorScheme.error
                                  : Colors.transparent,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color:
                              _pinError != null
                                  ? theme.colorScheme.error
                                  : Colors.transparent,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color:
                              _pinError != null
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      errorText: _pinError,
                      errorStyle: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      counterText: '',
                    ),
                    onChanged: (value) {
                      if (_pinError != null) {
                        setState(() => _pinError = null);
                      }
                    },
                    onSubmitted: (_) {
                      final canVerify = !_verifying && !_sending;
                      if (canVerify) _verifyCode();
                    },
                  ),
                  const SizedBox(height: 12),
                  // 재발송 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed:
                            (!_sending && _remaining == Duration.zero)
                                ? _sendCode
                                : null,
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color:
                              (!_sending && _remaining == Duration.zero)
                                  ? theme.colorScheme.primary
                                  : Colors.grey[400],
                        ),
                        label: Text(
                          _remaining > Duration.zero
                              ? context
                                  .tr('email_verification_resend_in')
                                  .replaceAll('{time}', _mmss(_remaining))
                              : context.tr('email_verification_resend_code'),
                          style: TextStyle(
                            color:
                                (!_sending && _remaining == Duration.zero)
                                    ? theme.colorScheme.primary
                                    : Colors.grey[400],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // 하단 여백 (키보드가 올라올 때 버튼과 겹치지 않도록)
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),

        // 하단 고정 버튼 영역 (키보드가 올라올 때 따라 올라감)
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child:
                _codeSent
                    ? SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed:
                            (!_verifying && !_sending) ? _verifyCode : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (!_verifying && !_sending)
                                  ? theme.colorScheme.onSurface
                                  : Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _verifying
                                ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.surface,
                                    ),
                                  ),
                                )
                                : Text(
                                  context.tr('email_verification_verify'),
                                  style: TextStyle(
                                    color:
                                        (!_verifying && !_sending)
                                            ? theme.colorScheme.surface
                                            : Colors.grey[600],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                      ),
                    )
                    : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed:
                            (!_sending && _remaining == Duration.zero)
                                ? _sendCode
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (!_sending && _remaining == Duration.zero)
                                  ? theme.colorScheme.onSurface
                                  : Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _sending
                                ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.surface,
                                    ),
                                  ),
                                )
                                : Text(
                                  context.tr('email_verification_send_code'),
                                  style: TextStyle(
                                    color:
                                        (!_sending &&
                                                _remaining == Duration.zero)
                                            ? theme.colorScheme.surface
                                            : Colors.grey[600],
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}
