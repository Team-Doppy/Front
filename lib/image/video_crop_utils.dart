import 'dart:io';
import 'package:doppy/image/crop_editor.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';

/// 비디오 크롭 유틸리티
/// FFmpeg를 사용하여 비디오 크롭을 처리합니다.
class VideoCropUtils {
  VideoCropUtils._();

  /// 비디오 크롭 적용 (트림 + 크롭)
  ///
  /// [videoFile] 원본 비디오 파일
  /// [startValue] 트림 시작 시간 (초)
  /// [endValue] 트림 종료 시간 (초)
  /// [cropState] 크롭 상태
  /// [videoWidth] 원본 비디오 너비 (픽셀)
  /// [videoHeight] 원본 비디오 높이 (픽셀)
  static Future<File> applyVideoCrop({
    required File videoFile,
    required double startValue,
    required double endValue,
    required CropState cropState,
    required int videoWidth,
    required int videoHeight,
  }) async {
    final tempDir = await Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/cropped_$timestamp.mp4';

    final duration = endValue - startValue;

    // ✅ 크롭이 없으면 트림만 수행 (copy 코덱으로 빠르게)
    if (!cropState.isCropRectInitialized || cropState.cropRectImage == null) {
      return await _trimOnly(videoFile, startValue, endValue, outputPath);
    }

    // ✅ 크롭 영역을 픽셀 좌표로 변환
    final cropRect = cropState.cropRectImage!;
    final x = cropRect.left.toInt().clamp(0, videoWidth);
    final y = cropRect.top.toInt().clamp(0, videoHeight);
    final w = cropRect.width.toInt().clamp(1, videoWidth - x);
    final h = cropRect.height.toInt().clamp(1, videoHeight - y);

    // ✅ 짝수로 맞춤 (비디오 코덱 요구사항)
    final cropX = (x ~/ 2) * 2;
    final cropY = (y ~/ 2) * 2;
    final cropW = (w ~/ 2) * 2;
    final cropH = (h ~/ 2) * 2;

    // ✅ FFmpeg crop 필터 적용
    // -ss: 시작 시간
    // -t: 길이
    // -vf crop=w:h:x:y: 크롭 필터 (너비:높이:x좌표:y좌표)
    // -c:v libx264: 비디오 코덱 (크롭은 재인코딩 필요)
    // -preset veryfast: 빠른 인코딩
    // -crf 20: 고품질
    // -c:a copy: 오디오는 복사 (빠름)
    final command =
        '-ss ${startValue.toStringAsFixed(2)} '
        '-i "${videoFile.path}" '
        '-t ${duration.toStringAsFixed(2)} '
        '-vf "crop=$cropW:$cropH:$cropX:$cropY" '
        '-c:v libx264 '
        '-preset veryfast '
        '-crf 20 '
        '-pix_fmt yuv420p '
        '-c:a copy '
        '-movflags +faststart '
        '-y '
        '"$outputPath"';

    debugPrint('[VideoCrop] FFmpeg 명령 (트림+크롭): $command');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        debugPrint('[VideoCrop] ✅ 크롭 완료: $outputPath');
        return outputFile;
      } else {
        throw Exception('출력 파일이 생성되지 않았습니다.');
      }
    } else {
      final output = await session.getOutput();
      debugPrint('[VideoCrop] ❌ FFmpeg 실패: $output');
      throw Exception('비디오 크롭에 실패했습니다.');
    }
  }

  /// 트림만 수행 (크롭 없음, copy 코덱으로 빠르게)
  static Future<File> _trimOnly(
    File videoFile,
    double startValue,
    double endValue,
    String outputPath,
  ) async {
    final duration = endValue - startValue;

    final command =
        '-ss ${startValue.toStringAsFixed(2)} '
        '-i "${videoFile.path}" '
        '-t ${duration.toStringAsFixed(2)} '
        '-c copy '
        '-movflags +faststart '
        '-avoid_negative_ts make_zero '
        '-y '
        '"$outputPath"';

    debugPrint('[VideoCrop] FFmpeg 명령 (트림만): $command');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        return outputFile;
      } else {
        throw Exception('출력 파일이 생성되지 않았습니다.');
      }
    } else {
      final output = await session.getOutput();
      debugPrint('[VideoCrop] ❌ FFmpeg 실패: $output');
      throw Exception('비디오 트림에 실패했습니다.');
    }
  }
}
