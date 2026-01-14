import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/find_email_verification_flow.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';

class FindIdScreen extends StatefulWidget {
  const FindIdScreen({super.key});

  @override
  State<FindIdScreen> createState() => _FindIdScreenState();
}

class _FindIdScreenState extends State<FindIdScreen> {
  final AuthService _authService = AuthService();
  String? _verifiedEmail;
  String? _verifiedCode; // 이메일 인증 시 받은 인증 코드 저장
  String? _foundUsername;
  String? _errorMessage;
  int _currentStep = 0; // 0: 이메일 인증, 1: 결과

  // 비밀번호 변경 관련
  bool _showPasswordChange = false;
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _changingPassword = false;
  String? _passwordError;

  Future<void> _findUsername() async {
    if (_verifiedEmail == null) return;

    setState(() {
      _errorMessage = null;
    });

    try {
      final username = await _authService.findUsername(_verifiedEmail!);

      if (!mounted) return;

      if (username != null && username.isNotEmpty) {
        setState(() {
          _foundUsername = username;
          _currentStep = 1;
        });
      } else {
        setState(() {
          _errorMessage = '사용자를 찾을 수 없습니다';
        });
      }
    } catch (e) {
      if (!mounted) return;

      // 에러 메시지 처리
      String errorMessage = ErrorHandler.getErrorMessage(e);
      final errorString = e.toString();

      // API 에러 코드 확인
      if (errorString.contains('EMAIL_NOT_VERIFIED')) {
        errorMessage = '이메일이 인증되지 않았습니다';
      } else if (errorString.contains('USER_NOT_FOUND')) {
        errorMessage = '사용자를 찾을 수 없습니다';
      } else if (errorString.contains('FIND_USERNAME_FAILED')) {
        errorMessage = '아이디 찾기에 실패했습니다';
      }

      setState(() {
        _errorMessage = errorMessage;
      });
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  bool _isValidPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[a-zA-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  Future<void> _changePassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    setState(() {
      _passwordError = null;
    });

    if (!_isValidPassword(newPassword)) {
      setState(() {
        _passwordError = '비밀번호가 너무 짧습니다';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _passwordError = '비밀번호가 일치하지 않습니다';
      });
      return;
    }

    setState(() {
      _changingPassword = true;
    });

    try {
      // 이전에 받은 인증 코드를 사용하여 비밀번호 변경
      if (_verifiedCode == null || _verifiedCode!.isEmpty) {
        setState(() {
          _changingPassword = false;
          _passwordError = '인증 코드가 만료되었거나 유효하지 않습니다';
        });
        return;
      }

      final success = await _authService.changePassword(
        username: _foundUsername ?? '',
        email: _verifiedEmail ?? '',
        code: _verifiedCode!,
        newPassword: newPassword,
      );

      if (!mounted) return;

      if (success) {
        // 비밀번호 변경 성공 - 성공 메시지 표시 후 로그인 화면으로 이동
        ErrorHandler.showInfo(context, context.tr('password_change_success'));

        // 로그인 화면으로 이동 (모든 화면 제거)
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      } else {
        setState(() {
          _changingPassword = false;
          _passwordError = '비밀번호 변경에 실패했습니다';
        });
      }
    } catch (e) {
      if (!mounted) return;

      String errorMessage = ErrorHandler.getErrorMessage(e);
      final errorString = e.toString();

      // 구체적인 에러 코드에 따른 사용자 친화적인 메시지
      if (errorString.contains('VERIFICATION_CODE_EXPIRED')) {
        errorMessage = context.tr('error_verification_code_expired');
      } else if (errorString.contains('VERIFICATION_CODE_INVALID') ||
          errorString.contains('INVALID_VERIFICATION_CODE')) {
        errorMessage = context.tr('error_verification_code_invalid');
      } else if (errorString.contains('VERIFICATION_CODE_EXPIRED_OR_INVALID')) {
        errorMessage = context.tr('error_verification_code_expired_or_invalid');
      } else if (errorString.contains('PASSWORD_TOO_SHORT')) {
        errorMessage = context.tr('error_password_too_short');
      } else if (errorString.contains('PASSWORD_TOO_LONG')) {
        errorMessage = context.tr('error_password_too_long');
      } else if (errorString.contains('PASSWORD_SAME_AS_OLD')) {
        errorMessage = context.tr('error_password_same_as_old');
      } else if (errorString.contains('USERNAME_EMAIL_MISMATCH')) {
        errorMessage = context.tr('error_username_email_mismatch');
      } else if (errorString.contains('USER_NOT_FOUND')) {
        errorMessage = context.tr('error_user_not_found');
      } else if (errorString.contains('EMAIL_NOT_VERIFIED')) {
        errorMessage = context.tr('error_email_not_verified');
      } else if (errorString.contains('PASSWORD_CHANGE_FAILED')) {
        errorMessage = '비밀번호 변경에 실패했습니다. 다시 시도해주세요.';
      } else {
        // 일반적인 에러는 기본 메시지 사용
        errorMessage = '비밀번호 변경 중 오류가 발생했습니다. 다시 시도해주세요.';
      }

      setState(() {
        _changingPassword = false;
        _passwordError = errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            // 키보드 내리기
            FocusScope.of(context).unfocus();

            if (_currentStep == 1) {
              // 결과 화면일 때는 onboarding_screen으로 돌아가기
              Navigator.popUntil(context, (route) => route.isFirst);
            } else {
              // 이메일 인증 화면일 때는 이전 화면으로
              Navigator.pop(context);
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 24, top: 22),
            child: Text(
              _currentStep == 1 ? '확인' : '이전',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        bottom:
            _currentStep == 0
                ? PreferredSize(
                  preferredSize: const Size.fromHeight(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: 0.5,
                        minHeight: 8,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ),
                )
                : null,
      ),
      body: IndexedStack(
        index: _currentStep,
        children: [
          _buildEmailVerificationStep(),
          if (_foundUsername != null) _buildResultScreen(),
        ],
      ),
    );
  }

  Widget _buildEmailVerificationStep() {
    return Column(
      children: [
        Expanded(
          child: FindEmailVerificationFlow(
            title: '아이디/비밀번호 찾기',
            subtitle: '이메일 인증을 통해 아이디를 찾을 수 있습니다',
            onVerified: (email, code) async {
              _verifiedEmail = email;
              _verifiedCode = code;
              await _findUsername();
            },
          ),
        ),

        if (_errorMessage != null) ...[
          Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultScreen() {
    // 키보드가 올라왔는지 확인
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return GestureDetector(
      onTap: () {
        // 여백을 누르면 키보드 내리기
        FocusScope.of(context).unfocus();
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Spacer(flex: 1),

          // 아이디 표시 - 키보드 올라올 때 숨기기
          if (keyboardHeight <= 0)
            AnimatedOpacity(
              opacity: isKeyboardVisible ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                transform: Matrix4.translationValues(
                  0,
                  isKeyboardVisible ? -50 : 0,
                  0,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.5),
                  ),
                  child: Text(
                    _foundUsername ?? '',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.9),
                    ),
                  ),
                ),
              ),
            ),

          // find_password 링크 (토글) - 키보드 올라올 때 숨기기
          if (keyboardHeight <= 0)
            AnimatedOpacity(
              opacity: isKeyboardVisible ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedContainer(
                margin: const EdgeInsets.symmetric(vertical: 20),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                transform: Matrix4.translationValues(
                  0,
                  isKeyboardVisible ? 50 : 0,
                  0,
                ),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showPasswordChange = !_showPasswordChange;
                      // 접을 때 입력 필드 초기화
                      if (!_showPasswordChange) {
                        _newPasswordController.clear();
                        _confirmPasswordController.clear();
                        _passwordError = null;
                      }
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '비밀번호 변경',
                        style: TextStyle(
                          fontSize: 17,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showPasswordChange
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.9),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 비밀번호 변경 필드
          if (_showPasswordChange) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  // 새 비밀번호 입력 필드
                  TextField(
                    controller: _newPasswordController,
                    focusNode: _newPasswordFocusNode,
                    obscureText: _obscureNewPassword,
                    cursorColor: Theme.of(context).colorScheme.onSurface,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: '새 비밀번호를 입력하세요',
                      hintStyle: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(1),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 30,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.lock_outline_rounded
                              : Icons.lock_open_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureNewPassword = !_obscureNewPassword;
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        // 에러가 있으면 입력 시작 시 에러 메시지 제거
                        if (_passwordError != null) {
                          _passwordError = null;
                        }
                      });
                    },
                    onSubmitted: (_) {
                      FocusScope.of(
                        context,
                      ).requestFocus(_confirmPasswordFocusNode);
                    },
                  ),

                  const SizedBox(height: 6),
                  // 비밀번호 확인 입력 필드
                  TextField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocusNode,
                    obscureText: _obscureConfirmPassword,
                    cursorColor: Theme.of(context).colorScheme.onSurface,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 30,
                      ),
                      hintText: '비밀번호 확인',
                      hintStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.lock_outline_rounded
                              : Icons.lock_open_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                    onSubmitted: (_) {
                      if (_newPasswordController.text.trim().isNotEmpty &&
                          _confirmPasswordController.text.trim().isNotEmpty &&
                          !_changingPassword) {
                        _changePassword();
                      }
                    },
                  ),
                ],
              ),
            ),
            if (_passwordError != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _passwordError!,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildPasswordRequirement(
                    context.tr('join_password_min_length'),
                    _newPasswordController.text.length >= 8,
                  ),
                  _buildPasswordRequirement(
                    context.tr('join_password_letter_required'),
                    RegExp(r'[a-zA-Z]').hasMatch(_newPasswordController.text),
                  ),
                  _buildPasswordRequirement(
                    context.tr('join_password_number_required'),
                    RegExp(r'[0-9]').hasMatch(_newPasswordController.text),
                  ),
                ],
              ),
            ),

            Spacer(flex: 2),

            // 비밀번호 변경 버튼 - 키보드 올라올 때 숨기기
            AnimatedOpacity(
              opacity: isKeyboardVisible ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                transform: Matrix4.translationValues(
                  0,
                  isKeyboardVisible ? 50 : 0,
                  0,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 75),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
                        backgroundColor:
                            (_isValidPassword(
                                      _newPasswordController.text.trim(),
                                    ) &&
                                    _newPasswordController.text.trim() ==
                                        _confirmPasswordController.text
                                            .trim() &&
                                    !_changingPassword &&
                                    _passwordError == null)
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.grey[400],
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      onPressed:
                          (_isValidPassword(
                                    _newPasswordController.text.trim(),
                                  ) &&
                                  _newPasswordController.text.trim() ==
                                      _confirmPasswordController.text.trim() &&
                                  !_changingPassword &&
                                  _passwordError == null)
                              ? _changePassword
                              : null,
                      child:
                          _changingPassword
                              ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              )
                              : Text(
                                '비밀번호 변경하기',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                              ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 40),
          ] else ...[
            Spacer(flex: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordRequirement(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check : Icons.close,
            size: 16,
            color:
                isValid
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.4),
          ),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color:
                  isValid
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
