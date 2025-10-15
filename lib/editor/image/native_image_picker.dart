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
      print('이미지 선택 오류: $e');
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
      print('다중 이미지 선택 오류: $e');
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
      print('영상 선택 오류: $e');
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
      print('미디어 선택 오류: $e');
      return [];
    }
  }

  /// 선택 옵션을 보여주는 바텀시트
  static Future<List<File>?> showPickerBottomSheet(
    BuildContext context, {
    bool allowMultiple = true,
    int? maxCount,
    bool allowVideo = false,
  }) async {
    final picker = NativeImagePicker();

    return await showModalBottomSheet<List<File>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            padding: const EdgeInsets.only(bottom: 28),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                if (allowMultiple) ...[
                  ListTile(
                    leading: Icon(
                      allowVideo ? Icons.perm_media : Icons.photo_library,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                    ),
                    title: Text(
                      allowVideo ? '갤러리에서 선택 (이미지/영상)' : '갤러리에서 선택 (여러 장)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                    subtitle:
                        maxCount != null
                            ? Text(
                              '최대 $maxCount개',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                            )
                            : null,
                    onTap: () async {
                      final files =
                          allowVideo
                              ? await picker.pickMedia(maxCount: maxCount)
                              : await picker.pickMultipleImages(
                                maxCount: maxCount,
                              );
                      if (context.mounted) {
                        Navigator.pop(context, files.isNotEmpty ? files : null);
                      }
                    },
                  ),
                ],
                ListTile(
                  leading: Icon(
                    Icons.photo_camera,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                  title: Text(
                    '카메라로 촬영',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  onTap: () async {
                    final file = await picker.pickSingleImage(
                      source: ImageSource.camera,
                    );
                    if (context.mounted) {
                      Navigator.pop(context, file != null ? [file] : null);
                    }
                  },
                ),
                if (!allowMultiple) ...[
                  ListTile(
                    leading: Icon(
                      Icons.photo,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                    ),
                    title: Text(
                      '갤러리에서 선택',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                    onTap: () async {
                      final file = await picker.pickSingleImage();
                      if (context.mounted) {
                        Navigator.pop(context, file != null ? [file] : null);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
