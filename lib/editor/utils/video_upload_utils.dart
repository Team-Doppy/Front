import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';

/// 취소 토큰 클래스
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      for (final listener in _listeners) {
        listener();
      }
    }
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

/// 비디오 업로드 관련 유틸리티 클래스
class VideoUploadUtils {
  /// 최대 업로드 가능한 비디오 파일 크기 (300MB)
  static const int maxVideoSizeBytes = 300 * 1024 * 1024;
  static const int maxVideoSizeMB = 300;

  /// 현재 압축 중인 세션 추적 (취소용)
  static final Map<String, CancellationToken> _activeCompressions = {};

  /// 비디오 파일 확장자 검증 (mp4, mov, m4v만 허용)
  static bool validateExtension(String filePath) {
    final String ext = filePath.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v'}.contains(ext);
  }

  /// 비디오 파일 크기 검증 (최대 300MB)
  static Future<bool> validateFileSize(String filePath) async {
    try {
      final int bytes = await File(filePath).length();
      return bytes <= maxVideoSizeBytes;
    } catch (e) {
      debugPrint('[VideoUploadUtils] 파일 크기 검증 실패: $e');
      return true; // 크기를 확인할 수 없으면 서버에서 최종 검증
    }
  }

  /// 비디오에서 썸네일 생성
  /// [quality] 0-100 (낮을수록 빠르지만 품질 낮음)
  /// [position] 밀리초 단위 (0 = 첫 프레임)
  /// [useFastMethod] true면 VideoThumbnail 사용 (더 빠름), false면 VideoCompress 사용
  static Future<File?> generateThumbnail(
    String videoPath, {
    int quality = 50,
    int position = 500,
    bool useFastMethod = false,
  }) async {
    try {
      debugPrint(
        '[VideoUploadUtils] 썸네일 생성 시작: $videoPath (quality=$quality, position=${position}ms, fast=$useFastMethod)',
      );

      if (useFastMethod) {
        // VideoThumbnail 사용 (더 빠름)
        try {
          final tempDir = await getTemporaryDirectory();
          final thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: videoPath,
            thumbnailPath: tempDir.path,
            imageFormat: ImageFormat.JPEG,
            quality: quality,
            timeMs: position,
          );
          if (thumbnailPath != null) {
            final thumbnailFile = File(thumbnailPath);
            if (await thumbnailFile.exists()) {
              debugPrint(
                '[VideoUploadUtils] 썸네일 생성 완료 (VideoThumbnail): $thumbnailPath',
              );
              return thumbnailFile;
            }
          }
        } catch (e) {
          debugPrint(
            '[VideoUploadUtils] VideoThumbnail 실패, VideoCompress로 폴백: $e',
          );
        }
      }

      // VideoCompress 사용 (기본)
      final thumbnail = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: quality,
        position: position,
      );
      debugPrint(
        '[VideoUploadUtils] 썸네일 생성 완료 (VideoCompress): ${thumbnail.path}',
      );
      return thumbnail;
    } catch (e) {
      debugPrint('[VideoUploadUtils] 썸네일 생성 실패: $e');
      return null;
    }
  }

  /// 비디오 압축 (FFmpeg 사용 - 고품질 유지하면서 용량 최적화)
  /// H.264 코덱, CRF 23 (고품질), medium preset
  /// [cancellationToken]이 제공되면 취소 가능
  static Future<File?> compressVideo(
    String videoPath, {
    CancellationToken? cancellationToken,
  }) async {
    final compressionId =
        '${videoPath}_${DateTime.now().millisecondsSinceEpoch}';
    final token = cancellationToken ?? CancellationToken();
    _activeCompressions[compressionId] = token;

    try {
      debugPrint('[VideoUploadUtils] 비디오 압축 시작 (FFmpeg): $videoPath');

      // 취소 확인
      if (token.isCancelled) {
        debugPrint('[VideoUploadUtils] 압축이 이미 취소됨');
        _activeCompressions.remove(compressionId);
        return null;
      }

      final originalSize = await File(videoPath).length();
      debugPrint(
        '[VideoUploadUtils] 원본 크기: ${(originalSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );

      // 출력 파일 경로
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // FFmpeg 명령어 구성
      // -i: 입력 파일
      // -c:v libx264: H.264 코덱 사용
      // -crf 18: 품질 설정 (18=거의 무손실, 원본과 거의 동일한 품질)
      // -preset fast: 인코딩 속도와 CPU 사용률의 균형 (medium보다 빠르고 CPU 사용률 낮음)
      // -threads 2: CPU 코어 2개만 사용 (전체 CPU 사용 방지, 기기 발열 및 배터리 절약)
      // -c:a aac: 오디오 AAC 코덱
      // -b:a 192k: 오디오 비트레이트 (고품질, 원본과 유사한 품질)
      // -movflags +faststart: 웹 스트리밍 최적화 (moov atom을 앞으로)
      // -y: 기존 파일 덮어쓰기
      // 참고: 해상도는 자동으로 원본과 동일하게 유지됨
      final command =
          '-i "$videoPath" '
          '-c:v libx264 '
          '-crf 18 '
          '-preset fast '
          '-threads 2 '
          '-c:a aac '
          '-b:a 192k '
          '-movflags +faststart '
          '-y '
          '"$outputPath"';

      debugPrint('[VideoUploadUtils] FFmpeg 실행...');

      // FFmpeg 실행 (비동기)
      final session = await FFmpegKit.executeAsync(command, (session) async {
        // 완료 콜백
      });

      // 취소 감지: 주기적으로 확인
      checkCancellation() async {
        while (!token.isCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (token.isCancelled) {
            debugPrint('[VideoUploadUtils] 압축 취소 요청됨');
            FFmpegKit.cancel();
            break;
          }
        }
      }

      checkCancellation();

      final returnCode = await session.getReturnCode();

      // 취소 확인
      if (token.isCancelled) {
        debugPrint('[VideoUploadUtils] 압축이 취소됨');
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          try {
            await outputFile.delete();
          } catch (_) {}
        }
        _activeCompressions.remove(compressionId);
        return null;
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        // 취소된 경우
        if (token.isCancelled) {
          debugPrint('[VideoUploadUtils] 압축이 취소됨');
          _activeCompressions.remove(compressionId);
          return null;
        }

        final output = await session.getOutput();
        debugPrint('[VideoUploadUtils] FFmpeg 실패: $output');

        // 폴백: VideoCompress 사용
        debugPrint('[VideoUploadUtils] FFmpeg 실패 - VideoCompress로 폴백');
        final result = await _compressWithVideoCompress(
          videoPath,
          token: token,
        );
        _activeCompressions.remove(compressionId);
        return result;
      }

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        debugPrint('[VideoUploadUtils] 출력 파일이 생성되지 않았습니다');
        return await _compressWithVideoCompress(videoPath);
      }

      final compressedSize = await outputFile.length();
      final compressionRatio = (1 - compressedSize / originalSize) * 100;

      debugPrint('[VideoUploadUtils] ✅ FFmpeg 압축 완료!');
      debugPrint(
        '[VideoUploadUtils] 압축 크기: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );
      debugPrint(
        '[VideoUploadUtils] 압축률: ${compressionRatio.toStringAsFixed(1)}%',
      );

      // 압축 후 크기가 300MB를 초과하면 null 반환
      if (compressedSize > maxVideoSizeBytes) {
        debugPrint(
          '[VideoUploadUtils] ⚠️ 압축 후에도 파일이 너무 큽니다 (${(compressedSize / 1024 / 1024).toStringAsFixed(2)}MB > ${maxVideoSizeMB}MB)',
        );
        try {
          await outputFile.delete();
        } catch (_) {}
        return null;
      }

      _activeCompressions.remove(compressionId);
      return outputFile;
    } catch (e) {
      debugPrint('[VideoUploadUtils] 비디오 압축 중 오류: $e');

      // 취소된 경우
      if (token.isCancelled) {
        debugPrint('[VideoUploadUtils] 압축이 취소됨');
        _activeCompressions.remove(compressionId);
        return null;
      }

      // 에러 발생 시 폴백: VideoCompress 사용
      debugPrint('[VideoUploadUtils] 오류 발생 - VideoCompress로 폴백');
      final result = await _compressWithVideoCompress(videoPath, token: token);
      _activeCompressions.remove(compressionId);
      return result;
    }
  }

  /// 모든 진행 중인 압축 취소
  static void cancelAllCompressions() {
    debugPrint('[VideoUploadUtils] 모든 압축 취소 요청');
    for (final token in _activeCompressions.values) {
      token.cancel();
    }
    _activeCompressions.clear();
  }

  /// VideoCompress 폴백 함수
  static Future<File?> _compressWithVideoCompress(
    String videoPath, {
    CancellationToken? token,
  }) async {
    // 취소 확인
    if (token != null && token.isCancelled) {
      return null;
    }
    try {
      debugPrint('[VideoUploadUtils] VideoCompress로 압축 시작');
      final compressed = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.HighestQuality,
        deleteOrigin: false,
      );

      if (compressed == null || compressed.path == null) {
        debugPrint('[VideoUploadUtils] VideoCompress 압축 실패');
        return null;
      }

      final outputFile = File(compressed.path!);
      final compressedSize = await outputFile.length();

      debugPrint(
        '[VideoUploadUtils] VideoCompress 압축 완료: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );

      if (compressedSize > maxVideoSizeBytes) {
        try {
          await outputFile.delete();
        } catch (_) {}
        return null;
      }

      return outputFile;
    } catch (e) {
      debugPrint('[VideoUploadUtils] VideoCompress 압축 실패: $e');
      return null;
    }
  }

  /// 에러 메시지를 사용자 친화적으로 변환
  static String buildErrorMessage(Object? err) {
    String message = '영상 업로드에 실패했습니다.';
    try {
      if (err is HttpException) {
        message = err.message;
      } else if (err is DioException) {
        final data = err.response?.data;
        if (data is String && data.isNotEmpty) {
          message = data;
        } else if (data is Map<String, dynamic>) {
          message =
              (data['message']?.toString() ??
                  data['error']?.toString() ??
                  message);
        } else {
          message = err.message ?? message;
        }
      } else if (err != null) {
        message = err.toString();
      }
    } catch (_) {}

    final lower = message.toLowerCase();

    // 1. 파일 크기 초과
    final tooLarge =
        lower.contains('400') ||
        lower.contains('413') ||
        lower.contains('payload too large') ||
        lower.contains('request entity too large') ||
        lower.contains('file too large') ||
        lower.contains('too large') ||
        lower.contains('size limit') ||
        lower.contains('용량 초과') ||
        lower.contains('너무 큽') ||
        lower.contains('크기가 너무 큽') ||
        lower.contains('파일 크기가');
    if (tooLarge) {
      return '파일이 너무 큽니다\n최대 ${maxVideoSizeMB}MB까지만 업로드 가능합니다.';
    }

    // 2. 파일 형식 오류
    final formatError =
        lower.contains('validation_error') ||
        lower.contains('형식의 동영상') ||
        lower.contains('video/mp4') ||
        lower.contains('형식') ||
        lower.contains('format');
    if (formatError) {
      return '지원하지 않는 파일 형식입니다\nmp4, mov, m4v 형식의 영상만 업로드 가능합니다';
    }

    // 3. 서버 메시지가 무의미/누락일 때: 네트워크 안내로 통일
    final looksNullish =
        lower.contains('video upload failed null') ||
        lower.contains('null: null') ||
        lower.trim() == 'null' ||
        message.trim().isEmpty;
    if (looksNullish) {
      return '업로드에 실패했습니다.\n네트워크상태를 확인해주세요';
    }

    // 4. 기타 에러는 간단한 메시지로
    return '영상 업로드에 실패했습니다.\n잠시 후 다시 시도해주세요';
  }

  /// 업로드 실패 다이얼로그 표시 (로케일 적용)
  static Future<void> showUploadFailedDialog(
    BuildContext context,
    Object? error,
  ) async {
    final message = buildErrorMessage(error);
    final localization = AppLocalizations.of(context);
    final title = localization.translate('upload_failed');
    await DialogUtils.showInfoDialog(
      context,
      title: title.isNotEmpty ? title : '업로드 실패',
      message: message,
    );
  }

  /// 업로드 취소 다이얼로그 표시
  static Future<void> showUploadCancelledDialog(BuildContext context) async {
    await DialogUtils.showInfoDialog(
      context,
      title: '업로드 취소',
      message: '영상 업로드가 취소되었습니다',
    );
  }

  /// 업로드 타임아웃 다이얼로그 표시
  static Future<void> showUploadTimeoutDialog(BuildContext context) async {
    await DialogUtils.showInfoDialog(
      context,
      title: '업로드 실패',
      message: '업로드 시간이 초과되었습니다.\n네트워크 상태를 확인해주세요',
    );
  }

  /// 일반 오류 다이얼로그 표시
  static Future<void> showGeneralErrorDialog(BuildContext context) async {
    await DialogUtils.showInfoDialog(
      context,
      title: '오류',
      message: '영상 처리 중 오류가 발생했습니다.\n잠시 후 다시 시도해주세요',
    );
  }

  /// 클라이언트 측 파일 검증 (확장자 + 크기)
  static Future<String?> validateFile(
    BuildContext context,
    String filePath,
  ) async {
    // 확장자 검증
    if (!validateExtension(filePath)) {
      await DialogUtils.showInfoDialog(
        context,
        title: '지원하지 않는 형식',
        message: '영상 형식이 지원되지 않습니다. mp4/mov/m4v만 업로드 가능합니다.',
      );
      return '지원하지 않는 형식';
    }

    // 파일 크기 검증
    final isValidSize = await validateFileSize(filePath);
    if (!isValidSize) {
      await DialogUtils.showInfoDialog(
        context,
        title: '파일이 너무 큽니다',
        message: '최대 ${maxVideoSizeMB}MB까지만 업로드 가능합니다.',
      );
      return '파일이 너무 큽니다';
    }

    return null; // 검증 성공
  }
}
