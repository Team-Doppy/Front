import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🎯 이미지 크기 측정 공통 유틸리티
/// SingleImageComponent와 RowImageComponent에서 공통으로 사용
class ImageSizeUtils {
  ImageSizeUtils._();

  /// 로컬 경로인지 확인
  static bool isLocalPath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return false;
    if (path.startsWith('file://')) return true;
    return path.startsWith('/') ||
        path.contains('/Application/') ||
        path.contains('/Documents/');
  }

  /// 이미지 파일을 다운로드/읽기
  /// 로컬 파일은 직접 읽고, 네트워크 이미지는 전체 다운로드
  static Future<Uint8List?> downloadImageBytes(String imageUrl) async {
    try {
      if (isLocalPath(imageUrl)) {
        // 로컬 파일: 파일에서 직접 읽기
        final filePath =
            imageUrl.startsWith('file://') ? imageUrl.substring(7) : imageUrl;
        final file = File(filePath);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      } else {
        // 네트워크 이미지: 전체 이미지 다운로드 (HEIC/압축 PNG 대응)
        final uri = Uri.parse(imageUrl);
        final client = HttpClient();
        final request = await client.getUrl(uri);
        final response = await request.close();

        if (response.statusCode == 200) {
          final bytes = <int>[];
          await for (final chunk in response) {
            bytes.addAll(chunk);
          }
          client.close();
          return Uint8List.fromList(bytes);
        }
        client.close();
      }
    } catch (e) {
      debugPrint('[ImageSizeUtils] ⚠️ 이미지 다운로드 실패: $imageUrl - $e');
    }
    return null;
  }

  /// HEIC 파일인지 확인
  static bool isHeicFile(String imageUrl) {
    final lower = imageUrl.toLowerCase();
    return lower.endsWith('.heic') || lower.endsWith('.heif');
  }

  /// 이미지 바이트에서 크기 추출
  /// HEIC 파일은 null 반환 (Flutter에서 직접 디코딩 불가)
  static Future<Size?> extractSizeFromBytes(
    Uint8List imageBytes,
    String imageUrl,
  ) async {
    try {
      // 🎯 HEIC 파일 체크: Flutter는 HEIC를 기본 지원하지 않음
      if (isHeicFile(imageUrl)) {
        debugPrint(
          '[ImageSizeUtils] ⚠️ HEIC 파일은 Flutter에서 직접 디코딩 불가: $imageUrl',
        );
        return null;
      }

      // 🎯 instantiateImageCodec 사용
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();

      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );

      // 메모리 정리
      frame.image.dispose();

      return size;
    } catch (e) {
      debugPrint('[ImageSizeUtils] ⚠️ 이미지 크기 추출 실패: $imageUrl - $e');
      return null;
    }
  }

  /// 이미지 URL에서 크기 추출 (전체 프로세스)
  /// 1. 이미지 다운로드/읽기
  /// 2. 크기 추출
  static Future<Size?> measureImageSize(String imageUrl) async {
    final imageBytes = await downloadImageBytes(imageUrl);
    if (imageBytes == null) return null;
    return await extractSizeFromBytes(imageBytes, imageUrl);
  }

  /// ImageProvider를 사용하여 ImageInfo에서 크기 추출
  /// HEIC 파일도 처리 가능 (Image.network가 로드되면)
  static Future<Size?> extractSizeFromImageProvider(String imageUrl) async {
    try {
      final ImageProvider imageProvider =
          isLocalPath(imageUrl)
              ? FileImage(
                File(
                  imageUrl.startsWith('file://')
                      ? imageUrl.substring(7)
                      : imageUrl,
                ),
              )
              : NetworkImage(imageUrl);

      final completer = Completer<Size?>();
      final ImageStream stream = imageProvider.resolve(
        ImageConfiguration.empty,
      );

      late ImageStreamListener listener;
      Timer? timeoutTimer;
      bool removed = false;

      void safeRemoveListener() {
        if (removed) return;
        removed = true;
        try {
          stream.removeListener(listener);
        } catch (_) {
          // 일부 케이스에서 stream/completer가 이미 disposed 상태가 될 수 있음.
          // (예: 위젯 언마운트/이미지 교체로 인해 스트림 정리 후 타이머가 늦게 실행)
        }
      }

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          final size = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          if (!completer.isCompleted) {
            completer.complete(size);
          }
          timeoutTimer?.cancel();
          safeRemoveListener();
        },
        onError: (exception, stackTrace) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          timeoutTimer?.cancel();
          safeRemoveListener();
        },
      );

      stream.addListener(listener);

      // 타임아웃: 10초 후 리스너 제거
      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        safeRemoveListener();
      });

      return await completer.future;
    } catch (e) {
      debugPrint(
        '[ImageSizeUtils] ⚠️ ImageProvider에서 크기 추출 실패: $imageUrl - $e',
      );
      return null;
    }
  }
}
