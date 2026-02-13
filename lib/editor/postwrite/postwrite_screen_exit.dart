import 'package:flutter/material.dart';
import '../../editor/service/draft_service.dart';
import '../../editor/service/drag_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/utils/dialog_util.dart';
import '../utils/editor_localization.dart';
import '../../editor/postwrite/postwrite_screen_autosave.dart';
import 'package:super_editor/super_editor.dart';

/// PostwriteScreen의 exit 관련 기능을 분리한 mixin
mixin PostwriteScreenExit<T extends StatefulWidget> on State<T> {
  // Required getters - State 클래스에서 제공해야 함
  bool get mounted;
  BuildContext get context;
  FocusNode get editorFocusNode;
  EditorService get editorService;
  DraftService get draftService;
  DragService get dragService;
  NodeComponentService get nodeComponentService;
  MutableDocumentComposer get composer;
  Future<bool> Function() get saveDraft;
  /// 수정 모드일 때 true (뒤로가기 시 "수정을 취소할까요?" 등 다른 문구 사용)
  bool get isEditMode;

  /// 키보드 닫기
  void dismissKeyboard() {
    editorFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
  }

  /// 나가기 처리 (본문/변경사항 확인)
  Future<bool> handleWillPop() async {
    final hasBodyContent = editorService.hasNonEmptyBody(context: context);
    final hasChanges = editorService.shouldPromptSaveOnExitBodyOnly(context);

    // 케이스 1: 본문 없음 → 바로 나가기
    if (!hasBodyContent) {
      await performExitEditor(
        forceAutoDraftIfChanged: false,
        clearAutoDraft: false,
      );
      return false;
    }

    // 케이스 2: 변경사항 있음 → 저장 여부 확인
    if (hasChanges) {
      return await handleExitWithChanges();
    }

    // 케이스 3: 본문 있지만 변경사항 없음 → 나가기 확인
    return await handleExitWithoutChanges();
  }

  /// 변경사항 있을 때 나가기 처리
  /// 수정 모드에서는 임시저장 없이 '나가기' / '계속 작성' 두 옵션만 표시
  Future<bool> handleExitWithChanges() async {
    if (isEditMode) {
      final shouldExit = await DialogUtils.showConfirmDialog(
        context,
        title: context.tr('editor_cancel_edit_title'),
        message: context.tr('editor_cancel_edit_message'),
        confirmText: context.tr('editor_exit'),
        cancelText: context.tr('editor_continue_writing'),
        isDestructive: false,
      );
      if (shouldExit == true) {
        dismissKeyboard();
        if (mounted) {
          await performExitEditor(
            forceAutoDraftIfChanged: false,
            clearAutoDraft: true,
          );
        }
      }
      return false;
    }

    final shouldSave = await DialogUtils.showConfirmDialog(
      context,
      title: context.tr('editor_discard_or_save_title'),
      message: context.tr('editor_discard_or_save_message'),
      confirmText: context.tr('editor_save_and_exit'),
      cancelText: context.tr('editor_discard_without_save'),
      isDestructive: false,
    );

    if (shouldSave == true) {
      final success = await saveDraft();
      if (success) {
        await performExitEditor(
          forceAutoDraftIfChanged: true,
          clearAutoDraft: false,
        );
      }
    } else if (shouldSave == false) {
      dismissKeyboard();
      if (mounted) {
        await performExitEditor(
          forceAutoDraftIfChanged: false,
          clearAutoDraft: true,
        );
      }
    }
    return false;
  }

  /// 변경사항 없을 때 나가기 처리
  Future<bool> handleExitWithoutChanges() async {
    final title = isEditMode
        ? context.tr('editor_cancel_edit_title')
        : context.tr('editor_exit_writing_title');
    final message = isEditMode
        ? context.tr('editor_cancel_edit_message')
        : context.tr('editor_exit_writing_message');
    final shouldExit = await DialogUtils.showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmText: context.tr('editor_exit'),
      cancelText: context.tr('editor_continue_writing'),
      isDestructive: false,
    );

    if (shouldExit == true) {
      dismissKeyboard();
      if (mounted) {
        await performExitEditor(
          clearAutoDraft: false,
          forceAutoDraftIfChanged: false,
        );
      }
    }
    return false;
  }

  /// 에디터 종료 처리
  Future<void> performExitEditor({
    required bool forceAutoDraftIfChanged,
    required bool clearAutoDraft,
  }) async {
    if (!mounted) return;

    // 나갈 때는 항상 키보드 먼저 내리기
    dismissKeyboard();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    final shouldClearAutoDraft = clearAutoDraft;

    if (shouldClearAutoDraft) {
      await draftService.clearAutoDraft();
    } else if (forceAutoDraftIfChanged) {
      // 타이머와 무관하게 "나가기 직전" 1회 autoDraft 저장 보장
      // PostwriteScreenAutoSave mixin의 saveAutoDraftNowIfPossible 호출
      if (this is PostwriteScreenAutoSave) {
        await (this as PostwriteScreenAutoSave).saveAutoDraftNowIfPossible();
      }
    }

    if (!mounted) return;

    try {
      dragService.endDrag();
      composer.clearSelection();
      nodeComponentService.clearAll();
    } catch (_) {}

    try {
      nodeComponentService.clearTempVideoFile('default');
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
