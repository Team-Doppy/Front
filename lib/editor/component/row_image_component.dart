import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'dart:math' as math;

/// 여러 이미지를 가로로 배치하는 커스텀 노드 (최대 3개)
class ImageRowNode extends BlockNode {
  ImageRowNode({
    required this.id,
    required List<String> imageUrls,
    this.spacing = 8.0,
    Map<String, dynamic>? metadata,
  }) : imageUrls = imageUrls.take(3).toList(), // 최대 3개로 제한
       _metadata = metadata ?? <String, dynamic>{};

  @override
  bool get isDeletable => false;

  @override
  final String id;
  final List<String> imageUrls;
  final double spacing;
  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

  String get nodeType => 'imageRow';

  bool get hasContent => imageUrls.isNotEmpty;

  ImageRowNode copyWith({
    String? id,
    List<String>? imageUrls,
    double? spacing,
    Map<String, dynamic>? metadata,
  }) {
    return ImageRowNode(
      id: id ?? this.id,
      imageUrls: imageUrls?.take(3).toList() ?? this.imageUrls,
      spacing: spacing ?? this.spacing,
      metadata: metadata ?? _metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeType': nodeType,
      'imageUrls': imageUrls,
      'spacing': spacing,
    };
  }

  static ImageRowNode fromJson(Map<String, dynamic> json) {
    return ImageRowNode(
      id: json['id'] as String,
      imageUrls: List<String>.from(json['imageUrls'] as List),
      spacing: (json['spacing'] as num?)?.toDouble() ?? 8.0,
    );
  }

  @override
  bool containsPosition(Object position) {
    // 블록 노드는 Upstream/Downstream 포지션만 가진다고 가정
    return position is UpstreamDownstreamNodePosition;
  }

  Rect getRectForPosition(NodePosition nodePosition) {
    // 기본 구현 - 실제로는 컴포넌트에서 계산됨
    return const Rect.fromLTWH(0, 0, 0, 0);
  }

  NodeSelection getSelectionOfEverything() {
    return UpstreamDownstreamNodeSelection(
      base: const UpstreamDownstreamNodePosition.upstream(),
      extent: const UpstreamDownstreamNodePosition.downstream(),
    );
  }

  bool isVisualSelectionSupported() {
    // 이미지 행은 드래그 선택 불필요
    return false;
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return ImageRowNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      spacing: spacing,
      metadata: newMetadata,
    );
  }

  @override
  String? copyContent(NodeSelection selection) {
    // 이미지 행은 텍스트 복사 없음
    return null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    final updatedMetadata = Map<String, dynamic>.from(_metadata);
    updatedMetadata.addAll(newProperties);
    return ImageRowNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      spacing: spacing,
      metadata: updatedMetadata,
    );
  }

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
  ) => UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => UpstreamDownstreamNodePosition.upstream();
}

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
    with DocumentComponent, SingleTickerProviderStateMixin {
  double? _unifiedHeight;
  final Map<String, Size> _imageSizes = {};
  late final AnimationController _controller;

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

  static const double marginTop = 4;
  static const double marginBottom = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 900));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageService = context.watch<NodeComponentService>();
    final isSelected = imageService.selectedImageId == widget.nodeId;
    // selection 핸들이 이 행 이미지 노드를 포함할 때만, 경계가 이 노드면 Downstream일 때 포함
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection = seState?.editContext.composer.selection;
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;
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
    const double paddingWithText = 15;

    // 위/아래가 이미지인지 판정하여 SingleImage와 동일한 여백 정책 적용
    final bool hasImageAbove = _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow = _hasNeighborImage(doc, widget.nodeId, 1);

    return Column(
      children: [
        if (!hasImageAbove) SizedBox(height: paddingWithText),
        Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(top: marginTop, bottom: marginBottom),
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        children: [
                          // 이미지들
                          ...widget.imageUrls.asMap().entries.map((entry) {
                            final imageUrl = entry.value;

                            // 메타데이터에서 댓글 정보 가져오기
                            bool hasComments = false;
                            int commentCount = 0;
                            try {
                              final node = doc?.getNodeById(widget.nodeId);
                              if (node is ImageRowNode) {
                                final meta = node.metadata;
                                final commentInfo =
                                    meta['imageCommentInfo']
                                        as Map<String, dynamic>?;
                                if (commentInfo != null &&
                                    commentInfo[imageUrl] is Map) {
                                  final imgInfo =
                                      commentInfo[imageUrl]
                                          as Map<String, dynamic>;
                                  hasComments = imgInfo['hasComments'] == true;
                                  final cc = imgInfo['commentCount'];
                                  if (cc is num) commentCount = cc.toInt();
                                  if (cc is String)
                                    commentCount = int.tryParse(cc) ?? 0;
                                }
                              }
                            } catch (_) {}

                            return Expanded(
                              child: Container(
                                margin:
                                    imageUrl == widget.imageUrls.last
                                        ? EdgeInsets.zero
                                        : EdgeInsets.only(right: 1),
                                child: Stack(
                                  children: [
                                    SizedBox(
                                      height: _unifiedHeight ?? 150,
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (
                                          context,
                                          child,
                                          loading,
                                        ) {
                                          if (loading == null) return child;
                                          return ShimmerBox(
                                            width: double.infinity,
                                            height: _unifiedHeight ?? 150,
                                            borderRadius: BorderRadius.circular(
                                              0,
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stack) {
                                          print('Image error: $error');
                                          return ImageErrorPlaceholder(
                                            width: 200,
                                          );
                                        },
                                        frameBuilder: (
                                          context,
                                          child,
                                          frame,
                                          sync,
                                        ) {
                                          if (frame != null) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
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
                                    // 댓글 배지
                                    if (hasComments)
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: IgnorePointer(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(
                                                0.55,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .chat_bubble_outline_rounded,
                                                  color: Colors.white,
                                                  size: 12,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  commentCount.toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                  if (isSelectionHighlighted)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: AppColors.primary.withOpacity(0.4),
                        ),
                      ),
                    ),

                  // 스포일러 마스킹 (세션 캐시)
                  if (context.watch<NodeComponentService>().isSpoiler(
                    widget.nodeId,
                  ))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) {
                            return CustomPaint(
                              painter: _RowImageSpoilerPainter(
                                phase: _controller.value,
                                isEditing: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // 선택 보더
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
                          child: Container(height: 3, color: AppColors.primary),
                        ),

                      // 아래쪽 가로 라인
                      if (_shouldShowBottomDropLine())
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(height: 3, color: AppColors.primary),
                        ),

                      // 왼쪽 세로 라인 (가로배치 모드일 때)
                      if (_shouldShowLeftVerticalLine())
                        Positioned(
                          left: 0,
                          top: marginTop,
                          bottom: marginBottom,
                          child: Container(width: 3, color: AppColors.primary),
                        ),

                      // 오른쪽 세로 라인 (가로배치 모드일 때)
                      if (_shouldShowRightVerticalLine())
                        Positioned(
                          right: 0,
                          top: marginTop,
                          bottom: marginBottom,
                          child: Container(width: 3, color: AppColors.primary),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        if (!hasImageBelow) SizedBox(height: paddingWithText),
      ],
    );
  }

  void _measureAndUnifyHeight(String imageUrl, double availableWidth) {
    if (!mounted) return;

    final ImageProvider imageProvider = NetworkImage(imageUrl);
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

    // 이 노드 위에 삽입하는 경우
    if (dropIndex == currentNodeIndex) {
      return _shouldShowInsertionLine(currentNodeIndex, true);
    }
    return false;
  }

  bool _shouldShowBottomDropLine() {
    if (widget.dragService == null) return false;

    final dropIndex = widget.dragService.dropIndex;
    if (dropIndex == null) return false;

    // 현재 노드의 인덱스 찾기
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
      // 다음 인덱스에 삽입하는 경우
      if (dropIndex == currentNodeIndex + 1) {
        return _shouldShowInsertionLine(currentNodeIndex, false);
      }
    }
    return false;
  }

  /// 삽입 라인 표시 여부를 결정하는 공통 로직
  bool _shouldShowInsertionLine(int currentNodeIndex, bool isTopLine) {
    if (widget.dragService == null) return false;

    final doc = widget.dragService!.editorService.document;
    final documentLength = doc.length;

    // 특수 노드 타입 체크
    bool isSpecialNode(DocumentNode? node) {
      if (node == null) return false;
      return node is LinkNode ||
          node is MentionNode ||
          node is ImageNode ||
          node is ImageRowNode;
    }

    // 텍스트 노드 타입 체크
    bool isTextNode(DocumentNode? node) {
      if (node == null) return false;
      return node is ParagraphNode;
    }

    if (isTopLine) {
      // 위쪽 라인 표시 로직
      if (currentNodeIndex > 0) {
        final prevNode = doc.getNodeAt(currentNodeIndex - 1);

        // 케이스 1: 앞이 특수 노드인 경우 - 이 노드에서는 라인을 표시하지 않음
        // (위쪽 특수 노드가 아래쪽 라인을 표시하므로)
        if (isSpecialNode(prevNode)) {
          return false;
        }
      }
      return true;
    } else {
      // 아래쪽 라인 표시 로직
      if (currentNodeIndex + 1 < documentLength) {
        final nextNode = doc.getNodeAt(currentNodeIndex + 1);

        // 케이스 1: 뒤가 특수 노드인 경우 - 이 노드에서는 라인을 표시함
        // (특수-특수 사이에서는 위쪽 특수 노드가 아래쪽 라인을 표시)
        if (isSpecialNode(nextNode)) {
          return true;
        }

        // 케이스 2: 뒤가 텍스트 노드인 경우 - 이 노드에서는 라인을 표시함
        if (isTextNode(nextNode)) {
          return true;
        }
      }
      return true;
    }
  }

  bool _shouldShowLeftVerticalLine() {
    if (widget.dragService == null) return false;
    if (widget.dragService.draggingNodeId == null) return false;
    if (widget.dragService.dragPosition == null) return false;
    if (widget.dragService.draggingNodeId == widget.nodeId) return false;

    // 병합 모드에서만 세로 라인 표시 (reorder 라인과 중복 방지)
    if (widget.dragService.dragMode != DragType.imageRowMerge) return false;

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

    // 병합 모드에서만 세로 라인 표시 (reorder 라인과 중복 방지)
    if (widget.dragService.dragMode != DragType.imageRowMerge) return false;

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

  bool _hasNeighborImage(Document? doc, String nodeId, int direction) {
    if (doc == null) return false;
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is ImageNode || neighbor is ImageRowNode;
  }

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

    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    if (myIndex == end) {
      final boundary = extentIndex == end ? selection.extent : selection.base;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    return true;
  }
}

class _RowImageSpoilerPainter extends CustomPainter {
  final double phase;
  final bool isEditing;
  _RowImageSpoilerPainter({required this.phase, required this.isEditing});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final mask =
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white.withOpacity(isEditing ? 0.4 : 1.0);
    final dot =
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.black.withOpacity(0.3);

    canvas.drawRect(rect, mask);
    final area = rect.width * rect.height;
    final count =
        isEditing
            ? math.max(40, (area / 180).floor())
            : math.max(60, (area / 120).floor());
    final double t = phase * (2 * math.pi) * 1.1;
    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 486187739);
      final r = math.Random(seed);
      final baseX = r.nextDouble() * rect.width;
      final baseY = r.nextDouble() * rect.height;
      final amp = 1.2 + r.nextDouble() * 1.8; // 1.2~3.0px
      final ox = math.sin(t + i * 0.17) * amp;
      final oy = math.cos(t * 1.1 + i * 0.11) * amp;
      double x = baseX + ox;
      double y = baseY + oy;
      x = x % rect.width;
      y = y % rect.height;
      if (x < 0) x += rect.width;
      if (y < 0) y += rect.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1.5, 1.5), dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RowImageSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.isEditing != isEditing;
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
