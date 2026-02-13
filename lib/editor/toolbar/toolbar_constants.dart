import 'package:flutter/material.dart';
import '../style/text_attributions.dart';

/// 툴바에서 사용하는 색상 팔레트
class ToolbarColorPalette {
  ToolbarColorPalette._();

  /// 텍스트 색상 팔레트
  static const List<Color> textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFE53935), // Red
    Color(0xFFD81B60), // Pink
    Color(0xFF8E24AA), // Purple
    Color(0xFF5E35B1), // Deep Purple
    Color(0xFF3949AB), // Indigo
    Color(0xFF1E88E5), // Blue
    Color(0xFF039BE5), // Light Blue
    Color(0xFF00ACC1), // Cyan
    Color(0xFF00897B), // Teal
    Color(0xFF43A047), // Green
    Color(0xFF7CB342), // Light Green
    Color(0xFFC0CA33), // Lime
    Color(0xFFFDD835), // Yellow
    Color(0xFFFFB300), // Amber
    Color(0xFFF57C00), // Orange
    Color(0xFF6D4C41), // Brown
    Color(0xFF9E9E9E), // Grey
    Color(0xFF607D8B), // Blue Grey
  ];

  /// 형광펜 색상 목록
  static const List<Color> highlightColors = [
    highlightYellow,
    highlightGreen,
    highlightBlue,
    highlightPink,
    highlightOrange,
    highlightPurple,
  ];
}

/// 폰트 사이즈 옵션
class ToolbarFontSizes {
  ToolbarFontSizes._();

  static const List<double> sizes = [
    11,
    13,
    16,
    19,
    22,
    25,
    28,
    31,
    34,
    37,
    40,
    43,
    46,
    49,
    52,
    55,
    58,
    61,
    64,
  ];
}
