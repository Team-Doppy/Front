import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 홈 위젯과 독립적으로 사용 가능한 범용 폰트 스타일 헬퍼
class TypographyUtil {
  TypographyUtil._();

  /// 로케일에 따라 자동으로 NotoSans 폰트를 적용한 TextStyle 반환
  ///
  /// - 한국어(ko): `GoogleFonts.notoSansKr` 사용
  /// - 영어(en): `GoogleFonts.notoSans` 사용
  /// - 기타: `GoogleFonts.notoSans` 사용 (영문 폴백)
  ///
  /// [context] - BuildContext (로케일 정보 가져오기용)
  /// [fontSize] - 폰트 사이즈 (필수)
  /// [color] - 텍스트 색상
  /// [fontWeight] - 폰트 굵기 (기본값: FontWeight.w400)
  /// [letterSpacing] - 자간 (기본값: -1.0)
  /// [height] - 줄 간격 (기본값: 1.25)
  /// [shadows] - 텍스트 그림자
  ///
  /// 예시:
  /// ```dart
  /// Text(
  ///   'Hello World',
  ///   style: TypographyUtil.style(
  ///     context: context,
  ///     fontSize: 32,
  ///     color: Colors.white,
  ///     fontWeight: FontWeight.w900,
  ///   ),
  /// )
  /// ```
  static TextStyle style({
    required BuildContext context,
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) {
    final locale = Localizations.localeOf(context);
    final isKorean = locale.languageCode == 'ko';

    // 한국어면 notoSansKr, 아니면 notoSans
    final baseStyle =
        isKorean
            ? GoogleFonts.notoSansKr(
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing ?? -1.0,
              height: height ?? 1.25,
              color: color,
              shadows: shadows,
            )
            : GoogleFonts.notoSans(
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing ?? -1.0,
              height: height ?? 1.25,
              color: color,
              shadows: shadows,
            );

    // 폰트 폴백 추가 (일관성 보장)
    return baseStyle.copyWith(
      fontFamilyFallback:
          isKorean
              ? const ['Noto Sans KR', 'Noto Sans']
              : const ['Noto Sans', 'Noto Sans KR'],
    );
  }

  /// 볼드 스타일 (NotoSans 강제)
  ///
  /// 볼드 텍스트는 항상 NotoSans 계열을 사용하여 일관성 보장
  static TextStyle setStyle({
    required BuildContext context,
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) {
    // 볼드는 항상 notoSansKr 사용 (한국어든 영어든)
    final baseStyle = GoogleFonts.notoSansKr(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing ?? -1.2,
      height: height ?? 1.25,
      color: color,
      shadows: shadows,
    );

    // 폰트 폴백 추가
    return baseStyle.copyWith(
      fontFamilyFallback: const ['Noto Sans', 'Noto Sans KR'],
    );
  }

  /// Locale 객체를 직접 받아서 사용 (context 없이)
  ///
  /// [locale] - Locale 객체
  /// [fontSize] - 폰트 사이즈 (필수)
  /// [color] - 텍스트 색상
  /// [fontWeight] - 폰트 굵기 (기본값: FontWeight.w400)
  /// [letterSpacing] - 자간 (기본값: -1.0)
  /// [height] - 줄 간격 (기본값: 1.25)
  /// [shadows] - 텍스트 그림자
  static TextStyle styleWithLocale({
    required Locale locale,
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) {
    final isKorean = locale.languageCode == 'ko';

    final baseStyle =
        isKorean
            ? GoogleFonts.notoSansKr(
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing ?? -1.0,
              height: height ?? 1.25,
              color: color,
              shadows: shadows,
            )
            : GoogleFonts.notoSans(
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing ?? -1.0,
              height: height ?? 1.25,
              color: color,
              shadows: shadows,
            );

    return baseStyle.copyWith(
      fontFamilyFallback:
          isKorean
              ? const ['Noto Sans KR', 'Noto Sans']
              : const ['Noto Sans', 'Noto Sans KR'],
    );
  }
}
