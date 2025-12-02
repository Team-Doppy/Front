import 'dart:io';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:super_editor/super_editor.dart';
import 'dart:math' as math;

/// 여러 이미지를 가로로 배치하는 커스텀 노드 (최대 3개)
class ImageRowNode extends BlockNode {
  ImageRowNode({
    required this.id,
    required List<String> imageUrls,
    this.spacing = 0.0,
    Map<String, dynamic>? metadata,
  }) : imageUrls = imageUrls.take(3).toList(), // 최대 3개로 제한
       _metadata = metadata ?? <String, dynamic>{};

  @override
  bool get isDeletable => true;

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
      spacing: (json['spacing'] as num?)?.toDouble() ?? 0.0,
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
  const RowImageComponentBuilder({
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
    if (componentViewModel is ImageRowComponentViewModel) {
      return ImageRowComponent(
        nodeId: componentViewModel.nodeId,
        imageUrls: componentViewModel.imageUrls,
        spacing: componentViewModel.spacing,
        unifiedHeight: null, // 🎯 metadata 의존 제거
        isDarkMode: isDarkMode,
        componentKey: componentContext.componentKey,
        dragService: dragService,
        isEditing: isEditing,
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
      // 🎯 metadata 의존 제거 - 항상 null
      return ImageRowComponentViewModel(
        nodeId: node.id,
        imageUrls: node.imageUrls,
        spacing: node.spacing,
        unifiedHeight: null, // 항상 새로 측정
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
    this.unifiedHeight, // 🎯 사용하지 않음 (항상 null)
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final List<String> imageUrls;
  final double spacing;
  final double? unifiedHeight; // 🎯 metadata 의존 제거 (deprecated)
  final dynamic dragService;
  final bool isEditing;
  final bool isDarkMode;

  final GlobalKey _componentKey;

  GlobalKey get componentKey => _componentKey;

  @override
  State<ImageRowComponent> createState() => _ImageRowComponentState();
}

class _ImageRowComponentState extends State<ImageRowComponent>
    with DocumentComponent, TickerProviderStateMixin {
  double? _unifiedHeight;
  final Map<String, Size> _imageSizes = {};
  late final AnimationController _controller;

  // Scatter 애니메이션용
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  bool _wasSpoilerVisible = false;

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

    // upstream/downstream 위치일 때는 커서를 표시하지 않음 (사용자 요청)
    // selection 효과만 표시
    if (nodePosition is UpstreamDownstreamNodePosition) {
      return Offset.zero & renderBox.size;
    }

    return Offset.zero & renderBox.size;
  }

  @override
  bool isVisualSelectionSupported() => false;

  @override
  NodePosition? movePositionLeft(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) {
    // 현재 위치가 이미 downstream이면 null 반환 (삭제 허용)
    if (currentPosition is UpstreamDownstreamNodePosition) {
      final downstreamPos = const UpstreamDownstreamNodePosition.downstream();
      if (currentPosition == downstreamPos) {
        // 이미 downstream에 있으면 null 반환하여 삭제 허용
        return null;
      }
    }
    // 특수 노드 아래에서 백스페이스 시 특수 노드의 끝(downstream) 위치로 이동
    return const UpstreamDownstreamNodePosition.downstream();
  }

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
      // 🎯 upstream 위치로 커서가 가지 못하도록 항상 downstream 반환
      const UpstreamDownstreamNodePosition.downstream();

  @override
  NodePosition getEndPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  static const double marginTop = 2;
  static const double marginBottom = 2;

  // 🎯 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
  // 🎯 특수 노드 사이 클릭 감지 (true: 특수 노드 사이 클릭, false: 일반 클릭)
  bool _handleSpecialNodeTap(Offset globalPosition) {
    if (widget.dragService == null) return false;
    final editorService = widget.dragService!.editorService;
    final doc = editorService.document;
    final dragService = widget.dragService!;

    // 자신의 인덱스와 Rect 확인
    final currentNodeIndex = doc.getNodeIndexById(widget.nodeId);
    if (currentNodeIndex == -1) return false;

    final nodeRect = dragService.getNodeGlobalRect(widget.nodeId);
    if (nodeRect == null) return false;

    // 🎯 위쪽 이웃 노드 확인
    if (currentNodeIndex > 0) {
      final prevNode = doc.getNodeAt(currentNodeIndex - 1);
      if (prevNode != null) {
        if (NodeTypeChecker.isSpecialNode(prevNode)) {
          final prevRect = dragService.getNodeGlobalRect(prevNode.id);
          if (prevRect != null) {
            // 위쪽 노드와 자신 사이의 간격 확인 (위쪽 노드 아래 20px ~ 자신 위쪽 20px)
            final gapTop = prevRect.bottom - 20;
            final gapBottom = nodeRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }

    // 🎯 아래쪽 이웃 노드 확인
    if (currentNodeIndex < doc.nodeCount - 1) {
      final nextNode = doc.getNodeAt(currentNodeIndex + 1);
      if (nextNode != null) {
        if (NodeTypeChecker.isSpecialNode(nextNode)) {
          final nextRect = dragService.getNodeGlobalRect(nextNode.id);
          if (nextRect != null) {
            // 자신과 아래쪽 노드 사이의 간격 확인 (자신 아래 20px ~ 아래쪽 노드 위쪽 20px)
            final gapTop = nodeRect.bottom - 20;
            final gapBottom = nextRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex + 1);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    // 🎯 metadata 의존 제거 - 항상 새로 측정
    debugPrint('[RowImage] 🔄 높이 측정 시작 (${widget.imageUrls.length}개 이미지)');

    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 900));

    // Scatter 애니메이션 초기화
    _scatterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _scatterActive = false);
      }
    });
  }

  @override
  void didUpdateWidget(ImageRowComponent oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 이미지 URL이 변경되면 무조건 재측정
    if (!_areUrlsEqual(oldWidget.imageUrls, widget.imageUrls)) {
      debugPrint('[RowImage] 🔄 이미지 변경 감지 - 재측정');
      setState(() {
        _imageSizes.clear();
        _unifiedHeight = null;
      });
    }
  }

  bool _areUrlsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scatterCtrl.dispose();
    super.dispose();
  }

  // 🎯 이미지 사이 경계 탭 감지를 위한 상태 관리
  bool _imageRowBoundaryTapped = false;
  // 🎯 특수 노드 사이 클릭 감지 플래그
  bool _isSpecialNodeGapTap = false;

  // 🎯 이미지행 내부 경계(이미지 사이) 클릭 감지
  int? _detectImageRowBoundaryGap(ImageRowNode rowNode, Offset globalPos) {
    if (widget.dragService == null) return null;
    const double threshold = 6.0;
    final rect = widget.dragService!.getNodeGlobalRect(rowNode.id);
    if (rect == null) return null;

    // 수직으로 행 안쪽에 위치해야 함 (약간 오차 허용)
    if (globalPos.dy < rect.top - 8 || globalPos.dy > rect.bottom + 8) {
      return null;
    }

    final localX = globalPos.dx - rect.left;
    final int count = rowNode.imageUrls.length;
    if (count <= 1) return null;
    final double slot = rect.width / count;

    // 경계는 k*slot (k=1..count-1). 경계에 가까우면 감지
    for (int k = 1; k < count; k++) {
      final double boundaryX = slot * k;
      if ((localX - boundaryX).abs() <= threshold) {
        return k; // k번째 경계 = 앞 이미지 인덱스와 뒤 이미지 인덱스 사이
      }
    }
    return null;
  }

  // 🎯 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
  int? _findClickedImageIndex(ImageRowNode rowNode, Offset globalPosition) {
    if (widget.dragService == null) return null;
    try {
      final imageCount = rowNode.imageUrls.length;
      final rect = widget.dragService!.getNodeGlobalRect(rowNode.id);
      if (rect == null) return null;
      final imageWidth = rect.width / imageCount;

      // 클릭한 X 좌표에 따라 이미지 인덱스 계산
      final localX = globalPosition.dx - rect.left;
      final clickedIndex = (localX / imageWidth).floor();

      // 유효한 인덱스 범위 확인
      if (clickedIndex >= 0 && clickedIndex < imageCount) {
        return clickedIndex;
      }

      return 0;
    } catch (e) {
      return 0;
    }
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

    // 위/아래가 이미지인지 판정하여 SingleImage와 동일한 여백 정책 적용
    final bool hasImageAbove = _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow = _hasNeighborImage(doc, widget.nodeId, 1);

    return Column(
      children: [
        if (!hasImageAbove)
          SizedBox(height: EditorConfig.specialNodePaddingWithText),
        Stack(
          children: [
            // 🎯 편집 모드에서 탭/롱프레스 처리
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown:
                  widget.isEditing && widget.dragService != null
                      ? (details) {
                        // 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
                        final isGapTap = _handleSpecialNodeTap(
                          details.globalPosition,
                        );

                        // 이미지 사이 경계 감지
                        setState(() {
                          _imageRowBoundaryTapped = false;
                          _isSpecialNodeGapTap = isGapTap;
                        });
                        final node = doc?.getNodeById(widget.nodeId);
                        if (node is ImageRowNode) {
                          final betweenIndex = _detectImageRowBoundaryGap(
                            node,
                            details.globalPosition,
                          );
                          if (betweenIndex != null) {
                            // 경계 감지: 빈 문단 삽입
                            setState(() {
                              _imageRowBoundaryTapped = true;
                            });
                            final rowIndex = doc?.getNodeIndexById(
                              widget.nodeId,
                            );
                            if (rowIndex != null && rowIndex != -1) {
                              // EditorService를 통해 빈 문단 삽입
                              final editorService =
                                  widget.dragService?.editorService;
                              if (editorService != null) {
                                editorService.insertEmptyParagraphAtIndex(
                                  rowIndex + 1,
                                );
                                context.read<NodeComponentService>().selectNode(
                                  null,
                                );
                                widget.dragService?.invalidateNodeRectCache();
                              }
                            }
                          }
                        }
                      }
                      : null,
              onTap:
                  widget.isEditing && widget.dragService != null
                      ? () {
                        // 🎯 특수 노드 사이 클릭이면 셀렉 보류
                        if (_isSpecialNodeGapTap) {
                          setState(() {
                            _isSpecialNodeGapTap = false;
                          });
                          return;
                        }

                        // 이미지 사이 경계가 탭되었으면 노드 선택 처리 안 함
                        if (_imageRowBoundaryTapped) {
                          setState(() {
                            _imageRowBoundaryTapped = false;
                          });
                          return;
                        }
                        // 일반 영역: 노드 선택
                        final imageService =
                            context.read<NodeComponentService>();
                        final currentSelected = imageService.selectedImageId;
                        if (currentSelected == widget.nodeId) {
                          // 같은 노드 재탭: 선택 해제
                          imageService.selectNode(null);
                          widget.dragService?.invalidateNodeRectCache();
                        } else {
                          // 다른 노드 선택
                          imageService.selectNode(widget.nodeId);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              widget.dragService?.invalidateNodeRectCache();
                            }
                          });
                        }
                      }
                      : null,
              onLongPressStart:
                  widget.isEditing && widget.dragService != null
                      ? (details) {
                        // 키보드 내리기
                        final keyboardVisible =
                            MediaQuery.of(context).viewInsets.bottom > 0;
                        if (keyboardVisible) {
                          FocusScope.of(context).unfocus();
                        }
                        // 이미지 인덱스 찾기
                        final node = doc?.getNodeById(widget.nodeId);
                        if (node is ImageRowNode) {
                          final imageIndex = _findClickedImageIndex(
                            node,
                            details.globalPosition,
                          );
                          final imageService =
                              context.read<NodeComponentService>();
                          final isRowSelected =
                              imageService.selectedImageId == widget.nodeId;
                          if (isRowSelected) {
                            // 선택되어 있으면 바로 드래그
                            widget.dragService?.startDrag(
                              widget.nodeId,
                              context,
                              details.globalPosition,
                            );
                          } else {
                            // 선택 안 되어 있으면 분리 정보 설정 후 드래그
                            if (imageIndex != null) {
                              widget.dragService?.startDrag(
                                widget.nodeId,
                                context,
                                details.globalPosition,
                              );
                              widget.dragService?.setSplitImageInfo(
                                widget.nodeId,
                                imageIndex,
                              );
                            }
                          }
                        }
                      }
                      : null,
              onLongPressMoveUpdate:
                  widget.isEditing && widget.dragService != null
                      ? (details) {
                        // 드래그 업데이트 (auto-scroll은 DragService 내부에서 처리)
                        widget.dragService?.updateDrag(
                          details.globalPosition,
                          context,
                        );
                      }
                      : null,
              onLongPressEnd:
                  widget.isEditing && widget.dragService != null
                      ? (_) {
                        widget.dragService?.endDrag();
                      }
                      : null,
              child: Padding(
                padding: EdgeInsets.only(top: marginTop, bottom: marginBottom),
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // 행 전체 스포일러 여부 계산 (per-image 블러를 위해 선계산)
                        bool isRowSpoiler = false;
                        try {
                          final node = doc?.getNodeById(widget.nodeId);
                          Map<String, dynamic>? meta;
                          if (node is ImageRowNode) {
                            meta = node.metadata;
                          }
                          isRowSpoiler = context
                              .read<NodeComponentService>()
                              .shouldShowImageSpoiler(widget.nodeId, meta);
                        } catch (_) {}

                        // 🎯 업로드 중 상태 확인 (메타데이터 + 실제 업로드 태스크 존재 여부)
                        bool isUploading = false;
                        try {
                          final node = doc?.getNodeById(widget.nodeId);
                          if (node is ImageRowNode) {
                            final meta = node.metadata;
                            final isPlaceholder = meta['isPlaceholder'] == true;
                            // 🎯 플레이스홀더이면서 실제 업로드 태스크가 있을 때만 로딩 표시
                            if (isPlaceholder) {
                              try {
                                final uploadService =
                                    context.read<UploadService>();
                                isUploading = uploadService
                                    .hasActiveUploadForRef(widget.nodeId);
                              } catch (e) {
                                debugPrint(
                                  '[RowImage] UploadService 확인 실패: $e',
                                );
                                // UploadService를 사용할 수 없으면 플레이스홀더 상태 그대로 사용
                                isUploading = isPlaceholder;
                              }
                            }
                          }
                        } catch (_) {}

                        // 🎯 노드 레벨 댓글 정보 확인 (이미지 로우 전체)
                        bool hasComments = false;
                        try {
                          final node = doc?.getNodeById(widget.nodeId);
                          if (node is ImageRowNode) {
                            final meta = node.metadata;
                            // 노드 레벨 hasComments 확인
                            hasComments = meta['hasComments'] == true;

                            // 노드 레벨 정보가 없으면 각 이미지별 정보 확인
                            if (!hasComments) {
                              final commentInfo =
                                  meta['imageCommentInfo']
                                      as Map<String, dynamic>?;
                              if (commentInfo != null) {
                                // 하나라도 댓글이 있으면 표시
                                hasComments = commentInfo.values.any((imgInfo) {
                                  if (imgInfo is Map) {
                                    return imgInfo['hasComments'] == true;
                                  }
                                  return false;
                                });
                              }
                            }
                          }
                        } catch (_) {}

                        return Stack(
                          children: [
                            Row(
                              children: [
                                // 이미지들
                                ...widget.imageUrls.asMap().entries.map((
                                  entry,
                                ) {
                                  final imageUrl = entry.value;

                                  return Expanded(
                                    child: Container(
                                      margin:
                                          imageUrl == widget.imageUrls.last
                                              ? EdgeInsets.zero
                                              : const EdgeInsets.only(right: 2),
                                      child: Stack(
                                        children: [
                                          ConstrainedBox(
                                            constraints: BoxConstraints.expand(
                                              height: _unifiedHeight ?? 150,
                                            ),
                                            child: ImageFiltered(
                                              imageFilter:
                                                  isRowSpoiler
                                                      ? ui.ImageFilter.blur(
                                                        sigmaX: 12,
                                                        sigmaY: 12,
                                                      )
                                                      : ui.ImageFilter.blur(
                                                        sigmaX: 0,
                                                        sigmaY: 0,
                                                      ),
                                              child: _buildRowImageWidget(
                                                imageUrl,
                                                constraints.maxWidth,
                                              ),
                                            ),
                                          ),
                                          // ✅ 블러 위 어둡게(0.2) 오버레이
                                          if (isRowSpoiler)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: Container(
                                                  color: Colors.black
                                                      .withOpacity(0.15),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                            // 🎯 이미지 로우 전체 상단 끝에 댓글 배지 하나만 표시
                            if (hasComments)
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

                            // 🎯 업로드 중 로딩 스피너
                            if (isUploading)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.6),
                                    alignment: Alignment.center,
                                    child: const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 4,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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

                    // 스포일러 마스킹 (metadata + 세션 캐시)
                    Builder(
                      builder: (context) {
                        bool isSpoilerFlag = false;
                        final nodeService =
                            context.watch<NodeComponentService>();
                        try {
                          final node = doc?.getNodeById(widget.nodeId);
                          Map<String, dynamic>? meta;
                          if (node is ImageRowNode) {
                            meta = node.metadata;
                          }
                          isSpoilerFlag = nodeService.shouldShowImageSpoiler(
                            widget.nodeId,
                            meta,
                          );
                        } catch (_) {}

                        // 스포일러 해제 시 scatter 애니메이션 트리거
                        if (_wasSpoilerVisible &&
                            !isSpoilerFlag &&
                            _scatterCtrl.status != AnimationStatus.forward) {
                          _scatterActive = true;
                          _scatterCtrl
                            ..reset()
                            ..forward();
                        }
                        _wasSpoilerVisible = isSpoilerFlag;

                        if (!isSpoilerFlag && !_scatterActive) {
                          return const SizedBox.shrink();
                        }

                        return Builder(
                          builder: (context) {
                            final brightness = Theme.of(context).brightness;
                            final isLightTheme = brightness == Brightness.light;

                            return Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedBuilder(
                                  animation:
                                      _scatterActive
                                          ? _scatterCtrl
                                          : _controller,
                                  builder: (context, _) {
                                    if (_scatterActive) {
                                      return CustomPaint(
                                        painter: _RowImageSpoilerScatterPainter(
                                          progress: _scatterCtrl.value,
                                          backgroundColor: Colors.white,
                                          dotColor: Colors.white,
                                          isLightTheme: isLightTheme,
                                        ),
                                      );
                                    } else {
                                      return CustomPaint(
                                        painter: _RowImageSpoilerPainter(
                                          phase: _controller.value,
                                          isEditing: widget.isEditing,
                                          backgroundColor: Colors.transparent,
                                          dotColor: Colors.white,
                                          isLightTheme: isLightTheme,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    // 선택 보더
                    if (isSelected || isDownstreamSelected)
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
                          child: Container(height: 5, color: AppColors.primary),
                        ),

                      // 아래쪽 가로 라인
                      if (_shouldShowBottomDropLine())
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(height: 5, color: AppColors.primary),
                        ),

                      // 왼쪽 세로 라인 (가로배치 모드일 때)
                      if (_shouldShowLeftVerticalLine())
                        Positioned(
                          left: 0,
                          top: marginTop,
                          bottom: marginBottom,
                          child: Container(width: 5, color: AppColors.primary),
                        ),

                      // 오른쪽 세로 라인 (가로배치 모드일 때)
                      if (_shouldShowRightVerticalLine())
                        Positioned(
                          right: 0,
                          top: marginTop,
                          bottom: marginBottom,
                          child: Container(width: 5, color: AppColors.primary),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        if (!hasImageBelow)
          SizedBox(height: EditorConfig.specialNodePaddingWithText),
      ],
    );
  }

  /// 🎯 완전히 재설계된 높이 계산 로직
  /// - metadata 의존 완전 제거
  /// - 실시간 측정 및 즉각 반영
  /// - 모든 이미지가 측정되면 평균 높이 계산
  void _measureAndUnifyHeight(String imageUrl, double availableWidth) {
    if (!mounted) return;

    // 🎯 이미 측정 중인 이미지면 스킵
    if (_imageSizes.containsKey(imageUrl)) {
      return;
    }

    debugPrint('[RowImage] 📏 이미지 측정: $imageUrl');

    // 🎯 로컬/네트워크 자동 판단
    final ImageProvider imageProvider;
    if (_isLocalPath(imageUrl)) {
      final filePath =
          imageUrl.startsWith('file://') ? imageUrl.substring(7) : imageUrl;
      imageProvider = FileImage(File(filePath));
    } else {
      imageProvider = NetworkImage(imageUrl);
    }

    imageProvider
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener(
            (ImageInfo info, _) {
              if (!mounted) return;

              final originalSize = Size(
                info.image.width.toDouble(),
                info.image.height.toDouble(),
              );

              _imageSizes[imageUrl] = originalSize;
              debugPrint(
                '[RowImage] ✅ 측정: $imageUrl (${originalSize.width.toInt()}x${originalSize.height.toInt()})',
              );
              debugPrint(
                '[RowImage] 📊 진행: ${_imageSizes.length}/${widget.imageUrls.length}',
              );

              // 🎯 모든 이미지가 측정되었는지 확인
              if (_imageSizes.length == widget.imageUrls.length) {
                _calculateUnifiedHeight(availableWidth);
              }
            },
            onError: (exception, stackTrace) {
              debugPrint('[RowImage] ❌ 측정 실패: $imageUrl - $exception');
            },
          ),
        );
  }

  /// 🎯 통일된 높이 계산 (모든 이미지 측정 완료 후)
  void _calculateUnifiedHeight(double availableWidth) {
    if (!mounted) return;

    final count = widget.imageUrls.length;
    if (count == 0) return;

    // 각 이미지가 차지할 너비 계산
    final spacingWidth = widget.spacing * (count - 1);
    final eachWidth = (availableWidth - spacingWidth) / count;

    debugPrint('[RowImage] 🧮 높이 계산:');
    debugPrint('[RowImage]   총 너비: ${availableWidth.toInt()}px');
    debugPrint('[RowImage]   이미지당: ${eachWidth.toInt()}px');

    // 각 이미지의 원본 비율을 유지했을 때의 높이 계산
    final heights = <double>[];
    for (final url in widget.imageUrls) {
      final size = _imageSizes[url];
      if (size != null && size.width > 0) {
        final aspectRatio = size.height / size.width;
        final calculatedHeight = eachWidth * aspectRatio;
        heights.add(calculatedHeight);
        debugPrint('[RowImage]   → ${calculatedHeight.toInt()}px');
      }
    }

    if (heights.isEmpty) {
      debugPrint('[RowImage] ⚠️ 측정 가능한 이미지 없음');
      return;
    }

    // 🎯 평균 계산 (상위/하위 20% 제외하여 극단값 배제)
    heights.sort();
    final start = (heights.length * 0.2).floor();
    final end = (heights.length * 0.8).ceil();

    final filtered =
        heights.length > 2
            ? heights.sublist(start, end)
            : heights; // 2개 이하면 전체 사용

    final avg = filtered.reduce((a, b) => a + b) / filtered.length;

    // 🎯 최소/최대 범위 제한 (150px ~ 400px)
    final unified = avg.clamp(150.0, 400.0);

    debugPrint(
      '[RowImage] 🎯 최종 높이: ${unified.toInt()}px (평균: ${avg.toInt()}px)',
    );

    // 🎯 setState로 UI 업데이트
    if (_unifiedHeight != unified) {
      setState(() {
        _unifiedHeight = unified;
      });
      debugPrint('[RowImage] ✨ UI 업데이트 완료');
    }
  }

  bool _shouldShowTopDropLine() {
    return DropLineConfig.shouldShowTopDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
      isRowImage: true, // 🎯 RowImageComponent
    );
  }

  bool _shouldShowBottomDropLine() {
    return DropLineConfig.shouldShowBottomDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
      isRowImage: true, // 🎯 RowImageComponent
    );
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

  bool _hasNeighborImage(Document? doc, String nodeId, int direction) {
    if (doc == null) return false;
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;

    // 🎯 바로 인접한 노드 확인
    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        // 바로 인접한 노드가 특수 노드인 경우
        if (immediateNeighbor is ImageNode ||
            immediateNeighbor is ImageRowNode ||
            immediateNeighbor is ClipNode ||
            immediateNeighbor is LinkNode) {
          return true;
        }

        // 바로 인접한 노드가 빈 ParagraphNode인 경우
        if (immediateNeighbor is ParagraphNode) {
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;
          final isTitle = immediateNeighbor.metadata['isTitle'] == true;

          // 빈 ParagraphNode면 그 다음 노드를 확인
          if (!isTitle && isEmpty) {
            // 빈 ParagraphNode 다음 노드 확인
            final nextIndex = immediateIndex + direction;
            if (nextIndex >= 0 && nextIndex < doc.nodeCount) {
              final nextNeighbor = doc.getNodeAt(nextIndex);
              if (nextNeighbor is ImageNode ||
                  nextNeighbor is ImageRowNode ||
                  nextNeighbor is ClipNode ||
                  nextNeighbor is LinkNode) {
                // 빈 ParagraphNode를 사이에 둔 특수 노드 → 패딩 필요 (false 반환)
                return false;
              }
            }
            // 빈 ParagraphNode 다음에 특수 노드가 없으면 계속 검색
          } else if (!isTitle && !isEmpty) {
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
      if (neighbor is ImageNode ||
          neighbor is ImageRowNode ||
          neighbor is ClipNode ||
          neighbor is LinkNode) {
        return true;
      }

      // 빈 ParagraphNode가 아니면 (텍스트가 있는 경우) 패딩 필요
      if (neighbor is ParagraphNode) {
        final isEmpty = neighbor.text.text.trim().isEmpty;
        final isTitle = neighbor.metadata['isTitle'] == true;
        // 제목이 아니고 비어있지 않으면 텍스트 노드이므로 패딩 필요
        if (!isTitle && !isEmpty) {
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

  /// 🎯 Row 이미지 위젯 빌드 (로컬/네트워크 자동 판단)
  Widget _buildRowImageWidget(String imageUrl, double maxWidth) {
    final isLocal = _isLocalPath(imageUrl);

    if (isLocal) {
      // 로컬 이미지
      final filePath =
          imageUrl.startsWith('file://') ? imageUrl.substring(7) : imageUrl;

      return Image.file(
        File(filePath),
        key: ValueKey('$imageUrl-${Theme.of(context).brightness}'),
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded || frame != null) {
            // 로드 완료 → 높이 측정 트리거
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _measureAndUnifyHeight(imageUrl, maxWidth);
            });
            return child;
          }

          // 🎯 로컬 이미지 첫 로드 중: 쉬머 표시
          return Container(
            width: double.infinity,
            height: _unifiedHeight ?? 150,
            color:
                widget.isDarkMode
                    ? Colors.grey[900]?.withOpacity(0.1)
                    : Colors.grey[200]?.withOpacity(0.5),
          );
        },
        errorBuilder: (context, error, stack) {
          debugPrint('[RowImage] 로컬 이미지 로드 실패: $imageUrl, $error');
          return ImageErrorPlaceholder(width: 200);
        },
      );
    } else {
      // 네트워크 이미지
      return Image.network(
        imageUrl,
        key: ValueKey('$imageUrl-${Theme.of(context).brightness}'),
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSyncLoaded) {
          // 🎯 프리로드되었거나 캐시에 있으면 즉시 표시
          if (wasSyncLoaded || frame != null) {
            // 🎯 로드 완료 → 높이 측정 트리거 (로컬 이미지와 동일하게 처리)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _measureAndUnifyHeight(imageUrl, maxWidth);
            });
            return child;
          }

          // 🎯 네트워크 이미지 로드 중:
          // - 높이가 이미 측정되어 있으면 투명 컨테이너 (로컬→네트워크 전환 시)
          // - 높이가 없으면 쉬머 (첫 로딩)
          if (_unifiedHeight != null) {
            // 이미 로컬 이미지로 높이를 측정했으므로 투명 컨테이너만 표시
            return SizedBox(
              width: double.infinity,
              height: _unifiedHeight,
              child: Container(
                color:
                    widget.isDarkMode
                        ? Colors.grey[900]?.withOpacity(0.1)
                        : Colors.grey[200]?.withOpacity(0.3),
              ),
            );
          } else {
            // 첫 로딩이므로 쉬머 표시
            return Container(
              width: double.infinity,
              height: 150,
              color:
                  widget.isDarkMode
                      ? Colors.grey[900]?.withOpacity(0.1)
                      : Colors.grey[200]?.withOpacity(0.5),
            );
          }
        },
        errorBuilder: (context, error, stack) {
          debugPrint('[RowImage] 네트워크 이미지 로드 실패: $imageUrl, $error');
          return ImageErrorPlaceholder(width: 200);
        },
      );
    }
  }

  bool _isLocalPath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return false;
    if (path.startsWith('file://')) return true;
    return path.startsWith('/') ||
        path.contains('/Application/') ||
        path.contains('/Documents/');
  }
}

class _RowImageSpoilerPainter extends CustomPainter {
  final double phase;
  final bool isEditing;
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;
  _RowImageSpoilerPainter({
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
    if (backgroundColor.alpha != 0) {
      final double alpha = isEditing ? 0.4 : 1.0;
      if (alpha > 0) {
        mask.color = backgroundColor.withOpacity(alpha);
        canvas.drawRect(rect, mask);
      }
    }
    // 점을 더 선명하게 (높은 불투명도)
    final dotOpacity = isLightTheme ? 0.9 : 0.95;
    final dot =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(dotOpacity);

    final area = rect.width * rect.height;
    // 밀도 상향: 행에서도 충분한 알갱이 수 유지
    final count =
        isEditing
            ? math.max(300, (area / 1200).floor())
            : math.max(400, (area / 900).floor());
    // 속도 더 낮춤 (row 전용)
    final double t = phase * (2 * math.pi) * 0.9;

    // 기본 점들 그리기 (크기 2.2, 움직임/깜빡임 강화)
    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 486187739);
      final r = math.Random(seed);
      final baseX = r.nextDouble() * rect.width;
      final baseY = r.nextDouble() * rect.height;
      // 진폭 더 낮춤 (움직임 강도 추가 감소)
      final amp = 0.6 + r.nextDouble() * 3.0; // 0.6~3.6px
      final ox = math.sin(t + i * 0.21) * amp;
      final oy = math.cos(t * 0.9 + i * 0.13) * amp;
      double x = baseX + ox;
      double y = baseY + oy;
      // width/height가 0일 경우 나눗셈으로 NaN이 발생하지 않도록 방어
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
      final twinkle = 0.7 + 0.3 * math.sin(t * 1.0 + i * 0.45);
      final p = dot..color = dot.color.withOpacity(dotOpacity * twinkle);
      // 알갱이 크기 축소
      final sizePx = 1.0 + r.nextDouble() * 1.4; // 1.0~2.4px 원형
      canvas.drawCircle(Offset(x, y), sizePx / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RowImageSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.isEditing != isEditing;
  }
}

/// 이미지 행 스포일러 scatter 애니메이션 페인터
class _RowImageSpoilerScatterPainter extends CustomPainter {
  final double progress; // 0..1 진행도
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;

  _RowImageSpoilerScatterPainter({
    required this.progress,
    required this.backgroundColor,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseOpacity = isLightTheme ? 0.4 : 0.6;
    final fade = (1.0 - Curves.easeOut.transform(progress)).clamp(0.0, 1.0);
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = backgroundColor.withOpacity(baseOpacity * fade);

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
      final move = Curves.easeOutQuad.transform(progress) * speed;
      final x = startX + nx * move;
      final y = startY + ny * move;
      final sz = 1.2 + (1.8 * (1.0 - progress));
      canvas.drawRect(Rect.fromLTWH(x, y, sz, sz), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RowImageSpoilerScatterPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// ImageRowNode의 뷰모델
class ImageRowComponentViewModel extends SingleColumnLayoutComponentViewModel {
  ImageRowComponentViewModel({
    required super.nodeId,
    required this.imageUrls,
    required this.spacing,
    this.unifiedHeight, // 🎯 사용하지 않음 (deprecated)
  }) : super(createdAt: DateTime.now(), padding: EdgeInsets.zero);

  final List<String> imageUrls;
  final double spacing;
  final double? unifiedHeight; // 🎯 metadata 의존 제거 (deprecated)

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return ImageRowComponentViewModel(
      nodeId: nodeId,
      imageUrls: imageUrls,
      spacing: spacing,
      unifiedHeight: null, // 항상 null
    );
  }
}
