import 'dart:async';

import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/locale_provider.dart';

/// 아이디 찾기/비밀번호 재설정용 이메일 인증 컴포넌트
class FindEmailVerificationFlow extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? initialEmail;
  final Future<void> Function(String verifiedEmail, String verifiedCode)
  onVerified;

  const FindEmailVerificationFlow({
    super.key,
    required this.title,
    required this.subtitle,
    this.initialEmail,
    required this.onVerified,
  });

  @override
  State<FindEmailVerificationFlow> createState() =>
      _FindEmailVerificationFlowState();
}

class _FindEmailVerificationFlowState extends State<FindEmailVerificationFlow> {
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
    final now = DateTime.now();
    final until = _cooldownUntil;
    if (until != null) {
      final remain = until.difference(now);
      final newRemaining = remain.isNegative ? Duration.zero : remain;
      if (_remaining != newRemaining) {
        setState(() {
          _remaining = newRemaining;
        });
      }
      if (remain.isNegative || remain == Duration.zero) {
        _cooldownUntil = null;
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

    if (_remaining > Duration.zero) return;

    setState(() {
      _sending = true;
    });

    try {
      final localeProvider = Provider.of<LocaleProvider>(
        context,
        listen: false,
      );
      final region = localeProvider.isKorean ? 'KR' : 'US';

      final result = await _authService.sendEmailVerificationCode(
        email: email,
        region: region,
        mode: 'FIND',
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _codeSent = true;
          _sending = false;
          _failedAttempts = 0;
          _codeController.clear();
        });

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
      } else {
        // 에러 코드별 메시지 처리
        final errorCode = result.error?.error;
        String errorMessage =
            result.message ?? context.tr('email_verification_send_first');

        if (errorCode != null) {
          switch (errorCode) {
            case 'EMAIL_NOT_FOUND':
              errorMessage = context.tr('error_email_not_found');
              break;
            case 'INVALID_EMAIL_FORMAT':
              errorMessage = context.tr('error_invalid_email_format');
              break;
            case 'RATE_LIMIT_EXCEEDED':
              errorMessage = context.tr('error_rate_limit_exceeded');
              break;
            case 'EMAIL_REQUIRED':
              errorMessage = context.tr('error_email_required');
              break;
            case 'SEND_CODE_FAILED':
              // 서버 메시지 그대로 사용
              break;
            default:
              // 기본 메시지 사용
              break;
          }
        }

        setState(() {
          _sending = false;
          _emailError = errorMessage;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _emailError = ErrorHandler.getErrorMessage(e);
      });
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
        code: code,
        mode: 'FIND',
      );

      if (!mounted) return;

      if (result.success && (result.verified ?? true)) {
        await widget.onVerified(email, code);
      } else {
        // 에러 코드별 메시지 처리
        final errorCode = result.error?.error;
        String errorMessage =
            result.message ?? context.tr('email_verification_code_mismatch');

        if (errorCode != null) {
          switch (errorCode) {
            case 'VERIFICATION_CODE_EXPIRED':
              errorMessage = context.tr('error_verification_code_expired');
              _codeController.clear();
              _codeSent = false;
              break;
            case 'INVALID_VERIFICATION_CODE':
              errorMessage = context.tr('error_verification_code_invalid');
              break;
            case 'VERIFY_FAILED':
              // 서버 메시지 그대로 사용
              break;
            default:
              // 기본 메시지 사용
              break;
          }
        }

        setState(() {
          _verifying = false;
          _failedAttempts++;
          _pinError = errorMessage;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _failedAttempts++;
        _pinError = ErrorHandler.getErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
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
                    fontSize: 26,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                // 이메일 입력 필드
                TextField(
                  controller: _emailController,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  cursorColor: theme.colorScheme.onSurface,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: context.tr('email_verification_email_hint'),
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
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
                              : theme.colorScheme.onSurfaceVariant.withOpacity(
                                0.5,
                              ),
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          _emailError != null
                              ? BorderSide(
                                color: theme.colorScheme.error,
                                width: 1.5,
                              )
                              : BorderSide.none,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          _emailError != null
                              ? BorderSide(
                                color: theme.colorScheme.error,
                                width: 1.5,
                              )
                              : BorderSide.none,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.error,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.error,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    errorText: _emailError,
                    errorStyle: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    errorMaxLines: 2,
                  ),
                  onChanged: (_) {
                    setState(() {
                      if (_emailError != null) {
                        _emailError = null;
                      }
                    });
                  },
                  onSubmitted: (_) {
                    final canSend =
                        !_sending && _remaining == Duration.zero && !_codeSent;
                    if (canSend) _sendCode();
                  },
                ),

                // 인증 코드 입력 필드
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    enabled: !_verifying,
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
                      hintText: context.tr('email_verification_code_hint'),
                      hintStyle: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceVariant,
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color:
                            _pinError != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.5),
                      ),
                      suffixIcon:
                          _remaining > Duration.zero
                              ? Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatDuration(_remaining),
                                      style: TextStyle(
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity(0.6),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                ),
                              )
                              : null,
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            _pinError != null
                                ? BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 1.5,
                                )
                                : BorderSide.none,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            _pinError != null
                                ? BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 1.5,
                                )
                                : BorderSide.none,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      errorText: _pinError,
                      errorStyle: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      errorMaxLines: 2,
                      counterText: '',
                    ),
                    onChanged: (_) {
                      setState(() {
                        if (_pinError != null) {
                          _pinError = null;
                        }
                      });
                    },
                    onSubmitted: (_) {
                      final canVerify =
                          !_verifying &&
                          _codeController.text.trim().length == 6;
                      if (canVerify) _verifyCode();
                    },
                  ),
                  const SizedBox(height: 12),
                  // 재발송 버튼 - 10초 쿨다운 후 부드럽게 나타남
                  AnimatedOpacity(
                    opacity: _remaining == Duration.zero ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed:
                            (!_sending && _remaining == Duration.zero)
                                ? _sendCode
                                : null,
                        child: Text(
                          context.tr('email_verification_resend_code'),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.5),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                    ? // 🎯 인증 버튼: 로딩 중이거나 활성화되어 있을 때만 표시
                    (_verifying ||
                            (!_sending &&
                                _codeController.text.trim().length == 6))
                        ? SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed:
                                (!_verifying &&
                                        !_sending &&
                                        _codeController.text.trim().length == 6)
                                    ? _verifyCode
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.onSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            child:
                                _verifying
                                    ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  theme.colorScheme.onSurface,
                                                ),
                                          ),
                                        ),
                                      ],
                                    )
                                    : Text(
                                      context.tr('email_verification_verify'),
                                      style: TextStyle(
                                        color: theme.colorScheme.surface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                          ),
                        )
                        : const SizedBox.shrink()
                    : // 🎯 발송 버튼: 로딩 중이거나 활성화되어 있을 때만 표시
                    (_sending ||
                        (_remaining == Duration.zero &&
                            _isValidEmail(_emailController.text.trim())))
                    ? SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            (!_sending &&
                                    _remaining == Duration.zero &&
                                    _isValidEmail(_emailController.text.trim()))
                                ? _sendCode
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _sending
                                ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              theme.colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                  ],
                                )
                                : Text(
                                  context.tr('email_verification_send_code'),
                                  style: TextStyle(
                                    color: theme.colorScheme.surface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                      ),
                    )
                    : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
