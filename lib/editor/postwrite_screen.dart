import 'dart:io';
import 'package:doppy/editor/%20adf.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show ClipNode, videoPlayerControllers, PinComponentBuilder;

import 'package:doppy/editor/style/selected_toolbar.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/title_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/edit_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/writer_sticker_canvas.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/draft_list_overlay.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/image/custom_image_editor_screen.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, imageRow, location, unknown }

class PostwriteScreen extends StatefulWidget {
  final bool isEditingMode;
  final Map<String, dynamic>? exportedDataForEdit;

  const PostwriteScreen({
    super.key,
    this.isEditingMode = false,
    this.exportedDataForEdit,
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
  late final EditService editService;

  //overlay
  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  //manipulation
  ScrollController scrollController = ScrollController();
  Offset? _lastTapPosition; // 마지막 탭 위치 저장

  //keyboard
  bool isKeyboardVisible = false; // 키보드 표시 상태
  String? currentDraftId; // 임시저장 관련

  @override
  void initState() {
    super.initState();
    // 스포일러 렌더링 모드: 글쓰기화면
    setSpoilerEditingMode(true);

    // 편집 모드이면 전달된 exportedDataForEdit를 기반으로 문서를 복원
    // 새 글 작성 모드이면 빈 문서 생성
    if (widget.isEditingMode && widget.exportedDataForEdit != null) {
      try {
        document = EditService().rebuildDocumentForEdit(
          widget.exportedDataForEdit!,
        );
      } catch (e) {
        // 실패 시 빈 문서로 초기화
        document = MutableDocument(
          nodes: [
            ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
          ],
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ErrorHandler.showError(context, '게시물 데이터를 불러올 수 없습니다');
          }
        });
      }
    } else {
      print('🔄 새 글 작성 모드');
      // 새 글 작성 모드 - 빈 문서 생성
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
    }
    composer = MutableDocumentComposer();

    // FocusNode 초기화
    _editorFocusNode = FocusNode(debugLabel: 'editor_focus');

    // 포커스 변화 감지 (키보드 상태 추적)
    _editorFocusNode.addListener(() {
      setState(() {
        isKeyboardVisible = _editorFocusNode.hasFocus;
      });
    });

    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(editor: editor, document: document);
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    textStylingService = TextStylingService(editor: editor, composer: composer);

    //service 초기화2

    stickerService = StickerService();
    nodeComponentService = NodeComponentService();

    // 전역 스타일링 서비스 설정 (렌더링용)
    setGlobalTextStylingService(textStylingService);
    // 편집 서비스
    editService = EditService();

    // ImageService는 build 메서드에서 설정
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    dragService.attachScrollController(scrollController);
    dragService.addListener(_onDragging);

    // 임시저장 서비스 초기화
    draftService = DraftService();

    // 문서 변경 시 다음 버튼 상태 업데이트
    editorService.addListener(_onEditorServiceChange);

    // 폰트 변경 감지
    textStylingService.addListener(_onEditorServiceChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 편집 모드가 아닐 때만 커서 이동
      if (!widget.isEditingMode) {
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
      }
      try {
        // 최초 진입 스냅샷 마크(현재 상태를 저장 기준으로 간주)
        editorService.markSavedSnapshot();
        stickerService.saveInitialState();
      } catch (_) {}

      // 스크롤 리스너 추가
      scrollController.addListener(_onScrollChanged);
    });
  }

  bool _showAppBar = true;
  double _lastOffset = 0.0;
  bool _isScrollingUp = false;

  void _onKeyboardVisibilityChanged() {
    if (!mounted) return;

    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardHeight = viewInsets.bottom;
    final currentOffset =
        scrollController.hasClients ? scrollController.offset : 0.0;
    final delta = currentOffset - _lastOffset;

    // 상수 정의
    const scrollThreshold = 3.0;
    const topThreshold = 15.0;

    // 키보드 상태에 따른 스크롤 가능 여부 판단
    final isKeyboardUp = keyboardHeight > 200;
    final isKeyboardDown = keyboardHeight <= 30;

    // 키보드가 완전히 내려갔을 때도 스크롤 방향에 따라 앱바 제어
    if (isKeyboardDown) {
      // 스크롤 방향 감지
      if (delta < -scrollThreshold) {
        // 위로 스크롤 (앱바 표시)
        if (!_isScrollingUp || !_showAppBar) {
          setState(() {
            _isScrollingUp = true;
            _showAppBar = true;
          });
        }
      } else if (delta > scrollThreshold) {
        // 아래로 스크롤 (앱바 숨김)
        if (_isScrollingUp && _showAppBar) {
          setState(() {
            _isScrollingUp = false;
            _showAppBar = false;
          });
        }
      }
      // 맨 위에 있을 때는 항상 앱바 표시
      if (currentOffset <= topThreshold) {
        if (!_showAppBar) {
          setState(() {
            _showAppBar = true;
            _isScrollingUp = true;
          });
        }
      }

      _lastOffset = currentOffset;
      return;
    }

    // 키보드가 올라와 있을 때의 스크롤 가능 여부 확인
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

    // 3. 맨 위에 있을 때는 항상 앱바 표시
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

    // 4. 스크롤 방향에 따른 앱바 표시/숨김
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
        // 아래로 스크롤 (앱바 숨김) - 키보드가 올라와 있을 때만
        if (_isScrollingUp && isKeyboardUp) {
          setState(() {
            _isScrollingUp = false;
            _showAppBar = false;
          });
        }
      }
    }

    _lastOffset = currentOffset;
  }

  void _onScrollChanged() {
    // 스크롤 시 서비스 캐시 무효화
    try {
      dragService.invalidateNodeRectCache();
    } catch (_) {}
    // 레이아웃 변동 시 노드 rect 캐시 무효화 (스크롤시)
    try {
      dragService.invalidateNodeRectCache();
    } catch (_) {}
    _onKeyboardVisibilityChanged();
  }

  void _onEditorServiceChange() {
    if (mounted) {
      setState(() {});
    }
  }

  // 드래그 프리뷰 렌더링을 위한 리스너
  void _onDragging() {
    if (mounted) setState(() {});
  }

  void _cleanupAndExit() {
    try {
      dragService.endDrag();
      composer.clearSelection();
      nodeComponentService.clearAll();
    } catch (_) {}

    try {
      stickerService.select(null);
      stickerService.removeAll();
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  // ClipNode 액션 트리거
  void _triggerClipNodeAction(String nodeId, String action) {
    print('[ClipNode] Action triggered: $action for node: $nodeId');

    // 문서에서 ClipNode 찾기
    final node = document.getNodeById(nodeId);
    if (node is! ClipNode || node.url.isEmpty) {
      print('[ClipNode] ClipNode를 찾을 수 없거나 URL이 비어있습니다');
      return;
    }

    // 컨트롤러 찾기
    final key = 'video_${node.url.hashCode}';
    final controller = videoPlayerControllers[key];

    if (controller == null) {
      print('[ClipNode] 컨트롤러를 찾을 수 없습니다: $key');
      return;
    }

    // 액션 실행
    if (action == 'toggleMute') {
      controller.toggleMute?.call();
      print('[ClipNode] toggleMute() 호출됨');
    } else if (action == 'restartVideo') {
      controller.restartVideo?.call();
      print('[ClipNode] restartVideo() 호출됨');
    }
  }

  void _handleTap() {
    if (_lastTapPosition == null) return;
    // 1) 세로 노드 사이 클릭 감지 → 특수 노드(텍스트가 아닌) 사이에서 빈 문단 삽입
    final verticalGapIndex = _detectVerticalGapAt(_lastTapPosition!);
    if (verticalGapIndex != null) {
      final before =
          verticalGapIndex - 1 >= 0
              ? document.getNodeAt(verticalGapIndex - 1)
              : null;
      final after =
          verticalGapIndex < document.nodeCount
              ? document.getNodeAt(verticalGapIndex)
              : null;

      // 텍스트 노드가 아닌 특수 노드인지 확인
      bool isSpecialNode(DocumentNode node) {
        return node is ImageNode ||
            node is ImageRowNode ||
            node is ClipNode ||
            node is LinkNode ||
            (node is ParagraphNode && node.metadata['mention'] == true);
      }

      final bool isSpecialBefore = before != null && isSpecialNode(before);
      final bool isSpecialAfter = after != null && isSpecialNode(after);

      if (isSpecialBefore && isSpecialAfter) {
        // 현재 스크롤 위치 저장
        final currentScrollOffset =
            scrollController.hasClients ? scrollController.offset : 0.0;

        editorService.insertEmptyParagraphAtIndex(verticalGapIndex);

        // 키보드가 올라가 있으면 스크롤 위치 유지
        if (isKeyboardVisible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              scrollController.jumpTo(currentScrollOffset);
            }
          });
        } else {
          // 키보드가 내려가 있을 때만 포커스 요청
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_editorFocusNode.hasFocus) {
              _editorFocusNode.requestFocus();
            }
          });
        }
      }
      nodeComponentService.selectNode(null);
      return;
    }

    final nodeId = editorService.findNodeAtPosition(_lastTapPosition!)?.id;
    if (nodeId == null) return;

    final node = document.getNodeById(nodeId);

    // 2) 이미지행 내부 경계(이미지 사이) 클릭 감지 → 빈 문단 삽입
    if (node is ImageRowNode) {
      final betweenIndex = _detectImageRowBoundaryGap(node, _lastTapPosition!);
      if (betweenIndex != null) {
        final rowIndex = document.getNodeIndexById(node.id);
        if (rowIndex != -1) {
          editorService.insertEmptyParagraphAtIndex(rowIndex + 1);
        }
        nodeComponentService.selectNode(null);
        return;
      }
    }

    // 3) ClipNode 클릭 시 위치에 따라 분기 처리
    if (node is ClipNode) {
      final action = dragService.handleClipNodeTap(nodeId, _lastTapPosition!);
      if (action != null) {
        _triggerClipNodeAction(nodeId, action);
        nodeComponentService.selectNode(null);
        return;
      }
    }

    final bool isSpecial =
        node is ImageNode ||
        node is ImageRowNode ||
        node is LinkNode ||
        (node is ParagraphNode && node.metadata['mention'] == true) ||
        node is ClipNode;

    nodeComponentService.selectNode(isSpecial ? nodeId : null);
  }

  // moved to EditorService (getNodeGlobalRect)

  int? _detectVerticalGapAt(Offset globalPos) {
    // delegate to DragService
    return dragService.detectVerticalGapAt(globalPos);
  }

  int? _detectImageRowBoundaryGap(ImageRowNode rowNode, Offset globalPos) {
    const double threshold = 12.0; // 경계 감지 임계
    final rect = dragService.getNodeGlobalRect(rowNode.id);
    if (rect == null) return null;

    // 수직으로 행 안쪽에 위치해야 함 (약간 오차 허용)
    if (globalPos.dy < rect.top - 8 || globalPos.dy > rect.bottom + 8) {
      return null;
    }

    final localX = globalPos.dx - rect.left;
    final int count = rowNode.imageUrls.length;
    if (count <= 1) return null;
    final double slot = rect.width / count;

    // 경계는 k*slot (k=1..count-1). 경계에 가까우면 감지
    for (int k = 1; k < count; k++) {
      final double boundaryX = slot * k;
      if ((localX - boundaryX).abs() <= threshold) {
        return k; // k번째 경계 = 앞 이미지 인덱스와 뒤 이미지 인덱스 사이
      }
    }
    return null;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (isKeyboardVisible) {
      _editorFocusNode.unfocus();
    }

    final node = editorService.findNodeAtPosition(details.globalPosition);
    if (node == null) return;
    final nodeId = node.id;

    // 타이틀 문단은 드래그 금지
    if (node is ParagraphNode && node.metadata['isTitle'] == true) {
      return;
    }

    // 노드 타입별 분기
    if (node is ImageRowNode) {
      final isRowSelected = nodeComponentService.selectedImageId == nodeId;
      if (isRowSelected) {
        dragService.startDrag(nodeId, context, details.globalPosition);
      } else {
        _startImageRowDrag(nodeId, details.globalPosition);
      }
      return;
    }

    if (node is ImageNode) {
      dragService.startDrag(nodeId, context, details.globalPosition);
      return;
    }

    // 기타 노드(문단, 링크, 멘션, 구분선 등)
    dragService.startDrag(nodeId, context, details.globalPosition);
  }

  void _handleDragMoveAndAutoScroll(
    BuildContext context,
    LongPressMoveUpdateDetails details,
  ) {
    dragService.updateDrag(details.globalPosition, context);

    if (!scrollController.hasClients) return;

    final double screenHeight = MediaQuery.of(context).size.height;
    final double globalY = details.globalPosition.dy;
    const double edge = 140.0; // 감지 폭 확대
    const double base = 12.0; // 기본 속도
    final pos = scrollController.position;

    double speedFor(double distanceToEdge) {
      final d = (edge - distanceToEdge).clamp(0.0, edge);
      final factor = (d / edge);
      return base * (0.3 + 0.7 * factor); // 가장자리 근접 시 가속
    }

    if (globalY < edge) {
      final distance = globalY; // 상단까지 거리
      final delta = speedFor(distance);
      final next = (pos.pixels - delta).clamp(0.0, pos.maxScrollExtent);
      if (next != pos.pixels) {
        scrollController.jumpTo(next);
      }
    } else if (globalY > screenHeight - edge) {
      final distance = screenHeight - globalY; // 하단까지 거리
      final delta = speedFor(distance);
      final next = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
      if (next != pos.pixels) {
        scrollController.jumpTo(next);
      }
    }
  }

  Stylesheet _buildStylesheet(BuildContext context) {
    return buildCustomStylesheet(context).copyWith(
      documentPadding: EdgeInsets.only(top: 0, left: 0, right: 0, bottom: 100),
    );
  }

  @override
  void dispose() {
    // 스포일러 모드 복구
    setSpoilerEditingMode(false);
    // 이미지 선택 상태 초기화
    nodeComponentService.clearHighlightedSelectionSilently();
    nodeComponentService.clearSelectionSilently();

    textStylingService.removeListener(_onEditorServiceChange);
    textStylingService.dispose();
    editorService.removeListener(_onEditorServiceChange);
    editorService.dispose();
    dragService.removeListener(_onDragging);
    scrollController.removeListener(_onScrollChanged);
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 키보드 상태 변화 감지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onKeyboardVisibilityChanged();
    });

    return WillPopScope(
      onWillPop: () async {
        if (widget.isEditingMode) {
          final shouldCancel = await DialogUtils.showConfirmDialog(
            context,
            title: '수정 취소',
            message: '수정 중인 내용이 사라집니다.\n정말 취소하시겠습니까?',
            confirmText: '취소',
            cancelText: '계속 수정',
            isDestructive: true,
          );
          if (shouldCancel == true) {
            _cleanupAndExit();
          }
          return false;
        }

        // 새 글 작성 모드: 변경사항이 있으면 임시저장 다이얼로그
        final needPrompt = editorService.shouldPromptSaveOnExit(context);
        if (needPrompt) {
          final shouldSave = await DialogUtils.showConfirmDialog(
            context,
            title: '작성 취소',
            message: '작성 중인 내용을 임시저장할까요?',
            confirmText: '임시저장',
            cancelText: '저장 안 함',
            isDestructive: false,
          );
          if (shouldSave == true) {
            await _saveDraft();
            _cleanupAndExit();
          } else if (shouldSave == false) {
            _cleanupAndExit();
          }
          // null이면 아무 것도 안 함 (다이얼로그만 닫힘)
        } else {
          _cleanupAndExit();
        }
        return false;
      },

      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ValueListenableBuilder<String?>(
                      valueListenable: dragService.draggingNodeIdNotifier,
                      builder: (context, draggingNodeId, _) {
                        return TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: draggingNodeId != null ? 1.0 : 0.86,
                            end: draggingNodeId != null ? 0.86 : 1.0,
                          ),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              alignment: Alignment.center,
                              child: child,
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Theme(
                                  data: AppTheme.lightTheme,
                                  child: Stack(
                                    children: [
                                      SuperEditor(
                                        gestureMode:
                                            Platform.isIOS
                                                ? DocumentGestureMode.iOS
                                                : DocumentGestureMode.android,
                                        editor: editor,
                                        focusNode: _editorFocusNode,
                                        stylesheet: _buildStylesheet(context),
                                        selectionStyle: SelectionStyles(
                                          selectionColor: AppColors.primary
                                              .withValues(alpha: 0.3),
                                          highlightEmptyTextBlocks: false,
                                        ),
                                        documentLayoutKey: _documentLayoutKey,
                                        scrollController: scrollController,

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

                                          // 구분선 전용 컴포넌트
                                          DividerComponentBuilder(
                                            dragService: dragService,
                                          ),

                                          LinkComponentBuilder(
                                            dragService: dragService,
                                          ),

                                          PinComponentBuilder(
                                            dragService: dragService,
                                          ),

                                          // 기본 컴포넌트들 (Paragraph 제외)
                                          ...defaultComponentBuilders.where(
                                            (builder) =>
                                                builder.runtimeType
                                                    .toString() !=
                                                'ParagraphComponentBuilder',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  if (!stickerService.isDragging)
                    Positioned.fill(
                      child: GestureDetector(
                        onTapDown: (details) {
                          _lastTapPosition = details.globalPosition;
                        },
                        onTap: _handleTap,
                        onLongPressStart:
                            (details) => _handleLongPressStart(details),
                        onLongPressMoveUpdate:
                            (details) =>
                                _handleDragMoveAndAutoScroll(context, details),
                        onLongPressEnd: (details) {
                          dragService.endDrag();
                        },
                        behavior: HitTestBehavior.translucent,
                      ),
                    ),

                  // 드래그 오버레이 (키보드가 내려가 있을 때만 표시)
                  if (dragService.draggingNodeId != null && !isKeyboardVisible)
                    _buildDragOverlay(),

                  // 스티커 캔버스
                  Positioned.fill(
                    child: StickerCanvas(scrollController: scrollController),
                  ),

                  // 앱바
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    top: _showAppBar ? -10 : -100,
                    child:
                        widget.isEditingMode
                            ? EditModeAppBar(
                              editorService: editorService,
                              onSave: _saveEditedPost,
                            )
                            : EditorAppBar(
                              editorService: editorService,
                              stickerService: stickerService,
                            ),
                  ),

                  // 툴바 위 패딩
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.of(context).padding.top,
                    child: TopPadding(),
                  ),
                ],
              ),
            ),
          ],
        ),

        bottomNavigationBar: AnimatedContainer(
          duration: const Duration(milliseconds: 20),
          curve: Curves.easeInOut,
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).viewInsets.bottom <= 30
                    ? 20
                    : MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Consumer<NodeComponentService>(
            builder: (context, nodeService, child) {
              return nodeService.selectedNodeId != null
                  ? _buildSelectedToolbar()
                  : _buildDefaultToolbar();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

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
          nodeId: 'temp_split_image',
          nodeType: 'image',
          position: pos,
          document: document,
          splitImageUrl: rowNode.imageUrls[imageIndex],
        );
      }
    }

    // 일반 노드 드래그
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    final nodeType = _getNodeType(node);
    return DragOverlayWidget(
      nodeId: nodeId,
      nodeType: nodeType,
      position: pos,
      document: document,
    );
  }

  String _getNodeType(dynamic node) {
    if (node is ImageNode) return 'image';
    if (node is ImageRowNode) return 'imageRow';
    if (node is ParagraphNode) {
      if (node.metadata['mention'] == true) return 'mention';
      return 'paragraph';
    }
    if (node is LinkNode) return 'link';
    if (node is DividerNode) return 'divider';
    if (node is ClipNode) return 'clip';
    return 'default';
  }

  Widget _buildDefaultToolbar() {
    return DefaultToolbar(
      stylingService: textStylingService,
      editorService: editorService,
      scrollController: scrollController,
      isKeyboardVisible: isKeyboardVisible,
      onDismissKeyboard: () {
        _editorFocusNode.unfocus();
      },
      onShowDraftList: _showDraftList,
    );
  }

  Widget _buildSelectedToolbar() {
    final selectedId = nodeComponentService.selectedNodeId;
    if (selectedId == null) return const SizedBox.shrink();
    final node = document.getNodeById(selectedId);
    // 링크/멘션/이미지 공통 삭제 전용 툴바
    return SelectedToolbar(
      node: node,
      selectedId: selectedId,
      onEdit: () => _editImage(selectedId, node as ImageNode),
      onDelete: (node, selectedId) => _deleteNode(node, selectedId),
      onChangeAlignment:
          (node, selectedId) => _changeImageAlignment(node, selectedId),
    );
  }

  /// 이미지 정렬 변경
  Future<void> _changeImageAlignment(
    DocumentNode node,
    String selectedId,
  ) async {
    if (node is! ImageNode) return;

    // 메타데이터에서 현재 패딩 정보 가져오기
    final currentPadding = node.metadata['padding'] as String? ?? 'center';

    // 다음 패딩 모드로 전환
    final nextPadding = _getNextPaddingMode(currentPadding);

    // 메타데이터 업데이트
    final updatedMetadata = Map<String, dynamic>.from(node.metadata);
    updatedMetadata['padding'] = nextPadding;

    final newNode = ImageNode(
      id: node.id,
      imageUrl: node.imageUrl,
      altText: node.altText,
      metadata: updatedMetadata,
    );

    // editor.execute를 사용하여 노드 교체
    editor.execute([
      ReplaceNodeRequest(existingNodeId: selectedId, newNode: newNode),
    ]);
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

  void _deleteNode(DocumentNode node, String selectedId) {
    // 링크/멘션 등 다른 특수 노드 삭제
    try {
      nodeComponentService.selectNode(null);
      document.deleteNode(selectedId);
      setState(() {});
    } catch (e) {
      ErrorHandler.showError(context, '삭제할 수 없습니다');
    }
  }

  // 이미지 행에서 특정 이미지 드래그 시작 (분리는 드롭 시)
  void _startImageRowDrag(String imageRowId, Offset globalPosition) {
    final rowNode = document.getNodeById(imageRowId) as ImageRowNode?;
    if (rowNode != null) {
      final imageIndex = _findClickedImageIndex(rowNode, globalPosition);

      if (imageIndex != null) {
        dragService.startDrag(imageRowId, context, globalPosition);
        dragService.setSplitImageInfo(imageRowId, imageIndex);
      }
    }
  }

  // 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
  int? _findClickedImageIndex(ImageRowNode rowNode, Offset globalPosition) {
    try {
      final imageCount = rowNode.imageUrls.length;
      final screenWidth = MediaQuery.of(context).size.width;
      final imageWidth = screenWidth / imageCount;

      // 클릭한 X 좌표에 따라 이미지 인덱스 계산
      final clickedIndex = (globalPosition.dx / imageWidth).floor();

      // 유효한 인덱스 범위 확인
      if (clickedIndex >= 0 && clickedIndex < imageCount) {
        return clickedIndex;
      }

      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// 수동 임시저장 (새 버전 생성)
  Future<void> _saveDraft() async {
    try {
      final title = PostExporter.getTitleFromDocument(document);
      final thumbnailUrl = nodeComponentService.getTempThumbnailUrl(
        currentDraftId ?? '',
      );

      // 항상 새로운 버전으로 저장 (existingDraftId를 null로)
      currentDraftId = await draftService.saveDraft(
        editorService: editorService,
        stickerService: stickerService,
        title: title,
        thumbnailUrl: thumbnailUrl ?? '',
        visibility: 'public', // 기본값
        selectedGroupIds: [],
        existingDraftId: null, // 새 버전 생성
      );

      // 저장 스냅샷 마크
      editorService.markSavedSnapshot();
      stickerService.saveInitialState();

      // 임시저장 후에는 매핑 맵을 유지 (계속 작업할 수 있도록)
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '임시저장에 실패했습니다');
      }
    }
  }

  /// 수정된 포스트 저장 (편집 모드 전용)
  Future<void> _saveEditedPost() async {
    try {
      // TODO: implement update API call
      // 1. 현재 문서 상태를 export
      // 2. BlogService.updatePost 호출
      // 3. 성공 시 PostReaderScreen으로 돌아가기
      print('[PostwriteScreen] 수정 완료 버튼 클릭 (구현 예정)');
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '수정에 실패했습니다');
      }
    }
  }

  /// 임시저장 목록 보기
  Future<void> _showDraftList() async {
    try {
      if (!mounted) return;

      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder:
              (_, __, ___) => DraftListOverlay(
                currentDraftId: currentDraftId,
                onLoadDraft: (draftId) async {
                  try {
                    nodeComponentService.clearHighlightedSelectionSilently();
                    nodeComponentService.clearSelectionSilently();
                    composer.clearSelection();
                  } catch (_) {}
                  if (!mounted) return;
                  final success = await draftService.loadDraft(
                    draftId: draftId,
                    editorService: editorService,
                    stickerService: stickerService,
                  );

                  if (success && mounted) {
                    currentDraftId = draftId;

                    // 불러온 상태를 저장 스냅샷으로 간주
                    editorService.markSavedSnapshot();
                    stickerService.saveInitialState();

                    // UI 업데이트
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (mounted) {
                        editorService.updatePublishableStatus();
                        setState(() {});
                      }
                    });
                  } else if (!success && mounted) {
                    ErrorHandler.showError(context, '임시저장을 불러올 수 없습니다');
                  }
                },
              ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '임시저장 목록을 불러올 수 없습니다: $e');
      }
    }
  }
}
