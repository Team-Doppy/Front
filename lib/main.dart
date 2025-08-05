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

//비지니스 로직은 일단 비워두고 화면 구현 우선
// provider - notifier 공부해보고 상태관리 적용하기 (중요)
// Theme 폴더에서 컬러, 텍스트 스타일 일괄 적용
