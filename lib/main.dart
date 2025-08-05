import 'package:doppy/home_screen.dart';
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
      theme: AppTheme.lightTheme, // 라이트 테마
      darkTheme: AppTheme.darkTheme, // 다크 테마
      themeMode: ThemeMode.system, // 시스템 설정에 따라 자동 전환

      home: HomeScreen(),
    );
  }
}
