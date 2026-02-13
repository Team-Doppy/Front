import 'package:flutter/material.dart';

/// 폰트 카탈로그 항목
class FontItem {
  final String displayName;
  final String category; // 손글씨, 세리프, 산세리프, 디스플레이, 모노스페이스
  final TextStyle Function({FontWeight? fontWeight, double? fontSize})?
  googleFont;
  final String? localFontFamily;
  final bool supportsKorean;

  const FontItem({
    required this.displayName,
    required this.category,
    this.googleFont,
    this.localFontFamily,
    this.supportsKorean = false,
  });

  /// 실제 TextStyle을 반환
  TextStyle getTextStyle({
    FontWeight? fontWeight,
    double? fontSize,
    Color? color,
  }) {
    if (googleFont != null) {
      return googleFont!(
        fontWeight: fontWeight,
        fontSize: fontSize,
      ).copyWith(color: color);
    } else if (localFontFamily != null) {
      return TextStyle(
        fontFamily: localFontFamily,
        fontWeight: fontWeight,
        fontSize: fontSize,
        color: color,
      );
    }
    return TextStyle(fontWeight: fontWeight, fontSize: fontSize, color: color);
  }

  /// 저장용 식별자
  String get identifier => localFontFamily ?? displayName;
}
