import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/post/home_screen.dart';
import 'package:doppy/pages/post/manage_group_screen.dart';
import 'package:doppy/pages/post/manage_neighbor_screen.dart';
import 'package:doppy/pages/post/search_screen.dart';
import 'package:doppy/pages/post/user_profile_screen.dart';

import 'package:doppy/pages/user/login_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/user_provider.dart';
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
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => SearchService()),
        ChangeNotifierProvider(create: (_) => ImageService()),
        ChangeNotifierProvider(create: (_) => StickerService()),
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
      themeMode: ThemeMode.system,

      home: FutureBuilder<bool>(
        future: AuthProvider().checkLoginStatus(), // 비동기 로그인 체크 함수
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('에러 발생!'));
          }
          if (snapshot.data == true) {
            return const HomeScreen();
          } else {
            return const LoginScreen();
          }
        },
      ),

      routes: {
        '/home': (_) => const HomeScreen(),
        '/search': (_) => const SearchScreen(),
        '/profile': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final String? username = (args is Map) ? args['username'] : null;
          return UserProfileScreen(username: username);
        },
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
