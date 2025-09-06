import 'package:doppy/editor/config/config.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 커스텀 스타일시트
Stylesheet buildCustomStylesheet() {
  return defaultStylesheet.copyWith(
    documentPadding: const EdgeInsets.all(EditorConfig.documentPadding),
    addRulesAfter: [
      // 텍스트 노드 스타일
      StyleRule(BlockSelector.all, (doc, docNode) {
        if (docNode is ParagraphNode) {
          // 제목 문단 스타일
          final isTitle = (docNode.metadata['isTitle'] == true);
          if (isTitle) {
            return {
              Styles.textStyle: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: Colors.black,
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
            Styles.textStyle: const TextStyle(
              fontSize: 13,
              color: Colors.black,
            ),

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
