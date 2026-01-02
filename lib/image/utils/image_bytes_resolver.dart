import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
    // ✅ 절대 끝나지 않는 Future(무한 로딩) 방지:
    // - 캐시 매니저/파일 IO 등 어떤 단계에서 멈추더라도 전체 작업에 timeout을 건다.
    try {
      final timeoutDuration = timeout;
      return await _resolveOneInternal(source, headers: headers).timeout(
        timeoutDuration,
        onTimeout: () {
          debugPrint(
            '[ImageBytesResolver] ⏱️ 타임아웃: $source (${timeoutDuration.inSeconds}초 초과)',
          );
          throw TimeoutException('이미지 로딩 타임아웃: $source', timeoutDuration);
        },
      );
    } catch (e) {
      if (e is TimeoutException) {
        rethrow;
      }
      // 다른 에러는 _resolveOneInternal에서 이미 로그가 찍혔을 것이므로 그냥 rethrow
      rethrow;
    }
  }

  static Future<Uint8List> _resolveOneInternal(
    String source, {
    Map<String, String>? headers,
  }) async {
    final s = source.trim();
    if (s.isEmpty) {
      debugPrint('[ImageBytesResolver] ❌ 잘못된 소스 (빈 문자열): $source');
      throw ArgumentError.value(source, 'source', 'source is empty');
    }

    if (isNetwork(s)) {
      // ✅ 1순위: CachedNetworkImage가 사용하는 DefaultCacheManager 확인
      // (post_write_screen에서 이미 표시된 이미지는 여기 캐시에 있을 가능성이 높음)
      try {
        final defaultCache = await DefaultCacheManager().getFileFromCache(s);
        final defaultCachedFile = defaultCache?.file;
        if (defaultCachedFile != null && await defaultCachedFile.exists()) {
          debugPrint('[ImageBytesResolver] ✅ DefaultCache에서 로드 성공: $s');
          return await defaultCachedFile.readAsBytes();
        }
      } catch (e) {
        debugPrint('[ImageBytesResolver] ⚠️ DefaultCache 조회 실패 (폴백): $s - $e');
      }

      // ✅ 2순위: 편집 전용 캐시 확인
      try {
        final editCache = await EditImageCacheManager.instance.getFileFromCache(
          s,
        );
        final editCachedFile = editCache?.file;
        if (editCachedFile != null && await editCachedFile.exists()) {
          debugPrint('[ImageBytesResolver] ✅ EditCache에서 로드 성공: $s');
          return await editCachedFile.readAsBytes();
        }
      } catch (e) {
        debugPrint('[ImageBytesResolver] ⚠️ EditCache 조회 실패 (폴백): $s - $e');
      }

      // ✅ 3순위: 네트워크 다운로드
      debugPrint('[ImageBytesResolver] 🌐 네트워크에서 다운로드 시작: $s');
      debugPrint('[ImageBytesResolver] 📋 URL 상세 정보:');
      debugPrint('   - 전체 URL: $s');
      try {
        final uri = Uri.parse(s);
        debugPrint('   - 파싱된 URI: $uri');
        debugPrint('   - 호스트: ${uri.host}');
        debugPrint('   - 경로: ${uri.path}');

        final stopwatch = Stopwatch()..start();
        final resp = await http.get(uri, headers: headers);
        stopwatch.stop();
        debugPrint('   - 응답 시간: ${stopwatch.elapsedMilliseconds}ms');
        debugPrint('   - HTTP 상태 코드: ${resp.statusCode}');
        debugPrint('   - 응답 크기: ${resp.bodyBytes.length} bytes');
        debugPrint(
          '   - Content-Type: ${resp.headers['content-type'] ?? 'N/A'}',
        );

        if (resp.statusCode != 200) {
          debugPrint('[ImageBytesResolver] ❌ HTTP 에러 발생:');
          debugPrint('   - URL: $s');
          debugPrint('   - 상태 코드: ${resp.statusCode}');
          debugPrint('   - 상태 메시지: ${resp.reasonPhrase ?? 'N/A'}');
          debugPrint(
            '   - 응답 본문 (처음 200자): ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}',
          );

          // ✅ 오래된 포스트 이미지의 경우 404가 자주 발생할 수 있음
          if (resp.statusCode == 404) {
            debugPrint(
              '   ⚠️ [오래된 포스트 가능성] 404 Not Found - 서버에서 이미지 파일이 삭제되었거나 URL이 변경되었을 수 있습니다.',
            );
          } else if (resp.statusCode == 403) {
            debugPrint('   ⚠️ [권한 문제] 403 Forbidden - 이미지에 접근 권한이 없습니다.');
          } else if (resp.statusCode >= 500) {
            debugPrint('   ⚠️ [서버 에러] ${resp.statusCode} - 서버 내부 오류입니다.');
          }

          throw HttpException(
            'Failed to load image bytes: HTTP ${resp.statusCode} ${resp.reasonPhrase ?? ""}',
            uri: uri,
          );
        }
        debugPrint(
          '[ImageBytesResolver] ✅ 네트워크 다운로드 성공: $s (${resp.bodyBytes.length} bytes)',
        );

        // ✅ 다음 편집 진입을 빠르게: 두 캐시 모두에 저장 (실패해도 무시)
        unawaited(() async {
          try {
            await DefaultCacheManager().putFile(s, resp.bodyBytes);
            debugPrint('[ImageBytesResolver] 💾 DefaultCache 저장 완료: $s');
          } catch (e) {
            debugPrint(
              '[ImageBytesResolver] ⚠️ DefaultCache 저장 실패 (무시): $s - $e',
            );
          }
          try {
            await EditImageCacheManager.instance.putFile(s, resp.bodyBytes);
            debugPrint('[ImageBytesResolver] 💾 EditCache 저장 완료: $s');
          } catch (e) {
            debugPrint('[ImageBytesResolver] ⚠️ EditCache 저장 실패 (무시): $s - $e');
          }
        }());

        return resp.bodyBytes;
      } catch (e) {
        if (e is HttpException) {
          // HttpException은 이미 상세 로그가 찍혔으므로 rethrow만
          rethrow;
        } else if (e is SocketException) {
          debugPrint('[ImageBytesResolver] ❌ 네트워크 연결 실패:');
          debugPrint('   - URL: $s');
          debugPrint('   - 에러 타입: SocketException');
          debugPrint('   - 메시지: ${e.message}');
          debugPrint('   - 주소: ${e.address}');
          debugPrint('   - 포트: ${e.port}');
          debugPrint('   ⚠️ 네트워크 연결 문제 또는 DNS 해석 실패일 수 있습니다.');
        } else if (e is FormatException) {
          debugPrint('[ImageBytesResolver] ❌ URL 형식 오류:');
          debugPrint('   - URL: $s');
          debugPrint('   - 에러 타입: FormatException');
          debugPrint('   - 메시지: ${e.message}');
          debugPrint('   ⚠️ URL이 올바르지 않거나 파싱할 수 없는 형식입니다.');
        } else {
          debugPrint('[ImageBytesResolver] ❌ 네트워크 요청 실패 (알 수 없는 에러):');
          debugPrint('   - URL: $s');
          debugPrint('   - 에러 타입: ${e.runtimeType}');
          debugPrint('   - 메시지: $e');
          debugPrint('   - 스택 트레이스: ${StackTrace.current}');
        }
        rethrow;
      }
    }

    final path = toLocalPath(s);
    if (path == null || path.isEmpty) {
      debugPrint('[ImageBytesResolver] ❌ 잘못된 로컬 이미지 소스: $s');
      throw ArgumentError.value(
        source,
        'source',
        'invalid local image source: $s',
      );
    }
    final f = File(path);
    if (!await f.exists()) {
      debugPrint('[ImageBytesResolver] ❌ 로컬 파일 없음: $path');
      throw FileSystemException('Local image file does not exist: $path', path);
    }
    try {
      final bytes = await f.readAsBytes();
      debugPrint(
        '[ImageBytesResolver] ✅ 로컬 파일 로드 성공: $path (${bytes.length} bytes)',
      );
      return bytes;
    } catch (e) {
      debugPrint('[ImageBytesResolver] ❌ 로컬 파일 읽기 실패: $path - $e');
      rethrow;
    }
  }

  static Future<List<Uint8List>> resolveMany(
    List<String> sources, {
    Duration timeoutPerItem = const Duration(seconds: 10),
    Map<String, String>? headers,
  }) async {
    if (sources.isEmpty) return <Uint8List>[];

    debugPrint('[ImageBytesResolver] 📸 멀티 이미지 로딩 시작: ${sources.length}개');
    debugPrint('   - URLs: $sources');
    debugPrint('   - 타임아웃: ${timeoutPerItem.inSeconds}초/이미지');

    try {
      // ✅ 병렬로 처리해서 체감 시간을 줄인다(특히 Row/PageView 다중 이미지 편집 진입)
      final results = await Future.wait(
        sources.map(
          (s) => resolveOne(s, timeout: timeoutPerItem, headers: headers),
        ),
      );
      debugPrint(
        '[ImageBytesResolver] ✅ 멀티 이미지 로딩 완료: ${sources.length}개 모두 성공',
      );
      return results;
    } catch (e) {
      debugPrint('[ImageBytesResolver] ❌ 멀티 이미지 로딩 실패:');
      debugPrint('   - 전체 개수: ${sources.length}');
      debugPrint('   - 소스 목록: $sources');
      debugPrint('   - 에러 타입: ${e.runtimeType}');
      debugPrint('   - 에러 메시지: $e');
      rethrow;
    }
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
