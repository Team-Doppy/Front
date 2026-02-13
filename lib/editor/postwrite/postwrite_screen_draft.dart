import 'dart:convert';
import 'package:flutter/material.dart';
import '../../editor/config/emum_config.dart';
import '../../editor/data/draft.dart';
import '../../editor/service/draft_service.dart';
import '../../editor/service/drag_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/service/post_export_service.dart';
import '../../editor/style/text_styling_service.dart';
import 'package:super_editor/super_editor.dart';
import 'package:uuid/uuid.dart';

/// PostwriteScreen의 draft 관련 기능을 분리한 mixin
mixin PostwriteScreenDraft<T extends StatefulWidget> on State<T> {
  // Required getters - State 클래스에서 제공해야 함
  bool get mounted;
  BuildContext get context;
  String? get currentDraftId;
  EditorService get editorService;
  TextStylingService get textStylingService;
  DraftData? get initialDraftData;
  DraftService get draftService;
  NodeComponentService get nodeComponentService;
  FocusNode get editorFocusNode;
  DragService get dragService;
  MutableDocumentComposer get composer;
  /// false이면 네트워크 업로드 검사 스킵(오프라인 임시저장)
  bool get networkMode;

  /// 현재 상태에서 DraftData 생성
  DraftData? getCurrentDraftData() {
    if (currentDraftId == null) return null;

    // 현재 문서에서 메타데이터 추출
    final exported = PostExporter.exportToMap(
      forPublishing: false,
      allowPartialUpload: true,
      editorService: editorService,
      textStylingService: textStylingService,
    );

    final title = (exported['title'] as String?)?.trim() ?? '';
    final thumbnailUrl = PostContentUtils.findFirstBodyImageUrl(exported);
    final content = jsonEncode(exported);

    return DraftData(
      id: currentDraftId!,
      title: title,
      content: content,
      createdAt: initialDraftData?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      visibility: initialDraftData?.visibility,
      thumbnailUrl: thumbnailUrl.isEmpty ? null : thumbnailUrl,
    );
  }

  /// 메타데이터 추출 (제목, 썸네일)
  Map<String, String> extractDraftMetadata() {
    final exported = PostExporter.exportToMap(
      forPublishing: false,
      allowPartialUpload: true,
      editorService: editorService,
      textStylingService: textStylingService,
    );
    final title = (exported['title'] as String?)?.trim() ?? '';
    final thumbnailUrl = PostContentUtils.findFirstBodyImageUrl(exported);
    return {
      'title': title,
      'thumbnailUrl': thumbnailUrl.isEmpty ? '' : thumbnailUrl,
    };
  }

  /// 수동 임시저장 실행
  ///
  /// [title] 저장할 제목 (비어있으면 자동 추출)
  /// [onDraftIdChanged] draftId 변경 콜백
  ///
  /// 반환값: 성공 시 새로운 draftId, 실패 시 null
  Future<String?> saveDraftManually({
    String? title,
    void Function(String?)? onDraftIdChanged,
  }) async {
    try {
      // 메타데이터 추출
      final metadata = extractDraftMetadata();
      final finalTitle = title ?? metadata['title']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      // UUID 생성
      String? draftId = currentDraftId;
      if (draftId == null) {
        draftId = 'draft_${Uuid().v4()}';
        onDraftIdChanged?.call(draftId);
      }

      // 자동저장에서 온 경우 확인
      final autoDraft = await draftService.getAutoDraft();
      final isFromAutoDraft = autoDraft != null && autoDraft.id == draftId;

      // 임시저장 (networkMode false면 업로드 검사 스킵)
      final newDraftId = await draftService.saveDraft(
        editorService: editorService,
        title: finalTitle,
        thumbnailUrl: thumbnailUrl,
        visibility: AccessLevel.private,
        existingDraftId: draftId,
        textStylingService: textStylingService,
        networkMode: networkMode,
      );

      if (isFromAutoDraft) {
        await draftService.clearAutoDraft();
      }

      editorService.markSavedSnapshot();

      onDraftIdChanged?.call(newDraftId);
      return newDraftId;
    } catch (e) {
      return null;
    }
  }

  /// 본문 검증 및 제목 입력 후 임시저장
  ///
  /// [onShowBodyRequiredDialog] 본문이 없을 때 다이얼로그 표시 콜백
  /// [onShowTitleInputDialog] 제목이 없을 때 입력 다이얼로그 표시 콜백 (반환: 입력된 제목 또는 null)
  /// [onDraftIdChanged] draftId 변경 콜백
  /// [onSuccess] 성공 시 콜백
  /// [onError] 실패 시 콜백
  ///
  /// 반환값: 성공 시 true, 실패 시 false
  Future<bool> saveDraftWithValidation({
    required Future<void> Function() onShowBodyRequiredDialog,
    required Future<String?> Function() onShowTitleInputDialog,
    required void Function(String?) onDraftIdChanged,
    required void Function() onSuccess,
    required void Function() onError,
  }) async {
    try {
      // 본문 검증
      final hasBody = editorService.hasNonEmptyBody(context: context);
      if (!hasBody) {
        if (mounted) {
          await onShowBodyRequiredDialog();
        }
        return false;
      }

      // 메타데이터 추출
      final metadata = extractDraftMetadata();
      String finalTitle = metadata['title']!;

      // 제목 검증 및 입력 요청
      if (finalTitle.isEmpty) {
        if (mounted) {
          final titleText = await onShowTitleInputDialog();
          if (titleText == null || titleText.trim().isEmpty) {
            return false;
          }
          finalTitle = titleText.trim();
        } else {
          return false;
        }
      }

      // 임시저장 실행
      final newDraftId = await saveDraftManually(
        title: finalTitle,
        onDraftIdChanged: onDraftIdChanged,
      );

      if (mounted) {
        if (newDraftId != null) {
          onSuccess();
        } else {
          onError();
        }
      }

      return newDraftId != null;
    } catch (e) {
      if (mounted) {
        onError();
      }
      return false;
    }
  }

  /// 드래프트 로드 후 처리
  ///
  /// [draftId] 로드할 드래프트 ID
  /// [onDraftIdChanged] draftId 변경 콜백
  /// [onError] 실패 시 콜백
  ///
  /// 반환값: 성공 시 true, 실패 시 false
  Future<bool> handleDraftLoaded({
    required String draftId,
    required void Function(String) onDraftIdChanged,
    required void Function() onError,
  }) async {
    try {
      // 선택 및 포커스 해제
      nodeComponentService.clearHighlightedSelectionSilently();
      nodeComponentService.clearSelectionSilently();
      composer.clearSelection();
      editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      // 드래프트 로드
      final draft = await draftService.loadDraft(
        draftId: draftId,
        editorService: editorService,
        nodeComponentService: nodeComponentService,
        dragService: dragService,
        textStylingService: textStylingService,
      );

      if (draft == null || !mounted) {
        if (mounted) {
          onError();
        }
        return false;
      }

      // 상태 업데이트
      onDraftIdChanged(draftId);

      // 스냅샷 마크
      editorService.markSavedSnapshot();

      // 포커스 해제
      editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      return true;
    } catch (e) {
      if (mounted) {
        onError();
      }
      return false;
    }
  }
}
