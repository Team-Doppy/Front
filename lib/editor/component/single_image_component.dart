import 'dart:io';
import 'dart:typed_data';

import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
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
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
  });

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
    required GlobalKey componentKey,
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final String imageUrl;
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

  static const double marginTop = 2.5;
  static const double marginBottom = 2.5;
  static const double paddingWithText = 12;

  late final AnimationController _controller;
  // 스포일러 해제 스캐터 이펙트
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  bool _wasSpoilerVisible = false;

  @override
  void initState() {
    super.initState();
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
            final editedBytes = context
                .watch<NodeComponentService>()
                .getEditedBytes(widget.nodeId);
            final image = Padding(
              padding: EdgeInsets.zero,
              child: _buildImage(editedBytes),
            );

            // 플레이스홀더/업로드 중 상태 판정: imageUrl 비었거나 로컬 경로이거나 metadata.isPlaceholder == true
            // ignore: invalid_use_of_visible_for_testing_member
            final doc = seState?.editContext.editor.document;
            bool isUploading = false;
            try {
              final node = doc?.getNodeById(widget.nodeId);
              if (node is ImageNode) {
                final meta =
                    (node as dynamic).metadata as Map<String, dynamic>?;
                final isPh = meta != null && (meta['isPlaceholder'] == true);
                final url = widget.imageUrl;
                final isLocal = _isLocalPath(url) || url.isEmpty;
                isUploading = isPh || isLocal;
              }
            } catch (_) {}

            final imageService = context.watch<NodeComponentService>();
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

            // 스포일러 상태 (헬퍼 사용)
            bool isSpoilerFlag = false;
            final nodeService = context.read<NodeComponentService>();
            try {
              final node = doc?.getNodeById(widget.nodeId);
              Map<String, dynamic>? meta;
              if (node is ImageNode) {
                meta = (node as dynamic).metadata as Map<String, dynamic>?;
              }
              isSpoilerFlag = nodeService.shouldShowImageSpoiler(
                widget.nodeId,
                meta,
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
                Padding(
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
                                final brightness = Theme.of(context).brightness;
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
                                final brightness = Theme.of(context).brightness;
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
                            child: Container(
                              color: Colors.black.withOpacity(0.6),
                              alignment: Alignment.center,
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
          (node is ParagraphNode && node.metadata['mention'] == true) ||
          node is ImageNode ||
          node is ImageRowNode ||
          node is ClipNode;
      ;
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

  // 이미지 위젯 생성: editedBytes > (업로드중: metadata.localPath) > 로컬 파일 경로 > 네트워크 URL 순서
  Widget _buildImage(Uint8List? editedBytes) {
    if (editedBytes != null) {
      final double w = MediaQuery.of(context).size.width;
      return Image.memory(
        editedBytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded || frame != null) {
            _lastRenderedChild = child;
            return child;
          }
          final h = w / (4 / 5);
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
          final double w = MediaQuery.of(context).size.width;
          return Image.file(
            File(filePath),
            key: ValueKey('$filePath-${Theme.of(context).brightness}'),
            fit: BoxFit.contain,
            cacheWidth: w.isFinite ? w.toInt() : null,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded || frame != null) {
                _lastRenderedChild = child;
                return child;
              }
              final h = w / (4 / 5);
              return _lastRenderedChild ??
                  ShimmerBox(
                    width: w,
                    height: h,
                    isDarkMode: widget.isDarkMode,
                  );
            },
            errorBuilder:
                (context, error, stack) => Builder(
                  builder:
                      (context) => ImageErrorPlaceholder(
                        width: MediaQuery.of(context).size.width,
                      ),
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
            (context, error, stack) => Builder(
              builder:
                  (context) => ImageErrorPlaceholder(
                    width: MediaQuery.of(context).size.width,
                  ),
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
          return child;
        }
        final w = MediaQuery.of(context).size.width;
        final h = w / (4 / 5);
        return _lastRenderedChild ??
            ShimmerBox(width: w, height: h, isDarkMode: widget.isDarkMode);
      },
      errorBuilder:
          (context, error, stack) => Builder(
            builder:
                (context) => ImageErrorPlaceholder(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width / (4 / 5),
                ),
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
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is ImageNode ||
        neighbor is ImageRowNode ||
        neighbor is ClipNode;
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
