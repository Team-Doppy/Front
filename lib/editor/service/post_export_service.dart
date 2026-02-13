import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../editor/config/editor_config.dart';
import '../../editor/utils/list_paragraph_meta.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/component/link_component.dart';
import '../../editor/component/divider_component.dart';
import '../../editor/style/text_attributions.dart';
import 'package:super_editor/super_editor.dart';

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
  /// 업로드 대기 안내 메시지 로케일 키
  static const String kUploadWaitKey = 'editor_upload_wait';

  static void _throwUploadWait() => throw StateError(kUploadWaitKey);

  /// 편집 중 문서를 JSON 문자열로 내보낸다.
  /// [forPublishing]이 true이면 uploadedUrls를 확인하여 네트워크 URL로 변환
  /// [allowPartialUpload]이 true이면 업로드 완료되지 않은 이미지는 로컬 경로로 유지 (임시저장용)
  static String exportToJsonString({
    required EditorService editorService,
    bool pretty = true,
    bool forPublishing = false,
    bool allowPartialUpload = false,
    dynamic textStylingService, // TextStylingService (순환 참조 방지)
  }) {
    final map = exportToMap(
      editorService: editorService,
      forPublishing: forPublishing,
      allowPartialUpload: allowPartialUpload,
      textStylingService: textStylingService,
    );
    return JsonExport.encode(map, pretty: pretty);
  }

  /// 문서에서 제목 추출
  /// - 제목 노드가 있으면 해당 텍스트 반환 (비어있으면 '')
  /// - 제목 노드가 없으면 첫 번째 텍스트(Paragraph) 노드의 텍스트 반환
  /// - 노드가 없으면 ''
  static String extractTitleFromDocument(MutableDocument document) {
    ParagraphNode? titleNode;
    ParagraphNode? firstTextNode;
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode) {
        if (node.metadata[EditorConfig.titleNodeMetadataKey] == true) {
          titleNode = node;
          break;
        }
        if (firstTextNode == null) {
          firstTextNode = node;
        }
      }
    }
    if (titleNode != null) {
      return titleNode.text.text.trim();
    }
    if (firstTextNode != null) {
      return firstTextNode.text.text.trim();
    }
    return '';
  }

  /// 제목 노드 상태 확인
  /// (hasTitleNode, titleNodeEmpty)
  static ({bool hasTitleNode, bool titleNodeEmpty}) getTitleNodeStatus(
    MutableDocument document,
  ) {
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode &&
          node.metadata[EditorConfig.titleNodeMetadataKey] == true) {
        final isEmpty = node.text.text.trim().isEmpty;
        return (hasTitleNode: true, titleNodeEmpty: isEmpty);
      }
    }
    return (hasTitleNode: false, titleNodeEmpty: false);
  }

  /// 문서에서 제목 추출 (더 이상 사용되지 않음, extractTitleFromDocument 사용)
  static String getTitleFromDocument(MutableDocument document) {
    return extractTitleFromDocument(document);
  }

  /// 제목이 없으면 본문에서 발췌 (최대 30자)
  static String getTitleOrExtractFromBody(MutableDocument document) {
    // 본문에서 발췌
    final buffer = StringBuffer();

    // 모든 본문 노드에서 텍스트 수집
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode) {
        final text = node.text.text.trim();
        if (text.isNotEmpty) {
          buffer.write(text);
          buffer.write(' ');

          // 30자 이상이면 중단
          if (buffer.length >= 30) break;
        }
      }
    }

    final extracted = buffer.toString().trim();
    if (extracted.isEmpty) return '';

    // 최대 30자로 제한
    if (extracted.length > 30) {
      return extracted.substring(0, 30);
    }

    return extracted;
  }

  /// Export된 데이터에서 사용된 이미지/비디오 URL 수집
  static List<String> collectUsedMediaUrls(Map<String, dynamic> exported) {
    final Set<String> usedUrls = <String>{};

    try {
      // content의 nodes에서 이미지/비디오 URL 수집
      final dynamic content = exported['content'];
      final List<dynamic> nodes =
          (content is Map)
              ? List<dynamic>.from(content['nodes'] as List? ?? const [])
              : const [];

      for (int i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        if (n is! Map) continue;

        final String type = (n['type'] ?? '').toString();

        if (type == 'image') {
          // data.url 또는 url 필드에서 추출
          final data = n['data'] as Map<String, dynamic>?;
          final String url = (data?['url'] ?? n['url'] ?? '').toString();
          if (url.isNotEmpty) {
            usedUrls.add(url);
          }
        } else if (type == 'imageRow') {
          // urls 필드에서 추출
          final List<dynamic> urls = List<dynamic>.from(n['urls'] ?? const []);
          for (final u in urls) {
            final String url = u.toString();
            if (url.isNotEmpty) {
              usedUrls.add(url);
            }
          }
        } else if (type == 'pageViewImage' ||
            type == 'pageviewImage' ||
            type == 'page_view_image') {
          final List<dynamic> urls = List<dynamic>.from(
            n['imageUrls'] ?? const [],
          );
          for (final u in urls) {
            final String url = u.toString();
            if (url.isNotEmpty) {
              usedUrls.add(url);
            }
          }
        } else if (type == 'video' || type == 'clip') {
          // data.url에서 추출
          final data = n['data'] as Map<String, dynamic>?;
          final String url = (data?['url'] ?? '').toString();
          if (url.isNotEmpty) {
            usedUrls.add(url);
          }
        }
      }
    } catch (e) {
      debugPrint('[PostExporter] 미디어 URL 수집 실패: $e');
    }

    return usedUrls.toList();
  }

  /// 편집 중 문서를 JSON(Map)으로 내보낸다.
  /// [forPublishing]이 true이면 uploadedUrls를 확인하여 네트워크 URL로 변환
  /// [allowPartialUpload]이 true이면 업로드 완료되지 않은 이미지는 로컬 경로로 유지 (임시저장용)
  static Map<String, dynamic> exportToMap({
    required EditorService editorService,
    bool forPublishing = false,
    bool allowPartialUpload = false,
    dynamic textStylingService, // TextStylingService (순환 참조 방지)
  }) {
    final doc = editorService.document;
    final List<Map<String, dynamic>> nodes = <Map<String, dynamic>>[];

    for (int i = 0; i < doc.length; i++) {
      final node = doc.getNodeAt(i);
      if (node == null) continue;

      if (node is ParagraphNode) {
        final meta = node.metadata;

        final align = meta['textAlign'] as String?;
        final fontFamily = meta['fontFamily'] as String?;
        final listType = ListParagraphMeta.getListType(meta);

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'paragraph',
          'text': node.text.text,
          'spans': _buildParagraphSpans(node.text),
        };

        // 정렬: left/center/right 항상 export (center도 복원되도록)
        if (align != null && align.isNotEmpty) {
          nodeMap['align'] = align;
        }
        if (fontFamily != null && fontFamily.isNotEmpty) {
          nodeMap['fontFamily'] = fontFamily;
        }
        if (meta[EditorConfig.titleNodeMetadataKey] == true) {
          nodeMap['isTitle'] = true;
        }
        // 리스트 프리픽스 메타데이터 (보기 모드 렌더링용)
        if (listType != null) {
          nodeMap['listType'] = listType;
          if (listType == ListParagraphMeta.typeNumbered) {
            nodeMap['listIndex'] = ListParagraphMeta.getListIndex(meta);
          }
          if (listType == ListParagraphMeta.typeChecklist) {
            nodeMap['checked'] = ListParagraphMeta.isChecked(meta);
          }
        }

        nodes.add(nodeMap);
        continue;
      }

      // ImageNode (SuperEditor 내장)
      if (node is ImageNode) {
        Map<String, dynamic>? meta;
        try {
          meta = (node as dynamic).metadata as Map<String, dynamic>?;
        } catch (_) {
          meta = null;
        }
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

        // 🚀 forPublishing이 true이고 uploadedUrls가 있으면 네트워크 URL로 변환
        String imageUrl = node.imageUrl;
        if (forPublishing && meta != null) {
          final isNetworkUrl = _isNetworkUrl(imageUrl);

          if (!isNetworkUrl) {
            // 로컬 경로인 경우 uploadedUrls에서 변환 (path/file://path variant 대응)
            final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
            final resolved =
                uploadedUrls != null
                    ? _resolveNetworkUrl(imageUrl, uploadedUrls)
                    : null;
            if (resolved != null) {
              imageUrl = resolved;
            } else {
              // 🎯 UploadService로 실제 업로드 상태 확인
              final isUploading = editorService.isNodeUploading(node.id);

              if (isUploading) {
                _throwUploadWait();
              } else if (allowPartialUpload) {
                // allowPartialUpload이 true이면 로컬 경로 유지
                debugPrint(
                  '[PostExporter] 임시저장: 단일 이미지 로컬 경로 유지 (노드 ID: ${node.id})',
                );
              } else {
                _throwUploadWait();
              }
            }
          }
        }

        // 발행용: 단일 이미지도 로컬 경로 방어
        if (forPublishing && !_isNetworkUrl(imageUrl)) {
          debugPrint(
            '[PostExporter] ⚠️ ImageNode 스킵: 발행 시 로컬 경로 (nodeId=${node.id})',
          );
          continue;
        }

        final dataMap = <String, dynamic>{'url': imageUrl};

        if (hasSpoiler) {
          dataMap['spoiler'] = true;
        }

        // 쉬머용: 메타데이터 imageDimensions에서 aspectRatio 계산하여 포함
        if (meta != null) {
          final imageDimensions =
              meta['imageDimensions'] as Map<String, dynamic>?;
          if (imageDimensions != null && imageDimensions.isNotEmpty) {
            dynamic dims =
                imageDimensions[imageUrl] ?? imageDimensions[node.imageUrl];
            if (dims == null) {
              for (final key in imageDimensions.keys) {
                if (key.toString() == imageUrl ||
                    key.toString().endsWith(imageUrl.split('/').last)) {
                  dims = imageDimensions[key];
                  break;
                }
              }
            }
            if (dims is Map<String, dynamic>) {
              final w =
                  (dims['width'] is num)
                      ? (dims['width'] as num).toDouble()
                      : double.tryParse(dims['width']?.toString() ?? '');
              final h =
                  (dims['height'] is num)
                      ? (dims['height'] as num).toDouble()
                      : double.tryParse(dims['height']?.toString() ?? '');
              if (w != null && h != null && w > 0) {
                dataMap['aspectRatio'] = h / w;
              }
            }
          }
        }

        final out = {'id': node.id, 'type': 'image', 'data': dataMap};
        if (paddingMode == 'full') {
          out['padding'] = 'full';
        }
        nodes.add(out);
        continue;
      }

      // ImageRowNode
      if (node is ImageRowNode) {
        bool hasSpoiler = false;
        final meta = node.metadata;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        List<String> imageUrls = node.imageUrls;
        if (forPublishing) {
          final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
          if (uploadedUrls != null && uploadedUrls.isNotEmpty) {
            final List<String> convertedUrls = [];
            final List<String> failedUrls = [];

            for (final url in node.imageUrls) {
              if (_isNetworkUrl(url)) {
                convertedUrls.add(url);
                continue;
              }
              final networkUrl = _resolveNetworkUrl(url, uploadedUrls);
              if (networkUrl != null) {
                convertedUrls.add(networkUrl);
              } else {
                failedUrls.add(url);
              }
            }

            if (failedUrls.isNotEmpty) {
              final isUploading = editorService.isNodeUploading(node.id);

              if (isUploading) {
                _throwUploadWait();
              } else {
                debugPrint(
                  '[PostExporter] ⚠️ ImageRow 업로드 미완료 URL 무시하고 진행: nodeId=${node.id}, drop=${failedUrls.join(", ")}',
                );
                imageUrls = convertedUrls;
              }
            } else {
              imageUrls = convertedUrls;
            }
          } else if (node.imageUrls.any((url) => !_isNetworkUrl(url))) {
            final isUploading = editorService.isNodeUploading(node.id);
            if (isUploading) {
              _throwUploadWait();
            } else if (allowPartialUpload) {
              debugPrint(
                '[PostExporter] 🎯 임시저장: ImageRow 로컬 경로 유지 (노드 ID: ${node.id})',
              );
            } else {
              debugPrint(
                '[PostExporter] ⚠️ ImageRow uploadedUrls 없음 + 로컬 포함: 로컬 이미지는 무시하고 진행 (nodeId=${node.id})',
              );
              imageUrls = node.imageUrls.where(_isNetworkUrl).toList();
            }
          }
        }

        if (imageUrls.isEmpty) {
          debugPrint(
            '[PostExporter] ⚠️ ImageRow export 스킵: 남은 이미지가 없음 (nodeId=${node.id})',
          );
          continue;
        }

        // 발행용: 로컬 경로 최종 방어 (페이로드 오염 방지)
        if (forPublishing) {
          imageUrls = _filterNetworkUrlsOnly(imageUrls);
          if (imageUrls.isEmpty) continue;
        }

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'imageRow',
          'urls': imageUrls,
        };

        if (node.spacing != 4.0) {
          nodeMap['spacing'] = node.spacing;
        }
        if (hasSpoiler) {
          nodeMap['spoiler'] = true;
        }

        // 이미지 크기 정보 저장
        final imageDimensions =
            meta['imageDimensions'] as Map<String, dynamic>?;

        if (imageDimensions != null && imageDimensions.isNotEmpty) {
          final convertedDimensions = <String, dynamic>{};
          final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;

          for (final url in imageUrls) {
            String? dimensionKey = url;
            if (uploadedUrls != null) {
              String? foundLocalPath;
              for (final entry in uploadedUrls.entries) {
                if (entry.value.toString() == url) {
                  foundLocalPath = entry.key;
                  break;
                }
              }
              if (foundLocalPath != null && foundLocalPath.isNotEmpty) {
                dimensionKey = foundLocalPath;
              }
            }

            dynamic dimensionData =
                imageDimensions[dimensionKey] ?? imageDimensions[url];

            if (dimensionData == null) {
              for (final key in imageDimensions.keys) {
                if (key.toString().endsWith(url.split('/').last) ||
                    url.endsWith(key.toString().split('/').last)) {
                  dimensionData = imageDimensions[key];
                  break;
                }
              }
            }

            if (dimensionData != null) {
              convertedDimensions[url] = dimensionData;
            }
          }

          if (convertedDimensions.isNotEmpty) {
            nodeMap['imageDimensions'] = convertedDimensions;
          } else if (!forPublishing) {
            // 발행용이면 raw imageDimensions(로컬 경로 키 가능) 사용 안 함
            nodeMap['imageDimensions'] = imageDimensions;
          }
        }

        nodes.add(nodeMap);
        continue;
      }

      // PageViewImageNode
      if (node is PageViewImageNode) {
        bool hasSpoiler = false;
        final meta = node.metadata;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        List<String> imageUrls = node.imageUrls;
        if (forPublishing) {
          final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
          if (uploadedUrls != null && uploadedUrls.isNotEmpty) {
            final List<String> convertedUrls = [];
            final List<String> failedUrls = [];

            for (final url in node.imageUrls) {
              if (_isNetworkUrl(url)) {
                convertedUrls.add(url);
                continue;
              }
              final networkUrl = _resolveNetworkUrl(url, uploadedUrls);
              if (networkUrl != null) {
                convertedUrls.add(networkUrl);
              } else {
                failedUrls.add(url);
              }
            }

            if (failedUrls.isNotEmpty) {
              final isUploading = editorService.isNodeUploading(node.id);
              if (isUploading) {
                _throwUploadWait();
              } else {
                debugPrint(
                  '[PostExporter] ⚠️ PageView 업로드 미완료 URL 무시하고 진행: nodeId=${node.id}, drop=${failedUrls.join(", ")}',
                );
                imageUrls = convertedUrls;
              }
            } else {
              imageUrls = convertedUrls;
            }
          } else if (node.imageUrls.any((url) => !_isNetworkUrl(url))) {
            final isUploading = editorService.isNodeUploading(node.id);
            if (isUploading) {
              _throwUploadWait();
            } else {
              debugPrint(
                '[PostExporter] ⚠️ PageView uploadedUrls 없음 + 로컬 포함: 로컬 이미지는 무시하고 진행 (nodeId=${node.id})',
              );
              imageUrls = node.imageUrls.where(_isNetworkUrl).toList();
            }
          }
        }

        if (imageUrls.isEmpty) {
          debugPrint(
            '[PostExporter] ⚠️ PageView export 스킵: 남은 이미지가 없음 (nodeId=${node.id})',
          );
          continue;
        }

        // 발행용: 로컬 경로 최종 방어 (페이로드 오염 방지)
        if (forPublishing) {
          imageUrls = _filterNetworkUrlsOnly(imageUrls);
          if (imageUrls.isEmpty) continue;
        }

        final hasComments = (meta['hasComments'] ?? false) == true;
        final commentCountRaw = meta['commentCount'];
        final commentCount =
            (commentCountRaw is num)
                ? commentCountRaw.toInt()
                : int.tryParse(commentCountRaw?.toString() ?? '0') ?? 0;

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'pageViewImage',
          'imageUrls': imageUrls,
        };

        if (hasSpoiler) nodeMap['spoiler'] = true;
        if (hasComments) nodeMap['hasComments'] = true;
        if (commentCount > 0) nodeMap['commentCount'] = commentCount;

        final imgCommentInfo = meta['imageCommentInfo'];
        if (imgCommentInfo is Map) {
          nodeMap['imageCommentInfo'] = imgCommentInfo;
        }

        final imageDimensions =
            meta['imageDimensions'] as Map<String, dynamic>?;
        if (imageDimensions != null && imageDimensions.isNotEmpty) {
          final convertedDimensions = <String, dynamic>{};
          final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;

          for (final url in imageUrls) {
            String? dimensionKey = url;
            if (uploadedUrls != null) {
              String? foundLocalPath;
              for (final entry in uploadedUrls.entries) {
                if (entry.value.toString() == url) {
                  foundLocalPath = entry.key;
                  break;
                }
              }
              if (foundLocalPath != null && foundLocalPath.isNotEmpty) {
                dimensionKey = foundLocalPath;
              }
            }

            dynamic dimensionData =
                imageDimensions[dimensionKey] ?? imageDimensions[url];
            if (dimensionData == null) {
              for (final key in imageDimensions.keys) {
                if (key.toString().endsWith(url.split('/').last) ||
                    url.endsWith(key.toString().split('/').last)) {
                  dimensionData = imageDimensions[key];
                  break;
                }
              }
            }

            if (dimensionData != null) {
              convertedDimensions[url] = dimensionData;
            }
          }

          if (convertedDimensions.isNotEmpty) {
            nodeMap['imageDimensions'] = convertedDimensions;
          } else if (!forPublishing) {
            nodeMap['imageDimensions'] = imageDimensions;
          }
        }

        nodes.add(nodeMap);
        continue;
      }

      // Video(ClipNode)
      if (node is ClipNode) {
        final meta = node.metadata;

        bool hasSpoiler = false;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        String videoUrl = node.url;
        if (forPublishing) {
          final isNetworkUrl = _isNetworkUrl(videoUrl);

          if (!isNetworkUrl) {
            final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
            if (uploadedUrls != null && uploadedUrls.isNotEmpty) {
              final originalPath = meta['originalLocalPath'] as String?;

              String? foundUrl;
              if (originalPath != null && originalPath.isNotEmpty) {
                foundUrl = uploadedUrls[originalPath]?.toString();
                if (foundUrl != null) {
                  videoUrl = foundUrl;
                }
              }

              if (foundUrl == null && node.localPath.isNotEmpty) {
                foundUrl = uploadedUrls[node.localPath]?.toString();
                if (foundUrl != null) {
                  videoUrl = foundUrl;
                }
              }

              if (foundUrl == null && videoUrl.isNotEmpty) {
                foundUrl = uploadedUrls[videoUrl]?.toString();
                if (foundUrl != null) {
                  videoUrl = foundUrl;
                }
              }

              if (foundUrl == null) {
                _throwUploadWait();
              }
            } else {
              _throwUploadWait();
            }
          }

          if (forPublishing && !_isNetworkUrl(videoUrl)) {
            _throwUploadWait();
          }
        }

        final dataMap = <String, dynamic>{'url': videoUrl};

        if (hasSpoiler) {
          dataMap['spoiler'] = true;
        }

        final paddingMode = meta['padding'] as String?;
        if (paddingMode == 'full') {
          dataMap['padding'] = 'full';
        }

        if (node.thumbnailPath.isNotEmpty) {
          dataMap['thumbnailPath'] = node.thumbnailPath;
        } else if (meta['thumbnailUrl'] != null) {
          dataMap['thumbnailUrl'] = meta['thumbnailUrl'];
        }

        if (meta['aspectRatio'] != null) {
          dataMap['aspectRatio'] = meta['aspectRatio'];
        }

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'video',
          'data': dataMap,
        };
        if (paddingMode == 'full') {
          nodeMap['padding'] = 'full';
        }

        nodes.add(nodeMap);
        continue;
      }

      // DividerNode
      if (node is DividerNode) {
        nodes.add({'id': node.id, 'type': 'divider'});
        continue;
      }

      if (node is LinkNode) {
        final meta = node.metadata;
        final padding = (meta['padding'] as String?)?.trim();
        final viewMode = (meta['viewMode'] as String?)?.trim();
        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'link',
          'url': node.url,
          'title': node.title,
          'description': node.description,
          'thumbnailUrl': node.thumbnailUrl,
          // 🎯 center/full, image/text-only 모드 항상 명시적 export
          'padding': (padding == 'full') ? 'full' : 'center',
          if (viewMode == 'compact') 'viewMode': 'compact',
        };
        nodes.add(nodeMap);
        continue;
      }

      // 미지원 노드는 타입만 기록
      nodes.add({'id': node.id, 'type': node.runtimeType.toString()});
    }

    // 제목: 제목 노드 텍스트 > 첫 번째 텍스트 노드 > 빈 문자열
    final title = extractTitleFromDocument(doc);

    final Map<String, dynamic> result = {
      'title': title,
      'content': {'nodes': nodes},
    };

    // 전역 폰트 사이즈 (있을 때만 추가)
    if (textStylingService != null) {
      try {
        final globalFontSize = (textStylingService as dynamic).globalFontSize;
        if (globalFontSize != null) {
          result['globalFontSize'] = globalFontSize;
        }
      } catch (e) {
        debugPrint('[PostExporter] ⚠️ 전역 폰트 사이즈 저장 실패: $e');
      }
    }

    return result;
  }

  /// 리치 텍스트(AttributedText)에서 spans를 추출한다.
  static List<Map<String, dynamic>> _buildParagraphSpans(AttributedText text) {
    if (text.text.isEmpty) return <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> spans = <Map<String, dynamic>>[];

    Map<String, dynamic> attrsAt(int offset) {
      if (offset < 0 || offset >= text.text.length) return <String, dynamic>{};
      final atts = text.getAllAttributionsAt(offset);
      return _normalizeAttributions(atts);
    }

    int runStart = 0;
    Map<String, dynamic> prev = attrsAt(0);
    for (int i = 1; i <= text.text.length; i++) {
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
    bool spoiler = false;
    double? fontSize;
    ui.Color? color;
    ui.Color? highlight;
    String? fontFamily;

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
        spoiler = true;
      } else if (a is HighlightAttribution) {
        highlight = a.color;
      } else if (a is ColorAttribution) {
        color = a.color;
      } else if (a is FontSizeAttribution) {
        fontSize = a.fontSize;
      } else if (a is FontFamilyAttribution) {
        fontFamily = a.fontFamily;
      }
    }

    final map = <String, dynamic>{
      if (bold) 'bold': true,
      if (italic) 'italic': true,
      if (underline) 'underline': true,
      if (strike) 'strikethrough': true,
      if (spoiler) 'spoiler': true,
      if (fontSize != null) 'font_size': fontSize,
      if (color != null) 'color': _hexColor(color),
      if (highlight != null) 'highlight': _hexColor(highlight),
      if (fontFamily != null && fontFamily.isNotEmpty) 'fontFamily': fontFamily,
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

  /// 네트워크 URL인지 확인하는 헬퍼 함수
  static bool _isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 로컬 경로 → 네트워크 URL 변환 (uploadedUrls 키 variant 시도)
  /// - path / file://path 등 플랫폼별 표현 차이 대응
  static String? _resolveNetworkUrl(
    String localOrUrl,
    Map<String, dynamic> uploadedUrls,
  ) {
    if (_isNetworkUrl(localOrUrl)) return localOrUrl;
    // 정확 매칭
    final v = uploadedUrls[localOrUrl];
    if (v != null) return v.toString();
    // file:// prefix variant (media_picker 등에서 file://$path 사용)
    final withFile =
        localOrUrl.startsWith('file://') ? localOrUrl : 'file://$localOrUrl';
    final v2 = uploadedUrls[withFile];
    if (v2 != null) return v2.toString();
    // file:// 제거 variant
    final withoutFile = localOrUrl.replaceFirst(RegExp(r'^file:///*'), '');
    if (withoutFile.isNotEmpty && withoutFile != localOrUrl) {
      final v3 = uploadedUrls[withoutFile];
      if (v3 != null) return v3.toString();
    }
    return null;
  }

  /// 발행용: URL 목록에서 로컬 경로 제거 (페이로드 오염 방지)
  static List<String> _filterNetworkUrlsOnly(List<String> urls) {
    return urls.where(_isNetworkUrl).toList();
  }

  /// onPublish 콜백에서 최종 발행 페이로드 생성
  /// exportedJson을 파싱 후 title, thumbnailImageUrl, accessLevel을 명시적으로 설정
  static Map<String, dynamic> buildPublishPayload({
    required String title,
    required String? thumbnailImageUrl,
    required String accessLevel,
    required String exportedJson,
  }) {
    final payload = jsonDecode(exportedJson) as Map<String, dynamic>;
    payload['title'] = title;
    payload['thumbnailImageUrl'] = thumbnailImageUrl;
    payload['accessLevel'] = accessLevel;
    return payload;
  }
}

/// 포스트 콘텐츠 관련 유틸리티 함수
class PostContentUtils {
  /// Map에서 문자열 값 읽기 (여러 키 시도)
  static String? readString(
    Map<String, dynamic> map, {
    required List<String> keys,
  }) {
    for (final k in keys) {
      final v = map[k];
      if (v is String) return v;
    }
    return null;
  }

  /// 본문(content.nodes)에서 "첫 번째 미디어 URL"을 찾는다.
  ///
  /// - 이미지 우선, 없으면 영상 URL 반환
  /// - 반드시 http(s) URL만 반환 (로컬 경로는 제외)
  static String findFirstBodyImageUrl(Map<String, dynamic> exported) {
    bool isHttpUrl(String u) =>
        u.startsWith('http://') || u.startsWith('https://');

    try {
      dynamic content = exported['content'];
      List<dynamic> nodes = const [];

      if (content is Map) {
        nodes = List<dynamic>.from(content['nodes'] as List? ?? const []);
        if (nodes.isEmpty) {
          final nested = content['content'];
          if (nested is Map) {
            nodes = List<dynamic>.from(nested['nodes'] as List? ?? const []);
          }
        }
      } else if (exported['nodes'] is List) {
        nodes = List<dynamic>.from(exported['nodes'] as List? ?? const []);
      }

      if (nodes.isEmpty) return '';

      for (final n in nodes) {
        if (n is! Map) continue;
        final type = (n['type'] ?? n['nodeType'] ?? '').toString();

        if (type == 'image') {
          final data = (n['data'] as Map?)?.cast<String, dynamic>();
          final url =
              (data?['url'] ??
                      data?['imageUrl'] ??
                      data?['src'] ??
                      n['url'] ??
                      n['imageUrl'] ??
                      '')
                  .toString();
          if (url.isNotEmpty && isHttpUrl(url)) return url;
        }

        if (type == 'imageRow') {
          final urls = List<dynamic>.from(
            n['urls'] ?? n['imageUrls'] ?? n['images'] ?? const [],
          );
          for (final u in urls) {
            final url = u.toString();
            if (url.isNotEmpty && isHttpUrl(url)) return url;
          }
        }

        if (type == 'pageViewImage' ||
            type == 'pageviewImage' ||
            type == 'page_view_image') {
          final urls = List<dynamic>.from(
            n['imageUrls'] ?? n['urls'] ?? n['images'] ?? const [],
          );
          for (final u in urls) {
            final url = u.toString();
            if (url.isNotEmpty && isHttpUrl(url)) return url;
          }
        }

        if (type == 'video' || type == 'clip') {
          final data = (n['data'] as Map?)?.cast<String, dynamic>();
          final url =
              (data?['url'] ??
                      data?['videoUrl'] ??
                      n['url'] ??
                      n['videoUrl'] ??
                      '')
                  .toString();
          if (url.isNotEmpty && isHttpUrl(url)) return url;
        }
      }
    } catch (_) {}

    return '';
  }
}
