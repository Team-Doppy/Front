import 'package:doppy/onbording/onbording_screen.dart';
import 'package:doppy/provider/theme_provider.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/graph_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/screens/home_screen.dart';
import 'package:doppy/screens/splash_screen.dart';
import 'package:doppy/screens/write_screen.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:doppy/utils/bottom_nav_bar.dart';
import 'package:doppy/widgets/home_search_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// 앱 버전 및 상수
class AppConstants {
  static const String appVersion = '2.0';
  static const String webDomain = 'www.doppy.app';
  static const String webBaseUrl = 'https://www.doppy.app';
  static const String termsOfServiceUrl =
      'https://www.notion.so/doppy-2a594e338df780e1b6b9fddb9753e728';
  static const String contactEmail = 'app.doppy@gmail.com';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
  } catch (e) {
    debugPrint('[Firebase] 초기화 실패: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => GraphProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doppy',
      home: const AuthWrapper(),
      routes: {'/login': (_) => const LoginScreen()},
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      themeMode: context.watch<ThemeProvider>().themeMode,
    );
  }
}

/// JWT 기반 로그인 판단: 토큰 유효 시 SplashScreen, 없으면 LoginScreen
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isChecking = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final isLoggedIn = await AuthProvider().checkLoginStatus();
    if (!mounted) return;

    // 토큰이 있으면 유효성 검사
    if (isLoggedIn) {
      final valid = await AuthProvider().validateAndRefreshToken();
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isLoggedIn = valid;
      });
    } else {
      setState(() {
        _isChecking = false;
        _isLoggedIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isLoggedIn) {
      return const SplashScreen();
    }

    return const LoginScreen();
  }
}

class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key});

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  int _index = 0;

  void _onTabTap(int index) {
    final graphProv = context.read<GraphProvider>();
    if (index == 1) {
      graphProv.enterSearchMode();
    } else if (_index == 1 && index != 1) {
      graphProv.closeToNormal();
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    // 0=Home, 1=Search(홈 검색모드), 2=Write, 3=Profile
    final pageIndex = _index <= 1 ? 0 : _index - 1;

    return Scaffold(
      body: IndexedStack(
        index: pageIndex,
        children: [
          HomeScreen(
            viewMode: _index == 1 ? HomeViewMode.search : HomeViewMode.normal,
            onSearchClose: () => _onTabTap(0),
            onNavigateToPost: (nodeId) => setState(() => _index = 2),
          ),
          const WriteScreen(),
        ],
      ),
      bottomNavigationBar: Consumer<UserProvider>(
        builder:
            (_, userProv, __) => BottomNavBar(
              currentIndex: _index,
              onTap: _onTabTap,
              profileUsername: userProv.currentUser?.username ?? 'me',
              profileImageUrl: userProv.currentUser?.profileImageUrl,
            ),
      ),
    );
  }
}
