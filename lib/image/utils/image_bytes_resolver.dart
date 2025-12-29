import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'edit_image_cache_manager.dart';

/// 네트워크/로컬(파일 경로 or file://) 이미지 소스로부터 bytes를 가져오는 공용 유틸.
///
/// - 에디터(이미지/이미지로우/페이지뷰)와 썸네일 편집 등에서 재사용한다.
/// - "네트워크면 먼저 bytes를 받고, 로컬이면 즉시 bytes" 요구사항을 만족한다.
class ImageBytesResolver {
  const ImageBytesResolver._();

  static final Set<String> _warmedDiskCacheUrls = <String>{};

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
      // ✅ (편집 모드 최적화) 편집 전용 디스크 캐시를 먼저 조회해서 대기 시간을 줄인다.
      try {
        final cachedFile = await EditImageCacheManager.instance.getSingleFile(
          s,
        );
        if (await cachedFile.exists()) {
          return await cachedFile.readAsBytes();
        }
      } catch (_) {
        // 캐시 실패 시 네트워크로 폴백
      }

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
    // ✅ 병렬로 처리해서 체감 시간을 줄인다(특히 Row/PageView 다중 이미지 편집 진입)
    return await Future.wait(
      sources.map(
        (s) => resolveOne(s, timeout: timeoutPerItem, headers: headers),
      ),
    );
  }

  /// ✅ (편집 UX용) 네트워크 이미지의 "디스크 캐시"만 미리 채운다.
  /// - UI 위젯을 CachedNetworkImage로 바꾸지 않아도, 이후 편집 진입 시 bytes 로딩이 빨라진다.
  /// - 중복 다운로드 방지를 위해 URL 단위로 1회만 수행한다.
  static Future<void> warmDiskCache(
    String source, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final s = source.trim();
    if (s.isEmpty) return;
    if (!isNetwork(s)) return;

    // 이미 워밍업 시도한 URL은 중복 수행하지 않음
    if (_warmedDiskCacheUrls.contains(s)) return;
    _warmedDiskCacheUrls.add(s);

    try {
      await EditImageCacheManager.instance.downloadFile(s).timeout(timeout);
    } catch (_) {
      // 워밍업 실패는 무시 (편집 진입 시 resolveOne이 다시 시도)
    }
  }
}
