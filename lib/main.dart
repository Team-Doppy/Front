import 'package:doppy/pages/post/group_profile_screen.dart';
import 'package:doppy/pages/post/home_screen.dart';
import 'package:doppy/pages/post/search_screen.dart';
import 'package:doppy/pages/post/manage_group_screen.dart';
import 'package:doppy/pages/post/manage_neighbor_screen.dart';
import 'package:doppy/pages/post/postview_screen.dart';
import 'package:doppy/pages/post/user_profile_screen.dart';
import 'package:doppy/pages/user/login_screen.dart';
import 'package:flutter/material.dart';
import 'theme/theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doppy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // ✅ 초기 진입: 로그인
      initialRoute: '/login',

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
    );
  }
}
