import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/style/text_attributions.dart';
import 'package:doppy/editor/style/text_styling_service.dart'
    show TextStylingService;
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_editor/super_editor.dart';

// 전역 폰트 접근용
TextStylingService? _globalTextStylingService;

void setGlobalTextStylingService(TextStylingService? service) {
  _globalTextStylingService = service;
}

/// 커스텀 스타일시트 (테마에 따라 텍스트/타이틀 색을 적용)
/// [isReadOnly] true인 경우 전역 폰트를 사용하지 않고 블록의 metadata만 사용
Stylesheet buildCustomStylesheet(
  BuildContext context, {
  bool isReadOnly = false,
}) {
  // 🎯 성능 최적화: watch 대신 read 사용 (테마는 initState에서 감지)
  final bool isDark = context.read<ThemeProvider>().themeMode == ThemeMode.dark;
  final Color bodyColor =
      isDark
          ? const Color.fromARGB(230, 255, 255, 255)
          : AppColors.lightTextPrimary;

  return defaultStylesheet.copyWith(
    documentPadding: EdgeInsets.all(EditorConfig.documentPadding),
    addRulesAfter: [
      // 텍스트 노드 스타일
      StyleRule(BlockSelector.all, (doc, docNode) {
        if (docNode is ParagraphNode) {
          // 멘션 노드는 "일반 텍스트와 동일"하게 렌더링하고, 차이는 bold만 추가한다.
          // (폰트/사이즈/패딩은 본문과 동일하게 유지)
          final isMention = docNode.metadata['mention'] == true;

          // 메타데이터에서 폰트 정보 읽기
          final fontFamily = docNode.metadata['fontFamily'] as String?;
          TextStyle bodyStyle = TextStyle(
            fontSize: 16,
            color: bodyColor,
            height: EditorConfig.defaultLineHeight,
            leadingDistribution: TextLeadingDistribution.even,
          );

          // 🎯 구글 폰트 적용 (메타데이터 기반)
          // 폰트가 이미 로드되었는지 확인하고, 로드되지 않았으면 기본 폰트 사용
          if (fontFamily != null && fontFamily.isNotEmpty) {
            try {
              bodyStyle = GoogleFonts.getFont(fontFamily, textStyle: bodyStyle);
            } catch (e) {
              // 폰트 로드 실패 시 기본 폰트 사용 (UI 블로킹 방지)
              bodyStyle = bodyStyle.copyWith(fontFamily: fontFamily);
            }
          }

          return {
            Styles.textStyle:
                isMention
                    ? bodyStyle.copyWith(fontWeight: FontWeight.bold)
                    : bodyStyle,
            Styles.padding: CascadingPadding.only(
              top: 0,
              bottom: 0,
              left: 20,
              right: 20,
            ),
          };
        }
        if (docNode is ClipNode) {
          // 메타데이터에서 패딩 모드 확인 (기본값: 'center' = 패딩 있음)
          final paddingMode =
              docNode.metadata['padding'] as String? ?? 'center';

          // 'full' 모드면 좌우 패딩 없음, 'center' 모드면 기본 패딩
          final horizontalPadding = paddingMode == 'full' ? 0.0 : 20.0;

          debugPrint(
            '[StyleSheet] ClipNode 패딩 적용: nodeId=${docNode.id}, paddingMode=$paddingMode, horizontalPadding=$horizontalPadding',
          );

          return {
            Styles.padding: CascadingPadding.only(
              top: EditorConfig.imagePadding,
              bottom: EditorConfig.imagePadding,
              left: horizontalPadding,
              right: horizontalPadding,
            ),
          };
        } else if (docNode is ImageNode) {
          // 메타데이터에서 패딩 모드 확인
          final paddingMode =
              docNode.metadata['padding'] as String? ?? 'center';

          // 'full' 모드면 좌우 패딩 없음, 'center' 모드면 기본 패딩
          final horizontalPadding = paddingMode == 'full' ? 0.0 : 20.0;

          return {
            Styles.padding: CascadingPadding.only(
              top: EditorConfig.imagePadding,
              bottom: EditorConfig.imagePadding,
              left: horizontalPadding,
              right: horizontalPadding,
            ),
          };
        } else if (docNode is ImageRowNode) {
          return {
            Styles.padding: CascadingPadding.only(
              top: EditorConfig.imagePadding,
              bottom: EditorConfig.imagePadding,
              left: 0,
              right: 0,
            ),
          };
        } else if (docNode is LinkNode) {
          // 메타데이터에서 패딩 모드 확인 (기본값: 'center' = 패딩 있음)
          final paddingMode =
              docNode.metadata['padding'] as String? ?? 'center';
          final horizontalPadding = paddingMode == 'full' ? 0.0 : 20.0;
          return {
            Styles.padding: CascadingPadding.only(
              top: EditorConfig.imagePadding,
              bottom: EditorConfig.imagePadding,
              left: horizontalPadding,
              right: horizontalPadding,
            ),
          };
        }

        return {};
      }),
    ],
    inlineTextStyler: (attributions, existingStyle) {
      TextStyle style = existingStyle;
      bool isBold = false;
      bool isItalic = false;
      bool hasUnderline = false;
      bool hasStrikethrough = false;
      // 형광펜은 별도 오버레이로 렌더링하므로 스타일에서 사용하지 않음
      bool isSpoiler = false;
      String? fontFamily;

      // 🎯 existingStyle에서 폰트 패밀리 추출 (StyleRule에서 metadata 기반으로 설정된 폰트)
      String? existingFontFamily = existingStyle.fontFamily;

      for (final attribution in attributions) {
        if (attribution == boldAttribution) {
          isBold = true;
        } else if (attribution == italicsAttribution) {
          isItalic = true;
        } else if (attribution == underlineAttribution) {
          hasUnderline = true;
        } else if (attribution == strikethroughAttribution) {
          hasStrikethrough = true;
        } else if (attribution is HighlightAttribution) {
          // no-op: overlay painter handles highlight visuals
        } else if (attribution is NamedAttribution &&
            attribution.id == 'spoiler') {
          isSpoiler = true;
        } else if (attribution is ColorAttribution &&
            attribution is! HighlightAttribution) {
          // ✅ 글자색 (형광펜은 제외!)
          style = style.copyWith(color: attribution.color);
        } else if (attribution is FontSizeAttribution) {
          style = style.copyWith(
            fontSize: attribution.fontSize,
            // 🎯 폰트 크기를 줄이면 행간도 자연스럽게 같이 줄어들어야 함
            // (노드 간 간격/선택 박스 간격이 폰트 크기 변화에 반응)
            height: EditorConfig.defaultLineHeight,
            leadingDistribution: TextLeadingDistribution.even,
          );
        } else if (attribution is FontFamilyAttribution) {
          // 🎯 span 단위 폰트 (Attribution 기반 정교한 적용) - 최우선 적용
          fontFamily = attribution.fontFamily;
        }
      }

      style = style.copyWith(
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _buildTextDecoration(hasUnderline, hasStrikethrough),
        // height는 위에서 attribution/블록 스타일에서 일관되게 지정한다.
        leadingDistribution: TextLeadingDistribution.even,
        // 형광펜은 별도 오버레이로 렌더링하므로 배경색은 사용하지 않음
      );

      // 🙈 스포일러 스타일: 텍스트 색상은 유지, 마스크로만 가림
      if (isSpoiler) {
        // 스포일러 텍스트도 색상 유지
        // paragraph_component의 마스크가 시각적으로 가림
        style = style.copyWith(decoration: TextDecoration.none);
        // ColorAttribution이 없으면 기본 bodyColor 유지
      }

      // 🎨 폰트 패밀리 적용 우선순위:
      // 1. FontFamilyAttribution (span 단위 정교한 적용) - 최우선 ✅
      // 2. existingStyle의 fontFamily (StyleRule에서 metadata 기반으로 설정된 폰트) - 차순위
      // 3. 전역 폰트 (에디터 모드일 때만, Attribution과 metadata가 없을 때) - 마지막
      if (fontFamily == null || fontFamily.isEmpty) {
        // Attribution이 없으면 existingStyle의 폰트 사용 (StyleRule에서 metadata 기반으로 설정)
        if (existingFontFamily != null && existingFontFamily.isNotEmpty) {
          fontFamily = existingFontFamily;
        } else if (!isReadOnly) {
          // 에디터 모드일 때만 전역 폰트 사용 (Attribution과 metadata가 모두 없을 때만)
          fontFamily = _globalTextStylingService?.globalFontFamily;
        }
        // 읽기 모드에서는 전역 폰트를 사용하지 않음 (블록 metadata만 적용)
      }

      // 🎯 폰트 적용 (우선순위: Attribution > metadata > 전역 폰트)
      // 폰트가 이미 로드되었는지 확인하고, 로드되지 않았으면 기본 폰트 사용
      if (fontFamily != null && fontFamily.isNotEmpty) {
        try {
          // GoogleFonts.getFont는 비동기적으로 폰트를 로드하지만,
          // 폰트가 아직 로드되지 않았을 때는 기본 폰트를 사용하여 UI 블로킹 방지
          style = GoogleFonts.getFont(fontFamily, textStyle: style);
        } catch (e) {
          // 폰트 로드 실패 시 기본 폰트 사용 (UI 블로킹 방지)
          style = style.copyWith(fontFamily: fontFamily);
        }
      }
      // 본문 기본 색을 테마에 맞춰 적용 (인라인 컬러 지정이 없는 경우)
      if (style.color == null) {
        style = style.copyWith(color: bodyColor);
      }
      return style;
    },
  );
}

/// 텍스트 장식 빌드 (밑줄, 취소선)
TextDecoration _buildTextDecoration(bool hasUnderline, bool hasStrikethrough) {
  if (hasUnderline && hasStrikethrough) {
    return TextDecoration.combine([
      TextDecoration.underline,
      TextDecoration.lineThrough,
    ]);
  } else if (hasUnderline) {
    return TextDecoration.underline;
  } else if (hasStrikethrough) {
    return TextDecoration.lineThrough;
  } else {
    return TextDecoration.none;
  }
}
