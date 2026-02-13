import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_editor/super_editor.dart';
import 'package:uuid/uuid.dart';
import '../../editor/component/app_image_node.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/component/divider_component.dart';
import '../../editor/component/link_component.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/config/editor_config.dart';
import '../../editor/config/emum_config.dart';
import '../../editor/data/draft.dart';
import '../../editor/service/document_restore_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/service/post_export_service.dart';
import '../../editor/style/text_styling_service.dart';
import '../../editor/utils/dialog_util.dart';
import '../../editor/utils/editor_localization.dart';
import '../../editor/widgets/resume_writing_bottom_sheet.dart';

/// 임시저장 서비스
/// DraftData 기반으로 작동하며, 문서 내용은 content 필드에 저장됩니다.
class DraftService {
  static const String _draftsKey = 'draft_posts';
  static const String _currentDraftKey = 'current_draft';
  static const String _autoDraftKey = 'auto_draft';

  /// 임시저장 저장
  ///
  /// [networkMode]가 false이면 네트워크 업로드 검사를 스킵하고 로컬 경로 그대로 저장(오프라인 임시저장).
  Future<String> saveDraft({
    required EditorService editorService,
    required String title,
    required String? thumbnailUrl,
    required AccessLevel visibility,
    String? existingDraftId,
    dynamic textStylingService,
    bool networkMode = true,
  }) async {
    try {
      if (title.trim().isEmpty) {
        throw Exception('임시저장에는 제목이 필요합니다.');
      }

      final prefs = await SharedPreferences.getInstance();
      final draftId = existingDraftId ?? _generateUuidDraftId();
      final now = DateTime.now().toUtc();

      // networkMode가 false면 업로드 검사 스킵(로컬 이미지 경로 유지)
      final content = PostExporter.exportToMap(
        editorService: editorService,
        forPublishing: networkMode,
        allowPartialUpload: !networkMode,
        textStylingService: textStylingService,
      );

      final draftData = DraftData(
        id: draftId,
        title: title.trim(),
        content: json.encode(content),
        thumbnailUrl: thumbnailUrl,
        visibility: visibility,
        createdAt: existingDraftId != null
            ? await _getDraftCreatedAt(draftId)
            : now,
        updatedAt: now,
      );

      // 기존 목록에 추가/업데이트
      final drafts = await getAllDrafts();
      final existingIndex = drafts.indexWhere((d) => d.id == draftId);
      if (existingIndex != -1) {
        drafts[existingIndex] = draftData;
      } else {
        drafts.add(draftData);
      }

      await prefs.setString(
        _draftsKey,
        json.encode(drafts.map((d) => d.toJson()).toList()),
      );
      await prefs.setString(_currentDraftKey, draftId);

      return draftId;
    } catch (e, stackTrace) {
      debugPrint('[DraftService] ❌ 임시저장 실패: $e');
      debugPrint('[DraftService] 스택 트레이스: $stackTrace');
      throw Exception('임시저장에 실패했습니다: $e');
    }
  }

  /// 자동저장 (최근 1개만 유지)
  Future<String> saveAutoDraft({
    required EditorService editorService,
    required String draftId,
    required String title,
    String? thumbnailUrl,
    required AccessLevel visibility,
    dynamic textStylingService,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc();

      // 문서 내용만 추출 (DraftData 기반)
      final content = PostExporter.exportToMap(
        editorService: editorService,
        forPublishing: true,
        allowPartialUpload: true,
        textStylingService: textStylingService,
      );

      final draftData = DraftData(
        id: draftId,
        title: title.trim(),
        content: json.encode(content),
        thumbnailUrl: thumbnailUrl,
        visibility: visibility,
        createdAt: now,
        updatedAt: now,
      );

      await prefs.setString(_autoDraftKey, json.encode(draftData.toJson()));
      debugPrint('[DraftService] ✅ 자동저장 완료 (draftId: $draftId, title: ${title.isEmpty ? "(빈 제목)" : title})');
      return draftId;
    } catch (e, stackTrace) {
      if (e is StateError && e.message.contains('업로드')) {
        return draftId;
      }
      debugPrint('[DraftService] ❌ 자동저장 실패: $e');
      debugPrint('[DraftService] 스택 트레이스: $stackTrace');
      throw Exception('자동저장에 실패했습니다: $e');
    }
  }

  /// 자동저장 가져오기
  Future<DraftData?> getAutoDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_autoDraftKey);
      if (raw == null) return null;
      final jsonMap = json.decode(raw);
      if (jsonMap is! Map<String, dynamic>) return null;
      return DraftData.fromJson(jsonMap);
    } catch (e) {
      debugPrint('[DraftService] Error getting auto draft: $e');
      return null;
    }
  }

  /// 자동저장 삭제
  Future<void> clearAutoDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_autoDraftKey);
    } catch (e) {
      debugPrint('[DraftService] Error clearing auto draft: $e');
    }
  }

  /// 모든 임시저장 목록 가져오기
  Future<List<DraftData>> getAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = prefs.getString(_draftsKey);
      if (draftsJson == null) return [];

      final List<dynamic> draftsList = json.decode(draftsJson);
      return draftsList.map((json) => DraftData.fromJson(json)).toList();
    } catch (e) {
      debugPrint('[DraftService] Error getting drafts: $e');
      return [];
    }
  }

  /// 특정 임시저장 가져오기
  Future<DraftData?> getDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = prefs.getString(_draftsKey);
      if (draftsJson == null) return null;

      final List<dynamic> draftsList = json.decode(draftsJson);
      for (final jsonData in draftsList) {
        if (jsonData is Map<String, dynamic> && jsonData['id'] == draftId) {
          return DraftData.fromJson(jsonData);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[DraftService] Error getting draft: $e');
      return null;
    }
  }

  /// 임시저장 불러오기
  Future<DraftData?> loadDraft({
    required String draftId,
    required EditorService editorService,
    NodeComponentService? nodeComponentService,
    dynamic dragService,
    dynamic textStylingService,
  }) async {
    try {
      final draft = await getDraft(draftId);
      if (draft == null) return null;

      final exportedData = json.decode(draft.content) as Map<String, dynamic>;
      final documentRestoreService = DocumentRestoreService();

      // 초기화
      editorService.editor.composer.clearSelection();
      nodeComponentService?.clearSelection();
      nodeComponentService?.clearHighlightedSelection();
      editorService.clearHistory();

      if (dragService != null) {
        (dragService as dynamic).invalidateNodeRectCache();
      }

      // 문서 복원
      final document = documentRestoreService.rebuildDocumentForRead(
        exportedData,
      );
      await _replaceDocumentSafely(editorService, document);
      editorService.registerAllSpecialNodes();
      editorService.ensureTrailingParagraphAfterLastSpecialNode();

      if (dragService != null) {
        (dragService as dynamic).invalidateNodeRectCache();
      }

      editorService.saveInitialStateSync();
      editorService.markSavedSnapshot();
      editorService.requestEditorLayoutRefresh();

      // 전역 폰트 사이즈 복원
      if (textStylingService != null) {
        try {
          final globalFontSize = exportedData['globalFontSize'];
          if (globalFontSize != null) {
            (textStylingService as dynamic).changeFontSize(
              (globalFontSize as num).toDouble(),
            );
          }
        } catch (e) {
          debugPrint('[DraftService] ⚠️ 전역 폰트 사이즈 복원 실패: $e');
        }
      }

      debugPrint('[DraftService] ✅ 임시저장 불러오기 완료');
      return draft;
    } catch (e) {
      debugPrint('[DraftService] Error loading draft: $e');
      return null;
    }
  }

  /// 빈 문서로 교체 (새 글로 작성 시 - 화면 이동 없이 에디터만 교체)
  Future<void> loadEmptyDocument({
    required EditorService editorService,
    NodeComponentService? nodeComponentService,
    dynamic dragService,
  }) async {
    final emptyDoc = MutableDocument(
      nodes: [
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(''),
          metadata: <String, dynamic>{
            'textAlign': 'left',
            EditorConfig.titleNodeMetadataKey: true,
          },
        ),
      ],
    );

    editorService.editor.composer.clearSelection();
    nodeComponentService?.clearSelection();
    nodeComponentService?.clearHighlightedSelection();
    editorService.clearHistory();

    if (dragService != null) {
      (dragService as dynamic).invalidateNodeRectCache();
    }

    await _replaceDocumentSafely(editorService, emptyDoc);
    editorService.registerAllSpecialNodes();
    editorService.ensureTrailingParagraphAfterLastSpecialNode();

    if (dragService != null) {
      (dragService as dynamic).invalidateNodeRectCache();
    }

    editorService.saveInitialStateSync();
    editorService.markSavedSnapshot();
    editorService.requestEditorLayoutRefresh();
  }

  /// 자동저장 불러오기
  Future<bool> loadAutoDraft({
    required EditorService editorService,
    NodeComponentService? nodeComponentService,
    dynamic dragService,
    dynamic textStylingService,
  }) async {
    try {
      final draft = await getAutoDraft();
      if (draft == null) return false;

      final exportedData = json.decode(draft.content) as Map<String, dynamic>;
      final documentRestoreService = DocumentRestoreService();

      editorService.editor.composer.clearSelection();
      nodeComponentService?.clearSelection();
      nodeComponentService?.clearHighlightedSelection();
      editorService.clearHistory();

      if (dragService != null) {
        (dragService as dynamic).invalidateNodeRectCache();
      }

      final document = documentRestoreService.rebuildDocumentForRead(
        exportedData,
      );
      await _replaceDocumentSafely(editorService, document);
      editorService.registerAllSpecialNodes();
      editorService.ensureTrailingParagraphAfterLastSpecialNode();

      if (dragService != null) {
        (dragService as dynamic).invalidateNodeRectCache();
      }

      editorService.saveInitialStateSync();
      editorService.markSavedSnapshot();
      editorService.requestEditorLayoutRefresh();

      // 전역 폰트 사이즈 복원
      if (textStylingService != null) {
        try {
          final globalFontSize = exportedData['globalFontSize'];
          if (globalFontSize != null) {
            (textStylingService as dynamic).changeFontSize(
              (globalFontSize as num).toDouble(),
            );
          }
        } catch (e) {
          debugPrint('[DraftService] ⚠️ 전역 폰트 사이즈 복원 실패: $e');
        }
      }

      debugPrint('[DraftService] ✅ 자동저장 불러오기 완료');
      return true;
    } catch (e) {
      debugPrint('[DraftService] Error loading auto draft: $e');
      return false;
    }
  }

  /// 안전한 문서 교체
  Future<void> _replaceDocumentSafely(
    EditorService editorService,
    MutableDocument newDocument,
  ) async {
    try {
      final currentDoc = editorService.document;

      // 현재 문서의 모든 노드 삭제
      while (currentDoc.isNotEmpty) {
        final node = currentDoc.getNodeAt(0);
        if (node != null) {
          currentDoc.deleteNode(node.id);
        } else {
          break;
        }
      }

      // 새 문서의 노드들 추가
      for (int i = 0; i < newDocument.length; i++) {
        final node = newDocument.getNodeAt(i);
        if (node != null) {
          final copiedNode = _copyNode(node);
          currentDoc.insertNodeAt(i, copiedNode);
        }
      }

      editorService.editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[DraftService] Error replacing document: $e');
      _createDefaultDocument(editorService);
    }
  }

  /// 노드 복사본 생성
  dynamic _copyNode(dynamic node) {
    if (node is ParagraphNode) {
      final copiedMetadata = Map<String, dynamic>.from(node.metadata);
      final isMention = copiedMetadata['mention'] == true;
      final AttributedText attributed = node.text.copyText(0, node.text.length);

      if (isMention && node.text.text.isNotEmpty) {
        final hasBold = attributed
            .getAttributionSpansInRange(
              attributionFilter: (attr) => attr == boldAttribution,
              range: SpanRange(0, node.text.text.length - 1),
            )
            .isNotEmpty;

        if (!hasBold) {
          attributed.addAttribution(
            boldAttribution,
            SpanRange(0, node.text.text.length - 1),
          );
        }
      }

      return ParagraphNode(
        id: node.id,
        text: attributed,
        metadata: copiedMetadata,
      );
    }
    if (node is ImageNode) {
      return AppImageNode(
        id: node.id,
        imageUrl: node.imageUrl,
        altText: node.altText,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ImageRowNode) {
      return ImageRowNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        spacing: node.spacing,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ClipNode) {
      return ClipNode(
        id: node.id,
        url: node.url,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
        label: node.label,
        colorHex: node.colorHex,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is LinkNode) {
      return LinkNode(
        id: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
      );
    }
    if (node is DividerNode) {
      return DividerNode(id: node.id);
    }
    if (node is PageViewImageNode) {
      return PageViewImageNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    return node;
  }

  /// 기본 문서 생성 (복구용)
  void _createDefaultDocument(EditorService editorService) {
    try {
      final currentDoc = editorService.document;

      for (int i = currentDoc.length - 1; i >= 0; i--) {
        final node = currentDoc.getNodeAt(i);
        if (node != null) {
          currentDoc.deleteNode(node.id);
        }
      }

      currentDoc.insertNodeAt(
        0,
        ParagraphNode(
          id: '1',
          text: AttributedText(''),
          metadata: {
            'textAlign': 'left',
            EditorConfig.titleNodeMetadataKey: true,
          },
        ),
      );

      currentDoc.insertNodeAt(
        1,
        ParagraphNode(
          id: '2',
          text: AttributedText(''),
          metadata: {'textAlign': 'left'},
        ),
      );
    } catch (e) {
      debugPrint('[DraftService] Error creating default document: $e');
    }
  }

  /// 임시저장 삭제
  Future<bool> deleteDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await getAllDrafts();
      drafts.removeWhere((draft) => draft.id == draftId);

      await prefs.setString(
        _draftsKey,
        json.encode(drafts.map((d) => d.toJson()).toList()),
      );

      final currentDraftId = prefs.getString(_currentDraftKey);
      if (currentDraftId == draftId) {
        await prefs.remove(_currentDraftKey);
      }

      return true;
    } catch (e) {
      debugPrint('[DraftService] Error deleting draft: $e');
      return false;
    }
  }

  /// 모든 임시저장 삭제
  Future<bool> deleteAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftsKey);
      await prefs.remove(_currentDraftKey);
      await prefs.remove(_autoDraftKey);
      return true;
    } catch (e) {
      debugPrint('[DraftService] Error deleting all drafts: $e');
      return false;
    }
  }

  /// 현재 임시저장 ID 가져오기
  Future<String?> getCurrentDraftId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_currentDraftKey);
    } catch (e) {
      debugPrint('[DraftService] Error getting current draft ID: $e');
      return null;
    }
  }

  /// 임시저장 생성 시간 가져오기
  Future<DateTime> _getDraftCreatedAt(String draftId) async {
    try {
      final draft = await getDraft(draftId);
      return draft?.createdAt ?? DateTime.now().toUtc();
    } catch (e) {
      return DateTime.now().toUtc();
    }
  }

  /// 임시저장 ID 생성
  String _generateUuidDraftId() {
    const uuid = Uuid();
    return 'draft_${uuid.v4()}';
  }
}

/// 임시저장 관리 클래스
class DraftManager {
  final DraftService _draftService;
  String? _currentDraftId;
  String? _draftTitleOverride;
  String? _draftThumbnailOverride;
  bool _didExplicitDraftSave = false;
  bool _didPromptResumeWriting = false;
  Timer? _autoSaveTimer;
  bool _isAutoSaving = false;
  bool _isSavingAutoDraft = false;

  DraftManager(this._draftService);

  String? get currentDraftId => _currentDraftId;
  String? get draftTitleOverride => _draftTitleOverride;
  String? get draftThumbnailOverride => _draftThumbnailOverride;
  bool get didExplicitDraftSave => _didExplicitDraftSave;
  bool get isAutoSaving => _isAutoSaving;
  bool get isSavingAutoDraft => _isSavingAutoDraft;

  set currentDraftId(String? value) => _currentDraftId = value;
  set draftTitleOverride(String? value) => _draftTitleOverride = value;
  set draftThumbnailOverride(String? value) => _draftThumbnailOverride = value;
  set didExplicitDraftSave(bool value) => _didExplicitDraftSave = value;

  /// 드래프트 메타데이터 추출
  Map<String, dynamic> extractDraftMetadata({
    required EditorService editorService,
    required BuildContext context,
  }) {
    final title = _draftTitleOverride ?? '';
    final thumbnailUrl =
        _draftThumbnailOverride ?? _findFirstImageUrl(editorService) ?? '';

    return {'title': title, 'thumbnailUrl': thumbnailUrl};
  }

  /// 드래프트 메타데이터 복원
  void restoreDraftMetadata({
    required String? title,
    required String? thumbnailUrl,
  }) {
    _draftTitleOverride = title;
    _draftThumbnailOverride = thumbnailUrl;
  }

  /// 문서에서 첫 번째 이미지 URL 찾기
  String? _findFirstImageUrl(EditorService editorService) {
    try {
      final doc = editorService.document;
      for (int i = 0; i < doc.nodeCount; i++) {
        final node = doc.getNodeAt(i);

        if (node is ImageNode) {
          final url = node.imageUrl;
          if (url.isNotEmpty &&
              (url.startsWith('http://') || url.startsWith('https://'))) {
            return url;
          }
        }

        if (node is ImageRowNode) {
          if (node.imageUrls.isNotEmpty) {
            final url = node.imageUrls.first;
            if (url.isNotEmpty &&
                (url.startsWith('http://') || url.startsWith('https://'))) {
              return url;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DraftManager] 이미지 찾기 실패: $e');
    }
    return null;
  }

  /// 자동 저장 시작
  void startAutoSave({
    required bool isEditingMode,
    required Duration? interval,
    required VoidCallback onAutoSave,
  }) {
    if (isEditingMode || interval == null) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(interval, (timer) {
      onAutoSave();
    });
  }

  /// 자동 저장 중지
  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// 자동 드래프트 저장 (즉시)
  Future<void> saveAutoDraftNowIfPossible({
    required bool mounted,
    required bool isEditingMode,
    required EditorService editorService,
    required NodeComponentService nodeComponentService,
    required TextStylingService textStylingService,
    required BuildContext context,
  }) async {
    if (!mounted || isEditingMode) return;
    if (_isSavingAutoDraft || _isAutoSaving) return;

    final hasAnyContent =
        editorService.hasNonEmptyTitle() ||
        editorService.hasNonEmptyBody(context: context);
    if (!hasAnyContent) return;

    try {
      _isSavingAutoDraft = true;

      if (_currentDraftId == null || _currentDraftId!.trim().isEmpty) {
        const uuid = Uuid();
        _currentDraftId = 'draft_${uuid.v4()}';
      }

      final metadata = extractDraftMetadata(
        editorService: editorService,
        context: context,
      );
      final title = metadata['title']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      await _draftService.saveAutoDraft(
        editorService: editorService,
        draftId: _currentDraftId!,
        title: title.trim(),
        thumbnailUrl: thumbnailUrl,
        visibility: AccessLevel.public,
        textStylingService: textStylingService,
      );
    } finally {
      _isSavingAutoDraft = false;
    }
  }

  /// 자동 저장 실행
  Future<void> autoSave({
    required bool mounted,
    required bool contextMounted,
    required bool isEditingMode,
    required EditorService editorService,
    required NodeComponentService nodeComponentService,
    required TextStylingService textStylingService,
    required BuildContext context,
    required Function(bool) setIsAutoSaving,
  }) async {
    if (!mounted || !contextMounted) return;
    if (_isAutoSaving) return;

    try {
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) {
        debugPrint('[DraftManager] ⏭️ 자동 저장 스킵 (화면 비활성화 상태)');
        return;
      }
    } catch (e) {
      debugPrint('[DraftManager] Route 확인 실패 (무시): $e');
    }

    if (!editorService.shouldPromptSaveOnExit(context)) return;

    setIsAutoSaving(true);
    _isAutoSaving = true;

    try {
      final metadata = extractDraftMetadata(
        editorService: editorService,
        context: context,
      );
      final title = metadata['title']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      if (_currentDraftId == null) {
        const uuid = Uuid();
        _currentDraftId = 'draft_${uuid.v4()}';
      }

      await _draftService.saveAutoDraft(
        editorService: editorService,
        draftId: _currentDraftId!,
        title: title,
        thumbnailUrl: thumbnailUrl,
        visibility: AccessLevel.public,
        textStylingService: textStylingService,
      );

      debugPrint('[DraftManager] ✅ 자동 저장 완료: $title');
    } catch (e) {
      if (e is StateError && e.message.contains('업로드')) {
        debugPrint('[DraftManager] ⏭️ 자동 저장 스킵 (업로드 중): ${e.message}');
      } else {
        debugPrint('[DraftManager] ⚠️ 자동 저장 실패: $e');
      }
    } finally {
      if (mounted) {
        setIsAutoSaving(false);
        _isAutoSaving = false;
      }
    }
  }

  /// 이어 작성 프롬프트
  Future<bool> promptResumeWritingIfNeeded({
    required bool mounted,
    required bool isEditingMode,
    required BuildContext context,
    required EditorService editorService,
    required NodeComponentService nodeComponentService,
    required dynamic dragService,
    required TextStylingService textStylingService,
    required Function(String?) setCurrentDraftId,
    required Function(String?, String?) restoreDraftMetadata,
  }) async {
    if (!mounted || isEditingMode) return false;
    if (_didPromptResumeWriting) return false;
    _didPromptResumeWriting = true;

    var didShowSheet = false;
    try {
      final autoDraft = await _draftService.getAutoDraft();
      if (!mounted || autoDraft == null) return false;
      didShowSheet = true;

      FocusManager.instance.primaryFocus?.unfocus();

      // 간단한 시간 포맷팅
      final timeAgo = _formatRelativeTime(autoDraft.updatedAt);

      final choice = await ResumeWritingBottomSheet.show(
        context,
        title: autoDraft.title,
        subtitle: timeAgo,
      );
      if (!mounted) return true;
      if (choice == null) return true;

      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.3),
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        if (choice == ResumeWritingChoice.resume) {
          final ok = await _draftService.loadAutoDraft(
            editorService: editorService,
            nodeComponentService: nodeComponentService,
            dragService: dragService,
            textStylingService: textStylingService,
          );
          if (!mounted) return true;
          if (ok) {
            setCurrentDraftId(autoDraft.id);
            restoreDraftMetadata(autoDraft.title, autoDraft.thumbnailUrl);
          }
        } else if (choice == ResumeWritingChoice.newDraft) {
          await _draftService.clearAutoDraft();
        }
      } finally {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('[DraftManager] resume writing prompt 실패(무시): $e');
    }
    return didShowSheet;
  }

  /// 상대 시간 포맷팅
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  /// 수동 임시저장
  Future<bool> saveDraft({
    required bool mounted,
    required BuildContext context,
    required EditorService editorService,
    required NodeComponentService nodeComponentService,
    required TextStylingService textStylingService,
    required Function(String?) setCurrentDraftId,
    required Function(String) showInfo,
    required Function(String) showError,
    required Future<String?> Function() showTitleInputDialog,
  }) async {
    try {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
      }

      final hasBody = editorService.hasNonEmptyBody(context: context);
      if (!hasBody) {
        if (mounted) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('editor_content_required'),
            message: context.tr('editor_body_required'),
          );
        }
        return false;
      }

      final titleMetadata = extractDraftMetadata(
        editorService: editorService,
        context: context,
      );
      final currentTitle = titleMetadata['title']!;

      if (currentTitle.trim().isEmpty) {
        if (mounted) {
          final titleText = await showTitleInputDialog();
          if (titleText == null || titleText.trim().isEmpty) {
            return false;
          }
          _draftTitleOverride = titleText.trim();
        } else {
          return false;
        }
      }

      final metadata = extractDraftMetadata(
        editorService: editorService,
        context: context,
      );
      final title = metadata['title']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      if (_currentDraftId == null) {
        const uuid = Uuid();
        _currentDraftId = 'draft_${uuid.v4()}';
      }

      final autoDraft = await _draftService.getAutoDraft();
      final bool isFromAutoDraft =
          autoDraft != null &&
          _currentDraftId != null &&
          autoDraft.id == _currentDraftId;

      _currentDraftId = await _draftService.saveDraft(
        editorService: editorService,
        title: title,
        thumbnailUrl: thumbnailUrl,
        visibility: AccessLevel.private,
        existingDraftId: _currentDraftId,
        textStylingService: textStylingService,
      );

      if (isFromAutoDraft) {
        await _draftService.clearAutoDraft();
      }

      editorService.markSavedSnapshot();
      _didExplicitDraftSave = true;

      if (mounted) {
        showInfo(context.tr('editor_draft_saved'));
      }

      return true;
    } catch (e) {
      if (mounted) {
        showError(context.tr('editor_draft_save_failed'));
      }
      return false;
    }
  }

  /// 에디터 종료 시 처리
  Future<void> exitEditor({
    required bool forceAutoDraftIfChanged,
    required bool clearAutoDraft,
    required EditorService editorService,
    required bool shouldPromptSaveOnExit,
  }) async {
    final shouldClearAutoDraft = clearAutoDraft || _didExplicitDraftSave;

    if (shouldClearAutoDraft) {
      await _draftService.clearAutoDraft();
    }
  }

  /// 정리
  void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }
}
