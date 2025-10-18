import 'package:doppy/main.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/models/post_data.dart';
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

  final BlogService _blogService = BlogService();

  // ignore: unused_field
  List<PostData> _preloadedPosts = [];
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
        // 내 프로필 선로딩 - 실패 시 전체 진행 중단
        try {
          // ignore: use_build_context_synchronously
          await context.read<UserProvider>().fetchMyProfile();
        } catch (e) {
          setState(() {
            _isTokenValidated = false; // 게이트 다운
            _isDataLoaded = true;
            _loadingStatus = '프로필 로딩 실패';
          });
        }
        if (_isTokenValidated) {
          await _loadHomeData();
        }
      } else {
        // 토큰이 없거나 유효하지 않은 경우 빈 데이터로 설정
        setState(() {
          _preloadedPosts = [];
          _isDataLoaded = true;
        });
      }

      // 3. 네비게이션
      await _navigateAfterReady();
    } catch (e) {
      setState(() {
        _isTokenValidated = false;
        _isDataLoaded = true;
        _preloadedPosts = [];
        _loadingStatus = '오류가 발생했습니다';
      });
      await _navigateAfterReady();
    }
  }

  Future<void> _loadHomeData() async {
    try {
      // 기본 필터가 "친구만 보기"이므로 getFriendsPosts 사용
      final serverData = await _blogService.getFriendsPosts(page: 0, size: 10);
      final posts =
          serverData.map((data) => PostData.fromServer(data)).toList();

      setState(() {
        _preloadedPosts = posts;
        _loadingStatus = posts.isEmpty ? '데이터 로드 완료' : '이미지를 미리 로드하는 중...';
      });
      print('[SplashScreen] Successfully loaded ${posts.length} posts');

      // 이미지 미리 로드 (최대 3개)
      if (posts.isNotEmpty) {
        await _preloadImages(posts.take(3).toList());
      }

      setState(() {
        _isDataLoaded = true;
      });
    } catch (e) {
      print('[SplashScreen] Error loading home data: $e');
      // 서버 오류 시 빈 리스트로 초기화
      setState(() {
        _preloadedPosts = [];
        _isDataLoaded = true;
      });
    }
  }

  Future<void> _preloadImages(List<PostData> posts) async {
    final List<Future<void>> preloadFutures = [];

    for (final post in posts) {
      if (post.thumbnailImageUrl.isNotEmpty) {
        print('[SplashScreen] Preloading image: ${post.thumbnailImageUrl}');
        preloadFutures.add(
          precacheImage(
            NetworkImage(post.thumbnailImageUrl),
            context,
          ).catchError((error) {
            print('[SplashScreen] Failed to preload image: $error');
          }),
        );
      }
    }

    if (preloadFutures.isNotEmpty) {
      try {
        await Future.wait(preloadFutures);
        print(
          '[SplashScreen] Successfully preloaded ${preloadFutures.length} images',
        );
      } catch (e) {
        print('[SplashScreen] Error preloading images: $e');
      }
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
              (_, __, ___) =>
                  RootShell(initialIndex: 0, preloadedPosts: _preloadedPosts),
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
