import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Index 1 background: 별명 입력 화면
class Index1Background extends StatefulWidget {
  final TextEditingController nicknameController;
  final Future<void> Function()? onNicknameSubmitted;
  final String submittedNickname; // ✅ 제출된 별명 (변화 감지용)
  final ValueChanged<bool>? onShouldHideIndicator; // ✅ 인디케이터 숨김 여부 콜백

  const Index1Background({
    super.key,
    required this.nicknameController,
    this.onNicknameSubmitted,
    this.submittedNickname = '',
    this.onShouldHideIndicator,
  });

  @override
  State<Index1Background> createState() => _Index1BackgroundState();
}

class _Index1BackgroundState extends State<Index1Background> {
  bool _isLoading = false;
  bool? _lastShouldHideIndicator;

  Future<void> _handleSubmit() async {
    final nickname = widget.nicknameController.text.trim();
    if (nickname.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onNicknameSubmitted?.call();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: RepaintBoundary(
          child: Stack(
            children: [
              // 중앙 컨텐츠
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 안내 텍스트
                        Text(
                          '내 별명',
                          style: TextStyle(
                            color: AppColors.darkSurfaceVariant,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 별명 입력 필드
                        TextField(
                          controller: widget.nicknameController,
                          enabled: !_isLoading,
                          cursorColor: AppColors.darkSurface,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.darkSurfaceVariant,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: '탭해서 별명 입력하기!',
                            hintStyle: TextStyle(
                              color: AppColors.darkSurfaceVariant.withOpacity(
                                0.5,
                              ),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor: AppColors.lightSurfaceVariant, // 어두운 회색
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 30,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (!_isLoading) {
                              _handleSubmit();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 완료 버튼 (키보드 위에 고정)
              Positioned(
                bottom: keyboardHeight + 16,
                left: 24,
                right: 24,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.nicknameController,
                  builder: (context, value, child) {
                    final currentText = value.text.trim();
                    final hasText = currentText.isNotEmpty;
                    // ✅ 텍스트가 있고, 이전 제출된 별명과 다를 때만 표시
                    final hasChanged =
                        hasText && currentText != widget.submittedNickname;

                    // ✅ 키보드/완료버튼 상태 변화 시에만 인디케이터 숨김 여부 전달 (콜백/포스트프레임 남발 방지)
                    final currentHasKeyboard =
                        MediaQuery.of(context).viewInsets.bottom > 0;
                    final shouldHide = currentHasKeyboard || hasChanged;
                    if (_lastShouldHideIndicator != shouldHide) {
                      _lastShouldHideIndicator = shouldHide;
                      widget.onShouldHideIndicator?.call(shouldHide);
                    }

                    return AnimatedOpacity(
                      opacity: hasChanged ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !hasChanged || _isLoading,
                        child: SizedBox(
                          child: ElevatedButton(
                            onPressed:
                                hasChanged && !_isLoading
                                    ? _handleSubmit
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.darkSurfaceVariant,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  AppColors.lightSurfaceVariant,

                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child:
                                _isLoading
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.darkSurfaceVariant,
                                            ),
                                      ),
                                    )
                                    : hasChanged
                                    ? const Text(
                                      '완료',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                    : const Text(''),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
