import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

class RowImageComponentBuilder implements ComponentBuilder {
  const RowImageComponentBuilder({this.dragService});

  final dynamic dragService; // DragService 타입을 나중에 import해서 수정

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageRowComponentViewModel) {
      return ImageRowComponent(
        nodeId: componentViewModel.nodeId,
        imageUrls: componentViewModel.imageUrls,
        spacing: componentViewModel.spacing,
        componentKey: componentContext.componentKey, // ← 매우 중요
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
    if (node is ImageRowNode) {
      return ImageRowComponentViewModel(
        nodeId: node.id,
        imageUrls: node.imageUrls,
        spacing: node.spacing,
      );
    }
    return null;
  }
}

/// 실제로 문서에 올라가는 컴포넌트. 반드시 DocumentComponent를 구현해야 함.
class ImageRowComponent extends StatefulWidget {
  const ImageRowComponent({
    required this.nodeId,
    required this.imageUrls,
    required this.spacing,
    required GlobalKey componentKey,
    this.dragService,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final List<String> imageUrls;
  final double spacing;
  final dynamic dragService; // DragService 타입을 나중에 import해서 수정

  final GlobalKey _componentKey;

  GlobalKey get componentKey => _componentKey;

  @override
  State<ImageRowComponent> createState() => _ImageRowComponentState();
}

class _ImageRowComponentState extends State<ImageRowComponent>
    with DocumentComponent {
  double? _unifiedHeight;
  final Map<String, Size> _imageSizes = {};

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

  @override
  Widget build(BuildContext context) {
    final isSelected =
        context.watch<ImageService>().selectedImageId == widget.nodeId;

    return Stack(
      children: [
        // 메인 컨텐츠
        Container(
          margin: const EdgeInsets.only(top: 8),

          decoration: BoxDecoration(
            border:
                isSelected
                    ? Border.all(color: const Color(0xFF007AFF), width: 2)
                    : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  // 이미지들
                  ...widget.imageUrls.asMap().entries.map((entry) {
                    final imageUrl = entry.value;
                    return Expanded(
                      child: Container(
                        margin:
                            imageUrl == widget.imageUrls.last
                                ? EdgeInsets.zero
                                : EdgeInsets.only(right: 1),
                        child: SizedBox(
                          height: _unifiedHeight ?? 260,
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loading) {
                              if (loading == null) return child;
                              return Container(
                                height: _unifiedHeight ?? 260,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return Container(
                                height: _unifiedHeight ?? 260,
                                color: Colors.grey.shade300,
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.broken_image,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        "이미지 로드 실패",
                                        style: TextStyle(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            frameBuilder: (context, child, frame, sync) {
                              if (frame != null) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _measureAndUnifyHeight(
                                    imageUrl,
                                    constraints.maxWidth,
                                  );
                                });
                              }
                              return child;
                            },
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),

        // 드래그 라인 오버레이
        Positioned.fill(
          child: AnimatedBuilder(
            animation: widget.dragService,
            builder: (context, _) {
              return Stack(
                children: [
                  // 위쪽 가로 라인
                  if (_shouldShowTopDropLine())
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        color: const Color(0xFF007AFF),
                      ),
                    ),

                  // 아래쪽 가로 라인
                  if (_shouldShowBottomDropLine())
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        color: const Color(0xFF007AFF),
                      ),
                    ),

                  // 왼쪽 세로 라인 (가로배치 모드일 때)
                  if (_shouldShowLeftVerticalLine())
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 4,
                        color: const Color(0xFF007AFF),
                      ),
                    ),

                  // 오른쪽 세로 라인 (가로배치 모드일 때)
                  if (_shouldShowRightVerticalLine())
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 3,
                        color: const Color(0xFF007AFF),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _measureAndUnifyHeight(String imageUrl, double availableWidth) {
    if (!mounted) return;

    final imageProvider = NetworkImage(imageUrl);
    imageProvider
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener((ImageInfo info, _) {
            if (!mounted) return;

            _imageSizes[imageUrl] = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );

            if (_imageSizes.length == widget.imageUrls.length) {
              final count = widget.imageUrls.length;
              final spacingWidth = widget.spacing * (count - 1);
              final eachWidth = (availableWidth - spacingWidth) / count;

              final heights = <double>[];
              for (final url in widget.imageUrls) {
                final s = _imageSizes[url];
                if (s == null || s.width == 0) continue;
                heights.add(eachWidth * (s.height / s.width));
              }
              if (heights.isEmpty) return;

              heights.sort();
              final start = (heights.length * 0.2).floor();
              final end = (heights.length * 0.8).ceil();
              final filtered = heights.sublist(start, end);
              final avg = filtered.reduce((a, b) => a + b) / filtered.length;

              final unified = avg.clamp(150.0, 400.0);
              if (_unifiedHeight != unified) {
                setState(() => _unifiedHeight = unified);
              }
            }
          }),
        );
  }

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
    if (widget.dragService == null) return false;
    if (widget.dragService.draggingNodeId == null) return false;
    if (widget.dragService.dragPosition == null) return false;
    if (widget.dragService.draggingNodeId == widget.nodeId) return false;

    // 현재 노드가 타겟 노드가 아니면 표시하지 않음
    if (widget.dragService.targetNodeId != widget.nodeId) {
      return false;
    }

    if (!(widget.dragService.draggingNodeType == NodeType.image ||
        widget.dragService.draggingNodeType == NodeType.imageRow)) {
      return false;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final rect = (renderBox.localToGlobal(Offset.zero) & renderBox.size)
        .inflate(12);
    if (!rect.contains(widget.dragService.dragPosition!)) return false;

    return widget.dragService.dragPosition!.dx < rect.center.dx;
  }

  bool _shouldShowRightVerticalLine() {
    if (widget.dragService == null) return false;
    if (widget.dragService.draggingNodeId == null) return false;
    if (widget.dragService.dragPosition == null) return false;
    if (widget.dragService.draggingNodeId == widget.nodeId) return false;

    // 현재 노드가 타겟 노드가 아니면 표시하지 않음
    if (widget.dragService.targetNodeId != widget.nodeId) {
      return false;
    }

    if (!(widget.dragService.draggingNodeType == NodeType.image ||
        widget.dragService.draggingNodeType == NodeType.imageRow)) {
      return false;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final rect = (renderBox.localToGlobal(Offset.zero) & renderBox.size)
        .inflate(12);
    if (!rect.contains(widget.dragService.dragPosition!)) return false;

    return widget.dragService.dragPosition!.dx >= rect.center.dx;
  }

  int _getCurrentNodeIndex() {
    if (widget.dragService == null) return -1;
    return widget.dragService.getNodeIndex(widget.nodeId);
  }
}

/// ImageRowNode의 뷰모델
class ImageRowComponentViewModel extends SingleColumnLayoutComponentViewModel {
  ImageRowComponentViewModel({
    required super.nodeId,
    required this.imageUrls,
    required this.spacing,
  }) : super(createdAt: DateTime.now(), padding: EdgeInsets.zero);

  final List<String> imageUrls;
  final double spacing;

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return ImageRowComponentViewModel(
      nodeId: nodeId,
      imageUrls: imageUrls,
      spacing: spacing,
    );
  }
}
