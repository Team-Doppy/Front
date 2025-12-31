import 'dart:async';

import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:super_editor/super_editor.dart';
import 'dart:math' as math;

/// 여러 이미지를 PageView로 표시하는 커스텀 노드
class PageViewImageNode extends BlockNode {
  PageViewImageNode({
    required this.id,
    required List<String> imageUrls,
    Map<String, dynamic>? metadata,
  }) : imageUrls = imageUrls.toList(),
       _metadata = metadata ?? <String, dynamic>{};

  @override
  bool get isDeletable => true;

  @override
  final String id;
  final List<String> imageUrls;
  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

  String get nodeType => 'pageviewImage';

  bool get hasContent => imageUrls.isNotEmpty;

  PageViewImageNode copyWith({
    String? id,
    List<String>? imageUrls,
    Map<String, dynamic>? metadata,
  }) {
    return PageViewImageNode(
      id: id ?? this.id,
      imageUrls: imageUrls?.toList() ?? this.imageUrls,
      metadata: metadata ?? _metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeType': nodeType,
      'imageUrls': imageUrls,
      if (_metadata.isNotEmpty) 'metadata': _metadata,
    };
  }

  static PageViewImageNode fromJson(Map<String, dynamic> json) {
    return PageViewImageNode(
      id: json['id'] as String,
      imageUrls: List<String>.from(json['imageUrls'] as List),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  bool containsPosition(Object position) {
    return position is UpstreamDownstreamNodePosition;
  }

  Rect getRectForPosition(NodePosition nodePosition) {
    return const Rect.fromLTWH(0, 0, 0, 0);
  }

  NodeSelection getSelectionOfEverything() {
    return UpstreamDownstreamNodeSelection(
      base: const UpstreamDownstreamNodePosition.upstream(),
      extent: const UpstreamDownstreamNodePosition.downstream(),
    );
  }

  bool isVisualSelectionSupported() {
    return false;
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return PageViewImageNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      metadata: newMetadata,
    );
  }

  @override
  String? copyContent(NodeSelection selection) {
    return null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    final updatedMetadata = Map<String, dynamic>.from(_metadata);
    updatedMetadata.addAll(newProperties);
    return PageViewImageNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
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

class PageViewImageComponentBuilder implements ComponentBuilder {
  const PageViewImageComponentBuilder({
    required this.screenWidth,
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
  });

  final double screenWidth; // 🚀 최고 효율: 외부에서 전달받음
  final dynamic dragService;
  final bool isEditing;
  final bool isDarkMode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is PageViewImageComponentViewModel) {
      // ✅ 중요: nodeId 기반 GlobalObjectKey로 컴포넌트 Key를 안정화해서
      // 문서 조작 시 PageController/이미지 캐시 State가 불필요하게 리셋되는 것을 방지한다.
      // ✅ 중요: SuperEditor의 componentKey 추적을 깨면 드래그&드롭/삽입이 망가질 수 있으므로 유지한다.
      return PageViewImageComponent(
        nodeId: componentViewModel.nodeId,
        imageUrls: componentViewModel.imageUrls,
        screenWidth: screenWidth, // 🚀 최고 효율: 전달
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
    if (node is PageViewImageNode) {
      return PageViewImageComponentViewModel(
        nodeId: node.id,
        imageUrls: node.imageUrls,
      );
    }
    return null;
  }
}

/// PageView로 이미지를 표시하는 컴포넌트
class PageViewImageComponent extends StatefulWidget {
  const PageViewImageComponent({
    required this.nodeId,
    required this.imageUrls,
    required this.screenWidth,
    required GlobalKey componentKey,
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final List<String> imageUrls;
  final double screenWidth; // 🚀 최고 효율: 외부에서 한 번만 계산된 값
  final dynamic dragService;
  final bool isEditing;
  final bool isDarkMode;

  final GlobalKey _componentKey;

  GlobalKey get componentKey => _componentKey;

  @override
  State<PageViewImageComponent> createState() => _PageViewImageComponentState();
}

class _PageViewImageComponentState extends State<PageViewImageComponent>
    with DocumentComponent, TickerProviderStateMixin {
  // ✅ 같은 URL 이미지가 리빌드/재해결 과정에서 잠깐 frame=null이 되어도
  // 마지막으로 성공적으로 렌더된 child를 유지해서 "사라졌다가 다시 뜨는" 깜빡임을 줄인다.
  final Map<String, Widget> _lastRenderedByUrl = <String, Widget>{};
  late PageController _pageController;
  int _currentPage = 0;

  Timer? _edgeAutoPageTimer;
  int _edgeAutoPageDir = 0;

  late final AnimationController _controller;
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  bool _wasSpoilerVisible = false;
  bool _isSpecialNodeGapTap = false;

  // ✅ CachedNetworkImage 로딩 중에도 이전 이미지를 유지(깜빡임 방지)
  final Map<String, ImageProvider> _lastNetworkProviders = {};

  // 로컬 경로 -> 업로드 URL 변환 과정에서도 "같은 이미지"로 취급할 수 있도록
  // 업로드 매핑(uploadedUrls: {localPath: networkUrl})을 역으로 조회해서 canonical seed를 만든다.
  String _canonicalSeedForImageUrl(String imageUrl) {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      // ignore: invalid_use_of_visible_for_testing_member
      final doc = seState?.editContext.editor.document;
      if (doc == null) return imageUrl;
      final node = doc.getNodeById(widget.nodeId);
      if (node is! PageViewImageNode) return imageUrl;
      final meta = node.metadata;
      final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
      if (uploadedUrls == null || uploadedUrls.isEmpty) return imageUrl;

      // localPath인 경우
      if (uploadedUrls.containsKey(imageUrl)) return imageUrl;

      // networkUrl인 경우: value==imageUrl인 localPath 찾기
      for (final entry in uploadedUrls.entries) {
        final v = entry.value?.toString() ?? '';
        if (v == imageUrl) {
          final k = entry.key.toString();
          if (k.isNotEmpty) return k;
        }
      }
    } catch (_) {}
    return imageUrl;
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
      const UpstreamDownstreamNodePosition.downstream();

  @override
  NodePosition getEndPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  static const double marginTop = 2;
  static const double marginBottom = 2;

  bool _handleSpecialNodeTap(Offset globalPosition) {
    if (widget.dragService == null) return false;
    final editorService = widget.dragService!.editorService;
    final doc = editorService.document;
    final dragService = widget.dragService!;

    final currentNodeIndex = doc.getNodeIndexById(widget.nodeId);
    if (currentNodeIndex == -1) return false;

    final nodeRect = dragService.getNodeGlobalRect(widget.nodeId);
    if (nodeRect == null) return false;

    // 위쪽 이웃 노드 확인
    if (currentNodeIndex > 0) {
      final prevNode = doc.getNodeAt(currentNodeIndex - 1);
      if (prevNode != null) {
        if (NodeTypeChecker.isSpecialNode(prevNode)) {
          final prevRect = dragService.getNodeGlobalRect(prevNode.id);
          if (prevRect != null) {
            final gapTop = prevRect.bottom - 20;
            final gapBottom = nodeRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }

    // 아래쪽 이웃 노드 확인
    if (currentNodeIndex < doc.nodeCount - 1) {
      final nextNode = doc.getNodeAt(currentNodeIndex + 1);
      if (nextNode != null) {
        if (NodeTypeChecker.isSpecialNode(nextNode)) {
          final nextRect = dragService.getNodeGlobalRect(nextNode.id);
          if (nextRect != null) {
            final gapTop = nodeRect.bottom - 20;
            final gapBottom = nextRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
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
    assert(() {
      debugPrint(
        '[ImgLife][PageView] init: nodeId=${widget.nodeId}, keyHash=${identityHashCode(widget.key)}, componentKeyHash=${identityHashCode(widget._componentKey)}, urls=${widget.imageUrls.length}',
      );
      return true;
    }());
    _pageController = PageController(
      viewportFraction: 0.9, // 🎯 화면의 90% 사용 (padEnds 영역 줄이기)
    );

    // PageView 현재 페이지를 DragService에 전달(드롭 인덱스 계산용)
    final ds = widget.dragService;
    if (ds is DragService) {
      ds.setPageViewCurrentPage(widget.nodeId, _currentPage);
    }

    // 드래그 중 엣지 홀드 오토페이징을 위해 dragService 변경 감지
    if (widget.dragService is Listenable) {
      (widget.dragService as Listenable).addListener(_onDragServiceChanged);
    }

    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 900));

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
  void dispose() {
    assert(() {
      debugPrint(
        '[ImgLife][PageView] dispose: nodeId=${widget.nodeId}, keyHash=${identityHashCode(widget.key)}, componentKeyHash=${identityHashCode(widget._componentKey)}',
      );
      return true;
    }());
    _stopEdgeAutoPaging();
    if (widget.dragService is Listenable) {
      (widget.dragService as Listenable).removeListener(_onDragServiceChanged);
    }
    _pageController.dispose();
    _controller.dispose();
    _scatterCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PageViewImageComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlsChanged = !_areUrlsEqual(oldWidget.imageUrls, widget.imageUrls);
    final oldCount = oldWidget.imageUrls.length;
    final newCount = widget.imageUrls.length;
    final countIncreased = newCount > oldCount;

    if (urlsChanged) {
      _lastRenderedByUrl.clear();
    }

    // 🎯 이미지가 삽입된 경우 해당 인덱스로 부드럽게 스크롤
    if (countIncreased &&
        widget.isEditing &&
        widget.dragService is DragService) {
      final ds = widget.dragService as DragService;
      // DragService의 dropTarget에서 insertIndex 확인
      final insertIndex =
          (ds.dropTarget.kind == DropTargetKind.mergeIntoPageView &&
                  ds.dropTarget.targetRowId == widget.nodeId)
              ? ds.dropTarget.insertIndex
              : null;

      if (insertIndex != null &&
          insertIndex >= 0 &&
          insertIndex < newCount &&
          _pageController.hasClients) {
        // 🎯 삽입된 이미지가 가운데 보이도록 부드럽게 스크롤
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.animateToPage(
              insertIndex,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
            );
            setState(() {
              _currentPage = insertIndex;
            });
          }
        });
      }
    }

    // 현재 페이지가 범위를 넘어가면 안전하게 보정
    final maxPage = (widget.imageUrls.length - 1).clamp(0, 999999);
    if (_currentPage > maxPage) {
      _currentPage = maxPage;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
      }
    }

    // dragService 인스턴스가 바뀌면 리스너 재연결
    if (oldWidget.dragService != widget.dragService) {
      if (oldWidget.dragService is Listenable) {
        (oldWidget.dragService as Listenable).removeListener(
          _onDragServiceChanged,
        );
      }
      if (widget.dragService is Listenable) {
        (widget.dragService as Listenable).addListener(_onDragServiceChanged);
      }
    }
    assert(() {
      debugPrint(
        '[ImgLife][PageView] didUpdateWidget: nodeId=${widget.nodeId}, urlsChanged=$urlsChanged, oldCount=${oldWidget.imageUrls.length}, newCount=${widget.imageUrls.length}',
      );
      if (urlsChanged) {
        debugPrint(
          '[ImgLife][PageView] urls(old)=${oldWidget.imageUrls}\n[ImgLife][PageView] urls(new)=${widget.imageUrls}',
        );
      }
      return true;
    }());
  }

  void _onDragServiceChanged() {
    // 🎯 편집 모드에서만 자동 페이징 동작
    if (!widget.isEditing) {
      _stopEdgeAutoPaging();
      return;
    }
    final ds = widget.dragService;
    if (ds is! DragService) return;
    _updateEdgeAutoPaging(ds);
  }

  void _updateEdgeAutoPaging(DragService ds) {
    // 🎯 편집 모드에서만 자동 페이징 동작
    if (!widget.isEditing) {
      _stopEdgeAutoPaging();
      return;
    }
    // PageView가 드롭 타겟일 때만 자동 페이징
    final isTarget =
        ds.dropTarget.kind == DropTargetKind.mergeIntoPageView &&
        ds.dropTarget.targetRowId == widget.nodeId;
    final globalPos = ds.dragPosition;

    if (!isTarget || globalPos == null || widget.imageUrls.length <= 1) {
      _stopEdgeAutoPaging();
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _stopEdgeAutoPaging();
      return;
    }
    final local = box.globalToLocal(globalPos);
    const edgeThreshold = 30.0;
    final w = box.size.width;

    int dir = 0;
    if (local.dx <= edgeThreshold) {
      dir = -1;
    } else if (local.dx >= w - edgeThreshold) {
      dir = 1;
    }

    if (dir == 0) {
      _stopEdgeAutoPaging();
      return;
    }

    if (_edgeAutoPageTimer != null && _edgeAutoPageDir == dir) {
      return; // 같은 방향으로 이미 동작 중
    }

    _edgeAutoPageDir = dir;
    _edgeAutoPageTimer?.cancel();
    _edgeAutoPageTimer = Timer.periodic(
      const Duration(milliseconds: 420),
      (_) => _pageOnce(dir),
    );

    // 첫 페이징은 즉시 한 번 실행
    _pageOnce(dir);
  }

  void _stopEdgeAutoPaging() {
    _edgeAutoPageTimer?.cancel();
    _edgeAutoPageTimer = null;
    _edgeAutoPageDir = 0;
  }

  void _pageOnce(int dir) {
    if (!mounted || widget.imageUrls.isEmpty) return;
    if (!_pageController.hasClients) return;

    final current = _pageController.page?.round() ?? _currentPage;
    final next = (current + dir).clamp(0, widget.imageUrls.length - 1);
    if (next == current) return;

    // 🎯 더 부드러운 페이징 애니메이션
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  bool _areUrlsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 성능 최적화: context.watch → context.select로 변경
    final isSelected = context.select<NodeComponentService, bool>(
      (service) => service.selectedImageId == widget.nodeId,
    );

    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection = seState?.editContext.composer.selection;
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;

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

    final bool hasImageAbove = _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow = _hasNeighborImage(doc, widget.nodeId, 1);

    // 스포일러 상태 확인
    bool isSpoilerFlag = false;
    try {
      final node = doc?.getNodeById(widget.nodeId);
      Map<String, dynamic>? meta;
      if (node is PageViewImageNode) {
        meta = node.metadata;
      }
      isSpoilerFlag = context
          .read<NodeComponentService>()
          .shouldShowImageSpoiler(widget.nodeId, meta);
    } catch (_) {}

    // 🎯 업로드 중 상태 확인 (편집 모드에서만, 읽기 전용 모드에서는 항상 false)
    // 🎯 성능 최적화: context.watch → context.select로 변경
    bool isUploading = false;
    if (widget.isEditing) {
      try {
        isUploading = context.select<UploadService, bool>(
          (service) => service.hasActiveUploadForRef(widget.nodeId),
        );
      } catch (e) {
        debugPrint('[PageViewImage] UploadService 확인 실패: $e');
      }
    }

    // 댓글 배지 확인
    bool hasComments = false;
    try {
      final node = doc?.getNodeById(widget.nodeId);
      if (node is PageViewImageNode) {
        final meta = node.metadata;
        hasComments = meta['hasComments'] == true;
      }
    } catch (_) {}

    // 스포일러 해제 시 scatter 애니메이션 트리거
    final wasSpoilerBefore = _wasSpoilerVisible;
    // 🎯 초기 렌더링 감지: _wasSpoilerVisible이 false이고 isSpoilerFlag가 true면 초기 상태
    final isInitialSpoilerRender = !_wasSpoilerVisible && isSpoilerFlag;
    if (_wasSpoilerVisible &&
        !isSpoilerFlag &&
        _scatterCtrl.status != AnimationStatus.forward) {
      _scatterActive = true;
      _scatterCtrl
        ..reset()
        ..forward();
    }
    _wasSpoilerVisible = isSpoilerFlag;

    // 🎯 RepaintBoundary로 감싸서 키보드 애니메이션 시 불필요한 repaint 방지
    return RepaintBoundary(
      child: Column(
        children: [
          if (!hasImageAbove)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
          Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown:
                    widget.isEditing && widget.dragService != null
                        ? (details) {
                          final isGapTap = _handleSpecialNodeTap(
                            details.globalPosition,
                          );
                          setState(() {
                            _isSpecialNodeGapTap = isGapTap;
                          });
                        }
                        : null,
                onTap:
                    widget.isEditing && widget.dragService != null
                        ? () {
                          if (_isSpecialNodeGapTap) {
                            setState(() {
                              _isSpecialNodeGapTap = false;
                            });
                            return;
                          }

                          final imageService =
                              context.read<NodeComponentService>();
                          final currentSelected = imageService.selectedImageId;
                          if (currentSelected == widget.nodeId) {
                            imageService.selectNode(null);
                            widget.dragService?.invalidateNodeRectCache();
                          } else {
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
                          // 🎯 키보드 내리기 + 포커스 해제 (드래그 시작 시)
                          FocusManager.instance.primaryFocus?.unfocus();
                          FocusScope.of(context).unfocus();

                          // 이미지 서비스 확인
                          final imageService =
                              context.read<NodeComponentService>();
                          final isPageViewSelected =
                              imageService.selectedImageId == widget.nodeId;

                          if (isPageViewSelected) {
                            // 선택되어 있으면 전체 PageView를 드래그
                            widget.dragService?.startDrag(
                              widget.nodeId,
                              context,
                              details.globalPosition,
                            );
                          } else {
                            // 선택 안 되어 있으면 현재 페이지 인덱스를 찾아 분리 정보 설정
                            // 🎯 중요: setSplitPageViewInfo를 먼저 호출해야 _extractImageUrl에서 올바른 이미지를 사용할 수 있음
                            final pageIndex = _currentPage;
                            widget.dragService?.setSplitPageViewInfo(
                              widget.nodeId,
                              pageIndex,
                            );
                            widget.dragService?.startDrag(
                              widget.nodeId,
                              context,
                              details.globalPosition,
                            );
                          }
                        }
                        : null,
                onLongPressMoveUpdate:
                    widget.isEditing && widget.dragService != null
                        ? (details) {
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
                  padding: const EdgeInsets.only(
                    top: marginTop,
                    bottom: marginBottom,
                  ),
                  child: Stack(
                    children: [
                      // 🎯 PageView로 이미지 표시 (0.8 fraction)
                      SizedBox(
                        height: 400, // 고정 높이
                        child: AnimatedBuilder(
                          animation:
                              widget.dragService is Listenable
                                  ? (widget.dragService as Listenable)
                                  : Listenable.merge(const []),
                          builder: (context, _) {
                            // 🎯 편집 모드에서만 삽입 슬롯 표시
                            // 🎯 실제로 드래그가 움직였을 때만 표시 (길게 눌렀다가 놓는 경우 방지)
                            final int? highlightInsertIndex =
                                (widget.isEditing &&
                                        widget.dragService is DragService)
                                    ? () {
                                      final ds =
                                          widget.dragService as DragService;
                                      // 드래그가 일정 거리 이상 움직였을 때만 표시
                                      return (ds.hasDraggedSignificantly &&
                                              ds.dropTarget.kind ==
                                                  DropTargetKind
                                                      .mergeIntoPageView &&
                                              ds.dropTarget.targetRowId ==
                                                  widget.nodeId)
                                          ? ds.dropTarget.insertIndex
                                          : null;
                                    }()
                                    : null;

                            return Stack(
                              children: [
                                PageView.builder(
                                  padEnds: true,
                                  controller: _pageController,
                                  itemCount: widget.imageUrls.length,
                                  onPageChanged: (index) {
                                    setState(() {
                                      _currentPage = index;
                                    });
                                    final ds = widget.dragService;
                                    if (ds is DragService) {
                                      ds.setPageViewCurrentPage(
                                        widget.nodeId,
                                        index,
                                      );
                                    }
                                  },
                                  itemBuilder: (context, index) {
                                    final imageUrl = widget.imageUrls[index];
                                    final isFirst = index == 0;
                                    final isLast =
                                        index == widget.imageUrls.length - 1;

                                    final bool showSlotBefore =
                                        highlightInsertIndex != null &&
                                        highlightInsertIndex == index;
                                    final bool showSlotAfter =
                                        highlightInsertIndex != null &&
                                        highlightInsertIndex ==
                                            widget.imageUrls.length &&
                                        isLast;

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        left: isFirst ? 0 : 4,
                                        right: isLast ? 0 : 4,
                                      ),
                                      child: Row(
                                        children: [
                                          AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            curve: Curves.easeInOutCubic,
                                            child:
                                                showSlotBefore
                                                    ? const _PageViewInsertSlot()
                                                    : const SizedBox.shrink(),
                                          ),
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Stack(
                                                children: [
                                                  // ✅ 스포일러 토글(ON/OFF) 시 블러를 부드럽게
                                                  // 🎯 초기 렌더링 시 스포일러 깜빡임 방지: 초기 상태일 때는 즉시 표시
                                                  TweenAnimationBuilder<double>(
                                                    tween: Tween<double>(
                                                      begin:
                                                          wasSpoilerBefore
                                                              ? 12.0
                                                              : 0.0,
                                                      end:
                                                          isSpoilerFlag
                                                              ? 12.0
                                                              : 0.0,
                                                    ),
                                                    duration:
                                                        isInitialSpoilerRender ||
                                                                wasSpoilerBefore ==
                                                                    isSpoilerFlag
                                                            ? Duration.zero
                                                            : const Duration(
                                                              milliseconds: 180,
                                                            ),
                                                    curve: Curves.easeOutCubic,
                                                    builder: (
                                                      context,
                                                      sigma,
                                                      child,
                                                    ) {
                                                      return ImageFiltered(
                                                        imageFilter: ui
                                                            .ImageFilter.blur(
                                                          sigmaX: sigma,
                                                          sigmaY: sigma,
                                                        ),
                                                        child: child,
                                                      );
                                                    },
                                                    child: _buildImageWidget(
                                                      index,
                                                      imageUrl,
                                                    ),
                                                  ),
                                                  // ✅ 블러 위 어둡게 오버레이도 페이드
                                                  // 🎯 초기 렌더링 시 스포일러 깜빡임 방지: 초기 상태일 때는 즉시 표시
                                                  Positioned.fill(
                                                    child: IgnorePointer(
                                                      child: AnimatedOpacity(
                                                        opacity:
                                                            isSpoilerFlag
                                                                ? 1
                                                                : 0,
                                                        duration:
                                                            isInitialSpoilerRender ||
                                                                    wasSpoilerBefore ==
                                                                        isSpoilerFlag
                                                                ? Duration.zero
                                                                : const Duration(
                                                                  milliseconds:
                                                                      160,
                                                                ),
                                                        curve:
                                                            Curves.easeOutCubic,
                                                        child: Container(
                                                          color: Colors.black
                                                              .withOpacity(
                                                                0.15,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            curve: Curves.easeInOutCubic,
                                            child:
                                                showSlotAfter
                                                    ? const _PageViewInsertSlot()
                                                    : const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                if (highlightInsertIndex != null)
                                  Positioned(
                                    top: 10,
                                    left: 0,
                                    right: 0,
                                    child: IgnorePointer(
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.55,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).t('drop_here'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),

                      // 🎯 하단 인디케이터 (현재 페이지/전체 페이지 형식)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_currentPage + 1}/${widget.imageUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 댓글 배지
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
                            child: Center(
                              child: const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  color: Colors.white,
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

                      // 스포일러 마스킹
                      if (isSpoilerFlag || _scatterActive)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation:
                                  _scatterActive ? _scatterCtrl : _controller,
                              builder: (context, _) {
                                if (_scatterActive) {
                                  return CustomPaint(
                                    painter:
                                        _PageViewImageSpoilerScatterPainter(
                                          progress: _scatterCtrl.value,
                                          backgroundColor: Colors.white,
                                          dotColor: Colors.white,
                                          isLightTheme:
                                              Theme.of(context).brightness ==
                                              Brightness.light,
                                        ),
                                  );
                                } else {
                                  return CustomPaint(
                                    painter: _PageViewImageSpoilerPainter(
                                      phase: _controller.value,
                                      isEditing: widget.isEditing,
                                      backgroundColor: Colors.transparent,
                                      dotColor: Colors.white,
                                      isLightTheme:
                                          Theme.of(context).brightness ==
                                          Brightness.light,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),

                      // 선택 보더
                      if (isSelected || isDownstreamSelected)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedSelectionBorder(
                              isVisible: true,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 4,
                                  ),
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
                        if (_shouldShowTopDropLine())
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: AnimatedDropLine(
                              child: Container(
                                height: 5,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        if (_shouldShowBottomDropLine())
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: AnimatedDropLine(
                              child: Container(
                                height: 5,
                                color: AppColors.primary,
                              ),
                            ),
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
      ),
    );
  }

  /// 🎯 이미지 위젯 빌드 (로컬/네트워크 자동 판단)
  Widget _buildImageWidget(int index, String imageUrl) {
    // ✅ 읽기 모드에서도 decodeWidth를 줘야 PostReaderService.preloadTopMedia(precacheImage)와
    // 동일한 ResizeImage(width) 캐시 키로 hit가 난다.
    final decodeWidth = EditorImageProvider.editingDecodeWidth(
      context,
      widget.screenWidth,
    );

    final built = EditorImageProvider.build(
      url: imageUrl,
      isEditing: widget.isEditing,
      decodeWidth: decodeWidth,
    );
    if (!built.isLocal) {
      _lastNetworkProviders[imageUrl] = built.baseProvider;
    }

    final seed = _canonicalSeedForImageUrl(imageUrl);
    final dupCount =
        widget.imageUrls
            .where((u) => _canonicalSeedForImageUrl(u) == seed)
            .length;
    final keySeed = dupCount <= 1 ? seed : '$seed#$index';

    return Image(
      key: ValueKey(
        'pv_${widget.nodeId}_${Theme.of(context).brightness}_$keySeed',
      ),
      image: built.effectiveProvider,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded || frame != null) {
          _lastRenderedByUrl[imageUrl] = child;
          return child;
        }
        final last = _lastRenderedByUrl[imageUrl];
        if (last != null) return last;
        return ShimmerBox(
          width: double.infinity,
          height: 400,
          isDarkMode: widget.isDarkMode,
        );
      },
      errorBuilder: (context, error, stack) {
        debugPrint('[PageViewImage] 이미지 로드 실패: $imageUrl, $error');
        return ImageErrorPlaceholder(width: 200);
      },
    );
  }

  bool _shouldShowTopDropLine() {
    return DropLineConfig.shouldShowTopDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowBottomDropLine() {
    return DropLineConfig.shouldShowBottomDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _hasNeighborImage(Document? doc, String nodeId, int direction) {
    if (doc == null) return false;
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;

    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        if (NodeTypeChecker.isSpecialNode(immediateNeighbor)) {
          return true;
        }

        if (immediateNeighbor is ParagraphNode) {
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;

          if (isEmpty) {
            final nextIndex = immediateIndex + direction;
            if (nextIndex >= 0 && nextIndex < doc.nodeCount) {
              final nextNeighbor = doc.getNodeAt(nextIndex);
              if (NodeTypeChecker.isSpecialNode(nextNeighbor)) {
                return false;
              }
            }
          } else if (!isEmpty) {
            return false;
          }
        } else {
          return false;
        }
      }
    }

    int searchIndex = myIndex + direction;
    while (searchIndex >= 0 && searchIndex < doc.nodeCount) {
      final neighbor = doc.getNodeAt(searchIndex);
      if (neighbor == null) break;

      if (NodeTypeChecker.isSpecialNode(neighbor)) {
        return true;
      }

      if (neighbor is ParagraphNode) {
        final isEmpty = neighbor.text.text.trim().isEmpty;
        if (!isEmpty) {
          return false;
        }
      } else {
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
        // ✅ start 경계: "노드 앞쪽(upstream)"에 걸리면 노드를 포함한다고 본다.
        // 아래→위 드래그에서 특수 노드가 start 경계가 되는 경우가 많아 대칭성을 보장해야 한다.
        return pos.affinity == TextAffinity.upstream;
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

// 스포일러 페인터들
class _PageViewImageSpoilerPainter extends CustomPainter {
  final double phase;
  final bool isEditing;
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;

  _PageViewImageSpoilerPainter({
    required this.phase,
    required this.isEditing,
    required this.backgroundColor,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final mask = Paint()..style = PaintingStyle.fill;

    if (backgroundColor.alpha != 0) {
      final double alpha = isEditing ? 0.4 : 1.0;
      if (alpha > 0) {
        mask.color = backgroundColor.withOpacity(alpha);
        canvas.drawRect(rect, mask);
      }
    }

    final dotOpacity = isLightTheme ? 0.9 : 0.95;
    final dot =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(dotOpacity);

    final area = rect.width * rect.height;
    final count =
        isEditing
            ? math.max(300, (area / 1200).floor())
            : math.max(400, (area / 900).floor());
    final double t = phase * (2 * math.pi) * 0.9;

    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 486187739);
      final r = math.Random(seed);
      final baseX = r.nextDouble() * rect.width;
      final baseY = r.nextDouble() * rect.height;
      final amp = 0.6 + r.nextDouble() * 3.0;
      final ox = math.sin(t + i * 0.21) * amp;
      final oy = math.cos(t * 0.9 + i * 0.13) * amp;
      double x = baseX + ox;
      double y = baseY + oy;

      if (rect.width > 0) {
        x = x % rect.width;
      } else {
        x = 0;
      }
      if (rect.height > 0) {
        y = y % rect.height;
      } else {
        y = 0;
      }
      if (x < 0) x += rect.width;
      if (y < 0) y += rect.height;

      final twinkle = 0.7 + 0.3 * math.sin(t * 1.0 + i * 0.45);
      final p = dot..color = dot.color.withOpacity(dotOpacity * twinkle);
      final sizePx = 1.0 + r.nextDouble() * 1.4;
      canvas.drawCircle(Offset(x, y), sizePx / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _PageViewImageSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.isEditing != isEditing;
  }
}

class _PageViewImageSpoilerScatterPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;

  _PageViewImageSpoilerScatterPainter({
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

      final dirX = (startX - cx);
      final dirY = (startY - cy);
      final dirLen = math.sqrt(dirX * dirX + dirY * dirY) + 0.001;
      final nx = dirX / dirLen;
      final ny = dirY / dirLen;
      final speed = 30 + r.nextDouble() * 44;
      final move = Curves.easeOutQuad.transform(progress) * speed;
      final x = startX + nx * move;
      final y = startY + ny * move;
      final sz = 1.2 + (1.8 * (1.0 - progress));
      canvas.drawRect(Rect.fromLTWH(x, y, sz, sz), paint);
    }
  }

  @override
  bool shouldRepaint(
    covariant _PageViewImageSpoilerScatterPainter oldDelegate,
  ) {
    return oldDelegate.progress != progress;
  }
}

class _PageViewInsertSlot extends StatelessWidget {
  const _PageViewInsertSlot();

  @override
  Widget build(BuildContext context) {
    // 🎯 패딩만 표시 (가운데 보라색 라인 제거)
    return Container(
      width: 18,
      height: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

/// PageViewImageNode의 뷰모델
class PageViewImageComponentViewModel
    extends SingleColumnLayoutComponentViewModel {
  PageViewImageComponentViewModel({
    required super.nodeId,
    required this.imageUrls,
  }) : super(createdAt: DateTime.now(), padding: EdgeInsets.zero);

  final List<String> imageUrls;

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return PageViewImageComponentViewModel(
      nodeId: nodeId,
      imageUrls: imageUrls,
    );
  }
}
