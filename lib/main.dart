import 'package:doppy/pages/post/group_profile_screen.dart';
import 'package:doppy/pages/post/home_screen.dart';
import 'package:doppy/pages/post/manage_group_screen.dart';
import 'package:doppy/pages/post/manage_neighbor_screen.dart';
import 'package:doppy/pages/post/postview_screen.dart';
import 'package:doppy/pages/post/search_screen.dart';
import 'package:doppy/pages/post/user_profile_screen.dart';
import 'package:doppy/pages/user/login_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
      ],
      child: const MyApp(), // MyApp 위젯을 child로 감싸줍니다.
    ),
  );
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

      home: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
        },
      ),

      routes: {
          '/login': (_) => const LoginScreen(), // ✅ 추가
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
          '/group-profile': (_) => const GroupProfileScreen(),
          '/post-view': (_) => PostviewScreen(),
        },

        onUnknownRoute:
            (_) => MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
}
