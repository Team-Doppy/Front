import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/nodes/mention_node.dart';
import 'package:doppy/editor/component/clip_component.dart' show ClipNode;
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/font_preload_service.dart';
import 'package:doppy/editor/style/font_catalog.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/editor/style/text_attributions.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:video_player/video_player.dart';

/// 읽기 전용 포스트 복구 서비스
/// PostReaderScreen에서 사용하는 MutableDocument 복원 로직
class PostReaderService {
  bool _isDebug() {
    var v = false;
    assert(() {
      v = true;
      return true;
    }());
    return v;
  }

  void _d(String msg) {
    if (_isDebug()) debugPrint(msg);
  }

  /// Exported 데이터로부터 읽기 전용 MutableDocument를 복구한다.
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
              '[PostReaderService] 🔍 rebuildDocumentForRead: 첫 paragraph 노드 텍스트="$text"',
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
          final align = (m['align'] ?? 'center').toString();
          final spans = (m['spans'] as List?) ?? const [];
          final attributed = _buildAttributedText(
            text,
            spans,
          ); // ✅ spans에서 spoiler 처리됨

          final meta = <String, dynamic>{'textAlign': align};

          // 🎯 fontFamily를 메타데이터에서 추출하여 추가
          if (m['fontFamily'] != null) {
            final fontFamily = m['fontFamily'].toString();
            meta['fontFamily'] = fontFamily;
            debugPrint(
              '[PostReaderService] 📖 JSON에서 fontFamily 읽기: $fontFamily (노드 ID: $id)',
            );
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
          final String? paddingMode =
              (m['padding'] ?? data?['padding'])?.toString();
          _d('[PostReaderService] ImageNode $id padding=$paddingMode');

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
                'commentCount':
                    (commentCount is num)
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
          final urls =
              ((m['urls'] as List?) ?? const [])
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
          final commentCount =
              (m['commentCount'] is num)
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
                  final imgInfo =
                      (rawCommentInfo[url] as Map).cast<String, dynamic>();
                  imageCommentInfo[url] = {
                    'mediaId': imgInfo['mediaId']?.toString(),
                    'hasComments': imgInfo['hasComments'] == true,
                    'commentCount':
                        (imgInfo['commentCount'] is num)
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
            debugPrint('[PostReaderService] imageCommentInfo 파싱 실패: $e');
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
          final urls =
              ((m['imageUrls'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList();

          // 스포일러 정보 확인
          final hasSpoiler = m['spoiler'] == true;

          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          // 노드 레벨 댓글 정보
          final hasComments = (m['hasComments'] ?? false) == true;
          final commentCount =
              (m['commentCount'] is num)
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
                  final imgInfo =
                      (rawCommentInfo[url] as Map).cast<String, dynamic>();
                  imageCommentInfo[url] = {
                    'mediaId': imgInfo['mediaId']?.toString(),
                    'hasComments': imgInfo['hasComments'] == true,
                    'commentCount':
                        (imgInfo['commentCount'] is num)
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
              '[PostReaderService] pageViewImage commentInfo 파싱 실패: $e',
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

        case 'link':
          rebuilt.add(
            LinkNode(
              id: id,
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
            ),
          );
          break;

        case 'mention':
          // MentionNode로 복구
          final usernames =
              ((m['usernames'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList();
          final textAlign = (m['align'] ?? 'center').toString();
          final fontSize = (m['fontSize'] as num?)?.toDouble();

          final mentionMetadata = <String, dynamic>{'textAlign': textAlign};
          if (fontSize != null) {
            mentionMetadata['fontSize'] = fontSize;
          }

          rebuilt.add(
            MentionNode(
              id: id,
              usernames: usernames,
              metadata: mentionMetadata,
            ),
          );
          break;

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
            aspectRatio =
                (aspectRatioValue is num)
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
                'commentCount':
                    (commentCount is num)
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

          final finalId =
              id.isNotEmpty
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
            aspectRatio =
                (aspectRatioValue is num)
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
                'commentCount':
                    (commentCount is num)
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
            debugPrint('[PostReaderService] 스포일러 상태 복원: $nodeId');
          }
        }
        if (kDebugMode) {
          debugPrint(
            '[PostReaderService] 스포일러 상태 복원 완료: ${spoilerNodes.length}개 노드',
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
            '[PostReaderService] Invalid span range: start=$start, end=$end, textLength=${text.length}',
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
            debugPrint('DEBUG: PostReaderService 형광펜 디코딩 - HEX: $highlightHex');
          }
          final highlightColor = _parseHexColor(highlightHex);
          if (kDebugMode) {
            debugPrint(
              'DEBUG: PostReaderService 형광펜 디코딩 - 색상: $highlightColor',
            );
          }
          atts.add(HighlightAttribution(highlightColor));
        }

        // 🎯 폰트 패밀리 속성 (span 단위 정교한 적용)
        final fontFamily = ann['fontFamily'] as String?;
        if (fontFamily != null && fontFamily.isNotEmpty) {
          atts.add(FontFamilyAttribution(fontFamily));
          debugPrint(
            '[PostReaderService] 📖 Span에서 fontFamily 복원: $fontFamily (start=$start, end=$end)',
          );
        }

        // 스포일러 속성
        if (ann['spoiler'] == true) {
          atts.add(spoilerAttribution);
          if (kDebugMode) {
            debugPrint(
              '[PostReaderService] spans에서 스포일러 발견: start=$start, end=$end',
            );
          }
        }

        // 속성을 텍스트에 적용
        for (final a in atts) {
          attributed.addAttribution(a, SpanRange(start, end - 1));
        }
      }
    } catch (e) {
      debugPrint('[PostReaderService] Error building attributed text: $e');
      // 오류 발생 시 기본 텍스트 반환
    }

    return attributed;
  }

  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }

  /// 컨텐츠에서 이미지 URL을 추출한다 (포맷 변화에 견고)
  List<String> extractImageUrls(Map<String, dynamic> content) {
    final List<String> imageUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];

    for (final raw in nodes) {
      if (imageUrls.length >= 64) break; // 안전 상한

      final m = (raw as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();
      final data = (m['data'] as Map?)?.cast<String, dynamic>();

      bool addSingle(String? u) {
        final s = (u ?? '').toString();
        if (s.isNotEmpty) {
          imageUrls.add(s);
          return true;
        }
        return false;
      }

      if (type == 'image' || type == 'img' || type == 'single_image') {
        // url 필드 우선, 없으면 data.url
        if (!addSingle(m['url'])) {
          addSingle(data?['url']);
        }
      } else if (type == 'imageRow' ||
          type == 'image_row' ||
          type == 'row_image') {
        // urls 또는 data.urls
        final rawUrls =
            (m['urls'] as List?) ?? (data?['urls'] as List?) ?? const [];
        for (final u in rawUrls) {
          if (imageUrls.length >= 64) break;
          addSingle(u?.toString());
        }
      }
    }

    _d('[PostReaderService] 이미지 URL 추출 완료: ${imageUrls.length}개');
    return imageUrls;
  }

  /// 컨텐츠에서 클립(영상) URL을 추출한다
  List<String> extractClipUrls(Map<String, dynamic> content) {
    final List<String> clipUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];

    for (final raw in nodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();

      if (type == 'clip' || type == 'video') {
        // video 타입도 포함
        final data = m['data'] as Map<String, dynamic>?;
        final url = (data?['url'] ?? m['url'] ?? '').toString();
        if (url.isNotEmpty) clipUrls.add(url);
      }
    }

    _d('[PostReaderService] 클립 URL 추출 완료: ${clipUrls.length}개');
    return clipUrls;
  }

  /// 첫 N개 미디어 노드(이미지+영상 합쳐서)에서 모든 미디어 URL을 추출한다
  Map<String, List<String>> extractFirstMediaUrls(
    Map<String, dynamic> content, {
    int mediaNodeCount = 3,
  }) {
    final List<String> imageUrls = [];
    final List<String> clipUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];
    int mediaNodeCounter = 0;

    bool addSingleImage(String? u) {
      final s = (u ?? '').toString();
      if (s.isNotEmpty && s.startsWith('http')) {
        imageUrls.add(s);
        return true;
      }
      return false;
    }

    bool addSingleClip(String? u) {
      final s = (u ?? '').toString();
      if (s.isNotEmpty && s.startsWith('http')) {
        clipUrls.add(s);
        return true;
      }
      return false;
    }

    for (final raw in nodes) {
      if (mediaNodeCounter >= mediaNodeCount) break;

      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();
      final data = (m['data'] as Map?)?.cast<String, dynamic>();

      bool isMediaNode = false;

      // 이미지 노드 처리
      if (type == 'image' || type == 'img' || type == 'single_image') {
        isMediaNode = true;
        if (!addSingleImage(m['url'])) {
          addSingleImage(data?['url']);
        }
      } else if (type == 'imageRow' ||
          type == 'image_row' ||
          type == 'row_image') {
        isMediaNode = true;
        final rawUrls =
            (m['urls'] as List?) ?? (data?['urls'] as List?) ?? const [];
        for (final u in rawUrls) {
          if (imageUrls.length >= 64) break;
          addSingleImage(u?.toString());
        }
      } else if (type == 'pageViewImage' ||
          type == 'page_view_image' ||
          type == 'pageviewImage') {
        isMediaNode = true;
        final rawUrls = (m['imageUrls'] as List?) ?? const [];
        for (final u in rawUrls) {
          if (imageUrls.length >= 64) break;
          addSingleImage(u?.toString());
        }
      }
      // 영상 노드 처리
      else if (type == 'clip' || type == 'video') {
        isMediaNode = true;
        final url = (data?['url'] ?? m['url'] ?? '').toString();
        addSingleClip(url);
      }

      // 미디어 노드인 경우에만 카운터 증가 (이미지+영상 합쳐서 카운트)
      if (isMediaNode) {
        mediaNodeCounter++;
      }
    }

    _d(
      '[PostReaderService] 🎯 첫 $mediaNodeCount개 미디어 노드(이미지+영상 합쳐서)에서 URL 추출 완료: 이미지 ${imageUrls.length}개, 비디오 ${clipUrls.length}개',
    );
    if (_isDebug()) {
      if (imageUrls.isNotEmpty) {
        debugPrint(
          '[PostReaderService] 🖼️ 추출된 이미지 URL: ${imageUrls.join(", ")}',
        );
      }
      if (clipUrls.isNotEmpty) {
        debugPrint(
          '[PostReaderService] 🎬 추출된 비디오 URL: ${clipUrls.join(", ")}',
        );
      }
    }

    return {'images': imageUrls, 'clips': clipUrls};
  }

  /// 첫 N개 미디어 노드에서 이미지 URL을 추출한다 (하위 호환성)
  List<String> extractTopImageUrls(
    Map<String, dynamic> content, {
    int mediaNodeCount = 3,
  }) {
    final result = extractFirstMediaUrls(
      content,
      mediaNodeCount: mediaNodeCount,
    );
    return result['images'] ?? [];
  }

  /// 첫 N개 미디어 노드에서 비디오 URL을 추출한다 (하위 호환성)
  List<String> extractTopClipUrls(
    Map<String, dynamic> content, {
    int mediaNodeCount = 3,
  }) {
    final result = extractFirstMediaUrls(
      content,
      mediaNodeCount: mediaNodeCount,
    );
    return result['clips'] ?? [];
  }

  /// 위쪽에 있는 스티커 이미지 URL 추출 (yPx 기준으로 정렬하여 상위 스티커 선택)
  List<String> extractTopStickerImageUrls(Map<String, dynamic> content) {
    final List<String> stickerUrls = [];
    final stickers = (content['stickers'] as List?) ?? [];

    if (stickers.isEmpty) {
      return stickerUrls;
    }

    // 스티커를 yPx 기준으로 정렬하기 위한 리스트
    final List<Map<String, dynamic>> sortedStickers = [];

    for (final sticker in stickers) {
      if (sticker is! Map) continue;
      final m = sticker.cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();

      // 이미지 타입 스티커만 처리
      if (type != 'image') continue;

      final contentData = m['content'];
      String? url;

      // 레거시 지원: content가 Map, String, 또는 다른 형태일 수 있음
      if (contentData is Map) {
        // ✅ URL + 크기 정보 (PNG 드로잉) 또는 레거시 {url: ...}
        url = (contentData['url'] ?? '').toString();
      } else if (contentData is String) {
        // 레거시: content가 직접 URL 문자열인 경우
        url = contentData;
      }

      // URL이 있는 스티커만 처리 (bytes는 제외)
      if (url == null || url.isEmpty) continue;

      // yPx 값을 가져옴 (positionFallback 또는 anchor 기준)
      double yPx = double.infinity; // 기본값은 무한대 (아래쪽)

      final positionFallback =
          (m['positionFallback'] as Map?)?.cast<String, dynamic>();
      if (positionFallback != null) {
        final y = (positionFallback['yPx'] as num?)?.toDouble();
        if (y != null) {
          yPx = y;
        }
      } else {
        // anchor가 있는 경우, 일단 0으로 설정 (추후 개선 가능)
        final anchor = (m['anchor'] as Map?)?.cast<String, dynamic>();
        if (anchor != null) {
          yPx = 0.0; // anchor가 있는 경우 임시로 0으로 설정
        }
      }

      sortedStickers.add({'url': url, 'yPx': yPx});
    }

    // yPx 기준으로 정렬 (작은 값이 위쪽)
    sortedStickers.sort((a, b) {
      final yA = (a['yPx'] as num?)?.toDouble() ?? double.infinity;
      final yB = (b['yPx'] as num?)?.toDouble() ?? double.infinity;
      return yA.compareTo(yB);
    });

    // 상위 스티커들의 URL 추출 (최대 10개)
    for (final sticker in sortedStickers.take(10)) {
      final url = (sticker['url'] ?? '').toString();
      if (url.isNotEmpty) {
        stickerUrls.add(url);
      }
    }

    _d('[PostReaderService] 🎨 위쪽 스티커 이미지 URL 추출: ${stickerUrls.length}개');

    return stickerUrls;
  }

  /// 문서에서 사용된 폰트 추출
  Set<String> extractUsedFonts(Map<String, dynamic> content) {
    final Set<String> fontIdentifiers = {};
    final nodes = (content['nodes'] as List?) ?? [];

    for (final raw in nodes) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();

      if (type == 'paragraph') {
        // 노드 레벨 fontFamily
        if (m['fontFamily'] != null) {
          fontIdentifiers.add(m['fontFamily'].toString());
        }

        // spans 레벨 fontFamily
        final spans = (m['spans'] as List?) ?? [];
        for (final span in spans) {
          if (span is Map && span['fontFamily'] != null) {
            fontIdentifiers.add(span['fontFamily'].toString());
          }
        }
      }
    }

    debugPrint(
      '[PostReaderService] 🔤 문서에서 사용된 폰트 추출: ${fontIdentifiers.length}개 - ${fontIdentifiers.join(", ")}',
    );
    return fontIdentifiers;
  }

  /// 실패해도 계속 진행 (에러는 로그만 남김)
  /// 첫 N개 미디어 노드(이미지+영상 합쳐서)에 있는 모든 미디어를 프리로드
  /// 위쪽에 있는 스티커 이미지도 함께 프리로드
  Future<void> preloadTopMedia(
    BuildContext context,
    Map<String, dynamic> content, {
    int mediaNodeCount = 3,
  }) async {
    // 첫 N개 미디어 노드(이미지+영상 합쳐서)에서 모든 미디어 URL 추출
    final mediaUrls = extractFirstMediaUrls(
      content,
      mediaNodeCount: mediaNodeCount,
    );
    final imageUrls = mediaUrls['images'] ?? [];
    final clipUrls = mediaUrls['clips'] ?? [];

    // 위쪽 스티커 이미지 URL 추출
    final stickerImageUrls = extractTopStickerImageUrls(content);

    if (imageUrls.isEmpty && clipUrls.isEmpty && stickerImageUrls.isEmpty) {
      debugPrint('[PostReaderService] ⚠️ 프리로드할 미디어가 없습니다');
      // 🎯 미디어가 없어도 폰트는 동기적으로 프리로드
      await _preloadFonts(context, content);
      return;
    }

    // 🎯 눈에 잘 띄는 동기 프리로드 시작 로그
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🚀 [동기 프리로드 시작] 첫 $mediaNodeCount개 미디어 노드');
    debugPrint('   📸 이미지: ${imageUrls.length}개');
    debugPrint('   🎬 비디오: ${clipUrls.length}개');
    debugPrint('   🎨 스티커: ${stickerImageUrls.length}개');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('');

    // 🎯 이미지와 비디오, 스티커를 순차 실행으로 프리로드 (Future.wait 제거 - dispose 안전성)
    final decodeWidth = EditorImageProvider.readingDecodeWidth(
      context,
      MediaQuery.sizeOf(context).width,
    );

    // 🎯 Future.wait는 중단 불가능하므로, 순차 실행으로 변경 (dispose 안전성)
    // 이미지와 스티커는 순차 실행, 비디오는 병렬 실행 (이미 순차 내부 처리)

    // 이미지 프리로드 (순차 실행)
    if (imageUrls.isNotEmpty) {
      for (final url in imageUrls) {
        // 🎯 context dispose 체크
        if (!context.mounted) {
          debugPrint('[PostReaderService] ⚠️ context dispose됨 - 이미지 프리로드 중단');
          return;
        }
        try {
          final built = EditorImageProvider.build(
            url: url,
            isEditing: false, // 읽기 모드
            // ✅ 읽기 모드도 decodeWidth를 줘서 원본(대용량) 디코딩/캐시 점유를 줄이고,
            // 홈 화면 썸네일/배경 캐시가 밀려나는 현상을 완화한다.
            decodeWidth: decodeWidth,
          );
          // 🎯 effectiveProvider를 프리로드 (렌더링 시 사용하는 것과 정확히 동일)
          await precacheImage(built.effectiveProvider, context);
          debugPrint('[PostReaderService] ✅ 이미지 프리로드 완료: $url');
        } catch (e) {
          if (e.toString().contains('dispose') ||
              e.toString().contains('mounted')) {
            debugPrint('[PostReaderService] ⚠️ context dispose로 인한 중단: $url');
            return;
          }
          debugPrint('[PostReaderService] ❌ 이미지 프리로드 실패: $url - $e');
        }
      }
    }

    // 스티커 이미지 프리로드 (순차 실행)
    if (stickerImageUrls.isNotEmpty) {
      for (final url in stickerImageUrls) {
        // 🎯 context dispose 체크
        if (!context.mounted) {
          debugPrint('[PostReaderService] ⚠️ context dispose됨 - 스티커 프리로드 중단');
          return;
        }
        try {
          final built = EditorImageProvider.build(
            url: url,
            isEditing: false, // 읽기 모드
            decodeWidth: decodeWidth,
          );
          await precacheImage(built.effectiveProvider, context);
          debugPrint('[PostReaderService] ✅ 스티커 이미지 프리로드 완료: $url');
        } catch (e) {
          if (e.toString().contains('dispose') ||
              e.toString().contains('mounted')) {
            debugPrint('[PostReaderService] ⚠️ context dispose로 인한 중단: $url');
            return;
          }
          debugPrint('[PostReaderService] ❌ 스티커 이미지 프리로드 실패: $url - $e');
        }
      }
    }

    // 비디오 프리로드 (순차 실행 - 각 비디오는 내부적으로 초기화 대기)
    if (clipUrls.isNotEmpty) {
      for (final url in clipUrls) {
        // 🎯 context dispose 체크
        if (!context.mounted) {
          debugPrint('[PostReaderService] ⚠️ context dispose됨 - 비디오 프리로드 중단');
          return;
        }
        try {
          await preloadVideoForReader(url);
        } catch (e) {
          debugPrint('[PostReaderService] ⚠️ 비디오 프리로드 실패 (계속 진행): $url - $e');
          // 에러를 무시하고 계속 진행
        }
      }
    }

    // 🎯 캐시 적용을 위해 한 프레임 대기
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    await completer.future;

    // 🎯 폰트 프리로드 (동기적으로 실행)
    await _preloadFonts(context, content);

    // 🎯 눈에 잘 띄는 동기 프리로드 완료 로그
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('✅ [동기 프리로드 완료] 첫 $mediaNodeCount개 미디어 노드');
    debugPrint('   📸 이미지: ${imageUrls.length}개');
    debugPrint('   🎬 비디오: ${clipUrls.length}개');
    debugPrint('   🎨 스티커: ${stickerImageUrls.length}개');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('');
  }

  /// 동기적으로 폰트 프리로드 (에러 무시)
  Future<void> _preloadFonts(
    BuildContext context,
    Map<String, dynamic> content,
  ) async {
    // 🎯 context dispose 체크
    if (!context.mounted) {
      debugPrint('[PostReaderService] ⚠️ context dispose됨 - 폰트 프리로드 중단');
      return;
    }

    try {
      final fontIdentifiers = extractUsedFonts(content);
      if (fontIdentifiers.isEmpty) {
        debugPrint('[PostReaderService] 🔤 프리로드할 폰트 없음');
        return;
      }

      final fontPreloadService = FontPreloadService();
      final fontsToLoad = <FontItem>[];

      for (final identifier in fontIdentifiers) {
        // 🎯 context dispose 체크
        if (!context.mounted) {
          debugPrint('[PostReaderService] ⚠️ context dispose됨 - 폰트 프리로드 중단');
          return;
        }

        final font = FontCatalog.findByIdentifier(identifier);
        if (font != null && !fontPreloadService.isPreloaded(identifier)) {
          fontsToLoad.add(font);
        }
      }

      if (fontsToLoad.isEmpty) {
        debugPrint('[PostReaderService] 🔤 모든 폰트가 이미 로드됨');
        return;
      }

      debugPrint('[PostReaderService] 🔤 폰트 프리로드 시작: ${fontsToLoad.length}개');

      // 병렬로 폰트 로드 (최대 5개씩)
      for (int i = 0; i < fontsToLoad.length; i += 5) {
        // 🎯 context dispose 체크
        if (!context.mounted) {
          debugPrint('[PostReaderService] ⚠️ context dispose됨 - 폰트 프리로드 중단');
          return;
        }

        final batch = fontsToLoad.skip(i).take(5).toList();
        await Future.wait(
          batch.map((font) => fontPreloadService.preloadFont(font)),
          eagerError: false,
        );
        // 배치 간 짧은 딜레이
        if (i + 5 < fontsToLoad.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      debugPrint('[PostReaderService] ✅ 폰트 프리로드 완료: ${fontsToLoad.length}개');
    } catch (e) {
      if (e.toString().contains('dispose') ||
          e.toString().contains('mounted')) {
        debugPrint('[PostReaderService] ⚠️ context dispose로 인한 중단: 폰트 프리로드');
        return;
      }
      debugPrint('[PostReaderService] ⚠️ 폰트 프리로드 실패 (무시): $e');
    }
  }

  /// 이미지를 미리 로드한다
  /// 🎯 EditorImageProvider를 사용하여 렌더링과 동일한 캐시 키 보장
  Future<void> preloadImages(
    BuildContext context,
    List<String> imageUrls, {
    int maxCount = 15, // 🎯 6 -> 15로 증가 (성능 개선)
    bool Function()? shouldContinue, // ✅ pop/dispose 시 중단용
  }) async {
    final imagesToPreload = imageUrls.take(maxCount).toList();

    if (imagesToPreload.isEmpty) {
      return;
    }

    _d('[PostReaderService] 🖼️ 이미지 ${imagesToPreload.length}개 미리 로드 시작');
    _d('[PostReaderService] 🖼️ 프리로드할 URL 목록: ${imagesToPreload.join(", ")}');

    final decodeWidth = EditorImageProvider.readingDecodeWidth(
      context,
      MediaQuery.sizeOf(context).width,
    );

    try {
      // ✅ Future.wait는 취소가 불가능해서, pop 시 캐시를 계속 밀어내는 원인이 될 수 있다.
      // 따라서 순차 실행 + shouldContinue() 체크로 중단 가능하게 한다.
      for (final url in imagesToPreload) {
        if (shouldContinue != null && !shouldContinue()) return;

        // 🎯 context dispose 체크: precacheImage 호출 전에 확인
        if (!context.mounted) {
          debugPrint('[PostReaderService] ⚠️ context dispose됨 - 이미지 프리로드 중단');
          return;
        }

        try {
          final built = EditorImageProvider.build(
            url: url,
            isEditing: false, // 읽기 모드
            decodeWidth: decodeWidth,
          );

          // 🎯 context dispose 체크: precacheImage 호출 직전에 다시 확인
          if (!context.mounted) {
            debugPrint('[PostReaderService] ⚠️ context dispose됨 - 이미지 프리로드 중단');
            return;
          }

          await precacheImage(
            built.effectiveProvider,
            context,
            onError: (e, stack) {
              debugPrint('[PostReaderService] ❌ 이미지 프리캐싱 실패: $url - $e');
            },
          );
          _d('[PostReaderService] ✅ 이미지 프리캐싱 완료: $url');

          // 🎯 UI 끊김(스피너 점프) 완화: 매 이미지 프리캐시 후 프레임을 양보
          // - 디코딩/업로드가 몰리면 렌더 프레임이 크게 드랍될 수 있어, 작업을 확실히 분산한다.
          await Future<void>.delayed(const Duration(milliseconds: 16));
        } catch (e) {
          // 🎯 context dispose 에러는 무시 (정상적인 상황)
          if (e.toString().contains('dispose') ||
              e.toString().contains('mounted')) {
            debugPrint('[PostReaderService] ⚠️ context dispose로 인한 중단: $url');
            return;
          }
          debugPrint('[PostReaderService] ❌ 이미지 프리캐싱 중 오류: $url - $e');
        }
      }
      _d('[PostReaderService] ✅ 이미지 프리캐싱 완료: ${imagesToPreload.length}개');
    } catch (e) {
      debugPrint('[PostReaderService] ❌ 이미지 프리캐싱 중 오류: $e');
    }
  }

  // ===== 영상 프리로드 컨트롤러 캐시 (레거시 지원용) =====
  // 🎯 VideoCacheService로 통합되었으나, 레거시 코드 호환성을 위해 유지
  static final Map<String, VideoPlayerController> _preloadedControllers = {};
  static final Map<String, DateTime> _preloadTimestamps = {}; // 생성 시간 추적

  // ===== 프리로드 완료 알림 리스너 =====
  static final List<void Function(String)> _clipPreloadedListeners = [];

  static void addClipPreloadedListener(void Function(String url) listener) {
    _clipPreloadedListeners.add(listener);
  }

  static void removeClipPreloadedListener(void Function(String url) listener) {
    _clipPreloadedListeners.remove(listener);
  }

  static void _notifyClipPreloaded(String url) {
    for (final l in List.from(_clipPreloadedListeners)) {
      try {
        l(url);
      } catch (_) {}
    }
  }

  /// 프리로드된 컨트롤러를 전달하고 캐시에서 제거한다 (소유권 이전)
  /// 🎯 VideoCacheService로 통합 (레거시 지원)
  static VideoPlayerController? takePreloadedController(String url) {
    // 🎯 VideoCacheService에서 먼저 확인
    final videoCache = VideoCacheService();
    if (videoCache.hasController(url, namespace: 'editor')) {
      final controller = videoCache.getOrCreateController(
        url,
        namespace: 'editor',
      );
      // 참조 카운트는 유지 (다른 곳에서 사용 중일 수 있음)
      debugPrint('[PostReaderService] VideoCacheService에서 컨트롤러 반환: $url');
      return controller;
    }

    // 🎯 레거시 캐시에서 마이그레이션
    _preloadTimestamps.remove(url);
    final controller = _preloadedControllers.remove(url);
    if (controller != null) {
      // VideoCacheService에 등록
      try {
        videoCache.getOrCreateController(url, namespace: 'editor');
        debugPrint('[PostReaderService] 레거시 캐시에서 VideoCacheService로 이동: $url');
      } catch (e) {
        debugPrint('[PostReaderService] VideoCacheService 등록 실패: $url - $e');
      }
    }
    return controller;
  }

  /// 프리로드된 컨트롤러를 가져오기만 함 (캐시에 유지)
  /// 🎯 VideoCacheService로 통합 (레거시 지원)
  static VideoPlayerController? getPreloadedController(String url) {
    // 🎯 VideoCacheService에서 먼저 확인
    final videoCache = VideoCacheService();
    if (videoCache.hasController(url, namespace: 'editor')) {
      return videoCache.getOrCreateController(url, namespace: 'editor');
    }

    // 🎯 레거시 캐시 확인
    return _preloadedControllers[url];
  }

  /// 남아있는 프리로드 컨트롤러 정리
  /// 🎯 VideoCacheService로 통합 (레거시 지원)
  static void disposeAllPreloaded() {
    // 🎯 레거시 캐시 정리
    for (final c in _preloadedControllers.values) {
      try {
        c.dispose();
      } catch (_) {}
    }
    _preloadedControllers.clear();
    _preloadTimestamps.clear();

    // 🎯 VideoCacheService는 전역 싱글톤이므로 여기서 dispose하지 않음
    // (다른 곳에서 사용 중일 수 있음)
    debugPrint('[PostReaderService] 레거시 프리로드 컨트롤러 정리 완료');
  }

  // 🎯 제거됨: _disposeOldestControllers
  // VideoCacheService가 LRU 정책으로 자동 관리하므로 불필요

  /// 단일 비디오를 프리로드한다 (에디터에서 플레이스홀더 교체 시 사용)
  /// 🎯 VideoCacheService로 통합 (중복 캐시 시스템 제거)
  static Future<void> preloadVideo(String url) async {
    if (url.isEmpty) return;

    // 🎯 VideoCacheService 사용 (namespace: 'editor')
    final videoCache = VideoCacheService();

    // 이미 프리로드된 경우 스킵
    if (videoCache.hasController(url, namespace: 'editor')) {
      if (videoCache.isInitialized(url, namespace: 'editor')) {
        debugPrint(
          '[PostReaderService] 이미 프리로드된 비디오 (VideoCacheService): $url',
        );
        _notifyClipPreloaded(url);
        return;
      }
    }

    // 🎯 레거시 캐시에서 마이그레이션
    if (_preloadedControllers.containsKey(url)) {
      final controller = _preloadedControllers.remove(url);
      _preloadTimestamps.remove(url);
      if (controller != null) {
        try {
          if (controller.value.isInitialized) {
            // VideoCacheService에 등록 (참조 카운트 증가)
            videoCache.getOrCreateController(url, namespace: 'editor');
            debugPrint(
              '[PostReaderService] ✅ 레거시 캐시에서 VideoCacheService로 이동: $url',
            );
            _notifyClipPreloaded(url);
            return;
          }
        } catch (e) {
          debugPrint('[PostReaderService] ⚠️ 레거시 캐시 컨트롤러 무효화: $url - $e');
        }
        // dispose 레거시 컨트롤러
        try {
          controller.dispose();
        } catch (_) {}
      }
    }

    try {
      debugPrint(
        '[PostReaderService] 🚀 비디오 프리로드 시작 (VideoCacheService): $url',
      );
      final controller = videoCache.getOrCreateController(
        url,
        namespace: 'editor',
      );

      // 이미 초기화된 경우 스킵
      if (controller.value.isInitialized) {
        debugPrint('[PostReaderService] ✅ 비디오 프리로드 완료 (이미 초기화됨): $url');
        _notifyClipPreloaded(url);
        return;
      }

      // 🎯 VideoCacheService가 이미 initialize()를 시작했을 수 있으므로
      // 초기화 완료를 대기
      int maxWaitMs = 10000;
      int waitedMs = 0;
      const checkInterval = Duration(milliseconds: 100);

      while (!controller.value.isInitialized && waitedMs < maxWaitMs) {
        await Future.delayed(checkInterval);
        waitedMs += checkInterval.inMilliseconds;

        // 🎯 dispose 체크: 컨트롤러 유효성 확인
        try {
          if (controller.value.hasError) {
            throw Exception('비디오 초기화 실패: ${controller.value.errorDescription}');
          }
        } catch (e) {
          debugPrint('[PostReaderService] ⚠️ 컨트롤러 오류 감지: $e');
          break;
        }
      }

      if (controller.value.isInitialized) {
        _notifyClipPreloaded(url);
        debugPrint(
          '[PostReaderService] ✅ 비디오 프리로드 완료 (VideoCacheService): $url',
        );
      } else if (waitedMs >= maxWaitMs) {
        debugPrint('[PostReaderService] ⚠️ 비디오 프리로드 타임아웃: $url');
        throw TimeoutException('비디오 초기화 타임아웃', const Duration(seconds: 10));
      } else {
        throw Exception('비디오 초기화 실패');
      }
    } catch (e) {
      debugPrint(
        '[PostReaderService] ❌ 비디오 프리로드 실패 (VideoCacheService): $url - $e',
      );
      rethrow;
    }
  }

  /// 읽기 모드용 비디오 프리로드 (readerVideoControllers에 저장)
  /// 🎯 최적화: 중복 체크, 빠른 초기화, 에러 핸들링 개선
  /// 🎯 Public static 메서드: PostReaderScreen에서 나머지 비디오 비동기 프리로드에 사용
  static Future<void> preloadVideoForReader(String url) async {
    if (url.isEmpty) {
      debugPrint('[PostReaderService] ⚠️ 빈 URL로 프리로드 시도');
      return;
    }

    // 🎯 VideoCacheService에서 이미 프리로드된 경우 스킵
    final videoCache = VideoCacheService();
    if (videoCache.hasController(url, namespace: 'reader')) {
      if (videoCache.isInitialized(url, namespace: 'reader')) {
        debugPrint(
          '[PostReaderService] ✅ 이미 프리로드된 비디오 (VideoCacheService): $url',
        );
        return;
      }
    }

    // PostReaderService 캐시도 확인
    if (_preloadedControllers.containsKey(url)) {
      final controller = _preloadedControllers.remove(url);
      _preloadTimestamps.remove(url);
      if (controller != null) {
        try {
          if (controller.value.isInitialized) {
            // VideoCacheService에 등록 (참조 카운트 증가)
            videoCache.getOrCreateController(url, namespace: 'reader');
            debugPrint(
              '[PostReaderService] ✅ 캐시에서 VideoCacheService로 이동: $url',
            );
            return;
          }
        } catch (e) {
          debugPrint('[PostReaderService] ⚠️ 캐시 컨트롤러 무효화: $url - $e');
        }
      }
    }

    // 🎯 VideoCacheService를 통해 컨트롤러 생성 및 초기화
    try {
      debugPrint(
        '[PostReaderService] 🚀 비디오 프리로드 시작 (VideoCacheService): $url',
      );

      final controller = videoCache.getOrCreateController(
        url,
        namespace: 'reader',
      );

      // 이미 초기화된 경우 스킵
      if (controller.value.isInitialized) {
        debugPrint('[PostReaderService] ✅ 비디오 프리로드 완료 (이미 초기화됨): $url');
        return;
      }

      // 🎯 VideoCacheService가 이미 initialize()를 시작했을 수 있으므로
      // 초기화 완료를 대기하는 헬퍼 사용
      final stopwatch = Stopwatch()..start();

      // 초기화 완료 대기 (최대 10초)
      int maxWaitMs = 10000;
      int waitedMs = 0;
      const checkInterval = Duration(milliseconds: 100);

      while (!controller.value.isInitialized && waitedMs < maxWaitMs) {
        await Future.delayed(checkInterval);
        waitedMs += checkInterval.inMilliseconds;

        // 🎯 dispose 체크: 컨트롤러 유효성 확인
        try {
          if (controller.value.hasError) {
            throw Exception('비디오 초기화 실패: ${controller.value.errorDescription}');
          }
        } catch (e) {
          debugPrint('[PostReaderService] ⚠️ 컨트롤러 오류 감지: $e');
          break;
        }
      }

      stopwatch.stop();

      // 🎯 초기화 완료 확인
      try {
        if (controller.value.isInitialized) {
          debugPrint(
            '[PostReaderService] ✅ 비디오 프리로드 완료 (VideoCacheService): $url '
            '(${stopwatch.elapsedMilliseconds}ms, ${controller.value.size.width}x${controller.value.size.height})',
          );
        } else if (waitedMs >= maxWaitMs) {
          debugPrint('[PostReaderService] ⚠️ 비디오 프리로드 타임아웃: $url');
        } else {
          debugPrint('[PostReaderService] ⚠️ 비디오 프리로드 실패: $url');
        }
      } catch (_) {
        // best-effort
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[PostReaderService] ❌ 비디오 프리로드 실패 (VideoCacheService): $url - $e',
      );
      debugPrint('[PostReaderService] 스택: $stackTrace');
      // 에러를 다시 던지지 않음 (다른 비디오 프리로드에 영향 없도록)
    }
  }

  /// Exported 데이터로부터 스티커를 복구하여 StickerService에 추가한다.
  /// DraftService에서 사용하는 스티커 복구 로직
  void restoreStickers({
    required Map<String, dynamic> exported,
    required StickerService stickerService,
  }) {
    try {
      // 스티커 복원
      stickerService.removeAll();

      // content 안에 stickers가 있는지 확인
      final content = (exported['content'] as Map<String, dynamic>?) ?? {};
      final stickers =
          (content['stickers'] as List?) ??
          (exported['stickers'] as List?) ??
          [];

      for (final stickerData in stickers) {
        if (stickerData is Map<String, dynamic>) {
          stickerService.addStickerFromData(stickerData);
        }
      }
    } catch (e) {
      debugPrint('[PostReaderService] Error restoring stickers: $e');
    }
  }

  /// 편집 화면 열기
  static Future<Object?> openEditScreen(
    BuildContext context, {
    required Map<String, dynamic> exportedData,
    required String postId,
  }) async {
    if (postId.isEmpty) {
      debugPrint('[PostReaderService] postId가 없습니다');
      return null;
    }

    debugPrint('[PostReaderService] openEditScreen: 편집 화면 열기');
    debugPrint(
      '  - 전달할 exportedData의 content.nodes: ${((exportedData['content'] as Map?)?['nodes'] as List?)?.length ?? 0}개',
    );

    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => PostwriteScreen(
              isEditingMode: true,
              exportedDataForEdit: exportedData,
              postId: postId,
            ),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    return result;
  }

  /// 수정 완료 후 문서 재배치 (서버에서 최신 문서 가져와서 재구성)
  /// 반환값: (refreshedDocument, mergedData)
  static Future<(MutableDocument, Map<String, dynamic>)>
  refreshDocumentAfterEdit(
    BuildContext context,
    String postId, {
    required Map<String, dynamic> currentExportedData,
  }) async {
    try {
      debugPrint('[PostReaderService] 수정 완료 후 문서 재배치 시작: postId=$postId');

      // 서버에서 최신 content 가져오기
      final blogService = BlogService();
      final response = await blogService.getPostContent(postId);

      // 최신 content로 merged 데이터 구성
      final merged = Map<String, dynamic>.from(currentExportedData);
      merged['content'] = response['content'] ?? {};

      // 공개범위 정보도 업데이트
      if (response.containsKey('accessLevel')) {
        merged['accessLevel'] = response['accessLevel'];
      }
      if (response.containsKey('sharedGroupIds')) {
        merged['sharedGroupIds'] = response['sharedGroupIds'];
      }
      if (response.containsKey('sharedGroupNames')) {
        merged['sharedGroupNames'] = response['sharedGroupNames'];
      }

      // 최신 문서로 재구성
      final postReaderService = PostReaderService();
      final refreshedDocument = postReaderService.rebuildDocumentForRead(
        merged,
      );

      debugPrint('[PostReaderService] ✅ 문서 재배치 완료');
      return (refreshedDocument, merged);
    } catch (e) {
      debugPrint('[PostReaderService] ❌ 문서 재배치 실패: $e');
      // 실패 시 기존 문서 반환
      final postReaderService = PostReaderService();
      return (
        postReaderService.rebuildDocumentForRead(currentExportedData),
        currentExportedData,
      );
    }
  }
}
