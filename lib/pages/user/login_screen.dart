import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onNext});

  final void Function(String userId, String password)? onNext;

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

  // 전체 화면을 위로 올릴 픽셀 오프셋 (음수면 위로 이동)
  static const double _yShift = -140.0;

  // 색상 (Figma 스니펫)
  static const Color _fillGray = Color(0x7FD9D9D9);
  static const Color _hintGray = Color(0xB2515151);
  static const Color _subTextGray = Color(0xFF515151);
  static const Color _primary = Color(0xB25C6AC4);

  // 입력 UI 치수
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
    final can =
        _idController.text.trim().isNotEmpty && _pwController.text.isNotEmpty;
    if (can != _canSubmit) setState(() => _canSubmit = can);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = _idController.text.trim();
    final pw = _pwController.text;
    if (widget.onNext != null) {
      widget.onNext!(id, pw);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('로그인 시도: $id / $pw')));
    }
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
    const double maxBodyWidth = 402; // Figma 기준 폭 상한
    const double horizontalPadding = 24;
    final Size screen = MediaQuery.of(context).size;
    final double screenHeight = screen.height;
    final double contentMaxWidth =
        math.min(maxBodyWidth, screen.width) - horizontalPadding * 2;

    // 텍스트
    const String titleText = '아이디, 비밀번호를 입력해주세요.';
    const String subText = '이후에도 언제든지 변경할 수 있어요.';

    // 실제 텍스트 높이 측정 (제목=contentMaxWidth, 부제=최대 244px)
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

    // 라벨(제목/부제) → 입력창 간격 = 화면 높이 * 0.1
    final double labelToInputsGap = screenHeight * 0.07;

    // 두 입력창 블록의 중앙이 화면 중앙이 되도록 상단 여백 계산
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
                        // 동적 상단 여백 (중앙 정렬 기준)
                        SizedBox(height: topSpacer),

                        // 제목
                        Text(titleText, style: AppTextStyles.headlineLarge),
                        const SizedBox(height: 8),

                        // 부제 (폭 244 제한)
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

                        // 라벨 → 입력창 간격
                        SizedBox(height: labelToInputsGap),

                        // 입력 블록
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
                            child: Text(
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
