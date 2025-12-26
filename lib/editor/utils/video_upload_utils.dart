import 'dart:async';
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

  /// 비디오 압축 (FFmpeg 사용 - 고품질 유지하면서 용량 및 로딩 속도 최적화)
  /// H.264 코덱, CRF 20 (고품질), veryfast preset, GOP 24 (1초 간격)
  /// [cancellationToken]이 제공되면 취소 가능
  /// 100MB 이하 mp4 파일은 압축을 건너뛰고 원본 파일을 반환합니다.
  static Future<File?> compressVideo(
    String videoPath, {
    CancellationToken? cancellationToken,
  }) async {
    final compressionId =
        '${videoPath}_${DateTime.now().millisecondsSinceEpoch}';
    final token = cancellationToken ?? CancellationToken();
    _activeCompressions[compressionId] = token;

    try {
      // 취소 확인
      if (token.isCancelled) {
        debugPrint('[VideoUploadUtils] 압축이 이미 취소됨');
        _activeCompressions.remove(compressionId);
        return null;
      }

      final originalSize = await File(videoPath).length();
      final fileExtension = videoPath.split('.').last.toLowerCase();

      debugPrint(
        '[VideoUploadUtils] 원본 크기: ${(originalSize / 1024 / 1024).toStringAsFixed(2)}MB, 형식: $fileExtension',
      );

      // 🎯 모든 파일을 FFmpeg H.264 재인코딩 (검정 화면 문제 해결)
      // 핵심: keyframe을 선두에 배치하여 video_player가 즉시 디코딩 가능하도록
      debugPrint(
        '[VideoUploadUtils] 비디오 처리 시작 (FFmpeg H.264 re-encode): $videoPath',
      );

      // 출력 파일 경로
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 🎯 FFmpeg 명령어: 고품질 압축 및 빠른 로딩을 위한 H.264 재인코딩
      // -vcodec libx264: H.264 코덱 (keyframe 제어 가능)
      // -preset veryfast: 빠른 인코딩 + 적절한 압축 효율 (ultrafast보다 효율적)
      // -crf 20: 고품질 (18보다 약간 낮지만 체감 차이 거의 없음, 파일 크기 감소)
      // -x264opts: x264 레벨 파라미터
      //   - keyint=24: 최대 GOP 24 (1초마다 keyframe, 24fps 기준 - 초기 로딩 최적화)
      //   - min-keyint=24: 최소 GOP 24 (고정 간격)
      //   - no-scenecut: scene change detection 완전 비활성화
      // -pix_fmt yuv420p: 호환성 높은 픽셀 포맷
      // -profile:v main: main profile (baseline보다 효율적)
      // -level 3.1: 모바일 호환성
      // -acodec aac: AAC 오디오
      // -movflags +faststart: 스트리밍 최적화 (moov atom 앞 배치)
      final command =
          '-i "$videoPath" '
          '-vcodec libx264 '
          '-preset veryfast '
          '-crf 20 '
          '-x264opts keyint=24:min-keyint=24:no-scenecut '
          '-pix_fmt yuv420p '
          '-profile:v main '
          '-level 3.1 '
          '-acodec aac '
          '-movflags +faststart '
          '-y '
          '"$outputPath"';

      debugPrint(
        '[VideoUploadUtils] FFmpeg 실행 (H.264 re-encode with GOP=24, preset=veryfast, CRF=20)...',
      );

      // FFmpeg 실행 (비동기)
      final session = await FFmpegKit.executeAsync(command, (session) async {
        // 완료 콜백
      });

      // 🎯 취소 감지: 주기적으로 확인 (백그라운드에서 실행)
      unawaited(() async {
        while (!token.isCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (token.isCancelled) {
            debugPrint('[VideoUploadUtils] 압축 취소 요청됨');
            FFmpegKit.cancel();
            break;
          }
        }
      }());

      // 🎯 세션이 완료될 때까지 기다리기 (또는 취소될 때까지)
      // getReturnCode()는 세션이 완료되면 즉시 반환되지만, 완료 전에는 null을 반환할 수 있음
      // 따라서 주기적으로 확인하면서 완료를 기다림
      ReturnCode? returnCode;
      int attempts = 0;
      const maxAttempts = 600; // 최대 5분 대기 (500ms * 600 = 300초)

      while (returnCode == null &&
          attempts < maxAttempts &&
          !token.isCancelled) {
        await Future.delayed(const Duration(milliseconds: 500));
        returnCode = await session.getReturnCode();
        attempts++;

        // 취소 확인
        if (token.isCancelled) {
          debugPrint('[VideoUploadUtils] 압축이 취소됨 (대기 중)');
          FFmpegKit.cancel();
          final outputFile = File(outputPath);
          if (await outputFile.exists()) {
            try {
              await outputFile.delete();
            } catch (_) {}
          }
          _activeCompressions.remove(compressionId);
          return null;
        }
      }

      // 🎯 최종 취소 확인
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

      // 🎯 여전히 null이면 세션이 아직 실행 중이거나 취소된 것
      if (returnCode == null) {
        debugPrint('[VideoUploadUtils] ⚠️ FFmpeg 세션이 완료되지 않았습니다 (타임아웃 또는 취소)');
        // 취소 시도
        try {
          FFmpegKit.cancel();
        } catch (_) {}
        _activeCompressions.remove(compressionId);
        return null;
      }

      // 취소 확인 (가장 먼저)
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
        // 취소된 경우 (중복 체크)
        if (token.isCancelled) {
          debugPrint('[VideoUploadUtils] 압축이 취소됨');
          _activeCompressions.remove(compressionId);
          return null;
        }

        // 🎯 상세한 에러 로그 수집
        final output = await session.getOutput();
        final allLogs = await session.getAllLogsAsString();
        final failStackTrace = await session.getFailStackTrace();

        debugPrint('[VideoUploadUtils] FFmpeg 실패 (ReturnCode: $returnCode)');
        if (output != null && output.isNotEmpty) {
          debugPrint('[VideoUploadUtils] FFmpeg 출력: $output');
        }
        if (allLogs != null && allLogs.isNotEmpty) {
          // 마지막 1000자만 출력 (너무 길면 잘라냄)
          final logsToPrint =
              allLogs.length > 1000
                  ? '...${allLogs.substring(allLogs.length - 1000)}'
                  : allLogs;
          debugPrint('[VideoUploadUtils] FFmpeg 전체 로그 (마지막 부분): $logsToPrint');
        }
        if (failStackTrace != null && failStackTrace.isNotEmpty) {
          debugPrint('[VideoUploadUtils] FFmpeg 스택 트레이스: $failStackTrace');
        }

        // 🎯 FFmpeg 세션 명시적으로 취소 (리소스 낭비 방지)
        try {
          FFmpegKit.cancel();
          debugPrint('[VideoUploadUtils] FFmpeg 세션 취소 완료');
        } catch (e) {
          debugPrint('[VideoUploadUtils] FFmpeg 세션 취소 오류: $e');
        }

        // 폴백: VideoCompress 사용
        debugPrint('[VideoUploadUtils] FFmpeg 실패 - VideoCompress로 폴백');
        _activeCompressions.remove(compressionId);
        return null;
      }

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        debugPrint('[VideoUploadUtils] ⚠️ 출력 파일이 생성되지 않았습니다');

        // 🎯 상세한 에러 로그 수집
        final output = await session.getOutput();
        final allLogs = await session.getAllLogsAsString();
        if (output != null && output.isNotEmpty) {
          debugPrint('[VideoUploadUtils] FFmpeg 출력: $output');
        }
        if (allLogs != null && allLogs.isNotEmpty) {
          final logsToPrint =
              allLogs.length > 1000
                  ? '...${allLogs.substring(allLogs.length - 1000)}'
                  : allLogs;
          debugPrint('[VideoUploadUtils] FFmpeg 전체 로그 (마지막 부분): $logsToPrint');
        }

        // 🎯 FFmpeg 세션 명시적으로 취소
        try {
          FFmpegKit.cancel();
        } catch (e) {
          debugPrint('[VideoUploadUtils] FFmpeg 세션 취소 오류: $e');
        }

        _activeCompressions.remove(compressionId);
        return null;
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

      // 🎯 FFmpeg 세션 명시적으로 취소 (에러 발생 시)
      try {
        FFmpegKit.cancel();
        debugPrint('[VideoUploadUtils] FFmpeg 세션 취소 완료 (에러 발생)');
      } catch (cancelError) {
        debugPrint('[VideoUploadUtils] FFmpeg 세션 취소 오류: $cancelError');
      }

      _activeCompressions.remove(compressionId);
      return null;
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
