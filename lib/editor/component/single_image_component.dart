import 'dart:io';
import 'dart:typed_data';

import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'package:super_editor/super_editor.dart';

/// 깜빡이는 플레이스홀더 위젯
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder({Key? key}) : super(key: key);

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(8),
          width: double.infinity,
          height: 200, // 적절한 높이 설정
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.darkSurface, width: 2),
          ),
        );
      },
    );
  }
}

class SingleImageComponentBuilder implements ComponentBuilder {
  const SingleImageComponentBuilder({this.dragService});

  final dynamic dragService; // DragService 타입을 나중에 import해서 수정

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

  static const double marginTop = 4;
  static const double marginBottom = 2;
  static const double paddingWithText = 15;

  @override
  Widget build(BuildContext context) {
    // selection 핸들이 이미지 노드를 포함할 때만, 그리고 경계가 이미지인 경우 Downstream일 때만 하이라이트
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection = seState?.editContext.composer.selection;
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);

    return Column(
      children: [
        if (!hasImageAbove) SizedBox(height: paddingWithText),
        // 실제 이미지 내용 + 좌/우 세로 라인 (머지 모드에서)
        LayoutBuilder(
          builder: (context, constraints) {
            final editedBytes = context.watch<ImageService>().getEditedBytes(
              widget.nodeId,
            );
            final image = _buildImage(editedBytes);

            final imageService = context.watch<ImageService>();
            final isSelected = imageService.selectedImageId == widget.nodeId;
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

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: marginTop,
                    bottom: marginBottom,
                  ),
                  child: Stack(
                    children: [
                      image,
                      if (isSelectionHighlighted)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: AppColors.primary.withOpacity(0.4),
                            ),
                          ),
                        ),
                      if (isSelected)
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
                if (_shouldShowTopDropLine())
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Container(height: 5, color: AppColors.primary),
                    ),
                  ),

                if (_shouldShowLeftVerticalLine())
                  Positioned(
                    top: marginTop,
                    bottom: marginBottom,
                    left: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Container(width: 5, color: AppColors.primary),
                    ),
                  ),
                if (_shouldShowRightVerticalLine())
                  Positioned(
                    top: marginTop,
                    bottom: marginBottom,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Container(width: 5, color: AppColors.primary),
                    ),
                  ),
                if (_shouldShowBottomDropLine())
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
        if (!hasImageBelow) SizedBox(height: paddingWithText),
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
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;
    // 이 노드의 위에 삽입하는 경우
    return dropIndex == currentNodeIndex;
  }

  bool _shouldShowBottomDropLine() {
    if (widget.dragService == null) return false;
    final dropIndex = widget.dragService.dropIndex;
    if (dropIndex == null) return false;
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 마지막 노드인지 확인
    final documentLength =
        widget.dragService?.editorService.document.length ?? 0;
    final isLastNode = currentNodeIndex == documentLength - 1;

    if (isLastNode) {
      // 마지막 노드일 때는 문서 끝에 삽입하는 경우
      return dropIndex == documentLength;
    } else {
      // 일반적인 경우: 이 노드의 아래에 삽입하는 경우 (다음 인덱스)
      // 하지만 다음 노드가 있으면 이중 표시 방지를 위해 false 반환
      return dropIndex == currentNodeIndex + 1;
    }
  }

  bool _shouldShowLeftVerticalLine() {
    final service = widget.dragService;
    if (service == null) return false;

    if (service.draggingNodeId == null) return false;
    if (service.dragPosition == null) return false;
    if (service.draggingNodeId == widget.nodeId) {
      return false;
    }

    // 현재 노드가 타겟 노드가 아니면 표시하지 않음
    if (service.targetNodeId != widget.nodeId) {
      return false;
    }

    // dragService의 dragMode가 imageRowMerge가 아니면 표시하지 않음
    if (service.dragMode != DragType.imageRowMerge) {
      return false;
    }

    // dragService의 isDraggingFromLeft를 사용하여 방향 판정
    final result = service.isDraggingFromLeft;
    return result;
  }

  bool _shouldShowRightVerticalLine() {
    final service = widget.dragService;

    if (service == null) return false;

    if (service.draggingNodeId == null) return false;
    if (service.dragPosition == null) return false;
    if (service.draggingNodeId == widget.nodeId) {
      return false;
    }

    // 현재 노드가 타겟 노드가 아니면 표시하지 않음
    if (service.targetNodeId != widget.nodeId) {
      return false;
    }

    // dragService의 dragMode가 imageRowMerge가 아니면 표시하지 않음
    if (service.dragMode != DragType.imageRowMerge) {
      return false;
    }

    // dragService의 isDraggingFromLeft를 사용하여 방향 판정
    final result = !service.isDraggingFromLeft;
    return result;
  }

  int _getCurrentNodeIndex() {
    if (widget.dragService == null) return -1;
    return widget.dragService.getNodeIndex(widget.nodeId);
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

  // 이미지 위젯 생성: editedBytes > 로컬 파일 경로 > 네트워크 URL 순서
  Widget _buildImage(Uint8List? editedBytes) {
    if (editedBytes != null) {
      return Image.memory(editedBytes, fit: BoxFit.contain);
    }

    final url = widget.imageUrl;
    if (_isLocalPath(url)) {
      final filePath = url.startsWith('file://') ? url.substring(7) : url;
      return Image.file(
        File(filePath),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => _errorBox(),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child; // 로드 완료
        return const _ShimmerPlaceholder(); // 로드 중
      },
      errorBuilder: (context, error, stack) => _errorBox(),
      gaplessPlayback: true,
    );
  }

  bool _isLocalPath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return false;
    if (path.startsWith('file://')) return true;
    return path.startsWith('/') ||
        path.contains('/Application/') ||
        path.contains('/Documents/');
  }

  Widget _errorBox() {
    return Container(
      color: Colors.grey.shade300,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.broken_image, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text("이미지를 불러올 수 없습니다.", style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  bool _hasNeighborImage(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is ImageNode || neighbor is ImageRowNode;
  }
}
