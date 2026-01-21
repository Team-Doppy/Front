import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/pages/screens/onboarding_screen.dart' show LoginScreen;
import 'package:doppy/pages/components/email_verification_flow.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/auth_service.dart';

class JoinScreen extends StatefulWidget {
  final bool skipModeSelection; // 선택 단계 건너뛰기 (바로 회원가입)
  final bool emailVerificationOnly; // 이메일 인증만 수행 (회원가입 플로우 건너뛰기)
  final VoidCallback? onEmailVerified; // 이메일 인증 완료 시 콜백

  const JoinScreen({
    super.key,
    this.skipModeSelection = false,
    this.emailVerificationOnly = false,
    this.onEmailVerified,
  });

  @override
  _JoinScreenState createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  int _currentStep = 0;
  final AuthService _authService = AuthService();

  // 각 단계별 컨트롤러들
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // 각 단계별 상태
  bool _isIdDuplicateChecked = false;
  bool _isIdAvailable = false;
  bool _isPasswordValid = false;
  bool _isPasswordMatch = false;
  bool _isCheckingDuplicate = false;
  bool _isIdLengthChecked = false; // ID 길이 체크 시도 여부
  String? _verifiedEmail;

  // 비밀번호 표시 여부
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    // skipModeSelection이 true면 바로 회원가입 플로우로 시작
    if (widget.skipModeSelection) {
      _currentStep = 0; // 이메일 인증 단계부터 시작
    }
    // emailVerificationOnly가 true면 이메일 인증만 수행
    if (widget.emailVerificationOnly) {
      _currentStep = 0; // 이메일 인증 단계부터 시작
    }
  }

  List<String> get _stepTitles {
    // emailVerificationOnly 모드일 때는 이메일 인증 단계만 표시
    if (widget.emailVerificationOnly) {
      return [context.tr('join_step_email')];
    }
    return [
      context.tr('join_step_email'),
      context.tr('join_step_id'),
      context.tr('join_step_password'),
      context.tr('join_step_confirm_password'),
      context.tr('join_step_complete'),
    ];
  }

  @override
  void dispose() {
    _idController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading:
            _isCompleteStep()
                ? null
                : GestureDetector(
                  onTap: () async {
                    // emailVerificationOnly 모드면 로그아웃 확인 다이얼로그 표시
                    if (widget.emailVerificationOnly) {
                      final confirmed = await DialogUtils.showConfirmDialog(
                        context,
                        title: context.tr('logout'),
                        message: context.tr('logout_confirm'),
                        confirmText: context.tr('logout'),
                        cancelText: context.tr('cancel'),
                        isDestructive: false,
                      );

                      if (confirmed == true && mounted) {
                        // 로그아웃 처리
                        await AuthProvider().logout();
                        // 온보딩 화면으로 이동 (스택 완전히 비우기)
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      }
                      return;
                    }
                    // skipModeSelection이 true이고 첫 단계면 바로 닫기
                    if (widget.skipModeSelection && _currentStep == 0) {
                      Navigator.pop(context);
                    } else if (_currentStep > 0) {
                      _previousStep();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24, top: 22),
                    child: Text(
                      context.tr('previous'),
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

        bottom:
            _isCompleteStep()
                ? null
                : PreferredSize(
                  preferredSize: const Size.fromHeight(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (_currentStep + 1) / _stepTitles.length,
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
                ),
      ),
      body: IndexedStack(
        index: _currentStep,
        children: [
          _buildEmailVerificationStep(),
          if (!widget.emailVerificationOnly) ...[
            _buildIdStep(),
            _buildPasswordStep(),
            _buildConfirmPasswordStep(),
            _buildCompleteStep(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailVerificationStep() {
    return Column(
      children: [
        Expanded(
          child: EmailVerificationFlow(
            title: context.tr('start_doppy'),
            subtitle: context.tr('join_enter_email_subtitle_signup_initial'),
            codeSentSubtitle: context.tr('join_enter_email_subtitle_signup'),
            initialEmail: _verifiedEmail ?? _emailController.text,
            enabledEmailEdit: true,
            mode:
                widget.emailVerificationOnly
                    ? 'UPDATE'
                    : 'REGISTER', // emailVerificationOnly 모드면 UPDATE 모드 사용
            onVerified: (email) async {
              if (!mounted) return;

              setState(() {
                _verifiedEmail = email;
                _emailController.text = email;
              });

              // emailVerificationOnly 모드면 이메일 업데이트 후 스플래시로 이동
              if (widget.emailVerificationOnly) {
                // 이메일 인증 완료 후 토큰 갱신 (서버에서 새 토큰 발급)
                try {
                  debugPrint('[JoinScreen] 이메일 인증 완료 - 토큰 갱신 시작: $email');
                  final loginResponse = await _authService.updateEmail(
                    email: email,
                  );
                  if (loginResponse != null) {
                    debugPrint('[JoinScreen] ✅ 토큰 갱신 완료');
                    // AuthProvider도 업데이트
                    final authProvider = Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    );
                    await authProvider.validateAndRefreshToken();
                  } else {
                    debugPrint('[JoinScreen] ⚠️ 토큰 갱신 실패 (계속 진행)');
                  }
                } catch (e) {
                  debugPrint('[JoinScreen] ❌ 토큰 갱신 중 오류: $e');
                }

                // 다음 프레임에 네비게이션 실행 (setState 완료 후)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) {
                    debugPrint('[JoinScreen] ⚠️ 위젯이 마운트되지 않음 - 네비게이션 취소');
                    return;
                  }

                  // 스플래시로 이동 (스택 완전히 비우기)
                  debugPrint('[JoinScreen] 스플래시로 이동 시작');
                  try {
                    Navigator.of(context).pushAndRemoveUntil(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const SplashScreen(),
                        transitionDuration: const Duration(milliseconds: 250),
                        transitionsBuilder: (_, animation, __, child) {
                          return FadeTransition(
                            opacity: CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOut,
                            ),
                            child: child,
                          );
                        },
                      ),
                      (route) => false, // 모든 이전 라우트 제거
                    );
                    debugPrint('[JoinScreen] ✅ 스플래시로 이동 완료');
                  } catch (e, stackTrace) {
                    debugPrint('[JoinScreen] ❌ 네비게이션 오류: $e');
                    debugPrint('[JoinScreen] 스택 트레이스: $stackTrace');
                  }
                });
                return;
              }

              _nextStep();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIdStep() {
    return Column(
      children: [
        // 스크롤 가능한 컨텐츠 영역
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              SizedBox(height: 36),
              Text(
                context.tr('join_enter_id_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                context.tr('join_enter_id_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                controller: _idController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: context.tr('join_id_hint'),
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                  prefixIconColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  errorStyle: TextStyle(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  errorText:
                      _isIdLengthChecked && _idController.text.length < 4
                          ? context.tr('join_id_too_short')
                          : (_isIdDuplicateChecked && !_isIdAvailable
                              ? context.tr('join_id_already_used')
                              : null),
                  suffixIcon:
                      _idController.text.isNotEmpty
                          ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _idController.clear();
                                _isIdDuplicateChecked = false;
                                _isIdLengthChecked = false;
                              });
                            },
                          )
                          : null,
                ),
                onSubmitted: (_) {
                  setState(() {
                    _isIdLengthChecked = true;
                  });
                  if (_idController.text.length >= 4) {
                    _handleIdNext();
                  }
                },
                onChanged: (value) {
                  setState(() {
                    _isIdDuplicateChecked = false;
                    _isIdLengthChecked = false;
                  });
                },
              ),
            ],
          ),
        ),

        // 하단 고정 버튼 영역
        (_isCheckingDuplicate || _idController.text.length >= 4)
            ? Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        _isCheckingDuplicate
                            ? null
                            : () {
                              setState(() {
                                _isIdLengthChecked = true;
                              });
                              if (_idController.text.length >= 4) {
                                _handleIdNext();
                              }
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child:
                        _isCheckingDuplicate
                            ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.surface,
                                ),
                              ),
                            )
                            : Text(
                              context.tr('next'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.surface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ),
            )
            : const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      children: [
        // 스크롤 가능한 컨텐츠 영역
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              SizedBox(height: 36),
              Text(
                context.tr('join_set_password_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                context.tr('join_set_password_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                cursorColor: Theme.of(context).colorScheme.onSurface,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: context.tr('password_hint'),
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) {
                  if (_isPasswordValid) {
                    _nextStep();
                  }
                },
                onChanged: (value) {
                  setState(() {
                    _isPasswordValid = _validatePassword(value);
                  });
                },
              ),
              SizedBox(height: 16),
              if (_passwordController.text.isNotEmpty) ...[
                _buildPasswordRequirement(
                  context.tr('join_password_min_length'),
                  _passwordController.text.length >= 8,
                ),
                _buildPasswordRequirement(
                  context.tr('join_password_letter_required'),
                  RegExp(r'[a-zA-Z]').hasMatch(_passwordController.text),
                ),
                _buildPasswordRequirement(
                  context.tr('join_password_number_required'),
                  RegExp(r'[0-9]').hasMatch(_passwordController.text),
                ),
              ],
            ],
          ),
        ),

        // 하단 고정 버튼 영역
        _isPasswordValid
            ? Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      context.tr('next'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.surface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            )
            : const SizedBox.shrink(),
      ],
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
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.9)
                      : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.4),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmPasswordStep() {
    // 🎯 비밀번호 재확인 페이지에 들어올 때마다 가장 먼저 현재 입력값 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final currentMatch =
            _confirmPasswordController.text.isNotEmpty &&
            _confirmPasswordController.text == _passwordController.text;
        if (_isPasswordMatch != currentMatch) {
          setState(() {
            _isPasswordMatch = currentMatch;
          });
        }
      }
    });

    return Column(
      children: [
        // 스크롤 가능한 컨텐츠 영역
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              SizedBox(height: 36),
              Text(
                context.tr('join_confirm_password_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                context.tr('join_confirm_password_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: context.tr('join_confirm_password_hint'),
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                ),
                onSubmitted: (_) {
                  if (_isPasswordMatch && !_isCheckingDuplicate) {
                    _completeSignup();
                  }
                },
                onChanged: (value) {
                  setState(() {
                    _isPasswordMatch = value == _passwordController.text;
                  });
                },
              ),
            ],
          ),
        ),

        // 하단 고정 버튼 영역
        (_isCheckingDuplicate || _isPasswordMatch)
            ? Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        (_isPasswordMatch && !_isCheckingDuplicate)
                            ? _completeSignup
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child:
                        _isCheckingDuplicate
                            ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.surface,
                                ),
                              ),
                            )
                            : Text(
                              context.tr('join_complete_button'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.surface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ),
            )
            : const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildCompleteStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.tr('join_complete_title'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 48),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _validatePassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[a-zA-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  /// 완료 단계인지 확인
  bool _isCompleteStep() {
    return _currentStep == _stepTitles.length - 1;
  }

  void _handleIdNext() {
    if (!_isIdDuplicateChecked) {
      // 중복확인 먼저 수행 (자동으로 다음 단계 진행)
      _checkIdDuplicate();
    } else if (_isIdAvailable) {
      // 중복확인 완료되고 사용 가능하면 다음 단계로
      _nextStep();
    }
  }

  void _checkIdDuplicate() async {
    debugPrint('[-] [JoinScreen] _checkIdDuplicate');
    setState(() {
      _isCheckingDuplicate = true;
    });

    try {
      final isAvailable = await _authService.checkUsernameDuplicate(
        _idController.text,
      );

      debugPrint('[-] [JoinScreen] _checkIdDuplicate: $isAvailable');

      setState(() {
        _isIdDuplicateChecked = true;
        _isIdAvailable = isAvailable;
        _isCheckingDuplicate = false;
      });

      // 사용 가능한 ID라면 바로 다음 단계로
      if (isAvailable) {
        _nextStep();
      }
    } catch (e) {
      setState(() {
        _isIdDuplicateChecked = true;
        _isIdAvailable = false;
        _isCheckingDuplicate = false;
      });

      // 에러 메시지 표시
      if (mounted) {
        ErrorHandler.showError(
          context,
          context.tr('join_id_check_error').replaceAll('{error}', '$e'),
        );
      }
    }
  }

  void _nextStep() {
    if (_currentStep < _stepTitles.length - 1) {
      setState(() {
        _currentStep++;
        // 🎯 비밀번호 재확인 페이지에 들어갈 때마다 현재 입력값 확인
        final confirmPasswordStep = 3; // 비밀번호 확인 단계는 항상 3번째 (0부터 시작)
        if (_currentStep == confirmPasswordStep) {
          _isPasswordMatch =
              _confirmPasswordController.text.isNotEmpty &&
              _confirmPasswordController.text == _passwordController.text;
        }
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        // 첫 번째 단계로 돌아가면 바로 닫기
        if (_currentStep == 0) {
          Navigator.pop(context);
          return;
        }
        // 🎯 비밀번호 재확인 페이지로 돌아올 때도 현재 입력값 확인
        final confirmPasswordStep = 3; // 비밀번호 확인 단계는 항상 3번째 (0부터 시작)
        if (_currentStep == confirmPasswordStep) {
          _isPasswordMatch =
              _confirmPasswordController.text.isNotEmpty &&
              _confirmPasswordController.text == _passwordController.text;
        }
      });
    } else {
      // 첫 단계면 바로 닫기
      Navigator.pop(context);
    }
  }

  void _completeSignup() async {
    // 회원가입 API 호출
    setState(() {
      _isCheckingDuplicate = true; // 로딩 상태로 재사용
    });

    try {
      final region = context.read<LocaleProvider>().regionCode; // 'KR' or 'US'

      final success = await _authService.register(
        username: _idController.text,
        password: _passwordController.text,
        email: _verifiedEmail ?? _emailController.text,
        alias: _idController.text, // username을 alias로 사용
        region: region,
      );

      if (success) {
        // 회원가입 성공
        // 🎯 서버에서 온보딩 플래그를 관리하므로 로컬 플래그 저장 제거
        _nextStep(); // 완료 화면으로 이동

        // 1초 후 스플래시 화면으로 부드럽게 페이드 전환 (로그인 성공 시와 동일)
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          // 🎯 회원가입 후 스플래시로 부드럽게 페이드 전환 (로그인 성공 시와 동일)
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const SplashScreen(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOut,
                  ),
                  child: child,
                );
              },
            ),
            (route) => false,
          );
        }
      } else {
        // 회원가입 실패
        setState(() {
          _isCheckingDuplicate = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('signup_failed_try_again'),
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isCheckingDuplicate = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context
                  .tr('signup_error_with_message')
                  .replaceAll('{error}', '$e'),
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
