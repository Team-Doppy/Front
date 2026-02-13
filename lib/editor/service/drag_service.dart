import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../editor/config/editor_config.dart';
import '../../editor/config/emum_config.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/utils/node_type_checker.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/link_component.dart';
import '../../upload/service/upload_service_interface.dart';
import 'package:super_editor/super_editor.dart';

// ==========================================
// 타입 정의
// ==========================================

enum DragType { none, reorder, imageRowMerge, imagePageViewMerge }

/// 드래그 "대상(사용자가 실제로 잡은 것)"의 종류
enum DragSubjectKind { node, rowItem, pageViewItem }

/// 드래그 "의도"
enum DragIntent {
  none,
  reorderNode,
  splitFromRow,
  mergeIntoRow,
  returnToRow,
  splitFromPageView,
  mergeIntoPageView,
}

enum DropTargetKind {
  none,
  insertBetweenNodes,
  mergeIntoRow,
  mergeIntoPageView,
  mergeMentions,
}

class DropTarget {
  const DropTarget._(
    this.kind, {
    this.insertIndex,
    this.targetRowId,
    this.targetNodeId,
    this.isFromLeft,
  });

  const DropTarget.none() : this._(DropTargetKind.none);

  const DropTarget.insertBetweenNodes(int index)
    : this._(DropTargetKind.insertBetweenNodes, insertIndex: index);

  const DropTarget.mergeIntoRow({
    required String rowId,
    required bool isFromLeft,
    String? targetNodeId,
  }) : this._(
         DropTargetKind.mergeIntoRow,
         targetRowId: rowId,
         targetNodeId: targetNodeId ?? rowId,
         isFromLeft: isFromLeft,
       );

  const DropTarget.mergeIntoPageView({
    required String pageViewId,
    required int insertIndex,
    String? targetNodeId,
  }) : this._(
         DropTargetKind.mergeIntoPageView,
         targetRowId: pageViewId,
         targetNodeId: targetNodeId ?? pageViewId,
         insertIndex: insertIndex,
       );

  const DropTarget.mergeMentions({
    required String mentionId,
    required int insertIndex,
  }) : this._(
         DropTargetKind.mergeMentions,
         targetNodeId: mentionId,
         insertIndex: insertIndex,
       );

  final DropTargetKind kind;
  final int? insertIndex;
  final String? targetRowId;
  final String? targetNodeId;
  final bool? isFromLeft;
}

// ==========================================
// 드래그 상태 관리
// ==========================================

/// 드래그 세션의 상태를 관리하는 클래스
class _DragState {
  // 기본 드래그 정보
  String? draggingNodeId;
  NodeType? draggingNodeType;
  String? targetNodeId;
  NodeType? targetNodeType;
  DragType dragMode = DragType.none;

  // 위치 정보
  Offset? dragPosition;
  Offset? lastMovedPosition;
  Offset? dragStartPosition;
  int? dropIndex;

  // 드래그 세션 정보
  DragSubjectKind subjectKind = DragSubjectKind.node;
  String? subjectNodeId;
  String? subjectRowId;
  int? subjectRowImageIndex;
  // split 대상 고정용 (인덱스 변동/비동기 업데이트에도 안전)
  String? subjectRowImageUrl;
  String? subjectPageViewId;
  int? subjectPageViewImageIndex;
  // split 대상 고정용 (인덱스 변동/비동기 업데이트에도 안전)
  String? subjectPageViewImageUrl;
  DragIntent intent = DragIntent.none;
  DropTarget dropTarget = const DropTarget.none();

  // 프리뷰 이미지
  String? previewImageUrl;
  String? previewImageLocalPath;
  String? mentionProfileImageUrl;

  // 분리 정보
  String? splitImageRowId;
  int? splitImageIndex;
  String? splitPageViewId;
  int? splitPageViewIndex;

  // 타겟 정보
  String? targetRowId;
  String? targetPageViewId;
  int? targetPageViewInsertIndex;

  // PageView 현재 페이지 캐시
  final Map<String, int> pageViewCurrentPageById = {};

  bool get hasSplitImageInfo =>
      splitImageRowId != null && splitImageIndex != null;

  bool get hasSplitPageViewInfo =>
      splitPageViewId != null && splitPageViewIndex != null;

  bool get isRowItemDrag =>
      subjectKind == DragSubjectKind.rowItem &&
      subjectRowId != null &&
      subjectRowImageIndex != null;

  bool get isPageViewItemDrag =>
      subjectKind == DragSubjectKind.pageViewItem &&
      subjectPageViewId != null &&
      subjectPageViewImageIndex != null;

  bool get hasDraggedSignificantly {
    if (dragPosition == null || dragStartPosition == null) return false;
    return (dragPosition! - dragStartPosition!).distance >
        EditorDragConfig.dragSignificantDistancePx;
  }

  void reset() {
    draggingNodeId = null;
    draggingNodeType = null;
    targetNodeId = null;
    targetNodeType = null;
    dragMode = DragType.none;
    dragPosition = null;
    lastMovedPosition = null;
    dragStartPosition = null;
    dropIndex = null;

    subjectKind = DragSubjectKind.node;
    subjectNodeId = null;
    subjectRowId = null;
    subjectRowImageIndex = null;
    subjectRowImageUrl = null;
    subjectPageViewId = null;
    subjectPageViewImageIndex = null;
    subjectPageViewImageUrl = null;
    intent = DragIntent.none;
    dropTarget = const DropTarget.none();

    previewImageUrl = null;
    previewImageLocalPath = null;
    mentionProfileImageUrl = null;

    splitImageRowId = null;
    splitImageIndex = null;
    splitPageViewId = null;
    splitPageViewIndex = null;

    targetRowId = null;
    targetPageViewId = null;
    targetPageViewInsertIndex = null;
  }
}

// ==========================================
// 좌표 변환 및 계산 헬퍼
// ==========================================

/// 좌표 변환 및 노드 위치 계산을 담당하는 헬퍼 클래스
class _DragCoordinateHelper {
  final EditorService editorService;
  final Map<String, Rect> _nodeRectCache = {};

  _DragCoordinateHelper(this.editorService);

  void invalidateCache() => _nodeRectCache.clear();

  Rect? getNodeGlobalRect(String nodeId) {
    try {
      final cached = _nodeRectCache[nodeId];
      if (cached != null) return cached;

      final layout =
          editorService.documentLayoutKey?.currentState as DocumentLayout?;
      if (layout == null) return null;

      final component = layout.getComponentByNodeId(nodeId);
      if (component == null) return null;

      final ro = component.context.findRenderObject();
      RenderBox? box;
      if (ro is RenderSliverToBoxAdapter) {
        box = ro.child;
      } else if (ro is RenderBox) {
        box = ro;
      }
      if (box == null) return null;

      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      _nodeRectCache[nodeId] = rect;
      return rect;
    } catch (_) {
      return null;
    }
  }

  Offset? globalToDocumentLocal(Offset global) {
    try {
      final ro = editorService.documentLayoutKey?.currentContext
          ?.findRenderObject();
      RenderBox? renderBox;
      if (ro is RenderSliverToBoxAdapter) {
        renderBox = ro.child;
      } else if (ro is RenderBox) {
        renderBox = ro;
      }
      if (renderBox == null) return null;
      return renderBox.globalToLocal(global);
    } catch (_) {
      return null;
    }
  }

  /// 세로 노드 사이 클릭 감지
  int? detectVerticalGapAt(Offset globalPos, {double pad = 30.0}) {
    final layout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (layout == null) return null;

    final local = globalToDocumentLocal(globalPos);
    if (local == null) return null;

    DocumentPosition? nearest;
    try {
      nearest = layout.getDocumentPositionNearestToOffset(local);
    } catch (_) {
      return null;
    }
    if (nearest == null) return null;

    final doc = editorService.document;
    final idx = doc.getNodeIndexById(nearest.nodeId);
    if (idx < 0) return null;

    bool isGapBetween(int aIndex, int bIndex) {
      final a = doc.getNodeAt(aIndex);
      final b = doc.getNodeAt(bIndex);
      if (a == null || b == null) return false;
      final ra = getNodeGlobalRect(a.id);
      final rb = getNodeGlobalRect(b.id);
      if (ra == null || rb == null) return false;
      final y = globalPos.dy;
      return (y >= ra.bottom - pad && y <= rb.top + pad);
    }

    if (idx + 1 < doc.nodeCount && isGapBetween(idx, idx + 1)) {
      return idx + 1;
    }
    if (idx - 1 >= 0 && isGapBetween(idx - 1, idx)) {
      return idx;
    }
    return null;
  }

  /// 드래그 방향 계산 (왼쪽에서 오는지 오른쪽에서 오는지)
  bool isDraggingFromLeft(Offset dragPosition, String? targetNodeId) {
    if (targetNodeId == null) return true;

    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return true;

    final component = documentLayout.getComponentByNodeId(targetNodeId);
    if (component == null) return true;

    final renderBox = component.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return true;

    final targetCenter =
        renderBox.localToGlobal(Offset.zero) +
        Offset(renderBox.size.width / 2, renderBox.size.height / 2);

    return dragPosition.dx < targetCenter.dx;
  }
}

// ==========================================
// 이미지 URL 추출 헬퍼
// ==========================================

/// 드래그 오버레이에 표시할 이미지 URL을 추출하는 헬퍼 클래스
class _DragImageExtractor {
  final EditorService editorService;
  final _DragState state;

  _DragImageExtractor(this.editorService, this.state);

  void extractImageUrl(String nodeId) {
    try {
      final node = editorService.document.getNodeById(nodeId);
      if (node == null) {
        _clearPreview();
        return;
      }

      _clearPreview();

      if (node is ImageNode) {
        _extractFromImageNode(node);
      } else if (node is ClipNode) {
        _extractFromClipNode(node);
      } else if (node is ImageRowNode) {
        _extractFromImageRowNode(node);
      } else if (node is PageViewImageNode) {
        _extractFromPageViewImageNode(node);
      } else if (node is LinkNode) {
        state.previewImageUrl = node.thumbnailUrl;
      }
    } catch (_) {
      _clearPreview();
    }
  }

  void _clearPreview() {
    state.previewImageUrl = null;
    state.previewImageLocalPath = null;
  }

  void _extractFromImageNode(ImageNode node) {
    final imageUrl = node.imageUrl;
    if (imageUrl.isNotEmpty && !EditorService.isNetworkUrl(imageUrl)) {
      state.previewImageLocalPath = imageUrl;
    } else {
      state.previewImageUrl = imageUrl;
    }
  }

  void _extractFromClipNode(ClipNode node) {
    if (node.thumbnailPath.isNotEmpty) {
      state.previewImageLocalPath = node.thumbnailPath;
    } else if (node.localPath.isNotEmpty) {
      state.previewImageLocalPath = node.localPath;
    } else {
      final meta = node.metadata;
      if (meta['thumbnailUrl'] != null) {
        state.previewImageUrl = meta['thumbnailUrl'].toString();
      }
    }
  }

  void _extractFromImageRowNode(ImageRowNode node) {
    if (node.imageUrls.isNotEmpty) {
      final firstUrl = node.imageUrls.first;
      if (firstUrl.isNotEmpty && !EditorService.isNetworkUrl(firstUrl)) {
        state.previewImageLocalPath = firstUrl;
      } else {
        state.previewImageUrl = firstUrl;
      }
    }
  }

  void _extractFromPageViewImageNode(PageViewImageNode node) {
    if (node.imageUrls.isNotEmpty) {
      String targetUrl;
      if (state.isPageViewItemDrag &&
          state.subjectPageViewImageIndex != null &&
          state.subjectPageViewImageIndex! >= 0 &&
          state.subjectPageViewImageIndex! < node.imageUrls.length) {
        targetUrl = node.imageUrls[state.subjectPageViewImageIndex!];
      } else {
        targetUrl = node.imageUrls.first;
      }
      if (targetUrl.isNotEmpty && !EditorService.isNetworkUrl(targetUrl)) {
        state.previewImageLocalPath = targetUrl;
      } else {
        state.previewImageUrl = targetUrl;
      }
    }
  }
}

// ==========================================
// 자동 스크롤 컨트롤러
// ==========================================

/// 드래그 중 가장자리에서 자동 스크롤을 처리하는 클래스
class _AutoScrollController {
  ScrollController? scrollController;
  final EditorService editorService;
  final _DragCoordinateHelper coordinateHelper;

  Timer? _timer;
  double _direction = 0.0;

  _AutoScrollController({
    required this.scrollController,
    required this.editorService,
    required this.coordinateHelper,
  });

  void maybeAutoScroll(Offset? dragPosition) {
    if (scrollController == null || dragPosition == null) return;
    if (!scrollController!.hasClients) return;

    final bounds = _getViewportBounds();
    if (bounds == null) return;

    const edgeMargin = 72.0;
    double direction = 0.0;

    if (dragPosition.dy < bounds.top + edgeMargin) {
      direction = -1.0; // 위로 스크롤
    } else if (dragPosition.dy > bounds.bottom - edgeMargin) {
      direction = 1.0; // 아래로 스크롤
    }

    if (direction == 0.0) {
      _direction = 0.0;
      stop();
      return;
    }

    _direction = direction;
    _startTimer(edgeMargin, dragPosition);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer(double edgeMargin, Offset dragPosition) {
    if (_timer != null) return;

    const interval = Duration(milliseconds: 16); // ~60 FPS
    _timer = Timer.periodic(interval, (_) {
      if (scrollController == null) {
        stop();
        return;
      }
      if (!scrollController!.hasClients) {
        stop();
        return;
      }

      final bounds = _getViewportBounds();
      if (bounds == null) {
        stop();
        return;
      }

      final max = scrollController!.position.maxScrollExtent;
      final min = scrollController!.position.minScrollExtent;
      final current = scrollController!.offset;

      final distanceToEdge = _direction < 0
          ? (dragPosition.dy - bounds.top).clamp(0.0, edgeMargin)
          : (bounds.bottom - dragPosition.dy).clamp(0.0, edgeMargin);
      final proximity = (edgeMargin - distanceToEdge) / edgeMargin;
      const maxSpeed = 900.0; // px/s
      const minSpeed = 240.0; // px/s
      final speed = minSpeed + (maxSpeed - minSpeed) * proximity;
      final delta = speed * (interval.inMilliseconds / 1000.0) * _direction;

      final next = (current + delta).clamp(min, max);
      if (next == current) {
        stop();
        return;
      }

      scrollController!.jumpTo(next);
    });
  }

  Rect? _getViewportBounds() {
    try {
      final position = scrollController?.position;
      final ctx =
          position?.context.notificationContext ??
          position?.context.storageContext;
      if (ctx == null) return null;
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) return null;
      final topLeft = renderBox.localToGlobal(Offset.zero);
      return topLeft & renderBox.size;
    } catch (_) {
      return null;
    }
  }
}

// ==========================================
// 드롭 타겟 계산기 (가장 복잡한 부분)
// ==========================================

/// 드롭 타겟을 계산하는 복잡한 로직을 담당하는 클래스
class _DropTargetCalculator {
  final EditorService editorService;
  final _DragState state;
  final _DragCoordinateHelper coordinateHelper;
  final bool Function(String) isBusyRef;

  _DropTargetCalculator({
    required this.editorService,
    required this.state,
    required this.coordinateHelper,
    required this.isBusyRef,
  });

  Map<String, dynamic>? computeDropInfo(Offset globalPosition) {
    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return null;

    final localPosition = _convertToLocalPosition(globalPosition);
    if (localPosition == null) return null;

    final documentLength = editorService.document.length;
    if (documentLength == 0) {
      return _handleEmptyDocument();
    }

    final position = _getDocumentPosition(documentLayout, localPosition);
    if (position == null) return null;

    final doc = editorService.document;
    final initialNode = doc.getNodeById(position.nodeId);
    if (initialNode == null) return null;

    var node = initialNode;
    var nodeIndex = doc.getNodeIndexById(node.id);
    if (nodeIndex == -1) return null;

    var resolvedPosition = position;

    // 타겟 보정: 이미지 드래그 시 이웃 이미지 노드를 우선적으로 타겟으로 잡는다
    final corrected = _correctTargetForImageDrag(
      node,
      nodeIndex,
      resolvedPosition,
      globalPosition,
      doc,
    );
    if (corrected != null) {
      node = corrected['node'] as DocumentNode;
      nodeIndex = corrected['nodeIndex'] as int;
      resolvedPosition = corrected['position'] as DocumentPosition;
    }

    // 타겟 노드 정보 업데이트
    final targetNodeType = editorService.getNodeType(node.id);
    state.targetNodeId = node.id;
    state.targetNodeType = targetNodeType;

    // 드래그 모드 결정
    state.dragMode = _determineDragMode(
      targetNodeType,
      state.draggingNodeType,
      resolvedPosition,
      localPosition,
      documentLayout,
    );

    // 이미지 행 타겟에 대한 삽입 인덱스 계산
    if (targetNodeType == NodeType.imageRow) {
      state.targetRowId = node.id;
    } else {
      state.targetRowId = null;
    }

    // PageView 타겟에 대한 삽입 인덱스 계산
    if (targetNodeType == NodeType.pageViewImage &&
        state.dragMode == DragType.imagePageViewMerge) {
      state.targetPageViewId = node.id;
      try {
        final pageViewNode = node as PageViewImageNode;
        final Rect? targetRect = documentLayout.getRectForPosition(
          resolvedPosition,
        );
        if (targetRect != null) {
          final double localXWithinTarget = localPosition.dx - targetRect.left;
          final int imageCount = pageViewNode.imageUrls.length;
          if (imageCount > 0) {
            final int currentPage =
                (state.pageViewCurrentPageById[node.id] ?? 0).clamp(
                  0,
                  imageCount - 1,
                );
            final bool isLeftHalf = localXWithinTarget < (targetRect.width / 2);
            final int insertIdx = (isLeftHalf ? currentPage : (currentPage + 1))
                .clamp(0, imageCount);
            state.targetPageViewInsertIndex = insertIdx;
          } else {
            state.targetPageViewInsertIndex = 0;
          }
        }
      } catch (_) {
        state.targetPageViewInsertIndex = null;
      }
    } else {
      state.targetPageViewId = null;
      state.targetPageViewInsertIndex = null;
    }

    // 드롭 인덱스 계산
    final dropIndex = _calculateDropIndex(
      node,
      nodeIndex,
      resolvedPosition,
      localPosition,
      documentLayout,
      documentLength,
    );

    // dropTarget 설정
    _updateDropTarget(node, dropIndex);

    return {'dropIndex': dropIndex};
  }

  Offset? _convertToLocalPosition(Offset globalPosition) {
    final renderObject = editorService.documentLayoutKey?.currentContext
        ?.findRenderObject();
    if (renderObject == null) return null;

    RenderBox? renderBox;
    if (renderObject is RenderSliverToBoxAdapter) {
      renderBox = renderObject.child;
    } else if (renderObject is RenderBox) {
      renderBox = renderObject;
    }
    if (renderBox == null) return null;

    try {
      var localPosition = renderBox.globalToLocal(globalPosition);
      if (!localPosition.dx.isFinite || !localPosition.dy.isFinite) {
        return null;
      }

      final documentSize = renderBox.size;
      if (localPosition.dx < 0 ||
          localPosition.dx > documentSize.width ||
          localPosition.dy < 0 ||
          localPosition.dy > documentSize.height) {
        localPosition = Offset(
          localPosition.dx.clamp(0, documentSize.width),
          localPosition.dy.clamp(0, documentSize.height),
        );
      }
      return localPosition;
    } catch (_) {
      return null;
    }
  }

  DocumentPosition? _getDocumentPosition(
    DocumentLayout layout,
    Offset localPosition,
  ) {
    try {
      return layout.getDocumentPositionNearestToOffset(localPosition);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _handleEmptyDocument() {
    state.dropTarget = const DropTarget.insertBetweenNodes(0);
    state.intent = DragIntent.reorderNode;
    state.dropIndex = 0;
    return {'dropIndex': 0};
  }

  Map<String, dynamic>? _correctTargetForImageDrag(
    DocumentNode node,
    int nodeIndex,
    DocumentPosition position,
    Offset globalPosition,
    MutableDocument doc,
  ) {
    if (state.draggingNodeType != NodeType.image) return null;

    // 이웃 노드 체크
    final neighborIds = <String?>[
      node.id,
      if (nodeIndex - 1 >= 0) doc.getNodeAt(nodeIndex - 1)?.id,
      if (nodeIndex + 1 < doc.length) doc.getNodeAt(nodeIndex + 1)?.id,
    ];

    for (final id in neighborIds) {
      if (id == null || id == state.draggingNodeId) continue;
      final n = doc.getNodeById(id);
      if (n == null) continue;

      final nType = editorService.getNodeType(id);
      if (nType != NodeType.image && nType != NodeType.imageRow) continue;

      final r = coordinateHelper.getNodeGlobalRect(id);
      if (r != null && r.contains(globalPosition)) {
        return {
          'node': n,
          'nodeIndex': doc.getNodeIndexById(id),
          'position': DocumentPosition(
            nodeId: id,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          ),
        };
      }
    }

    // 윈도우 스캔 (주변 인덱스 범위 훑기)
    final currentType = editorService.getNodeType(node.id);
    final targetIsImageLike =
        currentType == NodeType.image || currentType == NodeType.imageRow;
    if (!targetIsImageLike && doc.length > 0) {
      final start = (nodeIndex - 6).clamp(0, doc.length - 1);
      final end = (nodeIndex + 6).clamp(0, doc.length - 1);

      String? bestId;
      double bestDist2 = double.infinity;

      for (int i = start; i <= end; i++) {
        final candidate = doc.getNodeAt(i);
        if (candidate == null) continue;
        final cid = candidate.id;
        if (cid == state.draggingNodeId) continue;

        final ct = editorService.getNodeType(cid);
        if (ct != NodeType.image && ct != NodeType.imageRow) continue;

        final r = coordinateHelper.getNodeGlobalRect(cid);
        if (r == null) continue;

        final inflated = r.inflate(16);
        if (!inflated.contains(globalPosition)) continue;

        final delta = inflated.center - globalPosition;
        final d2 = (delta.dx * delta.dx) + (delta.dy * delta.dy);
        if (d2 < bestDist2) {
          bestDist2 = d2;
          bestId = cid;
        }
      }

      if (bestId != null) {
        final n = doc.getNodeById(bestId);
        if (n != null) {
          return {
            'node': n,
            'nodeIndex': doc.getNodeIndexById(bestId),
            'position': DocumentPosition(
              nodeId: bestId,
              nodePosition: const UpstreamDownstreamNodePosition.downstream(),
            ),
          };
        }
      }
    }

    return null;
  }

  DragType _determineDragMode(
    NodeType targetNodeType,
    NodeType? draggingNodeType,
    DocumentPosition resolvedPosition,
    Offset localPosition,
    DocumentLayout documentLayout,
  ) {
    final isTargetBusy =
        state.targetNodeId != null && isBusyRef(state.targetNodeId!);

    // PageView 병합 모드 체크 (싱글 / PageView 한 장 / Row 한 장 → PageView에 넣기)
    if (targetNodeType == NodeType.pageViewImage &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.pageViewImage ||
            draggingNodeType == NodeType.imageRow)) {
      return _checkPageViewMergeMode(
        resolvedPosition,
        localPosition,
        documentLayout,
        isTargetBusy,
      );
    }

    // Image/Row 병합 모드 체크 (싱글/Row 위에 드롭 시 가로 병합)
    // 🎯 PageView에서 한 장 뺀 드래그(hasSplitPageViewInfo)도 "이미지 하나"로 간주해 Row/싱글에 병합 허용
    final isDraggingOneImage =
        draggingNodeType == NodeType.image ||
        draggingNodeType == NodeType.imageRow ||
        (state.hasSplitPageViewInfo && draggingNodeType == NodeType.pageViewImage);
    if ((targetNodeType == NodeType.image ||
            targetNodeType == NodeType.imageRow) &&
        isDraggingOneImage) {
      return _checkImageRowMergeMode(
        targetNodeType,
        resolvedPosition,
        localPosition,
        documentLayout,
        isTargetBusy,
      );
    }

    return DragType.reorder;
  }

  DragType _checkPageViewMergeMode(
    DocumentPosition resolvedPosition,
    Offset localPosition,
    DocumentLayout documentLayout,
    bool isTargetBusy,
  ) {
    final sameId = state.draggingNodeId == state.targetNodeId;
    // 🎯 같은 노드 위에서 한 장 드래그 또는 Row에서 한 장 / PageView에서 한 장 → PageView에 병합 허용
    final allowMergeCandidate =
        !sameId ||
        state.isPageViewItemDrag ||
        state.isRowItemDrag;

    if (!allowMergeCandidate || isTargetBusy) {
      return DragType.reorder;
    }

    final targetRect = documentLayout.getRectForPosition(resolvedPosition);
    if (targetRect == null) return DragType.reorder;

    final localXWithinTarget = localPosition.dx - targetRect.left;
    final localYWithinTarget = localPosition.dy - targetRect.top;
    final w = targetRect.width;
    final h = targetRect.height;

    final verticalInset = (h * EditorDragConfig.pageViewMergeVerticalInsetRatio)
        .clamp(
          EditorDragConfig.pageViewMergeVerticalInsetMinPx,
          EditorDragConfig.pageViewMergeVerticalInsetMaxPx,
        );
    final inVerticalSafeBand =
        localYWithinTarget > verticalInset &&
        localYWithinTarget < (h - verticalInset);

    final deadZone = (w * EditorDragConfig.pageViewMergeCenterDeadZoneRatio)
        .clamp(
          EditorDragConfig.pageViewMergeCenterDeadZoneMinPx,
          EditorDragConfig.pageViewMergeCenterDeadZoneMaxPx,
        );
    final midX = w / 2;
    final isClearlyLeft = localXWithinTarget < (midX - deadZone);
    final isClearlyRight = localXWithinTarget > (midX + deadZone);

    final shouldEnablePageViewMerge =
        inVerticalSafeBand && (isClearlyLeft || isClearlyRight);

    // 🎯 같은 PageView 안에서 한 장 드래그 시: 같은 PageView 위에 있으면 merge(삽입) 모드 허용
    // Row에서 한 장 드래그 시: 다른 노드(PageView) 위에서는 merge 허용
    final isOverSamePageView = state.hasSplitPageViewInfo &&
        state.targetNodeId == state.splitPageViewId;
    if (state.hasSplitPageViewInfo && !isOverSamePageView) {
      return DragType.reorder; // PageView 한 장 드래그인데 다른 노드 위 → reorder만
    }
    if (!shouldEnablePageViewMerge) {
      return DragType.reorder;
    }

    return DragType.imagePageViewMerge;
  }

  DragType _checkImageRowMergeMode(
    NodeType targetNodeType,
    DocumentPosition resolvedPosition,
    Offset localPosition,
    DocumentLayout documentLayout,
    bool isTargetBusy,
  ) {
    final sameId = state.draggingNodeId == state.targetNodeId;
    // 🎯 Row 아이템 드래그 또는 PageView에서 한 장 뺀 드래그도 "한 장"으로 취급해 병합 허용
    final allowMergeCandidate =
        !sameId || state.isRowItemDrag || state.isPageViewItemDrag;

    if (!allowMergeCandidate || isTargetBusy) {
      return DragType.reorder;
    }

    const horizontalMergeEdgePx = 50.0;
    final targetRect = documentLayout.getRectForPosition(resolvedPosition);

    bool nearHorizontalEdge = false;
    if (targetRect != null) {
      final leftEdge = targetRect.left + horizontalMergeEdgePx;
      final rightEdge = targetRect.right - horizontalMergeEdgePx;
      nearHorizontalEdge =
          localPosition.dx <= leftEdge || localPosition.dx >= rightEdge;
    } else {
      if (targetNodeType == NodeType.image ||
          targetNodeType == NodeType.imageRow) {
        nearHorizontalEdge = true;
      }
    }

    if (nearHorizontalEdge && !isTargetBusy) {
      return DragType.imageRowMerge;
    }

    return DragType.reorder;
  }

  int? _calculateDropIndex(
    DocumentNode node,
    int nodeIndex,
    DocumentPosition resolvedPosition,
    Offset localPosition,
    DocumentLayout documentLayout,
    int documentLength,
  ) {
    final targetRect = documentLayout.getRectForPosition(resolvedPosition);
    int? finalCandidate;

    if (targetRect == null) {
      finalCandidate = nodeIndex;
    } else {
      finalCandidate = (localPosition.dy <= targetRect.center.dy)
          ? nodeIndex
          : (nodeIndex + 1);
    }

    // 병합 모드일 때는 dropIndex를 null로 설정 (Row/싱글 병합 시 삽입선 대신 병합 타깃 표시)
    if (state.dragMode == DragType.imageRowMerge) {
      finalCandidate = null;
    }
    if (state.dragMode == DragType.imagePageViewMerge &&
        !state.hasSplitPageViewInfo) {
      finalCandidate = null;
    }

    // 분리 취소 감지
    if (targetRect != null) {
      finalCandidate = _checkSplitCancel(
        finalCandidate,
        targetRect,
        localPosition,
      );
    }

    // 빈 문단 자동 삭제를 고려한 조정
    if (finalCandidate != null) {
      finalCandidate = _adjustForEmptyParagraphs(
        finalCandidate,
        documentLength,
      );
    }

    return finalCandidate;
  }

  int? _checkSplitCancel(
    int? candidate,
    Rect targetRect,
    Offset localPosition,
  ) {
    if (candidate == null) return candidate;

    final localY = localPosition.dy - targetRect.top;
    final edgeY = (targetRect.height * EditorDragConfig.splitCancelEdgeYRatio)
        .clamp(
          EditorDragConfig.splitCancelEdgeYMinPx,
          EditorDragConfig.splitCancelEdgeYMaxPx,
        );
    final inCenter = localY > edgeY && localY < (targetRect.height - edgeY);

    if (state.hasSplitImageInfo &&
        state.targetNodeId == state.splitImageRowId &&
        inCenter) {
      return null;
    }

    if (state.hasSplitPageViewInfo &&
        state.targetNodeId == state.splitPageViewId &&
        inCenter) {
      return null;
    }

    return candidate;
  }

  int _adjustForEmptyParagraphs(int candidateIndex, int documentLength) {
    if (candidateIndex < 0 || candidateIndex > documentLength) {
      return candidateIndex;
    }

    final doc = editorService.document;

    if (candidateIndex > 0) {
      final prevNode = doc.getNodeAt(candidateIndex - 1);
      if (prevNode != null && NodeTypeChecker.isEmptyParagraph(prevNode)) {
        // 제목 노드(isTitle) 바로 아래는 축소하지 않음 → 제목 밑으로 드롭 가능하게
        if (prevNode is ParagraphNode &&
            prevNode.metadata[EditorConfig.titleNodeMetadataKey] == true) {
          return candidateIndex;
        }
        return candidateIndex - 1;
      }
    }

    return candidateIndex;
  }

  void _updateDropTarget(DocumentNode node, int? dropIndex) {
    if (state.dragMode == DragType.imageRowMerge) {
      if (state.targetNodeId != null && isBusyRef(state.targetNodeId!)) {
        state.dragMode = DragType.reorder;
        return;
      }

      final isFromLeft = coordinateHelper.isDraggingFromLeft(
        state.dragPosition!,
        state.targetNodeId,
      );
      state.dropTarget = DropTarget.mergeIntoRow(
        rowId: node.id,
        isFromLeft: isFromLeft,
        targetNodeId: node.id,
      );
      state.intent = DragIntent.mergeIntoRow;
      state.dropIndex = null;
      return;
    }

    if (state.dragMode == DragType.imagePageViewMerge) {
      if (state.targetNodeId != null && isBusyRef(state.targetNodeId!)) {
        state.dragMode = DragType.reorder;
        return;
      }

      final insertIdx = state.targetPageViewInsertIndex ?? 0;
      state.dropTarget = DropTarget.mergeIntoPageView(
        pageViewId: node.id,
        insertIndex: insertIdx,
        targetNodeId: node.id,
      );
      state.intent = DragIntent.mergeIntoPageView;
      state.dropIndex = null;
      return;
    }

    if (dropIndex != null) {
      final validDropIndex = dropIndex.clamp(0, editorService.document.length);

      // 멘션 노드 병합은 EditorService에서 처리
      state.dropTarget = DropTarget.insertBetweenNodes(validDropIndex);
      state.intent = DragIntent.reorderNode;
      state.dropIndex = validDropIndex;
    } else {
      state.dropTarget = const DropTarget.none();
      state.dropIndex = null;
    }
  }
}

// ==========================================
// 메인 DragService
// ==========================================

/// 드래그 앤 드롭 기능을 관리하는 서비스
class DragService extends ChangeNotifier {
  final EditorService editorService;

  /// 네트워크 업로드/업로드 상태 추적을 사용할지 여부.
  /// - false이면 UploadService busy 상태를 무시하고 드래그/드롭을 항상 활성화한다.
  final bool networkMode;
  final _DragState _state = _DragState();

  NodeComponentService? _imageService;
  ScrollController? _scrollController;
  IUploadService? _uploadService;

  DragService({
    required this.editorService,
    NodeComponentService? imageService,
    ScrollController? scrollController,
    bool? networkMode,
  }) : _imageService = imageService,
       _scrollController = scrollController,
       networkMode = networkMode ?? editorService.networkMode {
    _coordinateHelper = _DragCoordinateHelper(editorService);
    _imageExtractor = _DragImageExtractor(editorService, _state);
    _autoScrollController = _AutoScrollController(
      scrollController: scrollController,
      editorService: editorService,
      coordinateHelper: _coordinateHelper,
    );
    _dropTargetCalculator = _DropTargetCalculator(
      editorService: editorService,
      state: _state,
      coordinateHelper: _coordinateHelper,
      isBusyRef: _isBusyRef,
    );
  }

  late final _DragCoordinateHelper _coordinateHelper;
  late final _DragImageExtractor _imageExtractor;
  late final _AutoScrollController _autoScrollController;
  late final _DropTargetCalculator _dropTargetCalculator;

  // ==========================================
  // Public API
  // ==========================================

  bool get isDragging => _state.draggingNodeId != null;
  bool get hasDraggedSignificantly => _state.hasDraggedSignificantly;
  bool get hasSplitImageInfo => _state.hasSplitImageInfo;
  bool get hasSplitPageViewInfo => _state.hasSplitPageViewInfo;
  bool get isRowItemDrag => _state.isRowItemDrag;
  bool get isPageViewItemDrag => _state.isPageViewItemDrag;

  String? get draggingNodeId => _state.draggingNodeId;
  final ValueNotifier<String?> draggingNodeIdNotifier = ValueNotifier<String?>(
    null,
  );
  NodeType? get draggingNodeType => _state.draggingNodeType;
  String? get targetNodeId => _state.targetNodeId;
  NodeType? get targetNodeType => _state.targetNodeType;
  DragType get dragMode => _state.dragMode;
  Offset? get dragPosition => _state.dragPosition;
  int? get dropIndex => _state.dropIndex;
  DropTarget get dropTarget => _state.dropTarget;
  DragIntent get intent => _state.intent;
  String? get previewImageUrl => _state.previewImageUrl;
  String? get previewImageLocalPath => _state.previewImageLocalPath;
  String? get subjectPageViewId => _state.subjectPageViewId;
  int? get subjectPageViewImageIndex => _state.subjectPageViewImageIndex;

  NodeComponentService? get imageService => _imageService;
  ScrollController? get scrollController => _scrollController;

  bool isBusyRef(String refId) {
    if (_uploadService == null) return false;
    return _uploadService!.isBusyRef(refId);
  }

  void setImageService(NodeComponentService imageService) {
    _imageService = imageService;
  }

  void attachScrollController(ScrollController controller) {
    _scrollController = controller;
    _autoScrollController.scrollController = controller;
  }

  void setPageViewCurrentPage(String pageViewId, int pageIndex) {
    _state.pageViewCurrentPageById[pageViewId] = pageIndex;

    // 🎯 같은 PageView 안에서 엣지 자동 스크롤 시 삽입 인덱스·드롭 타겟 갱신
    // (손가락은 그대로인데 페이지만 바뀌어도 dropTarget.insertIndex가 반영되도록)
    if (_state.dragMode == DragType.imagePageViewMerge &&
        _state.targetPageViewId == pageViewId &&
        _state.dragPosition != null) {
      final rect = getNodeGlobalRect(pageViewId);
      if (rect != null && rect.width > 0) {
        final doc = editorService.document;
        final node = doc.getNodeById(pageViewId);
        if (node is PageViewImageNode) {
          final imageCount = node.imageUrls.length;
          if (imageCount > 0) {
            final localX = _state.dragPosition!.dx - rect.left;
            final isLeftHalf = localX < (rect.width / 2);
            final insertIdx =
                (isLeftHalf ? pageIndex : pageIndex + 1).clamp(0, imageCount);
            _state.targetPageViewInsertIndex = insertIdx;
            _state.dropTarget = DropTarget.mergeIntoPageView(
              pageViewId: pageViewId,
              insertIndex: insertIdx,
              targetNodeId: pageViewId,
            );
            notifyListeners();
          }
        }
      }
    }
  }

  int? getPageViewCurrentPage(String pageViewId) {
    return _state.pageViewCurrentPageById[pageViewId];
  }

  void invalidateNodeRectCache() => _coordinateHelper.invalidateCache();

  Rect? getNodeGlobalRect(String nodeId) =>
      _coordinateHelper.getNodeGlobalRect(nodeId);

  Offset? globalToDocumentLocal(Offset global) =>
      _coordinateHelper.globalToDocumentLocal(global);

  int? detectVerticalGapAt(Offset globalPos, {double pad = 30.0}) =>
      _coordinateHelper.detectVerticalGapAt(globalPos, pad: pad);

  int getNodeIndex(String nodeId) =>
      editorService.document.getNodeIndexById(nodeId);

  bool get isDraggingFromLeft {
    if (_state.dragPosition == null || _state.targetNodeId == null) {
      return true;
    }
    return _coordinateHelper.isDraggingFromLeft(
      _state.dragPosition!,
      _state.targetNodeId,
    );
  }

  // ==========================================
  // Split Info Management
  // ==========================================

  void setSplitImageInfo(String rowId, int imageIndex) {
    _state.splitImageRowId = rowId;
    _state.splitImageIndex = imageIndex;
    _state.subjectKind = DragSubjectKind.rowItem;
    _state.subjectNodeId = null;
    _state.subjectRowId = rowId;
    _state.subjectRowImageIndex = imageIndex;
    // split 대상 URL을 고정해둔다 (인덱스가 변해도 안전하게 제거/병합 가능)
    try {
      final node = editorService.document.getNodeById(rowId);
      if (node is ImageRowNode &&
          imageIndex >= 0 &&
          imageIndex < node.imageUrls.length) {
        _state.subjectRowImageUrl = node.imageUrls[imageIndex];
      } else {
        _state.subjectRowImageUrl = null;
      }
    } catch (_) {
      _state.subjectRowImageUrl = null;
    }
    _state.intent = DragIntent.splitFromRow;
  }

  Map<String, dynamic>? getSplitImageInfo() {
    if (_state.splitImageRowId != null && _state.splitImageIndex != null) {
      return {
        'rowId': _state.splitImageRowId,
        'imageIndex': _state.splitImageIndex,
      };
    }
    return null;
  }

  void setSplitPageViewInfo(String pageViewId, int imageIndex) {
    _state.splitPageViewId = pageViewId;
    _state.splitPageViewIndex = imageIndex;
    _state.subjectKind = DragSubjectKind.pageViewItem;
    _state.subjectNodeId = null;
    _state.subjectPageViewId = pageViewId;
    _state.subjectPageViewImageIndex = imageIndex;
    // split 대상 URL을 고정해둔다 (인덱스가 변해도 안전하게 제거/병합 가능)
    try {
      final node = editorService.document.getNodeById(pageViewId);
      if (node is PageViewImageNode &&
          imageIndex >= 0 &&
          imageIndex < node.imageUrls.length) {
        _state.subjectPageViewImageUrl = node.imageUrls[imageIndex];
      } else {
        _state.subjectPageViewImageUrl = null;
      }
    } catch (_) {
      _state.subjectPageViewImageUrl = null;
    }
    _state.intent = DragIntent.splitFromPageView;
    _imageExtractor.extractImageUrl(pageViewId);
  }

  Map<String, dynamic>? getSplitPageViewInfo() {
    if (_state.splitPageViewId != null && _state.splitPageViewIndex != null) {
      return {
        'pageViewId': _state.splitPageViewId,
        'imageIndex': _state.splitPageViewIndex,
      };
    }
    return null;
  }

  // ==========================================
  // Drag Lifecycle
  // ==========================================

  void startDrag(String nodeId, BuildContext context, Offset globalPosition) {
    _bindUploadService(context);

    if (_isBusyRef(nodeId)) {
      debugPrint('[DragService] ⚠️ 업로드/압축 중인 노드는 드래그할 수 없습니다: $nodeId');
      return;
    }

    final node = editorService.document.getNodeById(nodeId);
    if (node is ImageRowNode || node is PageViewImageNode) {
      final meta = (node as dynamic).metadata as Map<String, dynamic>?;
      if (meta != null && meta['isPlaceholder'] == true) {
        debugPrint('[DragService] ⚠️ 업로드 중인 그룹 이미지는 드래그할 수 없습니다');
        return;
      }
    }

    _state.draggingNodeId = nodeId;
    draggingNodeIdNotifier.value = nodeId;
    _state.draggingNodeType = editorService.getNodeType(nodeId);
    _state.dragPosition = globalPosition;
    _state.lastMovedPosition = globalPosition;
    _state.dragStartPosition = globalPosition;

    _initializeDragSubject(nodeId);
    _state.dropTarget = const DropTarget.none();

    _autoScrollController.stop();

    final dropInfo = _dropTargetCalculator.computeDropInfo(globalPosition);
    if (dropInfo != null) {
      _state.dropIndex = dropInfo['dropIndex'] as int?;
    }

    if (node is ClipNode) {
      _pauseAllVideos();
    }

    notifyListeners();
  }

  void _initializeDragSubject(String nodeId) {
    if (_state.splitPageViewId != null && _state.splitPageViewIndex != null) {
      // PageView 아이템 분리 드래그: 이미 설정된 값 유지
      return;
    }

    if (_state.splitImageRowId != null && _state.splitImageIndex != null) {
      // Row 아이템 분리 드래그: 이미 설정된 값 유지
      _imageExtractor.extractImageUrl(nodeId);
      return;
    }

    // 기본은 "문서 노드 드래그"
    _state.subjectKind = DragSubjectKind.node;
    _state.subjectNodeId = nodeId;
    _state.subjectRowId = null;
    _state.subjectRowImageIndex = null;
    _state.subjectPageViewId = null;
    _state.subjectPageViewImageIndex = null;
    _state.intent = DragIntent.reorderNode;
    _imageExtractor.extractImageUrl(nodeId);
  }

  void updateDrag(Offset globalPosition, BuildContext context) {
    _bindUploadService(context);
    _state.dragPosition = globalPosition;
    _state.lastMovedPosition = globalPosition;

    _coordinateHelper.invalidateCache();

    final dropInfo = _dropTargetCalculator.computeDropInfo(globalPosition);
    if (dropInfo != null) {
      _state.dropIndex = dropInfo['dropIndex'] as int?;
    } else {
      _resetDropTarget();
    }

    if (_state.dropIndex == null && _state.dragMode == DragType.none) {
      _state.targetNodeId = null;
      _state.targetNodeType = null;
    }

    notifyListeners();
    _autoScrollController.maybeAutoScroll(_state.dragPosition);
  }

  void _resetDropTarget() {
    _state.dropIndex = null;
    _state.dropTarget = const DropTarget.none();
    _state.intent = DragIntent.none;
    _state.dragMode = DragType.none;
    _state.targetNodeId = null;
    _state.targetNodeType = null;
    _state.targetRowId = null;
  }

  void endDrag() {
    draggingNodeIdNotifier.value = null;
    _state.previewImageUrl = null;
    _state.previewImageLocalPath = null;

    if (_state.draggingNodeId == null) {
      _cleanup();
      return;
    }

    if (_shouldCancelSplit()) {
      _cleanup();
      return;
    }

    final handledBySplit = _handleSplitIfNeeded();
    if (handledBySplit) {
      _cleanup();
      return;
    }

    _executeDragAction();
    _cleanup();
  }

  bool _shouldCancelSplit() {
    // Row 분리 취소 체크
    if (_state.hasSplitImageInfo) {
      final backToOriginal =
          (_state.targetNodeId == _state.splitImageRowId) ||
          (_state.targetRowId == _state.splitImageRowId);
      final isSplittingToAdjacent =
          _state.dropTarget.kind == DropTargetKind.insertBetweenNodes;

      if (backToOriginal &&
          _state.dragMode != DragType.imageRowMerge &&
          !isSplittingToAdjacent) {
        return true;
      }
    }

    // PageView 분리 취소 체크
    if (_state.hasSplitPageViewInfo) {
      final backToOriginal =
          (_state.targetNodeId == _state.splitPageViewId) ||
          (_state.targetPageViewId == _state.splitPageViewId);
      final isSplittingToAdjacent =
          _state.dropTarget.kind == DropTargetKind.insertBetweenNodes;

      if (backToOriginal &&
          _state.dragMode != DragType.imagePageViewMerge &&
          !isSplittingToAdjacent) {
        return true;
      }
    }

    return false;
  }

  bool _handleSplitIfNeeded() {
    // ⚠️ 중요: split(한 장 떼어내기)은 "단독 노드로 삽입/재정렬"을 의도할 때만 실행해야 한다.
    // 기존 로직은 merge 모드에서도 split을 먼저 실행(부작용)한 뒤, 조건에 따라 false를 반환해
    // 결과적으로 "엉뚱한 이미지가 분리"되거나 "병합 대신 단순 분리" 같은 불안정이 발생할 수 있었다.

    final hasAnySplitInfo =
        _state.hasSplitImageInfo || _state.hasSplitPageViewInfo;
    if (!hasAnySplitInfo) return false;

    // merge 모드에서는 split을 절대 실행하지 않는다 (merge 액션이 source를 직접 갱신/감소시킴)
    if (_state.dragMode == DragType.imageRowMerge ||
        _state.dragMode == DragType.imagePageViewMerge) {
      return false;
    }

    // reorder(단독 삽입/이동)에서만 split 수행
    if (_state.dragMode != DragType.reorder) return false;

    final wantsStandaloneInsert =
        _state.dropTarget.kind == DropTargetKind.insertBetweenNodes ||
            _state.dropIndex != null;
    if (!wantsStandaloneInsert) return false;

    bool handled = false;
    if (_state.hasSplitImageInfo) {
      handled = _handleRowSplit() || handled;
    }
    if (_state.hasSplitPageViewInfo) {
      handled = _handlePageViewSplit() || handled;
    }

    return handled;
  }

  bool _handleRowSplit() {
    final rowId = _state.splitImageRowId;
    final imageIndex = _state.splitImageIndex;
    if (rowId == null || imageIndex == null) return false;

    final rowNode = editorService.document.getNodeById(rowId);
    if (rowNode == null || rowNode is! ImageRowNode) return false;
    if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) return false;

    final doc = editorService.document;
    final validDropIndex =
        (_state.dropIndex != null &&
            _state.dropIndex! >= 0 &&
            _state.dropIndex! <= doc.length)
        ? _state.dropIndex
        : null;

    int? insertIndex;
    if (_state.dragMode == DragType.reorder && validDropIndex != null) {
      insertIndex = validDropIndex;
    }

    final splitImageId = editorService.splitImageFromRow(
      rowId,
      imageIndex,
      insertIndex: insertIndex,
    );

    if (splitImageId != null) {
      _state.draggingNodeId = splitImageId;
      _state.draggingNodeType = editorService.getNodeType(splitImageId);
      _coordinateHelper.invalidateCache();
      return true;
    }

    return false;
  }

  bool _handlePageViewSplit() {
    final pageViewId = _state.splitPageViewId;
    final imageIndex = _state.splitPageViewIndex;
    if (pageViewId == null || imageIndex == null) return false;

    final pageViewNode = editorService.document.getNodeById(pageViewId);
    if (pageViewNode == null || pageViewNode is! PageViewImageNode)
      return false;
    if (imageIndex < 0 || imageIndex >= pageViewNode.imageUrls.length)
      return false;

    final doc = editorService.document;
    final validDropIndex =
        (_state.dropIndex != null &&
            _state.dropIndex! >= 0 &&
            _state.dropIndex! <= doc.length)
        ? _state.dropIndex
        : null;

    int? insertIndex;
    if (_state.dragMode == DragType.imagePageViewMerge &&
        _state.targetPageViewId != null &&
        _state.targetPageViewInsertIndex != null) {
      insertIndex = null; // 병합 처리
    } else if (_state.dropTarget.kind == DropTargetKind.insertBetweenNodes &&
        _state.dropTarget.insertIndex != null) {
      insertIndex = _state.dropTarget.insertIndex;
    } else if (_state.dragMode == DragType.reorder && validDropIndex != null) {
      insertIndex = validDropIndex;
    }

    final splitImageId = editorService.splitImageFromPageView(
      pageViewId,
      imageIndex,
      insertIndex: insertIndex,
    );

    if (splitImageId != null) {
      _state.draggingNodeId = splitImageId;
      _state.draggingNodeType = editorService.getNodeType(splitImageId);
      _coordinateHelper.invalidateCache();
      return true;
    }

    return false;
  }

  void _executeDragAction() {
    switch (_state.dragMode) {
      case DragType.reorder:
        _executeReorder();
        break;
      case DragType.imageRowMerge:
        _executeImageRowMerge();
        break;
      case DragType.imagePageViewMerge:
        _executeImagePageViewMerge();
        break;
      case DragType.none:
        break;
    }
  }

  void _executeReorder() {
    if (_state.dropIndex == null || _state.draggingNodeId == null) return;

    final nodeId = _state.draggingNodeId!;
    final doc = editorService.document;
    final validDropIndex = _state.dropIndex!.clamp(0, doc.length);

    final draggingNode = doc.getNodeById(nodeId);
    if (draggingNode == null) return;

    editorService.reorderNode(nodeId, validDropIndex);
    _coordinateHelper.invalidateCache();
  }

  void _executeImageRowMerge() {
    final mergeTargetId = _state.targetRowId ?? _state.targetNodeId;
    if (mergeTargetId == null) return;

    // 🎯 Row에서 한 장 뺀 드래그 → 다른 Row/싱글에 병합
    if (_state.isRowItemDrag &&
        _state.subjectRowId != null &&
        _state.subjectRowImageIndex != null) {
      editorService.mergeRowImageIntoRow(
        _state.subjectRowId!,
        _state.subjectRowImageIndex!,
        mergeTargetId,
        isFromLeft: isDraggingFromLeft,
        imageUrl: _state.subjectRowImageUrl,
      );
      _coordinateHelper.invalidateCache();
      return;
    }

    // 🎯 PageView에서 한 장 뺀 드래그 → PageView 이미지를 Row/싱글에 병합
    if (_state.isPageViewItemDrag &&
        _state.subjectPageViewId != null &&
        _state.subjectPageViewImageIndex != null) {
      editorService.mergePageViewImageIntoRow(
        _state.subjectPageViewId!,
        _state.subjectPageViewImageIndex!,
        mergeTargetId,
        isFromLeft: isDraggingFromLeft,
        imageUrl: _state.subjectPageViewImageUrl,
      );
      _coordinateHelper.invalidateCache();
      return;
    }

    if (_state.draggingNodeId == null) return;
    final nodeId = _state.draggingNodeId!;
    final targetId = mergeTargetId;

    final targetNode = editorService.document.getNodeById(targetId);
    if (targetNode == null) return;
    if (targetNode is! ImageRowNode && targetNode is! ImageNode) return;

    final draggingNode = editorService.document.getNodeById(nodeId);
    if (draggingNode == null) return;

    editorService.mergeImagesIntoRow(
      nodeId,
      targetId,
      isFromLeft: isDraggingFromLeft,
    );
    _coordinateHelper.invalidateCache();
  }

  void _executeImagePageViewMerge() {
    final mergeTargetId = _state.targetPageViewId ?? _state.targetNodeId;
    if (mergeTargetId == null || _state.targetPageViewInsertIndex == null) return;

    final targetId = mergeTargetId;
    final insertIndex = _state.targetPageViewInsertIndex!;

    final targetNode = editorService.document.getNodeById(targetId);
    if (targetNode == null) return;
    if (targetNode is! PageViewImageNode) return;

    // 🎯 Row에서 한 장 뺀 드래그 → Row 이미지를 PageView에 병합
    if (_state.isRowItemDrag &&
        _state.subjectRowId != null &&
        _state.subjectRowImageIndex != null) {
      editorService.mergeRowImageIntoPageView(
        _state.subjectRowId!,
        _state.subjectRowImageIndex!,
        targetId,
        insertIndex: insertIndex,
        imageUrl: _state.subjectRowImageUrl,
      );
      _coordinateHelper.invalidateCache();
      return;
    }

    if (_state.draggingNodeId == null) return;
    final nodeId = _state.draggingNodeId!;
    final draggingNode = editorService.document.getNodeById(nodeId);
    if (draggingNode == null) return;

    editorService.mergeImageIntoPageView(
      nodeId,
      targetId,
      insertIndex: insertIndex,
    );
    _coordinateHelper.invalidateCache();
  }

  void _cleanup() {
    _autoScrollController.stop();
    _state.reset();
    _ensureSelectionCleared();
    notifyListeners();
  }

  void _ensureSelectionCleared() {
    _imageService?.clearSelection();
    _imageService?.clearHighlightedSelection();
    try {
      editorService.editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[DragService] 텍스트 선택 해제 실패: $e');
    }
  }

  // ==========================================
  // ClipNode Handling
  // ==========================================

  String? handleClipNodeTap(String nodeId, Offset globalTapPosition) {
    final nodeRect = getNodeGlobalRect(nodeId);
    if (nodeRect == null) return null;

    final localTap = Offset(
      globalTapPosition.dx - nodeRect.left,
      globalTapPosition.dy - nodeRect.top,
    );

    const screenWidth = 400.0; // TODO: 실제 화면 너비 전달
    const muteButtonSize = 66.0;

    final buttonRight = screenWidth;
    final buttonLeft = buttonRight - muteButtonSize;
    final buttonBottom = nodeRect.height;
    final buttonTop = buttonBottom - muteButtonSize;

    final isMuteButtonArea =
        localTap.dx > buttonLeft &&
        localTap.dx < buttonRight &&
        localTap.dy > buttonTop &&
        localTap.dy < buttonBottom;

    if (isMuteButtonArea) {
      return 'toggleMute';
    }

    final isCenterArea =
        localTap.dx > (screenWidth / 2 - 100) &&
        localTap.dx < (screenWidth / 2 + 100) &&
        localTap.dy > (nodeRect.height / 2 - 25) &&
        localTap.dy < (nodeRect.height / 2 + 25);

    if (isCenterArea) {
      final clipNode = editorService.document.getNodeById(nodeId);
      if (clipNode is ClipNode) {
        final key = videoPlayerProxyKey(
          namespace: 'editor',
          url: clipNode.url,
          localPath: clipNode.localPath,
        );
        final controller = videoPlayerControllers[key];

        if (controller?.hasPlayedOnce != null && controller!.hasPlayedOnce!()) {
          return 'restartVideo';
        }
      }
      return 'restartVideo';
    }

    return null;
  }

  void _pauseAllVideos() {
    for (final entry in videoPlayerControllers.entries) {
      final controller = entry.value;
      if (controller.pause != null) {
        controller.pause!();
      }
    }
  }

  // ==========================================
  // Upload Service Binding
  // ==========================================

  bool _isBusyRef(String refId) {
    if (!networkMode) return false;
    if (_uploadService == null) return false;
    return _uploadService!.isBusyRef(refId);
  }

  void _bindUploadService(BuildContext context) {
    if (!networkMode) return;
    if (_uploadService != null) return;
    try {
      _uploadService = Provider.of<IUploadService>(context, listen: false);
    } catch (_) {
      // Provider가 없으면 무시
    }
  }
}
