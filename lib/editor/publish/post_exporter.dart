import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:flutter/material.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/location_component.dart';
import 'dart:convert';

/// 간단 JSON 인코더 유틸리티
/// - 앱 내에서 공통으로 JSON 문자열을 뽑을 때만 사용
/// - 구조 생성/수집은 별도 모듈에서 수행하고, 이 파일은 오직 문자열 인코딩만 담당
class JsonExport {
  /// data를 JSON 문자열로 직렬화한다.
  /// - pretty: true면 사람이 읽기 좋은 들여쓰기 적용
  static String encode(Object? data, {bool pretty = false}) {
    final encoder =
        pretty
            ? JsonEncoder.withIndent('  ', _toEncodable)
            : JsonEncoder(_toEncodable);
    return encoder.convert(data);
  }

  /// JSON에서 지원하지 않는 타입을 안전하게 문자열/맵으로 치환한다.
  /// - Uint8List → base64 string
  /// - DateTime → ISO8601 string
  /// - ui.Offset → {x, y}
  /// - ui.Color → #RRGGBB(또는 #AARRGGBB)
  static Object? _toEncodable(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) {
      return base64Encode(value);
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is ui.Offset) {
      return {'x': value.dx, 'y': value.dy};
    }
    if (value is ui.Size) {
      return {'width': value.width, 'height': value.height};
    }
    if (value is ui.Color) {
      final a = value.alpha.toRadixString(16).padLeft(2, '0');
      final r = value.red.toRadixString(16).padLeft(2, '0');
      final g = value.green.toRadixString(16).padLeft(2, '0');
      final b = value.blue.toRadixString(16).padLeft(2, '0');
      // ARGB를 포함한 8자리 HEX로 출력
      return '#${a.toUpperCase()}${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
    }
    // 기본적으로 jsonEncode가 처리 가능한 객체(Map/List/num/bool/String)
    // 혹은 toJson 메서드가 있는 객체는 그 결과를 사용
    try {
      // ignore: avoid_dynamic_calls
      final toJson = (value as dynamic).toJson;
      // ignore: avoid_dynamic_calls
      return toJson();
    } catch (_) {
      // 마지막 수단: 문자열로 덤프(디버그 용도)
      return value.toString();
    }
  }
}

/// 편집 결과를 JSON(Map)으로 내보내는 유틸리티.
/// - 구조 수집 및 직렬화를 모두 담당한다.
class PostExporter {
  /// 편집 중 문서/스티커를 JSON 문자열로 내보낸다.
  static String exportToJsonString({
    required EditorService editorService,
    required StickerService stickerService,
    Size? viewportSize,
    bool pretty = true,
  }) {
    final map = exportToMap(
      editorService: editorService,
      stickerService: stickerService,
      viewportSize: viewportSize,
    );
    return JsonExport.encode(map, pretty: pretty);
  }

  /// 편집 중 문서/스티커를 JSON(Map)으로 내보낸다.
  static Map<String, dynamic> exportToMap({
    required EditorService editorService,
    required StickerService stickerService,
    Size? viewportSize,
  }) {
    final doc = editorService.document;
    final layout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    final List<Map<String, dynamic>> nodes = <Map<String, dynamic>>[];

    for (int i = 0; i < doc.length; i++) {
      final node = doc.getNodeAt(i);
      if (node == null) continue;

      if (node is ParagraphNode) {
        final meta = node.metadata;
        nodes.add({
          'id': node.id,
          'type': 'paragraph',
          'text': node.text.text,
          'align': meta['textAlign'] ?? 'center',
          'isTitle': meta['isTitle'] == true,
          'spans': _buildParagraphSpans(node.text),
        });
        continue;
      }

      // ImageNode (SuperEditor 내장)
      if (node is ImageNode) {
        nodes.add({
          'id': node.id,
          'type': 'image',
          'url': node.imageUrl,
          'altText': node.altText,
        });
        continue;
      }

      // ImageRowNode (프로젝트에 존재하는 경우)
      if (node is ImageRowNode) {
        nodes.add({
          'id': node.id,
          'type': 'imageRow',
          'urls': node.imageUrls,
          'spacing': node.spacing,
        });
        continue;
      }

      if (node is LinkNode) {
        nodes.add({
          'id': node.id,
          'type': 'link',
          'url': node.url,
          'title': node.title,
          'description': node.description,
          'thumbnailUrl': node.thumbnailUrl,
        });
        continue;
      }

      if (node is LocationNode) {
        nodes.add({
          'id': node.id,
          'type': 'location',
          'lat': node.lat,
          'lng': node.lng,
          'title': node.title,
          'address': node.address,
          'description': node.description,
        });
        continue;
      }

      if (node is MentionNode) {
        nodes.add({
          'id': node.id,
          'type': 'mention',
          'usernames': node.usernames,
        });
        continue;
      }

      // 미지원 노드는 타입만 기록
      nodes.add({'id': node.id, 'type': node.runtimeType.toString()});
    }

    // Stickers
    final List<Map<String, dynamic>> stickers = <Map<String, dynamic>>[];
    for (final s in stickerService.stickers) {
      final base = <String, dynamic>{
        'id': s.id,
        'type': _stickerTypeString(s.type),
        'zIndex': s.zIndex,
        'opacity': s.opacity,
        'rotation': s.rotation,
        'scale': s.scale,
        'positionFallback': {
          'xPx': s.position.dx,
          'yPx': s.position.dy,
          'docWidth': viewportSize?.width,
        },
      };

      switch (s.type) {
        case StickerType.text:
          if (s.content is Map) {
            // 이미 {text, style} 형태로 보관된 경우 그대로 사용
            final m = (s.content as Map).cast<String, dynamic>();
            base['content'] = {
              'text': (m['text'] ?? '').toString(),
              'style': (m['style'] as Map?)?.cast<String, dynamic>(),
            };
            print(base['content']);
          } else {
            base['content'] = {'text': s.content.toString(), 'style': null};
          }
          break;
        case StickerType.emoji:
          base['content'] = s.content.toString();
          break;
        case StickerType.image:
          if (s.content is Uint8List) {
            base['content'] = {
              'bytes': s.content, // JsonExport가 base64 문자열로 직렬화
            };
          } else {
            base['content'] = {'url': s.content.toString()};
          }
          break;
      }

      // Anchor 계산: 문서 레이아웃이 있을 경우, 스티커의 문서 좌표와 가장 가까운 노드 rect를 찾고 상대 좌표를 기록
      Map<String, dynamic>? anchor;
      try {
        if (layout != null) {
          final nearest = _nearestNodeForDocOffset(
            layout: layout,
            document: doc,
            docOffset: s.position,
          );
          if (nearest != null) {
            final nodeId = nearest.nodeId;
            final rect = nearest.rect;
            final relX =
                rect.width == 0
                    ? 0.5
                    : ((s.position.dx - rect.left) / rect.width).clamp(
                      0.0,
                      1.0,
                    );
            final relY =
                rect.height == 0
                    ? 0.0
                    : ((s.position.dy - rect.top) / rect.height).clamp(
                      0.0,
                      1.0,
                    );
            anchor = {'nodeId': nodeId, 'relX': relX, 'relY': relY};
          }
        }
      } catch (_) {}
      base['anchor'] = anchor;
      stickers.add(base);
    }

    return {
      'version': '1.0',
      'thumnailUrl': '',
      'title': nodes[0]['text'],
      'writer': 'anonymous',
      'updatedAt': DateTime.now(),
      'document': {'nodes': nodes},
      'stickers': stickers,
    };
  }

  /// 리치 텍스트(AttributedText)에서 spans를 추출한다.
  /// 현 단계에선 최소 스냅샷(전체 범위 기본 스타일)만 제공하고,
  /// 세부 스타일은 후속 단계에서 확장한다.
  static List<Map<String, dynamic>> _buildParagraphSpans(AttributedText text) {
    if (text.text.isEmpty) return <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> spans = <Map<String, dynamic>>[];

    Map<String, dynamic> _attrsAt(int offset) {
      // offset이 범위를 벗어나면 빈 속성
      if (offset < 0 || offset >= text.text.length) return <String, dynamic>{};
      final atts = text.getAllAttributionsAt(offset);
      return _normalizeAttributions(atts);
    }

    int runStart = 0;
    Map<String, dynamic> prev = _attrsAt(0);
    for (int i = 1; i <= text.text.length; i++) {
      // 마지막 i == length에서는 강제로 종료 스팬 배출
      final Map<String, dynamic> curr =
          (i == text.text.length) ? <String, dynamic>{} : _attrsAt(i);
      final bool changed = !_shallowMapEquals(prev, curr);
      if (changed) {
        spans.add({'start': runStart, 'end': i, 'attrs': prev});
        runStart = i;
        prev = curr;
      }
    }
    return spans;
  }

  static Map<String, dynamic> _normalizeAttributions(Set<Attribution> atts) {
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strike = false;
    double? fontSize;
    ui.Color? color;

    for (final a in atts) {
      if (a == boldAttribution) {
        bold = true;
      } else if (a == italicsAttribution) {
        italic = true;
      } else if (a == underlineAttribution) {
        underline = true;
      } else if (a == strikethroughAttribution) {
        strike = true;
      } else if (a is ColorAttribution) {
        color = a.color;
      } else if (a is FontSizeAttribution) {
        fontSize = a.fontSize;
      }
    }

    final map = <String, dynamic>{
      if (bold) 'bold': true,
      if (italic) 'italic': true,
      if (underline) 'underline': true,
      if (strike) 'strikethrough': true,
      if (fontSize != null) 'font_size': fontSize,
      if (color != null) 'color': _hexColor(color),
    };
    return map;
  }

  static bool _shallowMapEquals(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      final va = a[k];
      final vb = b[k];
      if (va is num && vb is num) {
        if (va.toDouble() != vb.toDouble()) return false;
      } else if (va != vb) {
        return false;
      }
    }
    return true;
  }

  static String _hexColor(ui.Color c) {
    final a = c.alpha.toRadixString(16).padLeft(2, '0');
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    return '#${a.toUpperCase()}${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  /// 문서 좌표(docOffset)와 가장 가까운 노드 rect를 반환한다.
  static _AnchorCandidate? _nearestNodeForDocOffset({
    required DocumentLayout layout,
    required Document document,
    required ui.Offset docOffset,
  }) {
    Rect? bestRect;
    String? bestId;
    double bestDist = double.infinity;
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      try {
        final rect = layout.getRectForSelection(
          DocumentPosition(
            nodeId: node.id,
            nodePosition: const UpstreamDownstreamNodePosition.upstream(),
          ),
          DocumentPosition(
            nodeId: node.id,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          ),
        );
        if (rect == null) continue;
        final center = rect.center;
        final d = (center - docOffset).distance;
        if (d < bestDist) {
          bestDist = d;
          bestRect = rect;
          bestId = node.id;
        }
      } catch (_) {
        continue;
      }
    }
    if (bestId == null || bestRect == null) return null;
    return _AnchorCandidate(nodeId: bestId, rect: bestRect);
  }

  static String _stickerTypeString(StickerType t) {
    switch (t) {
      case StickerType.text:
        return 'text';
      case StickerType.emoji:
        return 'emoji';
      case StickerType.image:
        return 'image';
    }
  }
}

class _AnchorCandidate {
  final String nodeId;
  final Rect rect;
  _AnchorCandidate({required this.nodeId, required this.rect});
}
