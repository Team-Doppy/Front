import 'package:doppy/main.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/services/auth_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// 앱 부트스트랩 결과
class _BootstrapResult {
  final bool loggedIn;
  final HomeData? homeData;

  const _BootstrapResult({required this.loggedIn, this.homeData});

  factory _BootstrapResult.notLoggedIn() {
    return const _BootstrapResult(loggedIn: false, homeData: null);
  }

  factory _BootstrapResult.loggedIn(HomeData? homeData) {
    return _BootstrapResult(loggedIn: true, homeData: homeData);
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeInController;
  late final Animation<double> _fadeInOpacity;
  late final AnimationController _fadeOutController;
  late final Animation<double> _fadeOutOpacity;

  final HomeDataService _homeDataService = HomeDataService();

  late final Future<_BootstrapResult> _bootstrapFuture;

  @override
  void initState() {
    super.initState();

    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _fadeInOpacity = CurvedAnimation(
      parent: _fadeInController,
      curve: const Interval(0.0, 0.1, curve: Curves.easeOut),
    );

    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeOutOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeOutController, curve: Curves.easeOut),
    );

    // 🎯 먼저 로딩 로고 애니메이션 시작
    _fadeInController.forward();

    // 🎯 부트스트랩 Future 생성
    _bootstrapFuture = _bootstrap();

    // 🎯 애니메이션이 시작된 후 데이터 로드 및 네비게이션 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startSequence();
      _navigateAfterReady();
    });
  }

  void startSequence() {
    // 두둥 느낌: 타이밍에 맞춘 햅틱
    Future.delayed(const Duration(milliseconds: 550), () {
      HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      HapticFeedback.mediumImpact();
    });
  }

  /// 앱 부트스트랩: 인증 및 필수 데이터 로드
  Future<_BootstrapResult> _bootstrap() async {
    try {
      // 1. 토큰 검증 및 갱신
      final authProvider = context.read<AuthProvider>();
      final hasToken = await authProvider.checkLoginStatus();

      if (!hasToken) {
        return _BootstrapResult.notLoggedIn();
      }

      final isValid = await authProvider.validateAndRefreshToken();
      if (!isValid) {
        return _BootstrapResult.notLoggedIn();
      }

      if (!mounted) {
        return _BootstrapResult.notLoggedIn();
      }

      // 2. FCM 토큰 검사 및 필요시 재발급 (비동기로 처리하여 앱 시작을 막지 않음)
      _checkAndSyncFcmToken();

      // 3. 앱 시작 시 필수 데이터만 로드 (그룹 스키마 포함)
      // 홈 데이터, 검색 기록, 유저 정보, 그룹 스키마를 병렬로 로드
      final homeDataFuture = _loadHomeData();
      await Future.wait([
        homeDataFuture.then((_) => null),
        _loadSearchHistory(),
        _loadUserData(),
        _loadGroupSchema(),
      ]);

      // 홈 데이터 가져오기
      final homeData = await homeDataFuture;

      // 4. 트렌딩 데이터는 비동기로 백그라운드에서 로드 (앱 시작을 막지 않음)
      _loadTrendingData();

      // 5. 설정 정보 및 받은 요청은 비동기로 백그라운드에서 로드 (앱 시작을 막지 않음)
      _loadSettingsAndFriendRequests();

      return _BootstrapResult.loggedIn(homeData);
    } catch (e) {
      debugPrint('[SplashScreen] 부트스트랩 오류: $e');
      return _BootstrapResult.notLoggedIn();
    }
  }

  Future<HomeData> _loadHomeData() async {
    try {
      // 통합 피드 데이터 서비스를 사용하여 두 섹션 동시 로드
      final homeData = await _homeDataService.preloadAllSections(
        page: 0,
        size: 20, // 🎯 10 -> 20으로 증가 (앱 시작 시에도 20개 로드)
      );

      // 이미지 프리캐시는 Splash에서 하지 않음 (RootShell에서 처리)
      return homeData;
    } catch (e) {
      debugPrint('[SplashScreen] 피드 데이터 로드 실패: $e');
      return HomeData(friendsPosts: [], allPosts: []);
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      // SearchService를 통해 검색 기록 미리 로드
      final searchService = SearchService();
      await searchService.loadSearchHistory();
    } catch (e) {
      // 검색 기록 로드 실패는 앱 시작을 막지 않음
    }
  }

  Future<void> _loadUserData() async {
    try {
      final userProvider = context.read<UserProvider>();

      // 먼저 로컬 캐시 로드
      await userProvider.loadCurrentUserFromPrefs();

      // 그 다음 서버에서 최신 정보 가져오기
      await userProvider.fetchMyProfile();
    } catch (e) {
      // 유저 정보 로드 실패는 앱 시작을 막지 않음
    }
  }

  Future<void> _loadGroupSchema() async {
    try {
      // GroupProvider를 통해 그룹 스키마 미리 로드 (메타데이터만)
      final groupProvider = context.read<GroupProvider>();
      await groupProvider.fetchMyGroups(forceRefresh: false);
    } catch (e) {
      // 그룹 스키마 로드 실패는 앱 시작을 막지 않음
      debugPrint('[SplashScreen] 그룹 스키마 로드 실패: $e');
    }
  }

  Future<void> _loadTrendingData() async {
    try {
      // SearchService를 통해 트렌딩 데이터 비동기 로드 (shimmer 없이)
      final searchService = SearchService();
      await searchService.fetchTrendingKeywords(
        limit: 5,
        showShimmer: false, // 🎯 앱 시작 시에는 shimmer 표시하지 않음
      );
    } catch (e) {
      // 트렌딩 데이터 로드 실패는 앱 시작을 막지 않음
    }
  }

  /// 앱 시작 시 FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
  Future<void> _checkAndSyncFcmToken() async {
    try {
      final authService = AuthService();
      // FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
      // 비동기로 처리하여 앱 시작을 막지 않음
      final permissionGranted = await authService
          .syncFcmTokenAndSettings()
          .catchError((e) {
            return false;
          });

      // 🎯 알림 권한이 허용되었으면 로컬 설정도 on으로 동기화
      if (permissionGranted == true && mounted) {
        try {
          final userProvider = context.read<UserProvider>();
          // 서버에서 최신 설정을 가져와서 로컬에 동기화
          await userProvider.loadSettings();
          // 🎯 로컬 설정도 명시적으로 on으로 설정
          userProvider.updateNotificationEnabled(true);
        } catch (e) {
          debugPrint('[SplashScreen] 로컬 설정 동기화 실패 (무시): $e');
        }
      }
    } catch (e) {
      debugPrint('[SplashScreen] FCM 토큰 검사 오류 (무시): $e');
    }
  }

  /// 🎯 설정 정보 및 받은 친구 요청 비동기 로드 (앱 시작을 막지 않음)
  Future<void> _loadSettingsAndFriendRequests() async {
    try {
      // 설정 정보 로드
      final userProvider = context.read<UserProvider>();
      userProvider.loadSettings().catchError((e) {
        debugPrint('[SplashScreen] 설정 정보 로드 실패 (무시): $e');
      });

      // 받은 친구 요청 로드
      final friendProvider = context.read<FriendProvider>();
      friendProvider.fetchAllFriendData(forceRefresh: false).catchError((e) {
        debugPrint('[SplashScreen] 친구 요청 로드 실패 (무시): $e');
      });
    } catch (e) {
      debugPrint('[SplashScreen] 설정/친구 요청 로드 오류 (무시): $e');
    }
  }

  Future<void> _navigateAfterReady() async {
    // 🎯 애니메이션과 부트스트랩을 동일한 await 그룹으로 묶기
    await Future.wait([
      _fadeInController.forward().orCancel.catchError((_) => null),
      _bootstrapFuture,
    ]);

    if (!mounted) return;

    // 🎯 로딩 완료 후 dopp 로고 페이드아웃 애니메이션 시작
    await _fadeOutController.forward();

    if (!mounted) return;

    // 부트스트랩 결과에 따라 네비게이션
    final result = await _bootstrapFuture;
    if (!mounted) return;

    if (result.loggedIn) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder:
              (_, __, ___) => RootShell(
                initialIndex: 0,
                preloadedHomeData: result.homeData,
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
    _fadeInController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _fadeInController,
                _fadeOutController,
              ]),
              builder: (context, _) {
                // 페이드아웃이 진행 중이면 fadeOutOpacity, 아니면 fadeInOpacity
                final currentOpacity =
                    _fadeOutController.value > 0.0
                        ? _fadeOutOpacity.value
                        : _fadeInOpacity.value;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    DoppyLoadingLogo(
                      opacity: currentOpacity,
                      dTextSize: 40,
                      ppyTextSize: 40,
                      spinnerStrokeWidth: 4.5,
                      spinnerColor: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
