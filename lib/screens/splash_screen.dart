import 'package:dio/dio.dart';
import 'package:doppy/main.dart' show MainTabShell;
import 'package:doppy/onbording/onbording_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/graph_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/widgets/doppy_loading_logo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// DoppyLoadingLogo 기반 스플래시 스크린
///
/// 초기 데이터 로드:
/// 1. 유저 정보 => UserProvider (GET /api/auth/me)
/// 2. 그래프 => GraphProvider (GET /api/graph?mode=real)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  Future<void> _loadInitialData() async {
    if (!mounted || _loadStarted) return;
    _loadStarted = true;

    final authProvider = AuthProvider();
    final userProvider = context.read<UserProvider>();
    final graphProvider = context.read<GraphProvider>();

    try {
      // 1. 토큰 유효성 검사 및 갱신
      final tokenValid = await authProvider.validateAndRefreshToken();
      if (!tokenValid || !mounted) {
        _goToLogin();
        return;
      }

      // 2. 내 정보 로드 (GET /api/auth/me) – 401이면 catch로 가서 온보딩으로
      await userProvider.fetchUserBundle();

      // 3. 그래프 로드 (GET /api/graph?mode=real) – 실패해도 메인 진입, 타임아웃이면 온보딩
      await graphProvider.loadGraph(mode: 'mock', count: 13);
      if (!mounted) return;

      if (_isTimeoutErrorString(graphProvider.error)) {
        debugPrint('[SplashScreen] 그래프 로드 타임아웃 → 온보딩');
        _goToOnboarding();
        return;
      }

      _goToMain();
    } catch (e) {
      debugPrint('[SplashScreen] 초기 로드 실패: $e');
      if (_isTimeoutException(e)) {
        _goToOnboarding();
      } else {
        _goToLogin();
      }
    }
  }

  void _goToMain() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainTabShell(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// 401 등 실패 시 토큰 정리 후 온보딩(로그인)으로만 이동. 기존 스택 전부 제거.
  void _goToLogin() {
    AuthProvider().logout();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// 타임아웃 시 온보딩으로 이동 (로그아웃 없이)
  void _goToOnboarding() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  static bool _isTimeoutException(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout;
    }
    return e.toString().toLowerCase().contains('timeout');
  }

  static bool _isTimeoutErrorString(String? s) {
    if (s == null || s.isEmpty) return false;
    return s.toLowerCase().contains('timeout');
  }

  @override
  Widget build(BuildContext context) {
    return const DoppyLoadingLogo();
  }
}
