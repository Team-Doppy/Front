import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../image/image_util.dart';

// unused: simple_grid
import '../spatial_manager.dart';

class PostEncoder {
  // ===== Encoding =====
  static Map<String, dynamic> toModel({
    required MutableDocument document,
    required SpatialManager spatialManager,
  }) {
    // 최신 레이아웃 분석이 되어 있어야 좌표가 정확함
    final elementsById = <String, SpatialElement?>{};
    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      elementsById[node.id] = spatialManager.getElement(node.id);
    }

    final blocks = <Map<String, dynamic>>[];

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      // 요소 메타 접근은 아래 분기에서 직접 수행
      // final grid = spatialManager.gridSystem.pixelToGrid(position);

      if (node is ParagraphNode) {
        final richText = _buildRichText(node.text);
        // 텍스트는 좌표를 저장하지 않음(정렬/리치텍스트만 보존)
        blocks.add({
          'type': 'paragraph',
          'paragraph': {
            'text_align': node.metadata['textAlign'] ?? 'center',
            'rich_text': richText,
          },
        });
      } else if (node is ImageNode) {
        // 이미지는 수평 그리드 오프셋과 그리드 단위 크기만 저장
        final gridSizePx = spatialManager.gridSystem.gridSize;
        final columns = SystemConstants.gridSize.toInt();

        // 표시 크기(px): 편집기에서 저장한 실제 px 우선 사용 → 없으면 스케일 기반 추정
        final pxW =
            (elementsById[node.id]?.metadata['pxW'] as num?)?.toDouble();
        final pxH =
            (elementsById[node.id]?.metadata['pxH'] as num?)?.toDouble();
        final scale =
            (elementsById[node.id]?.metadata['scale'] as double?) ?? 1.0;
        final displayW =
            (pxW ?? (SystemConstants.displayWidth * scale)).round();
        final displayH =
            (pxH ?? (SystemConstants.displayHeight * scale)).round();

        // gridW/H는 우선 편집기에서 계산/저장한 값이 있으면 우선 사용
        int gridW = (elementsById[node.id]?.metadata['gridW'] as int?) ??
            (displayW / gridSizePx).round();
        if (gridW > columns) gridW = columns;
        int gridH = (elementsById[node.id]?.metadata['gridH'] as int?) ??
            (displayH / gridSizePx).round();
        if (gridW < 1) gridW = 1;
        if (gridH < 1) gridH = 1;

        // gridX도 편집기에서 저장한 값이 있으면 우선 사용
        int gridX = (elementsById[node.id]?.metadata['gridX'] as int?) ??
            (() {
              final dx =
                  (elementsById[node.id]?.metadata['xOffset'] as double?) ??
                      0.0;
              // 중앙 정렬의 좌측 시작 인덱스 = (columns - gridW) / 2
              final baseLeft = ((columns - gridW) / 2).round();
              final offsetCols = (dx / gridSizePx).round();
              return baseLeft + offsetCols;
            })();
        final maxLeft = (columns - gridW).clamp(0, columns);
        gridX = gridX.clamp(0, maxLeft);

        // 디버그 로그: 직렬화 직전 실제 값 확인

        blocks.add({
          'type': 'image',
          'image': {
            'url': node.imageUrl,
          },
          'layout': {
            'position': {
              'gridX': gridX,
            },
            'size': {
              'gridW': gridW,
              'gridH': gridH,
              'pxW': displayW,
              'pxH': displayH,
            },
          },
        });
      }
    }

    return {
      'version': '1.0',
      'grid': {'columns': SystemConstants.gridSize},
      'blocks': blocks,
    };
  }

  static String toJson({
    required MutableDocument document,
    required SpatialManager spatialManager,
    bool pretty = true,
  }) {
    final model = toModel(document: document, spatialManager: spatialManager);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(model)
        : jsonEncode(model);
  }

  // ===== Decoding =====
  static MutableDocument fromModel(Map<String, dynamic> model) {
    final blocks = (model['blocks'] as List<dynamic>? ?? []).cast<dynamic>();
    final nodes = <DocumentNode>[];

    for (final raw in blocks) {
      final map = (raw as Map).cast<String, dynamic>();
      final type = map['type'] as String?;
      if (type == 'paragraph') {
        final paragraph =
            (map['paragraph'] as Map?)?.cast<String, dynamic>() ?? {};
        final rich = (paragraph['rich_text'] as List<dynamic>? ?? []);
        final textAndRanges = _buildAttributedTextFromRich(rich);
        final metadata = <String, dynamic>{};
        final textAlign = paragraph['text_align'] as String?;
        if (textAlign != null) metadata['textAlign'] = textAlign;
        nodes.add(ParagraphNode(
          id: Editor.createNodeId(),
          text: textAndRanges.$1,
          metadata: metadata,
        ));
        // Apply attributions after node creation is handled by ParagraphNode's text
        // Since AttributedText already contains attributions, there is no extra step
      } else if (type == 'image') {
        final image = (map['image'] as Map?)?.cast<String, dynamic>() ?? {};
        final url = image['url'] as String? ?? '';
        nodes.add(ImageNode(
          id: Editor.createNodeId(),
          imageUrl: url,
          expectedBitmapSize: const ExpectedSize(3, 4),
        ));
      }
    }

    return MutableDocument(nodes: nodes);
  }

  static MutableDocument fromJson(String jsonStr) {
    final model = jsonDecode(jsonStr) as Map<String, dynamic>;
    return fromModel(model);
  }

  // ===== Helpers =====
  static List<Map<String, dynamic>> _buildRichText(AttributedText text) {
    final content = text.text;
    if (content.isEmpty) {
      return [];
    }

    final spans = <Map<String, dynamic>>[];
    TextAnnotations prev = _annotationsAt(text, 0);
    int runStart = 0;

    for (int i = 1; i < content.length; i++) {
      final ann = _annotationsAt(text, i);
      if (ann != prev) {
        spans.add(_spanFor(content.substring(runStart, i), prev));
        runStart = i;
        prev = ann;
      }
    }
    // last run
    spans.add(_spanFor(content.substring(runStart), prev));
    return spans;
  }

  static Map<String, dynamic> _spanFor(String text, TextAnnotations a) {
    final ann = <String, dynamic>{};
    if (a.bold) ann['bold'] = true;
    if (a.italic) ann['italic'] = true;
    if (a.underline) ann['underline'] = true;
    if (a.strikethrough) ann['strikethrough'] = true;
    if (a.color != null) ann['color'] = _colorToHex(a.color!);
    if (a.fontSize != null) ann['font_size'] = a.fontSize;

    return {
      'type': 'text',
      'text': {'content': text},
      if (ann.isNotEmpty) 'annotations': ann,
    };
  }

  static (AttributedText, List<_RangeAnn>) _buildAttributedTextFromRich(
      List<dynamic> rich) {
    final buffer = StringBuffer();
    final ranges = <_RangeAnn>[];
    for (final item in rich) {
      final map = (item as Map).cast<String, dynamic>();
      if (map['type'] != 'text') continue;
      final text = ((map['text'] as Map?)?.cast<String, dynamic>() ??
              {})['content'] as String? ??
          '';
      final start = buffer.length;
      buffer.write(text);
      final end = buffer.length;
      final ann = (map['annotations'] as Map?)?.cast<String, dynamic>() ?? {};
      ranges.add(_RangeAnn(start, end, ann));
    }

    final attributed = AttributedText(buffer.toString());

    for (final r in ranges) {
      if (r.start == r.end) continue;
      if (r.ann['bold'] == true) {
        attributed.addAttribution(boldAttribution, SpanRange(r.start, r.end));
      }
      if (r.ann['italic'] == true) {
        attributed.addAttribution(
            italicsAttribution, SpanRange(r.start, r.end));
      }
      if (r.ann['underline'] == true) {
        attributed.addAttribution(
            underlineAttribution, SpanRange(r.start, r.end));
      }
      if (r.ann['strikethrough'] == true) {
        attributed.addAttribution(
            strikethroughAttribution, SpanRange(r.start, r.end));
      }
      final colorStr = r.ann['color'] as String?;
      if (colorStr != null) {
        attributed.addAttribution(
            ColorAttribution(_hexToColor(colorStr)), SpanRange(r.start, r.end));
      }
      final fontSize = r.ann['font_size'];
      if (fontSize is num) {
        attributed.addAttribution(FontSizeAttribution(fontSize.toDouble()),
            SpanRange(r.start, r.end));
      }
    }

    return (attributed, ranges);
  }

  static TextAnnotations _annotationsAt(AttributedText text, int offset) {
    final set = text.getAllAttributionsAt(offset);
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strike = false;
    Color? color;
    double? fontSize;

    for (final a in set) {
      if (a == boldAttribution) bold = true;
      if (a == italicsAttribution) italic = true;
      if (a == underlineAttribution) underline = true;
      if (a == strikethroughAttribution) strike = true;
      if (a is ColorAttribution) color = a.color;
      if (a is FontSizeAttribution) fontSize = a.fontSize;
    }

    return TextAnnotations(
      bold: bold,
      italic: italic,
      underline: underline,
      strikethrough: strike,
      color: color,
      fontSize: fontSize,
    );
  }

  static String _colorToHex(Color color) {
    return '#'
        '${color.red.toRadixString(16).padLeft(2, '0')}'
        '${color.green.toRadixString(16).padLeft(2, '0')}'
        '${color.blue.toRadixString(16).padLeft(2, '0')}';
  }

  static Color _hexToColor(String hex) {
    var value = hex.replaceAll('#', '').toUpperCase();
    if (value.length == 6) value = 'FF$value';
    final intVal = int.parse(value, radix: 16);
    return Color(intVal);
  }
}

class TextAnnotations {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final Color? color;
  final double? fontSize;

  const TextAnnotations({
    required this.bold,
    required this.italic,
    required this.underline,
    required this.strikethrough,
    required this.color,
    required this.fontSize,
  });

  @override
  bool operator ==(Object other) {
    return other is TextAnnotations &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline &&
        other.strikethrough == strikethrough &&
        _colorEquals(other.color, color) &&
        other.fontSize == fontSize;
  }

  @override
  int get hashCode => Object.hash(
        bold,
        italic,
        underline,
        strikethrough,
        color?.value,
        fontSize,
      );

  static bool _colorEquals(Color? a, Color? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    return a.value == b.value;
  }
}

class _RangeAnn {
  final int start;
  final int end;
  final Map<String, dynamic> ann;

  _RangeAnn(this.start, this.end, this.ann);
}
