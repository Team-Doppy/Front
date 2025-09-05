import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class SingleImageComponent extends StatefulWidget {
  const SingleImageComponent({
    required this.nodeId,
    required this.imageUrl,
    required GlobalKey componentKey,
    this.dragService,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final String imageUrl;
  final GlobalKey _componentKey;
  final dynamic dragService; // DragService 타입을 나중에 import해서 수정

  @override
  State<SingleImageComponent> createState() => _SingleImageComponentState();
}

class _SingleImageComponentState extends State<SingleImageComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 위쪽 드롭 라인
        if (_shouldShowTopDropLine())
          Container(
            height: 3,
            color: const Color(0xFF007AFF),
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),

        // 실제 이미지 내용 + 좌/우 세로 라인 (머지 모드에서)
        LayoutBuilder(
          builder: (context, constraints) {
            final image = Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade300,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.broken_image, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        "이미지를 불러올 수 없습니다.",
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                );
              },
            );

            return Stack(
              children: [
                SizedBox(width: double.infinity, child: image),
                if (_shouldShowLeftVerticalLine())
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    child: Container(width: 4, color: const Color(0xFF007AFF)),
                  ),
                if (_shouldShowRightVerticalLine())
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: Container(width: 4, color: const Color(0xFF007AFF)),
                  ),
                if (_shouldShowBottomDropLine())
                  Container(
                    height: 3,
                    color: const Color(0xFF007AFF),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
              ],
            );
          },
        ),

        // 아래쪽 드롭 라인
        if (_shouldShowBottomDropLine())
          Container(
            height: 3,
            color: const Color(0xFF007AFF),
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),
      ],
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
      UpstreamDownstreamNodePosition.upstream();

  @override
  NodePosition getEndPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  bool _shouldShowTopDropLine() {
    if (widget.dragService == null) return false;

    final dropIndex = widget.dragService.dropIndex;
    if (dropIndex == null) return false;

    // 현재 노드의 인덱스 찾기
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 드롭 인덱스가 현재 노드와 같으면 위쪽에 라인 표시
    return dropIndex == currentNodeIndex;
  }

  bool _shouldShowBottomDropLine() {
    if (widget.dragService == null) return false;

    final dropIndex = widget.dragService.dropIndex;
    if (dropIndex == null) return false;

    // 현재 노드의 인덱스 찾기
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 마지막 노드인지 확인
    final totalNodes = widget.dragService.editorService.document.length;
    final isLastNode = currentNodeIndex == totalNodes - 1;

    // 드롭 인덱스가 현재 노드 다음이면 아래쪽에 라인 표시 (마지막 노드일 때만)
    return dropIndex == currentNodeIndex + 1 && isLastNode;
  }

  bool _shouldShowLeftVerticalLine() {
    final service = widget.dragService;
    if (service == null) return false;
    if (service.draggingNodeId == null) return false;
    if (service.dragPosition == null) return false;
    if (service.draggingNodeId == widget.nodeId) return false;
    if (!(service.draggingNodeType == NodeType.image ||
        service.draggingNodeType == NodeType.imageRow)) {
      return false;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final rect = (renderBox.localToGlobal(Offset.zero) & renderBox.size)
        .inflate(16);
    if (!rect.contains(service.dragPosition!)) return false;
    return service.dragPosition!.dx < rect.center.dx;
  }

  bool _shouldShowRightVerticalLine() {
    final service = widget.dragService;
    if (service == null) return false;
    if (service.draggingNodeId == null) return false;
    if (service.dragPosition == null) return false;
    if (service.draggingNodeId == widget.nodeId) return false;
    if (!(service.draggingNodeType == NodeType.image ||
        service.draggingNodeType == NodeType.imageRow)) {
      return false;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final rect = (renderBox.localToGlobal(Offset.zero) & renderBox.size)
        .inflate(16);
    if (!rect.contains(service.dragPosition!)) return false;
    return service.dragPosition!.dx >= rect.center.dx;
  }

  int _getCurrentNodeIndex() {
    if (widget.dragService == null) return -1;
    return widget.dragService.getNodeIndex(widget.nodeId);
  }
}
