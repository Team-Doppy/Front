import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import '../../editor/service/draft_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/service/post_export_service.dart';
import '../../editor/style/text_styling_service.dart';
import '../../editor/config/emum_config.dart';

/// PostwriteScreen의 auto-save 관련 기능을 분리한 mixin
mixin PostwriteScreenAutoSave<T extends StatefulWidget> on State<T> {
  // Required getters - State 클래스에서 제공해야 함
  bool get mounted;
  BuildContext get context;
  Timer? get autoSaveTimer;
  EditorService get editorService;
  DraftService get draftService;
  NodeComponentService get nodeComponentService;
  TextStylingService get textStylingService;
  String? get currentDraftId;
  Duration? get autoSaveInterval;
  bool get enableAutoSave;

  // Required setters
  set autoSaveTimer(Timer? value);
  set currentDraftId(String? value);

  /// 자동 저장 시작
  void startAutoSave() {
    autoSaveTimer?.cancel();

    final interval = autoSaveInterval;
    if (interval == null) {
      debugPrint('[AutoSave] ⏭️ 자동 저장 미시작: autoSaveInterval == null');
      return;
    }
    if (!enableAutoSave) {
      debugPrint('[AutoSave] ⏭️ 자동 저장 미시작: enableAutoSave == false');
      return;
    }

    debugPrint('[AutoSave] ▶️ 자동 저장 시작 (interval: ${interval.inSeconds}초)');
    autoSaveTimer = Timer.periodic(interval, (timer) async {
      if (!mounted || !context.mounted || !enableAutoSave) {
        timer.cancel();
        debugPrint('[AutoSave] ⏹️ 타이머 정지 (mounted/context/enable 변경)');
        return;
      }

      try {
        final route = ModalRoute.of(context);
        if (route == null || !route.isActive) {
          debugPrint('[AutoSave] ⏭️ 틱 스킵: route 비활성');
          return;
        }
      } catch (e) {
        debugPrint('[AutoSave] Route 확인 실패: $e');
        return;
      }

      if (!editorService.shouldPromptSaveOnExit(context)) {
        debugPrint('[AutoSave] ⏭️ 틱 스킵: 변경 없음 (shouldPromptSaveOnExit false)');
        return;
      }

      debugPrint('[AutoSave] 💾 자동 저장 실행 중…');
      final exported = PostExporter.exportToMap(
        forPublishing: false,
        allowPartialUpload: true,
        editorService: editorService,
        textStylingService: textStylingService,
      );

      final title = (exported['title'] as String?)?.trim() ?? '';
      final thumbnailUrl = PostContentUtils.findFirstBodyImageUrl(exported);

      final draftId = currentDraftId ??= 'draft_${Uuid().v4()}';

      await draftService.saveAutoDraft(
        editorService: editorService,
        draftId: draftId,
        title: title,
        thumbnailUrl: thumbnailUrl,
        visibility: AccessLevel.private,
        textStylingService: textStylingService,
      );

      if (mounted) {
        editorService.markSavedSnapshot();
        debugPrint('[AutoSave] ✅ 자동 저장 완료 (draftId: $draftId)');
      }
    });
  }

  /// 자동 저장 지금 실행 (나가기 직전)
  Future<void> saveAutoDraftNowIfPossible() async {
    if (!mounted || !context.mounted) return;

    // skip if no changes
    if (!editorService.shouldPromptSaveOnExit(context)) return;

    // export to map
    final exported = PostExporter.exportToMap(
      forPublishing: false,
      allowPartialUpload: true,
      editorService: editorService,
      textStylingService: textStylingService,
    );

    // extract title and thumbnail
    final title = (exported['title'] as String?)?.trim() ?? '';
    final thumbnailUrl = PostContentUtils.findFirstBodyImageUrl(exported);

    // use UUID based draftId
    final draftId = currentDraftId ??= 'draft_${Uuid().v4()}';

    // auto save (latest 1): save to auto draft list, but only keep one
    await draftService.saveAutoDraft(
      editorService: editorService,
      draftId: draftId,
      title: title,
      thumbnailUrl: thumbnailUrl,
      visibility: AccessLevel.private,
      textStylingService: textStylingService,
    );
  }
}
