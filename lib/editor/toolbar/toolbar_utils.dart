import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../style/text_styling_service.dart';
import '../style/text_attributions.dart';
import '../config/editor_config.dart';
import '../utils/editor_localization.dart';

/// 현재 적용 중인 폰트명 가져오기
String getCurrentFontName(
  BuildContext context,
  TextStylingService stylingService,
) {
  final selection = stylingService.composer.selection;

  // 선택 영역이 있으면 해당 범위의 폰트 확인
  if (selection != null && !selection.isCollapsed) {
    final node = stylingService.editor.document.getNodeById(
      selection.base.nodeId,
    );
    if (node is ParagraphNode) {
      // 1. Attribution에서 폰트 확인
      final position = selection.base.nodePosition as TextNodePosition;
      final attributions = node.text.getAllAttributionsAt(position.offset);
      for (final attribution in attributions) {
        if (attribution is FontFamilyAttribution) {
          return attribution.fontFamily;
        }
      }
      // 2. 메타데이터에서 폰트 확인
      final fontFamily = node.metadata['fontFamily'] as String?;
      if (fontFamily != null && fontFamily.isNotEmpty) {
        return fontFamily;
      }
    }
  }

  // 선택 영역이 없으면 전역 폰트 또는 첫 번째 문단의 폰트 확인
  final globalFont = stylingService.globalFontFamily;
  if (globalFont != null && globalFont.isNotEmpty) {
    return globalFont;
  }

  // 첫 번째 문단의 폰트 확인
  for (int i = 0; i < stylingService.editor.document.length; i++) {
    final node = stylingService.editor.document.getNodeAt(i);
    if (node is ParagraphNode) {
      final fontFamily = node.metadata['fontFamily'] as String?;
      if (fontFamily != null && fontFamily.isNotEmpty) {
        return fontFamily;
      }
    }
  }

  // 로케일에 따라 기본 폰트 이름 반환
  return context.tr('editor_default');
}

/// 현재 적용 중인 텍스트 색상 가져오기
Color getCurrentTextColor(
  BuildContext context,
  TextStylingService stylingService,
) {
  final selection = stylingService.composer.selection;
  Color? color;

  // 선택 영역이 있으면 해당 범위의 색상 확인
  if (selection != null && !selection.isCollapsed) {
    final node = stylingService.editor.document.getNodeById(
      selection.base.nodeId,
    );
    if (node is TextNode) {
      final position = selection.base.nodePosition as TextNodePosition;
      final attributions = node.text.getAllAttributionsAt(position.offset);
      for (final attribution in attributions) {
        // 형광펜은 제외하고 글자색만 반환
        if (attribution is ColorAttribution &&
            attribution is! HighlightAttribution) {
          color = attribution.color;
          break;
        }
      }
    }
  } else {
    // 선택이 없으면 preferences에서 확인
    final currentAttrs =
        stylingService.composer.preferences.currentAttributions;
    for (final attr in currentAttrs) {
      // 형광펜은 제외하고 글자색만 반환
      if (attr is ColorAttribution && attr is! HighlightAttribution) {
        color = attr.color;
        break;
      }
    }
  }

  // 기본 색상 (테마의 onSurface)
  return color ?? Theme.of(context).colorScheme.onSurface;
}

/// 선택 영역에 여러 색상이 섞여 있는지 확인
List<Color> getTextColorsInSelection(TextStylingService stylingService) {
  final selection = stylingService.composer.selection;
  final colors = <Color>{};

  if (selection != null && !selection.isCollapsed) {
    final startNode = stylingService.editor.document.getNodeById(
      selection.base.nodeId,
    );
    final endNode = stylingService.editor.document.getNodeById(
      selection.extent.nodeId,
    );

    if (startNode is TextNode && endNode is TextNode) {
      final startPos = selection.base.nodePosition as TextNodePosition;
      final endPos = selection.extent.nodePosition as TextNodePosition;

      // 단일 노드 내에서 선택된 경우만 여러 색상 체크
      if (startNode.id == endNode.id) {
        final startOffset = startPos.offset;
        final endOffset = endPos.offset;
        for (final i in _sampleOffsets(startOffset, endOffset)) {
          final attributions = startNode.text.getAllAttributionsAt(i);
          for (final attribution in attributions) {
            if (attribution is ColorAttribution &&
                attribution is! HighlightAttribution) {
              colors.add(attribution.color);
            }
          }
        }
      } else {
        // 여러 노드에 걸친 선택
        final startIndex = stylingService.editor.document.getNodeIndexById(
          startNode.id,
        );
        final endIndex = stylingService.editor.document.getNodeIndexById(
          endNode.id,
        );

        for (int i = startIndex; i <= endIndex; i++) {
          final node = stylingService.editor.document.getNodeAt(i);
          if (node is TextNode) {
            final startOffset = i == startIndex ? startPos.offset : 0;
            final endOffset = i == endIndex
                ? endPos.offset
                : node.text.text.length;

            for (final j in _sampleOffsets(startOffset, endOffset)) {
              final attributions = node.text.getAllAttributionsAt(j);
              for (final attribution in attributions) {
                if (attribution is ColorAttribution &&
                    attribution is! HighlightAttribution) {
                  colors.add(attribution.color);
                }
              }
            }
          }
        }
      }
    }
  }

  return colors.toList();
}

/// 텍스트 속성 계산 시 전체 범위 순회 대신 대표 offset만 샘플링
List<int> _sampleOffsets(int start, int end) {
  if (end <= start) return const [];
  final mid = (start + end) >> 1;
  final last = end - 1;
  final candidates = <int>{start, mid, last};
  candidates.removeWhere((o) => o < start || o >= end);
  return candidates.toList();
}

/// 현재 형광펜 색상 가져오기
Color? getCurrentHighlightColor(TextStylingService stylingService) {
  final selection = stylingService.composer.selection;

  // 선택 영역이 있으면 해당 범위의 형광펜 색상 확인
  if (selection != null && !selection.isCollapsed) {
    final node = stylingService.editor.document.getNodeById(
      selection.base.nodeId,
    );
    if (node is TextNode) {
      final position = selection.base.nodePosition as TextNodePosition;
      final attributions = node.text.getAllAttributionsAt(position.offset);
      for (final attribution in attributions) {
        if (attribution is HighlightAttribution) {
          return attribution.color;
        }
      }
    }
  }

  return null; // 형광펜이 없으면 null
}

/// 선택 영역에 등장하는 서로 다른 폰트 사이즈 집합 (mixed 여부 판단용)
Set<double> _getFontSizesInSelection(TextStylingService stylingService) {
  final selection = stylingService.composer.selection;
  final sizes = <double>{};
  if (selection == null || selection.isCollapsed) return sizes;

  final startNode = stylingService.editor.document.getNodeById(
    selection.base.nodeId,
  );
  final endNode = stylingService.editor.document.getNodeById(
    selection.extent.nodeId,
  );
  if (startNode is! TextNode || endNode is! TextNode) return sizes;

  final startPos = selection.base.nodePosition as TextNodePosition;
  final endPos = selection.extent.nodePosition as TextNodePosition;

  void collectFromNode(TextNode node, int startOffset, int endOffset) {
    for (final i in _sampleOffsets(startOffset, endOffset)) {
      double? size;
      for (final a in node.text.getAllAttributionsAt(i)) {
        if (a is FontSizeAttribution) {
          size = a.fontSize;
          break;
        }
      }
      sizes.add(size ?? EditorConfig.defaultBodyFontSize);
    }
  }

  if (startNode.id == endNode.id) {
    collectFromNode(startNode, startPos.offset, endPos.offset);
  } else {
    final startIndex = stylingService.editor.document.getNodeIndexById(
      startNode.id,
    );
    final endIndex = stylingService.editor.document.getNodeIndexById(
      endNode.id,
    );
    for (int i = startIndex; i <= endIndex; i++) {
      final node = stylingService.editor.document.getNodeAt(i);
      if (node is TextNode) {
        final startOffset = i == startIndex ? startPos.offset : 0;
        final endOffset = i == endIndex
            ? endPos.offset
            : node.text.text.length;
        collectFromNode(node, startOffset, endOffset);
      }
    }
  }
  return sizes;
}

/// 현재 폰트 사이즈 가져오기. 선택 영역에 서로 다른 크기가 섞여 있으면 null(mixed) 반환.
double? getCurrentFontSize(TextStylingService stylingService) {
  final selection = stylingService.composer.selection;

  if (selection != null && !selection.isCollapsed) {
    final sizes = _getFontSizesInSelection(stylingService);
    if (sizes.isEmpty) return EditorConfig.defaultBodyFontSize;
    if (sizes.length > 1) return null; // mixed
    return sizes.single;
  }

  double? fontSize;
  final current = stylingService.composer.preferences.currentAttributions;
  for (final attr in current) {
    if (attr is FontSizeAttribution) {
      fontSize = attr.fontSize;
      break;
    }
  }
  // 🎯 전체 선택 후 삭제 시 applyLastSelectionFontSizeWhenCollapsed가 globalFontSize는 19로 두는데
  // preferences 반영/캐시 타이밍 때문에 툴바만 16으로 보이는 경우 방지: globalFontSize를 fallback으로 사용
  if (fontSize == null && stylingService.globalFontSize != null) {
    fontSize = stylingService.globalFontSize;
  }
  return fontSize ?? EditorConfig.defaultBodyFontSize;
}

/// 정렬 상태에 따른 아이콘 반환
IconData getAlignmentIcon(TextAlign alignment) {
  switch (alignment) {
    case TextAlign.left:
      return Icons.format_align_left;
    case TextAlign.center:
      return Icons.format_align_center;
    case TextAlign.right:
      return Icons.format_align_right;
    default:
      return Icons.format_align_center;
  }
}
