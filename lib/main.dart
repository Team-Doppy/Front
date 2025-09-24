import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/screens/home_screen.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/onboarding/splash.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
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
      title: 'Doppy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: context.watch<ThemeProvider>().themeMode,
      home: const SplashScreen(),
      routes: {
        '/home': (_) => const RootShell(initialIndex: 0),
        '/login': (_) => const LoginScreen(),
        '/search': (_) => const RootShell(initialIndex: 1),
        '/profile': (context) => const RootShell(initialIndex: 3),
        // 필요 시 확장
        '/manage-group': (_) => const ManageGroupScreen(),
        '/manage-neighbor': (_) => const ManageNeighborScreen(),
        '/post-write': (_) => PostwriteScreen(screenWidth: screenWidth),
      },

      onUnknownRoute:
          (_) => MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
}

class RootShell extends StatefulWidget {
  final int initialIndex; // 0:홈,1:검색,2:작성,3:프로필
  const RootShell({super.key, this.initialIndex = 0});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index;

  // 각 탭의 페이지 유지용
  final _pages = const [
    HomeScreen(),
    SearchScreen(),
    SizedBox.shrink(), // 작성은 라우트로 별도 push
    UserProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  void _onTap(int i) {
    if (i == 2) {
      final screenWidth = MediaQuery.of(context).size.width;
      Navigator.of(context).pushNamed('/post-write', arguments: screenWidth);
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(child: IndexedStack(index: _index, children: _pages)),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
      ),
    );
  }
}
