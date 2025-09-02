import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
/*

class PostEncoder {
  // ===== Encoding =====
  static Map<String, dynamic> toModel({
    required MutableDocument document,
    required SpatialManager spatialManager,
  }) {
    spatialManager.analyzeAndUpdateDocument(
      document: document,
      screenWidth: spatialManager.gridSystem.screenWidth,
      documentPadding: 0.0,
    );

    // 최신 레이아웃 분석이 되어 있어야 좌표가 정확함
    final elementsById = <String, SpatialElement?>{};
    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      elementsById[node.id] = spatialManager.getElement(node.id);
    }

    final blocks = <Map<String, dynamic>>[];

    // 🎯 디코더에 필요한 정보들
    final gridSize = spatialManager.gridSystem.gridSize;
    final columns = SystemConstants.gridSize;
    final editorScreenWidth = spatialManager.gridSystem.screenWidth;

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;

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
        final element = elementsById[node.id];
        if (element != null) {
          final position = element.coordinates.document;
          final size = element.size;
          final metadata = element.metadata;

          //  실제 픽셀 크기와 위치 정보
          final pxW = (metadata['pxW'] as num?)?.toDouble() ?? size.width;
          final pxH = (metadata['pxH'] as num?)?.toDouble() ?? size.height;
          final scale = (metadata['scale'] as double?) ?? 1.0;
          final gridX = (metadata['gridX'] as num?)?.toDouble() ?? 0.0;

          blocks.add({
            'type': 'image',
            'image': {'url': node.imageUrl, 'alt': '이미지'},
            'layout': {
              'position': {'x': position.dx, 'y': position.dy, 'gridX': gridX},
              'size': {
                'width': size.width,
                'height': size.height,
                'pxW': pxW,
                'pxH': pxH,
                'scale': scale,
              },
            },
          });
        } else {
          blocks.add({
            'type': 'image',
            'image': {'url': node.imageUrl, 'alt': '이미지'},
            'layout': {
              'position': {'x': 0.0, 'y': 0.0, 'xOffset': 0.0},
              'size': {
                'width': 400.0,
                'height': 300.0,
                'pxW': 400.0,
                'pxH': 300.0,
                'scale': 1.0,
              },
            },
          });
        }
      }
    }

    return {
      'version': '1.0',
      'editor': {
        'screenWidth': editorScreenWidth,
        'gridSize': gridSize,
        'columns': columns,
      },
      'grid': {'columns': columns},
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
        nodes.add(
          ParagraphNode(
            id: Editor.createNodeId(),
            text: textAndRanges.$1,
            metadata: metadata,
          ),
        );
        // Apply attributions after node creation is handled by ParagraphNode's text
        // Since AttributedText already contains attributions, there is no extra step
      } else if (type == 'image') {
        final image = (map['image'] as Map?)?.cast<String, dynamic>() ?? {};
        final url = image['url'] as String? ?? '';
        nodes.add(
          ImageNode(
            id: Editor.createNodeId(),
            imageUrl: url,
            expectedBitmapSize: const ExpectedSize(3, 4),
          ),
        );
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
    List<dynamic> rich,
  ) {
    final buffer = StringBuffer();
    final ranges = <_RangeAnn>[];
    for (final item in rich) {
      final map = (item as Map).cast<String, dynamic>();
      if (map['type'] != 'text') continue;
      final text =
          ((map['text'] as Map?)?.cast<String, dynamic>() ?? {})['content']
              as String? ??
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
          italicsAttribution,
          SpanRange(r.start, r.end),
        );
      }
      if (r.ann['underline'] == true) {
        attributed.addAttribution(
          underlineAttribution,
          SpanRange(r.start, r.end),
        );
      }
      if (r.ann['strikethrough'] == true) {
        attributed.addAttribution(
          strikethroughAttribution,
          SpanRange(r.start, r.end),
        );
      }
      final colorStr = r.ann['color'] as String?;
      if (colorStr != null) {
        attributed.addAttribution(
          ColorAttribution(_hexToColor(colorStr)),
          SpanRange(r.start, r.end),
        );
      }
      final fontSize = r.ann['font_size'];
      if (fontSize is num) {
        attributed.addAttribution(
          FontSizeAttribution(fontSize.toDouble()),
          SpanRange(r.start, r.end),
        );
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
*/