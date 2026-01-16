import 'package:flutter/material.dart';

/// Index 4 background: 빈 상태 (실제 화면은 pushReplacement로 전환)
class Index4Background extends StatelessWidget {
  const Index4Background({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(color: Colors.transparent),
    );
  }
}
