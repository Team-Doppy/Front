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

// Global NavigatorKey for accessing context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🎯 FCM Background 메시지 핸들러 (top-level 함수로 선언)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase 초기화 필요 (background isolate에서는 별도로 초기화해야 함)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('[FCM] 백그라운드 메시지 수신: ${message.messageId}');
  print('[FCM] 데이터: ${message.data}');
  print(
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
    print('[Firebase] 플랫폼: ${defaultTargetPlatform}');

    await Firebase.initializeApp(options: options);

    // 🎯 FCM 백그라운드 메시지 핸들러 등록 (Firebase 초기화 후)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print('[FCM] 백그라운드 메시지 핸들러 등록 완료');

    // 🎯 FCM 포그라운드 메시지 핸들러 등록
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('[FCM] 포그라운드 메시지 수신: ${message.messageId}');
      print('[FCM] 데이터: ${message.data}');
      print(
        '[FCM] 알림: ${message.notification?.title} - ${message.notification?.body}',
      );
      // 포그라운드에서는 알림을 표시하지 않음
    });

    // 🎯 FCM 메시지 클릭 핸들러 등록
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('[FCM] 알림 클릭으로 앱 열림: ${message.messageId}');
      print('[FCM] 데이터: ${message.data}');
      // 필요한 경우 특정 화면으로 네비게이션
    });

    // 🎯 앱이 종료된 상태에서 알림 클릭으로 열린 경우 확인
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('[FCM] 종료된 앱에서 알림 클릭으로 열림: ${initialMessage.messageId}');
      print('[FCM] 데이터: ${initialMessage.data}');
    }

    print('[FCM] 포그라운드/백그라운드 메시지 핸들러 등록 완료');
  } catch (e) {
    print('[Firebase] 초기화 실패: $e');
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

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    // 라이프사이클 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 라이프사이클 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
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

  /// 포그라운드 전환 시 FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
  void _checkAndSyncFcmTokenOnForeground() {
    // 로그인 상태 확인 후 FCM 토큰 검사
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isLoggedIn) {
      try {
        final authService = AuthService();
        // FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
        // 비동기로 처리하여 UI를 막지 않음
        authService.syncFcmTokenAndSettings().catchError((e) {
          print('[RootShell] 포그라운드 전환 시 FCM 토큰 검사 및 동기화 실패 (무시): $e');
        });
      } catch (e) {
        print('[RootShell] 포그라운드 전환 시 FCM 토큰 검사 오류 (무시): $e');
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
