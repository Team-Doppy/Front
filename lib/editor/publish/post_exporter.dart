import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:flutter/material.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
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

  /// 문서에서 제목 추출
  static String getTitleFromDocument(MutableDocument document) {
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && node.metadata['isTitle'] == true) {
        return node.text.text.trim();
      }
    }
    return '';
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

    String titleText = '';

    for (int i = 0; i < doc.length; i++) {
      final node = doc.getNodeAt(i);
      if (node == null) continue;

      if (node is ParagraphNode) {
        final meta = node.metadata;
        if ((meta['isTitle'] == true) && titleText.isEmpty) {
          titleText = node.text.text;
        }

        // Paragraph 기반 멘션 노드 처리
        if (meta['mention'] == true) {
          final List<dynamic> namesDyn =
              (meta['usernames'] as List?) ?? const [];
          final List<String> names = namesDyn.map((e) => e.toString()).toList();
          nodes.add({'id': node.id, 'type': 'mention', 'usernames': names});
          continue;
        }

        final align = meta['textAlign'] as String?;
        final isTitle = meta['isTitle'] == true;
        final fontFamily = meta['fontFamily'] as String?;

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'paragraph',
          'text': node.text.text,
          'spans': _buildParagraphSpans(node.text), // ✅ spans에 spoiler 정보 포함됨
        };

        // 필요한 필드만 추가
        if (align != null && align != 'center') {
          nodeMap['align'] = align;
        }
        if (isTitle) {
          nodeMap['isTitle'] = true;
        }
        if (fontFamily != null && fontFamily.isNotEmpty) {
          nodeMap['fontFamily'] = fontFamily;
        }
        // spoiler는 spans에서 처리하므로 노드 레벨에서는 제거

        nodes.add(nodeMap);
        continue;
      }

      // ImageNode (SuperEditor 내장)
      if (node is ImageNode) {
        // metadata에서 mediaId/spoiler 추출
        Map<String, dynamic>? meta;
        try {
          meta = (node as dynamic).metadata as Map<String, dynamic>?;
        } catch (_) {
          meta = null;
        }
        final mediaId = meta != null ? (meta['mediaId']?.toString()) : null;
        final paddingMode = meta != null ? (meta['padding']?.toString()) : null;

        // 스포일러 확인: NodeComponentService 우선, metadata는 보조
        final nodeService = NodeComponentService();
        bool hasSpoiler;

        if (nodeService.isSpoiler(node.id)) {
          hasSpoiler = true;
        } else if (nodeService.isSpoilerDisabled(node.id)) {
          hasSpoiler = false;
        } else {
          hasSpoiler = meta != null && meta['spoiler'] == true;
        }

        final dataMap = <String, dynamic>{'url': node.imageUrl};

        if (mediaId != null && mediaId.isNotEmpty) {
          dataMap['mediaId'] = int.tryParse(mediaId) ?? mediaId;
        }
        // true일 때만 추가 (false는 키 없음으로 표현)
        if (hasSpoiler) {
          dataMap['spoiler'] = true;
        }

        final out = {'id': node.id, 'type': 'image', 'data': dataMap};
        // 패딩 모드: 기본(center)일 때는 생략, full만 저장
        if (paddingMode == 'full') {
          out['padding'] = 'full';
          print('[PostExporter] ImageNode ${node.id} padding=full 저장');
        }
        nodes.add(out);
        continue;
      }

      // ImageRowNode (프로젝트에 존재하는 경우)
      if (node is ImageRowNode) {
        // 스포일러 확인: metadata 또는 NodeComponentService
        bool hasSpoiler = false;
        final meta = node.metadata;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        // 각 이미지별 mediaId 추출 (댓글 정보는 제외)
        final imageCommentInfo =
            meta['imageCommentInfo'] as Map<String, dynamic>?;
        final List<Map<String, dynamic>> images = [];
        bool hasMediaId = false;

        if (imageCommentInfo != null && imageCommentInfo.isNotEmpty) {
          for (final imageUrl in node.imageUrls) {
            final imgData = <String, dynamic>{'url': imageUrl};

            if (imageCommentInfo[imageUrl] is Map) {
              final imgInfo =
                  imageCommentInfo[imageUrl] as Map<String, dynamic>;
              final mediaId = imgInfo['mediaId']?.toString();

              if (mediaId != null && mediaId.isNotEmpty) {
                imgData['mediaId'] = int.tryParse(mediaId) ?? mediaId;
                hasMediaId = true;
              }
            }

            images.add(imgData);
          }
        } else {
          // mediaId 정보가 없으면 기본 URL만
          for (final imageUrl in node.imageUrls) {
            images.add({'url': imageUrl});
          }
        }

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'imageRow',
          'urls': node.imageUrls,
        };

        if (node.spacing != 4.0) {
          nodeMap['spacing'] = node.spacing;
        }
        if (hasMediaId) {
          nodeMap['data'] = {'images': images};
        }
        if (hasSpoiler) {
          nodeMap['spoiler'] = true;
        }

        nodes.add(nodeMap);
        continue;
      }

      // Video(ClipNode) → 서버 규격: { type: "video", data: { mediaId, url } }
      if (node is ClipNode) {
        final meta = node.metadata;
        final mediaId = meta['mediaId']?.toString();

        // 스포일러 확인: metadata 또는 NodeComponentService
        bool hasSpoiler = false;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        final dataMap = <String, dynamic>{'url': node.url};

        if (mediaId != null && mediaId.isNotEmpty) {
          dataMap['mediaId'] = int.tryParse(mediaId) ?? mediaId;
        }
        if (hasSpoiler) {
          dataMap['spoiler'] = true;
        }

        nodes.add({'id': node.id, 'type': 'video', 'data': dataMap});
        continue;
      }

      // DividerNode
      if (node is DividerNode) {
        nodes.add({'id': node.id, 'type': 'divider'});
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
            // 로컬 오프셋(px) 기준 앵커: 문서 좌표(top-left)에서 노드 좌상단을 뺀 값
            final double localX = (s.position.dx - rect.left);
            final double localY = (s.position.dy - rect.top);
            anchor = {
              'nodeId': nodeId,
              'localX': localX,
              'localY': localY,
              'refW': rect.width,
            };
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

    final title = getTitleFromDocument(doc);
    //초안 뽑기
    final Map<String, dynamic> result = {
      'title': title,
      'author': author,
      'content': {'nodes': nodes, 'stickers': stickers},
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
    bool spoiler = false; // ✅ spans에 포함
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
      } else if (a == spoilerAttribution) {
        spoiler = true; // ✅ spoiler를 spans에 포함
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
      if (spoiler) 'spoiler': true, // ✅ spans에 포함
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
    bool? friendsOnly = false,
    List<int>? selectedGroupIds = const [],
    int? categoryId, // 카테고리 ID (필수)
    bool skipValidation = false, // 임시저장용 검증 생략 플래그
  }) {
    // 1. 필수 필드 검증
    final String title = base['title']?.toString() ?? '';
    if (!skipValidation && title.trim().isEmpty) {
      throw StateError('title is required for all access levels');
    }

    final dynamic content = base['content'];
    if (!skipValidation && content == null) {
      throw StateError('content is required for all access levels');
    }

    // 카테고리 ID 검증 (발행 시에만 필수, 0은 미지정 카테고리로 유효)
    if (!skipValidation && categoryId == null) {
      throw StateError('categoryId is required for publishing');
    }

    // 2. 공개 범위에 따른 필수 필드 설정
    String accessLevel;
    List<int> sharedGroupIds;

    // 디버그 로깅: 파라미터 확인
    debugPrint('===== [composeFinalPayload] 파라미터 =====');
    debugPrint('privateOnly: $privateOnly');
    debugPrint('publicOnly: $publicOnly');
    debugPrint('selectedGroupIds: $selectedGroupIds');
    debugPrint('friendsOnly: $friendsOnly');

    if (privateOnly == true) {
      accessLevel = 'PRIVATE';
      sharedGroupIds = [];
      debugPrint('[composeFinalPayload] → PRIVATE 선택됨');
    } else if (publicOnly == true) {
      accessLevel = 'PUBLIC';
      sharedGroupIds = [];
      debugPrint('[composeFinalPayload] → PUBLIC 선택됨');
    } else if (friendsOnly == true) {
      accessLevel = 'FRIENDS';
      sharedGroupIds = [];
      debugPrint('[composeFinalPayload] → FRIENDS 선택됨');
    } else {
      accessLevel = 'GROUPS';
      sharedGroupIds = selectedGroupIds ?? [];
      debugPrint('[composeFinalPayload] → GROUPS 선택됨 (그룹: $sharedGroupIds)');

      // GROUPS 선택시 최소 1개 이상의 그룹 ID 필요 (발행 시에만 검증)
      if (!skipValidation && sharedGroupIds.isEmpty) {
        throw StateError(
          'GROUPS access level requires at least one group ID in sharedGroupIds',
        );
      }
    }

    // 3. 기존 base를 복사하되, 공개 범위 관련 필드는 제거하고 새로 설정
    final Map<String, dynamic> result = <String, dynamic>{...base};

    // 기존 공개 범위 필드 완전히 제거 (덮어쓰기 보장)
    result.remove('accessLevel');
    result.remove('sharedGroupIds');

    // 4. 공개 범위 필수 필드 추가
    result['accessLevel'] = accessLevel;

    // 5. 그룹 공유시 필수 필드 (GROUPS인 경우만 추가)
    if (accessLevel == 'GROUPS' && sharedGroupIds.isNotEmpty) {
      result['sharedGroupIds'] = sharedGroupIds;
    } else {
      // GROUPS가 아니면 sharedGroupIds는 완전히 제거
      result.remove('sharedGroupIds');
    }

    // 6. 카테고리 ID 추가 (필수)
    if (categoryId != null) {
      result['categoryId'] = categoryId;
    }

    // 7. summary 필드 추가 (base에 있으면 사용, 없으면 excerpt 사용)
    final String summary =
        base['summary']?.toString() ?? base['excerpt']?.toString() ?? '';
    result['summary'] = summary;

    // 8. 썸네일 필수 필드 검증 및 추가
    if (!skipValidation && thumbnailImageUrl.trim().isEmpty) {
      throw StateError('thumbnailImageUrl is required for all access levels');
    }
    result['thumbnailImageUrl'] = thumbnailImageUrl;

    // 9. usedImageUrls → URL 문자열로 전환: 문서 노드/썸네일에서 URL을 수집해 문자열 배열로 제공
    try {
      final Set<String> usedUrls = <String>{};

      // 문서 노드에서 URL 수집
      final dynamic content = base['content'];
      final List<dynamic> nodes =
          (content is Map)
              ? List<dynamic>.from(content['nodes'] as List? ?? const [])
              : const [];
      for (final n in nodes) {
        if (n is! Map) continue;
        final String type = (n['type'] ?? '').toString();
        if (type == 'image') {
          // data.url 또는 url 필드에서 추출
          final data = n['data'] as Map<String, dynamic>?;
          final String url = (data?['url'] ?? n['url'] ?? '').toString();
          if (url.isNotEmpty) usedUrls.add(url);
        } else if (type == 'imageRow') {
          final List<dynamic> urls = List<dynamic>.from(n['urls'] ?? const []);
          for (final u in urls) {
            final String url = u.toString();
            if (url.isNotEmpty) usedUrls.add(url);
          }
        } else if (type == 'video') {
          // data.url에서 추출
          final data = n['data'] as Map<String, dynamic>?;
          final String url = (data?['url'] ?? '').toString();
          if (url.isNotEmpty) usedUrls.add(url);
        }
      }

      // 썸네일 URL도 포함(이전 로직에서 썸네일 ID를 병합했었음)
      if (thumbnailImageUrl.trim().isNotEmpty) {
        usedUrls.add(thumbnailImageUrl.trim());
      }

      // 결과 키는 기존과 동일하게 유지(호환)하되 값은 URL 문자열 목록로 제공
      result['usedImageUrls'] = usedUrls.toList();
    } catch (e) {
      print('❌ usedImageUrls 수집 실패: $e');
    }

    print('==============================================');
    print('Final API Payload (Server Spec Compliant):');
    print('Title: $title');
    print('AccessLevel: $accessLevel');
    if (accessLevel == 'GROUPS') {
      print('SharedGroupIds: $sharedGroupIds');
    }
    print('Thumbnail: ${result['thumbnailImageUrl'] ?? 'none'}');
    print('UsedImageUrls: ${result['usedImageUrls'] ?? 'none'}');
    print(JsonExport.encode(result, pretty: true));

    return result;
  }
}

class _AnchorCandidate {
  final String nodeId;
  final Rect rect;
  _AnchorCandidate({required this.nodeId, required this.rect});
}
