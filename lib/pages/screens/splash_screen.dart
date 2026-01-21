import 'package:doppy/main.dart' show RootShell, navigatorKey;
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/weekly_contribution_provider.dart';
import 'package:doppy/providers/home_recommendation_provider.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/utils/deep_link_store.dart';
import 'package:doppy/utils/deep_link_handler.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/pages/screens/join_screen.dart';
import 'package:doppy/pages/onbording/onbording_flow.dart';
import 'package:doppy/data/models/home_recommendation_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/providers/publish_provider.dart';
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:dio/dio.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 부트스트랩 결과
class _BootstrapResult {
  final bool loggedIn;
  final bool requiresEmailVerification;

  const _BootstrapResult({
    required this.loggedIn,

    this.requiresEmailVerification = false,
  });

  factory _BootstrapResult.notLoggedIn() {
    return const _BootstrapResult(loggedIn: false);
  }

  factory _BootstrapResult.loggedIn() {
    return _BootstrapResult(loggedIn: true);
  }

  factory _BootstrapResult.emailVerificationRequired() {
    return const _BootstrapResult(
      loggedIn: true,
      requiresEmailVerification: true,
    );
  }
}

class SplashScreen extends StatefulWidget {
  final bool skipOnboarding; // ✅ 임시: 온보딩 플로우 스킵 플래그 (포스트에서 진입 시)

  const SplashScreen({super.key, this.skipOnboarding = false});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeInController;
  late final Animation<double> _fadeInOpacity;
  late final AnimationController _fadeOutController;
  late final Animation<double> _fadeOutOpacity;

  late final Future<_BootstrapResult> _bootstrapFuture;
  bool _showRootShell = false;
  bool _hideSplashOverlay = false;
  bool _shouldForceOnboardingFlow = false; // 🎯 온보딩 미완료 계정이면 강제 진입 (서버 플래그 기반)
  bool _isMonitoringOnboardingPublish = false;
  VoidCallback? _onboardingPublishListener;

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

      // 이메일 인증 강제: JWT payload의 email이 null/empty면 이메일 인증 화면으로 보냄
      try {
        final email = await AuthService().getEmailFromToken();
        if (email == null) {
          return _BootstrapResult.emailVerificationRequired();
        }
      } catch (_) {}

      // 2. FCM 토큰 검사 및 필요시 재발급 (스피너 렌더링 안정화를 위해 약간 지연)
      // 스피너가 먼저 안정적으로 렌더링된 후 FCM 작업 시작
      // TODO: 알림 데이터 호출 주석처리
      // _checkAndSyncFcmToken();

      // 🎯 새로운 초기 로딩 순서 (번들 API 사용)
      // MyProfileFeed를 먼저 로드한 후 WeeklyContributions에서 totalPosts 사용
      // ✅ 필수 API: _loadUserBundle은 반드시 성공해야 함 (실패 시 로그인 화면으로)
      try {
        await _loadUserBundle();
      } catch (e) {
        // ✅ 유저 번들 로드 실패 시 (401, 502 등) 로그인 화면으로 리다이렉트
        // UserService가 DioException을 Exception으로 변환하므로 에러 메시지도 체크
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          debugPrint(
            '[SplashScreen] ⚠️ 유저 번들 로드 실패 (status: $statusCode) - 로그인 화면으로 리다이렉트',
          );
          return _BootstrapResult.notLoggedIn();
        }

        // ✅ Exception 메시지에 상태 코드가 포함된 경우도 체크
        final errorStr = e.toString();
        if (errorStr.contains('401') || errorStr.contains('502')) {
          debugPrint(
            '[SplashScreen] ⚠️ 유저 번들 로드 실패 (에러 메시지: $errorStr) - 로그인 화면으로 리다이렉트',
          );
          return _BootstrapResult.notLoggedIn();
        }

        // 기타 에러는 rethrow하여 상위에서 처리
        rethrow;
      }

      // 나머지 API는 병렬로 로드 (실패해도 앱 시작은 가능)
      await Future.wait([
        _loadFriendsBundle(),
        _loadMyProfileFeed(),
        _loadHomeRecommendations(), // ✅ 홈용 추천 카드 로드
      ]);

      // ✅ 홈(FillSection) "첫 화면" 이미지는 스플래시가 사라지기 전에 동기 프리로드
      // - CachedNetworkImage가 memCacheWidth로 리사이즈 디코드를 하므로,
      //   precache도 동일한 ResizeImage(width)로 해야 회색 placeholder가 사라진다.
      await _preloadHomeFillSectionCriticalImages();

      // ✅ 홈 화면의 모든 이미지/영상을 비동기로 프리캐싱 시작 (화면 진입을 막지 않음)
      _precacheAllHomeMedia();

      // MyProfileFeed 로드 완료 후 WeeklyContributions 로드 (totalPosts 사용을 위해)
      await _loadWeeklyContributions();

      // 5. 검색 기록 및 추천 포스트 (비동기)
      _loadSearchHistory();
      _loadSearchScreenData();

      return _BootstrapResult.loggedIn();
    } catch (e) {
      debugPrint('[SplashScreen] 부트스트랩 오류: $e');

      // ✅ 부트스트랩에서 DioException 발생 시 상태 코드 확인
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        // 401 (인증 실패) 또는 502 (서버 오류 - 인증 문제일 수 있음)는 로그인 화면으로
        if (statusCode == 401 || statusCode == 502) {
          debugPrint(
            '[SplashScreen] ⚠️ 부트스트랩 중 에러 발생 (status: $statusCode) - 로그인 화면으로 리다이렉트',
          );
          return _BootstrapResult.notLoggedIn();
        }
      }

      // ✅ Exception 메시지에 "401", "502" 또는 "인증이 필요"가 포함된 경우도 체크
      // (UserService가 DioException을 Exception으로 변환하므로)
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') ||
          errorStr.contains('502') ||
          errorStr.contains('unauthorized') ||
          errorStr.contains('인증이 필요') ||
          errorStr.contains('유저 번들 조회 실패: 401') ||
          errorStr.contains('유저 번들 조회 실패: 502')) {
        debugPrint('[SplashScreen] ⚠️ 부트스트랩 중 인증/서버 에러 발생 - 로그인 화면으로 리다이렉트');
        return _BootstrapResult.notLoggedIn();
      }

      // ✅ 기타 에러도 로그인 화면으로 리다이렉트 (안전을 위해)
      // 부트스트랩에서 에러가 발생했다는 것은 인증/초기화에 문제가 있다는 의미
      debugPrint('[SplashScreen] ⚠️ 부트스트랩 중 예상치 못한 에러 발생 - 로그인 화면으로 리다이렉트');
      return _BootstrapResult.notLoggedIn();
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      // SearchService를 통해 검색 기록 미리 로드
      final searchService = SearchService();
      await searchService.loadSearchHistory();
    } catch (e) {
      // 검색 기록 로드 실패는 앱 시작을 막지 않음 (무시)
    }
  }

  /// 🎯 서버에서 온보딩 완료 여부 확인
  bool _isOnboardingCompleted() {
    try {
      final userProvider = context.read<UserProvider>();
      final completed = userProvider.onboardingCompleted;
      // null이면 false로 간주 (온보딩 미완료)
      return completed ?? false;
    } catch (e) {
      debugPrint('[SplashScreen] 온보딩 완료 여부 확인 실패(스킵): $e');
      return true; // 체크 실패로 앱 진입을 막지 않는다.
    }
  }

  /// 🎯 탈퇴 진행 중 플래그 확인 및 처리 (재접속 시)
  Future<void> _checkAndHandleAccountDeletionInProgress() async {
    try {
      final authService = AuthService();
      final accountKey = await authService.getAccountKeyFromToken();
      if (accountKey == null) {
        return; // 계정 식별이 안 되면 스킵
      }

      final prefs = await SharedPreferences.getInstance();
      final key = 'account_deletion_in_progress_$accountKey';
      final isInProgress = prefs.getBool(key) ?? false;

      if (isInProgress) {
        debugPrint('[SplashScreen] ⚠️ 탈퇴 진행 중 플래그 감지됨 - 서버 상태 확인 후 처리');

        // ✅ 서버에서 계정 상태 확인 (401/403이면 이미 삭제됨)
        try {
          final userProvider = context.read<UserProvider>();
          // fetchUserBundle을 호출하여 서버 상태 확인
          await userProvider.fetchUserBundle(throwOnAuthError: false);
          // 성공하면 계정이 살아있음 → 플래그만 제거 (재시도 가능)
          await prefs.remove(key);
          debugPrint('[SplashScreen] ✅ 계정이 살아있음 - 탈퇴 진행 중 플래그 제거');
        } catch (e) {
          // 401/403이면 계정이 삭제됨 → 로컬 파쇄 진행
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('401') ||
              errorStr.contains('403') ||
              errorStr.contains('unauthorized')) {
            debugPrint('[SplashScreen] ✅ 서버에서 계정 삭제 확인됨 - 로컬 파쇄 진행');
            // 로컬 파쇄
            await AuthProvider().logout();
            final prefs2 = await SharedPreferences.getInstance();
            await prefs2.clear();
            await prefs2.remove(key);
            debugPrint('[SplashScreen] ✅ 로컬 데이터 파쇄 완료');
          } else {
            // 다른 에러면 플래그 유지 (네트워크 문제일 수 있음)
            debugPrint('[SplashScreen] ⚠️ 서버 상태 확인 실패 - 탈퇴 진행 중 플래그 유지: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[SplashScreen] 탈퇴 진행 중 플래그 확인 실패(스킵): $e');
    }
  }

  /// 유저 + 세팅 번들 로드
  Future<void> _loadUserBundle() async {
    try {
      // ✅ 탈퇴 진행 중 플래그 확인 (재접속 시 처리)
      await _checkAndHandleAccountDeletionInProgress();

      final userProvider = context.read<UserProvider>();

      // 먼저 로컬 캐시 로드
      await userProvider.loadCurrentUserFromPrefs();

      // 그 다음 서버에서 번들 정보 가져오기 (유저 + 세팅 통합)
      // ✅ 부트스트랩에서는 401/403 같은 인증 실패를 반드시 throw해서 로그인으로 보낸다.
      await userProvider.fetchUserBundle(throwOnAuthError: true);

      // 🎯 서버에서 온보딩 완료 여부 확인
      final completed = _isOnboardingCompleted();
      if (!completed) {
        if (mounted) {
          setState(() {
            _shouldForceOnboardingFlow = true;
          });
        }
        debugPrint('[SplashScreen] 온보딩 미완료 계정 감지됨 (서버 플래그) - 온보딩 플로우로 이동 예정');
      }
    } catch (e) {
      // ✅ 401, 502 등 모든 에러는 다시 throw하여 부트스트랩에서 처리
      // (유저 번들은 필수이므로 실패 시 로그인 화면으로 리다이렉트)
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        debugPrint('[SplashScreen] 유저 번들 로드 중 에러 발생 (status: $statusCode)');
        rethrow;
      }
      debugPrint('[SplashScreen] 유저 번들 로드 실패: $e');
      // DioException이 아닌 경우도 rethrow
      rethrow;
    }
  }

  /// 친구 번들 로드
  Future<void> _loadFriendsBundle() async {
    try {
      final friendProvider = context.read<FriendProvider>();
      await friendProvider.fetchFriendsBundle(forceRefresh: false);
    } catch (e) {
      // ✅ 401 에러는 다시 throw하여 부트스트랩에서 처리
      if (e is DioException && e.response?.statusCode == 401) {
        debugPrint('[SplashScreen] 친구 번들 로드 중 401 에러 발생');
        rethrow;
      }
      debugPrint('[SplashScreen] 친구 번들 로드 실패: $e');
      // 친구 정보 로드 실패는 앱 시작을 막지 않음 (401 제외)
    }
  }

  /// 주차 기여도 로드 (프로바이더에 저장)
  Future<void> _loadWeeklyContributions() async {
    try {
      final provider = context.read<WeeklyContributionProvider>();
      final currentYear = WeekUtils.getCurrentYear();

      // 현재 연도의 기여도 데이터 로드
      await provider.loadContributions(currentYear);

      // 총 포스트 개수 설정 (MyProfileFeedProvider에서)
      // MyProfileFeed가 먼저 로드되어야 하므로 이미 완료된 상태
      final feedProvider = context.read<MyProfileFeedProvider>();
      final userInfo = feedProvider.userInfo;

      int? totalPosts;

      if (userInfo != null && userInfo.containsKey('totalPosts')) {
        totalPosts = userInfo['totalPosts'] as int?;
        if (totalPosts != null) {
          provider.setTotalPostCount(totalPosts);
        }
      }

      // 서버에서 totalPosts를 받지 못한 경우, BaseFeedProvider의 totalPostCount 사용
      if (totalPosts == null || totalPosts == 0) {
        final totalPostCount = feedProvider.totalPostCount;
        if (totalPostCount > 0) {
          provider.setTotalPostCount(totalPostCount);
        }
      }
    } catch (e) {
      // ✅ 401 에러는 다시 throw하여 부트스트랩에서 처리
      if (e is DioException && e.response?.statusCode == 401) {
        debugPrint('[SplashScreen] 주차 기여도 로드 중 401 에러 발생');
        rethrow;
      }
      debugPrint('[SplashScreen] 주차 기여도 로드 실패 (무시): $e');
    }
  }

  /// 내 프로필 피드 로드
  Future<void> _loadMyProfileFeed() async {
    try {
      final myProfileFeedProvider = context.read<MyProfileFeedProvider>();
      // username은 null (내 프로필)
      await myProfileFeedProvider.loadInitial(username: null, force: false);
      debugPrint('[SplashScreen] 내 프로필 피드 로드 완료');
    } catch (e) {
      // ✅ 401 에러는 다시 throw하여 부트스트랩에서 처리
      if (e is DioException && e.response?.statusCode == 401) {
        debugPrint('[SplashScreen] 내 프로필 피드 로드 중 401 에러 발생');
        rethrow;
      }
      debugPrint('[SplashScreen] 내 프로필 피드 로드 실패 (무시): $e');
      // 피드 로드 실패는 앱 시작을 막지 않음 (401 제외)
    }
  }

  /// 🎯 검색 화면용 데이터 미리 로드 (추천 포스트만)
  Future<void> _loadSearchScreenData() async {
    try {
      final searchService = SearchService();
      // 추천 포스트 20개만 로드 (5개는 Hero, 나머지는 그리드용)
      await searchService.fetchRecommendedPosts(page: 0, size: 20);
    } catch (e) {
      // 데이터 로드 실패는 앱 시작을 막지 않음
      debugPrint('[SplashScreen] 검색 화면 데이터 로드 실패: $e');
    }
  }

  /// 홈용 추천 카드 로드
  Future<void> _loadHomeRecommendations() async {
    try {
      final provider = context.read<HomeRecommendationProvider>();
      await provider.loadHomeRecommendations();
      debugPrint('[SplashScreen] 홈용 추천 카드 로드 완료');
    } catch (e) {
      // ✅ 401 에러는 다시 throw하여 부트스트랩에서 처리
      if (e is DioException && e.response?.statusCode == 401) {
        debugPrint('[SplashScreen] 홈용 추천 카드 로드 중 401 에러 발생');
        rethrow;
      }
      // 데이터 로드 실패는 앱 시작을 막지 않음 (401 제외)
      debugPrint('[SplashScreen] 홈용 추천 카드 로드 실패 (무시): $e');
    }
  }

  /// 홈의 FillSection(큰 이미지 PageView)에서 "첫 장"이 즉시 보이도록 동기 프리로드한다.
  ///
  /// 핵심:
  /// - `PostFillSection` 내부가 `CachedNetworkImage(memCacheWidth: screenWidth*dpr*2)`를 쓰므로
  ///   precache도 `ResizeImage(width: screenWidth*dpr*2)`로 맞춰야 한다.
  Future<void> _preloadHomeFillSectionCriticalImages() async {
    try {
      if (!mounted) return;

      final screenWidth = MediaQuery.of(context).size.width;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      const maxDecodeWidthPx = 3072; // ✅ 과도한 디코드는 실패/지연 방지
      final memCacheWidth = (screenWidth * dpr * 2).round().clamp(
        1,
        maxDecodeWidthPx,
      );

      final urls = <String>[];

      // LockedHomeWidget: PostFillSection은 "최근 포스트"에서 posts.skip(1) 첫 장이 가장 빨리 보임
      try {
        final myFeed = context.read<MyProfileFeedProvider>();
        if (myFeed.posts.length >= 2) {
          final u = myFeed.posts[1]['thumbnailImageUrl'] as String?;
          if (u != null && u.trim().isNotEmpty) urls.add(u);
        }
      } catch (_) {}

      // UnlockedHomeWidget: EVENT_EMOTION(PostFillSection) 각 섹션의 첫 장만
      try {
        final recProvider = context.read<HomeRecommendationProvider>();
        final emotionBased = recProvider.getRecommendationsByType(
          RecCardType.EVENT_EMOTION,
        );
        for (final rec in emotionBased) {
          if (rec.posts.isEmpty) continue;
          final u = rec.posts.first['thumbnailImageUrl'] as String?;
          if (u != null && u.trim().isNotEmpty) urls.add(u);
        }
      } catch (_) {}

      final uniqueUrls = urls.toSet().toList();
      if (uniqueUrls.isEmpty) return;

      // ✅ "동기 프리로드": 첫 화면에 필요한 것만 await
      // (너무 많이 await하면 스플래시가 길어지므로 3개 정도로 제한)
      final critical = uniqueUrls.take(3).toList();

      debugPrint(
        '[SplashScreen] 🚀 홈 FillSection 동기 프리로드 시작: ${critical.length}개',
      );

      await Future.wait(
        critical.map((url) async {
          if (!mounted) return;
          try {
            final base = CachedNetworkImageProvider(url);
            final effective = ResizeImage(base, width: memCacheWidth);
            await precacheImage(effective, context);
            debugPrint('[SplashScreen] ✅ FillSection 프리로드 완료: $url');
          } catch (e) {
            if (e.toString().contains('dispose') ||
                e.toString().contains('mounted')) {
              debugPrint('[SplashScreen] ⚠️ context dispose로 인한 중단: $url');
              return;
            }
            debugPrint('[SplashScreen] ❌ FillSection 프리로드 실패: $url - $e');
          }
        }),
        eagerError: false,
      );

      debugPrint('[SplashScreen] ✅ 홈 FillSection 동기 프리로드 완료');
    } catch (e) {
      debugPrint('[SplashScreen] 홈 FillSection 프리로드 실패(무시): $e');
    }
  }

  /// ✅ 홈 화면의 모든 이미지/영상을 비동기로 프리캐싱
  /// 홈 데이터 로드 후 호출하여 백그라운드에서 프리캐싱 시작
  void _precacheAllHomeMedia() {
    if (!mounted) return;

    try {
      final recommendationProvider = context.read<HomeRecommendationProvider>();
      final friendProvider = context.read<FriendProvider>();
      final myFeedProvider = context.read<MyProfileFeedProvider>();

      final recommendations = recommendationProvider.recommendations;
      final friendPosts = friendProvider.friendPosts;
      final myProfilePosts = myFeedProvider.posts;
      final userInfo = myFeedProvider.userInfo;
      final profileImageUrl = userInfo?['profileImageUrl'] as String?;

      // 비동기로 프리캐싱 시작 (화면 진입을 막지 않음)
      HomeRecommendationProvider.precacheAllHomeMedia(
        context: context,
        recommendations: recommendations,
        friendPosts: friendPosts,
        myProfilePosts: myProfilePosts,
        profileImageUrl: profileImageUrl,
      );

      // ✅ 비디오 URL은 컨트롤러 프리로드 (이미지 precache로는 효과 없음)
      final urls = HomeRecommendationProvider.collectAllHomeMediaUrls(
        recommendations: recommendations,
        friendPosts: friendPosts,
        myProfilePosts: myProfilePosts,
        profileImageUrl: profileImageUrl,
      );
      for (final url in urls) {
        final u = url.toLowerCase();
        final isVideo =
            u.endsWith('.mp4') ||
            u.endsWith('.mov') ||
            u.endsWith('.m4v') ||
            u.contains('/videos/') ||
            u.contains('video');
        if (isVideo) {
          ThumbnailVideoPlayer.preload(url);
        }
      }
    } catch (e) {
      debugPrint('[SplashScreen] 홈 미디어 프리캐싱 시작 실패(무시): $e');
    }
  }

  /// 앱 시작 시 FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
  // ignore: unused_element
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
      // (번들 API에서 이미 설정을 가져왔으므로 여기서는 로컬만 업데이트)
      if (permissionGranted == true && mounted) {
        try {
          final userProvider = context.read<UserProvider>();
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

  Future<void> _transitionAfterReady() async {
    // 🎯 애니메이션과 부트스트랩을 동일한 await 그룹으로 묶기
    // ✅ 온보딩 업로드는 홈 진입을 막지 않고, 홈 위에서 "업로드 중..."으로 UX 제공
    await Future.wait([
      _fadeInController.forward().orCancel.catchError((_) => null),
      _bootstrapFuture,
    ]);

    if (!mounted) return;

    // 부트스트랩 결과에 따라 네비게이션
    final result = await _bootstrapFuture;
    if (!mounted) return;

    // ✅ 온보딩 게시로 스플래시에 들어온 경우:
    // - 업로드 상태를 홈 위에서 감시하면서, 진행 중에는 스낵바 노출
    if (result.loggedIn && widget.skipOnboarding) {
      _startMonitoringOnboardingPublish();
    }

    // 이메일 인증이 필요하면: JoinScreen의 이메일 인증 단계 재활용
    if (result.loggedIn && result.requiresEmailVerification) {
      await _fadeOutController.forward();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder:
              (_, __, ___) => JoinScreen(
                emailVerificationOnly: true,
                onEmailVerified: () {
                  // 이메일 인증 완료 후 스플래시로 돌아가서 다시 부트스트랩
                  // 스택을 완전히 비우고 스플래시로 이동
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const SplashScreen(),
                        transitionDuration: const Duration(milliseconds: 250),
                        transitionsBuilder: (_, animation, __, child) {
                          return FadeTransition(
                            opacity: CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOut,
                            ),
                            child: child,
                          );
                        },
                      ),
                      (route) => false, // 모든 이전 라우트 제거
                    );
                  }
                },
              ),
          transitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
        ),
      );
      return;
    }

    // 첫 회원가입이면 온보딩 플로우로 이동
    // ✅ 정책:
    // - 첫 회원가입이거나
    // - 온보딩 완료 플래그가 아직 없으면
    //   → 앱 진입 시 온보딩 플로우부터 시작
    if (result.loggedIn &&
        !widget.skipOnboarding &&
        _shouldForceOnboardingFlow) {
      //테스트 (반대로))
      await _fadeOutController.forward();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const OnboardingFlow(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
        ),
      );
      return;
    }

    if (result.loggedIn) {
      // ✅ RootShell은 항상 초기화 (홈 화면은 항상 생성됨)
      // 앱이 종료된 상태에서 딥링크로 열릴 때는 스플래시를 보여주고 초기화 후 타겟 페이지로 이동
      // RootShell을 먼저 "아래에" 렌더링해두고, 스플래시 오버레이만 페이드아웃
      // 화면 전환 시 포스트 리스트/배경이 "빡" 하고 늦게 나타나는 느낌을 줄인다.
      setState(() {
        _showRootShell = true;
      });

      // RootShell이 트리에 붙고, 그 다음 pending 딥링크가 있으면 "로딩 화면"을 먼저 올린다.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;

      await _maybeNavigateToPendingDeepLink();
      if (!mounted) return;

      // ✅ 홈 첫 프레임 안정화 대기
      // - HomeScreen의 addPostFrameCallback(총 포스트 수 보정 등)로 인한 첫 프레임 "흔들림"을 줄이기 위함
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      // 🎯 로딩 완료 후 doppy 로고 페이드아웃 애니메이션 완료까지 대기
      await _fadeOutController.forward();
      if (!mounted) return;

      // 오버레이 제거 (이제 RootShell만 보이게)
      // 딥링크가 있으면 DeepLinkCoordinator가 처리하여 타겟 페이지로 이동함
      setState(() {
        _hideSplashOverlay = true;
      });
    } else {
      // 로그인 화면으로 전환 (스택 초기화)
      await _fadeOutController.forward();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  void _startMonitoringOnboardingPublish() {
    if (!mounted) return;
    if (_isMonitoringOnboardingPublish) return;
    _isMonitoringOnboardingPublish = true;

    final publishProvider = context.read<PublishProvider>();

    // 이미 성공 상태면: 즉시 홈 데이터 보강
    if (publishProvider.status == PublishFlowStatus.success) {
      Future.microtask(() async {
        if (!mounted) return;
        await _ensureFreshDataAfterOnboardingPublish();
      });
      return;
    }

    void listener() async {
      if (!mounted) return;

      // 업로드 시작/진행: (온보딩→홈 전환 시) 스낵바를 띄우지 않는다.
      if (publishProvider.status == PublishFlowStatus.publishing) return;

      // ✅ 성공이면 홈 데이터 즉시 보강
      if (publishProvider.status == PublishFlowStatus.success) {
        await _ensureFreshDataAfterOnboardingPublish();
      }

      // ✅ 실패면 재시도 UX 제공 (홈 위에서)
      if (publishProvider.status == PublishFlowStatus.failure) {
        final ctx = navigatorKey.currentContext;
        await _handleOnboardingPublishFailure(
          title: ctx?.tr('publish_failed_title') ?? 'Publish failed',
          error: publishProvider.lastError,
        );
      }

      // 1회성: 완료되면 리스너 제거
      try {
        publishProvider.removeListener(listener);
      } catch (_) {}
    }

    _onboardingPublishListener = listener;
    publishProvider.addListener(listener);
  }

  Future<void> _waitForOnboardingPublishIfNeeded() async {
    if (!widget.skipOnboarding) return;
    if (!mounted) return;

    final publishProvider = context.read<PublishProvider>();

    // ✅ 온보딩에서 게시하고 넘어온 경우가 아니라면(업로드 중이 아님) 즉시 리턴
    if (publishProvider.status != PublishFlowStatus.publishing) return;

    // ✅ 업로드 완료(성공/실패)까지 대기
    final completer = Completer<void>();

    void listener() {
      if (publishProvider.status != PublishFlowStatus.publishing) {
        publishProvider.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }

    publishProvider.addListener(listener);

    try {
      // 혹시 상태가 이미 바뀐 경우 방어
      if (publishProvider.status != PublishFlowStatus.publishing) {
        publishProvider.removeListener(listener);
        return;
      }

      // 무한 대기 방지: 5분 타임아웃
      await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      publishProvider.removeListener(listener);
      // 타임아웃은 실패로 간주하고 재시도 UX를 띄운다.
      final ctx = navigatorKey.currentContext;
      await _handleOnboardingPublishFailure(
        title: ctx?.tr('publish_failed_title') ?? 'Publish failed',
        error: 'publish timeout',
      );
      return;
    }

    // ✅ 완료 후 상태 체크: 실패면 재시도/온보딩 복귀
    if (publishProvider.status == PublishFlowStatus.failure) {
      final ctx = navigatorKey.currentContext;
      await _handleOnboardingPublishFailure(
        title: ctx?.tr('publish_failed_title') ?? 'Publish failed',
        error: publishProvider.lastError,
      );
      return;
    }
  }

  Future<void> _handleOnboardingPublishFailure({
    required String title,
    Object? error,
  }) async {
    if (!mounted) return;
    final publishProvider = context.read<PublishProvider>();

    // ⚠️ 이 함수는 "온보딩 → 홈" 전환 이후에도 호출될 수 있어,
    // SplashScreen의 build context 대신 항상 현재 트리의 context를 사용한다.
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    // 이미 provider 쪽에서도 바텀시트를 띄울 수 있지만,
    // 스플래시에서는 "막힌 화면"이 되지 않도록 여기서도 확실히 UX 제공
    final action = await RetryCancelBottomSheet.show(
      ctx,
      title: title,
      error: error,
    );
    if (!mounted) return;

    if (action == RetryCancelAction.retry &&
        publishProvider.lastRequest != null) {
      publishProvider.startPublish(publishProvider.lastRequest!);
      await _waitForOnboardingPublishIfNeeded();
      return;
    }

    // 취소면 온보딩 플로우로 복귀 (스택 초기화)
    await _fadeOutController.forward();
    if (!mounted) return;
    Navigator.of(ctx).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const OnboardingFlow(),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _ensureFreshDataAfterOnboardingPublish() async {
    if (!mounted) return;
    final publishProvider = context.read<PublishProvider>();
    if (publishProvider.status != PublishFlowStatus.success) return;

    try {
      // ✅ 홈 화면에서 바로 최신 상태가 보이도록 필수 데이터만 재로드
      // - WeeklyContribution은 loadContributions가 캐시가 있으면 스킵되므로,
      //   "발행 직후"에는 refreshAfterPostPublished(optimistic)로 즉시 보라색/카운트 반영 + 백그라운드 동기화
      await Future.wait([_loadMyProfileFeed(), _loadHomeRecommendations()]);

      final request = publishProvider.lastRequest;
      final year = request?.year ?? WeekUtils.getCurrentYear();
      final weekNumber =
          request?.nthWeek ?? WeekUtils.getWeekNumber(DateTime.now());

      final weekly = context.read<WeeklyContributionProvider>();
      await weekly.refreshAfterPostPublished(
        year,
        weekNumber: weekNumber,
        optimisticUpdate: true,
      );

      await _preloadHomeFillSectionCriticalImages();
    } catch (e) {
      debugPrint('[SplashScreen] 온보딩 게시 후 데이터 재로드 실패(무시): $e');
    }
  }

  @override
  void dispose() {
    // ✅ 온보딩 게시 감시 리스너 해제 (context 누수/잘못된 트리 참조 방지)
    try {
      final listener = _onboardingPublishListener;
      if (listener != null) {
        context.read<PublishProvider>().removeListener(listener);
      }
    } catch (_) {}
    _onboardingPublishListener = null;
    _isMonitoringOnboardingPublish = false;

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
          if (_showRootShell) RootShell(initialIndex: 0),

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
