import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/pages/screens/setting_screen.dart';
import 'package:doppy/main.dart' show AppConstants;
import 'package:doppy/pages/components/email_verification_flow.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/auth_service.dart';

enum AuthMode { login, signup }

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  _JoinScreenState createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  AuthMode? _selectedMode; // null이면 선택 화면
  int _currentStep = 0;
  final AuthService _authService = AuthService();

  // 각 단계별 컨트롤러들
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // 로그인 필드 포커스 제어용
  final FocusNode _loginIdFocusNode = FocusNode();
  final FocusNode _loginPasswordFocusNode = FocusNode();

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

  List<String> get _stepTitles {
    if (_selectedMode == null) {
      return [context.tr('join_auth_mode_selection')];
    } else if (_selectedMode == AuthMode.login) {
      return [context.tr('login')];
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
    _loginIdFocusNode.dispose();
    _loginPasswordFocusNode.dispose();
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

        leading: GestureDetector(
          onTap: () {
            if (_currentStep > 0) {
              _previousStep();
            } else {
              Navigator.pop(context);
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 20, top: 22),
            child: Text(
              context.tr('previous'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(1),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        bottom: PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(
              value:
                  _selectedMode == null
                      ? 0.25 // 선택 화면에서는 100% (1/1)
                      : (_currentStep + 1) /
                          _stepTitles.length, // 선택 후에는 현재 단계 / 전체 단계
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentStep,
        children:
            _selectedMode == null
                ? [_buildModeSelectionStep()]
                : _selectedMode == AuthMode.login
                ? [_buildModeSelectionStep(), _buildLoginStep()]
                : [
                  _buildModeSelectionStep(),
                  _buildEmailVerificationStep(),
                  _buildIdStep(),
                  _buildPasswordStep(),
                  _buildConfirmPasswordStep(),
                  _buildCompleteStep(),
                ],
      ),
    );
  }

  Widget _buildEmailVerificationStep() {
    return Column(
      children: [
        Expanded(
          child: EmailVerificationFlow(
            title: context.tr('join_enter_email_title'),
            subtitle: context.tr('join_enter_email_subtitle'),
            initialEmail: _verifiedEmail ?? _emailController.text,
            enabledEmailEdit: true,
            onVerified: (email) async {
              if (!mounted) return;
              setState(() {
                _verifiedEmail = email;
                _emailController.text = email;
              });
              _nextStep();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelectionStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            context.tr('join_welcome_title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),

          // 이용약관 및 개인정보 처리방침 보기
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              // 🎯 이용약관 웹뷰로 이동 (AppConstants에서 URL 주입)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => WebViewScreen(
                        url: AppConstants.termsOfServiceUrl,
                        title: context.tr('terms_of_service'),
                      ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('join_terms_and_privacy'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 32),

          // 로그인 옵션
          _buildAuthOption(
            title: context.tr('login'),
            subtitle: context.tr('join_login_subtitle'),
            onTap: () {
              setState(() {
                _selectedMode = AuthMode.login;
                _currentStep = 1;
              });
            },
          ),

          SizedBox(height: 10),

          // 회원가입 옵션
          _buildAuthOption(
            title: context.tr('signup'),
            subtitle: context.tr('join_signup_subtitle'),
            onTap: () {
              setState(() {
                _selectedMode = AuthMode.signup;
                _currentStep = 1;
              });
            },
          ),

          Spacer(),
        ],
      ),
    );
  }

  Widget _buildAuthOption({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginStep() {
    return Column(
      children: [
        // 스크롤 가능한 컨텐츠 영역
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              SizedBox(height: 36),
              Text(
                context.tr('login'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                context.tr('join_login_description'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 32),

              // ID 입력
              TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                controller: _idController,
                focusNode: _loginIdFocusNode,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: context.tr('join_id_hint'),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                  prefixIconColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
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
                              });
                            },
                          )
                          : null,
                ),
                onSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_loginPasswordFocusNode);
                },
                onChanged: (value) {
                  setState(() {});
                },
              ),

              SizedBox(height: 16),

              // 비밀번호 입력
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                cursorColor: Theme.of(context).colorScheme.onSurface,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                focusNode: _loginPasswordFocusNode,
                decoration: InputDecoration(
                  hintText: context.tr('password_hint'),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                  prefixIconColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_idController.text.isNotEmpty &&
                      _passwordController.text.isNotEmpty &&
                      !_isCheckingDuplicate) {
                    _handleLogin();
                  }
                },
                onChanged: (value) {
                  setState(() {});
                },
              ),

              // 비밀번호 변경, 아이디 찾기, 비밀번호 찾기 링크
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        // TODO: 아이디 찾기 화면으로 이동
                      },
                      child: Text(
                        context.tr('find_id'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '|',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        // TODO: 비밀번호 찾기 화면으로 이동
                      },
                      child: Text(
                        context.tr('find_password'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '|',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        // TODO: 비밀번호 변경 화면으로 이동
                      },
                      child: Text(
                        context.tr('change_password'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 하단 고정 버튼 영역 (Scaffold의 resizeToAvoidBottomInset에 맡기고 SafeArea만 적용)
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    (_idController.text.isNotEmpty &&
                            _passwordController.text.isNotEmpty &&
                            !_isCheckingDuplicate)
                        ? _handleLogin
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (_idController.text.isNotEmpty &&
                              _passwordController.text.isNotEmpty)
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.grey[300],
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
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        )
                        : Text(
                          context.tr('login'),
                          style: TextStyle(
                            color:
                                (_idController.text.isNotEmpty &&
                                        _passwordController.text.isNotEmpty)
                                    ? Theme.of(context).colorScheme.surface
                                    : Colors.grey[600],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
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
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                controller: _idController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: context.tr('join_id_hint'),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                  prefixIconColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
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
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  errorStyle: TextStyle(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        if (_idController.text.isNotEmpty)
          Container(
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
                    backgroundColor:
                        _isCheckingDuplicate
                            ? Colors.grey[300]
                            : Theme.of(context).colorScheme.onSurface,
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
                                Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          )
                          : Text(
                            context.tr('next'),
                            style: TextStyle(
                              color:
                                  _isCheckingDuplicate
                                      ? Colors.grey[600]
                                      : Theme.of(context).colorScheme.surface,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),
            ),
          ),
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
                decoration: InputDecoration(
                  hintText: context.tr('password_hint'),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
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
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isPasswordValid ? _nextStep : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isPasswordValid
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  context.tr('next'),
                  style: TextStyle(
                    color:
                        _isPasswordValid
                            ? Theme.of(context).colorScheme.surface
                            : Colors.grey[600],
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
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
                decoration: InputDecoration(
                  hintText: context.tr('join_confirm_password_hint'),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        _isPasswordMatch &&
                                _confirmPasswordController.text.isNotEmpty
                            ? BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                            : BorderSide.none,
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
        Container(
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
                  backgroundColor:
                      _isPasswordMatch
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.grey[300],
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
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        )
                        : Text(
                          context.tr('join_complete_button'),
                          style: TextStyle(
                            color:
                                _isPasswordMatch
                                    ? Theme.of(context).colorScheme.surface
                                    : Colors.grey[600],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
          ),
        ),
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
          Icon(
            Icons.check_circle,
            size: 100,
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(height: 24),
          Text(
            context.tr('join_complete_title'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            context.tr('join_complete_subtitle'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
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
        // 🎯 비밀번호 재확인 페이지(step 3)에 들어갈 때마다 현재 입력값 확인
        if (_selectedMode == AuthMode.signup && _currentStep == 4) {
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
        // 첫 번째 단계(모드 선택)로 돌아가면 선택 초기화
        if (_currentStep == 0) {
          _selectedMode = null;
          _idController.clear();
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _isIdDuplicateChecked = false;
          _isIdAvailable = false;
          _isPasswordValid = false;
          _isPasswordMatch = false;
          _isIdLengthChecked = false;
          _verifiedEmail = null;
        }
        // 🎯 비밀번호 재확인 페이지(step 3)로 돌아올 때도 현재 입력값 확인
        else if (_selectedMode == AuthMode.signup && _currentStep == 4) {
          _isPasswordMatch =
              _confirmPasswordController.text.isNotEmpty &&
              _confirmPasswordController.text == _passwordController.text;
        }
      });
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isCheckingDuplicate = true;
    });

    final id = _idController.text.trim();
    final pw = _passwordController.text;
    final region = context.read<LocaleProvider>().regionCode; // 'KR' or 'US'

    final success = await AuthProvider().login(id, pw, region: region);

    if (!mounted) return;

    if (success) {
      // 🎯 로그인 후 스플래시로 부드럽게 페이드 전환
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
    } else {
      ErrorHandler.showError(
        context,
        context.tr('login_failed_invalid_credentials'),
      );
      setState(() {
        _isCheckingDuplicate = false;
      });
    }

    setState(() {
      _isCheckingDuplicate = false;
    });
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
