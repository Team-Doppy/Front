import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 별명 설정 단계
class NicknameSettingStep extends StatefulWidget {
  final TextEditingController nicknameController;
  final UserType? userType; // 역할에 따라 멘트 변경
  final VoidCallback? onNicknameSubmitted; // ✅ 별명 제출 콜백 (로컬 상태 업데이트만)
  final VoidCallback? onConfirm; // ✅ 별명 제출 후 다음 단계로 이동
  final VoidCallback? onBack; // ✅ 뒤로가기 버튼 콜백

  const NicknameSettingStep({
    super.key,
    required this.nicknameController,
    this.userType,
    this.onNicknameSubmitted,
    this.onConfirm,
    this.onBack,
  });

  @override
  State<NicknameSettingStep> createState() => _NicknameSettingStepState();
}

class _NicknameSettingStepState extends State<NicknameSettingStep> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    // 화면이 나타나면 200ms 지연 후 자동으로 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    // 화면이 사라질 때 키보드 확실하게 내리기
    _focusNode.unfocus();
    _focusNode.dispose();
    super.dispose();
  }

  String _getSubtitleMessage() {
    switch (widget.userType) {
      case UserType.military:
        return '기록과 리포트에 사용돼요';
      case UserType.plannedEnlistment:
        return '기록과 리포트에 사용돼요';
      case UserType.girlfriend:
        return '남자친구에게 보이는 이름이에요';
      default:
        return '도피에서 활동할 이름';
    }
  }

  void _handleSubmit() {
    final nickname = widget.nicknameController.text.trim();
    if (nickname.isEmpty) return;

    // 제출 시 키보드 내리기
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();

    // API 호출 없이 로컬 상태만 업데이트
    widget.onNicknameSubmitted?.call();

    // 키보드가 내려간 후 0.2초 지연 후 다음 단계로
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        widget.onConfirm?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: RepaintBoundary(
          child: Stack(
            children: [
              // 뒤로가기 버튼
              if (widget.onBack != null)
                Positioned(
                  top: 8,
                  left: 12,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    onPressed: () {
                      // 뒤로가기 시 키보드 먼저 내리기
                      _focusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      // 키보드가 내려가는 애니메이션을 위해 잠시 대기
                      Future.delayed(const Duration(milliseconds: 200), () {
                        if (mounted) {
                          widget.onBack?.call();
                        }
                      });
                    },
                  ),
                ),
              // 중앙 컨텐츠
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 56),
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 안내 텍스트 (통일된 메인 타이틀)
                        Text(
                          '여기서 불릴 이름을 정해볼까요?',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 20,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 별명 입력 필드
                        TextField(
                          controller: widget.nicknameController,
                          focusNode: _focusNode,
                          enabled: true,
                          cursorColor: Theme.of(context).colorScheme.onSurface,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: _getSubtitleMessage(),
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceVariant, // 어두운 회색
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
                            _handleSubmit();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
