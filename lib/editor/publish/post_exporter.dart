import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:flutter/material.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
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
    // 업로드 성공된 URL→imageId 매핑(전역 서비스)
    final Map<String, String> urlToId = NodeComponentService().urlToImageIdMap;
    final Set<int> usedImageIds = <int>{};

    int? _idFromUrl(String url) {
      final s = urlToId[url];
      if (s == null || s.isEmpty) return null;
      return int.tryParse(s);
    }

    String titleText = '';

    for (int i = 0; i < doc.length; i++) {
      final node = doc.getNodeAt(i);
      if (node == null) continue;

      if (node is ParagraphNode) {
        final meta = node.metadata;
        if ((meta['isTitle'] == true) && titleText.isEmpty) {
          titleText = node.text.text;
        }
        nodes.add({
          'id': node.id,
          'type': 'paragraph',
          'text': node.text.text,
          'align': meta['textAlign'] ?? 'center',
          'isTitle': meta['isTitle'] == true,
          'isSubheading': meta['isSubheading'] == true,
          'pin': meta['pin'] == true,
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
        final int? id = _idFromUrl(node.imageUrl);
        if (id != null) usedImageIds.add(id);
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
        for (final u in node.imageUrls) {
          final int? id = _idFromUrl(u);
          if (id != null) usedImageIds.add(id);
        }
        continue;
      }

      //   (커스텀)
      if (node is ClipNode) {
        nodes.add({
          'id': node.id,
          'type': 'clip',
          'label': node.label,
          'color': node.colorHex,
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
        case StickerType.drawing:
          // 벡터 그리기 데이터를 그대로 저장
          if (s.content is Map) {
            base['content'] = (s.content as Map).cast<String, dynamic>();
          }
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

    final String author = AuthProvider().username ?? '';
    if (author.isEmpty) {
      throw StateError('author is required');
    }

    //초안 뽑기
    final Map<String, dynamic> result = {
      'title':
          titleText.isNotEmpty
              ? titleText
              : (nodes.isNotEmpty
                  ? (nodes.first['text'] ?? '').toString()
                  : ''),
      'author': author,
      'content': {'nodes': nodes},
      'stickers': stickers,
    };

    return result;
  }

  /// 리치 텍스트(AttributedText)에서 spans를 추출한다.
  /// 현 단계에선 최소 스냅샷(전체 범위 기본 스타일)만 제공하고,
  /// 세부 스타일은 후속 단계에서 확장한다.
  static List<Map<String, dynamic>> _buildParagraphSpans(AttributedText text) {
    if (text.text.isEmpty) return <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> spans = <Map<String, dynamic>>[];

    Map<String, dynamic> attrsAt(int offset) {
      // offset이 범위를 벗어나면 빈 속성
      if (offset < 0 || offset >= text.text.length) return <String, dynamic>{};
      final atts = text.getAllAttributionsAt(offset);
      return _normalizeAttributions(atts);
    }

    int runStart = 0;
    Map<String, dynamic> prev = attrsAt(0);
    for (int i = 1; i <= text.text.length; i++) {
      // 마지막 i == length에서는 강제로 종료 스팬 배출
      final Map<String, dynamic> curr =
          (i == text.text.length) ? <String, dynamic>{} : attrsAt(i);
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
    ui.Color? highlight;

    for (final a in atts) {
      if (a == boldAttribution) {
        bold = true;
      } else if (a == italicsAttribution) {
        italic = true;
      } else if (a == underlineAttribution) {
        underline = true;
      } else if (a == strikethroughAttribution) {
        strike = true;
      } else if (a is HighlightAttribution) {
        // 형광펜 색상
        highlight = a.color;
      } else if (a is ColorAttribution) {
        // 텍스트 색상 (형광펜이 아닌 경우)
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
      if (highlight != null) 'highlight': _hexColor(highlight),
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
      case StickerType.drawing:
        return 'drawing';
      case StickerType.image:
        return 'image';
    }
  }

  /// 기본 내보내기 결과(base)에 공개 범위/썸네일/최종 제목/요약/생성시각 등을 덧붙여
  /// 최종 게시 페이로드를 구성한다. 서버 API 스펙에 맞춰 필수 필드들을 검증한다.
  static Map<String, dynamic> composeFinalPayload({
    required String thumbnailImageUrl,
    required Map<String, dynamic> base,
    DateTime? createdAt,
    bool? privateOnly = false,
    bool? publicOnly = false,
    List<int>? selectedGroupIds = const [],
  }) {
    // 1. 필수 필드 검증
    final String title = base['title']?.toString() ?? '';
    if (title.trim().isEmpty) {
      throw StateError('title is required for all access levels');
    }

    final dynamic content = base['content'];
    if (content == null) {
      throw StateError('content is required for all access levels');
    }

    // 2. 공개 범위에 따른 필수 필드 설정
    String accessLevel;
    List<int> sharedGroupIds;

    if (privateOnly == true) {
      accessLevel = 'PRIVATE';
      sharedGroupIds = [];
    } else if (publicOnly == true) {
      accessLevel = 'PUBLIC';
      sharedGroupIds = [];
    } else {
      accessLevel = 'GROUPS';
      sharedGroupIds = selectedGroupIds ?? [];

      // GROUPS 선택시 최소 1개 이상의 그룹 ID 필요
      if (sharedGroupIds.isEmpty) {
        throw StateError(
          'GROUPS access level requires at least one group ID in sharedGroupIds',
        );
      }
    }

    // 3. 기존 base를 복사하고 공개 범위 필드만 추가
    final Map<String, dynamic> result = <String, dynamic>{...base};

    // 4. 공개 범위 필수 필드 추가
    result['accessLevel'] = accessLevel;

    // 5. 그룹 공유시 필수 필드
    if (accessLevel == 'GROUPS' && sharedGroupIds.isNotEmpty) {
      result['sharedGroupIds'] = sharedGroupIds;
    }

    // 6. 썸네일 필수 필드 검증 및 추가
    if (thumbnailImageUrl.trim().isEmpty) {
      throw StateError('thumbnailImageUrl is required for all access levels');
    }
    result['thumbnailImageUrl'] = thumbnailImageUrl;

    // 7. usedImageIds 보강: base에 없으면 문서 노드/매핑으로 재생성, 썸네일 id도 병합
    try {
      final Set<int> usedIds = <int>{};
      final dynamic baseIds = base['usedImageIds'];
      if (baseIds is List) {
        for (final v in baseIds) {
          final int? n = (v is int) ? v : int.tryParse(v.toString());
          if (n != null) usedIds.add(n);
        }
      }

      final Map<String, String> urlToId =
          NodeComponentService().urlToImageIdMap;

      // 썸네일 URL → id 매핑 병합
      final String? thumbIdStr = urlToId[thumbnailImageUrl];
      final int? thumbId = thumbIdStr == null ? null : int.tryParse(thumbIdStr);
      if (thumbId != null) usedIds.add(thumbId);

      // 문서 노드를 항상 스캔하여 보강(중복은 Set으로 자동 제거)
      try {
        final dynamic content = base['content'];
        final List<dynamic> nodes =
            (content is Map)
                ? List<dynamic>.from(content['nodes'] as List? ?? const [])
                : const [];
        for (final n in nodes) {
          if (n is! Map) continue;
          final String type = (n['type'] ?? '').toString();
          if (type == 'image') {
            final String url = (n['url'] ?? '').toString();
            final String? idStr = urlToId[url];
            final int? id = idStr == null ? null : int.tryParse(idStr);
            if (id != null) usedIds.add(id);
          } else if (type == 'imageRow') {
            final List<dynamic> urls = List<dynamic>.from(
              n['urls'] ?? const [],
            );
            for (final u in urls) {
              final String url = u.toString();
              final String? idStr = urlToId[url];
              final int? id = idStr == null ? null : int.tryParse(idStr);
              if (id != null) usedIds.add(id);
            }
          }
        }
      } catch (_) {}

      result['usedImageIds'] = usedIds.toList()..sort();
    } catch (_) {}

    print('==============================================');
    print('Final API Payload (Server Spec Compliant):');
    print('Title: $title');
    print('AccessLevel: $accessLevel');
    if (accessLevel == 'GROUPS') {
      print('SharedGroupIds: $sharedGroupIds');
    }
    print('Thumbnail: ${result['thumbnailImageUrl'] ?? 'none'}');
    print('UsedImageIds: ${result['usedImageIds'] ?? 'none'}');
    print(JsonExport.encode(result, pretty: true));

    return result;
  }
}

class _AnchorCandidate {
  final String nodeId;
  final Rect rect;
  _AnchorCandidate({required this.nodeId, required this.rect});
}
