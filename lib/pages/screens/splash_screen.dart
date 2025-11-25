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

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  final HomeDataService _homeDataService = HomeDataService();

  HomeData? _preloadedHomeData;
  bool _isDataLoaded = false;
  bool _isTokenValidated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.1, curve: Curves.easeOut),
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
      final authProvider = context.read<AuthProvider>();
      final hasToken = await authProvider.checkLoginStatus();

      if (hasToken) {
        final isValid = await authProvider.validateAndRefreshToken();
        _isTokenValidated = isValid;
      } else {
        _isTokenValidated = false;
      }

      // 2. 토큰이 유효한 경우에만 데이터 로딩
      if (_isTokenValidated) {
        // 🎯 앱 시작 시 FCM 토큰 검사 및 필요시 재발급 (비동기로 처리하여 앱 시작을 막지 않음)
        _checkAndSyncFcmToken();

        // 🎯 앱 시작 시 필수 데이터만 로드 (그룹 스키마 포함)
        // 홈 데이터, 검색 기록, 유저 정보, 그룹 스키마를 병렬로 로드
        await Future.wait([
          _loadHomeData(),
          _loadSearchHistory(),
          _loadUserData(),
          _loadGroupSchema(),
        ]);

        // 🎯 트렌딩 데이터는 비동기로 백그라운드에서 로드 (앱 시작을 막지 않음)
        _loadTrendingData();

        // 🎯 설정 정보 및 받은 요청은 비동기로 백그라운드에서 로드 (앱 시작을 막지 않음)
        _loadSettingsAndFriendRequests();
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
      setState(() {
        _isTokenValidated = false;
        _isDataLoaded = true;
        _preloadedHomeData = HomeData(friendsPosts: [], allPosts: []);
      });
      await _navigateAfterReady();
    }
  }

  Future<void> _loadHomeData() async {
    try {
      // 통합 피드 데이터 서비스를 사용하여 두 섹션 동시 로드
      final homeData = await _homeDataService.preloadAllSections(
        page: 0,
        size: 20, // 🎯 10 -> 20으로 증가 (앱 시작 시에도 20개 로드)
      );

      setState(() {
        _preloadedHomeData = homeData;
      });

      // 이미지 미리 로드 (두 섹션 모두)
      if (!homeData.isEmpty) {
        final allPosts = [...homeData.friendsPosts, ...homeData.allPosts];
        await _homeDataService.precacheImages(allPosts, context);
      }

      setState(() {
        _isDataLoaded = true;
      });
    } catch (e) {
      debugPrint('[SplashScreen] 피드 데이터 로드 실패: $e');

      setState(() {
        _preloadedHomeData = HomeData(friendsPosts: [], allPosts: []);
        _isDataLoaded = true;
      });
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
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    DoppyLoadingLogo(
                      opacity: _opacity.value,
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
