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
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'theme/theme.dart';
import 'utils/route_observer.dart';

// Global NavigatorKey for accessing context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class _RootShellState extends State<RootShell> {
  late int _index;
  bool _isFirstLoad = true; // 첫 로드 여부 추적
  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();
  final ValueNotifier<bool> _isShowingSearchResults = ValueNotifier(false);
  bool _isObscuredByOverlay = false; // 검색/글쓰기 오버레이에 가려졌는지

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _isShowingSearchResults.dispose();
    super.dispose();
  }

  // 검색 화면 열기
  void _openSearchScreen([String? initialQuery]) {
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => SearchScreenOverlay(
              initialQuery: initialQuery, // 초기 검색어 전달
              onSearchComplete: (results, query) {
                // 검색 결과를 받아서 홈화면으로 전환하며 표시
                Navigator.of(context).pop(); // 검색 화면 닫기

                if (mounted) {
                  // SearchProvider에 검색 결과 저장
                  context.read<SearchProvider>().setSearchResults(
                    results,
                    query,
                  );

                  // 홈화면에 검색 결과 전달
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final homeState = _homeScreenKey.currentState;
                    if (homeState != null && homeState.mounted) {
                      homeState.setSearchResults(results, query);
                    }
                  });
                }
              },
              onClose: () {
                Navigator.of(context).pop();
              },
            ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 첫 로드 후 애니메이션 활성화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isFirstLoad) {
        setState(() {
          _isFirstLoad = false;
        });
      }
    });
  }

  void _onTap(int i) {
    final searchResultProvider = context.read<SearchProvider>();

    // 검색 오버레이가 열려있을 때 홈 버튼을 누르면 오버레이만 닫기
    if (i == 0 && searchResultProvider.isSearchOverlayVisible) {
      searchResultProvider.setSearchOverlayVisible(false);
      return;
    }

    // 홈 버튼(0번)을 눌렀을 때 검색 결과를 표시 중이라면 초기화
    if (i == 0) {
      final homeState = _homeScreenKey.currentState;
      if (homeState != null && homeState.isShowingSearchResults) {
        homeState.clearSearchAndReturnToHome();
      }
      setState(() => _index = 0);
      return;
    }

    // 검색 버튼 클릭 시: 검색 화면 열기
    if (i == 1) {
      _openSearchScreen();
      return;
    }

    if (i == 2) {
      setState(() => _isObscuredByOverlay = true);
      Navigator.of(context)
          .push(
            PageRouteBuilder(
              pageBuilder:
                  (context, animation, secondaryAnimation) =>
                      PostwriteScreen(isEditingMode: false),
              transitionDuration: Duration.zero, // 애니메이션 제거
              reverseTransitionDuration: Duration.zero, // 역방향 애니메이션도 제거
            ),
          )
          .whenComplete(() {
            if (mounted) setState(() => _isObscuredByOverlay = false);
          });
      return;
    }

    setState(() {
      _index = i;
    });

    // 홈 탭 복귀 시: 기존 상태(필터/목록/스크롤)를 유지하고 추가 서버 요청을 하지 않음

    // 다른 탭으로 이동 시 검색 오버레이 상태 해제
    if (i != 0) {
      searchResultProvider.setSearchOverlayVisible(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // HomeScreen을 현재 탭 활성 상태와 함께 구성
    final homeScreen = HomeScreen(
      preloadedHomeData: widget.preloadedHomeData,
      key: _homeScreenKey,
      searchResultsNotifier: _isShowingSearchResults,
      isActive: _index == 0 && !_isObscuredByOverlay,
      onOpenSearchScreen: (query) => _openSearchScreen(query),
    );

    return Material(
      child: Stack(
        children: [
          // 메인 화면들
          IndexedStack(
            index: _index,
            children: [
              homeScreen,
              const SizedBox.shrink(), // 검색은 별도 라우트로 push
              const SizedBox.shrink(), // 작성은 라우트로 별도 push
              const UserProfileScreen(),
            ],
          ),
          // 플로팅 바텀 네비게이션 바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isShowingSearchResults,
              builder: (context, isShowingSearchResults, child) {
                // 검색 결과를 표시 중일 때는 홈(0)에서만 검색 아이콘(1번) 활성화
                final displayIndex =
                    (_index == 0 && isShowingSearchResults) ? 1 : _index;

                return CustomBottomNavigationBar(
                  currentIndex: displayIndex,
                  actualIndex: _index, // 실제 화면 인덱스 전달
                  onTap: _onTap,
                  isSearching: context.watch<SearchProvider>().isSearchActive,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
