import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../user/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  Future<void> _completeOnboarding(BuildContext context) async {
    // 1. FlutterSecureStorage 인스턴스를 생성합니다.
    const storage = FlutterSecureStorage();

    // 2. 'hasSeenOnboarding' 키에 'true'라는 문자열 값을 저장합니다.
    await storage.write(key: 'hasSeenOnboarding', value: 'true');

    if (context.mounted) {
      // 3. LoginScreen으로 이동합니다. (뒤로가기 방지)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _typingController;
  late AnimationController _cursorController;
  late Animation<double> _typingAnimation;
  late Animation<double> _cursorAnimation;

  int _currentPage = 0;
  final int _numPages = 3;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: "Doppy",
      subtitle: "이웃들과 함께하는\n특별한 소셜 플랫폼",
      description: "가까운 이웃들과 연결하고\n일상을 공유해보세요",
      typingText: "보고싶은 사람에게만,\n꼭 보여주고싶은 이야기만.",
    ),
    OnboardingPage(
      title: "함께 성장",
      subtitle: "이웃과 함께하는\n즐거운 경험",
      description: "정보를 나누고 새로운\n경험을 만들어보세요",
      typingText: "복잡한 틀 없이,\n그냥 쓰고 싶은 대로.",
    ),
    OnboardingPage(
      title: "지금 시작",
      subtitle: "Doppy와 함께하는\n특별한 만남",
      description: "새로운 이웃들과의\n특별한 만남을 시작하세요",
      typingText: "지금 당장 Doppy하세요!",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _typingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _cursorController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _typingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _typingController, curve: Curves.easeInOut),
    );

    _cursorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cursorController, curve: Curves.easeInOut),
    );

    _startTypingAnimation();
    _cursorController.repeat(reverse: true);
  }

  void _startTypingAnimation() {
    _typingController.reset();
    _typingController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _typingController.dispose();
    _cursorController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    _startTypingAnimation();
  }

  void _goToNextPage() {
    if (_currentPage < _numPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: TextButton(
                  onPressed: _navigateToLogin,
                  child: Text(
                    '건너뛰기',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            // Main Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _numPages,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // Bottom Section
            Container(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                children: [
                  // Page Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _numPages,
                          (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: _currentPage == index ? 32 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                          _currentPage == index
                              ? AppColors.primary
                              : Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // 마지막 페이지에서만 시작하기 버튼 표시
                  if (_currentPage == _numPages - 1) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _navigateToLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          '시작하기',
                          style: AppTextStyles.headlineMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Main Typing Effect
          _buildMainTypingEffect(page.typingText),
        ],
      ),
    );
  }

  Widget _buildMainTypingEffect(String fullText) {
    return AnimatedBuilder(
      animation: _typingAnimation,
      builder: (context, child) {
        final int currentCharacters =
        (_typingAnimation.value * fullText.length).round();
        final String displayText = fullText.substring(
          0,
          currentCharacters.clamp(0, fullText.length),
        );

        return Text(
          displayText,
          style: TextStyle(
            fontSize: 24,
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
        );
      },
    );
  }
}

class OnboardingPage {
  final String title;
  final String subtitle;
  final String description;
  final String typingText;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.typingText,
  });
}
