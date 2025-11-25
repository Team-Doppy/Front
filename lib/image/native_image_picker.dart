import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 네이티브 이미지/영상 선택기
class NativeImagePicker {
  final ImagePicker _picker = ImagePicker();

  /// 단일 이미지 선택
  Future<File?> pickSingleImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      debugPrint('이미지 선택 오류: $e');
      return null;
    }
  }

  /// 다중 이미지 선택 (최대 개수 제한 가능)
  Future<List<File>> pickMultipleImages({int? maxCount}) async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 85,
        limit: maxCount,
      );

      return images.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      debugPrint('다중 이미지 선택 오류: $e');
      return [];
    }
  }

  /// 단일 영상 선택
  Future<File?> pickSingleVideo({
    ImageSource source = ImageSource.gallery,
  }) async {
    try {
      final XFile? video = await _picker.pickVideo(source: source);

      if (video != null) {
        return File(video.path);
      }
      return null;
    } catch (e) {
      debugPrint('영상 선택 오류: $e');
      return null;
    }
  }

  /// 이미지 또는 영상 선택 (다중)
  Future<List<File>> pickMedia({int? maxCount}) async {
    try {
      final List<XFile> media = await _picker.pickMultipleMedia(
        imageQuality: 85,
        limit: maxCount,
      );

      return media.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      debugPrint('미디어 선택 오류: $e');
      return [];
    }
  }
}
