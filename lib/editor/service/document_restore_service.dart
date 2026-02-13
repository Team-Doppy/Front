import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../editor/component/app_image_node.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/component/divider_component.dart';
import '../../editor/component/link_component.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/config/editor_config.dart';
import '../../editor/data/draft.dart';
import '../../editor/utils/list_paragraph_meta.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/style/text_attributions.dart';
import 'package:super_editor/super_editor.dart';
import 'package:uuid/uuid.dart';

/// 문서 복원 서비스
/// Exported 데이터로부터 MutableDocument를 복원하는 역할
class DocumentRestoreService {
  /// DraftData가 있으면 그 ID를 반환하고, 없으면 새 UUID를 생성하여 반환한다.
  static String getOrCreateDraftId(DraftData? draftData) {
    if (draftData != null) {
      debugPrint(
        '[DocumentRestoreService] 🆔 DraftData의 draftId 사용: ${draftData.id}',
      );
      return draftData.id;
    } else {
      const uuid = Uuid();
      final newId = 'draft_${uuid.v4()}';
      debugPrint('[DocumentRestoreService] 🆔 새 UUID 기반 draftId 생성: $newId');
      return newId;
    }
  }

  /// DraftData로부터 MutableDocument를 복원한다.
  /// DraftData의 content(JSON 문자열)를 파싱하여 문서를 복원한다.
  /// 제목 노드가 없는데 title이 있으면 (첫 번째 텍스트를 제목으로 삼은 경우) 제목 노드를 자동 추가한다.
  /// 실패 시 빈 문서를 반환한다.
  MutableDocument restoreFromDraftData(DraftData draftData) {
    try {
      final exportedData =
          json.decode(draftData.content) as Map<String, dynamic>;
      var doc = rebuildDocumentForRead(exportedData);

      // 제목 노드가 없는데 draftData.title이 있으면 제목 노드 자동 추가 (첫 번째를 제목으로 삼은 경우)
      final title = (draftData.title).trim();
      if (title.isNotEmpty) {
        bool hasTitleNode = false;
        for (int i = 0; i < doc.length; i++) {
          final node = doc.getNodeAt(i);
          if (node != null &&
              node is ParagraphNode &&
              node.metadata[EditorConfig.titleNodeMetadataKey] == true) {
            hasTitleNode = true;
            break;
          }
        }
        if (!hasTitleNode) {
          final titleNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(title),
            metadata: <String, dynamic>{
              EditorConfig.titleNodeMetadataKey: true,
              'textAlign': 'left',
            },
          );
          final allNodes = <DocumentNode>[titleNode];
          for (int i = 0; i < doc.length; i++) {
            final n = doc.getNodeAt(i);
            if (n != null) allNodes.add(n);
          }
          doc = MutableDocument(nodes: allNodes);
          debugPrint(
            '[DocumentRestoreService] 제목 노드 없음 + title 있음 → 제목 노드 자동 추가',
          );
        }
      }

      return doc;
    } catch (e) {
      debugPrint('[DocumentRestoreService] DraftData 복원 실패: $e');
      // fallback to empty document
      return MutableDocument(
        nodes: [
          ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
        ],
      );
    }
  }

  /// Exported 데이터로부터 MutableDocument를 복구한다.
  MutableDocument rebuildDocumentForRead(Map<String, dynamic> exported) {
    // 저장 포맷(document | content 모두)과 과거 포맷까지 호환
    // 타입을 안전하게 검사하여 잘못된 캐스팅 예외 방지
    List nodes = const [];
    final dynamic doc = exported['document'];
    final dynamic content = exported['content'];
    if (doc is Map && doc['nodes'] is List) {
      nodes = (doc['nodes'] as List);
    } else if (content is Map && content['nodes'] is List) {
      nodes = (content['nodes'] as List);
    } else if (content is List) {
      nodes = content;
    } else {
      nodes = const [];
    }

    // 🎯 디버그: 첫 번째 paragraph 노드의 텍스트 확인
    if (nodes.isNotEmpty) {
      for (final raw in nodes) {
        if (raw is Map) {
          final m = raw.cast<String, dynamic>();
          final type = (m['type'] ?? '').toString();
          if (type == 'paragraph') {
            final text = (m['text'] ?? '').toString();
            debugPrint(
              '[DocumentRestoreService] 🔍 rebuildDocumentForRead: 첫 paragraph 노드 텍스트="$text"',
            );
            break;
          }
        }
      }
    }
    final rebuilt = <DocumentNode>[];
    final nodeService = NodeComponentService();

    // 스포일러 상태 복원을 위한 임시 저장소
    final spoilerNodes = <String>[];

    for (final raw in nodes) {
      if (raw is! Map) {
        // 알 수 없는 형태는 스킵
        continue;
      }
      final m = raw.cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final type = (m['type'] ?? '').toString();

      switch (type) {
        case 'paragraph':
          final text = (m['text'] ?? '').toString();
          final align = (m['align'] ?? 'left').toString();
          final spans = (m['spans'] as List?) ?? const [];
          final attributed = _buildAttributedText(
            text,
            spans,
          ); // ✅ spans에서 spoiler 처리됨

          final meta = <String, dynamic>{'textAlign': align};
          if (m['isTitle'] == true) {
            meta[EditorConfig.titleNodeMetadataKey] = true;
          }

          // 🎯 fontFamily를 메타데이터에서 추출하여 추가
          if (m['fontFamily'] != null) {
            final fontFamily = m['fontFamily'].toString();
            meta['fontFamily'] = fontFamily;
            debugPrint(
              '[DocumentRestoreService] 📖 JSON에서 fontFamily 읽기: $fontFamily (노드 ID: $id)',
            );
          }

          // 🎯 리스트 프리픽스 메타데이터 복원 (보기 모드 렌더링용)
          final listType = (m['listType'] ?? '').toString();
          if (listType == ListParagraphMeta.typeNumbered ||
              listType == ListParagraphMeta.typeBullet ||
              listType == ListParagraphMeta.typeChecklist ||
              listType == ListParagraphMeta.typeQuote) {
            meta[ListParagraphMeta.listType] = listType;
            if (listType == ListParagraphMeta.typeNumbered) {
              final idx = m['listIndex'];
              meta[ListParagraphMeta.listIndex] = (idx is int && idx >= 1)
                  ? idx
                  : int.tryParse(idx?.toString() ?? '') ?? 1;
            }
            if (listType == ListParagraphMeta.typeChecklist) {
              meta[ListParagraphMeta.checked] = m['checked'] == true;
            }
          }

          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
          break;

        case 'image':
          final data = (m['data'] as Map?)?.cast<String, dynamic>();
          final imageUrl = (m['url'] ?? data?['url'] ?? '').toString();
          final hasComments =
              (m['hasComments'] ?? data?['hasComments']) == true;
          final commentCount =
              (m['commentCount'] ?? data?['commentCount']) ?? 0;
          // 스포일러 정보 확인 (노드 레벨 또는 data 내부)
          final hasSpoiler =
              (m['spoiler'] == true) || (data?['spoiler'] == true);
          // 패딩 모드 복원 (노드 레벨 우선, data 내 보조)
          final String? paddingMode = (m['padding'] ?? data?['padding'])
              ?.toString();

          // NodeComponentService에 스포일러 상태 복원
          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          // 🎯 이미지 크기 메타데이터 복원 (shimmer 최적화)
          final imageDimensionsForSingle =
              m['imageDimensions'] as Map<String, dynamic>?;

          rebuilt.add(
            AppImageNode(
              id: id,
              imageUrl: imageUrl,
              altText: (m['altText'] ?? '').toString(),
              metadata: <String, dynamic>{
                'hasComments': hasComments,
                'commentCount': (commentCount is num)
                    ? commentCount.toInt()
                    : int.tryParse(commentCount.toString()) ?? 0,
                if (hasSpoiler) 'spoiler': true,
                if (paddingMode == 'full') 'padding': 'full',
                if (imageDimensionsForSingle != null &&
                    imageDimensionsForSingle.isNotEmpty)
                  'imageDimensions': imageDimensionsForSingle,
              },
            ),
          );
          break;

        case 'imageRow':
          final urls = ((m['urls'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();

          // 스포일러 정보 확인 (노드 레벨)
          final hasSpoiler = m['spoiler'] == true;

          // NodeComponentService에 스포일러 상태 복원
          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          // 🎯 노드 레벨 댓글 정보 파싱 (이미지 로우 전체)
          final hasComments = (m['hasComments'] ?? false) == true;
          final commentCount = (m['commentCount'] is num)
              ? (m['commentCount'] as num).toInt()
              : int.tryParse(m['commentCount']?.toString() ?? '0') ?? 0;

          // 🎯 imageCommentInfo 파싱 (각 이미지별 댓글 정보)
          final Map<String, Map<String, dynamic>> imageCommentInfo = {};
          try {
            // 서버에서 imageCommentInfo가 오는 경우 (data 내부 또는 노드 레벨)
            final data = m['data'] as Map<String, dynamic>?;
            final rawCommentInfo =
                (m['imageCommentInfo'] ?? data?['imageCommentInfo'])
                    as Map<String, dynamic>?;

            if (rawCommentInfo != null) {
              // 각 이미지 URL별로 댓글 정보 파싱
              for (final url in urls) {
                if (rawCommentInfo[url] is Map) {
                  final imgInfo = (rawCommentInfo[url] as Map)
                      .cast<String, dynamic>();
                  imageCommentInfo[url] = {
                    'mediaId': imgInfo['mediaId']?.toString(),
                    'hasComments': imgInfo['hasComments'] == true,
                    'commentCount': (imgInfo['commentCount'] is num)
                        ? (imgInfo['commentCount'] as num).toInt()
                        : int.tryParse(
                                imgInfo['commentCount']?.toString() ?? '0',
                              ) ??
                              0,
                  };
                }
              }
            }
          } catch (e) {
            debugPrint('[DocumentRestoreService] imageCommentInfo 파싱 실패: $e');
          }

          // 🎯 이미지 크기 메타데이터 복원 (shimmer 최적화)
          final imageDimensions = m['imageDimensions'] as Map<String, dynamic>?;

          // 메타데이터 구성
          final metadata = <String, dynamic>{
            if (hasSpoiler) 'spoiler': true,
            if (hasComments) 'hasComments': hasComments,
            if (commentCount > 0) 'commentCount': commentCount,
            if (imageCommentInfo.isNotEmpty)
              'imageCommentInfo': imageCommentInfo,
            if (imageDimensions != null && imageDimensions.isNotEmpty)
              'imageDimensions': imageDimensions,
          };

          rebuilt.add(
            ImageRowNode(
              id: id,
              imageUrls: urls,
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
              metadata: metadata.isNotEmpty ? metadata : null,
            ),
          );
          break;

        case 'pageViewImage':
        case 'pageviewImage':
        case 'page_view_image':
          final urls = ((m['imageUrls'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();

          // 스포일러 정보 확인
          final hasSpoiler = m['spoiler'] == true;

          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          // 노드 레벨 댓글 정보
          final hasComments = (m['hasComments'] ?? false) == true;
          final commentCount = (m['commentCount'] is num)
              ? (m['commentCount'] as num).toInt()
              : int.tryParse(m['commentCount']?.toString() ?? '0') ?? 0;

          // imageCommentInfo 파싱
          final Map<String, Map<String, dynamic>> imageCommentInfo = {};
          try {
            final data = m['data'] as Map<String, dynamic>?;
            final rawCommentInfo =
                (m['imageCommentInfo'] ?? data?['imageCommentInfo'])
                    as Map<String, dynamic>?;

            if (rawCommentInfo != null) {
              for (final url in urls) {
                if (rawCommentInfo[url] is Map) {
                  final imgInfo = (rawCommentInfo[url] as Map)
                      .cast<String, dynamic>();
                  imageCommentInfo[url] = {
                    'mediaId': imgInfo['mediaId']?.toString(),
                    'hasComments': imgInfo['hasComments'] == true,
                    'commentCount': (imgInfo['commentCount'] is num)
                        ? (imgInfo['commentCount'] as num).toInt()
                        : int.tryParse(
                                imgInfo['commentCount']?.toString() ?? '0',
                              ) ??
                              0,
                  };
                }
              }
            }
          } catch (e) {
            debugPrint(
              '[DocumentRestoreService] pageViewImage commentInfo 파싱 실패: $e',
            );
          }

          // 🎯 이미지 크기 메타데이터 복원
          final imageDimensions = m['imageDimensions'] as Map<String, dynamic>?;

          // 메타데이터 구성
          final pvMetadata = <String, dynamic>{
            if (hasSpoiler) 'spoiler': true,
            if (hasComments) 'hasComments': hasComments,
            if (commentCount > 0) 'commentCount': commentCount,
            if (imageCommentInfo.isNotEmpty)
              'imageCommentInfo': imageCommentInfo,
            if (imageDimensions != null && imageDimensions.isNotEmpty)
              'imageDimensions': imageDimensions,
          };

          rebuilt.add(
            PageViewImageNode(
              id: id,
              imageUrls: urls,
              metadata: pvMetadata.isNotEmpty ? pvMetadata : null,
            ),
          );
          break;

        case 'link': {
          final rawPadding = (m['padding'] ?? 'center').toString().trim();
          final rawViewMode = (m['viewMode'] ?? '').toString().trim();
          final linkMeta = <String, dynamic>{
            'padding': rawPadding == 'full' ? 'full' : 'center',
          };
          if (rawViewMode == 'compact') {
            linkMeta['viewMode'] = 'compact';
          }
          rebuilt.add(
            LinkNode(
              id: id,
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
              metadata: linkMeta,
            ),
          );
          break;
        }

        case 'divider':
          rebuilt.add(DividerNode(id: id));
          break;

        case 'clip':
          final data = (m['data'] as Map?)?.cast<String, dynamic>();
          final url = (m['url'] ?? data?['url'] ?? '').toString();
          final hasComments =
              (m['hasComments'] ?? data?['hasComments']) == true;
          final commentCount =
              (m['commentCount'] ?? data?['commentCount']) ?? 0;
          // 스포일러 정보 확인 (노드 레벨 또는 data 내부)
          final hasSpoiler =
              (m['spoiler'] == true) || (data?['spoiler'] == true);

          // NodeComponentService에 스포일러 상태 복원
          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          // 패딩 모드 복원 (노드 레벨 우선, data 내 보조, 기본값: 'center')
          final String paddingMode =
              (m['padding'] ?? data?['padding'])?.toString() ?? 'center';

          // 🎯 임시저장 복원: thumbnailPath, aspectRatio 복원
          final thumbnailPath = (data?['thumbnailPath'] ?? '').toString();
          final thumbnailUrl = data?['thumbnailUrl']?.toString();
          final aspectRatioValue = data?['aspectRatio'];
          double? aspectRatio;
          if (aspectRatioValue != null) {
            aspectRatio = (aspectRatioValue is num)
                ? aspectRatioValue.toDouble()
                : double.tryParse(aspectRatioValue.toString());
          }

          rebuilt.add(
            ClipNode(
              id: id,
              label: (m['label'] ?? '').toString(),
              colorHex: (m['color'] ?? '#FF5252').toString(),
              url: url,
              thumbnailPath: thumbnailPath,
              metadata: <String, dynamic>{
                'hasComments': hasComments,
                'commentCount': (commentCount is num)
                    ? commentCount.toInt()
                    : int.tryParse(commentCount.toString()) ?? 0,
                if (hasSpoiler) 'spoiler': true,
                'padding': paddingMode, // 🎯 항상 설정 (기본값: 'center')
                if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
                if (aspectRatio != null) 'aspectRatio': aspectRatio,
              },
            ),
          );
          break;

        case 'video':
          final data = (m['data'] as Map?)?.cast<String, dynamic>();
          final url = (m['url'] ?? data?['url'] ?? '').toString();
          final hasComments =
              (m['hasComments'] ?? data?['hasComments']) == true;
          final commentCount =
              (m['commentCount'] ?? data?['commentCount']) ?? 0;

          // 스포일러 정보 확인 (노드 레벨 또는 data 내부)
          final hasSpoiler =
              (m['spoiler'] == true) || (data?['spoiler'] == true);

          final finalId = id.isNotEmpty
              ? id
              : 'clip_${DateTime.now().millisecondsSinceEpoch}';

          // NodeComponentService에 스포일러 상태 복원
          if (hasSpoiler) {
            spoilerNodes.add(finalId);
          }

          // 패딩 모드 복원 (노드 레벨 우선, data 내 보조, 기본값: 'center')
          final String paddingMode =
              (m['padding'] ?? data?['padding'])?.toString() ?? 'center';

          // 🎯 임시저장 복원: thumbnailPath, aspectRatio 복원
          final thumbnailPath = (data?['thumbnailPath'] ?? '').toString();
          final thumbnailUrl = data?['thumbnailUrl']?.toString();
          final aspectRatioValue = data?['aspectRatio'];
          double? aspectRatio;
          if (aspectRatioValue != null) {
            aspectRatio = (aspectRatioValue is num)
                ? aspectRatioValue.toDouble()
                : double.tryParse(aspectRatioValue.toString());
          }

          rebuilt.add(
            ClipNode(
              id: finalId,
              label: (m['label'] ?? '').toString(),
              colorHex: (m['color'] ?? '#FF5252').toString(),
              url: url,
              thumbnailPath: thumbnailPath,
              metadata: <String, dynamic>{
                'hasComments': hasComments,
                'commentCount': (commentCount is num)
                    ? commentCount.toInt()
                    : int.tryParse(commentCount.toString()) ?? 0,
                if (hasSpoiler) 'spoiler': true,
                'padding': paddingMode, // 🎯 항상 설정 (기본값: 'center')
                if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
                if (aspectRatio != null) 'aspectRatio': aspectRatio,
              },
            ),
          );
          break;

        default:
          // 알 수 없는 노드는 문단으로 폴백
          rebuilt.add(ParagraphNode(id: id, text: AttributedText('[${type}]')));
      }
    }

    // 스포일러 상태를 NodeComponentService에 복원
    // 빌드 중 setState 방지를 위해 빌드 완료 후 실행
    if (spoilerNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final nodeId in spoilerNodes) {
          // 사용자가 해제한 스포일러는 다시 활성화하지 않음
          if (nodeService.isSpoilerDisabled(nodeId)) {
            continue;
          }
          nodeService.setSpoiler(nodeId, true);
          if (kDebugMode) {
            debugPrint('[DocumentRestoreService] 스포일러 상태 복원: $nodeId');
          }
        }
        if (kDebugMode) {
          debugPrint(
            '[DocumentRestoreService] 스포일러 상태 복원 완료: ${spoilerNodes.length}개 노드',
          );
        }
      });
    }

    return MutableDocument(nodes: rebuilt);
  }

  /// AttributedText의 spans를 복구한다.
  AttributedText _buildAttributedText(String text, List spans) {
    final attributed = AttributedText(text);

    // spans가 null이거나 비어있으면 기본 텍스트 반환
    if (spans.isEmpty) {
      return attributed;
    }

    try {
      for (final s in spans) {
        if (s == null) continue; // null 체크

        final m = (s as Map).cast<String, dynamic>();
        final start = (m['start'] as num?)?.toInt() ?? 0;
        final end = (m['end'] as num?)?.toInt() ?? start;

        // 텍스트 길이 범위 체크
        if (start < 0 || end > text.length || start > end) {
          debugPrint(
            '[DocumentRestoreService] Invalid span range: start=$start, end=$end, textLength=${text.length}',
          );
          continue;
        }

        final ann = (m['attrs'] as Map?)?.cast<String, dynamic>() ?? {};
        final atts = <Attribution>{};

        // 텍스트 스타일 속성들
        if (ann['bold'] == true) atts.add(boldAttribution);
        if (ann['italic'] == true) atts.add(italicsAttribution);
        if (ann['underline'] == true) atts.add(underlineAttribution);
        if (ann['strikethrough'] == true) atts.add(strikethroughAttribution);

        final fs = (ann['font_size'] as num?)?.toDouble();
        if (fs != null) atts.add(FontSizeAttribution(fs));

        final colorHex = ann['color'] as String?;
        if (colorHex != null && colorHex.isNotEmpty) {
          atts.add(ColorAttribution(_parseHexColor(colorHex)));
        }

        // 형광펜 속성
        final highlightHex = ann['highlight'] as String?;
        if (highlightHex != null && highlightHex.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              'DEBUG: DocumentRestoreService 형광펜 디코딩 - HEX: $highlightHex',
            );
          }
          final highlightColor = _parseHexColor(highlightHex);
          if (kDebugMode) {
            debugPrint(
              'DEBUG: DocumentRestoreService 형광펜 디코딩 - 색상: $highlightColor',
            );
          }
          atts.add(HighlightAttribution(highlightColor));
        }

        // 🎯 폰트 패밀리 속성 (span 단위 정교한 적용)
        final fontFamily = ann['fontFamily'] as String?;
        if (fontFamily != null && fontFamily.isNotEmpty) {
          atts.add(FontFamilyAttribution(fontFamily));
          debugPrint(
            '[DocumentRestoreService] 📖 Span에서 fontFamily 복원: $fontFamily (start=$start, end=$end)',
          );
        }

        // 스포일러 속성
        if (ann['spoiler'] == true) {
          atts.add(spoilerAttribution);
          if (kDebugMode) {
            debugPrint(
              '[DocumentRestoreService] spans에서 스포일러 발견: start=$start, end=$end',
            );
          }
        }

        // 속성을 텍스트에 적용
        for (final a in atts) {
          attributed.addAttribution(a, SpanRange(start, end - 1));
        }
      }
    } catch (e) {
      debugPrint('[DocumentRestoreService] Error building attributed text: $e');
      // 오류 발생 시 기본 텍스트 반환
    }

    return attributed;
  }

  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }
}
