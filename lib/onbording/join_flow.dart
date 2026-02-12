import 'dart:async';

import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/onbording/onbording_screen.dart';
import 'package:doppy/onbording/reset_flow.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/screens/splash_screen.dart';
import 'package:flutter/material.dart';

// ─── 문자열 (한글) ─────────────────────────────────────────────
class _K {
  static const email = '이메일 인증';
  static const id = '사용자 ID';
  static const password = '비밀번호';
  static const confirmPw = '비밀번호 확인';
  static const complete = '가입 완료';
  static const startDoppy = '시작하기';
  static const emailSubtitle = '이메일을 입력하고 인증 코드를 받아주세요.';
  static const emailCodeSubtitle = '이메일에 전송된 6자리 코드를 입력해주세요.';
  static const idTitle = '사용할 ID를 입력해주세요';
  static const idSubtitle = '4자 이상, 영문/숫자 조합으로 만들어주세요.';
  static const idHint = 'ID 입력';
  static const idTooShort = 'ID는 4자 이상이어야 합니다.';
  static const idAlreadyUsed = '이미 사용 중인 ID입니다.';
  static const pwTitle = '비밀번호를 설정해주세요';
  static const pwSubtitle = '8자 이상, 영문과 숫자를 포함해주세요.';
  static const pwHint = '비밀번호';
  static const pwConfirmTitle = '비밀번호를 다시 입력해주세요';
  static const pwConfirmSubtitle = '위에서 입력한 비밀번호와 동일하게 입력해주세요.';
  static const pwConfirmHint = '비밀번호 재입력';
  static const pwMinLen = '8자 이상';
  static const pwLetter = '영문 포함';
  static const pwNumber = '숫자 포함';
  static const next = '다음';
  static const prev = '이전';
  static const completeBtn = '가입 완료';
  static const sendCode = '인증 코드 발송';
  static const verify = '인증하기';
  static const emailHint = '이메일 주소';
  static const codeHint = '6자리 코드';
  static const invalidEmail = '올바른 이메일을 입력해주세요.';
  static const sendFirst = '먼저 인증 코드를 발송해주세요.';
  static const enter6 = '6자리 코드를 입력해주세요.';
  static const tooManyAttempts = '시도 횟수를 초과했습니다. 코드를 다시 발송해주세요.';
  static const codeMismatch = '코드가 일치하지 않습니다. ({count}회 남음)';
  static const logout = '로그아웃';
  static const logoutConfirm = '로그아웃 하시겠습니까?';
  static const cancel = '취소';
  static const signupFailed = '회원가입에 실패했습니다. 다시 시도해주세요.';
  static const signupError = '오류: {error}';
  static const idCheckError = 'ID 확인 중 오류: {error}';
  static const loginTitle = '로그인';
  static const loginSubtitle = '아이디나 비밀번호를 잊었나요?';
  static const loginBtn = '로그인';
  static const noAccount = '계정이 없나요?';
  static const loginFailed = 'ID와 비밀번호를 다시 확인해주세요.';
}

// ─── JoinFlow (회원가입) ───────────────────────────────────────
class JoinFlow extends StatefulWidget {
  final bool skipModeSelection;
  final bool emailVerificationOnly;
  final VoidCallback? onEmailVerified;

  const JoinFlow({
    super.key,
    this.skipModeSelection = false,
    this.emailVerificationOnly = false,
    this.onEmailVerified,
  });

  @override
  State<JoinFlow> createState() => _JoinFlowState();
}

class _JoinFlowState extends State<JoinFlow> {
  int _step = 0;

  /// 기본: 일반 로그인 화면. false면 회원가입 단계(이메일→ID→비밀번호→확인) 표시.
  bool _isLoginMode = true;
  final _auth = AuthService();
  final _idCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  bool _idChecked = false, _idAvailable = false;
  bool _pwValid = false, _pwMatch = false;
  bool _idLenChecked = false;
  String? _verifiedEmail;
  bool _loading = false;
  String? _loginErr;
  String? _idCheckErr;
  String? _signupErr;
  bool _obscurePw = true, _obscurePwConfirm = true;

  List<String> get _steps =>
      widget.emailVerificationOnly
          ? [_K.email]
          : [_K.email, _K.id, _K.password, _K.confirmPw, _K.complete];

  @override
  void dispose() {
    _idCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  bool get _isComplete => _step == _steps.length - 1;

  void _nextStep() {
    if (_step < _steps.length - 1) {
      setState(() {
        _step++;
        if (_step == 3) {
          _pwMatch =
              _pwConfirmCtrl.text.isNotEmpty &&
              _pwConfirmCtrl.text == _pwCtrl.text;
        }
      });
    }
  }

  void _prevStep() async {
    if (widget.emailVerificationOnly) {
      final ok = await showDialog<bool>(
        context: context,
        builder:
            (c) => AlertDialog(
              title: const Text(_K.logout),
              content: const Text(_K.logoutConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text(_K.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text(_K.logout),
                ),
              ],
            ),
      );
      if (ok == true && mounted) {
        await AuthProvider().logout();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (r) => false,
          );
        }
      }
      return;
    }
    if (_step > 0) {
      setState(() {
        _step--;
        if (_step == 3) {
          _pwMatch =
              _pwConfirmCtrl.text.isNotEmpty &&
              _pwConfirmCtrl.text == _pwCtrl.text;
        }
      });
    } else {
      // 회원가입 첫 단계에서 이전 → 로그인 화면으로
      setState(() => _isLoginMode = true);
    }
  }

  Future<void> _goToSplash() async {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SplashScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder:
            (_, a, __, child) => FadeTransition(
              opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut),
              child: child,
            ),
      ),
      (r) => false,
    );
  }

  InputDecoration _inputDeco(BuildContext c, {String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
    filled: true,
    fillColor:
        Theme.of(c).brightness == Brightness.dark
            ? Theme.of(c).colorScheme.background
            : Theme.of(c).colorScheme.surfaceVariant,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    ),
  );

  TextStyle _inputStyle(BuildContext c) => TextStyle(
    color: Theme.of(c).colorScheme.onSurface,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  Widget _primaryBtn(
    BuildContext c, {
    required String label,
    VoidCallback? onPressed,
    bool loading = false,
  }) => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(c).colorScheme.onSurface,
        foregroundColor: Theme.of(c).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child:
          loading
              ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    Theme.of(c).colorScheme.onSurface,
                  ),
                ),
              )
              : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
    ),
  );

  Future<void> _doLogin() async {
    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (id.isEmpty || pw.isEmpty) return;
    setState(() {
      _loading = true;
      _loginErr = null;
    });
    try {
      final ok = await AuthProvider().login(id, pw, region: 'KR');
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) _goToSplash();
      } else {
        setState(
          () => _loginErr = AuthProvider().lastLoginError ?? _K.loginFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loginErr = _K.loginFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading:
            _isLoginMode
                ? GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24, top: 22),
                    child: Text(
                      _K.prev,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                : (_isComplete
                    ? null
                    : GestureDetector(
                      onTap: _prevStep,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24, top: 22),
                        child: Text(
                          _K.prev,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )),
        actions:
            _isLoginMode && !widget.emailVerificationOnly
                ? [
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() => _isLoginMode = false),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24, top: 12),
                        child: Text(
                          _K.noAccount,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]
                : null,
        bottom:
            _isLoginMode || _isComplete
                ? null
                : PreferredSize(
                  preferredSize: const Size.fromHeight(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / _steps.length,
                        minHeight: 4,
                        backgroundColor: theme.colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.onSurface.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ),
                ),
      ),
      body:
          _isLoginMode && !widget.emailVerificationOnly
              ? _LoginStep(
                idCtrl: _idCtrl,
                pwCtrl: _pwCtrl,
                loading: _loading,
                obscurePw: _obscurePw,
                loginErr: _loginErr,
                onToggleObscure: () => setState(() => _obscurePw = !_obscurePw),
                onFieldsChanged: () => setState(() => _loginErr = null),
                inputDeco: _inputDeco,
                inputStyle: _inputStyle,
                primaryBtn: _primaryBtn,
                onLogin: _doLogin,
                onNoAccount: () => setState(() => _isLoginMode = false),
              )
              : IndexedStack(
                index: _step,
                children: [
                  JoinEmailStep(
                    title: _K.startDoppy,
                    subtitle: _K.emailSubtitle,
                    codeSubtitle: _K.emailCodeSubtitle,
                    initialEmail: _verifiedEmail ?? _emailCtrl.text,
                    enabledEdit: true,
                    mode: widget.emailVerificationOnly ? 'UPDATE' : 'REGISTER',
                    inputDeco: _inputDeco,
                    inputStyle: _inputStyle,
                    primaryBtn: _primaryBtn,
                    onVerified: (
                      email, {
                      String? code,
                      String? username,
                    }) async {
                      if (!mounted) return;
                      setState(() {
                        _verifiedEmail = email;
                        _emailCtrl.text = email;
                      });
                      if (widget.emailVerificationOnly) {
                        try {
                          final res = await _auth.updateEmail(email: email);
                          if (res != null)
                            await AuthProvider().validateAndRefreshToken();
                        } catch (e) {
                          debugPrint('[JoinFlow] updateEmail: $e');
                        }
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _goToSplash();
                        });
                        return;
                      }
                      _nextStep();
                    },
                  ),
                  if (!widget.emailVerificationOnly) ...[
                    _IdStep(
                      ctrl: _idCtrl,
                      idChecked: _idChecked,
                      idAvailable: _idAvailable,
                      idLenChecked: _idLenChecked,
                      idCheckErr: _idCheckErr,
                      loading: _loading,
                      inputDeco: _inputDeco,
                      inputStyle: _inputStyle,
                      primaryBtn: _primaryBtn,
                      onCheck: _checkId,
                      onNext: _nextStep,
                      onIdChanged:
                          () => setState(() {
                            _idChecked = false;
                            _idLenChecked = false;
                            _idCheckErr = null;
                          }),
                      onClear:
                          () => setState(() {
                            _idCtrl.clear();
                            _idChecked = false;
                            _idLenChecked = false;
                            _idCheckErr = null;
                          }),
                    ),
                    JoinPasswordStep(
                      ctrl: _pwCtrl,
                      valid: _pwValid,
                      inputDeco: _inputDeco,
                      inputStyle: _inputStyle,
                      primaryBtn: _primaryBtn,
                      obscure: _obscurePw,
                      onToggleObscure:
                          () => setState(() => _obscurePw = !_obscurePw),
                      onValidate:
                          (v) => setState(() => _pwValid = _validatePw(v)),
                      onNext: _nextStep,
                    ),
                    JoinConfirmPwStep(
                      pwCtrl: _pwCtrl,
                      confirmCtrl: _pwConfirmCtrl,
                      match: _pwMatch,
                      loading: _loading,
                      signupErr: _signupErr,
                      inputDeco: _inputDeco,
                      inputStyle: _inputStyle,
                      primaryBtn: _primaryBtn,
                      obscure: _obscurePwConfirm,
                      onToggleObscure:
                          () => setState(
                            () => _obscurePwConfirm = !_obscurePwConfirm,
                          ),
                      onMatch:
                          (v) => setState(() {
                            _pwMatch = v == _pwCtrl.text;
                            _signupErr = null;
                          }),
                      onComplete: _completeSignup,
                    ),
                    const Center(
                      child: Text(
                        _K.complete,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
    );
  }

  bool _validatePw(String s) =>
      s.length >= 8 &&
      RegExp(r'[a-zA-Z]').hasMatch(s) &&
      RegExp(r'[0-9]').hasMatch(s);

  Future<void> _checkId() async {
    setState(() {
      _idLenChecked = true;
      _loading = true;
      _idCheckErr = null;
    });
    try {
      final ok = await _auth.checkUsernameDuplicate(_idCtrl.text);
      if (!mounted) return;
      setState(() {
        _idChecked = true;
        _idAvailable = ok;
        _loading = false;
      });
      if (ok) _nextStep();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _idCheckErr = _K.idCheckError.replaceAll('{error}', '$e');
        });
      }
    }
  }

  Future<void> _completeSignup() async {
    setState(() {
      _loading = true;
      _signupErr = null;
    });
    try {
      final ok = await _auth.register(
        username: _idCtrl.text,
        password: _pwCtrl.text,
        email: _verifiedEmail ?? _emailCtrl.text,
        alias: _idCtrl.text,
        region: 'KR',
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) _goToSplash();
      } else {
        setState(() => _signupErr = _K.signupFailed);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _signupErr = _K.signupError.replaceAll('{error}', '$e');
        });
      }
    }
  }
}

// ─── 이메일 인증 단계 (Join/Reset 공용) ─────────────────────────
/// [mode] 'REGISTER' | 'UPDATE' | 'PASSWORD_RESET'
/// PASSWORD_RESET 시 sendCode는 findUsername+sendPasswordResetCode, verify 시 onVerified(email, code:, username:) 호출
class JoinEmailStep extends StatefulWidget {
  final String title, subtitle, codeSubtitle;
  final String? initialEmail;
  final bool enabledEdit;
  final String mode;
  final InputDecoration Function(BuildContext, {String? hint}) inputDeco;
  final TextStyle Function(BuildContext) inputStyle;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final Future<void> Function(String email, {String? code, String? username})
  onVerified;

  const JoinEmailStep({
    super.key,
    required this.title,
    required this.subtitle,
    required this.codeSubtitle,
    this.initialEmail,
    this.enabledEdit = true,
    this.mode = 'REGISTER',
    required this.inputDeco,
    required this.inputStyle,
    required this.primaryBtn,
    required this.onVerified,
  });

  @override
  State<JoinEmailStep> createState() => _JoinEmailStepState();
}

class _JoinEmailStepState extends State<JoinEmailStep> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _auth = AuthService();
  bool _sending = false, _verifying = false;
  bool _codeSent = false;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  DateTime? _cooldownUntil;
  String? _emailErr, _pinErr;
  int _failedAttempts = 0;
  static const _maxAttempts = 5;
  String? _foundUsername;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String s) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());

  void _startCooldown(Duration d) {
    _timer?.cancel();
    _cooldownUntil = DateTime.now().add(d);
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_cooldownUntil == null) return;
    final r = _cooldownUntil!.difference(DateTime.now());
    final next = r.isNegative ? Duration.zero : r;
    if (_remaining != next) setState(() => _remaining = next);
    if (r.isNegative) _cooldownUntil = null;
  }

  String _mmss(Duration d) {
    final s = d.inSeconds.clamp(0, 9999);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    setState(() => _emailErr = _pinErr = null);
    if (!_validEmail(email)) {
      setState(() => _emailErr = _K.invalidEmail);
      return;
    }
    if (_remaining > Duration.zero) return;
    setState(() => _sending = true);
    try {
      if (widget.mode == 'PASSWORD_RESET') {
        final findRes = await _auth.findUsernameByEmail(email);
        if (!mounted) return;
        if (!findRes.success) {
          setState(() {
            _emailErr = findRes.message ?? '해당 이메일로 가입된 계정이 없습니다.';
            _sending = false;
          });
          return;
        }
        _foundUsername = findRes.username;
        final res = await _auth.sendPasswordResetCode(
          email,
          username: _foundUsername,
        );
        if (!mounted) return;
        if (res.success) {
          setState(() {
            _codeSent = true;
            _failedAttempts = 0;
            _codeCtrl.clear();
            _sending = false;
          });
          final dur =
              res.expiresIn != null
                  ? Duration(seconds: res.expiresIn!)
                  : const Duration(minutes: 5);
          _startCooldown(dur);
        } else {
          final raw = res.message ?? '발송 실패';
          final msg =
              raw.contains('이메일 인증') && raw.contains('완료')
                  ? '이메일 인증을 마친 계정만 재설정할 수 있습니다.'
                  : raw;
          setState(() {
            _emailErr = msg;
            _sending = false;
          });
        }
      } else {
        final res = await _auth.sendEmailVerificationCode(
          email: email,
          region: 'KR',
          mode: widget.mode,
        );
        if (!mounted) return;
        if (res.success) {
          setState(() {
            _codeSent = true;
            _failedAttempts = 0;
            _codeCtrl.clear();
            _sending = false;
          });
          final dur =
              res.expiresIn != null
                  ? Duration(seconds: res.expiresIn!)
                  : const Duration(minutes: 5);
          _startCooldown(dur);
        } else {
          setState(() {
            _emailErr = res.message ?? '발송 실패';
            _sending = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _emailErr = e.toString();
          _sending = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailCtrl.text.trim();
    setState(() => _emailErr = _pinErr = null);
    if (!_codeSent) {
      setState(() => _pinErr = _K.sendFirst);
      return;
    }
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _pinErr = _K.enter6);
      return;
    }
    if (_failedAttempts >= _maxAttempts) {
      setState(() => _pinErr = _K.tooManyAttempts);
      return;
    }
    setState(() => _verifying = true);
    try {
      if (widget.mode == 'PASSWORD_RESET') {
        await widget.onVerified(email, code: code, username: _foundUsername);
      } else {
        final res = await _auth.verifyEmailCode(
          email: email,
          code: code,
          mode: widget.mode,
        );
        if (!mounted) return;
        if (res.success && (res.verified ?? true)) {
          await widget.onVerified(email);
        } else {
          final errCode = res.error?.error ?? '';
          if (errCode == 'INVALID_VERIFICATION_CODE') {
            setState(() {
              _failedAttempts++;
              final r = (_maxAttempts - _failedAttempts).clamp(0, _maxAttempts);
              _pinErr =
                  r > 0
                      ? _K.codeMismatch.replaceAll('{count}', '$r')
                      : _K.tooManyAttempts;
            });
          } else {
            setState(() => _pinErr = res.message ?? '인증 실패');
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _pinErr = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deco = widget.inputDeco(context);
    final w = widget;
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
                  w.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent ? w.codeSubtitle : w.subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  enabled: w.enabledEdit && !_sending && !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  cursorColor: theme.colorScheme.onSurface,
                  style: w.inputStyle(context),
                  decoration: deco.copyWith(
                    hintText: _K.emailHint,
                    errorText: _emailErr,

                    prefixIcon: Icon(
                      Icons.alternate_email_rounded,
                      size: 20,
                      color:
                          _emailErr != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant.withOpacity(
                                0.5,
                              ),
                    ),
                  ),
                  onChanged: (_) => setState(() => _emailErr = null),
                  onSubmitted: (_) {
                    if (!_sending && _remaining == Duration.zero && !_codeSent)
                      _sendCode();
                  },
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeCtrl,
                    enabled: !_sending && !_verifying,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    cursorColor: theme.colorScheme.onSurface,
                    style: w.inputStyle(context),
                    decoration: deco.copyWith(
                      hintText: _K.codeHint,
                      errorText: _pinErr,
                      counterText: '',
                      suffixIcon:
                          _remaining > Duration.zero
                              ? Padding(
                                padding: const EdgeInsets.only(right: 16),
                                child: Text(
                                  _mmss(_remaining),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withOpacity(0.6),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                              : null,
                    ),
                    onChanged: (_) => setState(() => _pinErr = null),
                    onSubmitted: (_) {
                      if (!_verifying && _codeCtrl.text.length == 6)
                        _verifyCode();
                    },
                  ),
                ],
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SafeArea(
            top: false,
            child:
                _codeSent
                    ? (_codeCtrl.text.length == 6 && _pinErr == null) ||
                            _verifying
                        ? widget.primaryBtn(
                          context,
                          label: _K.verify,
                          onPressed: _verifyCode,
                          loading: _verifying,
                        )
                        : const SizedBox.shrink()
                    : (_validEmail(_emailCtrl.text.trim()) &&
                            _emailErr == null) ||
                        _sending
                    ? widget.primaryBtn(
                      context,
                      label: _K.sendCode,
                      onPressed: _sendCode,
                      loading: _sending,
                    )
                    : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// ─── ID 단계 ─────────────────────────────────────────────────
class _IdStep extends StatelessWidget {
  final TextEditingController ctrl;
  final bool idChecked, idAvailable, idLenChecked, loading;
  final String? idCheckErr;
  final InputDecoration Function(BuildContext, {String? hint}) inputDeco;
  final TextStyle Function(BuildContext) inputStyle;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final VoidCallback onCheck;
  final VoidCallback onNext;
  final VoidCallback onIdChanged;
  final VoidCallback onClear;

  const _IdStep({
    required this.ctrl,
    required this.idChecked,
    required this.idAvailable,
    required this.idLenChecked,
    required this.idCheckErr,
    required this.loading,
    required this.inputDeco,
    required this.inputStyle,
    required this.primaryBtn,
    required this.onCheck,
    required this.onNext,
    required this.onIdChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canNext = ctrl.text.length >= 4;
    String? err;
    if (idCheckErr != null)
      err = idCheckErr;
    else if (idLenChecked && ctrl.text.length < 4)
      err = _K.idTooShort;
    else if (idChecked && !idAvailable)
      err = _K.idAlreadyUsed;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              const SizedBox(height: 36),
              Text(
                _K.idTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _K.idSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                cursorColor: theme.colorScheme.onSurface,
                style: inputStyle(context),
                decoration: inputDeco(context, hint: _K.idHint).copyWith(
                  errorText: err,
                  prefixIcon: const Icon(
                    Icons.alternate_email_rounded,
                    size: 18,
                  ),
                  suffixIcon:
                      ctrl.text.isNotEmpty
                          ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withOpacity(0.6),
                            ),
                            onPressed: onClear,
                          )
                          : null,
                ),
                onChanged: (_) => onIdChanged(),
                onSubmitted: (_) {
                  if (canNext) {
                    if (!idChecked)
                      onCheck();
                    else if (idAvailable)
                      onNext();
                  }
                },
              ),
            ],
          ),
        ),
        if (canNext || loading)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: SafeArea(
              top: false,
              child: primaryBtn(
                context,
                label: _K.next,
                onPressed:
                    loading
                        ? null
                        : () {
                          if (!idChecked)
                            onCheck();
                          else if (idAvailable)
                            onNext();
                        },
                loading: loading,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── 비밀번호 단계 (Join/Reset 공용) ──────────────────────────
class JoinPasswordStep extends StatelessWidget {
  final TextEditingController ctrl;
  final bool valid;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final void Function(String) onValidate;
  final InputDecoration Function(BuildContext, {String? hint}) inputDeco;
  final TextStyle Function(BuildContext) inputStyle;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final VoidCallback onNext;

  const JoinPasswordStep({
    required this.ctrl,
    required this.valid,
    required this.obscure,
    required this.onToggleObscure,
    required this.onValidate,
    required this.inputDeco,
    required this.inputStyle,
    required this.primaryBtn,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              const SizedBox(height: 36),
              Text(
                _K.pwTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _K.pwSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                cursorColor: theme.colorScheme.onSurface,
                style: inputStyle(context),
                decoration: inputDeco(context, hint: _K.pwHint).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      size: 18,
                    ),
                    onPressed: onToggleObscure,
                  ),
                ),
                onChanged: onValidate,
                onSubmitted: (_) => valid ? onNext() : null,
              ),
              if (ctrl.text.isNotEmpty) ...[
                const SizedBox(height: 16),
                _reqRow(context, _K.pwMinLen, ctrl.text.length >= 8),
                _reqRow(
                  context,
                  _K.pwLetter,
                  RegExp(r'[a-zA-Z]').hasMatch(ctrl.text),
                ),
                _reqRow(
                  context,
                  _K.pwNumber,
                  RegExp(r'[0-9]').hasMatch(ctrl.text),
                ),
              ],
            ],
          ),
        ),
        if (valid)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: SafeArea(
              top: false,
              child: primaryBtn(context, label: _K.next, onPressed: onNext),
            ),
          ),
      ],
    );
  }

  Widget _reqRow(BuildContext c, String txt, bool ok) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check : Icons.close,
          size: 16,
          color:
              ok
                  ? Theme.of(c).colorScheme.onSurface
                  : Theme.of(c).colorScheme.onSurfaceVariant.withOpacity(0.4),
        ),
        const SizedBox(width: 8),
        Text(
          txt,
          style: TextStyle(
            color:
                ok
                    ? Theme.of(c).colorScheme.onSurface.withOpacity(0.9)
                    : Theme.of(c).colorScheme.onSurfaceVariant.withOpacity(0.4),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ─── 비밀번호 확인 단계 (Join/Reset 공용) ──────────────────────
class JoinConfirmPwStep extends StatelessWidget {
  final TextEditingController pwCtrl, confirmCtrl;
  final bool match, loading;
  final String? signupErr;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final void Function(String) onMatch;
  final InputDecoration Function(BuildContext, {String? hint}) inputDeco;
  final TextStyle Function(BuildContext) inputStyle;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final VoidCallback onComplete;

  const JoinConfirmPwStep({
    required this.pwCtrl,
    required this.confirmCtrl,
    required this.match,
    required this.loading,
    this.signupErr,
    required this.obscure,
    required this.onToggleObscure,
    required this.onMatch,
    required this.inputDeco,
    required this.inputStyle,
    required this.primaryBtn,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              const SizedBox(height: 36),
              Text(
                _K.pwConfirmTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _K.pwConfirmSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure,
                cursorColor: Theme.of(context).colorScheme.onSurface,
                style: inputStyle(context),
                decoration: inputDeco(context, hint: _K.pwConfirmHint).copyWith(
                  errorText: signupErr,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                      size: 18,
                    ),
                    onPressed: onToggleObscure,
                  ),
                ),
                onChanged: onMatch,
                onSubmitted: (_) => match && !loading ? onComplete() : null,
              ),
            ],
          ),
        ),
        if (match || loading)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: SafeArea(
              top: false,
              child: primaryBtn(
                context,
                label: _K.completeBtn,
                onPressed: match ? onComplete : null,
                loading: loading,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── 로그인 단계 (기본 진입) ───────────────────────────────────
class _LoginStep extends StatelessWidget {
  final TextEditingController idCtrl;
  final TextEditingController pwCtrl;
  final bool loading;
  final bool obscurePw;
  final String? loginErr;
  final VoidCallback onToggleObscure;
  final VoidCallback onFieldsChanged;
  final InputDecoration Function(BuildContext, {String? hint}) inputDeco;
  final TextStyle Function(BuildContext) inputStyle;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final VoidCallback onLogin;
  final VoidCallback onNoAccount;

  const _LoginStep({
    required this.idCtrl,
    required this.pwCtrl,
    required this.loading,
    required this.obscurePw,
    this.loginErr,
    required this.onToggleObscure,
    required this.onFieldsChanged,
    required this.inputDeco,
    required this.inputStyle,
    required this.primaryBtn,
    required this.onLogin,
    required this.onNoAccount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canLogin = idCtrl.text.trim().isNotEmpty && pwCtrl.text.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              const SizedBox(height: 36),
              Text(
                _K.loginTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ResetFlow()),
                  );
                },
                child: Text(
                  _K.loginSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.9),

                    decorationColor: theme.colorScheme.onSurfaceVariant
                        .withOpacity(0.9),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: idCtrl,
                cursorColor: theme.colorScheme.onSurface,
                style: inputStyle(context),
                decoration: inputDeco(context, hint: _K.idHint).copyWith(
                  prefixIcon: Icon(
                    Icons.alternate_email_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                onChanged: (_) => onFieldsChanged(),
                onSubmitted: (_) {
                  if (canLogin && !loading) onLogin();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwCtrl,
                obscureText: obscurePw,
                cursorColor: theme.colorScheme.onSurface,
                style: inputStyle(context),
                decoration: inputDeco(context, hint: _K.pwHint).copyWith(
                  errorText: loginErr,
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color:
                        loginErr != null
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant.withOpacity(
                              0.5,
                            ),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePw ? Icons.visibility_off : Icons.visibility,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      size: 18,
                    ),
                    onPressed: onToggleObscure,
                  ),
                ),
                onChanged: (_) => onFieldsChanged(),
                onSubmitted: (_) {
                  if (canLogin && !loading) onLogin();
                },
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                if (canLogin || loading)
                  primaryBtn(
                    context,
                    label: _K.loginBtn,
                    onPressed: canLogin ? onLogin : null,
                    loading: loading,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
