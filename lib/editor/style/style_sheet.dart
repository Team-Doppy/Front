import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/config.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

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
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
              Styles.padding: const CascadingPadding.only(
                top: 10,
                bottom: 20,
                left: 0,
                right: 0,
              ),
            };
          }
          return {
            Styles.textStyle: TextStyle(fontSize: 16, color: bodyColor),

            Styles.padding: const CascadingPadding.all(
              EditorConfig.textPadding,
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

        return {};
      }),
    ],
    inlineTextStyler: (attributions, existingStyle) {
      TextStyle style = existingStyle;
      bool isBold = false;
      bool isItalic = false;
      bool hasUnderline = false;
      bool hasStrikethrough = false;

      for (final attribution in attributions) {
        if (attribution == boldAttribution) {
          isBold = true;
        } else if (attribution == italicsAttribution) {
          isItalic = true;
        } else if (attribution == underlineAttribution) {
          hasUnderline = true;
        } else if (attribution == strikethroughAttribution) {
          hasStrikethrough = true;
        } else if (attribution is ColorAttribution) {
          style = style.copyWith(color: attribution.color);
        } else if (attribution is FontSizeAttribution) {
          style = style.copyWith(fontSize: attribution.fontSize);
        }
      }

      style = style.copyWith(
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _buildTextDecoration(hasUnderline, hasStrikethrough),
      );
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
