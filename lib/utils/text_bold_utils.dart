import 'package:doppy/pages/components/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 로케일 기반 텍스트 볼드 적용 유틸리티
///
/// 텍스트를 로케일에 따라 파싱하여 특정 부분을 볼드로 만드는 헬퍼 함수들
class TextBoldUtils {
  TextBoldUtils._();

  /// 로케일에 따라 텍스트를 파싱하여 HomeTextChunk 리스트로 변환
  ///
  /// [text] - 원본 텍스트
  /// [context] - BuildContext (로케일 정보 가져오기용)
  /// [boldPattern] - 볼드로 만들 패턴 (정규식 또는 문자열, 선택)
  ///   - null이면 로케일 기본 규칙 적용
  ///   - 한국어: 마지막 단어/구를 볼드
  ///   - 영어: 마지막 단어/구를 볼드
  ///
  /// 예시:
  /// - 한국어: "안 남기면 없어지는 순간, 지금 기록하기" → "지금 기록하기" 볼드
  /// - 영어: "Moments fade away, Record now" → "Record now" 볼드
  static List<HomeTextChunk> parseWithBold({
    required String text,
    required BuildContext context,
    String? boldPattern,
  }) {
    final locale = Localizations.localeOf(context);
    final isKorean = locale.languageCode == 'ko';

    // boldPattern이 제공되면 그것을 사용
    if (boldPattern != null) {
      return _parseWithPattern(text, boldPattern);
    }

    // 로케일 기본 규칙 적용
    if (isKorean) {
      return _parseKoreanBold(text);
    } else {
      return _parseEnglishBold(text);
    }
  }

  /// 한국어 텍스트 파싱 (쉼표 뒤 마지막 부분을 볼드)
  static List<HomeTextChunk> _parseKoreanBold(String text) {
    // 쉼표로 분리
    final parts = text.split(',');
    if (parts.length < 2) {
      // 쉼표가 없으면 전체를 일반 텍스트로
      return [HomeTextChunk(text)];
    }

    // 마지막 부분을 제외한 앞부분
    final beforeLast = parts.sublist(0, parts.length - 1).join(',');
    // 마지막 부분 (앞뒤 공백 제거)
    final lastPart = parts.last.trim();

    if (beforeLast.isEmpty && lastPart.isEmpty) {
      return [HomeTextChunk(text)];
    }

    return [
      if (beforeLast.isNotEmpty) HomeTextChunk('$beforeLast, '),
      if (lastPart.isNotEmpty) HomeTextChunk(lastPart, bold: true),
    ];
  }

  /// 영어 텍스트 파싱 (쉼표 뒤 마지막 부분을 볼드)
  static List<HomeTextChunk> _parseEnglishBold(String text) {
    // 쉼표로 분리
    final parts = text.split(',');
    if (parts.length < 2) {
      // 쉼표가 없으면 전체를 일반 텍스트로
      return [HomeTextChunk(text)];
    }

    // 마지막 부분을 제외한 앞부분
    final beforeLast = parts.sublist(0, parts.length - 1).join(',');
    // 마지막 부분 (앞뒤 공백 제거)
    final lastPart = parts.last.trim();

    if (beforeLast.isEmpty && lastPart.isEmpty) {
      return [HomeTextChunk(text)];
    }

    return [
      if (beforeLast.isNotEmpty) HomeTextChunk('$beforeLast, '),
      if (lastPart.isNotEmpty) HomeTextChunk(lastPart, bold: true),
    ];
  }

  /// 패턴 기반 파싱 (정규식 또는 문자열)
  static List<HomeTextChunk> _parseWithPattern(String text, String pattern) {
    try {
      // 정규식으로 시도
      final regex = RegExp(pattern);
      final matches = regex.allMatches(text);

      if (matches.isEmpty) {
        // 매칭 실패 시 전체를 일반 텍스트로
        return [HomeTextChunk(text)];
      }

      final chunks = <HomeTextChunk>[];
      int lastEnd = 0;

      for (final match in matches) {
        // 매칭 전 부분
        if (match.start > lastEnd) {
          chunks.add(HomeTextChunk(text.substring(lastEnd, match.start)));
        }
        // 매칭된 부분 (볼드)
        chunks.add(HomeTextChunk(match.group(0) ?? '', bold: true));
        lastEnd = match.end;
      }

      // 남은 부분
      if (lastEnd < text.length) {
        chunks.add(HomeTextChunk(text.substring(lastEnd)));
      }

      return chunks;
    } catch (e) {
      // 정규식 파싱 실패 시 문자열 매칭으로 시도
      final index = text.indexOf(pattern);
      if (index == -1) {
        return [HomeTextChunk(text)];
      }

      return [
        if (index > 0) HomeTextChunk(text.substring(0, index)),
        HomeTextChunk(pattern, bold: true),
        if (index + pattern.length < text.length)
          HomeTextChunk(text.substring(index + pattern.length)),
      ];
    }
  }

  /// 특정 키워드들을 볼드로 만들기
  ///
  /// [text] - 원본 텍스트
  /// [keywords] - 볼드로 만들 키워드 리스트
  /// [caseSensitive] - 대소문자 구분 여부
  static List<HomeTextChunk> parseWithKeywords({
    required String text,
    required List<String> keywords,
    bool caseSensitive = false,
  }) {
    if (keywords.isEmpty) {
      return [HomeTextChunk(text)];
    }

    final chunks = <HomeTextChunk>[];
    int lastEnd = 0;

    // 모든 키워드의 위치 찾기
    final matches = <_MatchInfo>[];
    for (final keyword in keywords) {
      final searchText = caseSensitive ? text : text.toLowerCase();
      final searchKeyword = caseSensitive ? keyword : keyword.toLowerCase();
      int index = 0;

      while ((index = searchText.indexOf(searchKeyword, index)) != -1) {
        matches.add(_MatchInfo(index, index + keyword.length, keyword));
        index += keyword.length;
      }
    }

    // 위치 순으로 정렬
    matches.sort((a, b) => a.start.compareTo(b.start));

    // 겹치는 매칭 제거 (먼저 나온 것 우선)
    final nonOverlapping = <_MatchInfo>[];
    for (final match in matches) {
      if (nonOverlapping.isEmpty || match.start >= nonOverlapping.last.end) {
        nonOverlapping.add(match);
      }
    }

    // 청크 생성
    for (final match in nonOverlapping) {
      // 매칭 전 부분
      if (match.start > lastEnd) {
        chunks.add(HomeTextChunk(text.substring(lastEnd, match.start)));
      }
      // 매칭된 부분 (볼드)
      chunks.add(HomeTextChunk(match.keyword, bold: true));
      lastEnd = match.end;
    }

    // 남은 부분
    if (lastEnd < text.length) {
      chunks.add(HomeTextChunk(text.substring(lastEnd)));
    }

    return chunks.isEmpty ? [HomeTextChunk(text)] : chunks;
  }
}

/// 매칭 정보를 담는 내부 클래스
class _MatchInfo {
  final int start;
  final int end;
  final String keyword;

  _MatchInfo(this.start, this.end, this.keyword);
}

/// 로케일 기반 폰트 스타일 유틸리티
///
/// 홈 위젯과 독립적으로 사용 가능한 범용 폰트 스타일 헬퍼
class LocaleTypography {
  LocaleTypography._();

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
  ///   style: LocaleTypography.style(
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
  static TextStyle boldStyle({
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
