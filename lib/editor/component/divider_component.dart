import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../../editor/utils/animated_drop_line.dart';
import '../../editor/config/drop_line_config.dart';
import '../../editor/service/drag_service.dart' as DragService;

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
  final DragService.DragService? dragService;
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
      // ✅ 디바이더는 항상 가운데 정렬만 유지
      return DividerComponentViewModel(
        nodeId: node.id,
        mainAxis: MainAxisAlignment.center,
      );
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
  }) : super(key: componentKey);

  final String nodeId;
  final MainAxisAlignment mainAxis;
  final DragService.DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;

  @override
  State<_DividerComponent> createState() => _DividerComponentState();
}

class _DividerComponentState extends State<_DividerComponent>
    with DocumentComponent {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final pillContent = Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 150,
              height: 1.5,
              color: theme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final aligned = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [pillContent],
    );

    final tappable = widget.editor == null
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
                  child: Container(height: 3, color: theme.primary),
                ),
              ),
            if (_shouldShowBottomDropLine())
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedDropLine(
                  child: Container(height: 3, color: theme.primary),
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
    return DropLineConfig.resolve(nodeId: widget.nodeId, dragService: svc).top;
  }

  bool _shouldShowBottomDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    return DropLineConfig.resolve(
      nodeId: widget.nodeId,
      dragService: svc,
    ).bottom;
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
