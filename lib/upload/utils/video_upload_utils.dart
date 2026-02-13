import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../core/upload_types.dart';
import '../../media/editor/video_specs.dart';

/// 비디오 압축, 썸네일, 검증 등 (업로드 공통 유틸)
class VideoUploadUtils {
  static const int maxVideoSizeBytes = 300 * 1024 * 1024;
  static const int maxVideoSizeMB = 300;

  static final Map<String, CancellationToken> _activeCompressions = {};

  static bool validateExtension(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v'}.contains(ext);
  }

  static Future<bool> validateFileSize(String filePath) async {
    try {
      final bytes = await File(filePath).length();
      return bytes <= maxVideoSizeBytes;
    } catch (e) {
      debugPrint('[VideoUploadUtils] 파일 크기 검증 실패: $e');
      return true;
    }
  }

  static Future<File?> generateThumbnail({
    required String videoPath,
    int quality = 50,
    int position = 500,
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
    Future<File?> Function({
      required String videoPath,
      required int quality,
      required VideoTrimSpec? trimSpec,
      required VideoEditSpec? editSpec,
    })?
    generateWithFFmpeg,
    Future<File?> Function({
      required String videoPath,
      required int quality,
      required int position,
    })?
    generateWithLibrary,
  }) async {
    try {
      if (trimSpec != null || editSpec != null) {
        if (generateWithFFmpeg != null) {
          return await generateWithFFmpeg(
            videoPath: videoPath,
            quality: quality,
            trimSpec: trimSpec,
            editSpec: editSpec,
          );
        }
      }
      if (generateWithLibrary != null) {
        return await generateWithLibrary(
          videoPath: videoPath,
          quality: quality,
          position: position,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[VideoUploadUtils] 썸네일 생성 실패: $e');
      return null;
    }
  }

  static Future<File?> compressVideo({
    required String videoPath,
    CancellationToken? cancellationToken,
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
    required Future<File?> Function({
      required String videoPath,
      required String outputPath,
      required VideoTrimSpec? trimSpec,
      required VideoEditSpec? editSpec,
      required CancellationToken cancellationToken,
    })
    compressWithFFmpeg,
  }) async {
    final compressionId =
        '${videoPath}_${DateTime.now().millisecondsSinceEpoch}';
    final token = cancellationToken ?? CancellationToken();
    _activeCompressions[compressionId] = token;

    try {
      if (token.isCancelled) {
        _activeCompressions.remove(compressionId);
        return null;
      }

      final tempDir = Directory.systemTemp;
      final outputPath =
          '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final outputFile = await compressWithFFmpeg(
        videoPath: videoPath,
        outputPath: outputPath,
        trimSpec: trimSpec,
        editSpec: editSpec,
        cancellationToken: token,
      );

      if (token.isCancelled) {
        if (outputFile != null && await outputFile.exists()) {
          try {
            await outputFile.delete();
          } catch (_) {}
        }
        _activeCompressions.remove(compressionId);
        return null;
      }

      if (outputFile == null || !await outputFile.exists()) {
        _activeCompressions.remove(compressionId);
        return null;
      }

      final compressedSize = await outputFile.length();
      if (compressedSize > maxVideoSizeBytes) {
        try {
          await outputFile.delete();
        } catch (_) {}
        _activeCompressions.remove(compressionId);
        return null;
      }

      _activeCompressions.remove(compressionId);
      return outputFile;
    } catch (e) {
      debugPrint('[VideoUploadUtils] 비디오 압축 중 오류: $e');
      _activeCompressions.remove(compressionId);
      return null;
    }
  }

  static void cancelAllCompressions() {
    for (final token in _activeCompressions.values) {
      token.cancel();
    }
    _activeCompressions.clear();
  }

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

    final formatError =
        lower.contains('validation_error') ||
        lower.contains('형식의 동영상') ||
        lower.contains('video/mp4') ||
        lower.contains('형식') ||
        lower.contains('format');
    if (formatError) {
      return '지원하지 않는 파일 형식입니다\nmp4, mov, m4v 형식의 영상만 업로드 가능합니다';
    }

    final looksNullish =
        lower.contains('video upload failed null') ||
        lower.contains('null: null') ||
        lower.trim() == 'null' ||
        message.trim().isEmpty;
    if (looksNullish) {
      return '업로드에 실패했습니다.\n네트워크상태를 확인해주세요';
    }

    return '영상 업로드에 실패했습니다.\n잠시 후 다시 시도해주세요';
  }

  static String buildFFmpegCommand({
    required String videoPath,
    required String outputPath,
    VideoTrimSpec? trimSpec,
    VideoEditSpec? editSpec,
  }) {
    final List<String> inputArgs = [];
    final List<String> videoFilters = [];
    final List<String> outputArgs = [];

    inputArgs.add('-i "$videoPath"');

    if (trimSpec != null) {
      final startSeconds = trimSpec.startSeconds;
      final duration = trimSpec.endSeconds - trimSpec.startSeconds;
      if (startSeconds > 0) {
        inputArgs.insert(0, '-ss ${startSeconds.toStringAsFixed(3)}');
      }
      if (duration > 0) {
        inputArgs.add('-t ${duration.toStringAsFixed(3)}');
      }
    }

    if (editSpec != null) {
      final filters = <String>[];

      if (editSpec.rotationQuarterTurns > 0) {
        final turns = editSpec.rotationQuarterTurns % 4;
        if (turns == 1) {
          filters.add('transpose=1');
        } else if (turns == 2) {
          filters.add('transpose=1,transpose=1');
        } else if (turns == 3) {
          filters.add('transpose=2');
        }
      }

      if (editSpec.rotation != 0) {
        final radians = editSpec.rotation * math.pi / 180;
        filters.add('rotate=$radians:fillcolor=black@0:ow=iw:oh=ih');
      }

      if (editSpec.flipHorizontal) filters.add('hflip');
      if (editSpec.flipVertical) filters.add('vflip');

      if (editSpec.cropRectImage != null) {
        final rect = editSpec.cropRectImage!;
        final w = rect.width.round();
        final h = rect.height.round();
        final x = rect.left.round();
        final y = rect.top.round();
        filters.add('crop=$w:$h:$x:$y');
      }

      final adjustments = <String>[];
      if (editSpec.brightness != 0.0) {
        final val = (editSpec.brightness / 100.0).clamp(-1.0, 1.0);
        adjustments.add('brightness=$val');
      }
      if (editSpec.contrast != 0.0) {
        final val = (1.0 + editSpec.contrast / 100.0).clamp(0.0, 2.0);
        adjustments.add('contrast=$val');
      }
      if (editSpec.saturation != 0.0) {
        final val = (1.0 + editSpec.saturation / 100.0).clamp(0.0, 2.0);
        adjustments.add('saturation=$val');
      }
      if (adjustments.isNotEmpty) {
        filters.add('eq=${adjustments.join(":")}');
      }

      if (editSpec.luminance != 0.0) {
        final gamma = (1.0 + editSpec.luminance / 100.0).clamp(0.1, 3.0);
        filters.add('eq=gamma_r=$gamma:gamma_g=$gamma:gamma_b=$gamma');
      }

      if (editSpec.exposure != 0.0) {
        final exposure = (editSpec.exposure / 100.0 * 3.0).clamp(-3.0, 3.0);
        if (exposure > 0) {
          final blackPoint = (exposure / 3.0 * 0.1).clamp(0.0, 0.1);
          filters.add(
            'colorlevels=rimin=$blackPoint:gimin=$blackPoint:bimin=$blackPoint',
          );
        } else {
          final whitePoint = (1.0 + exposure / 3.0 * 0.1).clamp(0.9, 1.0);
          filters.add(
            'colorlevels=rimax=$whitePoint:gimax=$whitePoint:bimax=$whitePoint',
          );
        }
      }

      if (editSpec.sharpness > 0.0) {
        final amount = (editSpec.sharpness / 100.0 * 1.5).clamp(0.0, 2.0);
        filters.add('unsharp=5:5:$amount');
      }

      if (editSpec.temperature != 0.0) {
        final val = (editSpec.temperature / 100.0).clamp(-1.0, 1.0);
        filters.add('colorbalance=rs=$val:gs=0:bs=${-val}');
      }

      if (editSpec.blur > 0.0) {
        final radius = (editSpec.blur / 100.0 * 20.0).clamp(0.0, 20.0);
        filters.add('boxblur=luma_radius=$radius:luma_power=1');
      }

      if (editSpec.vignette > 0.0) {
        final intensity = (editSpec.vignette / 100.0).clamp(0.0, 1.0);
        final aspect = 1.0 - (intensity * 0.5);
        filters.add('vignette=PI/4:aspect=$aspect:mode=0');
      }

      if (editSpec.playbackSpeed != 1.0 && editSpec.playbackSpeed > 0) {
        final ptsScale = 1.0 / editSpec.playbackSpeed;
        filters.add('setpts=${ptsScale.toStringAsFixed(6)}*PTS');
      }

      if (filters.isNotEmpty) {
        videoFilters.add('-vf "${filters.join(",")}"');
      }

      if (editSpec.playbackSpeed != 1.0 && editSpec.playbackSpeed > 0) {
        final speed = editSpec.playbackSpeed.clamp(0.5, 2.0);
        if (speed != 1.0) {
          videoFilters.add('-af "atempo=$speed"');
        }
      }
    }

    outputArgs.addAll([
      '-vcodec libx264',
      '-preset veryfast',
      '-crf 20',
      '-x264opts keyint=24:min-keyint=24:no-scenecut',
      '-pix_fmt yuv420p',
      '-profile:v main',
      '-level 3.1',
      '-acodec aac',
      '-movflags +faststart',
      '-y',
      '"$outputPath"',
    ]);

    final commandParts = <String>[];
    commandParts.addAll(inputArgs);
    commandParts.addAll(videoFilters);
    commandParts.addAll(outputArgs);
    return commandParts.join(' ');
  }
}
