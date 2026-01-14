import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:doppy/editor/editor_appbar.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show ClipNode, ClipComponentBuilder, cleanupAllVideoPlayers;

import 'package:doppy/editor/style/selected_toolbar.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/overlay/mention_overlay.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:doppy/editor/overlay/selection_box_caret_overlay.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:doppy/editor/service/content_change_detector.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/style/text_styling_service.dart';
import 'package:doppy/editor/writer_sticker_canvas.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/draft_list_overlay.dart';
import 'package:doppy/editor/overlay/resume_writing_bottom_sheet.dart';
import 'package:doppy/editor/overlay/thumbnail_edit_overlay.dart';
import 'package:doppy/editor/overlay/empty_editor_state.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/utils/mentioned_usernames_extractor.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/pages/components/retry_cancel_bottom_sheet.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType {
  paragraph,
  image,
  imageRow,
  pageViewImage,
  location,
  mention,
  unknown,
}

class PostwriteScreen extends StatefulWidget {
  final bool isEditingMode;
  final Map<String, dynamic>? exportedDataForEdit;
  final String? postId; // 수정 모드용 post ID

  const PostwriteScreen({
    super.key,
    this.isEditingMode = false,
    this.exportedDataForEdit,
    this.postId,
  });

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen> {
  //super_editor
  late final Editor editor;
  late final MutableDocument document;
  late final MutableDocumentComposer composer;
  late final FocusNode _editorFocusNode;

  //service
  late final EditorService editorService;
  late final StickerService stickerService;
  late final NodeComponentService nodeComponentService;
  late final DragService dragService;
  late final DraftService draftService;
  late final TextStylingService textStylingService;

  //overlay
  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();

  /// 드래그 오버레이 좌표 변환을 위해 Scaffold body의 Stack 좌표계를 정확히 참조한다.
  final GlobalKey _editorBodyStackKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  //manipulation
  ScrollController scrollController = ScrollController();

  //keyboard
  // 🎯 성능 최적화: isKeyboardVisible은 build에서 MediaQuery로 직접 읽음
  String? currentDraftId; // 🎯 UUID 기반 임시저장 ID (글쓰기 시작 시 생성)

  // 영상 업로드 인디케이터 상태
  final ValueNotifier<bool> _videoUploadIndicatorNotifier = ValueNotifier<bool>(
    false,
  );

  // 🎯 빈 상태 감지 (키보드가 내려가고 문서가 비어있을 때)
  // ✅ derived state로 관리: build()에서 매번 계산하여 동기화
  final ValueNotifier<bool> _isEmptyNotifier = ValueNotifier<bool>(false);

  // 🎯 초기 진입 시 키보드가 올라오기 전까지 오버레이 숨김
  bool _isInitialEntry = true;

  // ✅ 업로드/압축 “세션(refId)” (드로잉 업로드 등 노드 id가 없는 작업을 refId 기반으로 가드하기 위함)
  late final String _editorUploadSessionId;

  // 공개범위 설정 (편집 모드용)
  String _editVisibility = 'public';
  List<int> _editGroupIds = [];

  // 서버에 적용된 제목 (썸네일 오버레이에서 변경 시 업데이트)
  String? _serverAppliedTitle;
  // 서버에 적용된 요약 (썸네일 오버레이에서 변경 시 업데이트)
  String? _serverAppliedSummary;
  // 서버에 적용된 썸네일 URL (썸네일 오버레이에서 변경 시 업데이트)
  String? _serverAppliedThumbnailUrl;

  // 저장 중 상태
  bool _isSaving = false;
  bool _isAutoSaving = false; // 자동 저장 중 상태
  Timer? _autoSaveTimer; // 자동 저장 타이머
  bool _didExplicitDraftSave = false; // ✅ "명시적 임시저장" 완료 여부 (autoDraft는 제외)
  bool _shouldRefreshMyFeed = false; // 수정사항 발생 시 한 번만 새로고침
  bool _categoryChanged = false; // 카테고리 변경 여부
  bool _didPromptResumeWriting = false; // ✅ 최초 진입 시 "이어 작성" 바텀시트 1회만

  // ✅ 다음(썸네일 편집)에서 편집한 메타데이터를 임시저장에 반영하기 위한 오버라이드
  String? _draftTitleOverride;
  String? _draftSummaryOverride;
  String? _draftThumbnailOverride;

  /// 🎯 메타데이터 복원 헬퍼 (중복 제거)
  void _restoreDraftMetadata({
    required String? title,
    required String? summary,
    required String? thumbnailUrl,
  }) {
    setState(() {
      _draftTitleOverride =
          (title?.trim().isNotEmpty ?? false) ? title!.trim() : null;
      _draftSummaryOverride =
          (summary?.trim().isNotEmpty ?? false) ? summary!.trim() : null;
      _draftThumbnailOverride =
          (thumbnailUrl?.trim().isNotEmpty ?? false)
              ? thumbnailUrl!.trim()
              : null;
    });
  }

  /// 🎯 메타데이터 추출 헬퍼 (중복 제거)
  Map<String, String> _extractDraftMetadata() {
    final title =
        (_draftTitleOverride?.trim().isNotEmpty ?? false)
            ? _draftTitleOverride!.trim()
            : '';
    final summary =
        (_draftSummaryOverride?.trim().isNotEmpty ?? false)
            ? _draftSummaryOverride!.trim()
            : '';
    String thumbnailUrl =
        (_draftThumbnailOverride?.trim().isNotEmpty ?? false)
            ? _draftThumbnailOverride!.trim()
            : '';
    if (thumbnailUrl.isEmpty) {
      final firstImageUrl = _findFirstImageUrl();
      if (firstImageUrl != null && firstImageUrl.isNotEmpty) {
        thumbnailUrl = firstImageUrl;
      }
    }
    return {'title': title, 'summary': summary, 'thumbnailUrl': thumbnailUrl};
  }

  bool _isSavingAutoDraft = false; // ✅ 메타데이터 변경 등으로 연속 저장 시 중복 방지

  Future<void> _saveAutoDraftNowIfPossible() async {
    if (!mounted || widget.isEditingMode) return;
    if (_isSavingAutoDraft || _isAutoSaving || _isSaving) return;

    // 본문이 전혀 없으면 autoDraft를 만들 필요 없음
    final hasAnyContent =
        editorService.hasNonEmptyTitle() ||
        editorService.hasNonEmptyBody(context: context);
    if (!hasAnyContent) return;

    // ✅ 업로드 중이어도 autoDraft 저장은 허용한다.
    // - Step1(썸네일/요약/제목) 편집값이 업로드/압축 타이밍 때문에 날아가는 문제 방지
    // - DraftService.saveAutoDraft는 allowPartialUpload=true로 저장 가능

    try {
      _isSavingAutoDraft = true;

      // draftId 보장
      if (currentDraftId == null || currentDraftId!.trim().isEmpty) {
        const uuid = Uuid();
        currentDraftId = 'draft_${uuid.v4()}';
      }

      final sessionKey = currentDraftId!;
      final videoFilePath = nodeComponentService.getTempVideoFilePath(
        sessionKey,
      );
      final videoThumbnailPath = nodeComponentService.getTempVideoThumbnailPath(
        sessionKey,
      );

      // ✅ 정책: 제목은 "임시저장/Step1 입력"이 아니면 본문에서 추출하지 않는다.
      final metadata = _extractDraftMetadata();
      final title = metadata['title']!;
      final summary = metadata['summary']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      await draftService.saveAutoDraft(
        editorService: editorService,
        stickerService: stickerService,
        draftId: currentDraftId!,
        title: title.trim(), // 🎯 빈 문자열이면 ''로 저장, 제목이 있으면 유지
        summary: summary,
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
        visibility: 'public',
        selectedGroupIds: [],
        textStylingService: textStylingService,
      );
    } finally {
      _isSavingAutoDraft = false;
    }
  }

  // 🎯 제목 변경 감지용 (수정 완료 버튼에서 체크)

  // 🎯 Frame-coalescing: 구조 변경 처리를 프레임당 1회로 제한
  bool _structureChangeScheduled = false;

  // 🎯 성능 최적화: keyboardVisibleNotifier를 한 번만 생성하고 값만 갱신
  late final ValueNotifier<bool> _keyboardVisibleNotifier;

  @override
  void initState() {
    super.initState();

    // 편집 모드이면 전달된 exportedDataForEdit를 기반으로 문서를 복원
    // 새 글 작성 모드이면 빈 문서 생성
    if (widget.isEditingMode && widget.exportedDataForEdit != null) {
      try {
        debugPrint('[PostwriteScreen] initState: 문서 복원 시작');
        debugPrint(
          '  - exportedDataForEdit의 content.nodes: ${((widget.exportedDataForEdit!['content'] as Map?)?['nodes'] as List?)?.length ?? 0}개',
        );

        // PostReaderService를 사용하여 문서 복원
        final postReaderService = PostReaderService();
        document = postReaderService.rebuildDocumentForRead(
          widget.exportedDataForEdit!,
        );

        debugPrint(
          '[PostwriteScreen] initState: 문서 복원 완료 (nodes: ${document.length}개)',
        );

        // 기존 공개범위 정보 복원
        final metadata =
            widget.exportedDataForEdit!['metadata'] as Map<String, dynamic>?;
        if (metadata != null) {
          final rawVis = (metadata['visibility'] ?? 'PUBLIC').toString();
          final visUpper = rawVis.toUpperCase();
          if (visUpper == 'PRIVATE') {
            _editVisibility = 'private';
            _editGroupIds = [];
          } else if (visUpper == 'GROUPS' || visUpper == 'PARTIAL') {
            _editVisibility = 'partial';
            final groupIds = metadata['groupIds'] as List<dynamic>?;
            _editGroupIds =
                groupIds?.map((e) => (e as num).toInt()).toList() ?? [];
          } else {
            _editVisibility = 'public';
            _editGroupIds = [];
          }
        }

        // 🎯 편집 모드: 초기 제목 설정 (수정 완료 버튼에서 변경 체크용)
        // 제목은 썸네일 편집 화면에서 입력하므로 여기서는 처리하지 않음
      } catch (e) {
        // 실패 시 빈 문서로 초기화
        document = MutableDocument(
          nodes: [
            ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
          ],
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final translatedText = context.tr('load_failed');
            debugPrint(
              '[PostwriteScreen] 번역 테스트: load_failed = "$translatedText"',
            );
            ErrorHandler.showError(context, translatedText);
          }
        });
      }
    } else {
      debugPrint('🔄 새 글 작성 모드');
      // 새 글 작성 모드 - 빈 문서 생성
      document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: '2',
            text: AttributedText(''),
            metadata: {'textAlign': 'center'},
          ),
        ],
      );
    }
    composer = MutableDocumentComposer();

    // FocusNode 초기화
    _editorFocusNode = FocusNode(debugLabel: 'editor_focus');

    // 🎯 keyboardVisibleNotifier 초기화 (한 번만 생성)
    _keyboardVisibleNotifier = ValueNotifier<bool>(false);

    // 🎯 성능 최적화: 포커스 상태는 MediaQuery로 자동 감지되므로
    // 별도 리스너 없이 build에서 직접 읽어서 사용
    // (키보드 높이 변화는 AnimatedPadding이 자동 처리)

    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(
      editor: editor,
      document: document,
      useExternalTitleField: true,
    );
    // ✅ 한 번만 고정 (screen lifecycle 동안 동일)
    _editorUploadSessionId = 'editor_${editorService.hashCode}';
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    editorService.setScrollController(scrollController);
    textStylingService = TextStylingService(editor: editor, composer: composer);
    // 🎯 히스토리 저장을 위해 EditorService 참조 설정
    textStylingService.setEditorService(editorService);

    //service 초기화2

    stickerService = StickerService();
    nodeComponentService = NodeComponentService();

    // 전역 스타일링 서비스 설정 (렌더링용)
    setGlobalTextStylingService(textStylingService);

    // ImageService는 build 메서드에서 설정
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    dragService.attachScrollController(scrollController);

    // 임시저장 서비스 초기화
    draftService = DraftService();

    // 🎯 새 글 작성 모드: UUID 기반 draftId 생성
    if (!widget.isEditingMode) {
      const uuid = Uuid();
      currentDraftId = 'draft_${uuid.v4()}';
      debugPrint('[PostwriteScreen] 🆔 UUID 기반 draftId 생성: $currentDraftId');
    }

    // 문서 변경 시 다음 버튼 상태 업데이트
    editorService.addListener(_onEditorServiceChange);

    // 🎯 document listener 추가: 노드 구조 변경만 감지 (텍스트 입력은 skip)
    document.addListener(_onDocumentStructureChanged);

    // 폰트 변경 감지
    textStylingService.addListener(_onEditorServiceChange);

    // 스티커(그리기 포함) 변경 감지
    stickerService.addListener(_onEditorServiceChange);
    stickerService.addListener(_onStickerHistoryChange);

    // 🎯 자동 저장 시작 (편집 모드가 아닐 때만)
    if (!widget.isEditingMode) {
      _startAutoSave();
    }

    // 🎯 노드 선택 변경 감지: 노드가 선택되면 키보드 내리기
    nodeComponentService.addListener(_onNodeSelectionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 편집 모드일 때 스티커 복원
      if (widget.isEditingMode && widget.exportedDataForEdit != null) {
        try {
          final postReaderService = PostReaderService();
          postReaderService.restoreStickers(
            exported: widget.exportedDataForEdit!,
            stickerService: stickerService,
          );
        } catch (e) {
          debugPrint('[PostwriteScreen] 스티커 복원 실패: $e');
        }
      }

      // ✅ 새 글 작성 모드: 자동저장(최근 1개)이 있으면 "이어 작성/새 글" 바텀시트로 선택하게 한다.
      // (자동 복원 금지)
      () async {
        if (!mounted) return;

        // ✅ "작성하던 글이 있어요" 바텀시트를 띄운 경우,
        // 바텀시트 dismiss 애니메이션이 완전히 끝난 뒤에 키보드 포커스를 주기 위해
        // 약간의 여유 시간을 둔다 (안정화 목적).
        Future<void> delayFocusAfterBottomSheetDismiss() async {
          // 다음 프레임까지 대기 (route transition 정리)
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return; // 뒤로가기로 나갔는지 체크
          // dismiss 애니메이션 + 레이아웃 안정화 여유
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted) return; // 지연 중 뒤로가기로 나갔는지 체크
        }

        if (!widget.isEditingMode) {
          final didShowResumeSheet = await _promptResumeWritingIfNeeded();
          if (didShowResumeSheet) {
            await delayFocusAfterBottomSheetDismiss();
            if (!mounted) return;
          }
        }

        // ✅ 0번 노드=제목 가정 제거:
        // 첫 진입 포커스는 "첫 번째 편집 가능한 문단"을 찾아 커서를 둔다.
        ParagraphNode? targetNode;

        targetNode ??=
            document.getNodeAt(0) is ParagraphNode
                ? document.getNodeAt(0) as ParagraphNode
                : null;

        if (targetNode != null) {
          if (!mounted) return; // 지연 중 뒤로가기로 나갔는지 체크
          final offset = targetNode.text.text.length;
          composer.setSelectionWithReason(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: targetNode.id,
                nodePosition: TextNodePosition(offset: offset),
              ),
            ),
            SelectionReason.userInteraction,
          );
          if (!mounted) return; // 키보드 올라오기 전 뒤로가기 체크
          _editorFocusNode.requestFocus();
        }

        try {
          // 최초 진입 스냅샷 마크(현재 상태를 저장 기준으로 간주)
          editorService.markSavedSnapshot();
          stickerService.saveInitialState();
        } catch (_) {}
      }();

      // 스크롤 리스너 추가

      // 🎯 폰트 미리 로드 시작 (백그라운드에서 병렬 처리)
      _preloadFonts();
    });
  }

  /// 폰트 미리 로드 (에디터 초기화 시 백그라운드에서 실행)
  Future<void> _preloadFonts() async {
    try {
      // 폰트 프리로드는 폰트 선택 시에만 수행 (필요할 때만 로드)
    } catch (e) {
      debugPrint('[PostwriteScreen] 초기화 실패 (무시): $e');
    }
  }

  // 🎯 document 구조 변경 감지 (텍스트 입력은 skip)
  void _onDocumentStructureChanged(DocumentChangeLog changeLog) {
    if (!mounted) return;

    final change = changeLog.changes[0];
    // 🎯 노드 구조 변경 시에만 처리 (텍스트 입력은 skip)
    if (change is NodeInsertedEvent ||
        change is NodeRemovedEvent ||
        change is NodeChangeEvent ||
        change is NodeMovedEvent) {
      // 🎯 Frame-coalescing: 이미 예약되어 있으면 스킵 (프레임당 1회만 처리)
      if (_structureChangeScheduled) return;

      _structureChangeScheduled = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _structureChangeScheduled = false;
        if (!mounted) return;

        dragService.invalidateNodeRectCache();
        // 🎯 드래그 중이 아닐 때 선택 해제 확인
        if (dragService.draggingNodeId == null) {
          final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
          final hasFocus = _editorFocusNode.hasFocus;
          // 텍스트 입력 중이 아니면 선택 해제
          if (!keyboardVisible && !hasFocus) {
            final nodeService = context.read<NodeComponentService>();
            nodeService.clearSelection();
            nodeService.clearHighlightedSelection();
          }
        }

        // (빈 상태는 build()에서 derived state로 동기화하므로 별도 체크 불필요)
      });
    }
  }

  void _onEditorServiceChange() {
    if (!mounted || !context.mounted) return;
    // ✅ autoDraft는 "저장됨"으로 치지 않는다.
    // ✅ 단, 사용자가 "명시적 임시저장"을 해둔 상태에서 다시 변경이 생기면 플래그 해제.
    if (_didExplicitDraftSave) {
      try {
        if (editorService.shouldPromptSaveOnExit(context)) {
          _didExplicitDraftSave = false;
        }
      } catch (_) {}
    }
    // 🎯 SuperEditor가 build에서 직접 생성되므로 언두/리두 후 자동 rebuild됨
    // 명시적 레이아웃 무효화 불필요
    setState(() {});
  }

  /// 🎯 문서가 비어있는지 확인
  /// ✅ 최적화: 빠른 실패를 위해 가벼운 체크를 먼저 수행
  bool _isDocumentEmpty() {
    // 1. 스티커 체크 (가장 빠른 체크)
    if (stickerService.stickers.isNotEmpty) return false;

    // 2. 문서 노드 체크
    // ✅ 최적화: 노드가 없으면 즉시 true 반환
    if (document.length == 0) return true;

    // ✅ 최적화: 노드를 순회하면서 빠른 실패
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;

      if (node is ParagraphNode) {
        // 빈 문단이 아니면 비어있지 않음 (빠른 실패)
        if (node.text.text.trim().isNotEmpty) return false;
      } else {
        // 이미지, divider 등 특수 노드가 있으면 비어있지 않음 (즉시 실패)
        return false;
      }
    }

    // 모든 노드가 빈 ParagraphNode인 경우
    return true;
  }

  // 🎯 스티커(드로잉) 추가/삭제는 EditorService 히스토리에 기록해야 한다.
  // - 이동/변형(transform)은 히스토리에 쌓지 않음 (스택 오염 방지)
  void _onStickerHistoryChange() {
    if (!mounted) return;
    // undo/redo 복원 과정에서 발생한 notify는 히스토리 재저장을 트리거하면 안 됨
    if (stickerService.isRestoringFromHistory) return;

    final kind = stickerService.lastChangeKind;
    if (kind == StickerChangeKind.add ||
        kind == StickerChangeKind.remove ||
        kind == StickerChangeKind.clear ||
        kind == StickerChangeKind.transform) {
      editorService.saveHistoryNow();

      // (빈 상태는 build()에서 derived state로 동기화하므로 별도 토글 불필요)
    }
  }

  // 🎯 노드 선택 변경 리스너: 노드가 선택되면 키보드 내리기
  void _onNodeSelectionChanged() {
    if (mounted && nodeComponentService.selectedNodeId != null) {
      // 노드가 선택되면 키보드 내리기
      _editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _cleanupAndExit() {
    // 🎯 키보드를 먼저 내려서 레이아웃 재계산 문제 방지
    // 다이얼로그가 닫힌 후 키보드가 내려가면서 빈 공간이 생기는 문제 해결
    _editorFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();

    try {
      dragService.endDrag();
      composer.clearSelection();
      nodeComponentService.clearAll();
    } catch (_) {}

    try {
      stickerService.resetSession();
    } catch (_) {}

    // ✅ 나가기 직전 정리(동기) - 오래 걸려도 상관없으니 여기서 최대한 처리
    try {
      cleanupAllVideoPlayers();
    } catch (_) {}

    // 🎯 영상 파일 정리
    try {
      nodeComponentService.clearTempVideoFile('default');
    } catch (_) {}

    if (!mounted) return;
    debugPrint(
      '[PostwriteScreen][EXIT] _cleanupAndExit: isEditingMode=${widget.isEditingMode} shouldRefreshMyFeed=$_shouldRefreshMyFeed categoryChanged=$_categoryChanged serverAppliedTitle=$_serverAppliedTitle serverAppliedSummary=$_serverAppliedSummary serverAppliedThumbnail=$_serverAppliedThumbnailUrl',
    );

    // ✅ 편집 모드에서 "메타데이터만 변경"된 경우에도 PostReader에 즉시 반영할 수 있도록 pop 결과를 제공
    if (widget.isEditingMode &&
        (_shouldRefreshMyFeed || _categoryChanged) &&
        widget.postId != null) {
      final base = Map<String, dynamic>.from(widget.exportedDataForEdit ?? {});
      if (_serverAppliedTitle != null) base['title'] = _serverAppliedTitle;
      if (_serverAppliedSummary != null)
        base['summary'] = _serverAppliedSummary;
      if (_serverAppliedThumbnailUrl != null) {
        base['thumbnailImageUrl'] = _serverAppliedThumbnailUrl;
      }
      debugPrint(
        '[PostwriteScreen][EXIT] pop(metadataOnly): postId=${widget.postId} title=${base['title']} summary=${base['summary']} thumbnail=${base['thumbnailImageUrl']}',
      );
      Navigator.of(context).pop(<String, dynamic>{
        'didEdit': true,
        'postId': widget.postId,
        'exported': base,
      });
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _exitEditor({
    required bool forceAutoDraftIfChanged,
    required bool clearAutoDraft,
  }) async {
    if (!mounted) return;
    if (!mounted) return;

    try {
      // ✅ 정책:
      // - "명시적 임시저장" 후 종료한 경우: autoDraft(이어쓰기용)는 남기면 안 됨 → 항상 삭제
      // - 그 외(자동저장 기반 종료): autoDraft를 남겨서 다음 진입 시 "작성하던 글이 있어요"를 띄움
      final shouldClearAutoDraft = clearAutoDraft || _didExplicitDraftSave;

      if (shouldClearAutoDraft) {
        await draftService.clearAutoDraft();
      } else if (forceAutoDraftIfChanged) {
        // ✅ 타이머와 무관하게 "나가기 직전" 1회 autoDraft 저장 보장
        await _saveAutoDraftNowIfPossible();
      }
    } catch (e) {
      debugPrint('[PostwriteScreen] exit 처리 중 오류(무시): $e');
    }

    if (!mounted) return;
    _cleanupAndExit();
  }

  // 제목은 썸네일 편집 화면에서 입력하므로 제목 노드 업데이트 로직 제거됨

  // moved to EditorService (getNodeGlobalRect)
  // _detectVerticalGapAt은 각 컴포넌트의 _handleSpecialNodeTap에서 처리하므로 제거됨

  /// 마지막 특수 노드 아래 빈 공간 클릭 시 빈 문단 추가
  void _handleTapBelowLastSpecialNode(Offset globalPosition) {
    debugPrint('[PostWrite] ========== 빈 공간 탭 처리 시작 ==========');
    debugPrint(
      '[PostWrite] globalPosition: (${globalPosition.dx}, ${globalPosition.dy})',
    );

    // ✅ 키보드가 올라오거나(뷰 인셋 변화), 스크롤/레이아웃이 재배치되면
    // 노드 rect 캐시가 stale 해질 수 있다.
    // 이 로직은 "마지막 노드 아래"를 판정해야 하므로 매번 최신 rect가 필요하다.
    dragService.invalidateNodeRectCache();

    final lastIndex = document.nodeCount - 1;
    debugPrint(
      '[PostWrite] lastIndex: $lastIndex, nodeCount: ${document.nodeCount}',
    );
    if (lastIndex < 0) {
      debugPrint('[PostWrite] lastIndex < 0, 종료');
      return;
    }

    final lastNode = document.getNodeAt(lastIndex);
    if (lastNode == null) {
      debugPrint('[PostWrite] lastNode is null, 종료');
      return;
    }
    debugPrint(
      '[PostWrite] lastNode: ${lastNode.id}, type: ${lastNode.runtimeType}',
    );

    // 마지막 노드가 특수 노드인지 확인
    final isSpecial = NodeTypeChecker.isSpecialNode(lastNode);
    debugPrint('[PostWrite] isSpecial: $isSpecial');
    if (!isSpecial) {
      debugPrint('[PostWrite] 마지막 노드가 특수 노드가 아님, 종료');
      return;
    }

    // 마지막 노드의 Rect 확인
    final nodeRect = dragService.getNodeGlobalRect(lastNode.id);
    if (nodeRect == null) {
      debugPrint('[PostWrite] nodeRect is null, 종료');
      return;
    }
    debugPrint(
      '[PostWrite] nodeRect: top=${nodeRect.top}, bottom=${nodeRect.bottom}, left=${nodeRect.left}, right=${nodeRect.right}',
    );
    debugPrint(
      '[PostWrite] nodeRect size: width=${nodeRect.width}, height=${nodeRect.height}',
    );

    // 🎯 노드 영역 아래 모든 여백을 클릭 가능 영역으로 확장
    final tapY = globalPosition.dy;
    final isBelowNode = tapY > nodeRect.bottom;
    final distanceBelow = tapY - nodeRect.bottom;

    debugPrint(
      '[PostWrite] 좌표 비교: tapY=$tapY, nodeBottom=${nodeRect.bottom}, distanceBelow=$distanceBelow',
    );
    debugPrint('[PostWrite] isBelowNode: $isBelowNode');

    if (isBelowNode) {
      // 🎯 실제로 그 위치가 비어있는지 확인 (다른 노드가 있는지 체크)
      final hitTestResult = editorService.findNodeByHitTest(
        globalPosition,
        dragService,
      );

      debugPrint(
        '[PostWrite] hitTestResult: ${hitTestResult?.key?.id}, lastNode: ${lastNode.id}',
      );
      if (hitTestResult != null) {
        debugPrint(
          '[PostWrite] hitTestResult.key: ${hitTestResult.key?.id}, value: ${hitTestResult.value}',
        );
        if (hitTestResult.value != null) {
          debugPrint(
            '[PostWrite] hitTestResult.value (Rect): top=${hitTestResult.value!.top}, bottom=${hitTestResult.value!.bottom}, left=${hitTestResult.value!.left}, right=${hitTestResult.value!.right}',
          );
        }
      }

      // hit test 결과가 없거나, 마지막 노드인 경우만 빈 공간으로 간주
      final isEmpty =
          hitTestResult == null ||
          hitTestResult.key == null ||
          hitTestResult.key!.id == lastNode.id;

      debugPrint(
        '[PostWrite] isEmpty=$isEmpty → 빈 텍스트 추가 ${isEmpty ? "실행" : "스킵"}',
      );

      if (isEmpty) {
        debugPrint('[PostWrite] 빈 텍스트 노드 추가 실행: index=${lastIndex + 1}');
        editorService.insertEmptyParagraphAtIndex(lastIndex + 1);
        nodeComponentService.selectNode(null);
        debugPrint('[PostWrite] 빈 텍스트 노드 추가 완료');
      }
    } else {
      debugPrint('[PostWrite] 노드 아래 영역이 아님, 스킵');
    }
    debugPrint('[PostWrite] ========== 빈 공간 탭 처리 종료 ==========');
  }

  Stylesheet _buildStylesheet(BuildContext context) {
    return buildCustomStylesheet(context).copyWith(
      // ✅ iOS selection handle이 앱바 영역으로 튀어나가며 body 경계에서 잘리는 이슈 방지
      // (최상단 줄에서 선택해도 핸들이 잘리지 않도록 상단 여백 확보)
      documentPadding: const EdgeInsets.only(
        top: 24,
        left: 0,
        right: 0,
        bottom: 100,
      ),
    );
  }

  /// 🎯 자동 저장 시작 (30초마다)
  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // ⚠️ 라우트 전환 중(deactivate)에는 mounted==true일 수 있지만
      // context가 deactivated 상태면 Provider lookup 등이 크래시를 유발할 수 있음
      if (!mounted || !context.mounted || widget.isEditingMode) {
        timer.cancel();
        return;
      }
      _autoSave();
    });
  }

  /// 🎯 자동 저장 실행
  Future<void> _autoSave() async {
    // ⚠️ 화면 전환/해제 타이밍 보호 (mounted==true여도 context가 이미 deactivated일 수 있음)
    if (!mounted || !context.mounted) return;
    // 이미 저장 중이면 스킵
    if (_isAutoSaving || _isSaving) return;

    // 변경사항이 없으면 스킵
    if (!editorService.shouldPromptSaveOnExit(context)) return;

    // ✅ 업로드 중이어도 autoDraft 저장은 허용한다 (복구 목적).
    // (saveAutoDraft는 allowPartialUpload=true)

    setState(() {
      _isAutoSaving = true;
    });

    try {
      // ✅ 정책: 제목은 "임시저장/Step1 입력"이 아니면 본문에서 추출하지 않는다.
      // 자동저장은 복구 목적이므로, 빈 제목이면 ''로 저장한다 (제목이 있으면 유지).
      final metadata = _extractDraftMetadata();
      final title = metadata['title']!;
      final summary = metadata['summary']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      // 🎯 UUID 기반 draftId 사용 (제목 기반 제거)
      if (currentDraftId == null) {
        // 혹시 UUID가 없으면 생성 (안전장치)
        const uuid = Uuid();
        currentDraftId = 'draft_${uuid.v4()}';
        debugPrint('[PostwriteScreen] ⚠️ UUID가 없어서 생성: $currentDraftId');
      }

      // 현재 draft ID를 sessionKey로 영상 파일만 가져오기
      final sessionKey = currentDraftId!;

      final videoFilePath = nodeComponentService.getTempVideoFilePath(
        sessionKey,
      );
      final videoThumbnailPath = nodeComponentService.getTempVideoThumbnailPath(
        sessionKey,
      );

      // 🎯 자동저장(최근 1개): 임시저장 리스트에는 저장하지 않고, 단 하나만 유지
      await draftService.saveAutoDraft(
        editorService: editorService,
        stickerService: stickerService,
        draftId: currentDraftId!,
        title: title,
        summary: summary,
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
        visibility: 'public',
        selectedGroupIds: [],
        textStylingService: textStylingService,
      );

      debugPrint('[PostwriteScreen] ✅ 자동 저장 완료: $title');
    } catch (e) {
      // 🎯 자동저장은 복구 목적이므로, 업로드 중인 미디어가 있어도 조용히 스킵 (throw하지 않음)
      // 업로드 완료 후 다음 자동저장에서 성공할 수 있도록 에러를 무시한다.
      if (e is StateError && e.message.contains('업로드')) {
        debugPrint('[PostwriteScreen] ⏭️ 자동 저장 스킵 (업로드 중): ${e.message}');
      } else {
        debugPrint('[PostwriteScreen] ⚠️ 자동 저장 실패: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAutoSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // 🎯 자동 저장 타이머 정리
    _autoSaveTimer?.cancel();
    _editorFocusNode.dispose();
    // 🎯 에디터 종료 시 진행 중인 비디오 압축 취소
    final uploadService = UploadService();
    uploadService.cancelEditorCompressions(_editorUploadSessionId);

    // 영상 업로드 인디케이터 정리
    _videoUploadIndicatorNotifier.dispose();

    // 🎯 에디터 종료 시 모든 비디오 플레이어 정리
    try {
      cleanupAllVideoPlayers();
      debugPrint('[PostwriteScreen] 모든 비디오 플레이어 정리 완료');
    } catch (e) {
      debugPrint('[PostwriteScreen] 비디오 정리 오류: $e');
    }

    // 이미지 선택 상태 초기화
    nodeComponentService.clearHighlightedSelectionSilently();
    nodeComponentService.clearSelectionSilently();

    textStylingService.removeListener(_onEditorServiceChange);
    textStylingService.dispose();
    editorService.removeListener(_onEditorServiceChange);
    editorService.dispose();
    stickerService.removeListener(_onEditorServiceChange);
    stickerService.removeListener(_onStickerHistoryChange);
    nodeComponentService.removeListener(_onNodeSelectionChanged);
    document.removeListener(_onDocumentStructureChanged);
    try {
      stickerService.resetSession(shouldNotify: false);
    } catch (_) {}
    _keyboardVisibleNotifier.dispose();
    _isEmptyNotifier.dispose();

    // 🎯 카테고리 변경 시 피드 프로바이더 캐시 초기화 + 새로고침
    if (_categoryChanged) {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final feed = MyProfileFeedProvider();
          feed.invalidateCache();
          feed.refresh().catchError((_) {});
          debugPrint('[PostwriteScreen] 카테고리 변경 후 피드 프로바이더 캐시 초기화 + 새로고침 완료');
        } catch (e) {
          debugPrint('[PostwriteScreen] 카테고리 변경 후 피드 새로고침 실패: $e');
        }
      });
    }
    // 🎯 수정 도중 변경이 있었다면 내 피드 선택적 업데이트 (전체 새로고침 생략)
    else if (_shouldRefreshMyFeed && widget.postId != null) {
      // 비디오 컨트롤러 정리가 완전히 완료될 때까지 약간 지연
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final feed = MyProfileFeedProvider(); // 싱글톤 직접 접근
          final postId = widget.postId!;

          // 변경된 메타데이터만 선택적 업데이트
          feed.updatePostMetadata(
            postId,
            thumbnailImageUrl: _serverAppliedThumbnailUrl,
            title: _serverAppliedTitle,
            summary: _serverAppliedSummary,
          );
          debugPrint('[PostwriteScreen] 프로필 피드 선택적 업데이트 완료 (썸네일/제목/요약 변경)');
        } catch (e) {
          debugPrint('[PostwriteScreen] 프로필 피드 선택적 업데이트 실패: $e');
          // 실패 시 fallback으로 전체 새로고침
          try {
            final feed = MyProfileFeedProvider();
            feed.invalidateCache();
            feed.refresh().catchError((_) {});
          } catch (_) {}
        }
      });
    } else if (_shouldRefreshMyFeed && widget.postId == null) {
      // 새 포스트 생성 시에는 전체 새로고침 필요 (포스트 ID가 없음)
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final feed = MyProfileFeedProvider();
          feed.invalidateCache();
          feed.refresh().catchError((_) {});
        } catch (_) {}
      });
    }
    super.dispose();
  }

  /// ✅ 자동저장(최근 1개)이 있으면 "이어 작성/새 글" 선택 바텀시트를 1회 표시
  /// 반환값: 바텀시트를 실제로 표시했는지 여부 (포커스 딜레이 판단용)
  Future<bool> _promptResumeWritingIfNeeded() async {
    if (!mounted || widget.isEditingMode) return false;
    if (_didPromptResumeWriting) return false;
    _didPromptResumeWriting = true;

    var didShowSheet = false;
    try {
      final autoDraft = await draftService.getAutoDraft();
      if (!mounted || autoDraft == null) return false;
      didShowSheet = true;

      // 에디터 포커스가 먼저 올라오면 UX가 어색해서 미리 내림
      _editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      final choice = await ResumeWritingBottomSheet.show(
        context,
        title: autoDraft.title,
        subtitle: TimeUtils.formatRelativeTime(context, autoDraft.updatedAt),
      );
      if (!mounted) return true; // 이미 시트는 표시됨
      if (choice == null) return true; // 시트 표시 후 사용자가 취소/바깥탭 등으로 닫음

      // ✅ 로딩 오버레이 표시 (바텀시트는 이미 닫힘)
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.3),
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // ✅ 백그라운드에서 초기화 작업 수행
      try {
        if (choice == ResumeWritingChoice.resume) {
          final ok = await draftService.loadAutoDraft(
            editorService: editorService,
            stickerService: stickerService,
            nodeComponentService: nodeComponentService,
            dragService: dragService,
            textStylingService: textStylingService,
          );
          if (!mounted) return true;
          if (ok) {
            setState(() {
              currentDraftId = autoDraft.id; // ✅ 자동저장 UUID 유지
            });
            // ✅ Step1 메타데이터도 함께 복원 (제목/요약/썸네일)
            _restoreDraftMetadata(
              title: autoDraft.title,
              summary: autoDraft.summary,
              thumbnailUrl: autoDraft.thumbnailUrl,
            );
            // (빈 상태는 build()에서 derived state로 동기화하므로 별도 토글 불필요)
          }
        } else if (choice == ResumeWritingChoice.newDraft) {
          await draftService.clearAutoDraft();
          // 새 글은 기존 init에서 만든 빈 문서 + 새 UUID를 그대로 사용
          // (autosave는 empty 상태에서 저장하지 않음)
        }
      } finally {
        // ✅ 로딩 오버레이 제거
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('[PostwriteScreen] resume writing prompt 실패(무시): $e');
    }
    return didShowSheet;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 🎯 EditorService에 context 설정 (노드 선택 해제용)
    // didChangeDependencies에서 호출하여 build마다 호출되지 않도록 최적화
    editorService.setContext(context);
    editorService.setEditorFocusNode(_editorFocusNode);
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 성능 최적화: 키보드 상태는 MediaQuery에서 직접 읽기 (변수 저장 제거)
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final appBarHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;

    // ✅ 빈 상태 오버레이는 "파생 상태(derived state)"로 동기화한다.
    // - 문서가 비었는지(텍스트/특수노드/스티커 기준)
    // - 키보드가 내려갔는지
    // - 커서(selection)가 없는지
    //
    // undo/redo, draft load, 미디어 추가 등 모든 경로에서 notifier 갱신 누락으로
    // 오버레이가 남아있는 문제를 원천적으로 줄인다.
    //
    // 🎯 초기 진입 시 키보드가 올라오기 전까지는 오버레이를 숨김
    final shouldShowEmptyOverlay =
        _isInitialEntry
            ? false
            : (!isKeyboardVisible &&
                composer.selection == null &&
                _isDocumentEmpty());
    if (_isEmptyNotifier.value != shouldShowEmptyOverlay) {
      _isEmptyNotifier.value = shouldShowEmptyOverlay;
    }

    // 🎯 keyboardVisibleNotifier 값 갱신 (매 build마다 생성하지 않고 값만 변경)
    if (_keyboardVisibleNotifier.value != isKeyboardVisible) {
      _keyboardVisibleNotifier.value = isKeyboardVisible;
      // ✅ 키보드 등장/퇴장은 문서 레이아웃(스크롤 위치 포함)을 바꾸므로
      // cached node rect를 반드시 무효화해서 hit-test/빈공간탭 판정이 정확해지게 한다.
      dragService.invalidateNodeRectCache();

      // 🎯 키보드가 올라오면 초기 진입 플래그 해제
      if (isKeyboardVisible && _isInitialEntry) {
        _isInitialEntry = false;
      }
    }

    // 🎯 키보드 이벤트로 setState 제거 (스크롤 기반으로만 앱바 제어)

    return WillPopScope(
      onWillPop: () async {
        if (widget.isEditingMode) {
          // 수정 모드: 변경사항이 있는지 확인
          // 제목은 썸네일 편집 화면에서 입력하므로 원본 데이터 그대로 사용
          final originalForComparison = widget.exportedDataForEdit!;

          final hasChanges = ContentChangeDetector.hasContentChanged(
            originalExported: originalForComparison,
            editorService: editorService,
            stickerService: stickerService,
          );
          final bool hasMetadataChanges =
              _shouldRefreshMyFeed || _categoryChanged;

          debugPrint(
            '[PostwriteScreen][WILL_POP] editMode: hasContentChanges=$hasChanges hasMetadataChanges=$hasMetadataChanges shouldRefreshMyFeed=$_shouldRefreshMyFeed categoryChanged=$_categoryChanged',
          );

          // 변경사항이 없으면 바로 나가기
          if (!hasChanges) {
            // ✅ 본문은 그대로인데 썸네일/제목/요약/카테고리/공개범위만 바뀐 케이스
            _cleanupAndExit();
            return false;
          }

          // 변경사항이 있을 때만 다이얼로그 표시
          final shouldCancel = await DialogUtils.showConfirmDialog(
            context,
            title: context.tr('cancel_edit_title'),
            message: context.tr('cancel_edit_message'),
            confirmText: context.tr('exit_writing_title'),
            cancelText: context.tr('continue_editing'),
            isDestructive: true,
          );
          if (shouldCancel == true) {
            _cleanupAndExit();
          }
          return false;
        }

        // 새 글 작성 모드:
        // 1) 변경사항이 있으면 "임시저장/저장 안 함" 다이얼로그
        // 2) ✅ 명시적 임시저장 후 "변경사항이 없으면" 다이얼로그 없이 바로 나가기
        // 3) 그 외에는 "나가기/계속 작성" 다이얼로그
        // 🎯 본문 변경사항만 확인 (제목/요약/썸네일은 썸네일 편집 화면에서 독립적으로 관리)
        final hasBodyContent = editorService.hasNonEmptyBody(context: context);
        final needPrompt = editorService.shouldPromptSaveOnExitBodyOnly(
          context,
        );

        // ✅ 오직 "명시적 임시저장 후 본문 변경사항 없음"일 때만 다이얼로그 스킵
        if (hasBodyContent && _didExplicitDraftSave && !needPrompt) {
          await _exitEditor(
            forceAutoDraftIfChanged: false,
            clearAutoDraft: false,
          );
          return false;
        }

        if (needPrompt) {
          final shouldSave = await DialogUtils.showConfirmDialog(
            context,
            title: context.tr('discard_or_save_title'),
            message: context.tr('discard_or_save_message'),
            confirmText: context.tr('save_and_exit'),
            cancelText: context.tr('discard_without_save'),
            isDestructive: false,
          );
          if (shouldSave == true) {
            final success = await _saveDraft();
            // ✅ 임시저장 성공했을 때만 편집기 닫기
            if (success) {
              // ✅ 나가기 직전 변경사항이 있었다면(=needPrompt==true) 타이머와 무관하게 autoDraft 1회 보장
              await _exitEditor(
                forceAutoDraftIfChanged: true,
                clearAutoDraft: false,
              );
            }
            // 실패하면 편집기 유지 (다이얼로그만 닫힘)
          } else if (shouldSave == false) {
            // 사용자가 "저장 안 함"을 명시적으로 선택한 경우:
            // 자동저장(최근 1개)도 함께 정리해서, 다음 진입 시 "이어 작성"이 뜨지 않게 한다.
            // 🎯 키보드를 먼저 내리고 안정화된 후 나가기
            _editorFocusNode.unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
            FocusScope.of(context).unfocus();

            // 키보드 애니메이션 완료 대기 (viewInsets가 0이 될 때까지 또는 최대 400ms)
            final startTime = DateTime.now();
            while (mounted) {
              final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
              if (keyboardHeight == 0) break;

              final elapsed = DateTime.now().difference(startTime);
              if (elapsed.inMilliseconds > 400) break; // 최대 400ms 대기

              await Future.delayed(const Duration(milliseconds: 50));
            }

            // 안정화를 위한 추가 대기
            if (mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
            }

            if (mounted) {
              await _exitEditor(
                forceAutoDraftIfChanged: false,
                clearAutoDraft: true,
              );
            }
          }
          // null이면 아무 것도 안 함 (다이얼로그만 닫힘)
        } else if (hasBodyContent) {
          final shouldExit = await DialogUtils.showConfirmDialog(
            context,
            title: context.tr('exit_writing_title'),
            message: context.tr('exit_writing_message'),
            confirmText: context.tr('exit'),
            cancelText: context.tr('continue_writing'),
            isDestructive: false,
          );
          if (shouldExit == true) {
            // 🎯 키보드를 먼저 내리고 안정화된 후 나가기
            _editorFocusNode.unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
            FocusScope.of(context).unfocus();

            // 키보드 애니메이션 완료 대기 (viewInsets가 0이 될 때까지 또는 최대 400ms)
            final startTime = DateTime.now();
            while (mounted) {
              final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
              if (keyboardHeight == 0) break;

              final elapsed = DateTime.now().difference(startTime);
              if (elapsed.inMilliseconds > 400) break; // 최대 400ms 대기

              await Future.delayed(const Duration(milliseconds: 50));
            }

            // 안정화를 위한 추가 대기
            if (mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
            }

            if (mounted) {
              // 🎯 본문 변경사항만 확인 (제목/요약/썸네일은 썸네일 편집 화면에서 독립적으로 관리)
              final changedNow = editorService.shouldPromptSaveOnExitBodyOnly(
                context,
              );
              await _exitEditor(
                forceAutoDraftIfChanged: changedNow,
                clearAutoDraft: false,
              );
            }
          }
        } else {
          await _exitEditor(
            forceAutoDraftIfChanged: false,
            clearAutoDraft: false,
          );
        }
        return false;
      },

      child: Stack(
        children: [
          Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(appBarHeight),
              child:
                  widget.isEditingMode
                      ? EditModeAppBar(
                        editorService: editorService,
                        onSave: _saveEditedPost,
                        currentVisibility: _editVisibility,
                        currentGroupIds: _editGroupIds,
                        postId: widget.postId,
                        isSaving: _isSaving,
                        isAutoSaving: _isAutoSaving,
                        videoUploadIndicatorNotifier:
                            _videoUploadIndicatorNotifier,
                        onVisibilityChanged: (visibility, groupIds) {
                          setState(() {
                            _editVisibility = visibility;
                            _editGroupIds = groupIds;
                          });
                          _shouldRefreshMyFeed = true;
                        },
                        onTitleSummaryChanged: (title, summary) {
                          setState(() {
                            _serverAppliedTitle = title;
                            _serverAppliedSummary = summary;
                          });
                          debugPrint(
                            '[PostwriteScreen] 제목/요약 업데이트 및 서버 적용: title=$title, summary=$summary',
                          );
                          _shouldRefreshMyFeed = true;
                        },
                        onCategoryChanged: () {
                          _categoryChanged = true;
                        },
                        onThumbnailChanged: (url, id) {
                          debugPrint(
                            '[PostwriteScreen] onThumbnailChanged 콜백 받음: url=$url, id=$id',
                          );
                          setState(() {
                            _serverAppliedThumbnailUrl = url;
                          });
                          _shouldRefreshMyFeed = true;
                        },
                        onEditThumbnail: _openThumbnailEditOverlay,
                        initialTitle: _serverAppliedTitle,
                        initialSummary: _serverAppliedSummary,
                        initialThumbnailUrl: _serverAppliedThumbnailUrl,
                        sessionKey: currentDraftId ?? 'draft_temp',
                        currentTitle: _serverAppliedTitle,
                        currentSummary: _serverAppliedSummary,
                        currentThumbnailUrl: _serverAppliedThumbnailUrl,
                        originalExportedData: widget.exportedDataForEdit,
                        stickerService: stickerService,
                      )
                      : EditorAppBar(
                        editorService: editorService,
                        stickerService: stickerService,
                        onSaveDraft: _saveDraft,
                        onLoadDraft: _showDraftList,
                        currentDraftId: currentDraftId,
                        videoUploadIndicatorNotifier:
                            _videoUploadIndicatorNotifier,
                        initialTitleForExport: _draftTitleOverride,
                        initialSummaryForExport: _draftSummaryOverride,
                        initialThumbnailUrlForExport: _draftThumbnailOverride,
                        onExportMetadataChanged: (
                          title,
                          summary,
                          thumbnailUrl,
                        ) {
                          setState(() {
                            _draftTitleOverride =
                                title.trim().isEmpty ? null : title.trim();
                            _draftSummaryOverride =
                                summary.trim().isEmpty ? null : summary.trim();
                            _draftThumbnailOverride =
                                thumbnailUrl.trim().isEmpty
                                    ? null
                                    : thumbnailUrl.trim();
                          });
                          // ✅ Step1에서 편집한 값이 뒤로가기로 날아가지 않게 즉시 autoDraft에 반영
                          _saveAutoDraftNowIfPossible().catchError((_) {});
                        },
                      ),
            ),
            body: Stack(
              key: _editorBodyStackKey,
              clipBehavior: Clip.none,
              children: [
                Theme(
                  data: AppTheme.lightTheme,
                  child: RawScrollbar(
                    controller: scrollController,
                    thumbColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                    thickness: 4,
                    radius: const Radius.circular(12),
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (details) {
                        _handleTapBelowLastSpecialNode(details.position);
                      },
                      child: Builder(
                        builder: (context) {
                          final screenWidth = MediaQuery.sizeOf(context).width;
                          final isDarkMode =
                              context.read<ThemeProvider>().themeMode ==
                              ThemeMode.dark;
                          return RepaintBoundary(
                            child: SuperEditor(
                              gestureMode:
                                  Platform.isIOS
                                      ? DocumentGestureMode.iOS
                                      : DocumentGestureMode.android,
                              editor: editor,
                              focusNode: _editorFocusNode,
                              stylesheet: _buildStylesheet(context),
                              selectionStyle: SelectionStyles(
                                selectionColor: AppColors.primary.withValues(
                                  alpha: 0.3,
                                ),
                                highlightEmptyTextBlocks: false,
                              ),
                              documentLayoutKey: _documentLayoutKey,
                              scrollController: scrollController,
                              documentOverlayBuilders: [
                                const SuperEditorIosToolbarFocalPointDocumentLayerBuilder(),
                                const SuperEditorIosHandlesDocumentLayerBuilder(
                                  caretWidth: 0,
                                ),
                                const SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder(),
                                const SuperEditorAndroidHandlesDocumentLayerBuilder(
                                  caretWidth: 0,
                                ),
                                SelectionBoxCaretOverlayBuilder(
                                  caretStyle: CaretStyle(
                                    width: 2,
                                    color: AppColors.primary,
                                  ),
                                  displayOnAllPlatforms: true,
                                ),
                              ],
                              componentBuilders: [
                                SingleImageComponentBuilder(
                                  screenWidth: screenWidth,
                                  dragService: dragService,
                                  isDarkMode: isDarkMode,
                                ),
                                RowImageComponentBuilder(
                                  screenWidth: screenWidth,
                                  dragService: dragService,
                                  isDarkMode: isDarkMode,
                                ),
                                PageViewImageComponentBuilder(
                                  screenWidth: screenWidth,
                                  dragService: dragService,
                                  isDarkMode: isDarkMode,
                                ),
                                CustomParagraphComponentBuilder(
                                  dragService: dragService,
                                  editorService: editorService,
                                ),
                                DividerComponentBuilder(
                                  dragService: dragService,
                                  editor: editor,
                                  focusNode: _editorFocusNode,
                                ),
                                MentionComponentBuilder(
                                  dragService: dragService,
                                  editor: editor,
                                  focusNode: _editorFocusNode,
                                  isDarkMode: isDarkMode,
                                ),
                                LinkComponentBuilder(
                                  dragService: dragService,
                                  isDarkMode: isDarkMode,
                                ),
                                ClipComponentBuilder(
                                  screenWidth: screenWidth,
                                  dragService: dragService,
                                  isEditing: true,
                                  isDarkMode: isDarkMode,
                                ),
                                ...defaultComponentBuilders.where(
                                  (builder) =>
                                      builder.runtimeType.toString() !=
                                      'ParagraphComponentBuilder',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // 드래그 오버레이 (키보드가 내려가 있을 때만 표시)
                //
                // ⚠️ 중요: DragOverlayWidget은 내부에서 Positioned를 반환한다.
                // 따라서 "화면 전체 크기의 Stack"을 기준으로 레이아웃되어야 한다.
                // AnimatedSwitcher 내부의 Stack(자식 크기 기반)으로 들어가면,
                // Stack 사이즈가 0으로 잡혀 오버레이가 (0,0) 근처(좌상단)에 고정되는 문제가 생길 수 있다.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: dragService,
                    builder: (context, _) {
                      final keyboardVisible =
                          MediaQuery.viewInsetsOf(context).bottom > 0;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child:
                            (dragService.draggingNodeId != null &&
                                    !keyboardVisible)
                                ? Stack(children: [_buildDragOverlay()])
                                : const SizedBox.shrink(key: ValueKey('empty')),
                      );
                    },
                  ),
                ),

                // 스티커 캔버스
                Positioned.fill(
                  child: RepaintBoundary(
                    child: StickerCanvas(scrollController: scrollController),
                  ),
                ),

                // 🎯 빈 상태 UI (키보드가 내려가고 문서가 비어있을 때)
                // ✅ _isEmptyNotifier가 이미 모든 조건(키보드, 커서, 문서)을 체크한 최종 결과이므로
                // ValueListenableBuilder에서는 isEmpty만 확인하면 됨
                ValueListenableBuilder<bool>(
                  valueListenable: _isEmptyNotifier,
                  builder: (context, isEmpty, _) {
                    // 🎯 처음 나올 때는 페이드 인 적용, 사라질 때는 페이드 아웃 없이 즉시 사라짐
                    if (!isEmpty) {
                      // 사라질 때는 즉시 제거 (페이드 아웃 없음)
                      return const SizedBox.shrink();
                    }

                    // 나타날 때는 AnimatedOpacity 사용 (페이드 인만 적용)
                    return Positioned.fill(
                      child: IgnorePointer(
                        ignoring: false,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeIn,
                          builder: (context, opacity, child) {
                            return Opacity(opacity: opacity, child: child);
                          },
                          child: EmptyEditorState(
                            onTap: () {
                              // 빈 상태 UI를 탭하면 첫 번째 문단에 포커스
                              if (document.isNotEmpty) {
                                final firstNode = document.getNodeAt(0);
                                if (firstNode is ParagraphNode) {
                                  editor.execute([
                                    ChangeSelectionRequest(
                                      DocumentSelection.collapsed(
                                        position: DocumentPosition(
                                          nodeId: firstNode.id,
                                          nodePosition: const TextNodePosition(
                                            offset: 0,
                                          ),
                                        ),
                                      ),
                                      SelectionChangeType.placeCaret,
                                      SelectionReason.userInteraction,
                                    ),
                                  ]);
                                  _editorFocusNode.requestFocus();
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            // 🎯 성능 최적화: 키보드 높이를 상위에서 한 번만 계산하여 전달
            // bottomNavigationBar 내부의 MediaQuery 접근 최소화
            bottomNavigationBar: _BottomBar(
              keyboardHeight: MediaQuery.viewInsetsOf(context).bottom,
              keyboardVisibleNotifier: _keyboardVisibleNotifier,
              textStylingService: textStylingService,
              editorService: editorService,
              scrollController: scrollController,
              onDismissKeyboard: () {
                _editorFocusNode.unfocus();
                // (빈 상태는 build()에서 derived state로 동기화하므로 별도 체크 불필요)
              },
              onShowDraftList: _showDraftList,
              videoUploadIndicatorNotifier: _videoUploadIndicatorNotifier,
              nodeComponentService: nodeComponentService,
              document: document,
              onEditImage: (selectedId, node) {
                nodeComponentService.editImage(
                  context: context,
                  imageId: selectedId,
                  node: node,
                  editorService: editorService,
                  document: document,
                );
              },
              onDeleteNode: _deleteNode,
              onChangeMediaAlignment: _changeMediaAlignment,
              // (빈 상태는 build()에서 derived state로 동기화하므로 별도 토글 불필요)
              onMediaAdded: null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

    // 🎯 DragService는 globalPosition을 저장한다.
    // 하지만 DragOverlayWidget은 현재 Stack(=Scaffold body) 좌표계를 기준으로 Positioned 된다.
    // 따라서 global -> local 변환을 하지 않으면 손가락을 "안 따라오는 것처럼" 보일 수 있다.
    final RenderBox? overlayBox =
        _editorBodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset localPos =
        overlayBox != null ? overlayBox.globalToLocal(pos) : pos;

    // 이미지 행 분리 모드
    if (dragService.hasSplitImageInfo) {
      final splitInfo = dragService.getSplitImageInfo();
      final rowNode =
          document.getNodeById(splitInfo?['rowId']) as ImageRowNode?;
      final imageIndex = splitInfo?['imageIndex'] as int?;

      if (rowNode != null &&
          imageIndex != null &&
          imageIndex < rowNode.imageUrls.length) {
        return DragOverlayWidget(
          position: localPos,
          document: document,
          splitImageUrl: rowNode.imageUrls[imageIndex],
        );
      }
    }

    // PageView 이미지 분리 모드
    if (dragService.isPageViewItemDrag) {
      final pageViewNode =
          document.getNodeById(dragService.subjectPageViewId ?? '')
              as PageViewImageNode?;
      final imageIndex = dragService.subjectPageViewImageIndex;

      if (pageViewNode != null &&
          imageIndex != null &&
          imageIndex >= 0 &&
          imageIndex < pageViewNode.imageUrls.length) {
        return DragOverlayWidget(
          position: localPos,
          document: document,
          splitImageUrl: pageViewNode.imageUrls[imageIndex],
        );
      }
    }

    // 일반 노드 드래그
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    return DragOverlayWidget(
      node: node,
      position: localPos,
      document: document,
      previewImageLocalPath:
          dragService.previewImageLocalPath, // 🎯 클립 썸네일 깜빡임 방지
      previewImageUrl:
          dragService.previewImageUrl, // 🚀 네트워크 URL (로컬-네트워크 혼용 구조)
    );
  }

  /// 미디어(이미지/영상) 정렬 변경
  Future<void> _changeMediaAlignment(
    DocumentNode node,
    String selectedId,
  ) async {
    debugPrint(
      '[PostWriteScreen] 토글 시작: nodeType=${node.runtimeType}, nodeId=$selectedId',
    );

    // 메타데이터에서 현재 패딩 정보 가져오기 (기본값: 'center' = 패딩 있음)
    final currentPadding = node.metadata['padding'] as String? ?? 'center';
    debugPrint('[PostWriteScreen] 현재 padding: $currentPadding');

    // 다음 패딩 모드로 전환
    final nextPadding = _getNextPaddingMode(currentPadding);
    debugPrint('[PostWriteScreen] 다음 padding: $nextPadding');

    // 메타데이터 업데이트
    final updatedMetadata = Map<String, dynamic>.from(node.metadata);
    updatedMetadata['padding'] = nextPadding;

    DocumentNode newNode;

    if (node is ImageNode) {
      newNode = AppImageNode(
        id: node.id,
        imageUrl: node.imageUrl,
        altText: node.altText,
        metadata: updatedMetadata,
      );
    } else if (node is ClipNode) {
      newNode = ClipNode(
        id: node.id,
        label: node.label,
        colorHex: node.colorHex,
        url: node.url,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
        metadata: updatedMetadata,
      );
    } else if (node is LinkNode) {
      newNode = LinkNode(
        id: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
        metadata: updatedMetadata,
      );
    } else {
      return; // 지원하지 않는 노드 타입
    }

    // 🎯 미디어 노드(Image/Clip)는 ReplaceNodeRequest 대신 replaceNodeById 사용 (remove+insert 이벤트 방지)
    // LinkNode는 텍스트 기반이라 ReplaceNodeRequest 유지
    if (node is ImageNode || node is ClipNode) {
      debugPrint(
        '[PostWriteScreen] 노드 교체 실행 (replaceNodeById): newNode.metadata=${newNode.metadata}',
      );
      editor.document.replaceNodeById(selectedId, newNode);
      debugPrint('[PostWriteScreen] 노드 교체 완료');
    } else {
      // LinkNode 등 기타 노드는 기존 방식 유지
      debugPrint(
        '[PostWriteScreen] 노드 교체 실행 (ReplaceNodeRequest): newNode.metadata=${newNode.metadata}',
      );
      editor.execute([
        ReplaceNodeRequest(existingNodeId: selectedId, newNode: newNode),
      ]);
      debugPrint('[PostWriteScreen] 노드 교체 완료');
    }

    // 🎯 padding 변경을 히스토리에 저장
    final editorService = Provider.of<EditorService>(context, listen: false);
    editorService.saveHistoryNow();

    // 교체 후 확인
    final replacedNode = editor.document.getNodeById(selectedId);
    if (replacedNode != null) {
      debugPrint('[PostWriteScreen] 교체 후 노드 메타데이터: ${replacedNode.metadata}');
    }

    // ✅ 툴바 유지: 확장/축소 후에도 선택을 유지한다.
  }

  String _getNextPaddingMode(String current) {
    switch (current) {
      case 'full':
        return 'center';
      case 'center':
      default:
        return 'full';
    }
  }

  void _deleteNode(DocumentNode node, String selectedId) {
    // 🎯 중복 삭제 방지: 노드가 이미 삭제되었는지 확인
    if (document.getNodeById(selectedId) == null) {
      return; // 이미 삭제됨
    }

    assert(() {
      debugPrint(
        '[TrashDbg] deleteNode tapped: selectedId=$selectedId type=${node.runtimeType} docCount=${document.nodeCount}',
      );
      return true;
    }());

    // ✅ 정책: 사용자가 삭제(휴지통/범위삭제 등)로 업로드/압축 중 항목을 제거하면
    // 업로드/압축은 즉시 취소되고, undo/redo 히스토리에서도 완전 제거된다.
    // 여기서는 "삭제 전/후 히스토리 저장"과 "복원 방지 레지스트리 처리"만 보장한다.
    editorService.saveHistoryBeforeDelete();

    // 🎯 원자적 삭제: 레지스트리에서 먼저 제거하여 복원 방지
    editorService.removeSpecialNodeFromRegistry(
      selectedId,
      explicitlyDeleted: true,
    );

    try {
      nodeComponentService.selectNode(null);

      // ✅ 심각 버그 방지:
      // 문서에 Paragraph가 하나도 없는 상태에서 "마지막 특수노드"까지 삭제하면
      // 문서가 완전히 비어 커서를 둘 수 없는 상태가 된다.
      //
      // 따라서 "문서에 노드가 1개만 남았고, 그 노드가 지금 삭제 대상"인 경우에는
      // 삭제 + 빈 Paragraph 추가를 원자적으로 editor.execute로 수행한다.
      // (실제로는 삭제 대신 빈 Paragraph로 교체하여 결과적으로 문서는 비지 않게 만든다)
      final onlyNode = (document.nodeCount == 1) ? document.getNodeAt(0) : null;
      final isDeletingLastRemainingNode =
          onlyNode != null && onlyNode.id == selectedId;

      if (isDeletingLastRemainingNode) {
        final paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
        final trailing = ParagraphNode(
          id: paragraphId,
          text: AttributedText(''),
          metadata: <String, dynamic>{
            // ✅ 기존 문서/툴바에서 유지하던 "현재 정렬"을 그대로 승계
            'textAlign': editorService.currentParagraphAlign,
          },
        );

        exec() {
          editor.execute([
            ReplaceNodeRequest(existingNodeId: selectedId, newNode: trailing),
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: paragraphId,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.deleteContent,
              SelectionReason.userInteraction,
            ),
          ]);
        }

        exec();
        assert(() {
          debugPrint(
            '[TrashDbg] last-node delete done via ReplaceNodeRequest: oldId=$selectedId newParagraphId=$paragraphId',
          );
          return true;
        }());
      } else {
        // 🎯 일반 케이스: 노드 삭제 (삭제 전 다시 한 번 존재 확인)
        if (document.getNodeById(selectedId) != null) {
          document.deleteNode(selectedId);
        }
        assert(() {
          debugPrint('[TrashDbg] normal delete done: deletedId=$selectedId');
          return true;
        }());
      }

      // ✅ 휴지통 삭제는 DocumentChangeLog(NodeRemovedEvent)가 항상 EditorService까지 도달한다고 가정할 수 없어,
      // 여기서 직접 "업로드/압축 취소 + 히스토리 purge" 트랜잭션을 실행한다.
      // 단, 일부 환경에서는 NodeRemovedEvent 경로에서도 동일 트랜잭션이 실행될 수 있어
      // 중복 실행을 막기 위해 "현재 업로드/압축 중"일 때만 호출한다.
      if (UploadService().isBusyRef(selectedId)) {
        editorService.cancelAndPurgeIfUploading(<String>{selectedId});
      }

      // ✅ 안정성: 툴바 삭제 버튼은 여기서 명시적으로 after-state를 저장하여 undo 활성화를 보장한다.
      // (EditorService 쪽에서 동일 스냅샷이면 자동으로 중복 스킵됨)
      editorService.saveHistoryNow();
      assert(() {
        final exists = document.getNodeById(selectedId) != null;
        debugPrint(
          '[TrashDbg] after saveHistoryNow: deletedId=$selectedId stillExists=$exists',
        );
        return true;
      }());

      setState(() {});
    } catch (e) {
      // 🎯 에러 발생 시 레지스트리 및 명시적 삭제 목록 정리
      editorService.removeSpecialNodeFromRegistry(selectedId);
      ErrorHandler.showError(context, context.tr('cannot_delete'));
    }
  }

  /// 문서에서 첫 번째 이미지 URL 찾기
  String? _findFirstImageUrl() {
    try {
      final doc = editorService.document;
      for (int i = 0; i < doc.nodeCount; i++) {
        final node = doc.getNodeAt(i);

        // ImageNode인 경우
        if (node is ImageNode) {
          final url = node.imageUrl;
          if (url.isNotEmpty &&
              (url.startsWith('http://') || url.startsWith('https://'))) {
            return url;
          }
        }

        // ImageRowNode인 경우 (첫 번째 이미지 사용)
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
      debugPrint('[PostwriteScreen] 이미지 찾기 실패: $e');
    }
    return null;
  }

  /// 썸네일 편집 화면 열기 (수정 모드 전용)
  Future<void> _openThumbnailEditOverlay() async {
    if (widget.postId == null) return;

    // 🎯 build phase 완료 후 Navigator.push 호출 (OverlayPortalController 에러 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) => ThumbnailEditOverlay(
                postId: widget.postId!,
                sessionKey: currentDraftId ?? 'draft_temp',
                initialTitle: _serverAppliedTitle,
                initialSummary: _serverAppliedSummary,
                initialThumbnailUrl: _serverAppliedThumbnailUrl,
                onThumbnailChanged: (url) {
                  setState(() {
                    _serverAppliedThumbnailUrl = url;
                  });
                  _shouldRefreshMyFeed = true;
                },
                onMetadataChanged: (title, summary) {
                  setState(() {
                    _serverAppliedTitle = title;
                    _serverAppliedSummary = summary;
                  });
                  debugPrint(
                    '[PostwriteScreen] 썸네일 편집 화면에서 제목/요약 업데이트: title=$title, summary=$summary',
                  );
                  _shouldRefreshMyFeed = true;
                },
              ),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          opaque: false,
          // 🎯 배경 반투명 오버레이 제거
          barrierColor: Colors.transparent,
        ),
      );
    });
  }

  /// 수동 임시저장 (새 버전 생성)
  Future<bool> _saveDraft() async {
    try {
      // 🎯 임시저장 후 포커스 해제 (키보드가 올라오지 않도록)
      if (mounted) {
        _editorFocusNode.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      }

      // 🎯 본문 검증 (제목보다 먼저)
      final hasBody = editorService.hasNonEmptyBody(context: context);
      if (!hasBody) {
        if (mounted) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('enter_content_first'),
            message: context.tr('body_required'),
          );
        }
        return false;
      }

      // 🎯 제목 검증 (본문 검증 통과 후)
      // ✅ 정책: 제목은 "임시저장/Step1 입력"이 아니면 본문에서 추출하지 않는다.
      final titleMetadata = _extractDraftMetadata();
      final currentTitle = titleMetadata['title']!;

      if (currentTitle.trim().isEmpty) {
        if (mounted) {
          // 🎯 제목 입력 다이얼로그 표시
          final titleText = await DialogUtils.showTextInputDialog(
            context,
            title: context.tr('save_draft'),
            hintText: context.tr('title_required_for_draft'),
            confirmText: context.tr('save'),
            cancelText: context.tr('cancel'),
          );

          // 사용자가 취소하거나 빈 제목을 입력한 경우
          if (titleText == null || titleText.trim().isEmpty) {
            return false; // ✅ 실패 반환
          }
          // ✅ 제목은 본문 문서에 삽입하지 않고(인덱스 가정 제거), override로만 유지
          setState(() {
            _draftTitleOverride = titleText.trim();
          });
        } else {
          return false; // ✅ mounted가 아니면 실패 반환
        }
      }

      // 🎯 업로드/압축 중인 미디어가 있으면 차단
      if (editorService.hasUnuploadedMedia()) {
        if (mounted) {
          // 🎯 상세한 디버그 정보 출력 (kDebugMode에서만 실행)
          if (kDebugMode) {
            final activeTasks = editorService
                .debugDumpBusyMediaForCurrentDocument(
                  kinds: {
                    UploadKind.editorImage,
                    UploadKind.video,
                    UploadKind.drawing,
                  },
                );
            debugPrint(
              '[PostwriteScreen] ⚠️ 업로드/압축 진행 중 - 임시저장 차단\n$activeTasks',
            );
          }
          ErrorHandler.showError(context, context.tr('please_wait_for_upload'));
        }
        return false;
      }

      // 🎯 임시저장 제목/요약/썸네일:
      // - 다음(썸네일 편집)에서 편집한 값이 있으면 그 값을 우선
      // - 없으면 기존 정책대로 문서에서 추출/자동 설정
      final metadata = _extractDraftMetadata();
      final title = metadata['title']!;
      final summary = metadata['summary']!;
      final thumbnailUrl = metadata['thumbnailUrl']!;

      // 🎯 UUID 기반 draftId 사용 (제목 기반 제거)
      if (currentDraftId == null) {
        // 혹시 UUID가 없으면 생성 (안전장치)
        const uuid = Uuid();
        currentDraftId = 'draft_${uuid.v4()}';
        debugPrint('[PostwriteScreen] ⚠️ UUID가 없어서 생성: $currentDraftId');
      }

      // 현재 draft ID를 sessionKey로 영상 파일만 가져오기
      final sessionKey = currentDraftId!;

      final videoFilePath = nodeComponentService.getTempVideoFilePath(
        sessionKey,
      );
      final videoThumbnailPath = nodeComponentService.getTempVideoThumbnailPath(
        sessionKey,
      );

      // ✅ "작성하던 글이 있어요"로 들어온 경우: 자동저장을 임시저장 리스트로 이동
      // 현재 currentDraftId가 자동저장 ID인지 확인
      final autoDraft = await draftService.getAutoDraft();
      final bool isFromAutoDraft =
          autoDraft != null &&
          currentDraftId != null &&
          autoDraft.id == currentDraftId;

      // 🎯 UUID 기반 임시저장 (제목은 자동 추출)
      currentDraftId = await draftService.saveDraft(
        editorService: editorService,
        stickerService: stickerService,
        title: title,
        summary: summary,
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
        visibility: 'public', // 기본값
        selectedGroupIds: [],
        existingDraftId: currentDraftId, // UUID 기반 ID 사용
        textStylingService: textStylingService,
      );

      // ✅ 자동저장에서 온 경우, 명시적 임시저장 후 자동저장 삭제
      if (isFromAutoDraft) {
        await draftService.clearAutoDraft();
      }

      // 저장 스냅샷 마크
      editorService.markSavedSnapshot();
      stickerService.saveInitialState();
      // ✅ "명시적 임시저장" 완료 (autoDraft는 제외)
      _didExplicitDraftSave = true;

      if (mounted) {
        ErrorHandler.showInfo(context, context.tr('draft_saved'));
      }

      return true; // ✅ 성공 반환
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, context.tr('draft_save_failed'));
      }
      return false; // ✅ 실패 반환
    }
  }

  /// 수정된 포스트 저장 (편집 모드 전용)
  Future<void> _saveEditedPost() async {
    debugPrint('[PostwriteScreen] ===== 수정 완료 버튼 클릭 =====');

    // 이미 저장 중이면 무시
    if (_isSaving) return;

    // 업로드/압축 중인 미디어가 있으면 차단
    if (editorService.hasUnuploadedMedia()) {
      // 🎯 상세한 디버그 정보 출력 (kDebugMode에서만 실행)
      if (kDebugMode) {
        final activeTasks = editorService.debugDumpBusyMediaForCurrentDocument(
          kinds: {UploadKind.editorImage, UploadKind.video, UploadKind.drawing},
        );
        debugPrint('[PostwriteScreen] ⚠️ 업로드/압축 진행 중 - 수정 완료 차단\n$activeTasks');
      }
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('wait_for_media_upload'),
        message: context.tr('media_still_uploading'),
      );
      return;
    }

    // 변경사항 확인
    // 제목은 썸네일 편집 화면에서 입력하므로 원본 데이터 그대로 사용
    final originalForComparison = widget.exportedDataForEdit!;

    final hasChanges = ContentChangeDetector.hasContentChanged(
      originalExported: originalForComparison,
      editorService: editorService,
      stickerService: stickerService,
    );

    if (!hasChanges) {
      final bool hasMetadataChanges = _shouldRefreshMyFeed || _categoryChanged;
      debugPrint(
        '[PostwriteScreen][SAVE_EDIT] noContentChanges: hasMetadataChanges=$hasMetadataChanges shouldRefreshMyFeed=$_shouldRefreshMyFeed categoryChanged=$_categoryChanged',
      );
      // ✅ 메타데이터만 변경된 경우: result를 담아서 나가기
      if (hasMetadataChanges) {
        _cleanupAndExit();
        return;
      }
      // 변경사항이 없으면 조용히 나가기
      Navigator.of(context).pop();
      return;
    }

    // 3. 저장 중 상태로 변경
    setState(() => _isSaving = true);

    try {
      // 4. 현재 문서 상태를 export
      final exported = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
        forPublishing: true, // 🚀 임시저장도 네트워크 이미지로 변환 (로드 속도 향상)
        allowPartialUpload: true, // 🚀 임시저장 시 업로드 미완료 이미지 허용 (로컬 경로로 저장)
        textStylingService: textStylingService,
      );

      // 5. content 추출
      final content = exported['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw Exception('본문 데이터를 추출할 수 없습니다.');
      }

      // 6. 사용된 이미지/비디오 URL 수집
      final usedImageUrls = _collectUsedMediaUrls(exported);
      // 6-1. mentionedUsernames 수집 (멘션 메타 노드 우선)
      final mentionedUsernames = MentionedUsernamesExtractor.extractFromContent(
        content,
      );

      debugPrint('[PostwriteScreen] Export 완료');
      debugPrint('  - 사용된 미디어: ${usedImageUrls.length}개');
      debugPrint('  - 멘션: ${mentionedUsernames.length}명');

      // 7. 제목은 썸네일 편집 화면에서 입력하므로 여기서는 저장하지 않음

      // 8. 서버에 본문 업데이트 요청 (제목은 썸네일 편집 화면에서 별도로 저장)
      await BlogService().updatePostContent(
        postId: int.parse(widget.postId!),
        content: content,
        title: null, // 제목은 썸네일 편집 화면에서 입력
        usedImageUrls: usedImageUrls,
        mentionedUsernames: mentionedUsernames,
      );

      // 🎯 서버 업데이트 성공 후에만 실행
      debugPrint('[PostwriteScreen] ✅ 본문 수정 완료');

      // 10. 안정화 시간 (0.5초) 후 완료
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() => _isSaving = false);
        _shouldRefreshMyFeed = true;

        // 🎯 스티커 및 드로잉 데이터 정리
        try {
          stickerService.resetSession();
          debugPrint('[PostwriteScreen] 드로잉 캔버스 정리 완료');
        } catch (_) {}

        // 🎯 서버 업데이트 완료 후 pop (서버에서 최신 데이터 받아오도록)
        debugPrint('[PostwriteScreen] ✅ 수정 완료 - 로컬 exported 기반으로 즉시 반영');
        // ✅ PostExporter.exportToMap에는 title이 비어있을 수 있다(제목은 썸네일 오버레이에서 관리).
        // PostReader에서 merge 시 빈 title이 기존 title을 덮어쓰는 문제를 막기 위해,
        // pop payload에 "서버 적용된(title/summary/thumbnail)" 값을 강제로 포함한다.
        final exportedForPop = <String, dynamic>{
          ...Map<String, dynamic>.from(widget.exportedDataForEdit ?? const {}),
          ...Map<String, dynamic>.from(exported),
        };
        if ((_serverAppliedTitle ?? '').trim().isNotEmpty) {
          exportedForPop['title'] = _serverAppliedTitle!.trim();
        }
        if ((_serverAppliedSummary ?? '').trim().isNotEmpty) {
          exportedForPop['summary'] = _serverAppliedSummary!.trim();
        }
        if ((_serverAppliedThumbnailUrl ?? '').trim().isNotEmpty) {
          exportedForPop['thumbnailImageUrl'] =
              _serverAppliedThumbnailUrl!.trim();
        }
        debugPrint(
          '[PostwriteScreen][POP] exportedForPop.title=${exportedForPop['title']} (serverAppliedTitle=$_serverAppliedTitle) exported.title=${exported['title']}',
        );
        Navigator.of(context).pop(<String, dynamic>{
          'didEdit': true,
          'postId': widget.postId,
          // ✅ 서버 재조회 없이, 방금 export한 로컬 데이터로 PostReader를 갱신한다.
          'exported': exportedForPop,
          'content': content,
        });
      }
    } catch (e) {
      debugPrint('[PostwriteScreen] ❌ 본문 수정 실패: $e');

      // 저장 중 상태 해제
      if (mounted) {
        setState(() => _isSaving = false);
        // 🎯 실패 UX: 스낵바 대신 재시도/취소/임시저장 바텀시트
        final action = await RetryCancelBottomSheet.show(
          context,
          title: context.tr('edit_failed_title'),
          error: e,
          showSaveDraft: true,
        );
        if (!mounted) return;
        if (action == RetryCancelAction.retry) {
          await _saveEditedPost();
        } else if (action == RetryCancelAction.saveDraft) {
          await _saveDraftFromEditFailure();
        }
      }
    } finally {}
  }

  /// 수정 실패 시 임시저장
  Future<void> _saveDraftFromEditFailure() async {
    try {
      debugPrint('[PostwriteScreen] 수정 실패 → 임시저장 시작');

      // 1. 메타데이터 추출 (서버에 적용된 값 우선)
      String title = _serverAppliedTitle ?? '';
      String summary = _serverAppliedSummary ?? '';
      String thumbnailUrl = _serverAppliedThumbnailUrl ?? '';

      // 제목/요약이 없으면 빈 문자열로 처리 (임시저장은 제목 필수이므로)
      if (title.trim().isEmpty) {
        title = context.tr('no_title');
      }
      if (summary.trim().isEmpty) {
        summary = '';
      }
      if (thumbnailUrl.trim().isEmpty) {
        // 첫 이미지 찾기
        final firstImageUrl = _findFirstImageUrl();
        if (firstImageUrl != null && firstImageUrl.isNotEmpty) {
          thumbnailUrl = firstImageUrl;
        }
      }

      // 3. draftId 생성 (편집 모드에서는 새 임시저장)
      const uuid = Uuid();
      final draftId = 'draft_${uuid.v4()}';

      // 4. 영상 파일 경로 (편집 모드에서는 일반적으로 없음)
      final sessionKey = draftId;
      final videoFilePath = nodeComponentService.getTempVideoFilePath(
        sessionKey,
      );
      final videoThumbnailPath = nodeComponentService.getTempVideoThumbnailPath(
        sessionKey,
      );

      // 5. 임시저장
      await draftService.saveDraft(
        editorService: editorService,
        stickerService: stickerService,
        title: title,
        summary: summary,
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
        visibility: _editVisibility,
        selectedGroupIds: _editGroupIds,
        existingDraftId: draftId,
        textStylingService: textStylingService,
      );

      if (mounted) {
        ErrorHandler.showInfo(context, context.tr('draft_saved'));
        debugPrint('[PostwriteScreen] ✅ 수정 실패 → 임시저장 완료');
      }
    } catch (e) {
      debugPrint('[PostwriteScreen] ❌ 수정 실패 → 임시저장 실패: $e');
      if (mounted) {
        ErrorHandler.showError(context, context.tr('draft_save_failed'));
      }
    }
  }

  /// 사용된 이미지/비디오 URL 수집
  /// PostExporter와 동일한 로직 사용
  List<String> _collectUsedMediaUrls(Map<String, dynamic> exported) {
    final Set<String> usedUrls = <String>{};

    try {
      // content의 nodes에서 이미지/비디오 URL 수집
      final dynamic content = exported['content'];
      final List<dynamic> nodes =
          (content is Map)
              ? List<dynamic>.from(content['nodes'] as List? ?? const [])
              : const [];

      debugPrint('[PostwriteScreen] URL 수집 시작 (노드 개수: ${nodes.length})');

      for (int i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        if (n is! Map) continue;

        final String type = (n['type'] ?? '').toString();
        debugPrint('  - 노드[$i] 타입: $type');

        if (type == 'image') {
          // data.url 또는 url 필드에서 추출
          final data = n['data'] as Map<String, dynamic>?;
          final String url = (data?['url'] ?? n['url'] ?? '').toString();
          if (url.isNotEmpty) {
            usedUrls.add(url);
            debugPrint('    → 이미지 URL 추가: $url');
          }
        } else if (type == 'imageRow') {
          // urls 필드에서 추출
          final List<dynamic> urls = List<dynamic>.from(n['urls'] ?? const []);
          for (final u in urls) {
            final String url = u.toString();
            if (url.isNotEmpty) {
              usedUrls.add(url);
              debugPrint('    → 이미지행 URL 추가: $url');
            }
          }
        } else if (type == 'video' || type == 'clip') {
          // data.url에서 추출 (비디오도 usedImageUrls에 포함!)
          final data = n['data'] as Map<String, dynamic>?;
          final String url = (data?['url'] ?? '').toString();
          if (url.isNotEmpty) {
            usedUrls.add(url);
            debugPrint('    → 비디오 URL 추가: $url');
          }
        }
      }

      // 🎯 스티커에서 이미지 URL 수집 (PNG 드로잉 포함)
      // 🎯 스티커는 exported['content']['stickers']에 있음 (exported['stickers']가 아님!)
      final contentStickers =
          (content is Map ? (content['stickers'] as List?) : null) ?? const [];
      debugPrint('  - 스티커 개수: ${contentStickers.length}');
      for (final sticker in contentStickers) {
        if (sticker is! Map) continue;
        final stickerType = (sticker['type'] ?? '').toString();
        if (stickerType == 'image') {
          final stickerContent = sticker['content'];
          String? url;

          if (stickerContent is Map) {
            // ✅ URL + 크기 정보 (PNG 드로잉) 또는 레거시 {url: ...}
            url = (stickerContent['url'] ?? '').toString();
          } else if (stickerContent is String) {
            // 레거시: content가 직접 URL 문자열인 경우
            url = stickerContent;
          }

          if (url != null && url.isNotEmpty) {
            // HTTP URL인지 확인 (로컬 파일 경로 제외)
            if (url.startsWith('http://') || url.startsWith('https://')) {
              usedUrls.add(url);
              debugPrint('    → 스티커 URL 추가: $url');
            } else {
              debugPrint('    → 스티커 URL이 HTTP가 아님 (로컬 파일?): $url');
            }
          } else {
            debugPrint('    → 스티커 URL이 비어있음: content=$stickerContent');
          }
        }
      }

      debugPrint('[PostwriteScreen] ✅ 총 수집된 미디어 URL: ${usedUrls.length}개');
      if (usedUrls.isNotEmpty) {
        for (final url in usedUrls) {
          debugPrint('  - $url');
        }
      }
    } catch (e) {
      debugPrint('[PostwriteScreen] 미디어 URL 수집 실패: $e');
    }

    return usedUrls.toList();
  }

  /// 임시저장 목록 보기
  Future<void> _showDraftList() async {
    try {
      if (!mounted) return;

      // 🎯 툴바의 오른쪽 끝 화살표를 눌렀을 때와 완전히 같은 방식으로 키보드 닫기
      _editorFocusNode.unfocus();

      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder:
              (_, __, ___) => DraftListOverlay(
                currentDraftId: currentDraftId,
                onLoadDraft: (draftId) async {
                  try {
                    nodeComponentService.clearHighlightedSelectionSilently();
                    nodeComponentService.clearSelectionSilently();
                    composer.clearSelection();

                    // 🎯 포커스 해제
                    _editorFocusNode.unfocus();
                    FocusManager.instance.primaryFocus?.unfocus();
                  } catch (_) {}

                  final draft = await draftService.loadDraft(
                    draftId: draftId,
                    editorService: editorService,
                    stickerService: stickerService,
                    nodeComponentService: nodeComponentService,
                    dragService: dragService,
                    textStylingService: textStylingService,
                  );

                  if (draft != null && mounted) {
                    setState(() {
                      currentDraftId = draftId;
                    });

                    // ✅ Step1 메타데이터도 함께 복원 (제목/요약/썸네일)
                    _restoreDraftMetadata(
                      title: draft.title,
                      summary: draft.summary,
                      thumbnailUrl: draft.thumbnailUrl,
                    );

                    // 🎯 불러온 상태를 저장 스냅샷으로 간주
                    editorService.markSavedSnapshot();
                    stickerService.saveInitialState();

                    // 🎯 포커스 확실히 해제
                    _editorFocusNode.unfocus();
                    FocusManager.instance.primaryFocus?.unfocus();

                    // (빈 상태는 build()에서 derived state로 동기화하므로 별도 토글 불필요)

                    // 🎯 SuperEditor가 build에서 직접 생성되므로 setState로 자동 rebuild됨
                    // 레이아웃 캐시 무효화는 불필요 (자동 재계산됨)
                  } else if (mounted) {
                    ErrorHandler.showError(
                      context,
                      context.tr('draft_load_failed'),
                    );
                  }
                },
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // ✅ 페이드인/아웃만 적용 (슬라이드 제거)
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          '${context.tr('draft_list_failed')}: $e',
        );
      }
    }
  }
}

/// 🎯 성능 최적화: bottomNavigationBar를 별도 위젯으로 분리
/// 키보드 높이를 파라미터로 받아 MediaQuery 접근 최소화
class _BottomBar extends StatelessWidget {
  final double keyboardHeight;
  final ValueNotifier<bool> keyboardVisibleNotifier;
  final TextStylingService textStylingService;
  final EditorService editorService;
  final ScrollController scrollController;
  final VoidCallback onDismissKeyboard;
  final VoidCallback onShowDraftList;
  final ValueNotifier<bool> videoUploadIndicatorNotifier;
  final NodeComponentService nodeComponentService;
  final Document document;
  final void Function(String selectedId, DocumentNode node) onEditImage;
  final void Function(DocumentNode node, String selectedId) onDeleteNode;
  final Future<void> Function(DocumentNode node, String selectedId)
  onChangeMediaAlignment;
  // ✅ 미디어 추가 시 빈 상태 오버레이를 숨기기 위한 콜백
  final VoidCallback? onMediaAdded;

  const _BottomBar({
    required this.keyboardHeight,
    required this.keyboardVisibleNotifier,
    required this.textStylingService,
    required this.editorService,
    required this.scrollController,
    required this.onDismissKeyboard,
    required this.onShowDraftList,
    required this.videoUploadIndicatorNotifier,
    required this.nodeComponentService,
    required this.document,
    required this.onEditImage,
    required this.onDeleteNode,
    required this.onChangeMediaAlignment,
    this.onMediaAdded,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<StickerService>(
      builder: (context, stickerService, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: stickerService.isDraggingNotifier,
          builder: (context, isDragging, child) {
            // 🎯 키보드 높이를 파라미터로 받아 MediaQuery 접근 제거
            // ✅ 키보드가 내려가는 애니메이션 중(viewInsets가 감소),
            // safe-area(bottom padding)보다 더 아래로 내려갔다가 다시 올라오는 "튐"이 생길 수 있음.
            // 그래서 "키보드 높이 vs safe-area" 중 더 큰 값을 사용해,
            // safe-area 위치에 도달하면 더 이상 내려가지 않게 만든다.
            final safeBottom = MediaQuery.paddingOf(context).bottom;
            final bottomPadding =
                keyboardHeight > safeBottom ? keyboardHeight : safeBottom;
            final theme = Theme.of(context);

            final Widget bar = Container(
              color: theme.colorScheme.background,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: Selector<NodeComponentService, String?>(
                  selector: (_, service) => service.selectedNodeId,
                  builder: (context, selectedId, _) {
                    final Widget toolbar;
                    if (selectedId != null) {
                      final node = document.getNodeById(selectedId);
                      if (node == null) return const SizedBox.shrink();
                      toolbar = SelectedToolbar(
                        // ✅ 같은 "SelectedToolbar" 내에서 선택 노드가 바뀌는 건
                        // 애니메이션이 과해보일 수 있으므로 key는 타입 기반으로 고정.
                        // (Selected ↔ Default 전환에서만 AnimatedSwitcher가 동작)
                        key: const ValueKey('selected_toolbar'),
                        node: node,
                        selectedId: selectedId,
                        onEdit: () => onEditImage(selectedId, node),
                        onDelete: onDeleteNode,
                        onChangeAlignment: onChangeMediaAlignment,
                        onEditMention: (nodeId, usernames) {
                          // 멘션 편집 오버레이 열기
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              opaque: false,
                              barrierDismissible: true,
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                              pageBuilder:
                                  (_, __, ___) => MentionOverlay(
                                    initialUsernames:
                                        usernames, // 편집 시 초기 선택된 사용자들 전달
                                    onClose: () {},
                                    onSelect: (username) {},
                                    onSubmit: (newUsernames) {
                                      editorService.updateMentionNode(
                                        nodeId,
                                        newUsernames,
                                      );
                                      // 노드가 업데이트되고 렌더링이 완료된 후 부드럽게 닫기
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            Future.delayed(
                                              const Duration(milliseconds: 150),
                                              () {
                                                final mounted = context.mounted;
                                                if (!mounted) return;
                                                try {
                                                  editorService.editor.composer
                                                      .clearSelection();
                                                  context
                                                      .read<
                                                        NodeComponentService
                                                      >()
                                                      .setSelectedNode(nodeId);
                                                } catch (_) {}
                                                Navigator.of(
                                                  context,
                                                ).maybePop();
                                              },
                                            );
                                          });
                                    },
                                  ),
                            ),
                          );
                        },
                        editorService: editorService,
                      );
                    } else {
                      // 🎯 keyboardVisibleNotifier는 상위에서 생성되어 전달됨 (매 build마다 생성하지 않음)
                      toolbar = DefaultToolbar(
                        key: const ValueKey('default_toolbar'),
                        stylingService: textStylingService,
                        editorService: editorService,
                        scrollController: scrollController,
                        keyboardVisibleNotifier: keyboardVisibleNotifier,
                        onDismissKeyboard: onDismissKeyboard,
                        onShowDraftList: onShowDraftList,
                        videoUploadIndicatorNotifier:
                            videoUploadIndicatorNotifier,
                        uploadRefId:
                            'editor_${editorService.hashCode}', // ✅ 드로잉 업로드 refId
                        onMediaAdded: onMediaAdded, // ✅ 미디어 추가 시 빈 상태 오버레이 숨기기
                      );
                    }

                    // ✅ 툴바 전환(선택됨 ↔ 기본)을 과하지 않게 부드럽게
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        return FadeTransition(
                          opacity: anim,
                          child: SizeTransition(
                            sizeFactor: anim,
                            axis: Axis.vertical,
                            axisAlignment: -1,
                            child: child,
                          ),
                        );
                      },
                      child: toolbar,
                    );
                  },
                ),
              ),
            );

            // ✅ 스티커 드래그 중이면 "숨김" 대신 아래로 부드럽게 내려가며 사라지게
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final offsetAnim = Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: offsetAnim, child: child),
                );
              },
              child:
                  isDragging
                      ? const SizedBox(key: ValueKey('bottom_bar_hidden'))
                      : KeyedSubtree(
                        key: const ValueKey('bottom_bar_visible'),
                        child: bar,
                      ),
            );
          },
        );
      },
    );
  }
}
