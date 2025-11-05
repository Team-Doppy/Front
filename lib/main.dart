import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/screens/search_screen.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/screens/home_screen.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/onboarding/splash.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

import 'package:doppy/pages/onboarding/onboarding_screen.dart';
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

  // 탭별 페이지를 한 번 생성해 유지 (상태 보존)
  List<Widget> _pages = const [];
  String? _pagesForUsername;

  // 계정별로 재생성되도록 페이지 빌더 사용 (캐시)
  void _ensurePagesBuilt(String? username) {
    if (_pagesForUsername == username && _pages.isNotEmpty) return;
    _pagesForUsername = username;
    _pages = [
      // HomeScreen은 탭 활성 상태를 build 시점에 주입하기 위해 build에서 다시 구성
      const SizedBox.shrink(),
      const SizedBox.shrink(),
      const SizedBox.shrink(), // 작성은 라우트로 별도 push
      UserProfileScreen(key: ValueKey('profile_$username')),
    ];
  }

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

  // 검색 화면 열기 (현재 화면에서 바로)
  void _openSearchScreen({String? initialQuery}) {
    setState(() => _isObscuredByOverlay = true);
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, animation, secondaryAnimation) {
              return FadeTransition(
                opacity: animation,
                child: SearchScreenOverlay(
                  initialQuery: initialQuery,
                  onSearchComplete: (results, query) {
                    // 검색 결과를 받아서 홈화면으로 전환하며 표시
                    Navigator.of(context).pop(); // 검색 화면 닫기

                    // 홈 탭으로 전환 후 검색 결과 설정
                    if (mounted) {
                      setState(() => _index = 0);

                      // 홈화면이 빌드된 후 검색 결과 전달
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
              );
            },
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return child;
            },
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
          ),
        )
        .whenComplete(() {
          if (mounted) setState(() => _isObscuredByOverlay = false);
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

    // 검색 버튼 클릭 시: 현재 화면에서 바로 SearchOverlay 열기
    if (i == 1) {
      // 탭 전환 없이 바로 검색 화면 열기 (현재 화면 위에서)
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
    final auth = context.watch<AuthProvider>();
    _ensurePagesBuilt(auth.username);

    // HomeScreen을 현재 탭 활성 상태와 함께 구성 (리스너 없이 단순 전달)
    final homeScreen = HomeScreen(
      preloadedHomeData: widget.preloadedHomeData,
      key: _homeScreenKey,
      searchResultsNotifier: _isShowingSearchResults,
      isActive: _index == 0 && !_isObscuredByOverlay,
    );

    return Material(
      child: Stack(
        children: [
          // 상태 보존을 위해 IndexedStack 사용
          IndexedStack(
            index: _index,
            children: [homeScreen, _pages[1], _pages[2], _pages[3]],
          ),
          // 플로팅 바텀 네비게이션 바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isShowingSearchResults,
              builder: (context, isShowingSearchResults, child) {
                // 검색 결과를 표시 중일 때는 검색 아이콘(1번)을 활성화
                final displayIndex =
                    (_index == 0 && isShowingSearchResults) ? 1 : _index;

                return CustomBottomNavigationBar(
                  currentIndex: displayIndex,
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
