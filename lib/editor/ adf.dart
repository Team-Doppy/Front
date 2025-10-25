import 'dart:ui';

import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:flutter/material.dart';

class EditModeAppBar extends StatelessWidget {
  final EditorService editorService;
  final VoidCallback? onSave;

  const EditModeAppBar({super.key, required this.editorService, this.onSave});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background.withOpacity(1),
            ),
            height: 55,
            width: MediaQuery.of(context).size.width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 뒤로가기 버튼
                GestureDetector(
                  onTap: () async {
                    Navigator.of(context).maybePop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                      size: 20,
                    ),
                  ),
                ),
                // 수정 완료 버튼 (변경 사항이 있을 때만 표시)
                if (editorService.canProceedToPublish())
                  GestureDetector(
                    onTap: onSave,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        '수정 완료',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
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

class EditorAppBar extends StatelessWidget {
  final EditorService editorService;
  final StickerService stickerService;
  const EditorAppBar({
    super.key,
    required this.editorService,
    required this.stickerService,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background.withOpacity(1),
            ),
            height: 55,
            width: MediaQuery.of(context).size.width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 뒤로가기 버튼
                GestureDetector(
                  onTap: () async {
                    Navigator.of(context).maybePop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.8),
                      size: 20,
                    ),
                  ),
                ),

                if (editorService.canProceedToPublish())
                  GestureDetector(
                    onTap:
                        editorService.canProceedToPublish()
                            ? () {
                              NodeComponentService().selectNode(null);
                              final json = exportToJsonString(context);

                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  opaque: false,
                                  barrierDismissible: true,
                                  pageBuilder:
                                      (_, __, ___) =>
                                          PostExportScreen(exported: json),
                                ),
                              );
                            }
                            : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),

                      child: Text(
                        '다음',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
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

  String exportToJsonString(BuildContext context) {
    return PostExporter.exportToJsonString(
      editorService: editorService,
      stickerService: stickerService,
      viewportSize: MediaQuery.of(context).size,
      pretty: true,
    );
  }
}

class TopPadding extends StatelessWidget {
  const TopPadding({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.background.withOpacity(1),
          ),
        ),
      ),
    );
  }
}
