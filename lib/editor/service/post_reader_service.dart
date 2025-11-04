import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
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
          final data = (m['data'] as Map?)?.cast<String, dynamic>();
          final imageUrl = (m['url'] ?? data?['url'] ?? '').toString();
          final mediaId = (m['mediaId'] ?? data?['mediaId'])?.toString();
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
          print('[PostReaderService] ImageNode $id padding=$paddingMode');

          // NodeComponentService에 스포일러 상태 복원
          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          rebuilt.add(
            ImageNode(
              id: id,
              imageUrl: imageUrl,
              altText: (m['altText'] ?? '').toString(),
              metadata: <String, dynamic>{
                if (mediaId != null) 'mediaId': mediaId,
                'hasComments': hasComments,
                'commentCount':
                    (commentCount is num)
                        ? commentCount.toInt()
                        : int.tryParse(commentCount.toString()) ?? 0,
                if (hasSpoiler) 'spoiler': true,
                if (paddingMode == 'full') 'padding': 'full',
              },
            ),
          );
          break;

        case 'imageRow':
          final urls =
              ((m['urls'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList();

          // 각 이미지별 댓글 정보 추출
          final imageCommentInfo = <String, Map<String, dynamic>>{};
          final data = (m['data'] as Map?)?.cast<String, dynamic>();

          // imageRow의 data에서 각 이미지별 정보가 있을 수 있음
          // 예: data: { images: [{ url: "...", mediaId: 123, hasComments: true, commentCount: 5 }, ...] }
          if (data != null && data['images'] is List) {
            final images = data['images'] as List;
            for (final img in images) {
              if (img is Map) {
                final imgMap = img.cast<String, dynamic>();
                final url = imgMap['url']?.toString();
                if (url != null && urls.contains(url)) {
                  final mediaId = imgMap['mediaId']?.toString();
                  final hasComments = imgMap['hasComments'] == true;
                  final commentCount =
                      (imgMap['commentCount'] is num)
                          ? (imgMap['commentCount'] as num).toInt()
                          : int.tryParse(
                                imgMap['commentCount']?.toString() ?? '0',
                              ) ??
                              0;
                  imageCommentInfo[url] = {
                    if (mediaId != null) 'mediaId': mediaId,
                    'hasComments': hasComments,
                    'commentCount': commentCount,
                  };
                }
              }
            }
          }

          // 스포일러 정보 확인 (노드 레벨)
          final hasSpoiler = m['spoiler'] == true;

          // NodeComponentService에 스포일러 상태 복원
          if (hasSpoiler) {
            spoilerNodes.add(id);
          }

          rebuilt.add(
            ImageRowNode(
              id: id,
              imageUrls: urls,
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
              metadata: {
                'imageCommentInfo': imageCommentInfo,
                if (hasSpoiler) 'spoiler': true,
              },
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
          final mediaId = (m['mediaId'] ?? data?['mediaId'])?.toString();
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

          rebuilt.add(
            ClipNode(
              id: id,
              label: (m['label'] ?? '').toString(),
              colorHex: (m['color'] ?? '#FF5252').toString(),
              url: url,
              metadata: <String, dynamic>{
                if (mediaId != null) 'mediaId': mediaId,
                'hasComments': hasComments,
                'commentCount':
                    (commentCount is num)
                        ? commentCount.toInt()
                        : int.tryParse(commentCount.toString()) ?? 0,
                if (hasSpoiler) 'spoiler': true,
              },
            ),
          );
          break;

        case 'video':
          final data = (m['data'] as Map?)?.cast<String, dynamic>();
          final url = (m['url'] ?? data?['url'] ?? '').toString();
          final mediaId = (m['mediaId'] ?? data?['mediaId'])?.toString();
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

          rebuilt.add(
            ClipNode(
              id: finalId,
              label: (m['label'] ?? '').toString(),
              colorHex: (m['color'] ?? '#FF5252').toString(),
              url: url,
              metadata: <String, dynamic>{
                if (mediaId != null) 'mediaId': mediaId,
                'hasComments': hasComments,
                'commentCount':
                    (commentCount is num)
                        ? commentCount.toInt()
                        : int.tryParse(commentCount.toString()) ?? 0,
                if (hasSpoiler) 'spoiler': true,
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
            print('[PostReaderService] 스포일러 상태 복원: $nodeId');
          }
        }
        if (kDebugMode) {
          print(
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
          if (kDebugMode) {
            print('DEBUG: PostReaderService 형광펜 디코딩 - HEX: $highlightHex');
          }
          final highlightColor = _parseHexColor(highlightHex);
          if (kDebugMode) {
            print('DEBUG: PostReaderService 형광펜 디코딩 - 색상: $highlightColor');
          }
          atts.add(HighlightAttribution(highlightColor));
        }

        // 폰트 패밀리 속성
        final fontFamily = ann['fontFamily'] as String?;
        if (fontFamily != null && fontFamily.isNotEmpty) {
          atts.add(FontFamilyAttribution(fontFamily));
        }

        // 스포일러 속성
        if (ann['spoiler'] == true) {
          atts.add(spoilerAttribution);
          if (kDebugMode) {
            print(
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

    print('[PostReaderService] 이미지 URL 추출 완료: ${imageUrls.length}개');
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

    print('[PostReaderService] 클립 URL 추출 완료: ${clipUrls.length}개');
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
  static final Map<String, DateTime> _preloadTimestamps = {}; // 생성 시간 추적
  static const int _maxPreloadCount = 20; // 최대 프리로드 개수 (모든 클립 지원)

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
      print('[PostReaderService] 오래된 프리로드 컨트롤러 정리: $url');
    }
  }

  /// 클립(영상)을 미리 로드한다 - 병렬 초기화 지원
  Future<void> preloadClips(
    BuildContext context,
    List<String> clipUrls, {
    int? maxCount, // ✅ nullable로 변경 (null이면 무제한)
  }) async {
    if (clipUrls.isEmpty) {
      return;
    }

    // 이미 프리로드된 URL 제외
    var urlsToPreload = clipUrls.where(
      (url) => !_preloadedControllers.containsKey(url),
    );

    // maxCount가 지정되면 제한, 아니면 전체
    if (maxCount != null) {
      urlsToPreload = urlsToPreload.take(maxCount);
    }

    final urlsList = urlsToPreload.toList();

    if (urlsList.isEmpty) {
      print('[PostReaderService] 프리로드할 클립 없음 (이미 모두 캐시됨)');
      return;
    }

    print('[PostReaderService] 클립 ${urlsList.length}개 병렬 프리로드 시작');

    // 최대 개수 초과 시 오래된 것부터 정리 (안전장치)
    final totalAfterPreload = _preloadedControllers.length + urlsList.length;
    if (totalAfterPreload > _maxPreloadCount) {
      final keepCount = _maxPreloadCount - urlsList.length;
      if (keepCount > 0) {
        _disposeOldestControllers(keepCount: keepCount);
      }
    }

    try {
      await Future.wait(
        urlsList.map((url) async {
          // ✅ urlsList 사용
          final controller = VideoPlayerController.networkUrl(Uri.parse(url));
          try {
            // 1. 기본 초기화 (메타데이터 + 첫 프레임)
            await controller.initialize();

            // 2. 초기 버퍼 확보 (0.1초 무음 재생 후 정지)
            await controller.setVolume(0); // 무음
            await controller.play();
            await Future.delayed(const Duration(milliseconds: 120)); // 버퍼 확보
            await controller.pause();
            await controller.seekTo(Duration.zero); // 처음으로 되돌리기

            // 캐시에 저장 및 타임스탬프 기록
            _preloadedControllers[url] = controller;
            _preloadTimestamps[url] = DateTime.now();

            // 리스너에 프리로드 완료 알림
            _notifyClipPreloaded(url);

            final shortUrl = url.split('/').last; // 파일명만 추출
            print('[PostReaderService] ✅ 클립 프리캐싱 완료 (버퍼 확보): $shortUrl');
          } catch (e) {
            print('[PostReaderService] 클립 프리캐싱 실패: $url - $e');
            await controller.dispose();
          }
        }),
      );
      print(
        '[PostReaderService] 🎉 클립 병렬 프리캐싱 완료 (총 ${_preloadedControllers.length}개 캐시됨)',
      );
      print('[PostReaderService] 캐시된 URL 목록:');
      for (final url in _preloadedControllers.keys) {
        final shortUrl = url.split('/').last;
        print('  - $shortUrl');
      }
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
