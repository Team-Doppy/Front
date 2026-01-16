import 'package:flutter/material.dart';
import 'package:doppy/theme/app_text_styles.dart';

/// Welcome 화면
/// 밝은 회색 배경에 텍스트만 표시 (카드는 OnboardingFlow에서 처리)
class WelcomeScreen extends StatelessWidget {
  final VoidCallback? onBack;
  const WelcomeScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 뒤로가기 버튼
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
                onPressed: () {
                  final cb = onBack;
                  if (cb != null) return cb();
                },
              ),
            ),
            const SizedBox(height: 72),
            // WELCOME! 텍스트 (카드 밖)
            Text(
              'WELCOME!',
              style: AppTextStyles.headlineLarge.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'affection_jh',
              style: AppTextStyles.bodyMedium.copyWith(
                color: const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
