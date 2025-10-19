import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/title_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
// removed unused image editor imports after simplifying selected toolbar
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/sticker_canvas.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/save_draft_overlay.dart';
import 'package:doppy/editor/overlay/draft_list_overlay.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/image/custom_image_editor_screen.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, imageRow, location, unknown }

class PostwriteScreen extends StatefulWidget {
  final double screenWidth;
  final Map<String, dynamic>? initialExported; // 기존 글 불러오기용
  final bool isEditMode; // 수정 모드 여부
  final String? postId; // 수정할 포스트 ID

  const PostwriteScreen({
    super.key,
    required this.screenWidth,
    this.initialExported,
    this.isEditMode = false,
    this.postId,
  });

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen> {
  late final Editor editor;
  late final MutableDocument document;
  late final MutableDocumentComposer composer;
  late final FocusNode _editorFocusNode;

  //service
  late final EditorService editorService;
  late final DragService dragService;
  late final DraftService draftService;
  late final TextStylingService textStylingService;

  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  ScrollController scrollController = ScrollController();
  Offset? _lastTapPosition; // 마지막 탭 위치 저장
  bool _isKeyboardVisible = false; // 키보드 표시 상태

  // 임시저장 관련
  String? _currentDraftId;
  // StickerCanvas는 화면 Stack 내에 부착 (기타 오버레이보다 아래)

  @override
  void initState() {
    super.initState();

    document = MutableDocument(
      nodes: [
        ParagraphNode(
          id: '1',
          text: AttributedText(''),
          metadata: {'isTitle': true, 'textAlign': 'center'},
        ),
        ParagraphNode(
          id: '2',
          text: AttributedText(''),
          metadata: {'textAlign': 'center'},
        ),
      ],
    );
    composer = MutableDocumentComposer();

    // FocusNode 초기화
    _editorFocusNode = FocusNode(debugLabel: 'editor_focus');

    // 키보드 상태 감지
    _editorFocusNode.addListener(_onFocusChange);

    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(editor: editor, document: document);
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    textStylingService = TextStylingService(editor: editor, composer: composer);
    // 전역 스타일링 서비스 설정 (렌더링용)
    setGlobalTextStylingService(textStylingService);
    // ImageService는 build 메서드에서 설정
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    dragService.attachScrollController(scrollController);
    dragService.addListener(_onDragChange);

    // 임시저장 서비스 초기화
    draftService = DraftService();
    _initializeDraft();

    // 초기 콘텐츠가 전달되었다면 문서를 교체하여 불러오기
    try {
      final initData = widget.initialExported;
      if (initData != null) {
        final newDoc = _rebuildDocument(initData);
        _replaceDocumentSafely(newDoc);
      }
    } catch (_) {}

    // 선택 범위가 바뀔 때 이미지 하이라이트 갱신
    composer.selectionNotifier.addListener(_updateImageSelectionHighlight);

    // 문서 변경 시 다음 버튼 상태 업데이트
    editorService.addListener(_onEditorServiceChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateImageSelectionHighlight();
      // 초기 진입 시 제목 아래 문단(id: '2')로 커서 이동 및 포커스 요청
      final node = document.getNodeById('2');
      if (node is ParagraphNode) {
        final offset = node.text.text.length;
        composer.setSelectionWithReason(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: offset),
            ),
          ),
          SelectionReason.userInteraction,
        );
      }
      // 최초 진입 스냅샷 마크(현재 상태를 저장 기준으로 간주)
      editorService.markSavedSnapshot();

      // 스티커 초기 상태 저장 (변경 감지를 위해)
      try {
        context.read<StickerService>().saveInitialState();
      } catch (_) {}

      // 스크롤 리스너 추가
      scrollController.addListener(_onScrollChanged);

      // StickerCanvas는 화면 Stack에 직접 부착하므로 여기선 별도 처리 없음
    });
  }

  double _lastOffset = 0.0;
  bool _isScrollingUp = false;
  bool _showAppBar = true; // 초기에는 항상 표시

  void _onScrollChanged() {
    final currentOffset = scrollController.offset;
    final delta = currentOffset - _lastOffset;

    // 스크롤 가능 여부 확인
    final canScroll =
        scrollController.hasClients &&
        scrollController.position.maxScrollExtent > 0;

    if (!canScroll) {
      // 스크롤이 불가능하면 앱바 항상 표시
      if (!_showAppBar) {
        setState(() {
          _showAppBar = true;
          _isScrollingUp = true;
        });
      }
      return;
    }

    // 맨 위에 있을 때는 항상 앱바 표시
    const topThreshold = 10.0;
    if (currentOffset <= topThreshold) {
      if (!_showAppBar) {
        setState(() {
          _showAppBar = true;
          _isScrollingUp = true;
        });
      }
      _lastOffset = currentOffset;
      return;
    }

    // 스크롤 임계값 설정 (너무 작은 변화는 무시)
    const scrollThreshold = 5.0;

    if (delta.abs() > scrollThreshold) {
      if (delta < 0) {
        // 위로 스크롤 (앱바 표시)
        if (!_isScrollingUp) {
          setState(() {
            _isScrollingUp = true;
            _showAppBar = true;
          });
        }
      } else {
        // 아래로 스크롤 (앱바 숨김)
        if (_isScrollingUp) {
          setState(() {
            _isScrollingUp = false;
            _showAppBar = false;
          });
        }
      }
    }

    _lastOffset = currentOffset;
  }

  void _onEditorServiceChange() {
    // 문서 변경 시 UI 업데이트 (다음 버튼 상태 반영)
    if (mounted) {
      setState(() {});
    }
  }

  /// 키보드가 현재 표시되고 있는지 확인
  bool get isKeyboardVisible => _isKeyboardVisible;

  /// 키보드 높이 가져오기
  double get keyboardHeight => MediaQuery.of(context).viewInsets.bottom;

  void _onFocusChange() {
    setState(() {
      _isKeyboardVisible = _editorFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    // 이미지 선택 상태 초기화 (조용히)
    NodeComponentService().clearHighlightedSelectionSilently();
    NodeComponentService().clearSelectionSilently();

    textStylingService.dispose();
    editorService.removeListener(_onEditorServiceChange);
    editorService.dispose();
    dragService.removeListener(_onDragChange);
    scrollController.removeListener(_onScrollChanged);
    _editorFocusNode.removeListener(_onFocusChange);
    try {
      composer.selectionNotifier.removeListener(_updateImageSelectionHighlight);
    } catch (_) {}
    try {
      _editorFocusNode.dispose();
    } catch (_) {}
    super.dispose();
  }

  // 전달된 exported(Map)으로 문서를 구성
  MutableDocument _rebuildDocument(Map<String, dynamic> data) {
    dynamic content = data['content'];
    if (content is String) {
      try {
        content = json.decode(content);
      } catch (_) {
        content = const {'nodes': []};
      }
    }
    if (content is! Map) {
      content = const {'nodes': []};
    }
    final nodes = (content['nodes'] as List?) ?? const [];
    final rebuilt = <DocumentNode>[];
    for (final raw in nodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final type = (m['type'] ?? '').toString();
      switch (type) {
        case 'paragraph':
          final text = (m['text'] ?? '').toString();
          final align = (m['align'] ?? 'center').toString();
          final isTitle = m['isTitle'] == true;
          final spans = (m['spans'] as List?) ?? const [];
          final attributed = _buildAttributedText(text, spans);
          final meta = <String, dynamic>{'textAlign': align};
          if (isTitle) meta['isTitle'] = true;
          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
          break;
        case 'image':
          rebuilt.add(
            ImageNode(
              id: id,
              imageUrl: (m['url'] ?? '').toString(),
              altText: (m['altText'] ?? '').toString(),
            ),
          );
          break;
        case 'imageRow':
          rebuilt.add(
            ImageRowNode(
              id: id,
              imageUrls:
                  ((m['urls'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
            ),
          );
          break;
        case 'link':
          rebuilt.add(
            LinkNode(
              id: id,
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
            ),
          );
          break;
        case 'location':
        case 'mention':
          rebuilt.add(
            MentionNode(
              id: id,
              usernames:
                  ((m['usernames'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
            ),
          );
          break;
        default:
          rebuilt.add(ParagraphNode(id: id, text: AttributedText('[$type]')));
      }
    }
    return MutableDocument(nodes: rebuilt);
  }

  AttributedText _buildAttributedText(String text, List spans) {
    final attributed = AttributedText(text);
    for (final s in spans) {
      final m = (s as Map).cast<String, dynamic>();
      final start = (m['start'] as num?)?.toInt() ?? 0;
      final end = (m['end'] as num?)?.toInt() ?? start;
      final ann = (m['attrs'] as Map?)?.cast<String, dynamic>() ?? {};
      final atts = <Attribution>{};
      if (ann['bold'] == true) atts.add(boldAttribution);
      if (ann['italic'] == true) atts.add(italicsAttribution);
      if (ann['underline'] == true) atts.add(underlineAttribution);
      if (ann['strikethrough'] == true) atts.add(strikethroughAttribution);
      final fs = (ann['font_size'] as num?)?.toDouble();
      if (fs != null) atts.add(FontSizeAttribution(fs));
      final colorHex = ann['color'] as String?;
      if (colorHex != null && colorHex.isNotEmpty) {
        atts.add(ColorAttribution(_parseHexColor(colorHex)));
      }
      for (final a in atts) {
        attributed.addAttribution(a, SpanRange(start, end - 1));
      }
    }
    return attributed;
  }

  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }

  void _replaceDocumentSafely(MutableDocument newDocument) {
    try {
      for (int i = document.length - 1; i >= 0; i--) {
        final node = document.getNodeAt(i);
        if (node != null) {
          document.deleteNode(node.id);
        }
      }
      for (int i = 0; i < newDocument.length; i++) {
        final node = newDocument.getNodeAt(i);
        if (node != null) {
          document.insertNodeAt(i, node);
        }
      }
    } catch (_) {}
  }

  void _cleanupAndExit() {
    try {
      // 1) 포커스 정리 (SuperEditor가 자체적으로 처리하도록 위임)
      // FocusScope.of(context).unfocus(); // 제거: SuperEditor가 자체적으로 포커스 관리

      // 2) 이미지 서비스 상태 초기화
      final img = NodeComponentService();
      img.clearHighlightedSelection();
      img.selectImage(null);
      img.clearImageUrlMapping(); // 매핑 맵 정리

      // 3) 스티커 서비스 상태 초기화(선택/드래그/리스트)
      try {
        final stickerSvc = context.read<StickerService>();
        stickerSvc.select(null);
        stickerSvc.removeAll();
        // 드래그 상태 리셋을 위해 begin/ end 없이 내부 플래그만 초기화
        // 리스트는 그대로 두되, 화면 이탈이므로 선택/플래그만 리셋
      } catch (_) {}

      // 4) 드래그 서비스 플래그 정리
      try {
        dragService.endDrag();
      } catch (_) {}

      // 5) 에디터 선택/하이라이트 제거
      try {
        composer.clearSelection();
      } catch (_) {}

      // 6) overlay 등 정리 후 종료
      Navigator.of(context).pop();
    } catch (_) {
      Navigator.of(context).pop();
    }
  }

  // 드래그 프리뷰 렌더링을 위한 리스너
  void _onDragChange() {
    if (mounted) setState(() {});
  }

  /// 텍스트 선택 범위에 포함된 이미지/이미지행을 회색 하이라이트로 표시
  void _updateImageSelectionHighlight() {
    try {
      final sel = composer.selection;
      if (sel == null) {
        NodeComponentService().clearHighlightedSelection();
        return;
      }

      final baseIndex = document.getNodeIndexById(sel.base.nodeId);
      final extentIndex = document.getNodeIndexById(sel.extent.nodeId);
      if (baseIndex == -1 || extentIndex == -1) {
        NodeComponentService().clearHighlightedSelection();
        return;
      }

      final start = baseIndex <= extentIndex ? baseIndex : extentIndex;
      final end = baseIndex <= extentIndex ? extentIndex : baseIndex;
      final ids = <String>{};
      for (int i = start; i <= end; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;
        if (node is ImageNode || node is ImageRowNode) {
          ids.add(node.id);
        }
      }

      NodeComponentService().setHighlightedSelection(ids);
    } catch (_) {
      NodeComponentService().clearHighlightedSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 키보드 상태 업데이트
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    _isKeyboardVisible = keyboardHeight > 0;

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        // 나가기 전 저장 필요 여부 판단(서비스 로직)
        final needPrompt = editorService.shouldPromptSaveOnExit();
        final stickerService = context.read<StickerService>();
        final hasStickerChanges = stickerService.hasChanges;
        if (needPrompt || hasStickerChanges) {
          final decision = await Navigator.of(context).push<ExitDecision>(
            PageRouteBuilder(
              opaque: false,
              barrierDismissible: true,
              pageBuilder: (_, __, ___) => const SaveDraftOverlay(),
            ),
          );
          if (decision == ExitDecision.saveDraft) {
            await _manualSaveDraft();
            // 저장 후 종료 (정리 포함)
            _cleanupAndExit();
          } else if (decision == ExitDecision.discard) {
            await Future.delayed(const Duration(milliseconds: 180));
            _cleanupAndExit();
          }
        } else {
          // 바로 종료(서비스 상태만 정리)
          _cleanupAndExit();
        }
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            AnimatedScale(
              alignment: Alignment.center,
              duration: const Duration(milliseconds: 100),
              scale: dragService.draggingNodeId != null ? 0.95 : 1.0,
              child: Stack(
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 100),

                    opacity:
                        dragService.draggingNodeId != null
                            ? 0.6
                            : 1.0, // 드래그 중일 때 투명도 조정
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 0, // SafeArea만
                        bottom: 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 타이틀 문단은 SuperEditor 안에서 metadata로 스타일링 처리
                          Expanded(
                            child: Theme(
                              data: AppTheme.lightTheme,
                              child: SuperEditor(
                                gestureMode:
                                    Platform.isIOS
                                        ? DocumentGestureMode.iOS
                                        : DocumentGestureMode.android,
                                editor: editor,
                                focusNode: _editorFocusNode,
                                stylesheet: buildCustomStylesheet(context),
                                documentLayoutKey: _documentLayoutKey,
                                scrollController: scrollController,

                                selectionStyle: SelectionStyles(
                                  selectionColor: AppColors.primary.withOpacity(
                                    0.3,
                                  ),
                                  highlightEmptyTextBlocks: false,
                                ),

                                componentBuilders: [
                                  // 타이틀 문단 전용 빌더(드래그 없음)
                                  TitleParagraphComponentBuilder(
                                    editorService: editorService,
                                  ),
                                  // 커스텀 이미지 컴포넌트들
                                  SingleImageComponentBuilder(
                                    dragService: dragService,
                                  ),
                                  RowImageComponentBuilder(
                                    dragService: dragService,
                                  ),
                                  CustomParagraphComponentBuilder(
                                    dragService: dragService,
                                    editorService: editorService,
                                  ),

                                  // 커스텀 언급 노드 컴포넌트
                                  MentionComponentBuilder(
                                    dragService: dragService,
                                  ),
                                  // 구분선 전용 컴포넌트
                                  DividerComponentBuilder(
                                    dragService: dragService,
                                  ),

                                  LinkComponentBuilder(
                                    dragService: dragService,
                                  ),

                                  PinComponentBuilder(dragService: dragService),

                                  // 기본 컴포넌트들 (Paragraph 제외)
                                  ...defaultComponentBuilders.where(
                                    (builder) =>
                                        builder.runtimeType.toString() !=
                                        'ParagraphComponentBuilder',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  !context.read<StickerService>().isDragging
                      ? Positioned.fill(
                        child: GestureDetector(
                          onTapDown: (details) {
                            // 탭 다운 시 위치 저장
                            _lastTapPosition = details.globalPosition;
                            print('탭 다운: ${details.globalPosition}');
                          },
                          onTap: () {
                            // 짧은 클릭 처리
                            if (_lastTapPosition != null) {
                              final nodeId =
                                  editorService
                                      .findNodeAtPosition(_lastTapPosition!)
                                      ?.id;
                              if (nodeId != null) {
                                // 특수 노드 탭 선택: 이미지/이미지행/링크/멘션
                                final node = document.getNodeById(nodeId);
                                if (node is ImageNode ||
                                    node is ImageRowNode ||
                                    node is LinkNode ||
                                    node is MentionNode ||
                                    node is ClipNode) {
                                  NodeComponentService().selectNode(nodeId);
                                } else {
                                  NodeComponentService().selectNode(null);
                                }
                              }
                            }
                          },
                          onLongPressStart: (details) {
                            // 🚫 키보드가 올라와 있으면 드래그 불가
                            if (_isKeyboardVisible) {
                              FocusManager.instance.primaryFocus?.unfocus();
                            }

                            final node = editorService.findNodeAtPosition(
                              details.globalPosition,
                            );
                            print('클릭한 노드: $node');
                            if (node != null) {
                              final nodeId = node.id;
                              final imageService =
                                  context.read<NodeComponentService>();

                              if (node is ParagraphNode &&
                                  node.metadata['isTitle'] == true) {
                                return;
                              }

                              if (node is ImageRowNode) {
                                // 이미지 행이 선택된 상태라면 전체 행 드래그
                                if (imageService.selectedImageId == nodeId) {
                                  dragService.startDrag(
                                    nodeId,
                                    context,
                                    details.globalPosition,
                                  );
                                } else {
                                  // 손가락이 클릭한 쪽의 가장 근접한 이미지를 분리해서 드래그
                                  _startImageRowDrag(
                                    nodeId,
                                    details.globalPosition,
                                  );
                                }
                              } else if (node is ImageNode) {
                                // 단일 이미지 드래그
                                dragService.startDrag(
                                  nodeId,
                                  context,
                                  details.globalPosition,
                                );
                              } else {
                                // 이미지가 아닌 요소 드래그
                                dragService.startDrag(
                                  nodeId,
                                  context,
                                  details.globalPosition,
                                );
                              }
                            }
                          },
                          onLongPressMoveUpdate: (details) {
                            // 🚫 키보드가 올라와 있으면 드래그 업데이트 불가
                            if (_isKeyboardVisible) return;

                            dragService.updateDrag(
                              details.globalPosition,
                              context,
                            );
                          },
                          onLongPressEnd: (details) {
                            // 🚫 키보드가 올라와 있으면 드래그 종료 처리 불가
                            if (_isKeyboardVisible) return;

                            dragService.endDrag();
                          },
                          behavior: HitTestBehavior.translucent,
                        ),
                      )
                      : SizedBox.shrink(),

                  // 드래그 오버레이 (키보드가 내려가 있을 때만 표시)
                  if (dragService.draggingNodeId != null && !_isKeyboardVisible)
                    _buildDragOverlay(),
                ],
              ),
            ),

            // 커스텀 투명 앱바 (왼쪽 - 뒤로가기)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              top: _showAppBar ? -10 : -100,
              left: 0,
              child: SafeArea(
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(1),
                      ),
                      height: 55,
                      width: MediaQuery.of(context).size.width,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 뒤로가기 버튼
                          GestureDetector(
                            onTap: () async {
                              final needPrompt =
                                  editorService.shouldPromptSaveOnExit();
                              final stickerService =
                                  context.read<StickerService>();
                              final hasStickerChanges =
                                  stickerService.hasChanges;
                              if (needPrompt || hasStickerChanges) {
                                final decision = await Navigator.of(
                                  context,
                                ).push<ExitDecision>(
                                  PageRouteBuilder(
                                    opaque: false,
                                    barrierDismissible: true,
                                    pageBuilder:
                                        (_, __, ___) =>
                                            const SaveDraftOverlay(),
                                  ),
                                );
                                if (decision == ExitDecision.saveDraft) {
                                  await _manualSaveDraft();
                                  _cleanupAndExit();
                                } else if (decision == ExitDecision.discard) {
                                  await Future.delayed(
                                    const Duration(milliseconds: 180),
                                  );
                                  _cleanupAndExit();
                                }
                              } else {
                                _cleanupAndExit();
                              }
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
                                        _editorFocusNode.unfocus();

                                        final json =
                                            PostExporter.exportToJsonString(
                                              editorService: editorService,
                                              stickerService:
                                                  context
                                                      .read<StickerService>(),
                                              viewportSize:
                                                  MediaQuery.of(context).size,
                                              pretty: true,
                                            );
                                        NodeComponentService().selectNode(null);

                                        Navigator.of(context).push(
                                          PageRouteBuilder(
                                            opaque: false,
                                            barrierDismissible: true,
                                            pageBuilder:
                                                (_, __, ___) =>
                                                    PostExportScreen(
                                                      exported: json,
                                                    ),
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
              ),
            ),

            // 스티커 캔버스 (기본 화면 위, 기타 오버레이 아래)
            Positioned.fill(
              child: StickerCanvas(scrollController: scrollController),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).padding.top - 10,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Consumer<NodeComponentService>(
              builder: (context, imageService, child) {
                return imageService.selectedNodeId != null
                    ? _buildSelectedToolbar()
                    : _buildDefaultToolbar();
              },
            ),
          ),
        ),
      ),
    );
  }

  // 드래그 오버레이 빌드 (노션 스타일 컴포넌트 미리보기)
  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

    // 분리할 이미지 정보가 있으면 해당 이미지의 오버레이 표시
    if (dragService.hasSplitImageInfo) {
      // DragService에서 분리 정보 가져오기
      final splitInfo = dragService.getSplitImageInfo();
      if (splitInfo != null) {
        final rowId = splitInfo['rowId'] as String;
        final imageIndex = splitInfo['imageIndex'] as int;

        // 분리할 이미지의 URL 가져오기
        final rowNode = document.getNodeById(rowId);
        if (rowNode is ImageRowNode && imageIndex < rowNode.imageUrls.length) {
          final splitImageUrl = rowNode.imageUrls[imageIndex];

          // 분리할 이미지의 오버레이 표시
          return DragOverlayWidget(
            nodeId: 'temp_split_image',
            nodeType: 'image',
            position: pos,
            document: document,
            splitImageUrl: splitImageUrl, // 분리용 임시 이미지 URL 전달
          );
        }
      }
    }

    // 일반적인 경우 (분리할 이미지 정보가 없을 때)
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    String nodeType = 'default';
    if (node is ImageNode) {
      nodeType = 'image';
    } else if (node is ImageRowNode) {
      nodeType = 'imageRow';
    } else if (node is ParagraphNode) {
      nodeType = 'paragraph';
    } else if (node is LinkNode) {
      nodeType = 'link';
    } else if (node is MentionNode) {
      nodeType = 'mention';
    } else if (node is DividerNode) {
      nodeType = 'divider';
    } else if (node is ClipNode) {
      nodeType = 'clip';
    }
    return DragOverlayWidget(
      nodeId: nodeId,
      nodeType: nodeType,
      position: pos,
      document: document,
    );
  }

  Widget _buildDefaultToolbar() {
    return DefaultToolbar(
      stylingService: textStylingService,
      editorService: editorService,
      scrollController: scrollController,
      isKeyboardVisible: _isKeyboardVisible,
      isEditMode: widget.isEditMode,

      onDismissKeyboard: () {
        // 키보드 내리기 (SuperEditor의 포커스 관리 활용)
        _editorFocusNode.unfocus();
      },
      onRequestFocus: () {
        // 에디터 포커스 복원
        _editorFocusNode.requestFocus();
      },
      onShowDraftList: _showDraftList,
    );
  }

  Widget _buildSelectedToolbar() {
    final selectedId = NodeComponentService().selectedNodeId;
    if (selectedId == null) return const SizedBox.shrink();

    final node = document.getNodeById(selectedId);
    // 링크/멘션/이미지 공통 삭제 전용 툴바
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),

      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            '선택됨',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          /*
          Text(
            '선택됨: ${node.runtimeType}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
         */
          const Spacer(),
          if (node is ImageNode)
            IconButton(
              tooltip: '수정',
              onPressed: () => _editImage(selectedId, node),
              icon: Icon(
                Icons.crop,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),

          IconButton(
            tooltip: '삭제',
            onPressed: () {
              // 이미지 계열은 안전 삭제 루틴 사용
              if (node is ImageNode || node is ImageRowNode) {
                _deleteImageSafely(selectedId);
                return;
              }

              // 링크/멘션 등 다른 특수 노드 삭제
              try {
                NodeComponentService().selectNode(null);
                composer.clearSelection();
                document.deleteNode(selectedId);
                setState(() {});
              } catch (e) {
                ErrorHandler.showError(context, '삭제할 수 없습니다');
              }
            },
            icon: Icon(
              size: 20,
              Icons.delete,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 이미지 편집
  Future<void> _editImage(String imageId, ImageNode node) async {
    try {
      FocusScope.of(context).unfocus();
      final response = await http.get(Uri.parse(node.imageUrl));
      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, '이미지를 불러올 수 없습니다');
        }
        return;
      }

      final imageBytes = response.bodyBytes;
      // 3. 이미지 편집기 열기 (오버레이 스타일)
      final editedBytes = await Navigator.push<Uint8List?>(
        // ignore: use_build_context_synchronously
        context,
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder:
              (context, _, __) =>
                  CustomImageEditorScreen(imageBytes: imageBytes),
        ),
      );

      FocusScope.of(context).unfocus();
      if (editedBytes == null || !mounted) return;

      final upload = context.read<UploadService>();

      // 임시 파일로 변환
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(editedBytes);

      final tasks = await upload.uploadFilesViaServerBatches([
        tempFile,
      ], kind: UploadKind.editorImage);

      // 임시 파일 삭제
      try {
        await tempFile.delete();
      } catch (_) {}

      if (tasks.isEmpty || tasks.first.state != UploadState.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, '이미지 업로드에 실패했습니다');
        }
        return;
      }

      final newUrl = tasks.first.url;
      if (newUrl == null || newUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ErrorHandler.showError(context, '이미지 URL을 받을 수 없습니다');
        }
        return;
      }

      // 5. 문서에서 이미지 URL 교체
      final nodeIndex = document.getNodeIndexById(imageId);
      if (nodeIndex != -1) {
        final newNode = ImageNode(
          id: imageId,
          imageUrl: newUrl,
          altText: node.altText,
        );

        document.deleteNode(imageId);
        document.insertNodeAt(nodeIndex, newNode);
      }
    } catch (e) {
      print('이미지 편집 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ErrorHandler.showError(context, '이미지 편집 중 오류가 발생했습니다');
      }
    }
  }

  /// 안전한 이미지 삭제 메서드
  void _deleteImageSafely(String imageId) {
    try {
      // 1단계: 모든 선택 상태를 먼저 초기화
      NodeComponentService().selectNode(null);
      NodeComponentService().clearHighlightedSelection();
      composer.clearSelection();

      // 이미지 URL을 매핑에서 제거
      final node = document.getNodeById(imageId);
      if (node is ImageNode && node.imageUrl.isNotEmpty) {
        NodeComponentService().unregisterImageUrl(node.imageUrl);
      } else if (node is ImageRowNode) {
        NodeComponentService().unregisterImageUrls(node.imageUrls);
      }

      // 2단계: 포커스 해제 (SuperEditor가 자체적으로 처리)
      // FocusScope.of(context).unfocus(); // 제거: 불필요한 포커스 간섭 방지

      // 3단계: 다음 프레임에서 이미지 삭제 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            // 이미지 삭제
            document.deleteNode(imageId);
            setState(() {});
          } catch (e) {
            print('이미지 삭제 중 오류: $e');
          }
        }
      });
    } catch (e) {
      print('이미지 삭제 준비 중 오류: $e');
    }
  }

  // 이미지 행에서 특정 이미지 드래그 시작 (분리는 드롭 시)
  void _startImageRowDrag(String imageRowId, Offset globalPosition) {
    // 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
    final rowNode = document.getNodeById(imageRowId) as ImageRowNode?;
    if (rowNode != null) {
      final imageIndex = _findClickedImageIndex(rowNode, globalPosition);

      if (imageIndex != null) {
        print('분리할 이미지 인덱스: $imageIndex');

        // 이미지 행 전체를 드래그하되, 분리할 이미지 정보를 저장
        dragService.startDrag(imageRowId, context, globalPosition);

        // 분리할 이미지 정보를 DragService에 저장
        dragService.setSplitImageInfo(imageRowId, imageIndex);
      }
    }
  }

  // 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
  int? _findClickedImageIndex(ImageRowNode rowNode, Offset globalPosition) {
    try {
      // 간단한 방법: 화면 너비를 기반으로 이미지 인덱스 계산
      final imageCount = rowNode.imageUrls.length;
      final screenWidth = MediaQuery.of(context).size.width;
      final imageWidth = screenWidth / imageCount;

      // 클릭한 X 좌표에 따라 이미지 인덱스 계산
      final clickedIndex = (globalPosition.dx / imageWidth).floor();

      // 유효한 인덱스 범위 확인
      if (clickedIndex >= 0 && clickedIndex < imageCount) {
        print('계산된 이미지 인덱스: $clickedIndex (전체: $imageCount)');
        return clickedIndex;
      }

      // 기본값으로 첫 번째 이미지 반환
      print('기본값으로 첫 번째 이미지 선택');
      return 0;
    } catch (e) {
      print('이미지 인덱스 계산 에러: $e');
      return 0; // 에러 시 첫 번째 이미지 반환
    }
  }

  /// 임시저장 초기화
  Future<void> _initializeDraft() async {
    try {
      // 기존 임시저장이 있는지 확인
      _currentDraftId = await draftService.getCurrentDraftId();

      print('[PostwriteScreen] Draft initialized: $_currentDraftId');
    } catch (e) {
      print('[PostwriteScreen] Error initializing draft: $e');
    }
  }

  /// 수동 임시저장 (새 버전 생성)
  Future<void> _manualSaveDraft() async {
    try {
      final title = _getTitleFromDocument();
      final thumbnailUrl = _getThumbnailFromDocument();

      // 항상 새로운 버전으로 저장 (existingDraftId를 null로)
      _currentDraftId = await draftService.saveDraft(
        editorService: editorService,
        stickerService: context.read<StickerService>(),
        title: title,
        thumbnailUrl: thumbnailUrl,
        visibility: 'public', // 기본값
        selectedGroupIds: [],
        existingDraftId: null, // 새 버전 생성
      );

      print('[PostwriteScreen] Manual save completed: $_currentDraftId');
      // 저장 스냅샷 마크
      editorService.markSavedSnapshot();

      // 스티커 초기 상태 저장 (임시저장 후 변화 감지를 위해)
      context.read<StickerService>().saveInitialState();

      // 임시저장 후에는 매핑 맵을 유지 (계속 작업할 수 있도록)
    } catch (e) {
      print('[PostwriteScreen] Manual save failed: $e');
      if (mounted) {
        ErrorHandler.showError(context, '임시저장 실패: $e');
      }
    }
  }

  /// 문서에서 제목 추출
  String _getTitleFromDocument() {
    try {
      for (int i = 0; i < document.length; i++) {
        final node = document.getNodeAt(i);
        if (node is ParagraphNode && node.metadata['isTitle'] == true) {
          return node.text.text.trim();
        }
      }
    } catch (e) {
      print('[PostwriteScreen] Error getting title: $e');
    }
    return '제목 없음';
  }

  /// 문서에서 썸네일 URL 추출
  String _getThumbnailFromDocument() {
    try {
      for (int i = 0; i < document.length; i++) {
        final node = document.getNodeAt(i);
        if (node is ImageNode) {
          return node.imageUrl;
        } else if (node is ImageRowNode && node.imageUrls.isNotEmpty) {
          return node.imageUrls.first;
        }
      }
    } catch (e) {
      print('[PostwriteScreen] Error getting thumbnail: $e');
    }
    return '';
  }

  /// 임시저장 목록 보기
  Future<void> _showDraftList() async {
    try {
      final groupedDrafts = await draftService.getDraftsByTitle();

      if (!mounted) return;

      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder:
              (_, __, ___) => DraftListOverlay(
                drafts: groupedDrafts,
                currentDraftId: _currentDraftId,
                onLoadDraft: _loadDraft,
                onDeleteDraft: _deleteDraft,
              ),
        ),
      );
    } catch (e) {
      print('[PostwriteScreen] Error showing draft list: $e');
      if (mounted) {
        ErrorHandler.showError(context, '임시저장 목록을 불러올 수 없습니다: $e');
      }
    }
  }

  /// 임시저장 불러오기
  Future<void> _loadDraft(String draftId) async {
    try {
      // 기존 선택/하이라이트를 먼저 정리하여 SuperEditor가
      // 사라진 노드에 대한 selection을 적용하지 않도록 방지
      try {
        NodeComponentService().clearHighlightedSelection();
        NodeComponentService().selectNode(null);
        composer.clearSelection();
      } catch (_) {}

      final success = await draftService.loadDraft(
        draftId: draftId,
        editorService: editorService,
        stickerService: context.read<StickerService>(),
      );

      if (success) {
        _currentDraftId = draftId;

        // 불러온 문서의 이미지 URL과 ID 로그 출력
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('📂 [임시저장 불러오기 완료]');
        print('Draft ID: $draftId');

        final imageUrls = <String>[];
        for (int i = 0; i < document.length; i++) {
          final node = document.getNodeAt(i);
          if (node is ImageNode && node.imageUrl.isNotEmpty) {
            imageUrls.add(node.imageUrl);
          } else if (node is ImageRowNode) {
            imageUrls.addAll(node.imageUrls.where((url) => url.isNotEmpty));
          }
        }

        print('📸 문서 내 이미지 개수: ${imageUrls.length}');

        // 매핑 맵 상태 확인
        final urlToIdMap = NodeComponentService().urlToImageIdMap;
        print('💾 현재 매핑 맵 크기: ${urlToIdMap.length}');

        if (imageUrls.isNotEmpty) {
          print('🖼️ 이미지 URL 및 ID 매핑 리스트:');
          for (int i = 0; i < imageUrls.length; i++) {
            final url = imageUrls[i];
            final imageId = urlToIdMap[url];
            final urlDisplay = url.substring(
              url.length > 70 ? url.length - 70 : 0,
            );
            if (imageId != null) {
              print('  ${i + 1}. $urlDisplay');
              print('     → ID: $imageId ✓');
            } else {
              print('  ${i + 1}. $urlDisplay');
              print('     → ID: 없음 ⚠️');
            }
          }
        }
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        // UI 강제 업데이트 및 포커스 정리
        if (mounted) {
          // 포커스 해제 (키보드 숨김)
          _editorFocusNode.unfocus();

          // 불러온 상태를 저장 스냅샷으로 간주
          editorService.markSavedSnapshot();

          // 스티커 초기 상태 저장
          context.read<StickerService>().saveInitialState();

          // 발행 가능 여부 체크를 위한 UI 업데이트 (약간의 지연 후)
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              editorService.updatePublishableStatus();
            }
          });
        }
      } else {
        if (mounted) {
          ErrorHandler.showError(context, '임시저장을 불러올 수 없습니다');
        }
      }
    } catch (e) {
      print('[PostwriteScreen] Error loading draft: $e');
      if (mounted) {
        ErrorHandler.showError(context, '임시저장 불러오기 실패: $e');
      }
    }
  }

  /// 임시저장 삭제
  Future<void> _deleteDraft(String draftId) async {
    try {
      final success = await draftService.deleteDraft(draftId);

      if (success) {
        if (_currentDraftId == draftId) {
          _currentDraftId = null;
        }
      } else {
        if (mounted) {
          ErrorHandler.showError(context, '임시저장 삭제에 실패했습니다');
        }
      }
    } catch (e) {
      print('[PostwriteScreen] Error deleting draft: $e');
      if (mounted) {
        ErrorHandler.showError(context, '임시저장 삭제 실패: $e');
      }
    }
  }
}
