import 'dart:convert';
import 'dart:io';

/// 링크 메타데이터를 가져오는 유틸리티 클래스
class LinkMetaFetcher {
  /// URL에서 메타데이터 가져오기
  static Future<LinkMetaData?> fetchMeta(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      final res = await req.close();

      String html;
      if (res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.value(HttpHeaders.locationHeader) != null) {
        final redirected = res.headers.value(HttpHeaders.locationHeader)!;
        final rreq = await client.getUrl(Uri.parse(redirected));
        final rres = await rreq.close();
        html = await utf8.decodeStream(rres);
      } else {
        html = await utf8.decodeStream(res);
      }

      return _parseMeta(html);
    } catch (e) {
      return null;
    }
  }

  static LinkMetaData? _parseMeta(String html) {
    String? ogTitle = _firstMatch(
      html,
      RegExp(
        r'meta[^>]+property=[\"\"]og:title[\"\"][^>]+content=[\"\"]([^\"\"]+)',
      ),
    );
    String? ogDesc = _firstMatch(
      html,
      RegExp(
        r'meta[^>]+property=[\"\"]og:description[\"\"][^>]+content=[\"\"]([^\"\"]+)',
      ),
    );
    String? ogImage = _firstMatch(
      html,
      RegExp(
        r'meta[^>]+property=[\"\"]og:image[\"\"][^>]+content=[\"\"]([^\"\"]+)',
      ),
    );
    ogTitle ??= _firstMatch(
      html,
      RegExp(r'<title>(.*?)<\/title>', caseSensitive: false, dotAll: true),
    );

    if (ogTitle == null && ogDesc == null && ogImage == null) {
      return null;
    }

    return LinkMetaData(
      title: ogTitle,
      description: ogDesc,
      thumbnailUrl: ogImage,
    );
  }

  static String? _firstMatch(String html, RegExp re) {
    final m = re.firstMatch(html);
    if (m == null) return null;
    return m.groupCount >= 1 ? m.group(1) : null;
  }

  /// URL 정규화
  static String? normalizeUrl(String input) {
    String u = input.trim();
    if (u.isEmpty) return null;
    // http:// 또는 https://로 시작하지 않으면 추가
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      // 이미 도메인 형태인지 확인 (예: example.com)
      if (RegExp(
            r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.([a-zA-Z]{2,}|[a-zA-Z]{2,}\.[a-zA-Z]{2,})',
          ).hasMatch(u) ||
          RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(u)) {
        u = 'https://$u';
      } else {
        // 도메인 형태가 아니면 null 반환
        return null;
      }
    }
    // 기본 URL 패턴 검증
    if (!RegExp(
      r'^https?://[^\s/$.?#].[^\s]*$',
      caseSensitive: false,
    ).hasMatch(u)) {
      return null;
    }
    return u;
  }
}

/// 링크 메타데이터 모델
class LinkMetaData {
  final String? title;
  final String? description;
  final String? thumbnailUrl;

  LinkMetaData({this.title, this.description, this.thumbnailUrl});
}
