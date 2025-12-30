import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';

// 언급 블록 노드
class DividerNode extends BlockNode {
  DividerNode({required this.id});

  @override
  final String id;

  @override
  bool get isDeletable => true;

  @override
  bool containsPosition(Object position) =>
      position is UpstreamDownstreamNodePosition;

  @override
  UpstreamDownstreamNodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    return UpstreamDownstreamNodeSelection(
      base: base as UpstreamDownstreamNodePosition,
      extent: extent as UpstreamDownstreamNodePosition,
    );
  }

  @override
  UpstreamDownstreamNodePosition selectDownstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.upstream();

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      DividerNode(id: id);

  @override
  String? copyContent(NodeSelection selection) => null;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      DividerNode(id: id);
}

class DividerComponentViewModel extends SingleColumnLayoutComponentViewModel {
  DividerComponentViewModel({required super.nodeId, required this.mainAxis})
    : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final MainAxisAlignment mainAxis;

  @override
  SingleColumnLayoutComponentViewModel copy() =>
      DividerComponentViewModel(nodeId: nodeId, mainAxis: mainAxis);
}

class DividerComponentBuilder implements ComponentBuilder {
  const DividerComponentBuilder({
    this.dragService,
    this.editor,
    this.focusNode,
  });
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is DividerComponentViewModel) {
      return _DividerComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        mainAxis: viewModel.mainAxis,
        dragService: dragService,
        editor: editor,
        focusNode: focusNode,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is DividerNode) {
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

      return DividerComponentViewModel(nodeId: node.id, mainAxis: align);
    }
    return null;
  }
}

class _DividerComponent extends StatefulWidget {
  const _DividerComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.mainAxis,
    this.dragService,
    this.editor,
    this.focusNode,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final MainAxisAlignment mainAxis;
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;

  @override
  State<_DividerComponent> createState() => _DividerComponentState();
}

class _DividerComponentState extends State<_DividerComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    final pillContent = Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Builder(
        builder: (context) {
          final CrossAxisAlignment cross =
              widget.mainAxis == MainAxisAlignment.start
                  ? CrossAxisAlignment.start
                  : widget.mainAxis == MainAxisAlignment.end
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center;
          return Column(
            crossAxisAlignment: cross,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 150,
                  height: 1.5,
                  color: AppColors.darkTextSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );

    final aligned = Row(
      mainAxisAlignment: widget.mainAxis,
      children: [pillContent],
    );

    final tappable =
        widget.editor == null
            ? aligned
            : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              child: aligned,
            );

    if (widget.dragService == null) return tappable;

    return AnimatedBuilder(
      animation: widget.dragService!,
      builder: (context, _) {
        return Stack(
          children: [
            tappable,
            if (_shouldShowTopDropLine())
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedDropLine(
                  child: Container(height: 3, color: AppColors.primary),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleTap() {
    final editor = widget.editor;
    if (editor == null) return;

    // ✅ Divider를 탭하면 "실제 caret"은 다음 문단(다운스트림)으로 이동시킨다.
    // - 이러면 바로 Backspace로 divider를 지우는 UX를 만들기 쉽다.
    widget.focusNode?.requestFocus();

    final doc = editor.document;
    final dividerIndex = doc.getNodeIndexById(widget.nodeId);
    if (dividerIndex < 0) return;

    ParagraphNode? downstreamParagraph;
    for (int i = dividerIndex + 1; i < doc.nodeCount; i++) {
      final n = doc.getNodeAt(i);
      if (n is ParagraphNode) {
        downstreamParagraph = n;
        break;
      }
    }

    if (downstreamParagraph == null) {
      // 문서 끝이면 빈 문단을 하나 만들고 그쪽으로 caret 이동
      final paragraphId = 'p_${DateTime.now().microsecondsSinceEpoch}';
      final newParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
      );
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: (dividerIndex + 1).clamp(0, doc.nodeCount),
          newNode: newParagraph,
        ),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: paragraphId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      return;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: downstreamParagraph.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
  }

  bool _shouldShowTopDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = svc.getNodeIndex(widget.nodeId);
    if (current == -1) return false;
    return di == current;
  }

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
