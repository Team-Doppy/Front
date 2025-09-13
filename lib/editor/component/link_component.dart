import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/theme/app_colors.dart';

/// 텍스트와 독립적인 링크 블록 노드
class LinkNode extends BlockNode {
  LinkNode({
    required this.id,
    required this.url,
    this.title = '',
    this.description = '',
    this.thumbnailUrl = '',
  });

  @override
  bool get isDeletable => true;

  @override
  final String id;

  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;

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
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return LinkNode(
      id: id,
      url: url,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
    );
  }

  @override
  String? copyContent(NodeSelection selection) => url;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return LinkNode(
      id: id,
      url: url,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
    );
  }
}

class LinkComponentViewModel extends SingleColumnLayoutComponentViewModel {
  LinkComponentViewModel({
    required super.nodeId,
    required this.url,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;

  @override
  SingleColumnLayoutComponentViewModel copy() => LinkComponentViewModel(
    nodeId: nodeId,
    url: url,
    title: title,
    description: description,
    thumbnailUrl: thumbnailUrl,
  );
}

class LinkComponentBuilder implements ComponentBuilder {
  const LinkComponentBuilder({this.dragService});
  final DragService? dragService;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is LinkComponentViewModel) {
      return _LinkComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        url: viewModel.url,
        title: viewModel.title,
        description: viewModel.description,
        thumbnailUrl: viewModel.thumbnailUrl,
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
    if (node is LinkNode) {
      return LinkComponentViewModel(
        nodeId: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
      );
    }
    return null;
  }
}

class _LinkComponent extends StatefulWidget {
  const _LinkComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.url,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    this.dragService,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;
  final DragService? dragService;

  @override
  State<_LinkComponent> createState() => _LinkComponentState();
}

class _LinkComponentState extends State<_LinkComponent> with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        children: [
          if (widget.thumbnailUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child: Image.network(
                widget.thumbnailUrl,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => Container(
                      width: 100,
                      height: 100,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.link, color: Colors.white54),
                    ),
              ),
            )
          else
            Container(
              width: 100,
              height: 100,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A2A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: const Icon(Icons.link, color: Colors.white54),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title.isNotEmpty ? widget.title : widget.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    widget.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );

    if (widget.dragService == null) {
      return card;
    }

    return AnimatedBuilder(
      animation: widget.dragService!,
      builder: (context, _) {
        return Stack(
          children: [
            card,
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

  // DocumentComponent 최소 구현 (이미지/위치와 동일 정책)
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

  // 드래그 삽입 라인 표시 로직
  bool _shouldShowTopDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = _getCurrentNodeIndex();
    if (current == -1) return false;
    return di == current;
  }

  int _getCurrentNodeIndex() {
    final svc = widget.dragService;
    if (svc == null) return -1;
    return svc.getNodeIndex(widget.nodeId);
  }
}
