import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:video_compress/video_compress.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:path_provider/path_provider.dart';

/// 비디오 업로드 관련 유틸리티 클래스
class VideoUploadUtils {
  /// 최대 업로드 가능한 비디오 파일 크기 (300MB)
  static const int maxVideoSizeBytes = 300 * 1024 * 1024;
  static const int maxVideoSizeMB = 300;

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
      print('[VideoUploadUtils] 파일 크기 검증 실패: $e');
      return true; // 크기를 확인할 수 없으면 서버에서 최종 검증
    }
  }

  /// 비디오에서 썸네일 생성
  static Future<File?> generateThumbnail(
    String videoPath, {
    int quality = 50,
    int position = 500,
  }) async {
    try {
      print('[VideoUploadUtils] 썸네일 생성 시작: $videoPath');
      final thumbnail = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: quality,
        position: position,
      );
      print('[VideoUploadUtils] 썸네일 생성 완료: ${thumbnail.path}');
      return thumbnail;
    } catch (e) {
      print('[VideoUploadUtils] 썸네일 생성 실패: $e');
      return null;
    }
  }

  /// 비디오 압축 (FFmpeg 사용 - 고품질 유지하면서 용량 최적화)
  /// H.264 코덱, CRF 23 (고품질), medium preset
  static Future<File?> compressVideo(String videoPath) async {
    try {
      print('[VideoUploadUtils] 비디오 압축 시작 (FFmpeg): $videoPath');

      final originalSize = await File(videoPath).length();
      print(
        '[VideoUploadUtils] 원본 크기: ${(originalSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );

      // 출력 파일 경로
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // FFmpeg 명령어 구성
      // -i: 입력 파일
      // -c:v libx264: H.264 코덱 사용
      // -crf 23: 품질 설정 (18=거의 무손실, 23=고품질, 28=중품질)
      // -preset medium: 인코딩 속도/압축률 균형 (fast < medium < slow)
      // -c:a aac: 오디오 AAC 코덱
      // -b:a 128k: 오디오 비트레이트
      // -movflags +faststart: 웹 스트리밍 최적화 (moov atom을 앞으로)
      // -y: 기존 파일 덮어쓰기
      final command =
          '-i "$videoPath" '
          '-c:v libx264 '
          '-crf 23 '
          '-preset medium '
          '-c:a aac '
          '-b:a 128k '
          '-movflags +faststart '
          '-y '
          '"$outputPath"';

      print('[VideoUploadUtils] FFmpeg 실행...');

      // FFmpeg 실행
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();
        print('[VideoUploadUtils] FFmpeg 실패: $output');

        // 폴백: VideoCompress 사용
        print('[VideoUploadUtils] FFmpeg 실패 - VideoCompress로 폴백');
        return await _compressWithVideoCompress(videoPath);
      }

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        print('[VideoUploadUtils] 출력 파일이 생성되지 않았습니다');
        return await _compressWithVideoCompress(videoPath);
      }

      final compressedSize = await outputFile.length();
      final compressionRatio = (1 - compressedSize / originalSize) * 100;

      print('[VideoUploadUtils] ✅ FFmpeg 압축 완료!');
      print(
        '[VideoUploadUtils] 압축 크기: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );
      print('[VideoUploadUtils] 압축률: ${compressionRatio.toStringAsFixed(1)}%');

      // 압축 후 크기가 300MB를 초과하면 null 반환
      if (compressedSize > maxVideoSizeBytes) {
        print(
          '[VideoUploadUtils] ⚠️ 압축 후에도 파일이 너무 큽니다 (${(compressedSize / 1024 / 1024).toStringAsFixed(2)}MB > ${maxVideoSizeMB}MB)',
        );
        try {
          await outputFile.delete();
        } catch (_) {}
        return null;
      }

      return outputFile;
    } catch (e) {
      print('[VideoUploadUtils] 비디오 압축 중 오류: $e');
      // 에러 발생 시 폴백: VideoCompress 사용
      print('[VideoUploadUtils] 오류 발생 - VideoCompress로 폴백');
      return await _compressWithVideoCompress(videoPath);
    }
  }

  /// VideoCompress 폴백 함수
  static Future<File?> _compressWithVideoCompress(String videoPath) async {
    try {
      print('[VideoUploadUtils] VideoCompress로 압축 시작');
      final compressed = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.HighestQuality,
        deleteOrigin: false,
      );

      if (compressed == null || compressed.path == null) {
        print('[VideoUploadUtils] VideoCompress 압축 실패');
        return null;
      }

      final outputFile = File(compressed.path!);
      final compressedSize = await outputFile.length();

      print(
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
      print('[VideoUploadUtils] VideoCompress 압축 실패: $e');
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

  /// 업로드 실패 다이얼로그 표시
  static Future<void> showUploadFailedDialog(
    BuildContext context,
    Object? error,
  ) async {
    final message = buildErrorMessage(error);
    await DialogUtils.showInfoDialog(
      context,
      title: '업로드 실패',
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
