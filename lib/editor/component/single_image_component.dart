import 'dart:io';
import 'dart:typed_data';

import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/utils/image_size_utils.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:super_editor/super_editor.dart';

class SingleImageComponentBuilder implements ComponentBuilder {
  const SingleImageComponentBuilder({
    required this.screenWidth, // 🎯 외부에서 전달받음
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
  });

  final double screenWidth; // 🚀 한 번만 계산된 화면 너비
  final dynamic dragService; // DragService 타입을 나중에 import해서 수정
  final bool isEditing;
  final bool isDarkMode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageComponentViewModel) {
      return SingleImageComponent(
        nodeId: componentViewModel.nodeId,
        imageUrl: componentViewModel.imageUrl,
        componentKey: componentContext.componentKey,
        screenWidth: screenWidth, // 🚀 전달
        dragService: dragService,
        isEditing: isEditing,
        isDarkMode: isDarkMode,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is ImageNode) {
      return ImageComponentViewModel(nodeId: node.id, imageUrl: node.imageUrl);
    }
    return null;
  }
}

class SingleImageComponent extends StatefulWidget {
  const SingleImageComponent({
    required this.nodeId,
    required this.imageUrl,
    required this.screenWidth,
    required GlobalKey componentKey,
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final String imageUrl;
  final double screenWidth; // 🚀 최고 효율: 외부에서 한 번만 계산된 값
  final GlobalKey _componentKey;
  final dynamic dragService; // DragService 타입을 나중에 import해서 수정
  final bool isEditing;
  final bool isDarkMode;

  @override
  State<SingleImageComponent> createState() => _SingleImageComponentState();
}

class _SingleImageComponentState extends State<SingleImageComponent>
    with DocumentComponent, TickerProviderStateMixin {
  // 새 프레임이 준비되기 전까지 마지막으로 성공적으로 렌더한 child를 보존해 깜빡임을 줄인다.
  Widget? _lastRenderedChild;
  GlobalKey get componentKey => widget._componentKey;

  // 🎯 특수 노드 사이 클릭 감지 플래그
  bool _isSpecialNodeGapTap = false;

  static const double marginTop = 2.5;
  static const double marginBottom = 2.5;

  // 🎯 성능 최적화: 캐싱된 메타데이터 크기
  Size? _cachedImageSize;
  bool _sizeInitialized = false;

  // 🎯 특수 노드 사이 클릭 감지 (true: 특수 노드 사이 클릭, false: 일반 클릭)
  bool _handleSpecialNodeTap(Offset globalPosition) {
    if (widget.dragService == null) return false;
    final editorService = widget.dragService!.editorService;
    final doc = editorService.document;
    final dragService = widget.dragService!;

    // 자신의 인덱스와 Rect 확인
    final currentNodeIndex = doc.getNodeIndexById(widget.nodeId);
    if (currentNodeIndex == -1) return false;

    final nodeRect = dragService.getNodeGlobalRect(widget.nodeId);
    if (nodeRect == null) return false;

    // 🎯 위쪽 이웃 노드 확인
    if (currentNodeIndex > 0) {
      final prevNode = doc.getNodeAt(currentNodeIndex - 1);
      if (prevNode != null) {
        if (NodeTypeChecker.isSpecialNode(prevNode)) {
          final prevRect = dragService.getNodeGlobalRect(prevNode.id);
          if (prevRect != null) {
            // 위쪽 노드와 자신 사이의 간격 확인 (위쪽 노드 아래 20px ~ 자신 위쪽 20px)
            final gapTop = prevRect.bottom - 20;
            final gapBottom = nodeRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }

    // 🎯 아래쪽 이웃 노드 확인
    if (currentNodeIndex < doc.nodeCount - 1) {
      final nextNode = doc.getNodeAt(currentNodeIndex + 1);
      if (nextNode != null) {
        if (NodeTypeChecker.isSpecialNode(nextNode)) {
          final nextRect = dragService.getNodeGlobalRect(nextNode.id);
          if (nextRect != null) {
            // 자신과 아래쪽 노드 사이의 간격 확인 (자신 아래 20px ~ 아래쪽 노드 위쪽 20px)
            final gapTop = nodeRect.bottom - 20;
            final gapBottom = nextRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex + 1);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  late final AnimationController _controller;
  // 스포일러 해제 스캐터 이펙트
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  bool _wasSpoilerVisible = false;

  @override
  void initState() {
    super.initState();

    // 🎯 메타데이터에서 이미지 크기 미리 로드 (shimmer 최적화)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getImageSizeFromMetadata(); // 캐싱됨
    });

    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 1300));
    _scatterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (mounted) setState(() => _scatterActive = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scatterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 편집 모드에서만 selection 체크 (성능 최적화)
    // 🎯 읽기 모드에서도 doc에 접근하여 특수 노드 간격 확인 (포스트 라이트와 동일하게)
    DocumentSelection? composerSelection;
    Document? doc;
    // ignore: invalid_use_of_visible_for_testing_member
    SuperEditorState? seState;
    // ignore: invalid_use_of_visible_for_testing_member
    seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    doc = seState?.editContext.editor.document;
    if (widget.isEditing) {
      // ignore: invalid_use_of_visible_for_testing_member
      composerSelection = seState?.editContext.composer.selection;
    }
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);

    // 🎯 RepaintBoundary로 감싸서 키보드 애니메이션 시 불필요한 repaint 방지
    return RepaintBoundary(
      child: Column(
        children: [
          if (!hasImageAbove)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
          // 실제 이미지 내용 + 좌/우 세로 라인 (머지 모드에서)
          LayoutBuilder(
            builder: (context, constraints) {
              debugPrint(
                '[SingleImage] LayoutBuilder 호출: nodeId=${widget.nodeId}, constraints.maxWidth=${constraints.maxWidth}, screenWidth=${widget.screenWidth}',
              );

              // 🎯 성능 최적화: context.watch → context.select로 변경하여 필요한 부분만 rebuild
              final editedBytes = context
                  .select<NodeComponentService, Uint8List?>(
                    (service) => service.getEditedBytes(widget.nodeId),
                  );
              // 🎯 이미지 자체도 RepaintBoundary로 감싸서 키보드 애니메이션 시 repaint 방지
              final image = RepaintBoundary(
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: _buildImage(editedBytes),
                ),
              );

              // 🎯 업로드 중 상태 판정 (메타데이터 + 실제 업로드 태스크 존재 여부)
              // ignore: invalid_use_of_visible_for_testing_member
              final doc = seState?.editContext.editor.document;
              // 🎯 업로드 중 상태 확인 (편집 모드에서만, 읽기 전용 모드에서는 항상 false)
              bool isUploading = false;
              if (widget.isEditing) {
                try {
                  // 🎯 성능 최적화: context.watch → context.select로 변경
                  isUploading = context.select<UploadService, bool>(
                    (service) => service.hasActiveUploadForRef(widget.nodeId),
                  );
                } catch (e) {
                  debugPrint('[SingleImage] UploadService 확인 실패: $e');
                }
              }

              // 🎯 성능 최적화: context.watch → context.select로 변경
              final isSelected = context.select<NodeComponentService, bool>(
                (service) => service.selectedImageId == widget.nodeId,
              );

              // 🎯 downstream 위치에 커서가 있을 때도 selection 효과 표시
              bool isDownstreamSelected = false;
              if (composerSelection != null &&
                  composerSelection.isCollapsed &&
                  composerSelection.extent.nodeId == widget.nodeId) {
                final position = composerSelection.extent.nodePosition;
                if (position is UpstreamDownstreamNodePosition &&
                    position ==
                        const UpstreamDownstreamNodePosition.downstream()) {
                  isDownstreamSelected = true;
                }
              }
              // selection 핸들이 이미지 노드를 포함할 때만, 그리고 경계가 이미지인 경우 Downstream일 때만 하이라이트

              bool isSelectionHighlighted = false;
              if (composerSelection != null &&
                  !composerSelection.isCollapsed &&
                  doc != null) {
                isSelectionHighlighted = _isNodeCoveredBySelection(
                  doc,
                  composerSelection,
                  widget.nodeId,
                );
              }

              // 스포일러 상태 (헬퍼 사용)
              bool isSpoilerFlag = false;
              try {
                final node = doc?.getNodeById(widget.nodeId);
                Map<String, dynamic>? meta;
                if (node is ImageNode) {
                  meta = (node as dynamic).metadata as Map<String, dynamic>?;
                }
                // 🎯 context.select로 변경하여 스포일러 변경사항 감지
                isSpoilerFlag = context.select<NodeComponentService, bool>(
                  (service) =>
                      service.shouldShowImageSpoiler(widget.nodeId, meta),
                );
              } catch (_) {}

              // 댓글 배지 표시 값 추출
              bool hasCommentsFlag = false;

              try {
                final node = doc?.getNodeById(widget.nodeId);
                if (node is ImageNode) {
                  final meta =
                      (node as dynamic).metadata as Map<String, dynamic>?;
                  if (meta != null) {
                    hasCommentsFlag = meta['hasComments'] == true;
                  }
                }
              } catch (_) {}

              // 해제 직전 → 직후 전환 감지하여 스캐터 실행
              if (_wasSpoilerVisible &&
                  !isSpoilerFlag &&
                  _scatterCtrl.status != AnimationStatus.forward) {
                _scatterActive = true;
                _scatterCtrl
                  ..reset()
                  ..forward();
              }
              _wasSpoilerVisible = isSpoilerFlag;

              return Stack(
                children: [
                  // 🎯 편집 모드에서 탭/롱프레스 처리
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
                              final isGapTap = _handleSpecialNodeTap(
                                details.globalPosition,
                              );
                              setState(() {
                                _isSpecialNodeGapTap = isGapTap;
                              });
                            }
                            : null,
                    onTap:
                        widget.isEditing && widget.dragService != null
                            ? () {
                              // 🎯 특수 노드 사이 클릭이면 셀렉 보류
                              if (_isSpecialNodeGapTap) {
                                setState(() {
                                  _isSpecialNodeGapTap = false;
                                });
                                return;
                              }

                              debugPrint(
                                '[SingleImageComponent] onTap 호출됨: nodeId=${widget.nodeId}',
                              );
                              // 노드 선택/해제
                              final imageService =
                                  context.read<NodeComponentService>();
                              final currentSelected =
                                  imageService.selectedImageId;
                              if (currentSelected == widget.nodeId) {
                                // 같은 노드 재탭: 선택 해제
                                debugPrint('[SingleImageComponent] 선택 해제');
                                imageService.selectNode(null);
                                widget.dragService?.invalidateNodeRectCache();
                              } else {
                                // 다른 노드 선택
                                debugPrint(
                                  '[SingleImageComponent] 노드 선택: nodeId=${widget.nodeId}',
                                );
                                imageService.selectNode(widget.nodeId);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    widget.dragService
                                        ?.invalidateNodeRectCache();
                                  }
                                });
                              }
                            }
                            : null,
                    onLongPressStart:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 🎯 키보드 내리기 + 포커스 해제 (드래그 시작 시)
                              FocusManager.instance.primaryFocus?.unfocus();
                              FocusScope.of(context).unfocus();
                              // 드래그 시작
                              widget.dragService?.startDrag(
                                widget.nodeId,
                                context,
                                details.globalPosition,
                              );
                            }
                            : null,
                    onLongPressMoveUpdate:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 드래그 업데이트
                              widget.dragService?.updateDrag(
                                details.globalPosition,
                                context,
                              );
                            }
                            : null,
                    onLongPressEnd:
                        widget.isEditing && widget.dragService != null
                            ? (_) {
                              // 드래그 종료
                              widget.dragService?.endDrag();
                            }
                            : null,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: marginTop,
                        bottom: marginBottom,
                      ),
                      child: Stack(
                        children: [
                          image,
                          if (hasCommentsFlag)
                            Positioned(
                              top: 4,
                              right: 5,
                              child: IgnorePointer(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: SvgPicture.asset(
                                    'assets/icons/comment.svg',
                                    width: 12,
                                    height: 12,
                                    colorFilter: ColorFilter.mode(
                                      Theme.of(context).colorScheme.surface,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (isSpoilerFlag)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Builder(
                                  builder: (context) {
                                    final brightness =
                                        Theme.of(context).brightness;
                                    final isLightTheme =
                                        brightness == Brightness.light;
                                    return Stack(
                                      children: [
                                        // ✅ 기본 블러 레이어 (전체 채우기)
                                        Positioned.fill(
                                          child: ClipRect(
                                            child: BackdropFilter(
                                              filter: ui.ImageFilter.blur(
                                                sigmaX: 20,
                                                sigmaY: 20,
                                              ),
                                              child: Container(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: AnimatedBuilder(
                                            animation: _controller,
                                            builder: (context, _) {
                                              return CustomPaint(
                                                painter: _ImageSpoilerPainter(
                                                  phase: _controller.value,
                                                  isEditing: widget.isEditing,
                                                  // 배경 마스크 제거 → 블러만 적용
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  // 점은 항상 흰색
                                                  dotColor: Colors.white,
                                                  isLightTheme: isLightTheme,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          if (_scatterActive)
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: true,
                                child: Builder(
                                  builder: (context) {
                                    final brightness =
                                        Theme.of(context).brightness;
                                    final isLightTheme =
                                        brightness == Brightness.light;
                                    return AnimatedBuilder(
                                      animation: _scatterCtrl,
                                      builder: (context, _) {
                                        return CustomPaint(
                                          painter: _ImageSpoilerScatterPainter(
                                            t: _scatterCtrl.value,
                                            // 점은 항상 흰색
                                            dotColor: Colors.white,
                                            isLightTheme: isLightTheme,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          if (isUploading)
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: false,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 4,
                                      color: Colors.white.withOpacity(1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (isSelectionHighlighted)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  color: AppColors.primary.withOpacity(0.4),
                                ),
                              ),
                            ),
                          if (isSelected || isDownstreamSelected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.primary,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!isUploading && _shouldShowTopDropLine())
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Container(height: 5, color: AppColors.primary),
                      ),
                    ),

                  if (!isUploading && _shouldShowLeftVerticalLine())
                    Positioned(
                      top: marginTop,
                      bottom: marginBottom,
                      left: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Container(width: 5, color: AppColors.primary),
                      ),
                    ),
                  if (!isUploading && _shouldShowRightVerticalLine())
                    Positioned(
                      top: marginTop,
                      bottom: marginBottom,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Container(width: 5, color: AppColors.primary),
                      ),
                    ),
                  if (!isUploading && _shouldShowBottomDropLine())
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Container(height: 5, color: AppColors.primary),
                      ),
                    ),
                ],
              );
            },
          ),
          if (!hasImageBelow)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
        ],
      ),
    );
  }

  // DocumentComponent 필수 메서드들
  @override
  NodePosition getBeginningPosition() =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  NodePosition getEndPosition() => UpstreamDownstreamNodePosition.downstream();

  @override
  NodePosition? getPositionAtOffset(Offset localOffset) =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) => Offset.zero;

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Rect.zero;
    }
    return Offset.zero & renderBox.size;
  }

  @override
  Rect getRectForSelection(
    NodePosition baseNodePosition,
    NodePosition extentNodePosition,
  ) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Rect.zero;
    }
    return Offset.zero & renderBox.size;
  }

  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) =>
      UpstreamDownstreamNodeSelection(
        base: UpstreamDownstreamNodePosition.upstream(),
        extent: UpstreamDownstreamNodePosition.upstream(),
      );

  @override
  NodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) => UpstreamDownstreamNodeSelection(
    base: UpstreamDownstreamNodePosition.upstream(),
    extent: UpstreamDownstreamNodePosition.downstream(),
  );

  @override
  NodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) => null;

  @override
  NodeSelection getSelectionOfEverything() => UpstreamDownstreamNodeSelection(
    base: UpstreamDownstreamNodePosition.upstream(),
    extent: UpstreamDownstreamNodePosition.downstream(),
  );

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Rect.zero;
    }

    // upstream/downstream 위치일 때는 커서를 표시하지 않음 (사용자 요청)
    // selection 효과만 표시
    if (nodePosition is UpstreamDownstreamNodePosition) {
      return Offset.zero & renderBox.size;
    }

    return Offset.zero & renderBox.size;
  }

  @override
  bool isVisualSelectionSupported() => false;

  @override
  NodePosition? movePositionLeft(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) => null;

  @override
  NodePosition? movePositionRight(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) => null;

  @override
  NodePosition? movePositionUp(NodePosition currentPosition) => null;

  @override
  NodePosition? movePositionDown(NodePosition currentPosition) => null;

  @override
  NodePosition getBeginningPositionNearX(double x) =>
      // 🎯 upstream 위치로 커서가 가지 못하도록 항상 downstream 반환
      const UpstreamDownstreamNodePosition.downstream();

  @override
  NodePosition getEndPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  bool _shouldShowTopDropLine() {
    return DropLineConfig.shouldShowTopDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowBottomDropLine() {
    return DropLineConfig.shouldShowBottomDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowLeftVerticalLine() {
    return DropLineConfig.shouldShowLeftVerticalLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowRightVerticalLine() {
    return DropLineConfig.shouldShowRightVerticalLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  // selection이 이 이미지 노드를 포함하는지 계산. 경계가 이미지인 경우 Downstream일 때만 포함
  bool _isNodeCoveredBySelection(
    Document doc,
    DocumentSelection selection,
    String nodeId,
  ) {
    final baseIndex = doc.getNodeIndexById(selection.base.nodeId);
    final extentIndex = doc.getNodeIndexById(selection.extent.nodeId);
    final myIndex = doc.getNodeIndexById(nodeId);
    if (baseIndex == -1 || extentIndex == -1 || myIndex == -1) return false;

    final start = math.min(baseIndex, extentIndex);
    final end = math.max(baseIndex, extentIndex);
    if (myIndex < start || myIndex > end) return false;

    // 시작 경계가 이 노드인 경우: base/extent 중 누가 start인지에 따라 affinity 체크
    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    // 끝 경계가 이 노드인 경우
    if (myIndex == end) {
      final boundary = extentIndex == end ? selection.extent : selection.base;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    // 범위 내부에 완전히 포함
    return true;
  }

  /// 🎯 메타데이터에서 이미지 크기 가져오기 (shimmer 크기 결정)
  /// 최적화: 한 번만 조회하고 캐싱, 중복 로직 제거
  Size? _getImageSizeFromMetadata() {
    // 🚀 이미 조회했으면 캐시 반환
    if (_sizeInitialized) return _cachedImageSize;

    _sizeInitialized = true; // 실패해도 재시도 방지

    try {
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      final doc = seState?.editContext.editor.document;
      final node = doc?.getNodeById(widget.nodeId);

      if (node is! ImageNode) return null;

      final meta = (node as dynamic).metadata as Map<String, dynamic>?;
      if (meta == null) return null;

      final dimensions = meta['imageDimensions'] as Map<String, dynamic>?;
      if (dimensions == null || dimensions.isEmpty) return null;

      // URL 또는 로컬 경로로 크기 찾기 (우선순위: imageUrl > localPath)
      final sizeData =
          dimensions[widget.imageUrl] ??
          (meta['localPath'] != null
              ? dimensions[meta['localPath'].toString()]
              : null);

      if (sizeData is Map<String, dynamic> &&
          sizeData['width'] != null &&
          sizeData['height'] != null) {
        _cachedImageSize = Size(
          (sizeData['width'] as num).toDouble(),
          (sizeData['height'] as num).toDouble(),
        );
      }
    } catch (e) {
      debugPrint('[SingleImage] 메타데이터 크기 조회 실패: $e');
    }

    return _cachedImageSize;
  }

  /// 🎯 이미지 크기 측정 및 저장 (편집 모드 전용)
  /// 🎯 RowImage 스타일: 간결한 구현
  void _measureAndSaveImageSize() async {
    if (!widget.isEditing || !mounted) {
      return;
    }

    // 🎯 메타데이터에서 크기를 먼저 확인 (임시저장 등에서 이미 저장된 경우 스킵)
    if (_cachedImageSize == null) {
      final metaSize = _getImageSizeFromMetadata();
      if (metaSize != null) {
        // 메타데이터에 크기가 있으면 측정 불필요
        return;
      }
    } else {
      // 이미 캐시된 크기가 있으면 측정 불필요
      return;
    }

    try {
      // 🎯 공통 유틸리티 사용: 전체 이미지 다운로드 후 크기 추출
      final size = await ImageSizeUtils.measureImageSize(widget.imageUrl);

      if (!mounted) return;

      if (size != null) {
        _cachedImageSize = size;
        debugPrint(
          '[SingleImage] ✅ 이미지 크기 측정 완료: ${widget.imageUrl} -> ${size.width.toInt()}x${size.height.toInt()}',
        );
        _saveImageSizeToMetadata(size);
      } else {
        // 🎯 HEIC 파일 등은 ImageProvider로 재시도
        if (ImageSizeUtils.isHeicFile(widget.imageUrl)) {
          debugPrint('[SingleImage] 🔄 HEIC 파일: ImageProvider로 재시도');
          final providerSize =
              await ImageSizeUtils.extractSizeFromImageProvider(
                widget.imageUrl,
              );
          if (providerSize != null && mounted) {
            _cachedImageSize = providerSize;
            debugPrint(
              '[SingleImage] ✅ ImageProvider에서 크기 추출: ${widget.imageUrl} -> ${providerSize.width.toInt()}x${providerSize.height.toInt()}',
            );
            _saveImageSizeToMetadata(providerSize);
          }
        }
      }
    } catch (e) {
      // 🎯 크기 측정 실패는 조용히 처리 (이미지 표시에는 영향 없음)
      debugPrint('[SingleImage] ⚠️ 크기 측정 실패: ${widget.imageUrl} - $e');
    }
  }

  /// 🎯 측정된 이미지 크기를 메타데이터에 저장 (편집 모드 전용)
  /// 🎯 RowImage 스타일: 간결하고 최적화된 구현
  void _saveImageSizeToMetadata(Size size) {
    if (!widget.isEditing) return;

    try {
      final editorService = _getEditorService();
      if (editorService == null) {
        assert(() {
          debugPrint('[SingleImage] ⚠️ EditorService를 찾을 수 없어서 저장 실패');
          return true;
        }());
        return;
      }

      final doc = editorService.document;
      final node = doc.getNodeById(widget.nodeId);

      if (node is ImageNode) {
        final meta = node.metadata;
        final imageDimensions = Map<String, dynamic>.from(
          (meta['imageDimensions'] as Map<String, dynamic>?) ?? {},
        );

        final sizeData = {
          'width': size.width.toInt(),
          'height': size.height.toInt(),
        };

        // 🎯 성능 최적화: 이미 같은 크기가 저장되어 있으면 스킵
        final existingSize =
            imageDimensions[widget.imageUrl] as Map<String, dynamic>?;
        if (existingSize != null &&
            existingSize['width'] == size.width.toInt() &&
            existingSize['height'] == size.height.toInt()) {
          return; // 동일한 크기는 재저장하지 않음
        }

        // 🎯 로컬 경로를 키로 저장
        imageDimensions[widget.imageUrl] = sizeData;

        // 🎯 성능 최적화: 업로드된 네트워크 URL도 키로 저장 (나중에 매칭 용이)
        final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
        if (uploadedUrls != null && uploadedUrls.containsKey(widget.imageUrl)) {
          final networkUrl = uploadedUrls[widget.imageUrl].toString();
          if (networkUrl.isNotEmpty) {
            imageDimensions[networkUrl] = sizeData;
          }
        }

        final updatedNode = ImageNode(
          id: node.id,
          imageUrl: node.imageUrl,
          metadata: {...meta, 'imageDimensions': imageDimensions},
        );

        editorService.document.replaceNodeById(widget.nodeId, updatedNode);

        assert(() {
          debugPrint(
            '[SingleImage] ✅ 이미지 크기 저장 완료: nodeId=${widget.nodeId}, url=${widget.imageUrl}, size=${size.width.toInt()}x${size.height.toInt()}',
          );
          return true;
        }());
      } else {
        assert(() {
          debugPrint(
            '[SingleImage] ⚠️ ImageNode를 찾을 수 없음: nodeId=${widget.nodeId}',
          );
          return true;
        }());
      }
    } catch (e, stackTrace) {
      assert(() {
        debugPrint('[SingleImage] ❌ 메타데이터 저장 실패: $e');
        debugPrint('[SingleImage] 스택: $stackTrace');
        return true;
      }());
    }
  }

  /// 🎯 성능 최적화: EditorService 캐싱 조회 (RowImage 스타일)
  EditorService? _getEditorService() {
    // 🎯 dragService를 통해 editorService 접근 (Provider context 문제 방지)
    if (widget.dragService != null) {
      try {
        final editorService =
            (widget.dragService as dynamic).editorService as EditorService?;
        if (editorService != null) {
          return editorService;
        }
      } catch (e) {
        assert(() {
          debugPrint('[SingleImage] dragService로 EditorService 접근 실패: $e');
          return true;
        }());
      }
    }

    // 🎯 dragService가 없으면 Provider로 접근 시도 (fallback)
    try {
      return Provider.of<EditorService>(context, listen: false);
    } catch (e) {
      assert(() {
        debugPrint('[SingleImage] Provider로 EditorService 접근 실패: $e');
        return true;
      }());
      return null;
    }
  }

  // 이미지 위젯 생성: editedBytes > (업로드중: metadata.localPath) > 로컬 파일 경로 > 네트워크 URL 순서
  Widget _buildImage(Uint8List? editedBytes) {
    if (editedBytes != null) {
      final double w = widget.screenWidth; // 🚀 최고 효율: prop 사용
      return Image.memory(
        editedBytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded || frame != null) {
            _lastRenderedChild = child;
            // 🎯 편집 모드에서만 메타데이터 없을 때 크기 측정 (이미지 업로드 시)
            // 보기 모드에서는 메타데이터 필수 (재계산 안 함)
            if (widget.isEditing && _cachedImageSize == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _measureAndSaveImageSize();
                }
              });
            }
            return child;
          }
          // 🎯 메타데이터에서 실제 크기 가져오기
          final metaSize = _getImageSizeFromMetadata();
          final h =
              metaSize != null
                  ? (w * metaSize.height / metaSize.width) // 실제 비율
                  : w / (4 / 5); // 기본 비율
          return _lastRenderedChild ??
              ShimmerBox(width: w, height: h, isDarkMode: widget.isDarkMode);
        },
      );
    }

    final url = widget.imageUrl;

    // 업로드 중이면 metadata.localPath로 미리보기
    try {
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      final doc = seState?.editContext.editor.document;
      final node = doc?.getNodeById(widget.nodeId);
      if (node is ImageNode) {
        final meta = (node as dynamic).metadata as Map<String, dynamic>?;
        final localPath = meta != null ? (meta['localPath']?.toString()) : null;
        if ((url.isEmpty || !_isNetworkUrl(url)) &&
            localPath != null &&
            localPath.isNotEmpty) {
          final filePath =
              localPath.startsWith('file://')
                  ? localPath.substring(7)
                  : localPath;
          final double w = widget.screenWidth; // 🚀 최고 효율: prop 사용
          return Image.file(
            File(filePath),
            key: ValueKey('$filePath-${Theme.of(context).brightness}'),
            fit: BoxFit.contain,
            cacheWidth: w.isFinite ? w.toInt() : null,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded || frame != null) {
                _lastRenderedChild = child;
                // 🎯 편집 모드에서만 메타데이터 없을 때 크기 측정
                if (widget.isEditing && _cachedImageSize == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _measureAndSaveImageSize();
                    }
                  });
                }
                return child;
              }
              // 🎯 메타데이터에서 실제 크기 가져오기
              final metaSize = _getImageSizeFromMetadata();
              final h =
                  metaSize != null
                      ? (w * metaSize.height / metaSize.width) // 실제 비율
                      : w / (4 / 5); // 기본 비율
              return _lastRenderedChild ??
                  ShimmerBox(
                    width: w,
                    height: h,
                    isDarkMode: widget.isDarkMode,
                  );
            },
            errorBuilder:
                (context, error, stack) => ImageErrorPlaceholder(
                  width: widget.screenWidth, // 🎯 성능 최적화: MediaQuery 제거
                ),
          );
        }
      }
    } catch (_) {}
    if (_isLocalPath(url)) {
      final filePath = url.startsWith('file://') ? url.substring(7) : url;
      return Image.file(
        File(filePath),
        key: ValueKey('$filePath-${Theme.of(context).brightness}'),
        fit: BoxFit.contain,
        errorBuilder:
            (context, error, stack) => ImageErrorPlaceholder(
              width: widget.screenWidth, // 🎯 성능 최적화: MediaQuery 제거
            ),
      );
    }

    return Image.network(
      url,
      key: ValueKey('$url-${Theme.of(context).brightness}'),
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        // 프리로드(캐시 히트)된 경우 즉시 child 렌더 → 쉬머 미노출
        if (wasSyncLoaded || frame != null) {
          _lastRenderedChild = child;
          // 🎯 편집 모드에서만 메타데이터 없을 때 크기 측정 (이미지 업로드 시)
          // 보기 모드에서는 메타데이터 필수 (재계산 안 함)
          if (widget.isEditing && _cachedImageSize == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _measureAndSaveImageSize();
              }
            });
          }
          return child;
        }
        final w = widget.screenWidth; // 🎯 성능 최적화: MediaQuery 제거
        // 🎯 메타데이터에서 실제 크기 가져오기
        final metaSize = _getImageSizeFromMetadata();
        final h =
            metaSize != null
                ? (w * metaSize.height / metaSize.width) // 실제 비율
                : w / (4 / 5); // 기본 비율
        return _lastRenderedChild ??
            ShimmerBox(width: w, height: h, isDarkMode: widget.isDarkMode);
      },
      errorBuilder:
          (context, error, stack) => ImageErrorPlaceholder(
            width: widget.screenWidth, // 🎯 성능 최적화: MediaQuery 제거
            height: widget.screenWidth / (4 / 5),
          ),
    );
  }

  bool _isNetworkUrl(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  bool _isLocalPath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return false;
    if (path.startsWith('file://')) return true;
    return path.startsWith('/') ||
        path.contains('/Application/') ||
        path.contains('/Documents/');
  }

  bool _hasNeighborImage(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;

    // 🎯 바로 인접한 노드 확인
    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        // 바로 인접한 노드가 특수 노드인 경우
        if (immediateNeighbor is ImageNode ||
            immediateNeighbor is ImageRowNode ||
            immediateNeighbor is PageViewImageNode ||
            immediateNeighbor is ClipNode ||
            immediateNeighbor is LinkNode) {
          return true;
        }

        // 바로 인접한 노드가 빈 ParagraphNode인 경우
        if (immediateNeighbor is ParagraphNode) {
          // ignore: deprecated_member_use
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;
          final isTitle = immediateNeighbor.metadata['isTitle'] == true;

          // 빈 ParagraphNode면 그 다음 노드를 확인
          if (!isTitle && isEmpty) {
            // 빈 ParagraphNode 다음 노드 확인
            final nextIndex = immediateIndex + direction;
            if (nextIndex >= 0 && nextIndex < doc.nodeCount) {
              final nextNeighbor = doc.getNodeAt(nextIndex);
              if (NodeTypeChecker.isSpecialNode(nextNeighbor)) {
                // 빈 ParagraphNode를 사이에 둔 특수 노드 → 패딩 필요 (false 반환)
                return false;
              }
            }
            // 빈 ParagraphNode 다음에 특수 노드가 없으면 계속 검색
          } else if (!isTitle && !isEmpty) {
            // 텍스트가 있는 ParagraphNode → 패딩 필요
            return false;
          }
        } else {
          // 다른 타입의 노드면 패딩 필요
          return false;
        }
      }
    }

    // 🎯 빈 ParagraphNode를 건너뛰고 실제 특수 노드나 텍스트가 있는 노드를 찾음
    int searchIndex = myIndex + direction;
    while (searchIndex >= 0 && searchIndex < doc.nodeCount) {
      final neighbor = doc.getNodeAt(searchIndex);
      if (neighbor == null) break;

      // 특수 노드인 경우
      if (NodeTypeChecker.isSpecialNode(neighbor)) {
        return true;
      }

      // 빈 ParagraphNode가 아니면 (텍스트가 있는 경우) 패딩 필요
      if (neighbor is ParagraphNode) {
        // ignore: deprecated_member_use
        final isEmpty = neighbor.text.text.trim().isEmpty;
        final isTitle = neighbor.metadata['isTitle'] == true;
        // 제목이 아니고 비어있지 않으면 텍스트 노드이므로 패딩 필요
        if (!isTitle && !isEmpty) {
          return false; // 텍스트 노드가 있으면 패딩 필요
        }
        // 빈 ParagraphNode면 계속 검색
      } else {
        // 다른 타입의 노드면 패딩 필요
        return false;
      }

      searchIndex += direction;
    }

    return false;
  }
}

class _ImageSpoilerPainter extends CustomPainter {
  final double phase;
  final bool isEditing;
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;
  _ImageSpoilerPainter({
    required this.phase,
    required this.isEditing,
    required this.backgroundColor,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 초기 프레임 등에서 Size가 0인 경우 NaN이 발생하지 않도록 보호
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final mask = Paint()..style = PaintingStyle.fill;
    // 배경 칠하기는 명시적으로 투명색이 아닌 경우에만 수행
    // (Colors.transparent.withOpacity(1.0) → 불투명한 검정 문제 방지)
    if (backgroundColor.alpha != 0) {
      final double alpha = isEditing ? 0.4 : 1.0;
      if (alpha > 0) {
        mask.color = backgroundColor.withOpacity(alpha);
        canvas.drawRect(rect, mask);
      }
    }
    // 점을 더 선명하게 보이도록 높은 불투명도
    final dotOpacity = isLightTheme ? 0.9 : 0.95;
    final dot =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(dotOpacity);

    final area = rect.width * rect.height;
    // 밀도 상향: 큰 이미지에서도 충분한 알갱이 수 유지 (성능 고려)
    final count =
        isEditing
            ? math.max(300, (area / 1200).floor())
            : math.max(400, (area / 900).floor());
    // 속도 낮춤
    final double t = phase * (2 * math.pi) * 1.6;

    // 기본 점들 그리기 (크기 2.2, 움직임/깜빡임 강화)
    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 486187739);
      final r = math.Random(seed);
      final baseX = r.nextDouble() * rect.width;
      final baseY = r.nextDouble() * rect.height;
      // 진폭 낮춤 (움직임 강도 감소)
      final amp = 1.0 + r.nextDouble() * 5.0; // 1~6px
      final ox = math.sin(t + i * 0.21) * amp;
      final oy = math.cos(t * 0.9 + i * 0.13) * amp;
      double x = baseX + ox;
      double y = baseY + oy;
      // width/height가 0일 경우 나눗셈으로 NaN이 발생할 수 있으므로 방어
      if (rect.width > 0)
        x = x % rect.width;
      else
        x = 0;
      if (rect.height > 0)
        y = y % rect.height;
      else
        y = 0;
      if (x < 0) x += rect.width;
      if (y < 0) y += rect.height;
      // 별 깜빡임 효과: 점마다 약간 다른 투명도 변조
      final twinkle = 0.7 + 0.3 * math.sin(t * 1.3 + i * 0.5);
      final p = dot..color = dot.color.withOpacity(dotOpacity * twinkle);
      // 알갱이 크기 축소
      final sizePx = 1.0 + r.nextDouble() * 1.4; // 1.0~2.4px 원형
      canvas.drawCircle(Offset(x, y), sizePx / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ImageSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.isEditing != isEditing;
  }
}

// 이미지 스포일러 해제 시 파티클 흩어짐 이펙트
class _ImageSpoilerScatterPainter extends CustomPainter {
  final double t; // 0..1 진행도
  final Color dotColor;
  final bool isLightTheme;
  _ImageSpoilerScatterPainter({
    required this.t,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseOpacity = isLightTheme ? 0.4 : 0.6;
    final fade = (1.0 - Curves.easeOut.transform(t)).clamp(0.0, 1.0);
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(baseOpacity * fade);

    final area = rect.width * rect.height;
    final count = math.max(80, (area / 220).floor());
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 1009);
      final r = math.Random(seed);
      final rx = r.nextDouble() * rect.width;
      final ry = r.nextDouble() * rect.height;
      final startX = rect.left + rx;
      final startY = rect.top + ry;
      // 중심에서 방사형 퍼짐
      final dirX = (startX - cx);
      final dirY = (startY - cy);
      final dirLen = math.sqrt(dirX * dirX + dirY * dirY) + 0.001;
      final nx = dirX / dirLen;
      final ny = dirY / dirLen;
      final speed = 30 + r.nextDouble() * 44; // px
      final move = Curves.easeOutQuad.transform(t) * speed;
      final x = startX + nx * move;
      final y = startY + ny * move;
      final sz = 1.2 + (1.8 * (1.0 - t));
      canvas.drawRect(Rect.fromLTWH(x, y, sz, sz), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ImageSpoilerScatterPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}
