import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';

enum ResumeWritingChoice { resume, newDraft }

/// 🎯 "이전에 작성하던 글이 있어요" 바텀시트 (ProfileActionBottomSheet 스타일)
class ResumeWritingBottomSheet extends StatefulWidget {
  final String? title;
  final String? subtitle;

  const ResumeWritingBottomSheet({super.key, this.title, this.subtitle});

  static Future<ResumeWritingChoice?> show(
    BuildContext context, {
    String? title,
    String? subtitle,
  }) {
    return showModalBottomSheet<ResumeWritingChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder:
          (context) =>
              ResumeWritingBottomSheet(title: title, subtitle: subtitle),
    );
  }

  @override
  State<ResumeWritingBottomSheet> createState() =>
      _ResumeWritingBottomSheetState();
}

class _ResumeWritingBottomSheetState extends State<ResumeWritingBottomSheet> {
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
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.t('resume_writing_title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.title?.trim().isNotEmpty == true
                          ? widget.title!.trim()
                          : l10n.t('no_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildActionItem(
                      context,
                      label: l10n.t('resume_writing_continue'),
                      textColor: theme.colorScheme.onSurface,
                      onTap: () {
                        Navigator.of(context).pop(ResumeWritingChoice.resume);
                      },
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
                      label: l10n.t('resume_writing_new'),
                      textColor: theme.colorScheme.error,
                      onTap: () {
                        Navigator.of(context).pop(ResumeWritingChoice.newDraft);
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface
                              .withOpacity(0.03),
                          foregroundColor: theme.colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          l10n.t('cancel'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
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
    required VoidCallback? onTap,
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
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
