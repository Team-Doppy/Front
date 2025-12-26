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
import 'package:doppy/editor/component/clip_component.dart'
    show ClipNode, readerVideoControllers;
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/font_preload_service.dart';
import 'package:doppy/editor/style/font_catalog.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:video_player/video_player.dart';

/// 읽기 전용 포스트 복구 서비스
/// PostReaderScreen에서 사용하는 MutableDocument 복원 로직
class PostReaderService {
  /// Exported 데이터로부터 읽기 전용 MutableDocument를 복구한다.
  /// - includeTitleNode: true면 제목 노드도 포함 (드래프트 복구용), false면 제외 (글보기용)
  MutableDocument rebuildDocumentForRead(
    Map<String, dynamic> exported, {
    bool includeTitleNode = false,
  }) {
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
          final isTitle = m['isTitle'] == true;
          // 제목 문단은 화면 상단 이미지 오버레이로 별도 표시되므로 본문에서는 제외
          // 단, 드래프트 복구시에는 includeTitleNode가 true이면 포함
          if (isTitle && !includeTitleNode) break;
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

          // isTitle 정보도 메타데이터에 추가 (드래프트 복구시 제목 노드 인식용)
          if (isTitle) {
            meta['isTitle'] = true;
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
          debugPrint('[PostReaderService] ImageNode $id padding=$paddingMode');

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
          // 멘션은 이제 Paragraph 기반으로 처리됨
          final usernames =
              ((m['usernames'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList();
          final String text = usernames.map((u) => '@$u').join('\n');

          final AttributedText attributed = AttributedText(text);
          if (text.isNotEmpty) {
            attributed.addAttribution(
              boldAttribution,
              SpanRange(0, text.length - 1),
            );
          }

          final meta = <String, dynamic>{
            'textAlign': (m['align'] ?? 'center').toString(),
            'mention': true,
            'usernames': usernames,
          };

          // fontFamily를 메타데이터에서 추출하여 추가
          if (m['fontFamily'] != null) {
            meta['fontFamily'] = m['fontFamily'];
          }

          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
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

    debugPrint('[PostReaderService] 이미지 URL 추출 완료: ${imageUrls.length}개');
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

    debugPrint('[PostReaderService] 클립 URL 추출 완료: ${clipUrls.length}개');
    return clipUrls;
  }

  /// 첫 텍스트 노드 제외 후, 첫 N개 미디어 노드(이미지+영상 합쳐서)에서 모든 미디어 URL을 추출한다
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

    debugPrint(
      '[PostReaderService] 🎯 첫 $mediaNodeCount개 미디어 노드(이미지+영상 합쳐서)에서 URL 추출 완료: 이미지 ${imageUrls.length}개, 비디오 ${clipUrls.length}개',
    );
    if (imageUrls.isNotEmpty) {
      debugPrint(
        '[PostReaderService] 🖼️ 추출된 이미지 URL: ${imageUrls.join(", ")}',
      );
    }
    if (clipUrls.isNotEmpty) {
      debugPrint('[PostReaderService] 🎬 추출된 비디오 URL: ${clipUrls.join(", ")}');
    }

    return {'images': imageUrls, 'clips': clipUrls};
  }

  /// 첫 텍스트 노드 제외 후, 첫 N개 미디어 노드에서 이미지 URL을 추출한다 (하위 호환성)
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

  /// 첫 텍스트 노드 제외 후, 첫 N개 미디어 노드에서 비디오 URL을 추출한다 (하위 호환성)
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
  /// 첫 텍스트 노드 제외 후, 첫 N개 미디어 노드(이미지+영상 합쳐서)에 있는 모든 미디어를 프리로드
  Future<void> preloadTopMedia(
    BuildContext context,
    Map<String, dynamic> content, {
    int mediaNodeCount = 3,
  }) async {
    // 첫 텍스트 노드 제외 후, 첫 N개 미디어 노드(이미지+영상 합쳐서)에서 모든 미디어 URL 추출
    final mediaUrls = extractFirstMediaUrls(
      content,
      mediaNodeCount: mediaNodeCount,
    );
    final imageUrls = mediaUrls['images'] ?? [];
    final clipUrls = mediaUrls['clips'] ?? [];

    if (imageUrls.isEmpty && clipUrls.isEmpty) {
      debugPrint('[PostReaderService] ⚠️ 프리로드할 미디어가 없습니다');
      // 🎯 미디어가 없어도 폰트는 프리로드 (백그라운드)
      _preloadFontsInBackground(content);
      return;
    }

    debugPrint(
      '[PostReaderService] 🚀 첫 $mediaNodeCount개 미디어 노드 프리로드 시작: 이미지 ${imageUrls.length}개, 비디오 ${clipUrls.length}개',
    );

    // 🎯 이미지와 비디오를 병렬로 프리로드 (크기 측정 제거 - 서버 응답에 이미 포함)
    final futures = <Future>[];

    // 이미지 프리로드만 (크기는 서버 응답의 imageDimensions 사용)
    if (imageUrls.isNotEmpty) {
      for (final url in imageUrls) {
        futures.add(
          precacheImage(NetworkImage(url), context).catchError((e) {
            debugPrint('[PostReaderService] 이미지 프리로드 실패: $url - $e');
          }),
        );
      }
    }

    // 비디오 프리로드
    if (clipUrls.isNotEmpty) {
      for (final url in clipUrls) {
        futures.add(
          preloadVideoForReader(url).catchError((e) {
            debugPrint('[PostReaderService] ⚠️ 비디오 프리로드 실패 (계속 진행): $url - $e');
            // 에러를 무시하고 계속 진행
            return null;
          }),
        );
      }
    }

    // 모든 프리로드 완료 대기 (실패해도 계속 진행)
    try {
      await Future.wait(futures, eagerError: false);
    } catch (e) {
      debugPrint('[PostReaderService] ⚠️ 프리로드 중 일부 실패 (무시): $e');
    }

    // 🎯 캐시 적용을 위해 한 프레임 대기
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    await completer.future;

    debugPrint(
      '[PostReaderService] ✅ 상위 미디어 프리로드 완료: 이미지 ${imageUrls.length}개, 비디오 ${clipUrls.length}개',
    );

    // 🎯 폰트 프리로드 (백그라운드에서 비동기로 실행, 미디어 프리로드와 병렬)
    _preloadFontsInBackground(content);
  }

  /// 백그라운드에서 폰트 프리로드 (비동기, 에러 무시)
  void _preloadFontsInBackground(Map<String, dynamic> content) {
    Future.microtask(() async {
      try {
        final fontIdentifiers = extractUsedFonts(content);
        if (fontIdentifiers.isEmpty) {
          debugPrint('[PostReaderService] 🔤 프리로드할 폰트 없음');
          return;
        }

        final fontPreloadService = FontPreloadService();
        final fontsToLoad = <FontItem>[];

        for (final identifier in fontIdentifiers) {
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
        debugPrint('[PostReaderService] ⚠️ 폰트 프리로드 실패 (무시): $e');
      }
    });
  }

  /// 이미지를 미리 로드한다
  Future<void> preloadImages(
    BuildContext context,
    List<String> imageUrls, {
    int maxCount = 15, // 🎯 6 -> 15로 증가 (성능 개선)
  }) async {
    final imagesToPreload = imageUrls.take(maxCount).toList();

    if (imagesToPreload.isEmpty) {
      return;
    }

    debugPrint(
      '[PostReaderService] 🖼️ 이미지 ${imagesToPreload.length}개 미리 로드 시작',
    );
    debugPrint(
      '[PostReaderService] 🖼️ 프리로드할 URL 목록: ${imagesToPreload.join(", ")}',
    );

    try {
      await Future.wait(
        imagesToPreload.map((url) {
          return precacheImage(
            NetworkImage(url),
            context,
            onError: (e, stack) {
              debugPrint('[PostReaderService] ❌ 이미지 프리캐싱 실패: $url - $e');
            },
          ).then((_) {
            debugPrint('[PostReaderService] ✅ 이미지 프리캐싱 완료: $url');
          });
        }),
      );
      debugPrint(
        '[PostReaderService] ✅ 이미지 프리캐싱 완료: ${imagesToPreload.length}개',
      );
    } catch (e) {
      debugPrint('[PostReaderService] ❌ 이미지 프리캐싱 중 오류: $e');
    }
  }

  // ===== 영상 프리로드 컨트롤러 캐시 =====
  static final Map<String, VideoPlayerController> _preloadedControllers = {};
  static final Map<String, DateTime> _preloadTimestamps = {}; // 생성 시간 추적
  static const int _maxPreloadCount = 30; // 🎯 최대 프리로드 개수 증가 (20 -> 30, 성능 개선)

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
  static VideoPlayerController? takePreloadedController(String url) {
    _preloadTimestamps.remove(url);
    return _preloadedControllers.remove(url);
  }

  /// 프리로드된 컨트롤러를 가져오기만 함 (캐시에 유지)
  static VideoPlayerController? getPreloadedController(String url) {
    return _preloadedControllers[url];
  }

  /// 남아있는 프리로드 컨트롤러 정리
  static void disposeAllPreloaded() {
    for (final c in _preloadedControllers.values) {
      c.dispose();
    }
    _preloadedControllers.clear();
    _preloadTimestamps.clear();
  }

  /// 오래된 컨트롤러부터 정리 (메모리 관리)
  static void _disposeOldestControllers({int keepCount = 4}) {
    if (_preloadedControllers.length <= keepCount) return;

    // 생성 시간 기준으로 정렬 (오래된 순)
    final sorted =
        _preloadTimestamps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    // 오래된 것부터 제거
    final toRemove = sorted.length - keepCount;
    for (int i = 0; i < toRemove; i++) {
      final url = sorted[i].key;
      final controller = _preloadedControllers.remove(url);
      _preloadTimestamps.remove(url);
      controller?.dispose();
      debugPrint('[PostReaderService] 오래된 프리로드 컨트롤러 정리: $url');
    }
  }

  /// 단일 비디오를 프리로드한다 (에디터에서 플레이스홀더 교체 시 사용)
  static Future<void> preloadVideo(String url) async {
    if (url.isEmpty) return;

    // 이미 프리로드된 경우 스킵
    if (_preloadedControllers.containsKey(url)) {
      debugPrint('[PostReaderService] 이미 프리로드된 비디오: $url');
      return;
    }

    // 최대 개수 초과 시 오래된 것부터 정리
    if (_preloadedControllers.length >= _maxPreloadCount) {
      _disposeOldestControllers(keepCount: _maxPreloadCount - 1);
    }

    try {
      debugPrint('[PostReaderService] 비디오 프리로드 시작: $url');
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _preloadTimestamps[url] = DateTime.now();
      _preloadedControllers[url] = controller;

      await controller.initialize();
      _notifyClipPreloaded(url);
      debugPrint('[PostReaderService] ✅ 비디오 프리로드 완료: $url');
    } catch (e) {
      debugPrint('[PostReaderService] ❌ 비디오 프리로드 실패: $url - $e');
      // 실패 시 캐시에서 제거
      _preloadedControllers.remove(url);
      _preloadTimestamps.remove(url);
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

    // 이미 프리로드된 경우 스킵 (readerVideoControllers 확인)
    if (readerVideoControllers.containsKey(url)) {
      try {
        final existing = readerVideoControllers[url];
        if (existing != null && existing.value.isInitialized) {
          debugPrint('[PostReaderService] ✅ 이미 프리로드된 비디오 (reader): $url');
          return;
        } else {
          // 무효한 컨트롤러는 제거
          debugPrint('[PostReaderService] ⚠️ 무효한 컨트롤러 제거: $url');
          readerVideoControllers.remove(url);
        }
      } catch (e) {
        debugPrint('[PostReaderService] ⚠️ 기존 컨트롤러 확인 실패, 제거: $url - $e');
        readerVideoControllers.remove(url);
      }
    }

    // PostReaderService 캐시도 확인
    if (_preloadedControllers.containsKey(url)) {
      // 캐시에서 readerVideoControllers로 이동
      final controller = _preloadedControllers.remove(url);
      _preloadTimestamps.remove(url);
      if (controller != null) {
        try {
          if (controller.value.isInitialized) {
            readerVideoControllers[url] = controller;
            debugPrint('[PostReaderService] ✅ 캐시에서 reader로 이동: $url');
            return;
          }
        } catch (e) {
          debugPrint('[PostReaderService] ⚠️ 캐시 컨트롤러 무효화: $url - $e');
        }
      }
    }

    // 새로운 컨트롤러 생성 및 초기화
    VideoPlayerController? controller;
    try {
      debugPrint('[PostReaderService] 🚀 비디오 프리로드 시작 (reader): $url');

      controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {'Accept': 'video/*', 'Connection': 'keep-alive'},
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // 🎯 먼저 맵에 저장 (ClipComponent가 조기 접근 가능)
      readerVideoControllers[url] = controller;

      // 초기화 (타임아웃 추가 - 확장성 개선)
      final stopwatch = Stopwatch()..start();
      await controller.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('비디오 초기화 타임아웃', const Duration(seconds: 10));
        },
      );
      stopwatch.stop();

      debugPrint(
        '[PostReaderService] ✅ 비디오 프리로드 완료 (reader): $url '
        '(${stopwatch.elapsedMilliseconds}ms, ${controller.value.size.width}x${controller.value.size.height})',
      );
    } catch (e, stackTrace) {
      debugPrint('[PostReaderService] ❌ 비디오 프리로드 실패 (reader): $url - $e');
      debugPrint('[PostReaderService] 스택: $stackTrace');

      // 실패 시 캐시에서 제거 및 컨트롤러 정리
      readerVideoControllers.remove(url);

      if (controller != null) {
        try {
          controller.dispose();
        } catch (disposeError) {
          debugPrint('[PostReaderService] 컨트롤러 정리 실패: $disposeError');
        }
      }

      // 에러를 다시 던지지 않음 (다른 비디오 프리로드에 영향 없도록)
      // rethrow;
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
}
