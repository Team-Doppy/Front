import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_editor/super_editor.dart';
import '../component/clip_component.dart';
import '../component/link_component.dart';
import '../component/row_image_component.dart';
import '../config/editor_config.dart';
import 'text_attributions.dart';
import 'text_styling_service.dart' show TextStylingService;

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
  // 🎯 성능 최적화: 테마는 Theme.of로 직접 읽기
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color bodyColor = isDark
      ? const Color.fromARGB(230, 255, 255, 255)
      : Theme.of(context).colorScheme.onSurface;

  return defaultStylesheet.copyWith(
    documentPadding: EdgeInsets.all(EditorConfig.documentPadding),
    addRulesAfter: [
      // 텍스트 노드 스타일
      StyleRule(BlockSelector.all, (doc, docNode) {
        if (docNode is ParagraphNode) {
          // 메타데이터에서 폰트 정보 읽기
          final fontFamily = docNode.metadata['fontFamily'] as String?;
          final isTitle =
              docNode.metadata[EditorConfig.titleNodeMetadataKey] == true;
          TextStyle bodyStyle = TextStyle(
            fontSize: isTitle
                ? EditorConfig.defaultTitleFontSize
                : EditorConfig.defaultBodyFontSize,
            fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
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
            Styles.textStyle: bodyStyle,
            Styles.padding: CascadingPadding.only(
              top: isTitle ? EditorConfig.defaultTitleVerticalPadding : 0,
              bottom: isTitle ? EditorConfig.defaultTitleVerticalPadding : 0,
              left: EditorConfig.horizontalPadding,
              right: EditorConfig.horizontalPadding,
            ),
          };
        }
        if (docNode is ClipNode ||
            docNode is ImageNode ||
            docNode is LinkNode) {
          // 메타데이터에서 패딩 모드 확인 (기본값: 'center' = 패딩 있음)
          final paddingMode =
              docNode.metadata['padding'] as String? ?? 'center';
          final horizontalPadding = paddingMode == 'full'
              ? 0.0
              : EditorConfig.horizontalPadding;

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

      // 🎯 전역 폰트 사이즈 적용 (FontSizeAttribution이 없을 때만)
      double? finalFontSize = style.fontSize;
      final hasFontSizeAttribution = attributions.any(
        (attr) => attr is FontSizeAttribution,
      );
      if (!hasFontSizeAttribution && !isReadOnly) {
        final globalFontSize = _globalTextStylingService?.globalFontSize;
        if (globalFontSize != null) {
          finalFontSize = globalFontSize;
        }
      }
      // 🎯 제목 노드는 블록 스타일에서 defaultTitleFontSize로 설정됨 → 덮어쓰기 방지
      if (existingStyle.fontSize == EditorConfig.defaultTitleFontSize) {
        finalFontSize = EditorConfig.defaultTitleFontSize;
      }

      style = style.copyWith(
        // ✅ block(Paragraph) 레벨에서 지정된 fontWeight(예: mention=bold)는 유지해야 한다.
        // inlineTextStyler가 무조건 normal로 덮어쓰면 멘션이 boldAttribution 없이도 bold가 안 보이게 된다.
        fontWeight: isBold
            ? FontWeight.bold
            : (existingStyle.fontWeight ?? FontWeight.normal),
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _buildTextDecoration(hasUnderline, hasStrikethrough),
        fontSize: finalFontSize,
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
