import 'package:flutter/material.dart';

/// 이미지 위에 올라가는 텍스트 오버레이 데이터
class TextOverlayData {
  final String id;
  final String text;
  final Offset position; // 0~1 비율 기준
  final double fontSize;
  final Color textColor;
  final Color? backgroundColor;
  final TextAlign textAlign;
  final FontWeight fontWeight;
  final String? fontIdentifier; // FontCatalog identifier (google/local)

  const TextOverlayData({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 32,
    this.textColor = Colors.white,
    this.backgroundColor,
    this.textAlign = TextAlign.center,
    this.fontWeight = FontWeight.bold,
    this.fontIdentifier,
  });

  TextOverlayData copyWith({
    String? id,
    String? text,
    Offset? position,
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    TextAlign? textAlign,
    FontWeight? fontWeight,
    String? fontIdentifier,
  }) {
    return TextOverlayData(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textAlign: textAlign ?? this.textAlign,
      fontWeight: fontWeight ?? this.fontWeight,
      fontIdentifier: fontIdentifier ?? this.fontIdentifier,
    );
  }
}
