import 'package:doppy/main.dart' show kTestForceKorean, RootShell;
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/region_service.dart';
import 'package:doppy/utils/deep_link_store.dart';
import 'package:doppy/utils/deep_link_handler.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
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
  bool _showRootShell = false;
  bool _hideSplashOverlay = false;
  HomeData? _preloadedHomeData;

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
      duration: const Duration(milliseconds: 300),
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
      _transitionAfterReady();
    });
  }

  void startSequence() {
    Future.delayed(const Duration(milliseconds: 550), () {
      HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      HapticFeedback.mediumImpact();
    });
  }

  Future<void> _maybeNavigateToPendingDeepLink() async {
    final pending = DeepLinkStore.consume();
    if (pending == null) return;

    // ✅ Splash 진입에서는 별도 "링크 여는 중" 로딩 라우트 없이,
    // 스플래시 오버레이 상태에서 바로 타겟 화면으로 전환한다.
    try {
      await DeepLinkHandler.handleDeepLink(
        context,
        pending,
        showLoadingOverlay: false,
      );
    } catch (e) {
      debugPrint('[SplashScreen] pending 딥링크 처리 실패(무시): $e');
    }
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

      // 🎯 디버그 모드에서만: JWT 토큰의 region과 kTestForceKorean 플래그 비교 및 동기화
      // 프로덕션에서는 처음 계정별로 한번 결정된 지역이 변하면 안됨
      if (kDebugMode) {
        try {
          // 🎯 main.dart의 테스트 플래그 확인
          final expectedRegion =
              kTestForceKorean == true
                  ? 'KR'
                  : (kTestForceKorean == false ? 'US' : null);

          // 플래그가 null이면 비교하지 않음 (실제 OS 언어 사용)
          if (expectedRegion == null) {
            debugPrint(
              '[SplashScreen] [DEBUG] kTestForceKorean=null, Region 동기화 스킵',
            );
          } else {
            final regionService = RegionService();
            final tokenRegion = await regionService.getRegionFromTokenAsync();

            debugPrint(
              '[SplashScreen] [DEBUG] Region 동기화 체크: 테스트 플래그=$expectedRegion, JWT=$tokenRegion',
            );

            // region이 다르면 업데이트 (디버그 모드에서만)
            if (tokenRegion != null && tokenRegion != expectedRegion) {
              debugPrint(
                '[SplashScreen] [DEBUG] Region 불일치 감지! $tokenRegion → $expectedRegion로 업데이트',
              );
              final updated = await regionService.updateUserRegion(
                expectedRegion,
              );
              if (updated) {
                debugPrint(
                  '[SplashScreen] [DEBUG] Region 업데이트 성공: $expectedRegion',
                );
                // 토큰이 갱신되었으므로 AuthProvider도 업데이트
                await authProvider.validateAndRefreshToken();

                // 🎯 업데이트 후 다시 확인
                final newTokenRegion =
                    await regionService.getRegionFromTokenAsync();
                debugPrint(
                  '[SplashScreen] [DEBUG] 업데이트 후 토큰 region 확인: $newTokenRegion (기대: $expectedRegion)',
                );
                if (newTokenRegion != expectedRegion) {
                  debugPrint(
                    '[SplashScreen] [DEBUG] ⚠️ 경고: 토큰 업데이트 후에도 region이 일치하지 않음!',
                  );
                }
              } else {
                debugPrint('[SplashScreen] [DEBUG] Region 업데이트 실패 (기존 토큰 사용)');
              }
            } else if (tokenRegion == null) {
              // 토큰에 region이 없으면 업데이트 (초기 로그인 시 region이 없을 수 있음)
              debugPrint(
                '[SplashScreen] [DEBUG] JWT에 region이 없음. 테스트 플래그=$expectedRegion로 업데이트',
              );
              final updated = await regionService.updateUserRegion(
                expectedRegion,
              );
              if (updated) {
                debugPrint(
                  '[SplashScreen] [DEBUG] Region 설정 성공: $expectedRegion',
                );
                await authProvider.validateAndRefreshToken();

                // 🎯 업데이트 후 다시 확인
                final newTokenRegion =
                    await regionService.getRegionFromTokenAsync();
                debugPrint(
                  '[SplashScreen] [DEBUG] 업데이트 후 토큰 region 확인: $newTokenRegion (기대: $expectedRegion)',
                );
              }
            } else {
              debugPrint('[SplashScreen] [DEBUG] Region 일치: $expectedRegion');
            }
          }
        } catch (e) {
          debugPrint('[SplashScreen] [DEBUG] Region 동기화 중 오류 (무시): $e');
        }
      }

      // 2. FCM 토큰 검사 및 필요시 재발급 (스피너 렌더링 안정화를 위해 약간 지연)
      // ✅ 스피너가 먼저 안정적으로 렌더링된 후 FCM 작업 시작
      Future.delayed(const Duration(milliseconds: 300), () {
        _checkAndSyncFcmToken();
      });

      // 3. 앱 시작 시 필수 데이터만 로드 (그룹 스키마 포함)
      // ✅ 스피너가 먼저 안정적으로 렌더링된 후 필수 데이터 로드 시작 (100ms 지연)
      await Future.delayed(const Duration(milliseconds: 100));

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

      // 4. 트렌딩 데이터는 비동기로 백그라운드에서 로드 (스피너 안정화를 위해 약간 지연)
      // ✅ 스피너가 먼저 안정적으로 렌더링된 후 트렌딩 데이터 로드 시작
      Future.delayed(const Duration(milliseconds: 500), () {
        _loadTrendingData();
      });

      // 5. 설정 정보 및 받은 요청은 비동기로 백그라운드에서 로드 (스피너 안정화를 위해 약간 지연)
      // ✅ 스피너가 먼저 안정적으로 렌더링된 후 설정/친구 요청 로드 시작
      Future.delayed(const Duration(milliseconds: 700), () {
        _loadSettingsAndFriendRequests();
      });

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

  Future<void> _transitionAfterReady() async {
    // 🎯 애니메이션과 부트스트랩을 동일한 await 그룹으로 묶기
    await Future.wait([
      _fadeInController.forward().orCancel.catchError((_) => null),
      _bootstrapFuture,
    ]);

    if (!mounted) return;

    // 부트스트랩 결과에 따라 네비게이션
    final result = await _bootstrapFuture;
    if (!mounted) return;

    if (result.loggedIn) {
      // ✅ RootShell은 항상 초기화 (홈 화면은 항상 생성됨)
      // 앱이 종료된 상태에서 딥링크로 열릴 때는 스플래시를 보여주고 초기화 후 타겟 페이지로 이동
      // RootShell을 먼저 "아래에" 렌더링해두고, 스플래시 오버레이만 페이드아웃
      // 화면 전환 시 포스트 리스트/배경이 "빡" 하고 늦게 나타나는 느낌을 줄인다.
      setState(() {
        _preloadedHomeData = result.homeData;
        _showRootShell = true;
      });

      // RootShell이 트리에 붙고, 그 다음 pending 딥링크가 있으면 "로딩 화면"을 먼저 올린다.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;

      await _maybeNavigateToPendingDeepLink();
      if (!mounted) return;

      // 🎯 로딩 완료 후 doppy 로고 페이드아웃 애니메이션 완료까지 대기
      await _fadeOutController.forward();
      if (!mounted) return;

      // 오버레이 제거 (이제 RootShell만 보이게)
      // 딥링크가 있으면 DeepLinkCoordinator가 처리하여 타겟 페이지로 이동함
      setState(() {
        _hideSplashOverlay = true;
      });

      // ✅ 스플래시 로고 애니메이션이 끝난 뒤에만 이미지 프리캐시 시작
      // (스플래시 중 precacheImage/디코딩이 돌면 원형 스피너가 버벅여 보일 수 있음)
      try {
        final homeData = result.homeData;
        if (homeData != null && !homeData.isEmpty) {
          final primaryPosts =
              homeData.friendsPosts.isNotEmpty
                  ? homeData.friendsPosts
                  : homeData.allPosts;
          if (primaryPosts.isNotEmpty) {
            _homeDataService.startPreloadingImagesInBackground(
              primaryPosts,
              context,
              count: 5,
            );
          }
        }
      } catch (e) {
        debugPrint('[SplashScreen] 이미지 프리캐시 시작 실패(무시): $e');
      }
    } else {
      // 로그인 화면으로 전환 (스택 초기화)
      await _fadeOutController.forward();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
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
          // ✅ 홈을 미리 렌더링 (스플래시가 위에 덮여있어서 사용자는 못 봄)
          if (_showRootShell)
            RootShell(initialIndex: 0, preloadedHomeData: _preloadedHomeData),

          // ✅ 스플래시 오버레이 (페이드아웃 후 제거)
          if (!_hideSplashOverlay)
            Positioned.fill(
              // ✅ 뒤에 깔린 RootShell이 로고 페이드아웃 중 "비쳐 보이지" 않도록
              // 오버레이 자체는 끝까지 불투명 배경을 유지한다.
              child: IgnorePointer(
                ignoring: true,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.background,
                  child: Center(
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

                        return RepaintBoundary(
                          // ✅ 스피너 렌더링 안정화: 별도 레이어로 격리하여 메인 스레드 블로킹 최소화
                          child: IgnorePointer(
                            ignoring: true,
                            child: DoppyLoadingLogo(
                              opacity: currentOpacity,
                              // Splash에서는 외부 애니메이션 컨트롤러가 opacity를 이미 제어하므로
                              // 내부 AnimatedOpacity 지연(400ms)을 제거해서 "완전히 사라진 뒤" 전환되게 함
                              opacityDuration: Duration.zero,
                              dTextSize: 40,
                              ppyTextSize: 40,
                              spinnerStrokeWidth: 4.5,
                              spinnerColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
