import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum RetryCancelAction { retry, cancel }

/// ✅ 실패 UX 개선용: "다시 시도 / 취소" 바텀시트
/// - 다른 바텀시트들과 동일한 디자인(둥근 모서리 + 블러 + 드래그)
class RetryCancelBottomSheet {
  static Future<RetryCancelAction?> show(
    BuildContext context, {
    required String title,
    required String message,
    String? details,
    String retryText = '다시 시도',
    String cancelText = '취소',
  }) {
    return showModalBottomSheet<RetryCancelAction>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (bottomSheetContext) {
        final surface = Theme.of(bottomSheetContext).colorScheme.surface;
        final onSurface = Theme.of(bottomSheetContext).colorScheme.onSurface;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(bottomSheetContext).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.42,
              minChildSize: 0.32,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return GestureDetector(
                  onTap: () {},
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: surface.withOpacity(0.95),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          border: Border.all(
                            color: surface.withOpacity(0.6),
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Handle bar
                            Container(
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    message,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.35,
                                      color: onSurface.withOpacity(0.8),
                                    ),
                                  ),
                                  if (details != null &&
                                      details.trim().isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: onSurface.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: onSurface.withOpacity(0.08),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: SelectableText(
                                        details,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.35,
                                          color: onSurface.withOpacity(0.65),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: RawScrollbar(
                                controller: scrollController,
                                thumbColor: onSurface.withOpacity(0.25),
                                radius: const Radius.circular(20),
                                thickness: 4,
                                thumbVisibility: false,
                                child: SingleChildScrollView(
                                  controller: scrollController,
                                  child: Column(
                                    children: [
                                      _actionItem(
                                        context: bottomSheetContext,
                                        title: retryText,
                                        icon: Icons.refresh_rounded,
                                        emphasized: true,
                                        onTap:
                                            () => Navigator.of(
                                              bottomSheetContext,
                                            ).pop(RetryCancelAction.retry),
                                      ),
                                      _actionItem(
                                        context: bottomSheetContext,
                                        title: cancelText,
                                        icon: Icons.close_rounded,
                                        emphasized: false,
                                        onTap:
                                            () => Navigator.of(
                                              bottomSheetContext,
                                            ).pop(RetryCancelAction.cancel),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SafeArea(
                              top: false,
                              child: const SizedBox(height: 8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  static Widget _actionItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool emphasized,
    required VoidCallback onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color:
                  emphasized ? onSurface.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: onSurface.withOpacity(0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color:
                      emphasized
                          ? Theme.of(context).colorScheme.primary
                          : onSurface.withOpacity(0.65),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          emphasized ? FontWeight.w700 : FontWeight.w500,
                      color:
                          emphasized ? onSurface : onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
