import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/onbording/join_flow.dart';
import 'package:flutter/material.dart';

// ─── 문자열 (한글) ─────────────────────────────────────────────
class _RK {
  static const emailTitle = '이메일 인증';
  static const emailSubtitle = '이메일을 입력하고 인증 코드를 받아주세요.';
  static const emailCodeSubtitle = '이메일에 전송된 6자리 코드를 입력해주세요.';
  static const foundIdTitle = '등록된 ID입니다';
  static const foundIdSubtitle = '아래 ID로 로그인해주세요.';
  static const changePwBtn = '비번 변경';
  static const completeBtn = '완료';
  static const resetCompleteTitle = '비밀번호가 변경되었습니다';
  static const resetCompleteSubtitle = '새 비밀번호로 로그인해주세요.';
  static const resetFailed = '비밀번호 재설정에 실패했습니다.';
  static const resetError = '오류: {error}';
}

// ─── ResetFlow: 이메일 인증(Join UI) → ID 확인 + 비번 변경 버튼 → Join 비밀번호 단계 재활용
class ResetFlow extends StatefulWidget {
  const ResetFlow({super.key});

  @override
  State<ResetFlow> createState() => _ResetFlowState();
}

class _ResetFlowState extends State<ResetFlow> {
  int _step = 0; // 0: 이메일 인증, 1: ID 확인+비번변경 버튼, 2: 비밀번호, 3: 비밀번호 확인, 4: 완료
  final _auth = AuthService();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  String? _resetEmail;
  String? _resetCode;
  String? _foundUsername;
  bool _loading = false;
  String? _resetErr;
  bool _obscurePw = true;
  bool _obscurePwConfirm = true;
  bool _pwValid = false;
  bool _pwMatch = false;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  bool _validatePw(String s) =>
      s.length >= 8 &&
      RegExp(r'[a-zA-Z]').hasMatch(s) &&
      RegExp(r'[0-9]').hasMatch(s);

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
  }) =>
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(c).colorScheme.onSurface,
            foregroundColor: Theme.of(c).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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

  Future<void> _doResetPassword() async {
    final email = _resetEmail ?? '';
    final code = _resetCode ?? '';
    final username = _foundUsername ?? '';
    final pw = _pwCtrl.text;
    if (username.isEmpty || email.isEmpty || code.isEmpty) return;
    if (!_validatePw(pw) || pw != _pwConfirmCtrl.text) return;

    setState(() {
      _loading = true;
      _resetErr = null;
    });
    try {
      final res = await _auth.resetPassword(
        username: username,
        email: email,
        code: code,
        newPassword: pw,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (res.success) {
        setState(() => _step = 4);
      } else {
        setState(() => _resetErr = res.message ?? _RK.resetFailed);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _resetErr = _RK.resetError.replaceAll('{error}', '$e');
        });
      }
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
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
        leading: GestureDetector(
          onTap: _goBack,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, top: 22),
            child: Text(
              '이전',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_step) {
      case 0:
        return JoinEmailStep(
          title: _RK.emailTitle,
          subtitle: _RK.emailSubtitle,
          codeSubtitle: _RK.emailCodeSubtitle,
          enabledEdit: true,
          mode: 'PASSWORD_RESET',
          inputDeco: _inputDeco,
          inputStyle: _inputStyle,
          primaryBtn: _primaryBtn,
          onVerified: (email, {String? code, String? username}) async {
            if (!mounted) return;
            setState(() {
              _resetEmail = email;
              _resetCode = code;
              _foundUsername = username;
              _step = 1;
            });
          },
        );
      case 1:
        return _IdConfirmStep(
          theme: theme,
          username: _foundUsername ?? '-',
          primaryBtn: _primaryBtn,
          onChangePw: () => setState(() => _step = 2),
        );
      case 2:
        return JoinPasswordStep(
          ctrl: _pwCtrl,
          valid: _pwValid,
          inputDeco: _inputDeco,
          inputStyle: _inputStyle,
          primaryBtn: _primaryBtn,
          obscure: _obscurePw,
          onToggleObscure: () => setState(() => _obscurePw = !_obscurePw),
          onValidate: (v) => setState(() => _pwValid = _validatePw(v)),
          onNext: () => setState(() {
            _pwMatch = _pwConfirmCtrl.text.isNotEmpty && _pwConfirmCtrl.text == _pwCtrl.text;
            _step = 3;
          }),
        );
      case 3:
        return JoinConfirmPwStep(
          pwCtrl: _pwCtrl,
          confirmCtrl: _pwConfirmCtrl,
          match: _pwMatch,
          loading: _loading,
          signupErr: _resetErr,
          obscure: _obscurePwConfirm,
          onToggleObscure: () => setState(() => _obscurePwConfirm = !_obscurePwConfirm),
          onMatch: (v) => setState(() {
            _pwMatch = v == _pwCtrl.text;
            _resetErr = null;
          }),
          inputDeco: _inputDeco,
          inputStyle: _inputStyle,
          primaryBtn: _primaryBtn,
          onComplete: _doResetPassword,
        );
      case 4:
        return _ResultStep(
          title: _RK.resetCompleteTitle,
          subtitle: _RK.resetCompleteSubtitle,
          primaryBtn: _primaryBtn,
          btnLabel: _RK.completeBtn,
          onComplete: () => Navigator.pop(context),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── ID 확인 + 비번 변경 버튼 단계 ─────────────────────────────
class _IdConfirmStep extends StatelessWidget {
  final ThemeData theme;
  final String username;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final VoidCallback onChangePw;

  const _IdConfirmStep({
    required this.theme,
    required this.username,
    required this.primaryBtn,
    required this.onChangePw,
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
                _RK.foundIdTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _RK.foundIdSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  username,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SafeArea(
            top: false,
            child: primaryBtn(
              context,
              label: _RK.changePwBtn,
              onPressed: onChangePw,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 결과(완료) 단계 ───────────────────────────────────────────
class _ResultStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget Function(
    BuildContext, {
    required String label,
    VoidCallback? onPressed,
    bool loading,
  })
  primaryBtn;
  final String btnLabel;
  final VoidCallback onComplete;

  const _ResultStep({
    required this.title,
    required this.subtitle,
    required this.primaryBtn,
    required this.btnLabel,
    required this.onComplete,
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
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SafeArea(
            top: false,
            child: primaryBtn(
              context,
              label: btnLabel,
              onPressed: onComplete,
            ),
          ),
        ),
      ],
    );
  }
}
