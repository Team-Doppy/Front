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
      createdAt: DateTime.now(),
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
        // 제목 노드는 건너뛰기
        if (n['isTitle'] == true) {
          return;
        }

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
}
