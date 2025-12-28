import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 네트워크/로컬(파일 경로 or file://) 이미지 소스로부터 bytes를 가져오는 공용 유틸.
///
/// - 에디터(이미지/이미지로우/페이지뷰)와 썸네일 편집 등에서 재사용한다.
/// - "네트워크면 먼저 bytes를 받고, 로컬이면 즉시 bytes" 요구사항을 만족한다.
class ImageBytesResolver {
  const ImageBytesResolver._();

  static bool isNetwork(String source) {
    final s = source.trim();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  static bool isFileUri(String source) => source.trim().startsWith('file://');

  /// source가 파일 경로/파일 URI면 로컬 경로로 정규화한다.
  /// - `file:///a/b.png` -> `/a/b.png`
  /// - `/a/b.png` -> `/a/b.png`
  static String? toLocalPath(String source) {
    final s = source.trim();
    if (s.isEmpty) return null;
    if (isNetwork(s)) return null;
    if (isFileUri(s)) {
      try {
        return Uri.parse(s).toFilePath();
      } catch (_) {
        return null;
      }
    }
    // absolute/local path로 간주
    return s;
  }

  static Future<Uint8List> resolveOne(
    String source, {
    Duration timeout = const Duration(seconds: 10),
    Map<String, String>? headers,
  }) async {
    final s = source.trim();
    if (s.isEmpty) {
      throw ArgumentError.value(source, 'source', 'source is empty');
    }

    if (isNetwork(s)) {
      final uri = Uri.parse(s);
      final resp = await http.get(uri, headers: headers).timeout(timeout);
      if (resp.statusCode != 200) {
        throw HttpException('Failed to load image bytes: ${resp.statusCode}');
      }
      return resp.bodyBytes;
    }

    final path = toLocalPath(s);
    if (path == null || path.isEmpty) {
      throw ArgumentError.value(source, 'source', 'invalid local image source');
    }
    final f = File(path);
    if (!await f.exists()) {
      throw FileSystemException('Local image file does not exist', path);
    }
    return await f.readAsBytes();
  }

  static Future<List<Uint8List>> resolveMany(
    List<String> sources, {
    Duration timeoutPerItem = const Duration(seconds: 10),
    Map<String, String>? headers,
  }) async {
    if (sources.isEmpty) return <Uint8List>[];
    final out = <Uint8List>[];
    for (final s in sources) {
      out.add(await resolveOne(s, timeout: timeoutPerItem, headers: headers));
    }
    return out;
  }
}
