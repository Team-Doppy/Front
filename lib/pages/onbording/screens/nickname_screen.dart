import 'package:flutter/material.dart';
import 'package:doppy/theme/app_text_styles.dart';

/// 별명 입력 화면
/// 검정색 배경에 텍스트 입력 필드가 있는 화면
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _nicknameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F0F), // 검정색 배경
      child: SafeArea(
        child: Column(
          children: [
            // 뒤로가기 버튼
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // 입력 필드 영역
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 힌트 텍스트
                    Text(
                      '다른사람들이 이 별명으로도',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 입력 필드
                    TextField(
                      controller: _nicknameController,
                      focusNode: _focusNode,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: '별명을 입력하세요',
                        hintStyle: AppTextStyles.headlineMedium.copyWith(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 24,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      autofocus: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
