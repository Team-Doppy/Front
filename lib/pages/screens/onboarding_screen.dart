import 'package:doppy/pages/screens/join_screen.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.background
              : Colors.white,
      body: Stack(
        children: [
          // 메인 콘텐츠
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 로고/타이틀 영역
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 50),
                      Spacer(),

                      SizedBox(
                        height: 300,

                        child: OnboardingPlaceholder(reverse: true),
                      ),

                      Spacer(flex: 2),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 34),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "d",
                              style: GoogleFonts.jost(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -3,
                                fontSize: 68,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _SlowCircularProgressIndicator(
                                color: Theme.of(context).colorScheme.onSurface,
                                strokeWidth: 8.4,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.2),
                              ),
                            ),

                            Text(
                              "ppy",
                              style: GoogleFonts.jost(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -3,
                                fontSize: 68,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          "너희만 봐.",
                          style: GoogleFonts.comfortaa(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                            fontSize: 20,
                          ),
                        ),
                      ),

                      Spacer(),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            backgroundColor:
                                Theme.of(context).colorScheme.onSurface,
                            foregroundColor:
                                Theme.of(context).colorScheme.surface,
                            minimumSize: Size(double.infinity, 60),
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
                                        MediaQuery.of(context).size.height *
                                        0.92,
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
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                        Expanded(child: JoinScreen()),
                                      ],
                                    ),
                                  ),
                            );
                          },
                          child: Text(
                            '시작하기',
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.surface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

class OnboardingPlaceholder extends StatefulWidget {
  final bool reverse; // true면 오른쪽→왼쪽, false면 왼쪽→오른쪽

  const OnboardingPlaceholder({super.key, this.reverse = false});

  @override
  State<OnboardingPlaceholder> createState() => _OnboardingPlaceholderState();
}

class _OnboardingPlaceholderState extends State<OnboardingPlaceholder> {
  late final PageController _pageController;
  Timer? _autoScrollTimer;

  // 카드 데이터
  final List<_OnboardingCardData> _cards = const [
    _OnboardingCardData(
      title: '나와 맞는 글만 골라보기',
      subtitle: '친구 · 그룹 · 팔로우 기반 피드',
      imageUrl:
          'https://images.pexels.com/photos/261949/pexels-photo-261949.jpeg?auto=compress&cs=tinysrgb&w=800',
    ),
    _OnboardingCardData(
      title: '조용히, 깊이 있게',
      subtitle: '집중을 돕는 미니멀한 리더',
      imageUrl:
          'https://images.pexels.com/photos/7134982/pexels-photo-7134982.jpeg?auto=compress&cs=tinysrgb&w=800',
    ),
    _OnboardingCardData(
      title: '링크와 함께 기록하기',
      subtitle: '나만의 컬렉션을 만들어 보세요',
      imageUrl:
          'https://images.pexels.com/photos/1181671/pexels-photo-1181671.jpeg?auto=compress&cs=tinysrgb&w=800',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 가운데 근처 페이지에서 시작해서 양방향 무한 루프 느낌
    _pageController = PageController(viewportFraction: 0.8, initialPage: 1000);

    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!_pageController.hasClients) return;

      final currentPage = _pageController.page ?? _pageController.initialPage;
      final nextPage = widget.reverse ? currentPage - 1 : currentPage + 1;

      try {
        await _pageController.animateToPage(
          nextPage.round(),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOutCubic,
        );
      } catch (_) {
        // 컨트롤러 dispose 시 예외 무시
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 로그인 화면 안에서 쓰이는 가로 슬라이드 카드 플레이스홀더
    return ClipRRect(
      //borderRadius: BorderRadius.circular(18),
      child: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // 손 스와이프 비활성화
        itemBuilder: (context, index) {
          final card = _cards[index % _cards.length];
          return _buildCard(
            context,
            title: card.title,
            subtitle: card.subtitle,
            imageUrl: card.imageUrl,
          );
        },
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String imageUrl,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.grey.shade900,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 임시 이미지 (네트워크)
          Image.network(imageUrl, fit: BoxFit.cover),
          // 위에 어두운 그라디언트 깔기
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
          // 텍스트
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingCardData {
  final String title;
  final String subtitle;
  final String imageUrl;

  const _OnboardingCardData({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });
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
