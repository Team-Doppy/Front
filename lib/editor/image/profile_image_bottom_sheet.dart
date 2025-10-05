import 'dart:io';
import 'package:doppy/data/models/user_model.dart';
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

class ProfileInfoEditBottomSheet extends StatefulWidget {
  final User? user;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final Future<void> Function()? onClearProfileImage;
  final Function(List<File>)? onImagesSelected;
  final Future<void> Function({
    required String alias,
    required String description,
  })?
  onSave;

  const ProfileInfoEditBottomSheet({
    super.key,
    required this.user,
    required this.nameController,
    required this.descriptionController,
    this.onClearProfileImage,
    this.onImagesSelected,
    this.onSave,
  });

  @override
  State<ProfileInfoEditBottomSheet> createState() =>
      _ProfileInfoEditBottomSheetState();
}

class _ProfileInfoEditBottomSheetState
    extends State<ProfileInfoEditBottomSheet> {
  bool _saving = false;
  bool _showImageActions = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = screenHeight - keyboardHeight;
    final sheetHeight = availableHeight * 0.95;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: sheetHeight - 32),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 원형 프로필 + 액션 버튼
                    Center(
                      child: SizedBox(
                        width: 120,
                        height: 120,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onTap:
                                  () => setState(
                                    () =>
                                        _showImageActions = !_showImageActions,
                                  ),
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor: theme.colorScheme.onSurface
                                    .withOpacity(0.08),
                                backgroundImage:
                                    (widget.user?.profileImageUrl != null &&
                                            widget
                                                .user!
                                                .profileImageUrl!
                                                .isNotEmpty)
                                        ? NetworkImage(
                                          widget.user!.profileImageUrl!,
                                        )
                                        : null,
                                child:
                                    (widget.user?.profileImageUrl == null ||
                                            widget
                                                .user!
                                                .profileImageUrl!
                                                .isEmpty)
                                        ? Icon(
                                          Icons.person,
                                          size: 48,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.6),
                                        )
                                        : null,
                              ),
                            ),
                            // 기본 이미지로 변경
                            if (widget.onClearProfileImage != null)
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: AnimatedOpacity(
                                  opacity: _showImageActions ? 1 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: FloatingActionButton.small(
                                    heroTag: 'fab_reset_profile',
                                    backgroundColor: theme.colorScheme.surface,
                                    foregroundColor:
                                        theme.colorScheme.onSurface,
                                    onPressed:
                                        _saving
                                            ? null
                                            : () async {
                                              try {
                                                await widget
                                                    .onClearProfileImage!();
                                                if (context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        '변경 실패: $e',
                                                      ),
                                                      backgroundColor:
                                                          theme
                                                              .colorScheme
                                                              .error,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                    child: const Icon(
                                      Icons.restart_alt_rounded,
                                    ),
                                  ),
                                ),
                              ),
                            // 갤러리에서 선택
                            if (widget.onImagesSelected != null)
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: AnimatedOpacity(
                                  opacity: _showImageActions ? 1 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: FloatingActionButton.small(
                                    heroTag: 'fab_pick_profile',
                                    backgroundColor: theme.colorScheme.surface,
                                    foregroundColor:
                                        theme.colorScheme.onSurface,
                                    onPressed:
                                        _saving
                                            ? null
                                            : () async {
                                              if (!context.mounted) return;
                                              Navigator.pop(context);
                                              await showModalBottomSheet(
                                                context: context,
                                                backgroundColor:
                                                    theme.colorScheme.surface,
                                                barrierColor: Colors.black54,
                                                isScrollControlled: true,
                                                shape:
                                                    const RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.vertical(
                                                            top:
                                                                Radius.circular(
                                                                  16,
                                                                ),
                                                          ),
                                                    ),
                                                builder:
                                                    (_) => GalleryBottomSheet(
                                                      singleSelect: true,
                                                      onImagesSelected: (
                                                        files,
                                                      ) {
                                                        widget
                                                            .onImagesSelected!(
                                                          files,
                                                        );
                                                      },
                                                    ),
                                              );
                                            },
                                    child: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 별명 텍스트필드
                    TextField(
                      controller: widget.nameController,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: '별명',
                        alignLabelWithHint: true,
                        hintText: '새로운 별명을 입력하세요',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 소개글 텍스트필드
                    SizedBox(
                      height: keyboardHeight > 0 ? 120 : 200,
                      child: TextField(
                        controller: widget.descriptionController,
                        textAlign: TextAlign.center,
                        maxLines: null,
                        expands: true,
                        decoration: InputDecoration(
                          labelText: '소개글',
                          alignLabelWithHint: true,
                          hintText: '자신을 소개해보세요',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 저장 버튼
                    if (widget.onSave != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _saving
                                  ? null
                                  : () async {
                                    setState(() => _saving = true);
                                    try {
                                      await widget.onSave!(
                                        alias:
                                            widget.nameController.text.trim(),
                                        description:
                                            widget.descriptionController.text
                                                .trim(),
                                      );
                                      if (context.mounted)
                                        Navigator.pop(context);
                                    } finally {
                                      if (mounted)
                                        setState(() => _saving = false);
                                    }
                                  },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(_saving ? '저장 중...' : '저장'),
                        ),
                      ),
                    // 키보드가 올라올 때 하단 여백 추가
                    SizedBox(height: keyboardHeight > 0 ? 20 : 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
