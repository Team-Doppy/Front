import 'dart:io';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'native_image_picker.dart';

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
                  AppLocalizations.of(context).translate('select_from_gallery'),
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
                // 현재 시트 닫기
                Navigator.pop(context);

                // 네이티브 이미지 선택기 사용
                final picker = NativeImagePicker();
                final files =
                    singleSelect
                        ? await picker.pickSingleImage().then(
                          (f) => f != null ? [f] : <File>[],
                        )
                        : await picker.pickMultipleImages();

                if (files.isNotEmpty) {
                  onImagesSelected(files);
                }
              },
            ),
            ListTile(
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppLocalizations.of(context).translate('change_to_default'),
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
                        content: Text(
                          '${AppLocalizations.of(context).translate('change_failed')}: $e',
                        ),
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
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  late String _initialName;
  late String _initialDescription;

  @override
  void initState() {
    super.initState();
    // trim()된 값으로 초기값 저장
    _initialName = widget.nameController.text.trim();
    _initialDescription = widget.descriptionController.text.trim();
    print(
      '[ProfileEdit] 초기값 저장 - 이름: "$_initialName", 소개: "$_initialDescription"',
    );

    // Bottom Sheet 열릴 때 자동으로 별명란에 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _nameFocus.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final currentName = widget.nameController.text.trim();
    final currentDescription = widget.descriptionController.text.trim();

    final hasNameChange = currentName != _initialName;
    final hasDescChange = currentDescription != _initialDescription;

    print(
      '[ProfileEdit] 변경 체크 - 이름: "$currentName" vs "$_initialName" = $hasNameChange',
    );
    print(
      '[ProfileEdit] 변경 체크 - 소개: "$currentDescription" vs "$_initialDescription" = $hasDescChange',
    );

    // 별명이 비어있으면 변경사항이 있어도 저장 불가
    if (currentName.isEmpty) {
      return false;
    }

    return hasNameChange || hasDescChange;
  }

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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
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
                  const SizedBox(height: 20),

                  // 원형 프로필 + 액션 버튼]
                  /*
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            showModalBottomSheet(
                              context: context,
                              builder:
                                  (context) => ProfileImageBottomSheet(
                                    onClearProfileImage: () async {
                                      await widget.onClearProfileImage!();
                                    },
                                    onImagesSelected: (files) {
                                      widget.onImagesSelected!(files);
                                    },
                                  ),
                            );
                          },
                          child: CommonProfileAvatar(
                            imageUrl: widget.user?.profileImageUrl ?? '',
                            username: widget.user?.username ?? '',
                            size: 150,
                            borderWidth: 2,
                            borderColor: theme.colorScheme.onSurface,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 4,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.photo_camera,
                              color: theme.colorScheme.surface,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),*/
                  Text(
                    AppLocalizations.of(context).translate('nickname'),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  // 별명 텍스트필드
                  TextField(
                    controller: widget.nameController,
                    focusNode: _nameFocus,
                    textAlign: TextAlign.center,
                    onChanged: (value) => setState(() {}),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(
                        context,
                      ).translate('nickname_hint'),
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      errorText:
                          widget.nameController.text.trim().isEmpty
                              ? AppLocalizations.of(
                                context,
                              ).translate('nickname_required')
                              : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context).translate('introduction'),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  // 소개글 텍스트필드
                  TextField(
                    controller: widget.descriptionController,
                    focusNode: _descriptionFocus,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    onChanged: (value) => setState(() {}),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(
                        context,
                      ).translate('introduction_hint'),
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  Spacer(),

                  // 저장 버튼 (별명이 있고 변경사항이 있을 때만)
                  if (widget.onSave != null &&
                      _hasChanges &&
                      widget.nameController.text.trim().isNotEmpty)
                    _buildActionButton(
                      context: context,
                      icon: Icons.save,
                      label: AppLocalizations.of(
                        context,
                      ).translate('save_profile'),
                      onTap: () async {
                        final hasChanges = _hasChanges;
                        if (!hasChanges) return;

                        setState(() => _saving = true);

                        try {
                          await widget.onSave!(
                            alias: widget.nameController.text.trim(),
                            description:
                                widget.descriptionController.text.trim(),
                          );

                          // 저장 완료 후 잠시 대기
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );

                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          // 에러 처리
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).translate('save_error'),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onError,
                                  ),
                                ),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                    ),
                  // 키보드가 올라올 때 하단 여백 추가
                  SizedBox(height: keyboardHeight > 0 ? keyboardHeight : 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final hasChanges = _hasChanges;

    return Container(
      height: 55,
      decoration: BoxDecoration(
        color:
            hasChanges
                ? theme.colorScheme.onSurface
                : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving ? null : onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_saving) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _saving ? '' : label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
