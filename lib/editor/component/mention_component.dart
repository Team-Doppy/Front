import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/editor/utils/config.dart' show EditorConfig;
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/nodes/mention_node.dart';

class MentionComponentViewModel extends SingleColumnLayoutComponentViewModel {
  MentionComponentViewModel({
    required super.nodeId,
    required this.mainAxis,
    required this.usernames,
    required this.fontSize,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final MainAxisAlignment mainAxis;
  final List<String> usernames;
  final double fontSize;

  @override
  SingleColumnLayoutComponentViewModel copy() => MentionComponentViewModel(
    nodeId: nodeId,
    mainAxis: mainAxis,
    usernames: usernames,
    fontSize: fontSize,
  );
}

class MentionComponentBuilder implements ComponentBuilder {
  const MentionComponentBuilder({
    this.dragService,
    this.editor,
    this.focusNode,
    this.onMentionTap,
    this.isDarkMode = false,
  });
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;
  final void Function(List<String> usernames)? onMentionTap;
  final bool isDarkMode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is MentionComponentViewModel) {
      return _MentionComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        mainAxis: viewModel.mainAxis,
        usernames: viewModel.usernames,
        fontSize: viewModel.fontSize,
        dragService: dragService,
        editor: editor,
        focusNode: focusNode,
        onMentionTap: onMentionTap,
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
    if (node is MentionNode) {
      // 인접 문단 정렬 값을 추론하여 정렬 적용
      MainAxisAlignment align = MainAxisAlignment.center;
      final int idx = document.getNodeIndexById(node.id);
      String? alignStr;
      // 이전 문단 우선
      for (int i = idx - 1; i >= 0; i--) {
        final prev = document.getNodeAt(i);
        if (prev is ParagraphNode) {
          alignStr = prev.metadata['textAlign'] as String?;
          break;
        }
      }
      // 다음 문단 보조
      if (alignStr == null) {
        for (int i = idx + 1; i < document.length; i++) {
          final next = document.getNodeAt(i);
          if (next is ParagraphNode) {
            alignStr = next.metadata['textAlign'] as String?;
            break;
          }
        }
      }
      switch (alignStr) {
        case 'left':
          align = MainAxisAlignment.start;
          break;
        case 'right':
          align = MainAxisAlignment.end;
          break;
        case 'center':
        default:
          align = MainAxisAlignment.center;
      }

      final fontSize = (node.metadata['fontSize'] as num?)?.toDouble() ?? 16.0;

      return MentionComponentViewModel(
        nodeId: node.id,
        mainAxis: align,
        usernames: node.usernames,
        fontSize: fontSize,
      );
    }
    return null;
  }
}

class _MentionComponent extends StatefulWidget {
  const _MentionComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.mainAxis,
    required this.usernames,
    required this.fontSize,
    this.dragService,
    this.editor,
    this.focusNode,
    this.onMentionTap,
    this.isDarkMode = false,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final MainAxisAlignment mainAxis;
  final List<String> usernames;
  final double fontSize;
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;
  final void Function(List<String> usernames)? onMentionTap;
  final bool isDarkMode;

  @override
  State<_MentionComponent> createState() => _MentionComponentState();
}

class _MentionComponentState extends State<_MentionComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    // 🎯 읽기/편집 모드 통합: document 가져오기
    Document? doc = widget.editor?.document;
    if (doc == null) {
      // 읽기 모드: SuperEditorState를 통해 document 가져오기
      // ignore: invalid_use_of_visible_for_testing_member
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      // ignore: invalid_use_of_visible_for_testing_member
      doc = seState?.editContext.editor.document;
    }

    final composerSelection = widget.editor?.composer.selection;
    final imageService = context.watch<NodeComponentService>();
    final bool isSelected =
        widget.editor != null && imageService.selectedImageId == widget.nodeId;

    // 🎯 위/아래 인접 노드가 특수 노드인지 확인 (마진 계산용)
    final bool hasSpecialNodeAbove =
        doc == null ? false : _hasNeighborSpecialNode(doc, widget.nodeId, -1);
    final bool hasSpecialNodeBelow =
        doc == null ? false : _hasNeighborSpecialNode(doc, widget.nodeId, 1);

    // 🎯 마진 계산: 위/아래가 ParagraphNode면 4.0, 특수 노드면 더 큰 마진
    final double marginTop =
        hasSpecialNodeAbove ? EditorConfig.specialNodePaddingWithText : 4.0;
    final double marginBottom =
        hasSpecialNodeBelow ? EditorConfig.specialNodePaddingWithText : 4.0;

    // 🎯 downstream 위치에 커서가 있을 때도 selection 효과 표시
    bool isDownstreamSelected = false;
    if (composerSelection != null &&
        composerSelection.isCollapsed &&
        composerSelection.extent.nodeId == widget.nodeId) {
      final position = composerSelection.extent.nodePosition;
      if (position is UpstreamDownstreamNodePosition &&
          position == const UpstreamDownstreamNodePosition.downstream()) {
        isDownstreamSelected = true;
      }
    }

    // 🎯 selection 핸들이 멘션 노드를 포함할 때만, 그리고 경계가 멘션인 경우 Downstream일 때만 하이라이트
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

    if (widget.dragService == null) {
      // 드래그 서비스가 없으면 제스처 없는 버전 반환
      return widget.editor == null
          ? _buildMentionContent(
            isSelected,
            isDownstreamSelected,
            isSelectionHighlighted,
            false,
            marginTop,
            marginBottom,
          )
          : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: _buildMentionContent(
              isSelected,
              isDownstreamSelected,
              isSelectionHighlighted,
              false,
              marginTop,
              marginBottom,
            ),
          );
    }

    return AnimatedBuilder(
      animation: widget.dragService!,
      builder: (context, _) {
        // 🎯 builder 내부에서 계산해야 드래그 상태 변경 시 즉시 반영됨
        final svc = widget.dragService!;
        final dt = svc.dropTarget;

        // ✅ 멘션 병합 미리보기: DragService가 명시적으로 mergeMentions 타겟을 알려준다.
        final bool mergePreview =
            (dt.kind == DropTargetKind.mergeMentions) &&
            (dt.targetNodeId == widget.nodeId) &&
            (svc.draggingNodeId != widget.nodeId);

        // ✅ 드롭라인 표시는 공통 정책(DropLineConfig)으로 통일
        final flags = DropLineConfig.resolve(
          nodeId: widget.nodeId,
          dragService: svc,
        );
        final bool isDraggingMentionSelf =
            (svc.draggingNodeId == widget.nodeId) &&
            (dt.kind == DropTargetKind.mergeMentions);
        final bool showTop =
            !mergePreview && !isDraggingMentionSelf && flags.top;
        final bool showBottom =
            !mergePreview && !isDraggingMentionSelf && flags.bottom;

        // 🎯 제스처가 포함된 위젯 (AnimatedBuilder 내부에서 생성)
        final contentWithGesture =
            widget.editor == null
                ? _buildMentionContent(
                  isSelected,
                  isDownstreamSelected,
                  isSelectionHighlighted,
                  mergePreview,
                  marginTop,
                  marginBottom,
                )
                : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onLongPressStart:
                      widget.editor != null && widget.dragService != null
                          ? (details) {
                            // 🎯 키보드 내리기 + 포커스 해제 (드래그 시작 시)
                            FocusManager.instance.primaryFocus?.unfocus();
                            FocusScope.of(context).unfocus();
                            // 드래그 시작
                            widget.dragService!.startDrag(
                              widget.nodeId,
                              context,
                              details.globalPosition,
                            );
                          }
                          : null,
                  onLongPressMoveUpdate:
                      widget.editor != null && widget.dragService != null
                          ? (details) {
                            // 드래그 업데이트
                            widget.dragService!.updateDrag(
                              details.globalPosition,
                              context,
                            );
                          }
                          : null,
                  onLongPressEnd:
                      widget.editor != null && widget.dragService != null
                          ? (_) {
                            // 드래그 종료
                            widget.dragService!.endDrag();
                          }
                          : null,
                  child: _buildMentionContent(
                    isSelected,
                    isDownstreamSelected,
                    isSelectionHighlighted,
                    mergePreview,
                    marginTop,
                    marginBottom,
                  ),
                );

        return Stack(
          children: [
            contentWithGesture,
            if (showTop)
              Positioned(
                top: 0,
                left: 70,
                right: 70,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedDropLine(
                      child: Container(
                        height: 5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            if (showBottom)
              Positioned(
                bottom: 0,
                left: 70,
                right: 70,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedDropLine(
                      child: Container(
                        height: 5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMentionContent(
    bool isSelected,
    bool isDownstreamSelected,
    bool isSelectionHighlighted,
    bool mergePreview,
    double marginTop,
    double marginBottom,
  ) {
    final CrossAxisAlignment cross =
        widget.mainAxis == MainAxisAlignment.start
            ? CrossAxisAlignment.start
            : widget.mainAxis == MainAxisAlignment.end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;

    // 병합 미리보기 또는 선택 상태일 때 primary 색상
    final shouldUsePrimaryColor =
        mergePreview ||
        isSelected ||
        isDownstreamSelected ||
        isSelectionHighlighted;

    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: EdgeInsets.only(top: marginTop, bottom: marginBottom),
      child: Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children:
            widget.usernames.map((username) {
              return Builder(
                builder: (context) {
                  final defaultTextColor =
                      widget.isDarkMode
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary;
                  final textColor =
                      shouldUsePrimaryColor
                          ? Theme.of(context).colorScheme.primary
                          : defaultTextColor;
                  return AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: widget.fontSize,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '@$username',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: widget.fontSize,
                        ),
                      ),
                    ),
                  );
                },
              );
            }).toList(),
      ),
    );

    return Row(mainAxisAlignment: widget.mainAxis, children: [content]);
  }

  void _handleTap() {
    // 읽기 모드에서는 멘션 탭 처리
    if (widget.editor == null && widget.onMentionTap != null) {
      widget.onMentionTap!(widget.usernames);
      return;
    }

    // 편집 모드에서는 선택 토글
    final editor = widget.editor;
    if (editor == null) return;

    final imageService = context.read<NodeComponentService>();
    final currentSelected = imageService.selectedImageId;
    if (currentSelected == widget.nodeId) {
      imageService.selectNode(null);
    } else {
      imageService.selectImage(widget.nodeId);
    }
  }

  // 🎯 인접 노드가 특수 노드인지 확인 (이미지 컴포넌트의 _hasNeighborImage와 동일한 로직)
  bool _hasNeighborSpecialNode(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;

    // 🎯 바로 인접한 노드 확인
    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        // 바로 인접한 노드가 특수 노드인 경우 (정책은 NodeTypeChecker/config에서 단일 관리)
        if (NodeTypeChecker.isSpecialNode(immediateNeighbor)) {
          return true;
        }

        // 바로 인접한 노드가 빈 ParagraphNode인 경우
        if (immediateNeighbor is ParagraphNode) {
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;

          // 빈 ParagraphNode면 그 다음 노드를 확인
          if (isEmpty) {
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
          } else if (!isEmpty) {
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
        final isEmpty = neighbor.text.text.trim().isEmpty;
        // 비어있지 않으면 텍스트 노드이므로 패딩 필요
        if (!isEmpty) {
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

  // selection이 이 멘션 노드를 포함하는지 계산
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

    // 시작 경계가 이 노드인 경우
    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        // ✅ start 경계는 upstream일 때 포함 (아래→위 드래그 대칭 보장)
        return pos.affinity == TextAffinity.upstream;
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

  // dropLine 표시는 build()에서 paragraph_component 규칙으로 처리한다.

  // DocumentComponent 최소 구현
  @override
  NodePosition getBeginningPosition() =>
      const UpstreamDownstreamNodePosition.upstream();
  @override
  NodePosition getEndPosition() =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  NodePosition? getPositionAtOffset(Offset localOffset) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  Offset getOffsetForPosition(NodePosition nodePosition) => Offset.zero;
  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Rect.zero : (Offset.zero & box.size);
  }

  @override
  Rect getRectForSelection(NodePosition base, NodePosition extent) =>
      getRectForPosition(extent);
  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) =>
      UpstreamDownstreamNodeSelection(
        base: const UpstreamDownstreamNodePosition.upstream(),
        extent: const UpstreamDownstreamNodePosition.upstream(),
      );
  @override
  NodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) => UpstreamDownstreamNodeSelection(
    base: const UpstreamDownstreamNodePosition.upstream(),
    extent: const UpstreamDownstreamNodePosition.downstream(),
  );
  @override
  NodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) => null;
  @override
  NodeSelection getSelectionOfEverything() => UpstreamDownstreamNodeSelection(
    base: const UpstreamDownstreamNodePosition.upstream(),
    extent: const UpstreamDownstreamNodePosition.downstream(),
  );
  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Rect.zero : (Offset.zero & box.size);
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
      const UpstreamDownstreamNodePosition.upstream();
  @override
  NodePosition getEndPositionNearX(double x) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;
}
