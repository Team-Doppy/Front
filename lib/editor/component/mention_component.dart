import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/service/drag_service.dart';

// 언급 블록 노드
class MentionNode extends BlockNode {
  MentionNode({required this.id, required this.usernames});

  @override
  final String id;
  final List<String> usernames;

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
      MentionNode(id: id, usernames: usernames);

  @override
  String? copyContent(NodeSelection selection) => usernames.join(',');

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      MentionNode(id: id, usernames: usernames);
}

class MentionComponentViewModel extends SingleColumnLayoutComponentViewModel {
  MentionComponentViewModel({
    required super.nodeId,
    required this.usernames,
    required this.mainAxis,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final List<String> usernames;
  final MainAxisAlignment mainAxis;

  @override
  SingleColumnLayoutComponentViewModel copy() => MentionComponentViewModel(
    nodeId: nodeId,
    usernames: List<String>.from(usernames),
    mainAxis: mainAxis,
  );
}

class MentionComponentBuilder implements ComponentBuilder {
  const MentionComponentBuilder({this.dragService});
  final DragService? dragService;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is MentionComponentViewModel) {
      return _MentionComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        usernames: viewModel.usernames,
        mainAxis: viewModel.mainAxis,
        dragService: dragService,
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

      return MentionComponentViewModel(
        nodeId: node.id,
        usernames: node.usernames,
        mainAxis: align,
      );
    }
    return null;
  }
}

class _MentionComponent extends StatefulWidget {
  const _MentionComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.usernames,
    required this.mainAxis,
    this.dragService,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final List<String> usernames;
  final MainAxisAlignment mainAxis;
  final DragService? dragService;

  @override
  State<_MentionComponent> createState() => _MentionComponentState();
}

class _MentionComponentState extends State<_MentionComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    final pillContent = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              for (final u in widget.usernames)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.alternate_email,
                        color: AppColors.darkTextPrimary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        u,
                        style: const TextStyle(
                          color: AppColors.darkTextPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
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

    if (widget.dragService == null) return aligned;

    return AnimatedBuilder(
      animation: widget.dragService!,
      builder: (context, _) {
        return Stack(
          children: [
            aligned,
            if (_shouldShowTopDropLine())
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 3, color: AppColors.primary),
              ),
          ],
        );
      },
    );
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

  bool _shouldShowTopDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = svc.getNodeIndex(widget.nodeId);
    if (current == -1) return false;
    return di == current;
  }
}
