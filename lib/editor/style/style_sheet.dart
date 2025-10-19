import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/config.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart'; // HighlightAttribution import
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
Stylesheet buildCustomStylesheet(BuildContext context) {
  final bool isDark =
      context.watch<ThemeProvider>().themeMode == ThemeMode.dark;
  final Color titleColor =
      isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  final Color bodyColor =
      isDark
          ? const Color.fromARGB(230, 255, 255, 255)
          : AppColors.lightTextPrimary;

  return defaultStylesheet.copyWith(
    documentPadding: const EdgeInsets.all(EditorConfig.documentPadding),
    addRulesAfter: [
      // 텍스트 노드 스타일
      StyleRule(BlockSelector.all, (doc, docNode) {
        if (docNode is ParagraphNode) {
          // 제목 문단 스타일
          final isTitle = (docNode.metadata['isTitle'] == true);

          // 제목 스타일은 문서의 0번째 문단에만 적용
          if (isTitle && doc.getNodeIndexById(docNode.id) == 0) {
            return {
              Styles.textStyle: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: titleColor,
                height: 0,
              ),
              Styles.padding: const CascadingPadding.only(
                top: 100,
                bottom: 20,
                left: 20,
                right: 20,
              ),
            };
          }

          return {
            Styles.textStyle: TextStyle(fontSize: 16, color: bodyColor),

            Styles.padding: const CascadingPadding.only(
              top: 0,
              bottom: 0,
              left: 20,
              right: 20,
            ),
          };
        }
        if (docNode is ImageNode) {
          return {
            Styles.padding: CascadingPadding.symmetric(
              vertical: EditorConfig.imagePadding,
              horizontal: 0,
            ),
          };
        }
        if (docNode is ImageRowNode) {
          return {
            Styles.padding: CascadingPadding.symmetric(
              vertical: EditorConfig.imagePadding,
              horizontal: 0,
            ),
          };
        }

        if (docNode is ClipNode) {
          return {
            Styles.padding: CascadingPadding.symmetric(
              vertical: 0,
              horizontal: 0,
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
      Color? highlightColor;
      String? fontFamily;

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
          highlightColor = attribution.color;
        } else if (attribution is ColorAttribution) {
          style = style.copyWith(color: attribution.color);
        } else if (attribution is FontSizeAttribution) {
          style = style.copyWith(fontSize: attribution.fontSize);
        } else if (attribution is FontFamilyAttribution) {
          fontFamily = attribution.fontFamily;
        }
      }

      style = style.copyWith(
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _buildTextDecoration(hasUnderline, hasStrikethrough),
        // 🎨 형광펜 배경색 적용 (연한 색상으로 자연스러운 효과)
        backgroundColor: highlightColor?.withOpacity(0.4), // 투명도 조정으로 더 자연스럽게
      );

      // 🎨 폰트 패밀리 적용 (Google Fonts 로더 통해 동적 로드)
      // Attribution이 없으면 전역 폰트 사용
      if (fontFamily == null || fontFamily.isEmpty) {
        fontFamily = _globalTextStylingService?.globalFontFamily;
        if (fontFamily != null) {
          print('[FontDebug] 전역 폰트 사용: $fontFamily');
        }
      }

      if (fontFamily != null && fontFamily.isNotEmpty) {
        print('[FontDebug] inlineTextStyler 폰트 감지: $fontFamily');
        try {
          style = GoogleFonts.getFont(fontFamily, textStyle: style);
          print('[FontDebug] GoogleFonts.getFont 성공: $fontFamily');
        } catch (e) {
          print('[FontDebug] GoogleFonts.getFont 실패: $fontFamily (오류: $e)');
          // 폰트명이 GoogleFonts에 없을 경우 fallback으로 family만 지정
          style = style.copyWith(fontFamily: fontFamily);
        }
      }
      // 본문/타이틀 기본 색을 테마에 맞춰 적용 (인라인 컬러 지정이 없는 경우)
      if (style.color == null) {
        style = style.copyWith(color: bodyColor);
      }
      // 제목의 경우 위에서 const TextStyle로 생성했으므로 색상을 후처리로 주입
      // ParagraphNode의 metadata를 직접 접근할 수 없어서, 기본적으로 bodyColor를 주고
      // 실제 렌더링에서 첫 문단(isTitle=true)은 아래 규칙으로 타이틀 색을 덮어씀
      // (SuperEditor는 상위 규칙 → 인라인 규칙 순 적용)
      return style;
    },
    addRulesBefore: [
      // 타이틀 문단에 색상을 강제로 덮어씌우기 (테마 반영)
      StyleRule(BlockSelector.all, (doc, node) {
        if (node is ParagraphNode) {
          final isTitle = (node.metadata['isTitle'] == true);
          if (isTitle && doc.getNodeIndexById(node.id) == 0) {
            return {Styles.textStyle: TextStyle(color: titleColor)};
          }
        }
        return {};
      }),
    ],
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
