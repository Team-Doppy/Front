import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:doppy/theme/app_text_styles.dart';

/// Welcome 화면
/// 밝은 회색 배경에 회전된 어두운 회색 사각형 위에 파란색 카드가 있는 디자인
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      color: const Color(0xFFF5F5F5), // 밝은 회색 배경
      child: SafeArea(
        child: Stack(
          children: [
            // 뒤로가기 버튼
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // 중앙 콘텐츠
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  // WELCOME! 텍스트
                  Text(
                    'WELCOME!',
                    style: AppTextStyles.headlineLarge.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // affection_jh 텍스트
                  Text(
                    'affection_jh',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 80),
                  // 회전된 어두운 회색 사각형과 파란색 카드
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // 회전된 어두운 회색 사각형 (배경)
                      AnimatedBuilder(
                        animation: _rotationController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle:
                                _rotationController.value * 2 * math.pi * 0.1,
                            child: Container(
                              width: size.width * 0.7,
                              height: size.width * 0.7,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          );
                        },
                      ),
                      // 파란색 카드 (앞)
                      Container(
                        width: size.width * 0.65,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B7FFF), // 밝은 파란색
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '정겹게 별명하나!',
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '다른사람들이 이 별명으로도\n찾을 수 있어요!',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.white.withOpacity(0.9),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
