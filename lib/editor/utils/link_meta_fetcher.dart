import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 링크 메타데이터
class LinkMeta {
  final String? title;
  final String? description;
  final String? thumbnailUrl;

  LinkMeta({this.title, this.description, this.thumbnailUrl});
}

/// 링크 메타데이터 가져오기 유틸리티
///
/// Open Graph 메타 태그와 일반 메타 태그를 파싱하여
/// 제목, 설명, 썸네일 URL을 추출합니다.
class LinkMetaFetcher {
  LinkMetaFetcher._();

  /// URL 정규화
  ///
  /// http:// 또는 https://가 없으면 https://를 추가합니다.
  static String? normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  /// 링크 메타데이터 가져오기
  ///
  /// [url] 정규화된 URL
  /// 반환: LinkMeta 또는 null (실패 시)
  static Future<LinkMeta?> fetchMeta(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      // 🎯 일부 사이트(자체 서명/만료 등)는 인증서 검증 실패로 메타 조회가 불가 → 링크 미리보기용으로만 검증 완화
      client.badCertificateCallback = (_, __, ___) => true;
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      req.headers.add(
        'User-Agent',
        'Mozilla/5.0 (compatible; LinkPreview/1.0)',
      );

      final res = await req.close();

      // 리다이렉트 처리
      String? html;
      if (res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.value(HttpHeaders.locationHeader) != null) {
        final redirected = res.headers.value(HttpHeaders.locationHeader)!;
        final rreq = await client.getUrl(Uri.parse(redirected));
        rreq.headers.add(
          'User-Agent',
          'Mozilla/5.0 (compatible; LinkPreview/1.0)',
        );
        final rres = await rreq.close();
        html = await utf8.decodeStream(rres);
      } else {
        html = await utf8.decodeStream(res);
      }

      client.close();
      return _parseMeta(html);
    } catch (e) {
      debugPrint('[LinkMetaFetcher] 메타데이터 가져오기 실패: $e');
      return null;
    }
  }

  /// HTML 엔티티 디코딩 (og:title, og:description 등에서 &amp; &lt; 등 복원)
  static String decodeHtmlEntities(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// HTML에서 메타데이터 파싱
  static LinkMeta? _parseMeta(String html) {
    // Open Graph 우선, 없으면 일반 메타 태그 사용
    final rawTitle =
        _extractOgTag(html, 'og:title') ?? _extractMetaTag(html, 'title');
    final rawDesc =
        _extractOgTag(html, 'og:description') ??
        _extractMetaTag(html, 'description');
    final ogImage = _extractOgTag(html, 'og:image');

    return LinkMeta(
      title: rawTitle != null ? decodeHtmlEntities(rawTitle) : null,
      description: rawDesc != null ? decodeHtmlEntities(rawDesc) : null,
      thumbnailUrl: ogImage,
    );
  }

  /// Open Graph 태그 추출
  static String? _extractOgTag(String html, String property) {
    final pattern = RegExp(
      'meta[^>]+property=["\']$property["\'][^>]+content=["\']([^"\']+)',
      caseSensitive: false,
    );
    return _firstMatch(html, pattern);
  }

  /// 일반 메타 태그 추출
  static String? _extractMetaTag(String html, String name) {
    final pattern = RegExp(
      'meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)',
      caseSensitive: false,
    );
    return _firstMatch(html, pattern);
  }

  /// 정규식 첫 번째 매치 추출
  static String? _firstMatch(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    if (match == null || match.groupCount < 1) return null;
    return match.group(1)?.trim();
  }
}
