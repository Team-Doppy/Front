import 'package:doppy/pages/post/home_screen.dart';
import 'package:doppy/pages/post/search_screen.dart';
import 'package:doppy/pages/post/user_profile_screen.dart';
import 'package:doppy/pages/user/login_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AuthProvider(), // ✅ 이 부분이 필수입니다!
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: MaterialApp(
        title: 'Doppy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,

        // ✅ 초기 진입: 로그인 화면
        home: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            // AuthProvider의 isLoggedIn 상태에 따라 다른 화면을 보여줌
            return auth.isLoggedIn ? HomeScreen() : LoginScreen();
          },
        ),

        routes: {
          '/login': (_) => const LoginScreen(), // ✅ 추가
          '/home': (_) => const HomeScreen(),
          '/search': (_) => const SearchScreen(),
          '/profile': (_) => const UserProfileScreen(),
          // 필요 시 확장
          // '/manage-group':    (_) => const ManageGroupScreen(),
          // '/manage-neighbor': (_) => const ManageNeighborScreen(),
          // '/group-profile':   (_) => const GroupProfileScreen(),
          // '/post-view':       (_) => const PostViewScreen(),
        },

        onUnknownRoute:
            (_) => MaterialPageRoute(builder: (_) => const HomeScreen()),
      ),
    );
  }
}
