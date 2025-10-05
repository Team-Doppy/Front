import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/screens/home_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/onboarding/splash.dart';
import 'package:doppy/pages/screens/manage_neighbor_screen.dart';
import 'package:doppy/pages/screens/search_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

import 'package:doppy/pages/user/login_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/data/services/search_service.dart';
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
        ChangeNotifierProvider(create: (_) => ImageService()),
        ChangeNotifierProvider(create: (_) => StickerService()),
        ChangeNotifierProvider(create: (_) => UploadService()),
      ],
      child: MyApp(
        hasSeenOnboarding: hasSeenOnboarding,
      ), // MyApp 위젯을 child로 감싸줍니다.
    ),
  );
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
        // 필요 시 확장
        '/manage-group': (_) => const ManageNeighborScreen(initialTabIndex: 1),
        '/manage-neighbor':
            (_) => const ManageNeighborScreen(initialTabIndex: 0),
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

  // 계정별로 재생성되도록 페이지 빌더 사용
  List<Widget> _buildPages(String? username) => [
    HomeScreen(
      key: ValueKey('home_$username'),
      preloadedPosts: widget.preloadedPosts,
    ),
    SearchScreen(key: ValueKey('search_$username')),
    const SizedBox.shrink(), // 작성은 라우트로 별도 push
    UserProfileScreen(key: ValueKey('profile_$username')),
  ];

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

  void _onTap(int i) {
    if (i == 2) {
      final screenWidth = MediaQuery.of(context).size.width;
      Navigator.of(context).pushNamed('/post-write', arguments: screenWidth);
      return;
    }
    final wasIndex = _index;
    setState(() => _index = i);
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
    final pages = _buildPages(auth.username);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          // SlideTransition 제거하고 FadeTransition만 사용하여 버벅임 방지
          return FadeTransition(opacity: animation, child: child);
        },
        child: KeyedSubtree(
          key: ValueKey('page_${auth.username}_$_index'),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
      ),
      // 플로팅 바텀 내비게이션바
    );
  }
}
