import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';

enum ThumbnailEditChoice { edit, change }

/// 🎯 썸네일 편집 바텀시트 (두 옵션만 있는 깔끔한 디자인)
class ThumbnailEditBottomSheet extends StatelessWidget {
  const ThumbnailEditBottomSheet({super.key});

  static Future<ThumbnailEditChoice?> show(BuildContext context) {
    return showModalBottomSheet<ThumbnailEditChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => const ThumbnailEditBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(null),
              child: Container(color: Colors.transparent),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionItem(
                      context,
                      label: l10n.t('edit_thumbnail'),
                      textColor: theme.colorScheme.onSurface,
                      onTap:
                          () => Navigator.of(
                            context,
                          ).pop(ThumbnailEditChoice.edit),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 0,
                      endIndent: 0,
                      color: theme.colorScheme.onSurface.withOpacity(0.05),
                    ),
                    _buildActionItem(
                      context,
                      label: l10n.t('change_thumbnail'),
                      textColor: theme.colorScheme.onSurface,
                      onTap:
                          () => Navigator.of(
                            context,
                          ).pop(ThumbnailEditChoice.change),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required String label,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
