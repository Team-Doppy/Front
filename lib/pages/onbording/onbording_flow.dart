import 'package:flutter/material.dart';
import 'package:doppy/pages/onbording/screens/welcome_screen.dart';
import 'package:doppy/pages/onbording/screens/nickname_screen.dart';
import 'package:doppy/pages/onbording/screens/profile_setup_screen.dart';
import 'package:doppy/pages/onbording/widgets/onboarding_progress_indicator.dart';
import 'dart:math' as math;

/// 온보딩 플로우 메인 위젯
/// 스와이프로 화면 전환이 가능하며, 검정색 배경이 자연스럽게 확장되는 효과를 제공합니다.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late PageController _pageController;
  double _pageOffset = 0.0;
  final int _totalPages = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    if (_pageController.hasClients) {
      setState(() {
        _pageOffset = _pageController.page ?? 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 첫 번째 페이지에서 두 번째 페이지로 넘어갈 때 검정색이 확장되는 효과
    final darkOverlayProgress = (_pageOffset.clamp(0.0, 1.0));

    return Scaffold(
      body: Stack(
        children: [
          // PageView로 스와이프 가능한 화면들
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            children: const [
              WelcomeScreen(),
              NicknameScreen(),
              ProfileSetupScreen(),
            ],
          ),
          // 검정색 오버레이 (스와이프 시 확장) - 하단에서 원형으로 확장
          if (darkOverlayProgress > 0)
            Positioned.fill(
              child: ClipPath(
                clipper: _CircularRevealClipper(
                  progress: darkOverlayProgress,
                  center: Alignment.bottomCenter,
                ),
                child: Container(color: const Color(0xFF0F0F0F)),
              ),
            ),
          // 진행 표시기 (첫 번째 화면에만 표시)
          if (_pageOffset < 0.5)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: (1.0 - darkOverlayProgress * 2).clamp(0.0, 1.0),
                child: OnboardingProgressIndicator(
                  currentPage: 0,
                  totalPages: _totalPages,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 원형 확장 클리퍼
class _CircularRevealClipper extends CustomClipper<Path> {
  final double progress;
  final Alignment center;

  _CircularRevealClipper({required this.progress, required this.center});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (progress <= 0) {
      // 아직 확장되지 않음
      return path;
    }

    final centerPoint = center.alongSize(size);
    final maxRadius = math.sqrt(
      math.pow(size.width, 2) + math.pow(size.height, 2),
    );
    final currentRadius = maxRadius * progress;

    path.addOval(Rect.fromCircle(center: centerPoint, radius: currentRadius));
    return path;
  }

  @override
  bool shouldReclip(_CircularRevealClipper oldClipper) {
    return oldClipper.progress != progress || oldClipper.center != center;
  }
}
