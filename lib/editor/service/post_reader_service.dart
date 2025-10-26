import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/sticker_service.dart';
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
          final attributed = _buildAttributedText(text, spans);
          final meta = <String, dynamic>{'textAlign': align};

          // fontFamily를 메타데이터에서 추출하여 추가
          if (m['fontFamily'] != null) {
            meta['fontFamily'] = m['fontFamily'];
          }

          // isTitle 정보도 메타데이터에 추가 (드래프트 복구시 제목 노드 인식용)
          if (isTitle) {
            meta['isTitle'] = true;
          }

          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
          break;

        case 'image':
          rebuilt.add(
            ImageNode(
              id: id,
              imageUrl: (m['url'] ?? '').toString(),
              altText: (m['altText'] ?? '').toString(),
            ),
          );
          break;

        case 'imageRow':
          rebuilt.add(
            ImageRowNode(
              id: id,
              imageUrls:
                  ((m['urls'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
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
          rebuilt.add(
            MentionNode(
              id: id,
              usernames:
                  ((m['usernames'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
            ),
          );
          break;

        case 'divider':
          rebuilt.add(DividerNode(id: id));
          break;

        case 'clip':
          rebuilt.add(
            ClipNode(
              id: id,
              label: (m['label'] ?? '').toString(),
              colorHex: (m['color'] ?? '#FF5252').toString(),
              url: (m['url'] ?? '').toString(),
            ),
          );
          break;

        default:
          // 알 수 없는 노드는 문단으로 폴백
          rebuilt.add(ParagraphNode(id: id, text: AttributedText('[${type}]')));
      }
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
          print(
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
          print('DEBUG: PostReaderService 형광펜 디코딩 - HEX: $highlightHex');
          final highlightColor = _parseHexColor(highlightHex);
          print('DEBUG: PostReaderService 형광펜 디코딩 - 색상: $highlightColor');
          atts.add(HighlightAttribution(highlightColor));
        }

        // 폰트 패밀리 속성
        final fontFamily = ann['fontFamily'] as String?;
        if (fontFamily != null && fontFamily.isNotEmpty) {
          atts.add(FontFamilyAttribution(fontFamily));
        }

        // 속성을 텍스트에 적용
        for (final a in atts) {
          attributed.addAttribution(a, SpanRange(start, end - 1));
        }
      }
    } catch (e) {
      print('[PostReaderService] Error building attributed text: $e');
      // 오류 발생 시 기본 텍스트 반환
    }

    return attributed;
  }

  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }

  /// 컨텐츠에서 이미지 URL을 추출한다
  List<String> extractImageUrls(Map<String, dynamic> content) {
    final List<String> imageUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];

    for (final raw in nodes) {
      if (imageUrls.length >= 6) break;

      final m = (raw as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();

      if (type == 'image') {
        final url = (m['url'] ?? '').toString();
        if (url.isNotEmpty) imageUrls.add(url);
      } else if (type == 'imageRow') {
        final urls =
            ((m['urls'] as List?) ?? const [])
                .map((e) => e.toString())
                .where((u) => u.isNotEmpty)
                .toList();
        imageUrls.addAll(urls);
      }
    }

    return imageUrls;
  }

  /// 컨텐츠에서 클립(영상) URL을 추출한다
  List<String> extractClipUrls(Map<String, dynamic> content) {
    final List<String> clipUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];

    for (final raw in nodes) {
      if (clipUrls.length >= 2) break; // 최대 2개만 프리캐싱

      final m = (raw as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();

      if (type == 'clip') {
        final url = (m['url'] ?? '').toString();
        if (url.isNotEmpty) clipUrls.add(url);
      }
    }

    return clipUrls;
  }

  /// 이미지를 미리 로드한다
  Future<void> preloadImages(
    BuildContext context,
    List<String> imageUrls, {
    int maxCount = 6,
  }) async {
    final imagesToPreload = imageUrls.take(maxCount).toList();

    if (imagesToPreload.isEmpty) {
      return;
    }

    print('[PostReaderService] 이미지 ${imagesToPreload.length}개 미리 로드 시작');

    try {
      await Future.wait(
        imagesToPreload.map((url) {
          return precacheImage(
            NetworkImage(url),
            context,
            onError: (e, stack) {
              print('[PostReaderService] 이미지 프리캐싱 실패: $url - $e');
            },
          );
        }),
      );
      print('[PostReaderService] 이미지 프리캐싱 완료');
    } catch (e) {
      print('[PostReaderService] 이미지 프리캐싱 중 오류: $e');
    }
  }

  // ===== 영상 프리로드 컨트롤러 캐시 =====
  static final Map<String, VideoPlayerController> _preloadedControllers = {};

  /// 프리로드된 컨트롤러를 전달하고 캐시에서 제거한다 (소유권 이전)
  static VideoPlayerController? takePreloadedController(String url) {
    return _preloadedControllers.remove(url);
  }

  /// 남아있는 프리로드 컨트롤러 정리
  static void disposeAllPreloaded() {
    for (final c in _preloadedControllers.values) {
      c.dispose();
    }
    _preloadedControllers.clear();
  }

  /// 클립(영상)을 미리 로드한다
  Future<void> preloadClips(BuildContext context, List<String> clipUrls) async {
    if (clipUrls.isEmpty) {
      return;
    }

    print('[PostReaderService] 클립 ${clipUrls.length}개 미리 로드 시작');

    try {
      // 컨트롤러를 초기화하여 캐시에 저장 (나중에 위젯이 재사용)
      for (final url in clipUrls) {
        if (_preloadedControllers.containsKey(url)) {
          print('[PostReaderService] 이미 프리로드됨: $url');
          continue;
        }
        final controller = VideoPlayerController.networkUrl(Uri.parse(url));
        try {
          await controller.initialize();
          // 음소거 기본값 유지(소리는 위젯에서 제어)
          _preloadedControllers[url] = controller;
          print('[PostReaderService] 클립 프리캐싱 완료: $url');
        } catch (e) {
          print('[PostReaderService] 클립 프리캐싱 실패: $url - $e');
          await controller.dispose();
        }
      }
      print('[PostReaderService] 클립 프리캐싱 완료');
    } catch (e) {
      print('[PostReaderService] 클립 프리캐싱 중 오류: $e');
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
      print('[PostReaderService] Error restoring stickers: $e');
    }
  }
}
