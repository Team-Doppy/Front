import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/nodes/mention_node.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/material.dart';

import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/text_attributions.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'dart:convert';
import 'package:doppy/utils/mentioned_usernames_extractor.dart';

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
  /// [forPublishing]이 true이면 uploadedUrls를 확인하여 네트워크 URL로 변환
  /// [allowPartialUpload]이 true이면 업로드 완료되지 않은 이미지는 로컬 경로로 유지 (임시저장용)
  static String exportToJsonString({
    required EditorService editorService,
    required StickerService stickerService,
    Size? viewportSize,
    bool pretty = true,
    bool forPublishing = false,
    bool allowPartialUpload = false, // 🚀 임시저장 시 업로드 미완료 이미지 허용
    dynamic textStylingService, // TextStylingService (순환 참조 방지)
  }) {
    final map = exportToMap(
      editorService: editorService,
      stickerService: stickerService,
      viewportSize: viewportSize,
      forPublishing: forPublishing,
      allowPartialUpload: allowPartialUpload,
      textStylingService: textStylingService,
    );
    return JsonExport.encode(map, pretty: pretty);
  }

  /// 문서에서 제목 추출 (더 이상 사용되지 않음, 빈 문자열 반환)
  static String getTitleFromDocument(MutableDocument document) {
    return '';
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

      // 스티커에서 이미지 URL 수집 (PNG 드로잉 포함)
      final contentStickers =
          (content is Map ? (content['stickers'] as List?) : null) ?? const [];
      for (final sticker in contentStickers) {
        if (sticker is! Map) continue;
        final stickerType = (sticker['type'] ?? '').toString();
        if (stickerType == 'image') {
          final stickerContent = sticker['content'];
          String? url;

          if (stickerContent is Map) {
            // URL + 크기 정보 (PNG 드로잉) 또는 레거시 {url: ...}
            url = (stickerContent['url'] ?? '').toString();
          } else if (stickerContent is String) {
            // 레거시: content가 직접 URL 문자열인 경우
            url = stickerContent;
          }

          if (url != null &&
              url.isNotEmpty &&
              (url.startsWith('http://') || url.startsWith('https://'))) {
            usedUrls.add(url);
          }
        }
      }
    } catch (e) {
      debugPrint('[PostExporter] 미디어 URL 수집 실패: $e');
    }

    return usedUrls.toList();
  }

  /// 편집 중 문서/스티커를 JSON(Map)으로 내보낸다.
  /// [forPublishing]이 true이면 uploadedUrls를 확인하여 네트워크 URL로 변환
  /// [allowPartialUpload]이 true이면 업로드 완료되지 않은 이미지는 로컬 경로로 유지 (임시저장용)
  static Map<String, dynamic> exportToMap({
    required EditorService editorService,
    required StickerService stickerService,
    Size? viewportSize,
    bool forPublishing = false,
    bool allowPartialUpload = false, // 🚀 임시저장 시 업로드 미완료 이미지 허용
    dynamic textStylingService, // TextStylingService (순환 참조 방지)
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

        final align = meta['textAlign'] as String?;
        final fontFamily = meta['fontFamily'] as String?;

        // 🎯 폰트 메타데이터 디버그 로그
        if (fontFamily != null && fontFamily.isNotEmpty) {
          debugPrint(
            '[PostExporter] 📝 ParagraphNode ${node.id} - fontFamily 메타데이터 발견: $fontFamily',
          );
        }

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
        if (fontFamily != null && fontFamily.isNotEmpty) {
          nodeMap['fontFamily'] = fontFamily;
          debugPrint(
            '[PostExporter] ✅ JSON에 fontFamily 추가: $fontFamily (노드 ID: ${node.id})',
          );
        }
        // spoiler는 spans에서 처리하므로 노드 레벨에서는 제거

        nodes.add(nodeMap);
        continue;
      }

      // ImageNode (SuperEditor 내장)
      if (node is ImageNode) {
        // metadata에서 spoiler 추출
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
        // - 이미 네트워크 URL이면 그대로 사용 (편집 모드에서 기존 발행된 이미지)
        // - 로컬 경로이면 uploadedUrls에서 변환 (편집 중 새로 추가한 이미지)
        String imageUrl = node.imageUrl;
        if (forPublishing && meta != null) {
          final isNetworkUrl = _isNetworkUrl(imageUrl);

          if (!isNetworkUrl) {
            // 로컬 경로인 경우 uploadedUrls에서 변환 (필수)
            final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
            if (uploadedUrls != null && uploadedUrls[imageUrl] != null) {
              imageUrl = uploadedUrls[imageUrl].toString();
              debugPrint(
                '[PostExporter] 🔄 단일 이미지 네트워크 URL 변환: ${node.imageUrl} -> $imageUrl',
              );
            } else {
              // 🎯 UploadService로 실제 업로드 상태 확인 (ref 태스크 기반)
              final isUploading = editorService.isNodeUploading(node.id);

              if (isUploading) {
                // 🚀 업로드 중: 임시저장 불가 (업로드 완료 대기)
                throw StateError(
                  '임시저장 불가: 이미지가 업로드 중입니다. '
                  '이미지 업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id}, URL: ${node.imageUrl})',
                );
              } else if (allowPartialUpload) {
                // 🎯 allowPartialUpload이 true이면 로컬 경로 유지 (발행 시에만 사용)
                debugPrint(
                  '[PostExporter] 🎯 임시저장: 단일 이미지 로컬 경로 유지 (노드 ID: ${node.id})',
                );
              } else {
                // 🚀 변환 실패: 업로드되지 않은 이미지 (발행/임시저장 불가)
                throw StateError(
                  '${allowPartialUpload ? "임시저장" : "발행"} 불가: 이미지가 업로드되지 않았습니다. '
                  '이미지 업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id}, URL: ${node.imageUrl})',
                );
              }
            }
          }
          // 이미 네트워크 URL이면 변환 불필요 (기존 발행된 이미지)
        }

        final dataMap = <String, dynamic>{'url': imageUrl};

        // true일 때만 추가 (false는 키 없음으로 표현)
        if (hasSpoiler) {
          dataMap['spoiler'] = true;
        }

        final out = {'id': node.id, 'type': 'image', 'data': dataMap};
        // 패딩 모드: 기본(center)일 때는 생략, full만 저장
        if (paddingMode == 'full') {
          out['padding'] = 'full';
          debugPrint('[PostExporter] ImageNode ${node.id} padding=full 저장');
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

        debugPrint('[PostExporter] 🔍 ImageRowNode 저장 시작: ${node.id}');
        debugPrint('[PostExporter] 🔍 URLs: ${node.imageUrls}');
        debugPrint('[PostExporter] 🔍 metadata: ${meta.keys.toList()}');
        debugPrint(
          '[PostExporter] 🔍 imageDimensions 존재 여부: ${meta.containsKey('imageDimensions')}',
        );
        if (meta.containsKey('imageDimensions')) {
          debugPrint(
            '[PostExporter] 🔍 imageDimensions 내용: ${meta['imageDimensions']}',
          );
        }

        // 🚀 forPublishing이 true이고 uploadedUrls가 있으면 네트워크 URL로 변환
        // - 이미 네트워크 URL이면 그대로 사용 (편집 모드에서 기존 발행된 이미지)
        // - 로컬 경로이면 uploadedUrls에서 변환 (편집 중 새로 추가한 이미지)
        List<String> imageUrls = node.imageUrls;
        if (forPublishing) {
          final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
          if (uploadedUrls != null && uploadedUrls.isNotEmpty) {
            final List<String> convertedUrls = [];
            final List<String> failedUrls = [];

            for (final url in node.imageUrls) {
              // 이미 네트워크 URL이면 변환 불필요
              if (_isNetworkUrl(url)) {
                convertedUrls.add(url); // 기존 발행된 이미지
                continue;
              }

              // 로컬 경로인 경우 변환 (필수)
              final networkUrl = uploadedUrls[url];
              if (networkUrl != null) {
                convertedUrls.add(networkUrl.toString());
                debugPrint(
                  '[PostExporter] 🔄 ImageRow 네트워크 URL 변환: $url -> $networkUrl',
                );
              } else {
                failedUrls.add(url);
              }
            }

            // 🚀 변환 실패한 URL 처리
            if (failedUrls.isNotEmpty) {
              // 🎯 UploadService로 실제 업로드 상태 확인 (ref 태스크 기반)
              final isUploading = editorService.isNodeUploading(node.id);

              if (isUploading) {
                // 🚀 업로드 중: 임시저장 불가 (업로드 완료 대기)
                throw StateError(
                  '임시저장 불가: 이미지 행의 일부 이미지가 업로드 중입니다. '
                  '이미지 업로드가 완료될 때까지 기다려주세요. '
                  '(노드 ID: ${node.id}, 실패한 URL: ${failedUrls.join(", ")})',
                );
              } else if (allowPartialUpload) {
                // 🎯 allowPartialUpload이 true이면 로컬 경로 유지 (발행 시에만 사용)
                debugPrint(
                  '[PostExporter] 🎯 임시저장: ImageRow 일부 이미지 로컬 경로 유지 (노드 ID: ${node.id}, 실패한 URL: ${failedUrls.join(", ")})',
                );
                // 변환된 URL과 실패한 URL을 모두 포함
                imageUrls = convertedUrls + failedUrls;
              } else {
                // 🚀 변환 실패: 업로드되지 않은 이미지 (발행/임시저장 불가)
                throw StateError(
                  '${allowPartialUpload ? "임시저장" : "발행"} 불가: 이미지 행의 일부 이미지가 업로드되지 않았습니다. '
                  '모든 이미지 업로드가 완료될 때까지 기다려주세요. '
                  '(노드 ID: ${node.id}, 실패한 URL: ${failedUrls.join(", ")})',
                );
              }
            } else {
              imageUrls = convertedUrls;
            }
          } else if (node.imageUrls.any((url) => !_isNetworkUrl(url))) {
            // uploadedUrls가 없는데 로컬 경로가 있으면
            // 🎯 UploadService로 실제 업로드 상태 확인 (ref 태스크 기반)
            final isUploading = editorService.isNodeUploading(node.id);

            if (isUploading) {
              // 🚀 업로드 중: 임시저장 불가 (업로드 완료 대기)
              throw StateError(
                '임시저장 불가: 이미지 행이 업로드 중입니다. '
                '이미지 업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id})',
              );
            } else if (allowPartialUpload) {
              // 🎯 allowPartialUpload이 true이면 로컬 경로 유지 (발행 시에만 사용)
              debugPrint(
                '[PostExporter] 🎯 임시저장: ImageRow 로컬 경로 유지 (노드 ID: ${node.id})',
              );
            } else {
              // 🚀 변환 실패: 업로드되지 않은 이미지 (발행/임시저장 불가)
              throw StateError(
                '${allowPartialUpload ? "임시저장" : "발행"} 불가: 이미지 행에 업로드되지 않은 이미지가 있습니다. '
                '이미지 업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id})',
              );
            }
          }
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

        // 이미지 크기 정보 저장 (임시저장 불러올 때 빠른 높이 계산용)
        final imageDimensions =
            meta['imageDimensions'] as Map<String, dynamic>?;
        debugPrint(
          '[PostExporter] 🔍 imageDimensions 체크: ${imageDimensions != null ? "있음 (${imageDimensions.length}개)" : "없음"}',
        );

        if (imageDimensions != null && imageDimensions.isNotEmpty) {
          debugPrint(
            '[PostExporter] 🔍 imageDimensions 키: ${imageDimensions.keys.toList()}',
          );
          // URL 변환이 발생했으면 크기 정보도 키를 변환
          final convertedDimensions = <String, dynamic>{};
          final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;

          for (final url in imageUrls) {
            // 네트워크 URL로 변환된 경우, 로컬 경로 키의 크기 정보를 찾아서 매핑
            String? dimensionKey = url;
            if (uploadedUrls != null) {
              // uploadedUrls에서 역방향 검색 (networkUrl -> localPath)
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

            // 🎯 여러 키로 시도: dimensionKey, url, 그리고 imageDimensions의 모든 키에서 매칭
            dynamic dimensionData =
                imageDimensions[dimensionKey] ?? imageDimensions[url];

            // 🎯 정확히 매칭되지 않으면 부분 매칭 시도 (URL 끝부분 비교)
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
              debugPrint(
                '[PostExporter] ✅ 이미지 크기 매칭 성공: $url -> $dimensionData',
              );
            } else {
              debugPrint('[PostExporter] ⚠️ 이미지 크기 매칭 실패: $url');
            }
          }

          // 🎯 convertedDimensions 저장 (발행/임시저장 모두)
          if (convertedDimensions.isNotEmpty) {
            nodeMap['imageDimensions'] = convertedDimensions;
            debugPrint(
              '[PostExporter] ✅ convertedDimensions 저장: ${convertedDimensions.length}개',
            );
          } else {
            // 🎯 convertedDimensions가 비어있으면 원본 그대로 저장 (발행/임시저장 모두)
            // 발행된 글을 다른 사람이 볼 때도 빠른 높이 계산을 위해 필요
            // URL 매칭이 실패해도 원본 메타데이터를 그대로 저장
            nodeMap['imageDimensions'] = imageDimensions;
            debugPrint(
              '[PostExporter] ✅ 원본 imageDimensions 저장 (매칭 실패했지만 원본 저장): ${imageDimensions.length}개',
            );
          }
        } else {
          debugPrint(
            '[PostExporter] ⚠️ imageDimensions가 없거나 비어있음 - 메타데이터에 저장되지 않았을 수 있음',
          );
        }

        debugPrint('[PostExporter] 🔍 최종 nodeMap: $nodeMap');
        nodes.add(nodeMap);
        continue;
      }

      // PageViewImageNode (여러 이미지를 PageView로 표시)
      if (node is PageViewImageNode) {
        // 스포일러 확인: metadata 또는 NodeComponentService
        bool hasSpoiler = false;
        final meta = node.metadata;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        // 🚀 forPublishing이 true이고 uploadedUrls가 있으면 네트워크 URL로 변환
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
              final networkUrl = uploadedUrls[url];
              if (networkUrl != null) {
                convertedUrls.add(networkUrl.toString());
              } else {
                failedUrls.add(url);
              }
            }

            if (failedUrls.isNotEmpty) {
              final isUploading = editorService.isNodeUploading(node.id);
              if (isUploading) {
                throw StateError(
                  '임시저장 불가: 페이지뷰 이미지가 업로드 중입니다. '
                  '업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id}, 실패한 URL: ${failedUrls.join(", ")})',
                );
              } else if (allowPartialUpload) {
                imageUrls = convertedUrls + failedUrls;
              } else {
                throw StateError(
                  '${allowPartialUpload ? "임시저장" : "발행"} 불가: 페이지뷰 이미지 중 업로드되지 않은 이미지가 있습니다. '
                  '업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id}, 실패한 URL: ${failedUrls.join(", ")})',
                );
              }
            } else {
              imageUrls = convertedUrls;
            }
          } else if (node.imageUrls.any((url) => !_isNetworkUrl(url))) {
            final isUploading = editorService.isNodeUploading(node.id);
            if (isUploading) {
              throw StateError(
                '임시저장 불가: 페이지뷰 이미지가 업로드 중입니다. '
                '업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id})',
              );
            } else if (!allowPartialUpload) {
              throw StateError(
                '${allowPartialUpload ? "임시저장" : "발행"} 불가: 페이지뷰 이미지에 업로드되지 않은 이미지가 있습니다. '
                '업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id})',
              );
            }
          }
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

          nodeMap['imageDimensions'] =
              convertedDimensions.isNotEmpty
                  ? convertedDimensions
                  : imageDimensions;
        }

        nodes.add(nodeMap);
        continue;
      }

      // Video(ClipNode) → 서버 규격: { type: "video", data: { url } }
      if (node is ClipNode) {
        final meta = node.metadata;

        // 스포일러 확인: metadata 또는 NodeComponentService
        bool hasSpoiler = false;
        if (meta['spoiler'] == true) {
          hasSpoiler = true;
        } else {
          final nodeService = NodeComponentService();
          hasSpoiler = nodeService.isSpoiler(node.id);
        }

        // 🚀 forPublishing이 true이고 uploadedUrls가 있으면 네트워크 URL로 변환
        // - 이미 네트워크 URL이면 그대로 사용 (편집 모드에서 기존 발행된 비디오)
        // - 로컬 경로이면 uploadedUrls에서 변환 (편집 중 새로 추가한 비디오)
        String videoUrl = node.url;
        if (forPublishing) {
          final isNetworkUrl = _isNetworkUrl(videoUrl);

          if (!isNetworkUrl) {
            // 로컬 경로인 경우 uploadedUrls에서 변환 (필수)
            // 🎯 이미지와 동일한 구조: 원본 경로를 키로 사용
            final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
            if (uploadedUrls != null && uploadedUrls.isNotEmpty) {
              // 원본 경로를 metadata에서 가져오기
              final originalPath = meta['originalLocalPath'] as String?;

              // 🎯 원본 경로를 우선적으로 사용 (uploadedUrls의 키는 원본 경로)
              String? foundUrl;
              if (originalPath != null && originalPath.isNotEmpty) {
                foundUrl = uploadedUrls[originalPath]?.toString();
                if (foundUrl != null) {
                  videoUrl = foundUrl;
                  debugPrint(
                    '[PostExporter] 🔄 Video 네트워크 URL 변환 (원본 경로): $originalPath -> $videoUrl',
                  );
                }
              }

              // 원본 경로로 찾지 못했으면 localPath로 시도
              if (foundUrl == null && node.localPath.isNotEmpty) {
                foundUrl = uploadedUrls[node.localPath]?.toString();
                if (foundUrl != null) {
                  videoUrl = foundUrl;
                  debugPrint(
                    '[PostExporter] 🔄 Video 네트워크 URL 변환 (localPath): ${node.localPath} -> $videoUrl',
                  );
                }
              }

              // localPath로도 찾지 못했으면 url 자체가 로컬 경로인 경우 시도
              if (foundUrl == null && videoUrl.isNotEmpty) {
                foundUrl = uploadedUrls[videoUrl]?.toString();
                if (foundUrl != null) {
                  videoUrl = foundUrl;
                  debugPrint(
                    '[PostExporter] 🔄 Video 네트워크 URL 변환 (url): ${node.url} -> $videoUrl',
                  );
                }
              }

              // 모든 시도 실패
              if (foundUrl == null) {
                // 🚀 변환 실패: 업로드되지 않은 비디오 (임시저장/발행 모두 불가)
                throw StateError(
                  '${allowPartialUpload ? '임시저장' : '발행'} 불가: 비디오가 업로드되지 않았습니다. '
                  '비디오 업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id}, URL: ${node.url})',
                );
              }
            } else {
              // uploadedUrls가 없는데 로컬 경로면 에러 (임시저장/발행 모두 불가)
              throw StateError(
                '${allowPartialUpload ? '임시저장' : '발행'} 불가: 비디오가 업로드되지 않았습니다. '
                '비디오 업로드가 완료될 때까지 기다려주세요. (노드 ID: ${node.id})',
              );
            }
          }
          // 이미 네트워크 URL이면 변환 불필요 (기존 발행된 비디오)

          // 🎯 최종 검증: forPublishing일 때는 반드시 네트워크 URL이어야 함
          if (forPublishing && !_isNetworkUrl(videoUrl)) {
            debugPrint(
              '[PostExporter] ⚠️ 비디오 URL이 여전히 로컬 경로입니다: $videoUrl (노드 ID: ${node.id})',
            );
            throw StateError(
              '발행 불가: 비디오 URL이 로컬 경로입니다. '
              '비디오 업로드가 완료되지 않았거나 변환에 실패했습니다. '
              '(노드 ID: ${node.id}, URL: $videoUrl)',
            );
          }
        }

        final dataMap = <String, dynamic>{'url': videoUrl};

        if (hasSpoiler) {
          dataMap['spoiler'] = true;
        }

        // 패딩 모드 내보내기 (기본값: 'center'는 생략, 'full'만 명시)
        final paddingMode = meta['padding'] as String?;
        if (paddingMode == 'full') {
          dataMap['padding'] = 'full';
        }

        // 🎯 임시저장용 썸네일 경로 저장 (복원 시 드래그 오버레이에 필요)
        if (node.thumbnailPath.isNotEmpty) {
          dataMap['thumbnailPath'] = node.thumbnailPath;
        }
        // metadata의 thumbnailUrl도 저장 (네트워크 썸네일)
        else if (meta['thumbnailUrl'] != null) {
          dataMap['thumbnailUrl'] = meta['thumbnailUrl'];
        }

        // 🎯 aspectRatio 저장 (복원 시 비율 유지)
        if (meta['aspectRatio'] != null) {
          dataMap['aspectRatio'] = meta['aspectRatio'];
        }

        // 노드 레벨에도 패딩 정보 저장 (이미지와 동일한 방식)
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

      // MentionNode
      if (node is MentionNode) {
        final meta = node.metadata;
        final textAlign = meta['textAlign'] as String?;
        final fontSize = meta['fontSize'] as num?;

        final nodeMap = <String, dynamic>{
          'id': node.id,
          'type': 'mention',
          'usernames': node.usernames,
        };

        if (textAlign != null && textAlign != 'center') {
          nodeMap['align'] = textAlign;
        }
        if (fontSize != null) {
          nodeMap['fontSize'] = fontSize;
        }

        nodes.add(nodeMap);
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

      // 🎯 PNG 드로잉만 지원 (StickerType.image만 처리)
      if (s.type == StickerType.image) {
        if (s.content is Map) {
          // ✅ URL + 크기 정보 (PNG 드로잉)
          base['content'] = s.content; // {url, width, height}
        } else if (s.content is String) {
          // 레거시: URL만 있음
          base['content'] = {'url': s.content};
        } else if (s.content is Uint8List) {
          // ⚠️ 업로드가 완료되지 않은 경우 (에러)
          debugPrint('❌ [PostExporter] 스티커 ${s.id}의 이미지가 아직 업로드 중입니다!');
          base['content'] = {
            'bytes': s.content, // 임시로 base64로 저장
          };
        }
      } else {
        // text, emoji, drawing 타입은 무시
        continue;
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

    // 🎯 백그라운드에서 돌아왔을 때를 대비해 여러 소스에서 author 가져오기
    // 1. AuthService의 동기 캐시에서 먼저 시도 (가장 안정적)
    String author = AuthService().currentUsernameSync ?? '';

    // 2. 없으면 AuthProvider에서 가져오기
    if (author.isEmpty) {
      author = AuthProvider().username ?? '';
    }

    // 3. 여전히 없으면 에러 (백그라운드에서 돌아왔을 때는 AuthService.currentUsernameSync가 있어야 함)
    if (author.isEmpty) {
      debugPrint(
        '[PostExporter] ⚠️ author를 가져올 수 없습니다. AuthService.currentUsernameSync와 AuthProvider().username 모두 비어있습니다.',
      );
      throw StateError('author is required');
    }

    // 제목은 Step1(썸네일 편집 화면)에서 입력하므로 빈 문자열로 설정
    final title = '';

    //초안 뽑기
    final Map<String, dynamic> result = {
      'title': title,
      'author': author,
      'content': {'nodes': nodes, 'stickers': stickers},
    };

    // 🎯 전역 폰트 사이즈 저장
    if (textStylingService != null) {
      try {
        final globalFontSize = (textStylingService as dynamic).globalFontSize;
        if (globalFontSize != null) {
          result['globalFontSize'] = globalFontSize;
          debugPrint('[PostExporter] ✅ 전역 폰트 사이즈 저장: $globalFontSize');
        }
      } catch (e) {
        debugPrint('[PostExporter] ⚠️ 전역 폰트 사이즈 저장 실패: $e');
      }
    }

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
    String? fontFamily; // 🎯 span 단위 폰트 지원

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
      } else if (a is FontFamilyAttribution) {
        // 🎯 span 단위 폰트 패밀리 (Attribution 기반 정교한 적용)
        fontFamily = a.fontFamily;
        debugPrint(
          '[PostExporter] 📝 Span에 FontFamilyAttribution 발견: $fontFamily',
        );
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
      if (fontFamily != null && fontFamily.isNotEmpty)
        'fontFamily': fontFamily, // 🎯 span 단위 폰트 export
    };

    if (fontFamily != null && fontFamily.isNotEmpty) {
      debugPrint('[PostExporter] ✅ Span에 fontFamily 추가: $fontFamily');
    }

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
    // 🎯 PNG 드로잉만 지원
    return 'image';
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
    // 🎯 base에 이미 usedImageUrls가 있으면 사용 (수정 시 PostPublishService에서 이미 수집한 경우)
    if (base['usedImageUrls'] != null && base['usedImageUrls'] is List) {
      final existingUrls = List<String>.from(base['usedImageUrls'] as List);
      debugPrint(
        '[PostExporter] 📌 base에서 기존 usedImageUrls 사용: ${existingUrls.length}개',
      );
      result['usedImageUrls'] = existingUrls;
    } else {
      // 🎯 새로 작성하는 경우에만 수집
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
            // 🚀 발행 시에는 네트워크 URL만 수집 (로컬 경로 제외)
            if (url.isNotEmpty && _isNetworkUrl(url)) {
              usedUrls.add(url);
            }
          } else if (type == 'imageRow') {
            final List<dynamic> urls = List<dynamic>.from(
              n['urls'] ?? const [],
            );
            for (final u in urls) {
              final String url = u.toString();
              // 🚀 발행 시에는 네트워크 URL만 수집 (로컬 경로 제외)
              if (url.isNotEmpty && _isNetworkUrl(url)) {
                usedUrls.add(url);
              }
            }
          } else if (type == 'video') {
            // data.url에서 추출
            final data = n['data'] as Map<String, dynamic>?;
            final String url = (data?['url'] ?? '').toString();
            // 🚀 발행 시에는 네트워크 URL만 수집 (로컬 경로 제외)
            if (url.isNotEmpty && _isNetworkUrl(url)) {
              usedUrls.add(url);
            }
          }
        }

        // 썸네일 URL도 포함
        if (thumbnailImageUrl.trim().isNotEmpty) {
          usedUrls.add(thumbnailImageUrl.trim());
        }

        // 🎯 스티커 이미지 URL도 포함 (PNG 드로잉 포함)
        final List<dynamic> contentStickers = List<dynamic>.from(
          (content is Map ? content['stickers'] : null) as List? ?? const [],
        );
        debugPrint(
          '[PostExporter] 📌 content.stickers 개수: ${contentStickers.length}',
        );
        for (final s in contentStickers) {
          if (s is! Map) continue;
          final String stickerType = (s['type'] ?? '').toString();
          debugPrint('[PostExporter] 📌 스티커 타입: $stickerType');
          if (stickerType == 'image') {
            final contentMap = s['content'] as Map<String, dynamic>?;
            debugPrint('[PostExporter] 📌 content: $contentMap');
            if (contentMap != null) {
              final String url = (contentMap['url'] ?? '').toString();
              debugPrint('[PostExporter] 📌 URL: $url');
              if (url.isNotEmpty) {
                usedUrls.add(url);
                debugPrint('[PostExporter] ✅ 스티커 URL 추가: $url');
              }
            }
          }
        }

        // 결과 키는 기존과 동일하게 유지(호환)하되 값은 URL 문자열 목록로 제공
        result['usedImageUrls'] = usedUrls.toList();
      } catch (e) {
        debugPrint('❌ usedImageUrls 수집 실패: $e');
      }
    }

    debugPrint('==============================================');
    debugPrint('Final API Payload (Server Spec Compliant):');
    debugPrint('Title: $title');
    debugPrint('AccessLevel: $accessLevel');
    if (accessLevel == 'GROUPS') {
      debugPrint('SharedGroupIds: $sharedGroupIds');
    }
    debugPrint('Thumbnail: ${result['thumbnailImageUrl'] ?? 'none'}');
    debugPrint('UsedImageUrls: ${result['usedImageUrls'] ?? 'none'}');

    // 10. mentionedUsernames
    // ✅ 멘션은 "텍스트 @파싱"이 아니라 에디터 메타(mention 노드)를 1순위로 사용해야 누락/오판이 적다.
    // - 서버 스펙: null 또는 [] 모두 허용
    // - 요구사항: 발행 시 항상 필드 자체는 포함
    try {
      if (base['mentionedUsernames'] is List) {
        final existing = List<String>.from(base['mentionedUsernames'] as List);
        result['mentionedUsernames'] = existing;
        debugPrint(
          '[PostExporter] 📌 base에서 기존 mentionedUsernames 사용: ${existing.length}개',
        );
      } else {
        final contentMap =
            (base['content'] is Map)
                ? (base['content'] as Map).cast<String, dynamic>()
                : null;
        final mentions = MentionedUsernamesExtractor.extractFromContent(
          contentMap,
        );
        result['mentionedUsernames'] = mentions; // 빈 배열도 포함
        debugPrint(
          '[PostExporter] ✅ mentionedUsernames 수집: ${mentions.length}개',
        );
      }
    } catch (e) {
      // 실패해도 발행은 막지 않되, 필드는 포함
      result['mentionedUsernames'] = <String>[];
      debugPrint('[PostExporter] ❌ mentionedUsernames 수집 실패: $e');
    }

    debugPrint(JsonExport.encode(result, pretty: true));

    return result;
  }

  /// 네트워크 URL인지 확인하는 헬퍼 함수
  static bool _isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }
}

class _AnchorCandidate {
  final String nodeId;
  final Rect rect;
  _AnchorCandidate({required this.nodeId, required this.rect});
}
