import 'package:doppy/editor/image/image_util.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../util/view_scale.dart';

/// 커스텀 스타일시트
Stylesheet buildCustomStylesheet([BuildContext? context]) {
  final scale = context != null ? EditorViewScale.of(context) : 1.0;
  final baseFontSize = 16.0 * scale;
  final baseLineHeight = SystemConstants.defaultLineHeight1; // 비율은 유지, 폰트에만 스케일
  return defaultStylesheet.copyWith(
    documentPadding: const EdgeInsets.only(
      left: 0,
      right: 0,
      top: SystemConstants.documentMargin,
      bottom: SystemConstants.documentMargin,
    ),
    addRulesAfter: [
      StyleRule(BlockSelector.all, (doc, docNode) {
        final baseStyle = {
          Styles.textStyle: const TextStyle(color: Colors.black),
          Styles.padding: const CascadingPadding.all(0),
        };

        // 🎯 정렬 스타일 추가 (기본값: 중간 정렬)
        TextAlign textAlign = TextAlign.center; // 기본값

        if (docNode is ParagraphNode) {
          final textAlignName = docNode.metadata['textAlign'] as String?;
          if (textAlignName != null) {
            switch (textAlignName) {
              case 'left':
                textAlign = TextAlign.left;
                break;
              case 'center':
                textAlign = TextAlign.center;
                break;
              case 'right':
                textAlign = TextAlign.right;
                break;
            }
          }
        }

        baseStyle[Styles.textAlign] = textAlign;
        baseStyle[Styles.textStyle] = (baseStyle[Styles.textStyle] as TextStyle)
            .copyWith(fontSize: baseFontSize, height: baseLineHeight);

        return baseStyle;
      }),
      // 🎯 이미지 노드에 대한 간격 추가
      StyleRule(BlockSelector.all, (doc, docNode) {
        if (docNode is ImageNode) {
          return {
            Styles.padding: const CascadingPadding.only(
              top: SystemConstants.imagePadding,
              bottom: 0,
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
        fontSize: (style.fontSize ?? 16) * scale,
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
