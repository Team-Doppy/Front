import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/screens/home_screen.dart';
import 'package:doppy/pages/screens/search_screen_overlay.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/onboarding/splash.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

import 'package:doppy/pages/user/login_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/providers/search_result_provider.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/services/account_manager_service.dart';
import 'package:flutter/material.dart';
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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ProfileFeedProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => CategoryOverlayProvider()),
        ChangeNotifierProvider(create: (_) => PostDragDropService()),
        ChangeNotifierProvider(create: (_) => SearchService()),
        ChangeNotifierProvider(create: (_) => SearchResultProvider()),
        ChangeNotifierProvider(create: (_) => NodeComponentService()),
        ChangeNotifierProvider(create: (_) => StickerService()),
        ChangeNotifierProvider(create: (_) => UploadService()),
      ],
      child: MyApp(
        hasSeenOnboarding: hasSeenOnboarding,
      ), // MyApp 위젯을 child로 감싸줍니다.
    ),
  );

  // 4. 앱 시작 시 계정 동기화 수행 (백그라운드에서)
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      print('[Main] Starting account sync on app launch...');

      // 먼저 서버에서 계정 정보를 가져와서 로컬과 동기화
      final syncSuccess = await AccountManagerService.syncWithServer();

      if (syncSuccess) {
        print('[Main] Account sync completed successfully');
      } else {
        print('[Main] Account sync failed, but app continues');
      }
    } catch (e) {
      print('[Main] Account sync error: $e');
      // 동기화 실패해도 앱은 계속 실행
    }
  });
}

class MyApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const MyApp({super.key, required this.hasSeenOnboarding});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Doppy',
      debugShowCheckedModeBanner: false,
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
        '/post-write': (_) => PostwriteScreen(screenWidth: screenWidth),
      },

      onUnknownRoute:
          (_) => MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
}

class RootShell extends StatefulWidget {
  final int initialIndex; // 0:홈,1:검색,2:작성,3:프로필
  final List<PostData>? preloadedPosts; // 스플래시 선로딩 데이터 전달용
  const RootShell({super.key, this.initialIndex = 0, this.preloadedPosts});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index;
  bool _isFirstLoad = true; // 첫 로드 여부 추적
  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();

  // 탭별 페이지를 한 번 생성해 유지 (상태 보존)
  List<Widget> _pages = const [];
  String? _pagesForUsername;

  // 계정별로 재생성되도록 페이지 빌더 사용 (캐시)
  void _ensurePagesBuilt(String? username) {
    if (_pagesForUsername == username && _pages.isNotEmpty) return;
    _pagesForUsername = username;
    _pages = [
      HomeScreen(preloadedPosts: widget.preloadedPosts, key: _homeScreenKey),
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
    Navigator.of(context).push(
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
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return child;
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  void _onTap(int i) {
    final searchResultProvider = context.read<SearchResultProvider>();

    // 검색 오버레이가 열려있을 때 홈 버튼을 누르면 오버레이만 닫기
    if (i == 0 && searchResultProvider.isSearchOverlayVisible) {
      searchResultProvider.setSearchOverlayVisible(false);
      return;
    }

    // 검색 버튼 클릭 시: 현재 화면에서 바로 SearchOverlay 열기
    if (i == 1) {
      print('[RootShell] 검색 버튼 클릭됨');
      // 탭 전환 없이 바로 검색 화면 열기 (현재 화면 위에서)
      _openSearchScreen();
      return;
    }

    if (i == 2) {
      final screenWidth = MediaQuery.of(context).size.width;
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  PostwriteScreen(screenWidth: screenWidth),
          transitionDuration: Duration.zero, // 애니메이션 제거
          reverseTransitionDuration: Duration.zero, // 역방향 애니메이션도 제거
        ),
      );
      return;
    }
    final wasIndex = _index;
    setState(() => _index = i);

    // 홈 탭 복귀 시: 기존 상태(필터/목록/스크롤)를 유지하고 추가 서버 요청을 하지 않음

    // 다른 탭으로 이동 시 검색 오버레이 상태 해제
    if (i != 0) {
      searchResultProvider.setSearchOverlayVisible(false);
    }

    // 프로필 탭 전환 시: 첫 진입이거나 명시적 새로고침 상황에서만 강제 로드
    if (i == 3 && wasIndex != 3) {
      context.read<ProfileFeedProvider>().loadInitial(
        username: null,
        force: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _ensurePagesBuilt(auth.username);

    return Material(
      child: Stack(
        children: [
          // 상태 보존을 위해 IndexedStack 사용
          IndexedStack(index: _index, children: _pages),
          // 플로팅 바텀 네비게이션 바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Consumer<SearchResultProvider>(
              builder:
                  (context, searchResultProvider, _) =>
                      CustomBottomNavigationBar(
                        currentIndex: _index,
                        onTap: _onTap,
                        isSearching: searchResultProvider.isSearchActive,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
