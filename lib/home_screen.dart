import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Home')));
  }
}

//비지니스 로직은 일단 비워두고 화면 구현 우선
// provider - notifier 공부해보고 상태관리 적용하기 (중요)
// Theme 폴더에서 컬러, 텍스트 스타일 일괄 적용
