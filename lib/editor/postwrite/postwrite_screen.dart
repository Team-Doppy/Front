import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../upload/service/upload_service.dart';
import '../../upload/service/upload_service_interface.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/component/divider_component.dart';
import '../../editor/component/link_component.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/paragraph_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/component/single_image_component.dart';
import '../../editor/config/editor_config.dart';
import '../../editor/data/draft.dart';
import '../../editor/widgets/selection_box_caret_overlay.dart';
import '../../editor/service/draft_service.dart';
import '../../editor/service/drag_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/service/document_restore_service.dart';
import '../../editor/style/style_sheet.dart';
import '../../editor/style/text_styling_service.dart';
import '../../editor/utils/dialog_util.dart';
import '../utils/editor_localization.dart';
import '../../editor/postwrite/postwrite_screen_lifecycle.dart';
import '../../editor/postwrite/postwrite_screen_exit.dart';
import '../../editor/postwrite/postwrite_screen_autosave.dart';
import '../../editor/postwrite/postwrite_screen_ui.dart';
import '../../editor/postwrite/postwrite_screen_draft.dart';
import '../../editor/postwrite/postwrite_appbar.dart';
import '../../editor/postwrite/postwrite_bottombar.dart';
import '../../editor/widgets/draft_list_widget.dart';
import '../../editor/widgets/resume_writing_bottom_sheet.dart';
import '../../editor/utils/snackbar_util.dart';
import '../../editor/utils/scrollbar_util.dart';
import '../../editor/utils/backspace_empty_list_keyboard_action.dart';
import 'package:super_editor/super_editor.dart';

class PostwriteScreen extends StatefulWidget {
  final bool enableAutoSave;
  final DraftData? draftData;
  final bool disableAutoFocus;

  /// 진입 시 에디터에 포커스를 주어 키보드를 자동으로 올릴지 여부. 기본값 true.
  final bool autoShowKeyboardOnEntry;
  final Duration? autoSaveInterval;

  /// true: UploadService 연동(업로드/실패 시 노드 제거 포함) + 발행 시 네트워크 URL 기준 export
  /// false: 업로드 없이 로컬 경로를 페이로드에 포함 + 드래그/이동 UX를 로컬 기준으로 활성화
  final bool networkMode;

  final UploadService uploadService;

  /// 발행 시 호출 (모든 파라미터 필수)
  final OnPublishCallback? onPublish;

  /// true면 수정 모드(기존 포스트 편집). 콜백에 isEditMode/existingPostId 전달됨.
  final bool isEditMode;

  const PostwriteScreen({
    super.key,
    this.draftData,
    this.autoSaveInterval,
    this.enableAutoSave = true,
    this.disableAutoFocus = false,
    this.autoShowKeyboardOnEntry = true,
    this.networkMode = false,
    required this.uploadService,
    this.onPublish,
    this.isEditMode = false,
  });

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen>
    with
        PostwriteScreenLifecycle,
        PostwriteScreenExit,
        PostwriteScreenAutoSave,
        PostwriteScreenUI,
        PostwriteScreenDraft {
  // draft id
  String? currentDraftId;
  //super_editor
  late final Editor editor;
  late final MutableDocument document;
  late final FocusNode _editorFocusNode;
  late final MutableDocumentComposer composer;

  //service
  late final DragService dragService;
  late final DraftService draftService;
  late final EditorService editorService;
  late final TextStylingService textStylingService;
  late final NodeComponentService nodeComponentService;

  //overlay
  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();

  // editor layout key
  final GlobalKey _editorBodyStackKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  // scroll
  ScrollController scrollController = ScrollController();

  // draft save
  Timer? _autoSaveTimer;

  // Getters for mixins
  @override
  Timer? get autoSaveTimer => _autoSaveTimer;

  @override
  set autoSaveTimer(Timer? value) => _autoSaveTimer = value;

  @override
  FocusNode get editorFocusNode => _editorFocusNode;

  @override
  ValueNotifier<bool> get keyboardVisibleNotifier => _keyboardVisibleNotifier;

  @override
  Duration? get autoSaveInterval => widget.autoSaveInterval;

  @override
  bool get enableAutoSave => widget.enableAutoSave && !widget.isEditMode;

  @override
  bool get networkMode => widget.networkMode;

  @override
  GlobalKey get editorBodyStackKey => _editorBodyStackKey;

  Future<void> Function({
    required bool forceAutoDraftIfChanged,
    required bool clearAutoDraft,
  })
  get exitEditor => _exitEditor;

  @override
  Future<bool> Function() get saveDraft => _saveDraft;

  @override
  bool get isEditMode => widget.isEditMode;

  @override
  VoidCallback get onNodeSelectionChangedCallback => _onNodeSelectionChanged;

  @override
  DraftData? get initialDraftData => widget.draftData;

  // 🎯 성능 최적화: keyboardVisibleNotifier를 한 번만 생성하고 값만 갱신
  late final ValueNotifier<bool> _keyboardVisibleNotifier;

  @override
  void initState() {
    super.initState();

    // draftData restore
    if (widget.draftData != null) {
      final documentRestoreService = DocumentRestoreService();
      document = documentRestoreService.restoreFromDraftData(widget.draftData!);
    } else {
      document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'madebyJaehun',
            text: AttributedText(''),
            metadata: {
              'textAlign': 'left',
              EditorConfig.titleNodeMetadataKey: true,
            },
          ),
        ],
      );
    }
    _editorFocusNode = FocusNode(debugLabel: 'editor_focus');
    _keyboardVisibleNotifier = ValueNotifier<bool>(false);

    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    // service setup1
    editorService = EditorService(
      editor: editor,
      document: document,
      useExternalTitleField: true,
      networkMode: widget.networkMode,
    );
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    draftService = DraftService();
    nodeComponentService = NodeComponentService();
    textStylingService = TextStylingService(editor: editor, composer: composer);

    // service setup2
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    editorService.setScrollController(scrollController);
    textStylingService.setEditorService(editorService);
    dragService.attachScrollController(scrollController);

    // global text styling service
    setGlobalTextStylingService(textStylingService);

    // draftId setup
    currentDraftId = DocumentRestoreService.getOrCreateDraftId(
      widget.draftData,
    );

    // listener setup
    nodeComponentService.addListener(onNodeSelectionChangedCallback);

    // auto save start
    if (widget.enableAutoSave) {
      startAutoSave();
    }

    // mark saved snapshot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editorService.markSavedSnapshot();
    });

    // 진입 시 자동 키보드 상승 (이전에 작성하던 글이 있으면 키보드 올리지 않음)
    if (widget.autoShowKeyboardOnEntry && widget.draftData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editorFocusNode.canRequestFocus) {
          _editorFocusNode.requestFocus();
        }
      });
    }

    // 초기 draftData가 있으면 ResumeWritingBottomSheet 먼저 표시 (수정 모드에서는 생략)
    if (widget.draftData != null && !widget.isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showResumeWritingSheetForInitialDraft();
      });
    }
  }

  Future<void> _showResumeWritingSheetForInitialDraft() async {
    if (widget.draftData == null) return;
    final draft = widget.draftData!;

    final choice = await ResumeWritingBottomSheet.show(
      context,
      title: draft.title,
    );
    if (!mounted) return;
    if (choice == null) return;

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (choice == ResumeWritingChoice.resume) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editorFocusNode.requestFocus();
      });
    } else if (choice == ResumeWritingChoice.newDraft) {
      await draftService.clearAutoDraft();
      await draftService.loadEmptyDocument(
        editorService: editorService,
        nodeComponentService: nodeComponentService,
        dragService: dragService,
      );
      if (!mounted) return;
      setState(() {
        currentDraftId = DocumentRestoreService.getOrCreateDraftId(null);
      });
      editorService.markSavedSnapshot();

      // 에디터 리빌드 완료 후 포커스(키보드 상승)

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editorFocusNode.requestFocus();
      });
    }
  }

  // node selection changed listener for keyboard hide
  void _onNodeSelectionChanged() {
    onNodeSelectionChanged();
  }

  Stylesheet _buildStylesheet(BuildContext context) {
    return buildStylesheet(context);
  }

  Future<void> _exitEditor({
    required bool forceAutoDraftIfChanged,
    required bool clearAutoDraft,
  }) async {
    await performExitEditor(
      forceAutoDraftIfChanged: forceAutoDraftIfChanged,
      clearAutoDraft: clearAutoDraft,
    );
  }

  void _handleTapBelowLastSpecialNode(Offset globalPosition) {
    handleTapBelowLastSpecialNode(globalPosition);
  }

  Future<bool> _handleWillPop() async {
    return await handleWillPop();
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 키보드 상태 실시간 감지 및 업데이트
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_keyboardVisibleNotifier.value != isKeyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _keyboardVisibleNotifier.value = isKeyboardVisible;
        }
      });
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UploadService>.value(
          value: widget.uploadService,
        ),
        ChangeNotifierProvider<IUploadService>.value(
          value: widget.uploadService,
        ),
        ChangeNotifierProvider.value(value: editorService),
        ChangeNotifierProvider.value(value: dragService),
        ChangeNotifierProvider.value(value: textStylingService),
        ChangeNotifierProvider.value(value: nodeComponentService),
      ],
      child: Builder(
        builder: (providerContext) {
          editorService.setContext(providerContext);
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              // canPop: false이므로 didPop은 항상 false (팝이 막혀 있음)
              // 사용자가 뒤로가기 시도 시 나가기 로직(다이얼로그 등) 실행
              if (!didPop) {
                await _handleWillPop();
              }
            },

            child: Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: Theme.of(context).colorScheme.surface,
              appBar: PostwriteAppBar(
                editorService: editorService,
                networkMode: widget.networkMode,
                onSaveDraft: _saveDraft,
                onLoadDraft: _showDraftList,
                draftData: getCurrentDraftData(),
                onPublish: widget.onPublish,
                isEditMode: widget.isEditMode,
                existingPostId: widget.isEditMode ? widget.draftData?.id : null,
              ),
              body: Stack(
                key: _editorBodyStackKey,
                clipBehavior: Clip.none,
                children: [
                  ScrollbarUtil.buildScrollbar(
                    controller: scrollController,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (details) {
                        _handleTapBelowLastSpecialNode(details.position);
                      },
                      // 슈퍼에디터 렌더링
                      child: Builder(
                        builder: (context) {
                          final isDarkMode =
                              Theme.of(context).brightness == Brightness.dark;
                          final screenWidth = MediaQuery.sizeOf(context).width;
                          final handleColor = Theme.of(
                            context,
                          ).colorScheme.primary;
                          return RepaintBoundary(
                            child: ValueListenableBuilder<int>(
                              valueListenable:
                                  editorService.historyRestoreVersion,
                              builder: (_, version, __) => _EditorWithHandleColor(
                                handleColor: handleColor,
                                child: KeyedSubtree(
                                  key: ValueKey('editor_$version'),
                                  child: SuperEditor(
                                    gestureMode: Platform.isIOS
                                        ? DocumentGestureMode.iOS
                                        : DocumentGestureMode.android,
                                    editor: editor,
                                    focusNode: _editorFocusNode,
                                    keyboardActions: [
                                      backspaceClearEmptyListParagraphWhenFirstNode,
                                      ...defaultKeyboardActions,
                                    ],
                                    stylesheet: _buildStylesheet(context),
                                    selectionStyle: SelectionStyles(
                                      selectionColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.3),
                                      highlightEmptyTextBlocks: false,
                                    ),
                                    documentLayoutKey: _documentLayoutKey,
                                    scrollController: scrollController,
                                    documentOverlayBuilders: [
                                      const SuperEditorIosToolbarFocalPointDocumentLayerBuilder(),
                                      SuperEditorIosHandlesDocumentLayerBuilder(
                                        handleColor: handleColor,
                                        caretWidth: 0,
                                      ),
                                      const SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder(),
                                      SuperEditorAndroidHandlesDocumentLayerBuilder(
                                        caretColor: handleColor,
                                        caretWidth: 0,
                                      ),
                                      SelectionBoxCaretOverlayBuilder(
                                        caretStyle: CaretStyle(
                                          width: 2,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
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
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // 드래그 오버레이
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: dragService,
                      builder: (context, _) {
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
                                  !_keyboardVisibleNotifier.value)
                              ? Stack(children: [buildDragOverlay()])
                              : const SizedBox.shrink(key: ValueKey('empty')),
                        );
                      },
                    ),
                  ),
                ],
              ),

              bottomNavigationBar: PostwriteBottomBar(
                document: document,
                editorService: editorService,
                scrollController: scrollController,
                textStylingService: textStylingService,
                nodeComponentService: nodeComponentService,
                keyboardVisibleNotifier: _keyboardVisibleNotifier,
                onDismissKeyboard: () {
                  dismissKeyboard();
                },
                onDeleteNode: _deleteNode,
                onShowDraftList: _showDraftList,
                onEditImage: (selectedId, node) {
                  nodeComponentService.editImage(
                    context: context,
                    imageId: selectedId,
                    node: node,
                    editorService: editorService,
                    document: document,
                  );
                },
                onChangeMediaAlignment: _changeMediaAlignment,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 미디어(이미지/영상) 정렬 변경
  Future<void> _changeMediaAlignment(
    DocumentNode node,
    String selectedId,
  ) async {
    editorService.changeNodePadding(selectedId, null);
  }

  void _deleteNode(DocumentNode node, String selectedId) {
    editorService.deleteNode(
      selectedId,
      onNodeSelected: (nodeId) => nodeComponentService.selectNode(nodeId),
    );
  }

  /// 수동 임시저장 (새 버전 생성)
  Future<bool> _saveDraft() async {
    if (mounted) {
      _editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }

    return await saveDraftWithValidation(
      onShowBodyRequiredDialog: () async {
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('editor_content_required'),
          message: context.tr('editor_body_required'),
        );
      },
      onShowTitleInputDialog: () async {
        final titleText = await DialogUtils.showTextInputDialog(
          context,
          title: context.tr('editor_save_draft'),
          hintText: context.tr('editor_title_required'),
          confirmText: context.tr('editor_save'),
          cancelText: context.tr('editor_cancel'),
        );
        return titleText?.trim();
      },
      onDraftIdChanged: (id) {
        if (mounted) {
          setState(() {
            currentDraftId = id;
          });
        }
      },
      onSuccess: () {
        SnackbarUtil.showInfo(context, context.tr('editor_draft_saved'));
      },
      onError: () {
        SnackbarUtil.showError(context, context.tr('editor_draft_save_failed'));
      },
    );
  }

  /// 임시저장 목록 보기
  Future<void> _showDraftList() async {
    try {
      if (!mounted) return;
      _editorFocusNode.unfocus();

      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder: (_, __, ___) => DraftListWidget(
            currentDraftId: currentDraftId,
            onLoadDraft: (draftId) async {
              await handleDraftLoaded(
                draftId: draftId,
                onDraftIdChanged: (id) {
                  if (mounted) {
                    setState(() {
                      currentDraftId = id;
                    });
                  }
                },
                onError: () {
                  SnackbarUtil.showError(
                    context,
                    context.tr('editor_draft_load_failed'),
                  );
                },
              );
            },
          ),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        SnackbarUtil.showError(context, context.tr('editor_draft_list_failed'));
      }
    }
  }
}

/// SuperEditor를 감싸서 다크모드에서도 셀렉션 핸들 색상이 테마 primary에 맞게 표시되도록 합니다.
class _EditorWithHandleColor extends StatefulWidget {
  const _EditorWithHandleColor({
    required this.handleColor,
    required this.child,
  });

  final Color handleColor;
  final Widget child;

  @override
  State<_EditorWithHandleColor> createState() => _EditorWithHandleColorState();
}

class _EditorWithHandleColorState extends State<_EditorWithHandleColor> {
  late final SuperEditorAndroidControlsController _androidController;
  late final SuperEditorIosControlsController _iosController;

  @override
  void initState() {
    super.initState();
    _androidController = SuperEditorAndroidControlsController(
      controlsColor: widget.handleColor,
    );
    _iosController = SuperEditorIosControlsController(
      handleColor: widget.handleColor,
    );
  }

  @override
  void didUpdateWidget(_EditorWithHandleColor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handleColor != widget.handleColor) {
      _androidController.dispose();
      _iosController.dispose();
      _androidController = SuperEditorAndroidControlsController(
        controlsColor: widget.handleColor,
      );
      _iosController = SuperEditorIosControlsController(
        handleColor: widget.handleColor,
      );
    }
  }

  @override
  void dispose() {
    _androidController.dispose();
    _iosController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SuperEditorAndroidControlsScope(
      controller: _androidController,
      child: SuperEditorIosControlsScope(
        controller: _iosController,
        child: widget.child,
      ),
    );
  }
}
