import 'package:flutter/material.dart';

class EditorConfig {
  // 동적으로 계산하는 함수로 변경
  static double getComplementOfGlobalToDocument(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final appBarHeight = AppBar().preferredSize.height;
    return statusBarHeight + appBarHeight;
  }

  static const double documentPadding = 12;
  static const double textPadding = 2;
  static const double imagePadding = 4;
}
