import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';
import 'package:provider/provider.dart';
import '../../providers//auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  final _idFocus = FocusNode();
  final _pwFocus = FocusNode();

  bool _obscure = true;
  bool _canSubmit = false;

  // ✅ API 통신 중 로딩 상태를 표시하기 위한 변수 추가
  bool _isLoading = false;

  static const double _yShift = -140.0;

  static const Color _fillGray = Color(0x7FD9D9D9);
  static const Color _hintGray = Color(0xB2515151);
  static const Color _subTextGray = Color(0xFF515151);
  static const Color _primary = Color(0xB25C6AC4);

  static const double _fieldHeight = 44;
  static const double _fieldsGap = 16;
  static const double _buttonHeight = 50;

  @override
  void initState() {
    super.initState();
    _idController.addListener(_updateSubmitState);
    _pwController.addListener(_updateSubmitState);
  }

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    _idFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  void _updateSubmitState() {
    // ✅ 로딩 중일 때는 버튼 비활성화
    if (_isLoading) {
      if (_canSubmit) setState(() => _canSubmit = false);
      return;
    }
    final can =
        _idController.text.trim().isNotEmpty && _pwController.text.isNotEmpty;
    if (can != _canSubmit) setState(() => _canSubmit = can);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    final id = _idController.text.trim();
    final pw = _pwController.text;

    // Provider를 통해 AuthProvider의 login 메소드 호출
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(id, pw);

    // ✅ mounted 체크: 비동기 작업 후 위젯이 여전히 화면에 있는지 확인 (중요)
    if (!mounted) return;

    if (success) {
      // 로그인 성공 시 AuthProvider가 상태를 변경하여
      // main.dart의 Consumer가 자동으로 HomeScreen으로 전환해줍니다.
      // 따라서 여기서 직접 화면을 전환하는 코드는 필요 없습니다.
      // Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } else {
      // 로그인 실패 시 사용자에게 피드백 제공
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('아이디 또는 비밀번호가 일치하지 않습니다.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  InputDecoration _decoration({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.withColor(AppTextStyles.bodyMedium, _hintGray),
      filled: true,
      fillColor: _fillGray,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(5),
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double maxBodyWidth = 402;
    const double horizontalPadding = 24;
    final Size screen = MediaQuery.of(context).size;
    final double screenHeight = screen.height;
    final double contentMaxWidth =
        math.min(maxBodyWidth, screen.width) - horizontalPadding * 2;

    const String titleText = '아이디, 비밀번호를 입력해주세요.';
    const String subText = '이후에도 언제든지 변경할 수 있어요.';

    final titlePainter = TextPainter(
      text: TextSpan(text: titleText, style: AppTextStyles.headlineLarge),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: contentMaxWidth);

    final subPainter = TextPainter(
      text: TextSpan(
        text: subText,
        style: AppTextStyles.withColor(AppTextStyles.bodyLarge, _subTextGray),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: math.min(244, contentMaxWidth));

    final double titleHeight = titlePainter.size.height;
    final double subHeight = subPainter.size.height;

    final double labelToInputsGap = screenHeight * 0.07;

    final double inputsBlockHeight = _fieldHeight + _fieldsGap + _fieldHeight;
    final double inputsBlockCenterOffset = _fieldHeight + (_fieldsGap / 2);

    final double computedTopSpacer =
        (screenHeight / 2) -
        (titleHeight +
            8 +
            subHeight +
            labelToInputsGap +
            inputsBlockCenterOffset);

    final double topSpacer = computedTopSpacer.clamp(0.0, screenHeight);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxBodyWidth),
              child: Transform.translate(
                offset: const Offset(0, _yShift),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: topSpacer),

                        Text(titleText, style: AppTextStyles.headlineLarge),
                        const SizedBox(height: 8),

                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 244),
                          child: Text(
                            subText,
                            style: AppTextStyles.withColor(
                              AppTextStyles.bodyLarge,
                              _subTextGray,
                            ),
                          ),
                        ),

                        SizedBox(height: labelToInputsGap),

                        SizedBox(
                          height: inputsBlockHeight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 아이디
                              SizedBox(
                                height: _fieldHeight,
                                child: TextFormField(
                                  controller: _idController,
                                  focusNode: _idFocus,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted:
                                      (_) => FocusScope.of(
                                        context,
                                      ).requestFocus(_pwFocus),
                                  style: AppTextStyles.bodyLarge,
                                  decoration: _decoration(hint: 'User ID'),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return '아이디를 입력하세요.';
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              SizedBox(height: _fieldsGap),

                              // 비밀번호
                              SizedBox(
                                height: _fieldHeight,
                                child: TextFormField(
                                  controller: _pwController,
                                  focusNode: _pwFocus,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  obscureText: _obscure,
                                  style: AppTextStyles.bodyLarge,
                                  decoration: _decoration(
                                    hint: 'Password',
                                    suffix: IconButton(
                                      tooltip: _obscure ? '표시' : '숨기기',
                                      onPressed:
                                          () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return '비밀번호를 입력하세요.';
                                    }
                                    if (v.length < 6) {
                                      return '비밀번호는 6자 이상이어야 합니다.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 48),

                        // 다음 버튼
                        SizedBox(
                          width: double.infinity,
                          height: _buttonHeight,
                          child: ElevatedButton(
                            // ✅ 로딩 중이 아닐 때만 버튼 활성화
                            onPressed: _canSubmit ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              disabledBackgroundColor: _primary.withOpacity(
                                0.4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              elevation: 0,
                            ),
                            // ✅ 로딩 상태에 따라 버튼 내부 위젯 변경
                            child: _isLoading
                                ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3.0,
                            )
                                : Text(
                              '다음',
                              style: AppTextStyles.withColor(
                                AppTextStyles.bodyLarge,
                                Colors.white,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
