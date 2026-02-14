import 'package:doppy/app_flags.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/data/services/publish_flow_service.dart';
import 'package:doppy/editor/postwrite/postwrite_screen.dart';
import 'package:doppy/editor/service/draft_service.dart';
import 'package:doppy/editor/service/post_export_service.dart';
import 'package:doppy/onbording/onbording_screen.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/graph_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/screens/home_screen.dart';
import 'package:doppy/screens/splash_screen.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:doppy/upload/upload_init.dart';
import 'package:doppy/upload/service/upload_service.dart';
import 'package:doppy/utils/bottom_nav_bar.dart';
import 'package:doppy/widgets/home_search_field.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  final uploadService = await UploadInit.ensureInitialized(
    apiBaseUrl: BaseApiService.baseUrl,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => GraphProvider()),
        ChangeNotifierProvider<UploadService>.value(value: uploadService),
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

  final PublishFlowService _publishFlowService = PublishFlowService();

  Future<void> _onPublish(
    BuildContext navContext, {
    required String title,
    required String? thumbnailImageUrl,
    required String accessLevel,
    required String exportedJson,
    bool isEditMode = false,
    String? existingPostId,
    String? currentDraftId,
  }) async {
    final payload = PostExporter.buildPublishPayload(
      title: title,
      thumbnailImageUrl: thumbnailImageUrl,
      accessLevel: accessLevel,
      exportedJson: exportedJson,
    );
    final content = payload['content'] as Map<String, dynamic>? ?? {};
    final usedImageUrls = PostExporter.collectUsedMediaUrls(payload);
    final author =
        context.read<UserProvider>().currentUser?.username ?? 'unknown';

    await _publishFlowService.execute(
      navContext: navContext,
      hostContext: context,
      title: title,
      thumbnailImageUrl: thumbnailImageUrl,
      accessLevel: accessLevel,
      content: content,
      usedImageUrls: usedImageUrls,
      author: author,
      currentDraftId: currentDraftId,
    );
  }

  Future<void> _pushPostwriteScreen() async {
    final uploadService = context.read<UploadService>();
    final draftService = DraftService();
    final autoDraft = await draftService.getAutoDraft();
    if (!mounted) return;

    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder:
                (_, __, ___) => PostwriteScreen(
                  uploadService: uploadService,
                  networkMode: true,
                  enableAutoSave: true,
                  autoSaveInterval: const Duration(seconds: 20),
                  autoShowKeyboardOnEntry: true,
                  onPublish: _onPublish,
                  isEditMode: false,
                  draftData: autoDraft,
                ),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 200),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _index = 0);
        });
  }

  void _onTabTap(int index) {
    final graphProv = context.read<GraphProvider>();
    if (index == 2) {
      _pushPostwriteScreen();
      return;
    }
    if (index == 1) {
      graphProv.enterSearchMode();
    } else if (_index == 1 && index != 1) {
      graphProv.closeToNormal();
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: 0,
        children: [
          HomeScreen(
            viewMode: _index == 1 ? HomeViewMode.search : HomeViewMode.normal,
            onSearchClose: () => _onTabTap(0),
            onNavigateToPost: (_) => _pushPostwriteScreen(),
          ),
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
