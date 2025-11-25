import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/screens/search_screen.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/screens/home_screen.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

import 'package:doppy/pages/screens/onboarding_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
// import 'package:doppy/providers/feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/search_provider.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'firebase_options.dart';
import 'theme/theme.dart';
import 'utils/route_observer.dart';
import 'data/services/deep_link_service.dart';
import 'utils/deep_link_handler.dart';

// Global NavigatorKey for accessing context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 🎯 FCM 딥링크 처리
void _handleDeepLinkFromFcm(String deepLinkUrl) {
  final context = navigatorKey.currentContext;
  if (context == null) {
    debugPrint('[FCM] Navigator context가 없습니다 - 딥링크 처리를 건너뜁니다');
    return;
  }

  final result = DeepLinkService.parseDeepLink(deepLinkUrl);
  if (result != null && result.type != DeepLinkType.unknown) {
    DeepLinkHandler.handleDeepLink(context, result);
  }
}

// 🎯 FCM Background 메시지 핸들러 (top-level 함수로 선언)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase 초기화 필요 (background isolate에서는 별도로 초기화해야 함)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM] 백그라운드 메시지 수신: ${message.messageId}');
  debugPrint('[FCM] 데이터: ${message.data}');
  debugPrint(
    '[FCM] 알림: ${message.notification?.title} - ${message.notification?.body}',
  );
}

// 앱 버전 및 상수
class AppConstants {
  static const String appVersion = '1.0.0';

  // 🎯 이용약관 및 개인정보 처리방침 URL
  static const String termsOfServiceUrl =
      'https://www.notion.so/doppy-2a594e338df780e1b6b9fddb9753e728';
  static const String privacyPolicyUrl =
      'https://www.notion.so/doppy-2a594e338df780e1b6b9fddb9753e728'; // TODO: 개인정보 처리방침 URL로 변경 필요

  // 🎯 문의하기 이메일 주소
  static const String contactEmail = 'app.doppy@gmail.com';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🎯 Firebase 초기화
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    debugPrint('[Firebase] 플랫폼: ${defaultTargetPlatform}');

    await Firebase.initializeApp(options: options);

    // 🎯 FCM 백그라운드 메시지 핸들러 등록 (Firebase 초기화 후)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 🎯 FCM 포그라운드 메시지 핸들러 등록
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] 포그라운드 메시지 수신: ${message.messageId}');
      debugPrint('[FCM] 데이터: ${message.data}');
      debugPrint(
        '[FCM] 알림: ${message.notification?.title} - ${message.notification?.body}',
      );
      // 포그라운드에서는 알림을 표시하지 않음
    });

    // 🎯 FCM 메시지 클릭 핸들러 등록
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // 🎯 딥링크 처리
      final deepLink = message.data['deepLink'] as String?;
      if (deepLink != null && deepLink.isNotEmpty) {
        _handleDeepLinkFromFcm(deepLink);
      }
    });

    // 🎯 앱이 종료된 상태에서 알림 클릭으로 열린 경우 확인
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // 🎯 딥링크 처리
      final deepLink = initialMessage.data['deepLink'] as String?;
      if (deepLink != null && deepLink.isNotEmpty) {
        debugPrint('[FCM] 초기 딥링크 발견: $deepLink');
        // 앱 초기화 완료 후 처리
        Future.delayed(const Duration(milliseconds: 1000), () {
          _handleDeepLinkFromFcm(deepLink);
        });
      }
    }
  } catch (e) {
    debugPrint('[Firebase] 초기화 실패: $e');
  }

  // 1. FlutterSecureStorage 인스턴스를 생성합니다.
  const storage = FlutterSecureStorage();

  // 2. 'hasSeenOnboarding' 키의 값을 문자열로 읽어옵니다.
  final String? hasSeenOnboardingStr = await storage.read(
    key: 'hasSeenOnboarding',
  );

  // 3. 읽어온 값이 'true' 문자열인지 확인합니다.
  final bool hasSeenOnboarding = hasSeenOnboardingStr == 'true';

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) => OtherProfileFeedProvider(),
        ), // 싱글톤 인스턴스 사용
        ChangeNotifierProvider(
          create: (_) => MyProfileFeedProvider(),
        ), // 내 피드용 (싱글톤 인스턴스 사용)
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => CategoryOverlayProvider()),
        ChangeNotifierProvider(create: (_) => PostDragDropService()),

        ChangeNotifierProvider(create: (_) => SearchService()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => NodeComponentService()),
        ChangeNotifierProvider(create: (_) => StickerService()),
        ChangeNotifierProvider(create: (_) => UploadService()),
      ],
      child: MyApp(
        hasSeenOnboarding: hasSeenOnboarding,
      ), // MyApp 위젯을 child로 감싸줍니다.
    ),
  );

  // 전역 1회: 네트워크 모니터/재로딩 코디네이터 시작
  try {
    NetworkManager.initConnectivityMonitor();
  } catch (_) {}
  ConnectivityReloadCoordinator().start();
}

class MyApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const MyApp({super.key, required this.hasSeenOnboarding});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Doppy',
          debugShowCheckedModeBanner: false,

          // 다국어 설정
          locale: localeProvider.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            const AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: context.watch<ThemeProvider>().themeMode,
          home: const SplashScreen(),
          navigatorObservers: [routeObserver],
          routes: {
            '/home': (_) => const RootShell(initialIndex: 0),
            '/login': (_) => const LoginScreen(),
            '/search': (_) => const RootShell(initialIndex: 1),
            '/profile': (context) => const RootShell(initialIndex: 3),
            '/post-write': (_) => PostwriteScreen(isEditingMode: false),
          },

          onUnknownRoute:
              (_) => MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
    );
  }
}

class RootShell extends StatefulWidget {
  final int initialIndex; // 0:홈,1:검색,2:작성,3:프로필
  final HomeData? preloadedHomeData; // 스플래시 선로딩 데이터 전달용
  const RootShell({super.key, this.initialIndex = 0, this.preloadedHomeData});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  late int _index;
  String? _searchInitialQuery; // 검색 화면 초기 검색어
  final DeepLinkService _deepLinkService = DeepLinkService();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    // 라이프사이클 옵저버 등록
    WidgetsBinding.instance.addObserver(this);

    // 🎯 딥링크 리스너 등록 (웹 링크 직접 클릭 시 처리)
    _deepLinkService.listenToDeepLinks((DeepLinkResult result) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        debugPrint('[RootShell] 웹 링크에서 딥링크 수신: type=${result.type}');
        DeepLinkHandler.handleDeepLink(context, result);
      } else {
        debugPrint('[RootShell] Navigator context가 없습니다 - 딥링크 처리를 건너뜁니다');
      }
    });
  }

  @override
  void dispose() {
    // 라이프사이클 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
    // 딥링크 리스너 해제
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 포그라운드로 전환 시 FCM 토큰 검사 및 필요시 재발급
    if (state == AppLifecycleState.resumed) {
      _checkAndSyncFcmTokenOnForeground();
    }
  }

  /// 포그라운드 전환 시 인증 토큰 및 FCM 토큰 검사 및 필요시 재발급
  void _checkAndSyncFcmTokenOnForeground() {
    // 로그인 상태 확인 후 토큰 검사
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isLoggedIn) {
      try {
        // 🎯 1. 인증 토큰 검증 및 갱신 (세션 만료 다이얼로그 표시 전에 미리 갱신)
        // 비동기로 처리하여 UI를 막지 않음
        authProvider
            .validateAndRefreshToken()
            .then((isValid) {
              if (!isValid) {
                debugPrint(
                  '[RootShell] 포그라운드 전환 시 인증 토큰 갱신 실패 - 세션이 만료되었을 수 있음',
                );
                // 토큰 갱신 실패 시 다음 API 호출 시 세션 만료 다이얼로그가 표시됨
                return;
              }
              debugPrint('[RootShell] ✅ 포그라운드 전환 시 인증 토큰 검증 완료');
            })
            .catchError((e) {
              debugPrint('[RootShell] 포그라운드 전환 시 인증 토큰 검증 오류 (무시): $e');
            });

        // 🎯 2. FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
        // 비동기로 처리하여 UI를 막지 않음
        final authService = AuthService();
        authService
            .syncFcmTokenAndSettings()
            .then((permissionGranted) {
              // 🎯 알림 권한이 허용되었으면 로컬 설정도 on으로 동기화
              if (permissionGranted == true && mounted) {
                try {
                  final userProvider = Provider.of<UserProvider>(
                    context,
                    listen: false,
                  );
                  userProvider
                      .loadSettings()
                      .then((_) {
                        userProvider.updateNotificationEnabled(true);
                      })
                      .catchError((e) {});
                } catch (e) {}
              }
            })
            .catchError((e) {
              debugPrint('[RootShell] 포그라운드 전환 시 FCM 토큰 검사 및 동기화 실패 (무시): $e');
            });
      } catch (e) {
        debugPrint('[RootShell] 포그라운드 전환 시 토큰 검사 오류 (무시): $e');
      }
    }
  }

  // 검색 화면 열기
  void _openSearchScreen([String? initialQuery]) {
    if (!mounted) return;
    setState(() {
      _searchInitialQuery = initialQuery;
      _index = 1; // 검색 탭으로 전환
    });
  }

  // 탭 변경 처리 (검색 화면에서 호출)
  void _handleTabChange(int index) {
    if (!mounted) return;

    // 글쓰기 탭(2)은 글쓰기 화면 열기
    if (index == 2) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  PostwriteScreen(isEditingMode: false),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // 일반 탭 전환
    setState(() {
      _index = index;
      if (index != 1) {
        _searchInitialQuery = null;
      }
    });
  }

  void _onTap(int i) {
    final searchResultProvider = context.read<SearchProvider>();

    // 홈 탭 클릭
    if (i == 0) {
      if (searchResultProvider.isSearchOverlayVisible) {
        searchResultProvider.setSearchOverlayVisible(false);
      }
      setState(() {
        _index = 0;
        _searchInitialQuery = null;
      });
      return;
    }

    // 검색 탭 클릭
    if (i == 1) {
      _openSearchScreen();
      return;
    }

    // 글쓰기 탭 클릭
    if (i == 2) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  PostwriteScreen(isEditingMode: false),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // 프로필 탭 클릭
    setState(() {
      _index = i;
      if (i != 1) {
        _searchInitialQuery = null;
      }
    });

    // 다른 탭으로 이동 시 검색 오버레이 상태 해제
    if (i != 0) {
      searchResultProvider.setSearchOverlayVisible(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 각 탭의 화면을 IndexedStack으로 재사용 (새로 만들어지지 않음)
    return Material(
      child: Stack(
        children: [
          // 모든 탭 화면을 미리 생성하고 IndexedStack으로 관리 (상태 유지)
          IndexedStack(
            index: _index,
            children: [
              // 홈 화면
              HomeScreen(
                preloadedHomeData: widget.preloadedHomeData,
                isActive: _index == 0,
                onOpenSearchScreen: (query) => _openSearchScreen(query),
              ),
              // 검색 화면
              SearchScreenOverlay(
                initialQuery: _searchInitialQuery,
                onClose: () {
                  if (mounted) {
                    setState(() {
                      _index = 0;
                      _searchInitialQuery = null;
                    });
                  }
                },
                onTabChange: _handleTabChange,
              ),
              // 글쓰기 탭은 Navigator로 처리하므로 빈 위젯
              const SizedBox.shrink(),
              // 프로필 화면
              const UserProfileScreen(isFromBottomTab: true),
            ],
          ),
          // 플로팅 바텀 네비게이션 바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomBottomNavigationBar(
              currentIndex: _index,
              actualIndex: _index,
              onTap: _onTap,
              isSearching: context.watch<SearchProvider>().isSearchActive,
            ),
          ),
        ],
      ),
    );
  }
}
