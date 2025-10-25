import 'package:doppy/main.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _glow;
  late final Animation<double> _flash;

  final HomeDataService _homeDataService = HomeDataService();

  HomeData? _preloadedHomeData;
  bool _isDataLoaded = false;
  bool _isTokenValidated = false;
  String _loadingStatus = '앱을 시작하는 중...';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.9, curve: Curves.easeOutBack),
      ),
    );

    _glow = Tween<double>(begin: 0.0, end: 24.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.8, curve: Curves.easeOut),
      ),
    );

    _flash = Tween<double>(begin: 0.0, end: 0.8).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.55, 0.65, curve: Curves.easeOut),
      ),
    );

    startSequence();
  }

  void startSequence() {
    // 두둥 느낌: 타이밍에 맞춘 햅틱
    Future.delayed(const Duration(milliseconds: 550), () {
      HapticFeedback.heavyImpact();
    });
    initializeApp();
    Future.delayed(const Duration(milliseconds: 900), () {
      HapticFeedback.mediumImpact();
    });
  }

  Future<void> initializeApp() async {
    try {
      // 1. 토큰 검증 및 갱신
      setState(() {
        _loadingStatus = '인증을 확인하는 중...';
      });

      final authProvider = context.read<AuthProvider>();
      final hasToken = await authProvider.checkLoginStatus();

      if (hasToken) {
        final isValid = await authProvider.validateAndRefreshToken();
        setState(() {
          _isTokenValidated = isValid;
          _loadingStatus = isValid ? '데이터를 불러오는 중...' : '토큰이 만료되었습니다';
        });
      } else {
        setState(() {
          _isTokenValidated = false;
          _loadingStatus = '로그인이 필요합니다';
        });
      }

      // 2. 토큰이 유효한 경우에만 데이터 로딩
      if (_isTokenValidated) {
        setState(() {
          _loadingStatus = '데이터를 불러오는 중...';
        });
        // 인스타그램 방식: 일단 홈화면으로 진입, 네트워크 에러는 홈에서 처리
        setState(() {
          _preloadedHomeData = HomeData(friendsPosts: [], allPosts: []);
          _isDataLoaded = true;
          _loadingStatus = '홈화면 준비 완료';
        });
      } else {
        // 토큰이 없거나 유효하지 않은 경우 빈 데이터로 설정
        setState(() {
          _preloadedHomeData = HomeData(friendsPosts: [], allPosts: []);
          _isDataLoaded = true;
        });
      }

      // 3. 네비게이션
      await _navigateAfterReady();
    } catch (e) {
      final networkError = NetworkUtils.parseError(e);
      setState(() {
        _isTokenValidated = false;
        _isDataLoaded = true;
        _preloadedHomeData = HomeData(friendsPosts: [], allPosts: []);
        _loadingStatus = networkError.userMessage;
      });
      await _navigateAfterReady();
    }
  }

  Future<void> _loadHomeData() async {
    try {
      setState(() {
        _loadingStatus = '피드 데이터를 불러오는 중...';
      });

      // 통합 피드 데이터 서비스를 사용하여 두 섹션 동시 로드
      final homeData = await _homeDataService.preloadAllSections(
        page: 0,
        size: 10,
      );

      setState(() {
        _preloadedHomeData = homeData;
        _loadingStatus = homeData.isEmpty ? '데이터 로드 완료' : '이미지를 미리 로드하는 중...';
      });

      print(
        '[SplashScreen] 피드 데이터 로드 완료: 친구글 ${homeData.friendsPosts.length}개, 전체글 ${homeData.allPosts.length}개',
      );

      // 이미지 미리 로드 (두 섹션 모두)
      if (!homeData.isEmpty) {
        final allPosts = [...homeData.friendsPosts, ...homeData.allPosts];
        await _homeDataService.precacheImages(allPosts, context);
      }

      setState(() {
        _isDataLoaded = true;
        _loadingStatus = '로딩 완료';
      });
    } catch (e) {
      print('[SplashScreen] 피드 데이터 로드 실패: $e');
      final networkError = NetworkUtils.parseError(e);

      setState(() {
        _preloadedHomeData = HomeData(friendsPosts: [], allPosts: []);
        _isDataLoaded = true;
        _loadingStatus = networkError.userMessage;
      });
    }
  }

  Future<void> _navigateAfterReady() async {
    try {
      // 애니메이션 완료까지 대기
      await _controller.forward().orCancel;
    } catch (_) {}

    if (!mounted) return;

    // 데이터 로딩 완료까지 대기
    while (!_isDataLoaded) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }

    // 애니메이션 잔상 방지 약간의 텀 후 전환
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    // 토큰 검증 결과에 따라 네비게이션
    if (_isTokenValidated) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder:
              (_, __, ___) => RootShell(
                initialIndex: 0,
                preloadedHomeData: _preloadedHomeData,
              ),
          transitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder:
              (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
      );
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 약한 비네팅
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.0,
                colors: [Color(0xFF0A0A0A), Colors.black],
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow (alpha 직접 적용)
                    Container(
                      width: 180 * _scale.value,
                      height: 180 * _scale.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFB71C1C).withOpacity(
                              0.35 * (_opacity.value * 0.9).clamp(0.0, 1.0),
                            ),
                            blurRadius: _glow.value,
                            spreadRadius: _glow.value * 0.25,
                          ),
                        ],
                      ),
                    ),
                    // Logo
                    Opacity(
                      opacity: _opacity.value,
                      child: Transform.scale(
                        scale: _scale.value,
                        child: SizedBox(
                          width: 180,
                          height: 180,
                          child: Text(
                            'Doppy',
                            style: TextStyle(
                              fontSize: 50,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Flash overlay (alpha 직접 적용)
                    IgnorePointer(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.6 * _flash.value),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 로딩 상태 표시
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacity.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _loadingStatus,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
