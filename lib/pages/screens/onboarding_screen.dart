import 'package:doppy/pages/screens/join_screen.dart';
import 'package:doppy/pages/screens/setting_screen.dart';
import 'package:doppy/main.dart' show AppConstants;
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _typingController;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400), // 느린 회전
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _typingController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(
            child: Image.asset(
              'assets/images/onboarding0.png',
              fit: BoxFit.cover,
            ),
          ),
          // 배경 이미지
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.background.withOpacity(0.3),
            ),
          ),
          // 메인 콘텐츠
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 180),
                const Spacer(),

                // Doppy 로딩 로고 스타일 제목
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: _typingController,
                    builder: (context, child) {
                      return _buildTitleText(
                        context,
                        "Doppy",
                        ValueKey("Doppy"),
                      );
                    },
                  ),
                ),
                // 서브 텍스트
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    context.tr('onboarding_subtitle'),
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: const Color.fromARGB(255, 190, 190, 190),
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const Spacer(),
                // 하단 시작하기 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: Size(double.infinity, 56),
                        elevation: 0,
                      ),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          builder:
                              (context) => Container(
                                height:
                                    MediaQuery.of(context).size.height * 0.92,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // 핸들
                                    Container(
                                      margin: EdgeInsets.only(top: 8),
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[400],
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Expanded(child: JoinScreen()),
                                  ],
                                ),
                              ),
                        );
                      },
                      child: Text(
                        context.tr('onboarding_start_button'),
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 하단 푸터 정보
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "© 2025 Doppy",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Doppy 로딩 로고 스타일 제목 (o에 스핀)
  Widget _buildTitleText(BuildContext context, String text, Key key) {
    return Container(
      key: key,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "D"
          Text(
            "D",
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          // "o" - 회전하는 스피너 (Painter 사용)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _DoppyOSpinnerPainter(
                  progress: _typingController.value,
                  color: Theme.of(context).colorScheme.primary,
                  strokeWidth: 9,
                ),
              ),
            ),
          ),
          // "ppy"
          Text(
            "ppy",
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedORing extends StatefulWidget {
  final double size;
  const AnimatedORing({this.size = 80, super.key});

  @override
  _AnimatedORingState createState() => _AnimatedORingState();
}

class _AnimatedORingState extends State<AnimatedORing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: ORingPainter(_controller.value),
          size: Size(widget.size, widget.size),
        );
      },
    );
  }
}

class ORingPainter extends CustomPainter {
  final double t; // 0~1
  ORingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    // 기본 링 (연한 베이스)
    final basePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = Colors.grey.withOpacity(0.25);
    canvas.drawCircle(center, radius - 5, basePaint);

    // 메인 컬러의 hue를 시간에 따라 회전시키기
    final baseHue = (t * 360) % 360;
    Color _h(double h, double s, double v) =>
        HSVColor.fromAHSV(1, (h % 360), s, v).toColor();

    // sweep을 살짝 숨쉬듯 변화 (0.6π ~ 1.0π)
    final sweep = math.pi * (0.6 + 0.4 * math.sin(2 * math.pi * t)); // rad

    // 기본 시작각 (시간에 따라 한 바퀴 회전)
    final startAngle = 2 * math.pi * t;

    final rect = Rect.fromCircle(center: center, radius: radius - 5);

    // 여러 개의 라이트 스트로크를 겹쳐서 역동감 Up
    for (int i = 0; i < 3; i++) {
      final localT = (t + i * 0.25) % 1.0;
      final hue = baseHue + i * 40;

      final paint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                6 -
                i
                    .toDouble() // 바깥에서 안쪽으로 살짝 가늘어지게
            ..strokeCap = StrokeCap.round
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              4,
            ) // 약간의 블러로 글로우 느낌
            ..shader = SweepGradient(
              startAngle: 0,
              endAngle: 2 * math.pi,
              colors: [
                _h(hue, 0.9, 1.0),
                _h(hue + 40, 0.9, 1.0),
                _h(hue + 80, 0.9, 1.0),
              ],
            ).createShader(rect);

      final localStart =
          startAngle + localT * 0.8; // 약간씩 위상 차이를 줘서 서로 다른 속도로 도는 느낌

      canvas.drawArc(
        rect,
        localStart,
        sweep * (0.9 - i * 0.2), // 안쪽으로 갈수록 조금 짧게
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 🐌 느린 속도의 CircularProgressIndicator
class _SlowCircularProgressIndicator extends StatefulWidget {
  final Color color;
  final double strokeWidth;
  final Color? backgroundColor;

  const _SlowCircularProgressIndicator({
    required this.color,
    required this.strokeWidth,
    this.backgroundColor,
  });

  @override
  State<_SlowCircularProgressIndicator> createState() =>
      _SlowCircularProgressIndicatorState();
}

class _SlowCircularProgressIndicatorState
    extends State<_SlowCircularProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 🎯 기본 CircularProgressIndicator보다 2배 느리게 (기본 1.2초 → 2.4초)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(48, 48), // 기본 CircularProgressIndicator 크기
          painter: _SlowCircularProgressPainter(
            progress: _controller.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
            backgroundColor: widget.backgroundColor,
          ),
        );
      },
    );
  }
}

class _SlowCircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final Color? backgroundColor;

  _SlowCircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 🎯 반지름을 더 작게 (기본의 0.75배)
    final radius = ((size.width - strokeWidth) / 2) * 0.8;

    // 배경 원
    if (backgroundColor != null) {
      final backgroundPaint =
          Paint()
            ..color = backgroundColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, backgroundPaint);
    }

    // 진행 원호
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    // 0.75 바퀴 (270도) 길이의 원호
    const sweepAngle = 3 * math.pi / 2; // 270도
    final startAngle = -math.pi / 2 + (progress * 2 * math.pi);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SlowCircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// Doppy "o" 스피너 Painter (감각적인 스타일)
class _DoppyOSpinnerPainter extends CustomPainter {
  final double progress; // 0~1
  final Color color;
  final double strokeWidth;

  _DoppyOSpinnerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 기본 원형 스피너
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;

    // 270도 (3/4 원) 길이의 원호
    const sweepAngle = 3 * math.pi / 2; // 270도
    final startAngle = -math.pi / 2 + (progress * 2 * math.pi);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );

    // 글로우 효과를 위한 추가 레이어
    final glowPaint =
        Paint()
          ..color = color.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 1.5
          ..strokeCap = StrokeCap.butt
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(_DoppyOSpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
