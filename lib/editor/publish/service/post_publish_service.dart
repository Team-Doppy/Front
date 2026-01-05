import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:flutter/material.dart';

/// 포스트 발행 관련 비즈니스 로직 서비스
class PostPublishService {
  static final PostPublishService _instance = PostPublishService._internal();
  factory PostPublishService() => _instance;
  PostPublishService._internal();

  final BlogService _blogService = BlogService();

  /// 포스트 발행
  ///
  /// [payload] - 최종 발행할 포스트 데이터
  ///
  /// 반환: 업로드 결과 맵
  Future<Map<String, dynamic>> publishPost({
    required Map<String, dynamic> payload,
  }) async {
    return await _blogService.uploadPost(postData: payload);
  }

  /// 최종 JSON 페이로드 빌드
  ///
  /// [exportedBase] - exported 기본 데이터
  /// [title] - 제목
  /// [excerpt] - 본문 요약
  /// [thumbnailImageUrl] - 썸네일 이미지 URL
  /// [privateOnly] - 나만보기 여부
  /// [publicOnly] - 전체공개 여부
  /// [friendsOnly] - 친구공유 여부
  /// [selectedGroupIds] - 선택된 그룹 ID 목록
  /// [categoryId] - 카테고리 ID
  ///
  /// 반환: 최종 발행용 JSON 맵
  Future<Map<String, dynamic>> buildFinalPayload({
    required Map<String, dynamic> exportedBase,
    required String title,
    required String excerpt,
    required String thumbnailImageUrl,
    required bool privateOnly,
    required bool publicOnly,
    required bool friendsOnly,
    required List<int> selectedGroupIds,
    required int? categoryId,
  }) async {
    // ✅ 썸네일 URL 검증은 UI 레이어(_publish)에서 이미 수행됨
    // 여기서는 검증 없이 페이로드만 빌드

    // 기존 exportedBase를 복사하고 편집된 내용으로 덮어쓰기
    final editedBase = Map<String, dynamic>.from(exportedBase);

    // 제목과 본문을 편집된 내용으로 업데이트
    editedBase['title'] = title;
    editedBase['summary'] = excerpt;

    // 발행 직전 정리: 서버에 업로드되지 않은 로컬 이미지/영상 노드 제거
    _cleanLocalMediaNodes(editedBase);

    // usedImageUrls 재수집 (PNG 드로잉 포함)
    final usedUrls = _collectUsedImageUrls(editedBase, thumbnailImageUrl);
    editedBase['usedImageUrls'] = usedUrls.toList();

    return PostExporter.composeFinalPayload(
      thumbnailImageUrl: thumbnailImageUrl,
      base: editedBase,
      privateOnly: privateOnly,
      publicOnly: publicOnly,
      friendsOnly: friendsOnly,
      selectedGroupIds: selectedGroupIds,
      categoryId: categoryId,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// 로컬 미디어 노드 정리 (HTTP URL이 아닌 것 제거)
  /// 업로드되지 않은 미디어가 있으면 StateError 발생
  void _cleanLocalMediaNodes(Map<String, dynamic> editedBase) {
    try {
      bool isHttpUrl(String u) =>
          u.startsWith('http://') || u.startsWith('https://');

      final dynamic contentDyn = editedBase['content'];
      if (contentDyn is Map) {
        final List<dynamic> nodes = List<dynamic>.from(
          contentDyn['nodes'] as List? ?? const [],
        );
        final List<dynamic> cleaned = [];
        final List<String> localMediaNodes = []; // 업로드되지 않은 미디어 추적

        for (final n in nodes) {
          if (n is! Map) continue;
          final String type = (n['type'] ?? '').toString();

          if (type == 'image') {
            final Map<String, dynamic>? data =
                (n['data'] as Map?)?.cast<String, dynamic>();
            final String url = (data?['url'] ?? n['url'] ?? '').toString();
            if (isHttpUrl(url)) {
              cleaned.add(n);
            } else if (url.isNotEmpty) {
              localMediaNodes.add('이미지 (${n['id']})');
            }
          } else if (type == 'imageRow') {
            final List<dynamic> urls = List<dynamic>.from(
              n['urls'] ?? const [],
            );
            final List<String> httpUrls =
                urls.map((e) => e.toString()).where(isHttpUrl).toList();
            final List<String> localUrls =
                urls
                    .map((e) => e.toString())
                    .where((u) => u.isNotEmpty && !isHttpUrl(u))
                    .toList();
            if (httpUrls.isNotEmpty) {
              n['urls'] = httpUrls;
              cleaned.add(n);
            }
            if (localUrls.isNotEmpty) {
              localMediaNodes.add(
                '이미지 행 (${n['id']}) - ${localUrls.length}개 업로드 실패',
              );
            }
          } else if (type == 'video' || type == 'clip') {
            final Map<String, dynamic>? data =
                (n['data'] as Map?)?.cast<String, dynamic>();
            final String url = (data?['url'] ?? n['url'] ?? '').toString();
            if (isHttpUrl(url)) {
              cleaned.add(n);
            } else if (url.isNotEmpty) {
              localMediaNodes.add('비디오 (${n['id']})');
            }
          } else {
            cleaned.add(n); // 그 외 노드는 그대로 유지
          }
        }

        // 🚀 업로드되지 않은 미디어가 있으면 에러 발생
        if (localMediaNodes.isNotEmpty) {
          throw StateError(
            '업로드되지 않은 미디어가 있습니다: ${localMediaNodes.join(', ')}. '
            '모든 미디어가 업로드 완료된 후 발행해주세요.',
          );
        }

        // 🎯 stickers를 유지하면서 nodes만 교체
        editedBase['content'] = {
          ...contentDyn,
          'nodes': cleaned,
          // stickers가 있으면 유지
          if (contentDyn['stickers'] != null)
            'stickers': contentDyn['stickers'],
        };
      }
    } catch (e) {
      debugPrint('[PostPublishService] 로컬 미디어 정리 중 오류: $e');
    }
  }

  /// 사용된 이미지 URL 수집 (썸네일, 콘텐츠 이미지, 스티커 포함)
  Set<String> _collectUsedImageUrls(
    Map<String, dynamic> editedBase,
    String thumbnailImageUrl,
  ) {
    final Set<String> usedUrls = <String>{};

    // 썸네일
    if (thumbnailImageUrl.trim().isNotEmpty) {
      usedUrls.add(thumbnailImageUrl.trim());
    }

    // content의 이미지/비디오 노드
    final dynamic contentDyn = editedBase['content'];
    if (contentDyn is Map) {
      final nodes = List<dynamic>.from(contentDyn['nodes'] as List? ?? []);
      for (final n in nodes) {
        if (n is! Map) continue;
        final type = (n['type'] ?? '').toString();

        if (type == 'image') {
          final url =
              ((n['data'] as Map?)?['url'] ?? n['url'] ?? '').toString();
          if (url.isNotEmpty) usedUrls.add(url);
        } else if (type == 'imageRow') {
          final urls = List<dynamic>.from(n['urls'] ?? []);
          for (final u in urls) {
            if (u.toString().isNotEmpty) usedUrls.add(u.toString());
          }
        } else if (type == 'video' || type == 'clip') {
          final url = ((n['data'] as Map?)?['url'] ?? '').toString();
          if (url.isNotEmpty) usedUrls.add(url);
        }
      }

      // 스티커 이미지 URL (PNG 드로잉 포함)
      final stickers = List<dynamic>.from(
        contentDyn['stickers'] as List? ?? [],
      );
      debugPrint('[PostPublishService] 📌 스티커 수집 시작: ${stickers.length}개');
      for (final s in stickers) {
        if (s is! Map) {
          debugPrint('[PostPublishService] ⚠️ 스티커가 Map이 아님: $s');
          continue;
        }
        final stickerType = (s['type'] ?? '').toString();
        debugPrint('[PostPublishService] 📌 스티커 타입: $stickerType');
        if (stickerType == 'image') {
          final content = s['content'];
          String? url;

          if (content is Map) {
            // ✅ URL + 크기 정보 (PNG 드로잉) 또는 레거시 {url: ...}
            url = (content['url'] ?? '').toString();
            debugPrint('[PostPublishService] 📌 스티커 content (Map): $content');
          } else if (content is String) {
            // 레거시: content가 직접 URL 문자열인 경우
            url = content;
            debugPrint(
              '[PostPublishService] 📌 스티커 content (String): $content',
            );
          }

          if (url != null && url.isNotEmpty) {
            usedUrls.add(url);
            debugPrint('[PostPublishService] ✅ 스티커 URL 추가: $url');
          } else {
            debugPrint(
              '[PostPublishService] ⚠️ 스티커 URL이 비어있음: content=$content',
            );
          }
        } else {
          debugPrint('[PostPublishService] ⚠️ 스티커 타입이 image가 아님: $stickerType');
        }
      }
      debugPrint(
        '[PostPublishService] 📌 스티커 URL 수집 완료: 총 ${usedUrls.length}개 URL',
      );
    }

    return usedUrls;
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

  /// 노드에서 텍스트 수집 (제목 노드는 제외)
  static String collectText(dynamic node) {
    final buffer = StringBuffer();

    void walk(dynamic n) {
      if (n is Map) {
        // 모든 노드 처리 (더 이상 제목 노드 구분 없음)

        n.forEach((key, value) {
          final k = key.toString().toLowerCase();
          if (value is String) {
            if (k.contains('text') ||
                k.contains('content') ||
                k.contains('paragraph') ||
                k.contains('description') ||
                k.contains('body')) {
              buffer.write(' ');
              buffer.write(value);
            }
          } else {
            walk(value);
          }
        });
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return buffer.toString();
  }

  /// 텍스트에서 요약 자동 추출
  ///
  /// [collectedText] - 수집된 전체 텍스트
  /// [title] - 제목 (제목 부분 제거용)
  /// [maxLength] - 최대 길이 (기본값: 100)
  ///
  /// 반환: 자동 추출된 요약 텍스트
  static String extractSummary({
    required String collectedText,
    String title = '',
    int maxLength = 100,
  }) {
    String text =
        collectedText
            .replaceAll(RegExp('\\s+'), ' ')
            .replaceAll('\u200B', '')
            .trim();

    // 제목이 포함되어 있으면 제목 부분 제거
    String preview = text;
    if (title.isNotEmpty && preview.startsWith(title)) {
      preview = preview.substring(title.length).trim();
    }

    // 최대 길이 제한
    if (preview.length > maxLength) {
      // 마지막 공백 또는 마침표에서 자르기
      int cutIndex = preview.lastIndexOf(' ', maxLength);
      if (cutIndex == -1 || cutIndex < maxLength * 0.8) {
        cutIndex = maxLength;
      }
      preview = '${preview.substring(0, cutIndex).trim()}...';
    }

    return preview;
  }

  /// 본문(content.nodes)에서 "첫 번째 이미지 URL"을 찾는다.
  ///
  /// - Step1(썸네일/배경) 기본값으로 사용하기 위함
  /// - 반드시 http(s) URL만 반환 (로컬 경로는 제외)
  static String findFirstBodyImageUrl(Map<String, dynamic> exported) {
    bool isHttpUrl(String u) =>
        u.startsWith('http://') || u.startsWith('https://');

    try {
      assert(() {
        final thumb = (exported['thumbnailImageUrl'] ?? '').toString();
        final used = exported['usedImageUrls'];
        debugPrint(
          '[ThumbAuto][findFirstBodyImageUrl] start: thumbnailImageUrl="$thumb", usedImageUrlsType=${used.runtimeType}',
        );
        return true;
      }());

      // ✅ exported 전체에서 content.nodes를 우선 탐색하되,
      // 레거시/변형 구조(content가 Map이 아니거나 nodes 키가 다른 경우)도 안전하게 처리한다.
      dynamic content = exported['content'];
      List<dynamic> nodes = const [];

      if (content is Map) {
        nodes = List<dynamic>.from(content['nodes'] as List? ?? const []);
        // 일부 변형: content['content'] 아래에 nodes가 중첩될 수 있음
        if (nodes.isEmpty) {
          final nested = content['content'];
          if (nested is Map) {
            nodes = List<dynamic>.from(nested['nodes'] as List? ?? const []);
          }
        }
      } else if (exported['nodes'] is List) {
        // 변형: 최상위에 nodes가 있는 경우
        nodes = List<dynamic>.from(exported['nodes'] as List? ?? const []);
      }

      assert(() {
        debugPrint(
          '[ThumbAuto][findFirstBodyImageUrl] nodes=${nodes.length}, contentType=${content.runtimeType}',
        );
        for (int i = 0; i < nodes.length && i < 6; i++) {
          final n = nodes[i];
          if (n is! Map) continue;
          final type = (n['type'] ?? n['nodeType'] ?? '').toString();
          String sample = '';
          if (type == 'image') {
            final data = (n['data'] as Map?)?.cast<String, dynamic>();
            sample =
                (data?['url'] ?? data?['imageUrl'] ?? n['url'] ?? n['imageUrl'])
                    .toString();
          } else if (type == 'imageRow') {
            final urls = List<dynamic>.from(
              n['urls'] ?? n['imageUrls'] ?? n['images'] ?? const [],
            );
            sample = urls.isNotEmpty ? urls.first.toString() : '';
          } else if (type == 'pageViewImage' ||
              type == 'pageviewImage' ||
              type == 'page_view_image') {
            final urls = List<dynamic>.from(
              n['imageUrls'] ?? n['urls'] ?? n['images'] ?? const [],
            );
            sample = urls.isNotEmpty ? urls.first.toString() : '';
          }
          debugPrint(
            '[ThumbAuto][findFirstBodyImageUrl] node[$i] type=$type sample="$sample"',
          );
        }
        return true;
      }());

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

        // 다양한 키/타입 호환 (exporter 버전별 차이)
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
      }

      // ✅ 본문 노드에 이미지가 없으면(혹은 스키마가 달라 못 찾았으면)
      // stickers에서라도 하나 찾아서 Step1 배경으로 쓰게 한다.
      try {
        if (content is Map) {
          final stickers = List<dynamic>.from(content['stickers'] ?? const []);
          assert(() {
            debugPrint(
              '[ThumbAuto][findFirstBodyImageUrl] fallback: stickers=${stickers.length}',
            );
            return true;
          }());
          for (final s in stickers) {
            if (s is! Map) continue;
            if ((s['type'] ?? '').toString() != 'image') continue;
            final c = s['content'];
            String url = '';
            if (c is String) url = c;
            if (c is Map) url = (c['url'] ?? '').toString();
            if (url.isNotEmpty && isHttpUrl(url)) return url;
          }
        }
      } catch (_) {}
    } catch (_) {}

    assert(() {
      debugPrint('[ThumbAuto][findFirstBodyImageUrl] result="" (not found)');
      return true;
    }());
    return '';
  }
}
