import 'dart:io';
import 'package:flutter/material.dart';
import 'gallery_bottom_sheet.dart';

class ProfileImageBottomSheet extends StatelessWidget {
  final Future<void> Function() onClearProfileImage;
  final Function(List<File>) onImagesSelected;
  final bool singleSelect;

  const ProfileImageBottomSheet({
    Key? key,
    required this.onClearProfileImage,
    required this.onImagesSelected,
    this.singleSelect = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        padding: const EdgeInsets.only(bottom: 28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
            ListTile(
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '갤러리에서 선택',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
              onTap: () async {
                // 현재 시트 닫고 갤러리 시트 오픈
                Navigator.pop(context);
                await showModalBottomSheet(
                  context: context,
                  backgroundColor: theme.colorScheme.surface,
                  barrierColor: Colors.black54,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  builder:
                      (_) => GalleryBottomSheet(
                        singleSelect: singleSelect,
                        onImagesSelected: (files) {
                          onImagesSelected(files);
                        },
                      ),
                );
              },
            ),
            ListTile(
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '기본 이미지로 변경',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
              onTap: () async {
                try {
                  await onClearProfileImage();
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('변경 실패: $e'),
                        backgroundColor: theme.colorScheme.error,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
