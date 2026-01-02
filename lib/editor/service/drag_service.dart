import 'dart:async';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/component/clip_component.dart';
// 멘션은 MentionNode 기반으로 처리한다.
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

enum DragType { none, reorder, imageRowMerge, imagePageViewMerge }

/// 드래그 "대상(사용자가 실제로 잡은 것)"의 종류
/// - node: 문서에 존재하는 노드(기존)
/// - rowItem: ImageRowNode 내부의 특정 이미지(분리/복귀/병합)
/// - pageViewItem: PageViewImageNode 내부의 특정 이미지(분리/복귀/병합)
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
         // ✅ 항상 targetNodeId를 채워서(싱글 이미지/Row 모두) UI 매칭이 흔들리지 않게 한다.
         // rowId는 이름상 "Row"지만 실제로는 ImageNode(싱글)에도 사용될 수 있다.
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
         // ✅ 항상 targetNodeId를 채워서 UI 매칭이 흔들리지 않게 한다.
         targetNodeId: targetNodeId ?? pageViewId,
         insertIndex: insertIndex,
       );

  /// 멘션 노드 병합 미리보기 타겟
  /// - 실제 동작은 reorder 후 `EditorService._mergeAdjacentMentionNodesAround`에서 병합된다.
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

class DragService extends ChangeNotifier {
  final EditorService editorService;
  NodeComponentService? _imageService;
  ScrollController? scrollController;

  NodeComponentService? get imageService => _imageService;

  String? draggingNodeId;
  final ValueNotifier<String?> draggingNodeIdNotifier = ValueNotifier<String?>(
    null,
  );
  NodeType? draggingNodeType;
  String? targetNodeId;
  NodeType? targetNodeType;
  DragType dragMode = DragType.none;

  Offset? dragPosition;
  int? dropIndex;
  Offset? lastMovedPosition;
  Offset? _dragStartPosition; // 🎯 드래그 시작 위치 (드롭라인 표시 임계값 계산용)

  /// 🎯 드래그가 실제로 움직였는지 확인 (일정 거리 이상)
  bool get hasDraggedSignificantly {
    if (dragPosition == null || _dragStartPosition == null) return false;
    return (dragPosition! - _dragStartPosition!).distance >
        EditorDragConfig.dragSignificantDistancePx;
  }

  /// ===== 드래그 세션(대상/의도/드롭 타겟) =====
  DragSubjectKind subjectKind = DragSubjectKind.node;
  String? subjectNodeId; // subjectKind == node
  String? subjectRowId; // subjectKind == rowItem
  int? subjectRowImageIndex; // subjectKind == rowItem
  String? subjectPageViewId; // subjectKind == pageViewItem
  int? subjectPageViewImageIndex; // subjectKind == pageViewItem
  DragIntent intent = DragIntent.none;
  DropTarget dropTarget = const DropTarget.none();

  // 🎯 드래그 오버레이에 표시할 이미지 URL (로드 없이 바로 표시)
  String? previewImageUrl;
  String? previewImageLocalPath; // 로컬 파일 경로 (ClipNode용)

  // 🎯 멘션 노드 드래그 시 프로필 이미지 URL
  String? mentionProfileImageUrl;

  // 이미지 분리 정보 (Row)
  String? _splitImageRowId;
  int? _splitImageIndex;
  // 이미지 분리 정보 (PageView)
  String? _splitPageViewId;
  int? _splitPageViewIndex;
  // 이미지 행 타겟 삽입 정보
  String? _targetRowId;
  // PageView 타겟 삽입 정보
  String? _targetPageViewId;
  int? _targetPageViewInsertIndex;

  /// PageView 현재 페이지 인덱스 캐시
  /// - DragService는 PageController에 직접 접근할 수 없으므로, 실제 PageView 컴포넌트가 현재 페이지를 알려준다.
  final Map<String, int> _pageViewCurrentPageById = <String, int>{};

  // Auto-scroll state
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0.0; // -1: up, 1: down, 0: none

  // ===== 레이아웃/좌표 유틸 및 성능 캐시 =====
  final Map<String, Rect> _nodeRectCache = {};
  void invalidateNodeRectCache() => _nodeRectCache.clear();

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
      final ro =
          editorService.documentLayoutKey?.currentContext?.findRenderObject();
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

  /// 세로 노드 사이 클릭 감지. 감지 시 삽입 인덱스 반환
  int? detectVerticalGapAt(Offset globalPos, {double pad = 30.0}) {
    // 🎯 4.0 → 20.0 증가
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

  DragService({
    required this.editorService,
    NodeComponentService? imageService,
    this.scrollController,
  }) : _imageService = imageService;

  void setImageService(NodeComponentService imageService) {
    _imageService = imageService;
  }

  bool get isDragging => draggingNodeId != null;
  bool get hasSplitImageInfo =>
      _splitImageRowId != null && _splitImageIndex != null;
  bool get hasSplitPageViewInfo =>
      _splitPageViewId != null && _splitPageViewIndex != null;

  bool get isRowItemDrag =>
      subjectKind == DragSubjectKind.rowItem &&
      subjectRowId != null &&
      subjectRowImageIndex != null;
  bool get isPageViewItemDrag =>
      subjectKind == DragSubjectKind.pageViewItem &&
      subjectPageViewId != null &&
      subjectPageViewImageIndex != null;

  /// PageView 컴포넌트가 현재 페이지 인덱스를 DragService에 전달한다.
  void setPageViewCurrentPage(String pageViewId, int pageIndex) {
    _pageViewCurrentPageById[pageViewId] = pageIndex;
  }

  int? getPageViewCurrentPage(String pageViewId) {
    return _pageViewCurrentPageById[pageViewId];
  }

  void attachScrollController(ScrollController controller) {
    scrollController = controller;
  }

  // 분리할 이미지 정보 설정
  void setSplitImageInfo(String rowId, int imageIndex) {
    _splitImageRowId = rowId;
    _splitImageIndex = imageIndex;

    // ✅ 분리 드래그는 “문서 노드(ImageRowNode)”가 아니라 “Row 내부 아이템”을 드래그하는 것으로 모델링
    subjectKind = DragSubjectKind.rowItem;
    subjectNodeId = null;
    subjectRowId = rowId;
    subjectRowImageIndex = imageIndex;
    intent = DragIntent.splitFromRow;
  }

  // 분리할 이미지 정보 가져오기
  Map<String, dynamic>? getSplitImageInfo() {
    if (_splitImageRowId != null && _splitImageIndex != null) {
      return {'rowId': _splitImageRowId, 'imageIndex': _splitImageIndex};
    }
    return null;
  }

  // 분리할 PageView 이미지 정보 설정
  void setSplitPageViewInfo(String pageViewId, int imageIndex) {
    debugPrint(
      '[DragService] 🔍 setSplitPageViewInfo 호출: pageViewId=$pageViewId, imageIndex=$imageIndex',
    );
    _splitPageViewId = pageViewId;
    _splitPageViewIndex = imageIndex;

    // ✅ 분리 드래그는 "문서 노드(PageViewImageNode)"가 아니라 "PageView 내부 아이템"을 드래그하는 것으로 모델링
    subjectKind = DragSubjectKind.pageViewItem;
    subjectNodeId = null;
    subjectPageViewId = pageViewId;
    subjectPageViewImageIndex = imageIndex;
    intent = DragIntent.splitFromPageView;

    // 🎯 분리 정보 설정 후 이미지 URL 추출 (드래그 오버레이에 올바른 이미지 표시)
    _extractImageUrl(pageViewId);
  }

  // 분리할 PageView 이미지 정보 가져오기
  Map<String, dynamic>? getSplitPageViewInfo() {
    if (_splitPageViewId != null && _splitPageViewIndex != null) {
      return {
        'pageViewId': _splitPageViewId,
        'imageIndex': _splitPageViewIndex,
      };
    }
    return null;
  }

  void startDrag(String nodeId, BuildContext context, Offset globalPosition) {
    // 🎯 업로드 중인 그룹 이미지는 드래그 불가
    final node = editorService.document.getNodeById(nodeId);
    if (node is ImageRowNode || node is PageViewImageNode) {
      final meta = (node as dynamic).metadata as Map<String, dynamic>?;
      if (meta != null && meta['isPlaceholder'] == true) {
        debugPrint('[DragService] ⚠️ 업로드 중인 그룹 이미지는 드래그할 수 없습니다');
        return; // 드래그 시작 차단
      }
    }

    draggingNodeId = nodeId;
    draggingNodeIdNotifier.value = nodeId;
    draggingNodeType = editorService.getNodeType(nodeId);
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;
    _dragStartPosition = globalPosition; // 🎯 드래그 시작 위치 저장

    // 🎯 분리 정보가 이미 설정되어 있으면 유지 (PageView/Row 아이템 드래그)
    if (_splitPageViewId != null && _splitPageViewIndex != null) {
      // PageView 아이템 분리 드래그: 이미 setSplitPageViewInfo에서 설정된 값 유지
      // subjectKind, subjectPageViewId, subjectPageViewImageIndex는 이미 설정되어 있음
      // 🎯 setSplitPageViewInfo에서 이미 _extractImageUrl을 호출했으므로 다시 호출할 필요 없음
    } else if (_splitImageRowId != null && _splitImageIndex != null) {
      // Row 아이템 분리 드래그: 이미 setSplitImageInfo에서 설정된 값 유지
      // subjectKind, subjectRowId, subjectRowImageIndex는 이미 설정되어 있음
      // 🎯 setSplitImageInfo에서 이미 _extractImageUrl을 호출했을 수 있으므로 다시 호출
      _extractImageUrl(nodeId);
    } else {
      // 기본은 "문서 노드 드래그"
      subjectKind = DragSubjectKind.node;
      subjectNodeId = nodeId;
      subjectRowId = null;
      subjectRowImageIndex = null;
      subjectPageViewId = null;
      subjectPageViewImageIndex = null;
      intent = DragIntent.reorderNode;
      // 🎯 노드에서 이미지 URL 추출
      _extractImageUrl(nodeId);
    }
    dropTarget = const DropTarget.none();

    _stopAutoScroll();
    _autoScrollDirection = 0.0;

    final dropInfo = computeDropInfo(globalPosition);
    if (dropInfo != null) {
      dropIndex = dropInfo['dropIndex'] as int?;
    }

    // ClipNode 드래그 시작 시 모든 비디오 일시정지
    if (node is ClipNode) {
      _pauseAllVideos();
    }

    notifyListeners();
  }

  // 🎯 노드에서 이미지 URL 추출
  void _extractImageUrl(String nodeId) {
    try {
      final node = editorService.document.getNodeById(nodeId);
      if (node == null) {
        previewImageUrl = null;
        previewImageLocalPath = null;
        return;
      }

      previewImageUrl = null;
      previewImageLocalPath = null;

      if (node is ImageNode) {
        // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
        final imageUrl = node.imageUrl;
        if (imageUrl.isNotEmpty && !EditorService.isNetworkUrl(imageUrl)) {
          // 로컬 경로인 경우
          previewImageLocalPath = imageUrl;
        } else {
          // 네트워크 URL인 경우
          previewImageUrl = imageUrl;
        }
      } else if (node is ClipNode) {
        // ClipNode: thumbnailPath 우선, 없으면 metadata의 thumbnailUrl
        if (node.thumbnailPath.isNotEmpty) {
          previewImageLocalPath = node.thumbnailPath;
        } else if (node.localPath.isNotEmpty) {
          previewImageLocalPath = node.localPath;
        } else {
          final meta = node.metadata;
          if (meta['thumbnailUrl'] != null) {
            previewImageUrl = meta['thumbnailUrl'].toString();
          }
        }
      } else if (node is ImageRowNode) {
        // ImageRowNode: 첫 번째 이미지 URL 사용
        if (node.imageUrls.isNotEmpty) {
          final firstUrl = node.imageUrls.first;
          // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
          if (firstUrl.isNotEmpty && !EditorService.isNetworkUrl(firstUrl)) {
            previewImageLocalPath = firstUrl;
          } else {
            previewImageUrl = firstUrl;
          }
        }
      } else if (node is PageViewImageNode) {
        // PageViewImageNode: 분리 모드일 때는 선택된 이미지 인덱스 사용, 아니면 첫 번째 이미지
        if (node.imageUrls.isNotEmpty) {
          String targetUrl;
          if (isPageViewItemDrag &&
              subjectPageViewImageIndex != null &&
              subjectPageViewImageIndex! >= 0 &&
              subjectPageViewImageIndex! < node.imageUrls.length) {
            // 🎯 분리 모드: 선택된 페이지 인덱스의 이미지 사용
            targetUrl = node.imageUrls[subjectPageViewImageIndex!];
          } else {
            // 일반 드래그: 첫 번째 이미지 사용
            targetUrl = node.imageUrls.first;
          }
          // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
          if (targetUrl.isNotEmpty && !EditorService.isNetworkUrl(targetUrl)) {
            previewImageLocalPath = targetUrl;
          } else {
            previewImageUrl = targetUrl;
          }
        }
      } else if (node is LinkNode) {
        previewImageUrl = node.thumbnailUrl;
      }
    } catch (_) {
      previewImageUrl = null;
      previewImageLocalPath = null;
    }
  }

  void updateDrag(Offset globalPosition, BuildContext context) {
    Map<String, dynamic>? dropInfo;
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;

    // ✅ 드래그 중에는 스크롤/레이아웃 변동이 자주 발생한다.
    // 노드 rect 캐시가 stale 해지면(특히 싱글 이미지) hit-test 보정이 실패해서
    // 타겟이 Paragraph로 튀고, 결과적으로 병합/드롭라인이 안 뜨는 체감이 생긴다.
    // 성능 비용보다 정확도가 훨씬 중요하므로 매 프레임 무효화한다.
    invalidateNodeRectCache();

    dropInfo = computeDropInfo(globalPosition);

    if (dropInfo != null) {
      if (dropInfo['dropIndex'] != null) {
        final newDropIndex = dropInfo['dropIndex'] as int;
        dropIndex = newDropIndex;
      } else {
        dropIndex = null;
      }
    } else {
      // 🎯 중요: computeDropInfo가 null이면(레이아웃/좌표 계산 실패 등) 이전 dropTarget이 남아
      // 드롭라인/머지라인이 "유령"처럼 남을 수 있다. 이 경우 안전하게 타겟/모드를 리셋한다.
      dropIndex = null;
      dropTarget = const DropTarget.none();
      intent = DragIntent.none;
      dragMode = DragType.none;
      targetNodeId = null;
      targetNodeType = null;
      _targetRowId = null;
    }

    // computeDropInfo에서 이미 dragMode와 targetNodeId를 설정했으므로
    // dropIndex가 null이고 dragMode도 none일 때만 정리
    if (dropIndex == null && dragMode == DragType.none) {
      targetNodeId = null;
      targetNodeType = null;
    }
    // 그 외의 경우는 computeDropInfo에서 설정한 값을 그대로 사용

    // 항상 UI 업데이트 (드래그 오버레이 부드러운 이동을 위해)
    notifyListeners();

    // 가장자리 자동 스크롤
    _maybeAutoScroll(context);
  }

  void endDrag() {
    debugPrint('[DragService] 🎯 endDrag 호출됨');
    debugPrint(
      '[DragService] 🔍 endDrag 상태: hasSplitPageViewInfo=$hasSplitPageViewInfo, hasSplitImageInfo=$hasSplitImageInfo, dragMode=$dragMode, dropTarget=$dropTarget',
    );
    draggingNodeIdNotifier.value = null;
    previewImageUrl = null; // 🎯 이미지 URL 정리
    previewImageLocalPath = null;
    if (draggingNodeId == null) {
      debugPrint('[DragService] ⚠️ draggingNodeId가 null, 종료');
      _cleanup();
      return;
    }

    // 이미지 분리 예정이고, 원래 행으로 돌아왔으며 중앙 영역(=reorder) 드롭이면 분리 취소
    // 🎯 단, dropTarget이 insertBetweenNodes이면 Row 위/아래로 분리하려는 의도이므로 취소하지 않음
    if (hasSplitImageInfo) {
      final backToOriginal =
          (targetNodeId != null && targetNodeId == _splitImageRowId) ||
          (_targetRowId != null && _targetRowId == _splitImageRowId);
      final isSplittingToAdjacent =
          dropTarget.kind == DropTargetKind.insertBetweenNodes;
      debugPrint(
        '[DragService] 🔍 Row 분리 취소 체크: backToOriginal=$backToOriginal, isSplittingToAdjacent=$isSplittingToAdjacent, targetNodeId=$targetNodeId, _splitImageRowId=$_splitImageRowId, _targetRowId=$_targetRowId, dragMode=$dragMode, dropTarget.kind=${dropTarget.kind}',
      );
      // 🎯 Row 위/아래로 분리하려는 경우(dropTarget이 insertBetweenNodes)는 취소하지 않음
      if (backToOriginal &&
          dragMode != DragType.imageRowMerge &&
          !isSplittingToAdjacent) {
        debugPrint('[DragService] ⚠️ Row 분리 취소: 원래 Row로 돌아옴 (중앙 영역)');
        _cleanup();
        return;
      }
    }

    // PageView 이미지 분리 예정이고, 원래 PageView로 돌아왔으며 중앙 영역(=reorder) 드롭이면 분리 취소
    // 🎯 단, dropTarget이 insertBetweenNodes이면 PageView 위/아래로 분리하려는 의도이므로 취소하지 않음
    if (hasSplitPageViewInfo) {
      final backToOriginal =
          (targetNodeId != null && targetNodeId == _splitPageViewId) ||
          (_targetPageViewId != null && _targetPageViewId == _splitPageViewId);
      final isSplittingToAdjacent =
          dropTarget.kind == DropTargetKind.insertBetweenNodes;
      debugPrint(
        '[DragService] 🔍 PageView 분리 취소 체크: backToOriginal=$backToOriginal, isSplittingToAdjacent=$isSplittingToAdjacent, targetNodeId=$targetNodeId, _splitPageViewId=$_splitPageViewId, _targetPageViewId=$_targetPageViewId, dragMode=$dragMode, dropTarget.kind=${dropTarget.kind}',
      );
      // 🎯 PageView 위/아래로 분리하려는 경우(dropTarget이 insertBetweenNodes)는 취소하지 않음
      if (backToOriginal &&
          dragMode != DragType.imagePageViewMerge &&
          !isSplittingToAdjacent) {
        debugPrint('[DragService] ⚠️ PageView 분리 취소: 원래 PageView로 돌아옴 (중앙 영역)');
        _cleanup();
        return;
      }
    }

    // 이미지 분리 정보가 있으면 먼저 분리 실행
    bool handledBySplitInsertion = false;
    if (hasSplitImageInfo) {
      final rowId = _splitImageRowId;
      final imageIndex = _splitImageIndex;

      if (rowId != null && imageIndex != null) {
        // 🎯 분리 전 노드 존재 확인
        final rowNode = editorService.document.getNodeById(rowId);
        if (rowNode == null || rowNode is! ImageRowNode) {
          debugPrint('[DragService] ⚠️ 분리 대상 행이 존재하지 않음: $rowId');
          _cleanup();
          return;
        }

        // 🎯 이미지 인덱스 범위 확인
        if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) {
          debugPrint(
            '[DragService] ⚠️ 이미지 인덱스가 범위를 벗어남: $imageIndex (행 이미지 수: ${rowNode.imageUrls.length})',
          );
          _cleanup();
          return;
        }

        // 🎯 dropIndex 유효성 검증
        final doc = editorService.document;
        final validDropIndex =
            (dropIndex != null && dropIndex! >= 0 && dropIndex! <= doc.length)
                ? dropIndex
                : null;

        // 🎯 로우 이미지 분리: 원래 로직 유지 (dragMode == DragType.reorder일 때만 insertIndex 설정)
        // dropTarget을 확인하지 않고 원래대로 작동
        int? insertIndex;
        if (dragMode == DragType.reorder && validDropIndex != null) {
          insertIndex = validDropIndex;
        } else {
          insertIndex = null;
        }

        debugPrint(
          '[DragService] 🔍 Row 분리: dragMode=$dragMode, dropIndex=$dropIndex, validDropIndex=$validDropIndex, insertIndex=$insertIndex',
        );

        // 분리 확정 시점: targetRowId가 있으면 그 행에 삽입, 없으면 기존 로우 근처 단독 삽입
        final splitImageId = editorService.splitImageFromRow(
          rowId,
          imageIndex,
          insertIndex: insertIndex,
        );
        if (splitImageId != null) {
          draggingNodeId = splitImageId;
          draggingNodeType = editorService.getNodeType(splitImageId);
          handledBySplitInsertion =
              (dragMode == DragType.reorder && dropIndex != null);
          // 🎯 분리 성공 시 즉시 캐시 무효화
          invalidateNodeRectCache();
        }
      }
    }

    // PageView 이미지 분리 정보가 있으면 먼저 분리 실행
    debugPrint(
      '[DragService] 🔍 PageView 분리 체크: hasSplitPageViewInfo=$hasSplitPageViewInfo, _splitPageViewId=$_splitPageViewId, _splitPageViewIndex=$_splitPageViewIndex',
    );
    if (hasSplitPageViewInfo) {
      final pageViewId = _splitPageViewId;
      final imageIndex = _splitPageViewIndex;

      if (pageViewId != null && imageIndex != null) {
        // 🎯 분리 전 노드 존재 확인
        final pageViewNode = editorService.document.getNodeById(pageViewId);
        if (pageViewNode == null || pageViewNode is! PageViewImageNode) {
          debugPrint('[DragService] ⚠️ 분리 대상 PageView가 존재하지 않음: $pageViewId');
          _cleanup();
          return;
        }

        // 🎯 이미지 인덱스 범위 확인
        if (imageIndex < 0 || imageIndex >= pageViewNode.imageUrls.length) {
          debugPrint(
            '[DragService] ⚠️ 이미지 인덱스가 범위를 벗어남: $imageIndex (PageView 이미지 수: ${pageViewNode.imageUrls.length})',
          );
          _cleanup();
          return;
        }

        // 🎯 dropIndex 유효성 검증
        final doc = editorService.document;
        final validDropIndex =
            (dropIndex != null && dropIndex! >= 0 && dropIndex! <= doc.length)
                ? dropIndex
                : null;

        debugPrint(
          '[DragService] 🔍 PageView 분리: dragMode=$dragMode, dropIndex=$dropIndex, validDropIndex=$validDropIndex, dropTarget.kind=${dropTarget.kind}, dropTarget.insertIndex=${dropTarget.insertIndex}',
        );

        // 🎯 PageView 병합 모드인 경우 특정 인덱스에 삽입
        int? insertIndex;
        if (dragMode == DragType.imagePageViewMerge &&
            _targetPageViewId != null &&
            _targetPageViewInsertIndex != null) {
          insertIndex = null; // PageView 내부 삽입은 mergeImageIntoPageView에서 처리
          debugPrint(
            '[DragService] 🔍 PageView 병합 모드: insertIndex=null (병합 처리)',
          );
        } else {
          // 🎯 dropTarget이 insertBetweenNodes이면 insertIndex 설정 (dragMode와 무관하게)
          // 드롭라인이 표시되었다는 것은 사용자가 해당 위치에 삽입하려는 의도
          if (dropTarget.kind == DropTargetKind.insertBetweenNodes &&
              dropTarget.insertIndex != null) {
            insertIndex = dropTarget.insertIndex;
            debugPrint(
              '[DragService] 🔍 PageView 분리: dropTarget=insertBetweenNodes($insertIndex), insertIndex=$insertIndex',
            );
          } else if (dragMode == DragType.reorder && validDropIndex != null) {
            // 🎯 reorder 모드이고 validDropIndex가 있으면 사용
            insertIndex = validDropIndex;
            debugPrint(
              '[DragService] 🔍 PageView 분리: dragMode=reorder, insertIndex=$insertIndex',
            );
          } else {
            insertIndex = null;
            debugPrint(
              '[DragService] 🔍 PageView 분리: insertIndex=null (dropTarget.kind=${dropTarget.kind}, dragMode=$dragMode)',
            );
          }
        }

        // 분리 확정 시점
        debugPrint(
          '[DragService] 🔍 splitImageFromPageView 호출: pageViewId=$pageViewId, imageIndex=$imageIndex, insertIndex=$insertIndex',
        );
        final splitImageId = editorService.splitImageFromPageView(
          pageViewId,
          imageIndex,
          insertIndex: insertIndex,
        );
        if (splitImageId != null) {
          draggingNodeId = splitImageId;
          draggingNodeType = editorService.getNodeType(splitImageId);
          // 🎯 로우 이미지와 동일한 로직: reorder 모드이고 dropIndex가 있을 때만 처리 완료로 표시
          handledBySplitInsertion =
              (dragMode == DragType.reorder && dropIndex != null);
          // 🎯 분리 성공 시 즉시 캐시 무효화
          invalidateNodeRectCache();
        }
      }
    }

    // 실제 노드 이동 실행
    // 분리하면서 이미 원하는 위치로 삽입한 경우 추가 이동 불필요
    if (handledBySplitInsertion) {
      _cleanup();
      return;
    }

    switch (dragMode) {
      case DragType.reorder:
        if (dropIndex != null && draggingNodeId != null) {
          final nodeId = draggingNodeId!;
          final doc = editorService.document;
          final validDropIndex = dropIndex!.clamp(0, doc.length);

          // 드래그 중인 노드가 여전히 존재하는지 확인
          final draggingNode = doc.getNodeById(nodeId);
          if (draggingNode == null) {
            debugPrint('[DragService] ⚠️ 드래그 중인 노드가 존재하지 않음: $nodeId');
            _cleanup();
            return;
          }

          editorService.reorderNode(nodeId, validDropIndex);
          invalidateNodeRectCache();
          _cleanup();
          return;
        }
        break;
      case DragType.imageRowMerge:
        {
          final String? mergeTargetId = _targetRowId ?? targetNodeId;
          if (mergeTargetId != null && draggingNodeId != null) {
            final nodeId = draggingNodeId!;
            final targetId = mergeTargetId;

            // 병합 전 노드 존재 확인
            final targetNode = editorService.document.getNodeById(targetId);
            if (targetNode == null) {
              debugPrint('[DragService] ⚠️ 병합 대상 노드가 존재하지 않음: $targetId');
              _cleanup();
              return;
            }

            // 타겟 노드가 이미지 타입인지 확인
            if (targetNode is! ImageRowNode && targetNode is! ImageNode) {
              debugPrint(
                '[DragService] ⚠️ 병합 대상 노드가 이미지 타입이 아님: ${targetNode.runtimeType}',
              );
              _cleanup();
              return;
            }

            // 드래그 중인 노드가 여전히 존재하는지 확인
            final draggingNode = editorService.document.getNodeById(nodeId);
            if (draggingNode == null) {
              debugPrint('[DragService] ⚠️ 드래그 중인 노드가 존재하지 않음: $nodeId');
              _cleanup();
              return;
            }

            editorService.mergeImagesIntoRow(
              nodeId,
              targetId,
              isFromLeft: isDraggingFromLeft,
            );
            invalidateNodeRectCache();
            _cleanup();
            return;
          }
        }
        break;
      case DragType.imagePageViewMerge:
        {
          final String? mergeTargetId = _targetPageViewId ?? targetNodeId;
          if (mergeTargetId != null &&
              draggingNodeId != null &&
              _targetPageViewInsertIndex != null) {
            final nodeId = draggingNodeId!;
            final targetId = mergeTargetId;
            final insertIndex = _targetPageViewInsertIndex!;

            // 병합 전 노드 존재 확인
            final targetNode = editorService.document.getNodeById(targetId);
            if (targetNode == null) {
              debugPrint('[DragService] ⚠️ 병합 대상 노드가 존재하지 않음: $targetId');
              _cleanup();
              return;
            }

            // 타겟 노드가 PageViewImageNode인지 확인
            if (targetNode is! PageViewImageNode) {
              debugPrint(
                '[DragService] ⚠️ 병합 대상 노드가 PageView 타입이 아님: ${targetNode.runtimeType}',
              );
              _cleanup();
              return;
            }

            // 드래그 중인 노드가 여전히 존재하는지 확인
            final draggingNode = editorService.document.getNodeById(nodeId);
            if (draggingNode == null) {
              debugPrint('[DragService] ⚠️ 드래그 중인 노드가 존재하지 않음: $nodeId');
              _cleanup();
              return;
            }

            editorService.mergeImageIntoPageView(
              nodeId,
              targetId,
              insertIndex: insertIndex,
            );
            invalidateNodeRectCache();
            _cleanup();
            return;
          }
        }
        break;
      case DragType.none:
        break;
    }

    // 드래그 종료 처리
    _cleanup();
  }

  /// 🎯 선택 해제를 확실하게 보장하는 헬퍼 메서드
  void _ensureSelectionCleared() {
    imageService?.clearSelection();
    imageService?.clearHighlightedSelection();

    // 🎯 텍스트 선택도 해제
    try {
      editorService.editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[DragService] 텍스트 선택 해제 실패: $e');
    }
  }

  void _cleanup() {
    _stopAutoScroll();
    draggingNodeId = null;
    draggingNodeType = null;
    targetNodeId = null;
    targetNodeType = null;
    dragMode = DragType.none;
    dropIndex = null;
    dragPosition = null;
    lastMovedPosition = null;
    _dragStartPosition = null; // 🎯 드래그 시작 위치 초기화

    subjectKind = DragSubjectKind.node;
    subjectNodeId = null;
    subjectRowId = null;
    subjectRowImageIndex = null;
    subjectPageViewId = null;
    subjectPageViewImageIndex = null;
    intent = DragIntent.none;
    dropTarget = const DropTarget.none();

    // 분리 정보 초기화
    _splitImageRowId = null;
    _splitImageIndex = null;
    _splitPageViewId = null;
    _splitPageViewIndex = null;
    _targetRowId = null;
    _targetPageViewId = null;
    _targetPageViewInsertIndex = null;

    // 선택 해제 (다른 로직에서 선택이 다시 설정되는 경우 대비)
    _ensureSelectionCleared();

    notifyListeners();
  }

  void _maybeAutoScroll(BuildContext context) {
    if (scrollController == null || dragPosition == null) return;
    if (!scrollController!.hasClients) return;

    final bounds = _viewportBounds();
    if (bounds == null) return;
    const edgeMargin = 72.0; // 가장자리 감지 영역
    final pos = dragPosition!;

    double direction = 0.0;
    if (pos.dy < bounds.top + edgeMargin) {
      direction = -1.0; // 위로 스크롤
    } else if (pos.dy > bounds.bottom - edgeMargin) {
      direction = 1.0; // 아래로 스크롤
    }

    if (direction == 0.0) {
      _autoScrollDirection = 0.0;
      _stopAutoScroll();
      return;
    }

    _autoScrollDirection = direction;
    _startAutoScrollTimer(edgeMargin);
  }

  void _startAutoScrollTimer(double edgeMargin) {
    if (_autoScrollTimer != null) return;
    const interval = Duration(milliseconds: 16); // ~60 FPS
    _autoScrollTimer = Timer.periodic(interval, (_) {
      if (scrollController == null || dragPosition == null) {
        _stopAutoScroll();
        return;
      }
      if (!scrollController!.hasClients) {
        _stopAutoScroll();
        return;
      }

      final bounds = _viewportBounds();
      if (bounds == null) {
        _stopAutoScroll();
        return;
      }

      final max = scrollController!.position.maxScrollExtent;
      final min = scrollController!.position.minScrollExtent;
      final current = scrollController!.offset;

      // 속도: 가장자리 근접할수록 빠르게
      final distanceToEdge =
          _autoScrollDirection < 0
              ? (dragPosition!.dy - bounds.top).clamp(0.0, edgeMargin)
              : (bounds.bottom - dragPosition!.dy).clamp(0.0, edgeMargin);
      final proximity = (edgeMargin - distanceToEdge) / edgeMargin; // 0..1
      const maxSpeed = 900.0; // px/s
      const minSpeed = 240.0; // px/s
      final speed = minSpeed + (maxSpeed - minSpeed) * proximity;
      final delta =
          speed * (interval.inMilliseconds / 1000.0) * _autoScrollDirection;

      double next = (current + delta).clamp(min, max);
      if (next == current) {
        _stopAutoScroll();
        return;
      }

      scrollController!.jumpTo(next);

      // 스크롤 후 드롭 인덱스 재계산
      final dropInfo = computeDropInfo(dragPosition!);
      if (dropInfo != null && dropInfo['dropIndex'] != null) {
        dropIndex = dropInfo['dropIndex'] as int;
      }
      notifyListeners();
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  Rect? _viewportBounds() {
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

  /// 드래그 방향을 계산 (왼쪽에서 오는지 오른쪽에서 오는지)
  bool get isDraggingFromLeft {
    if (dragPosition == null || targetNodeId == null) {
      return true; // 기본값은 왼쪽
    }

    // 타겟 노드의 컴포넌트를 찾아서 그 중앙을 기준으로 판정
    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return true;

    final component = documentLayout.getComponentByNodeId(targetNodeId!);
    if (component == null) return true;

    final renderBox = component.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return true;

    final targetCenter =
        renderBox.localToGlobal(Offset.zero) +
        Offset(renderBox.size.width / 2, renderBox.size.height / 2);

    final isFromLeft = dragPosition!.dx < targetCenter.dx;

    assert(() {
      debugPrint('=== 드래그 방향 계산 ===');
      debugPrint('드래그 위치: ${dragPosition!}');
      debugPrint('타겟 중앙: $targetCenter');
      debugPrint('왼쪽에서 오는가: $isFromLeft');
      return true;
    }());

    return isFromLeft;
  }

  /// 단순한 드롭 인덱스 계산
  Map<String, dynamic>? computeDropInfo(Offset globalPosition) {
    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return null;

    // 글로벌 좌표를 문서의 로컬 좌표로 변환
    final renderObject =
        editorService.documentLayoutKey?.currentContext?.findRenderObject();
    if (renderObject == null) return null;

    RenderBox? renderBox;
    if (renderObject is RenderSliverToBoxAdapter) {
      renderBox = renderObject.child;
    } else if (renderObject is RenderBox) {
      renderBox = renderObject;
    }
    if (renderBox == null) return null;

    // 🎯 좌표 변환 및 유효성 검증
    Offset localPosition;
    try {
      localPosition = renderBox.globalToLocal(globalPosition);
      // 무한대 또는 NaN 값 체크
      if (!localPosition.dx.isFinite || !localPosition.dy.isFinite) {
        debugPrint('[DragService] ⚠️ 좌표가 유효하지 않음: $localPosition');
        return null;
      }

      // 🎯 문서 영역 범위 체크 및 클램핑
      final documentSize = renderBox.size;
      if (localPosition.dx < 0 ||
          localPosition.dx > documentSize.width ||
          localPosition.dy < 0 ||
          localPosition.dy > documentSize.height) {
        // 범위를 벗어나면 가장자리로 클램핑
        localPosition = Offset(
          localPosition.dx.clamp(0, documentSize.width),
          localPosition.dy.clamp(0, documentSize.height),
        );
        debugPrint('[DragService] 📍 좌표가 문서 범위를 벗어나 클램핑: $localPosition');
      }
    } catch (e) {
      debugPrint('[DragService] ⚠️ globalToLocal 변환 실패: $e');
      return null;
    }

    // 문서 끝 부분 감지를 위한 추가 처리
    final documentLength = editorService.document.length;

    // 🎯 빈 문서 처리
    if (documentLength == 0) {
      dropTarget = const DropTarget.insertBetweenNodes(0);
      intent = DragIntent.reorderNode;
      dropIndex = 0;
      return {'dropIndex': 0};
    }

    // SuperEditor의 정확한 위치 계산 (로컬 좌표 사용)
    DocumentPosition? position;
    try {
      position = documentLayout.getDocumentPositionNearestToOffset(
        localPosition,
      );
    } catch (e) {
      debugPrint("DragService에서 getDocumentPositionNearestToOffset 오류: $e");
      return null;
    }

    if (position == null) return null;

    final doc = editorService.document;
    // 이후 로직에서 position/node가 재할당될 수 있으므로 별도 non-null 변수로 분리
    DocumentPosition resolvedPosition = position;
    final initialNode = doc.getNodeById(resolvedPosition.nodeId);
    if (initialNode == null) return null;
    DocumentNode node = initialNode;

    // 노드 인덱스 찾기
    int nodeIndex = doc.getNodeIndexById(node.id);
    if (nodeIndex == -1) return null;

    debugPrint(
      '[DragService] 🎯 computeDropInfo 시작: globalPosition=$globalPosition, localPosition=$localPosition',
    );
    debugPrint(
      '[DragService] 초기 타겟: nodeId=${node.id}, nodeType=${node.runtimeType}, nodeIndex=$nodeIndex',
    );
    debugPrint(
      '[DragService] 드래그 중: draggingNodeId=$draggingNodeId, draggingNodeType=$draggingNodeType',
    );

    // ✅ 타겟 보정(표시 안정화 - 싱글 이미지 병합 드롭라인 안정화):
    // getDocumentPositionNearestToOffset는 노드 경계/패딩에서 "인접 문단"으로 튀는 경우가 있다.
    // 특히 이미지/특수노드에서 이러면 병합용 세로 드롭라인이 안 뜨는 체감이 생긴다.
    // 따라서 현재 노드/이웃(prev/next) 중 "특수노드(특히 이미지)" rect에 실제로 포인터가 들어가 있으면,
    // 그 특수노드를 타겟으로 보정한다.
    // 🎯 특히 드래그 중인 노드가 이미지일 때는 이웃 이미지 노드를 더 적극적으로 타겟으로 잡는다.
    final isDraggingImage = draggingNodeType == NodeType.image;
    final neighborIds = <String?>[
      node.id,
      if (nodeIndex - 1 >= 0) doc.getNodeAt(nodeIndex - 1)?.id,
      if (nodeIndex + 1 < doc.length) doc.getNodeAt(nodeIndex + 1)?.id,
    ];
    // 🎯 드래그 중인 노드가 이미지면, 이웃 이미지 노드를 우선적으로 타겟으로 잡는다.
    if (isDraggingImage) {
      debugPrint('[DragService] 🔍 이미지 드래그 감지, 이웃 노드 hit-test 보정 시작');
      for (final id in neighborIds) {
        if (id == null) continue;
        if (id == draggingNodeId) continue; // 자기 자신은 제외
        final n = doc.getNodeById(id);
        if (n == null) continue;
        // 이미지 타입만 타겟으로 (특수노드 전체가 아닌)
        final nType = editorService.getNodeType(id);
        if (nType != NodeType.image && nType != NodeType.imageRow) continue;
        final r = getNodeGlobalRect(id);
        debugPrint(
          '[DragService]   이웃 이미지 체크: id=$id, type=$nType, rect=$r, contains=${r != null && r.contains(globalPosition)}',
        );
        if (r != null && r.contains(globalPosition)) {
          debugPrint('[DragService] ✅ 이미지 타겟 보정: $id (기존: ${node.id})');
          node = n;
          nodeIndex = doc.getNodeIndexById(id);
          resolvedPosition = DocumentPosition(
            nodeId: id,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          );
          break;
        }
      }
    }
    // 일반적인 특수노드 보정 (멘션/링크 등)
    if (node.id == initialNode.id) {
      for (final id in neighborIds) {
        if (id == null) continue;
        final n = doc.getNodeById(id);
        if (n == null) continue;
        if (!NodeTypeChecker.isSpecialNode(n)) continue;
        final r = getNodeGlobalRect(id);
        if (r != null && r.contains(globalPosition)) {
          node = n;
          nodeIndex = doc.getNodeIndexById(id);
          resolvedPosition = DocumentPosition(
            nodeId: id,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          );
          break;
        }
      }
    }

    // ✅ 추가 타겟 보정(싱글 이미지 드롭라인 미표시 해결):
    // 로그에서처럼 손가락이 "싱글 이미지" 위에 있는데도 nearest position이 Paragraph로 잡히는 케이스가 있다.
    // 이 경우 이웃(prev/next)만으로는 이미지 타겟을 못 찾을 수 있으므로,
    // 주변 인덱스 범위를 훑어서 "손가락 아래에 실제로 걸린 이미지 rect"를 찾아 타겟을 이미지로 재보정한다.
    if (isDraggingImage) {
      final currentType = editorService.getNodeType(node.id);
      final bool targetIsImageLike =
          currentType == NodeType.image || currentType == NodeType.imageRow;
      if (!targetIsImageLike && doc.length > 0) {
        final int start = (nodeIndex - 6).clamp(0, doc.length - 1);
        final int end = (nodeIndex + 6).clamp(0, doc.length - 1);

        String? bestId;
        double bestDist2 = double.infinity;

        for (int i = start; i <= end; i++) {
          final candidate = doc.getNodeAt(i);
          if (candidate == null) continue;
          final cid = candidate.id;
          if (cid == draggingNodeId) continue;

          final ct = editorService.getNodeType(cid);
          if (ct != NodeType.image && ct != NodeType.imageRow) continue;

          final r = getNodeGlobalRect(cid);
          if (r == null) continue;

          // 약간 넓힌 rect로 hit-test (패딩/경계 튐 보정)
          final inflated = r.inflate(16);
          final contains = inflated.contains(globalPosition);
          if (!contains) continue;

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
            debugPrint(
              '[DragService] ✅ 이미지 타겟(윈도우 스캔) 보정: $bestId (기존 타겟: ${node.id}, type=$currentType, range=[$start..$end])',
            );
            node = n;
            nodeIndex = doc.getNodeIndexById(bestId);
            resolvedPosition = DocumentPosition(
              nodeId: bestId,
              nodePosition: const UpstreamDownstreamNodePosition.downstream(),
            );
          }
        } else {
          debugPrint(
            '[DragService] ⚠️ 이미지 타겟(윈도우 스캔) 실패: currentTarget=${node.id}($currentType), range=[$start..$end]',
          );
        }
      }
    }

    // 타겟 노드 정보 업데이트
    final targetNodeType = editorService.getNodeType(node.id);
    targetNodeId = node.id;
    this.targetNodeType = targetNodeType;

    debugPrint(
      '[DragService] 최종 타겟: nodeId=$targetNodeId, targetNodeType=$targetNodeType, nodeIndex=$nodeIndex',
    );

    // 드래그 모드 결정
    // 이미지/이미지Row끼리일 때에도, 타겟의 좌/우 가장자리 근처에서만 병합 모드로 진입
    // 그 외 대부분 영역에서는 reorder가 되도록 한다.
    // 🎯 싱글 이미지 병합 드롭라인 안정화: 감지 폭을 넓혀서 더 넓은 영역에서 병합 모드 진입
    const double horizontalMergeEdgePx = 50.0; // 좌/우 가장자리 감지 폭 (30 -> 50으로 확대)

    // 🎯 PageView 병합 모드 체크 (이미지 -> PageView 또는 PageView -> PageView)
    // - 기존: PageView 위에만 올라가면 항상 병합 모드 → 위/아래 드롭라인 감지가 매우 어려움
    // - 개선: "의도(좌/우로 충분히 치우침) + 세로 안전영역(위/아래 가장자리 제외)"에서만 병합 모드 진입
    if (targetNodeType == NodeType.pageViewImage &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.pageViewImage)) {
      final bool sameId = draggingNodeId == node.id;
      // pageViewItem 드래그는 draggingNodeId가 pageViewId여도 "자기 자신"으로 보지 않는다.
      final bool allowMergeCandidate = !sameId || isPageViewItemDrag;

      bool shouldEnablePageViewMerge = false;
      if (allowMergeCandidate) {
        final Rect? targetRect = documentLayout.getRectForPosition(
          resolvedPosition,
        );
        if (targetRect != null) {
          final double localXWithinTarget = localPosition.dx - targetRect.left;
          final double localYWithinTarget = localPosition.dy - targetRect.top;
          final double w = targetRect.width;
          final double h = targetRect.height;

          final double verticalInset =
              (h * EditorDragConfig.pageViewMergeVerticalInsetRatio).clamp(
                EditorDragConfig.pageViewMergeVerticalInsetMinPx,
                EditorDragConfig.pageViewMergeVerticalInsetMaxPx,
              );
          final bool inVerticalSafeBand =
              localYWithinTarget > verticalInset &&
              localYWithinTarget < (h - verticalInset);

          final double deadZone =
              (w * EditorDragConfig.pageViewMergeCenterDeadZoneRatio).clamp(
                EditorDragConfig.pageViewMergeCenterDeadZoneMinPx,
                EditorDragConfig.pageViewMergeCenterDeadZoneMaxPx,
              );
          final double midX = w / 2;
          final bool isClearlyLeft = localXWithinTarget < (midX - deadZone);
          final bool isClearlyRight = localXWithinTarget > (midX + deadZone);

          // ✅ 중앙(데드존)에서는 병합 미리보기(좌/우 패딩)를 띄우지 않는다.
          // ✅ 위/아래 가장자리에서는 reorder를 우선해서 드롭라인 감지 영역을 넓힌다.
          shouldEnablePageViewMerge =
              inVerticalSafeBand && (isClearlyLeft || isClearlyRight);
        }
      }

      // 🎯 페이지뷰 분리 중일 때는 병합 모드 비활성화 (드롭라인 표시 우선)
      final isSplittingPageView = hasSplitPageViewInfo;
      dragMode =
          (!isSplittingPageView &&
                  allowMergeCandidate &&
                  shouldEnablePageViewMerge)
              ? DragType.imagePageViewMerge
              : DragType.reorder;
    } else if ((targetNodeType == NodeType.image ||
            targetNodeType == NodeType.imageRow) &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow)) {
      final bool sameId = draggingNodeId == node.id;
      // rowItem 드래그는 draggingNodeId가 rowId(ImageRowNode)여도 "자기 자신"으로 보지 않는다.
      final bool allowMergeCandidate = !sameId || isRowItemDrag;
      debugPrint(
        '[DragService] 이미지/Row 병합 조건 체크: sameId=$sameId, isRowItemDrag=$isRowItemDrag, allowMergeCandidate=$allowMergeCandidate',
      );
      if (allowMergeCandidate) {
        // 문서 좌표계에서 타겟 노드의 사각형을 구해 좌/우 에지 근처인지 판단
        final Rect? targetRect = documentLayout.getRectForPosition(
          resolvedPosition,
        );

        bool nearHorizontalEdge = false;
        if (targetRect != null) {
          final double leftEdge = targetRect.left + horizontalMergeEdgePx;
          final double rightEdge = targetRect.right - horizontalMergeEdgePx;
          // localPosition은 동일 좌표계(문서 좌표) 기준
          nearHorizontalEdge =
              localPosition.dx <= leftEdge || localPosition.dx >= rightEdge;
          debugPrint(
            '[DragService] 타겟 rect: $targetRect, localX=${localPosition.dx}, leftEdge=$leftEdge, rightEdge=$rightEdge, nearHorizontalEdge=$nearHorizontalEdge',
          );
        } else {
          // 🎯 targetRect를 못 얻었어도, 타겟이 이미지 노드면 병합 모드로 진입 시도
          // (hit-test 보정으로 이미지 노드 타겟이 확정되었을 가능성이 높음)
          if (targetNodeType == NodeType.image ||
              targetNodeType == NodeType.imageRow) {
            nearHorizontalEdge = true; // 이미지 타겟이면 기본적으로 병합 모드 진입
            debugPrint(
              '[DragService] ⚠️ targetRect null, 이미지 타겟이므로 nearHorizontalEdge=true (병합 모드 진입 시도)',
            );
          } else {
            debugPrint(
              '[DragService] ⚠️ targetRect null, 이미지 타겟 아님, nearHorizontalEdge=false',
            );
          }
        }

        // ✅ 병합 모드는 "에지 근처"에서만 유지한다.
        // (점착성(Sticky)을 유지하면 한 번 병합 모드에 들어간 뒤,
        // 중앙으로 이동해도 reorder로 안 돌아가 드롭라인이 안 보이는 체감이 생길 수 있음)
        if (nearHorizontalEdge &&
            (targetNodeType == NodeType.image ||
                targetNodeType == NodeType.imageRow)) {
          dragMode = DragType.imageRowMerge;
          debugPrint('[DragService] ✅ 병합 모드 진입: DragType.imageRowMerge');
        } else {
          dragMode = DragType.reorder;
          debugPrint(
            '[DragService] 📍 reorder 모드: nearHorizontalEdge=$nearHorizontalEdge',
          );
        }
      } else {
        dragMode = DragType.reorder;
        debugPrint('[DragService] 📍 reorder 모드: allowMergeCandidate=false');
      }
    } else {
      dragMode = DragType.reorder;
    }

    // 드롭 인덱스 계산
    // ✅ 정책: "타겟 노드 사각형의 상/하 반"으로 before/after를 결정한다.
    // - 이렇게 해야 모든 노드(텍스트/특수/멘션/이미지)에서 드롭라인이 끊기지 않는다.
    int? finalCandidate;
    final Rect? targetRectForDropIndex = documentLayout.getRectForPosition(
      resolvedPosition,
    );
    if (targetRectForDropIndex == null) {
      // rect를 못 얻어도 최소한 '해당 노드 앞'은 유지
      finalCandidate = nodeIndex;
      debugPrint(
        '[DragService] ⚠️ targetRectForDropIndex null, finalCandidate=$finalCandidate (nodeIndex)',
      );
    } else {
      finalCandidate =
          (localPosition.dy <= targetRectForDropIndex.center.dy)
              ? nodeIndex
              : (nodeIndex + 1);
      debugPrint(
        '[DragService] 드롭 인덱스 계산: localY=${localPosition.dy}, centerY=${targetRectForDropIndex.center.dy}, finalCandidate=$finalCandidate',
      );
    }

    // 맨 위 삽입을 위한 특별 처리
    // 첫 행(타이틀 아래) 배치 허용: 타이틀을 건드리지 않되, 그 아래로는 허용
    // finalCandidate가 0이면 이후 타이틀 보정에서 +1 처리됨

    // 제목은 썸네일 편집 화면에서 입력하므로 제목 위로 드롭 불가 로직 제거됨

    // 가로배치 모드일 때는 dropIndex를 null로 설정 (가로라인 표시 안함)
    // 🎯 단, 로우 이미지 분리 중일 때는 UI 표시용으로 드롭라인을 표시
    if (dragMode == DragType.imageRowMerge && !hasSplitImageInfo) {
      finalCandidate = null;
    }

    // PageView 병합 모드일 때는 dropIndex를 null로 설정
    // 🎯 단, 페이지뷰 분리 중일 때는 UI 표시용으로 드롭라인을 표시 (비즈니스 로직은 endDrag에서 처리)
    if (dragMode == DragType.imagePageViewMerge && !hasSplitPageViewInfo) {
      finalCandidate = null;
    }

    // ✅ 분리 취소 감지(원래 행/페이지뷰 + "중앙 영역")에서만 라인을 숨긴다.
    // 기존 구현은 타겟이 원래 노드이면 전체 영역에서 드롭라인이 사라져
    // 위/아래 삽입이 "감지 범위가 너무 작은" 체감이 생길 수 있었다.
    // 🎯 페이지뷰 분리 중일 때는 dragMode와 관계없이 분리 취소 로직 적용
    if ((dragMode == DragType.reorder ||
            (dragMode == DragType.imagePageViewMerge &&
                hasSplitPageViewInfo)) &&
        targetRectForDropIndex != null) {
      // Row split cancel
      if (hasSplitImageInfo && targetNodeId == _splitImageRowId) {
        final localY = localPosition.dy - targetRectForDropIndex.top;
        final edgeY = (targetRectForDropIndex.height *
                EditorDragConfig.splitCancelEdgeYRatio)
            .clamp(
              EditorDragConfig.splitCancelEdgeYMinPx,
              EditorDragConfig.splitCancelEdgeYMaxPx,
            );
        final inCenter =
            localY > edgeY && localY < (targetRectForDropIndex.height - edgeY);
        debugPrint(
          '[DragService] 🔍 Row 분리 취소 체크: localY=$localY, edgeY=$edgeY, height=${targetRectForDropIndex.height}, inCenter=$inCenter, finalCandidate=$finalCandidate',
        );
        // 🎯 중앙 영역에서만 분리 취소 (위/아래 가장자리는 분리 허용)
        if (inCenter) {
          finalCandidate = null;
          debugPrint('[DragService] ⚠️ Row 분리 취소: 중앙 영역 (finalCandidate=null)');
        }
      }

      // PageView split cancel
      if (hasSplitPageViewInfo && targetNodeId == _splitPageViewId) {
        final localY = localPosition.dy - targetRectForDropIndex.top;
        final edgeY = (targetRectForDropIndex.height *
                EditorDragConfig.splitCancelEdgeYRatio)
            .clamp(
              EditorDragConfig.splitCancelEdgeYMinPx,
              EditorDragConfig.splitCancelEdgeYMaxPx,
            );
        final inCenter =
            localY > edgeY && localY < (targetRectForDropIndex.height - edgeY);
        if (inCenter) {
          finalCandidate = null;
        }
      }
    } else if ((dragMode == DragType.reorder ||
            (dragMode == DragType.imagePageViewMerge &&
                hasSplitPageViewInfo)) &&
        targetRectForDropIndex == null) {
      // rect를 못 얻으면 안전하게 취소 존으로 간주(기존 동작 유지)
      if (hasSplitImageInfo && targetNodeId == _splitImageRowId) {
        finalCandidate = null;
      }
      if (hasSplitPageViewInfo && targetNodeId == _splitPageViewId) {
        finalCandidate = null;
      }
    }

    // 디버그 로그
    /*
    debugPrint('=== 드롭 인덱스 계산 ===');
    debugPrint(
      '드래그 중인 노드: $draggingNodeId (인덱스: ${draggingNodeId != null ? getNodeIndex(draggingNodeId!) : -1})',
    );
    debugPrint('최종 드롭 인덱스: $finalCandidate');
    debugPrint('드래그 모드: $dragMode');
    */

    // 이미지 행 타겟에 대한 삽입 인덱스 계산 (분리/병합 판단에 활용)
    if (targetNodeType == NodeType.imageRow) {
      _targetRowId = node.id;
      // targetRect와 로컬 X로 삽입 위치 추정
      try {
        final Rect? targetRect = documentLayout.getRectForPosition(
          resolvedPosition,
        );
        // rowNode 정보 없이도 좌표 기반으로 삽입 슬롯 계산 (폭 기준 균등 분할)
        if (targetRect != null) {
          final double localXWithinTarget = localPosition.dx - targetRect.left;
          const int slots = 8; // 보수적 기본 슬롯 수 (필요 시 컴포넌트에서 전달하도록 개선)
          final double slotW = (targetRect.width / slots).clamp(
            1.0,
            targetRect.width,
          );
          int idx = (localXWithinTarget / slotW).floor();
          idx = idx.clamp(0, slots - 1);
        }
      } catch (_) {}
    } else {
      _targetRowId = null;
    }

    // 🎯 PageView 타겟에 대한 삽입 인덱스 계산
    // - PageView는 수평 스크롤이므로 Y가 아니라 X(좌/우)에 따라 before/after를 결정한다.
    // - 실제 "현재 페이지"는 PageView 컴포넌트가 setPageViewCurrentPage로 전달한다.
    if (targetNodeType == NodeType.pageViewImage &&
        dragMode == DragType.imagePageViewMerge) {
      _targetPageViewId = node.id;
      try {
        final pageViewNode = node as PageViewImageNode;
        final Rect? targetRect = documentLayout.getRectForPosition(
          resolvedPosition,
        );
        if (targetRect != null) {
          // PageView 내부의 X 좌표 계산
          final double localXWithinTarget = localPosition.dx - targetRect.left;
          final int imageCount = pageViewNode.imageUrls.length;
          if (imageCount > 0) {
            final int currentPage = (_pageViewCurrentPageById[node.id] ?? 0)
                .clamp(0, imageCount - 1);
            // dragMode가 imagePageViewMerge일 때만 여기로 들어오므로,
            // 중앙 데드존에서의 흔들림(좌/우 flip)은 이미 차단된 상태다.
            final bool isLeftHalf = localXWithinTarget < (targetRect.width / 2);
            final int insertIdx = (isLeftHalf ? currentPage : (currentPage + 1))
                .clamp(0, imageCount);
            _targetPageViewInsertIndex = insertIdx;
          } else {
            _targetPageViewInsertIndex = 0;
          }
        }
      } catch (_) {
        _targetPageViewInsertIndex = null;
      }
    } else {
      _targetPageViewId = null;
      _targetPageViewInsertIndex = null;
    }

    // ✅ dropTarget 업데이트 (드롭라인/머지라인 렌더링의 단일 입력 신호)
    if (dragMode == DragType.imageRowMerge) {
      final isFromLeft = isDraggingFromLeft;
      dropTarget = DropTarget.mergeIntoRow(
        rowId: node.id,
        isFromLeft: isFromLeft,
        targetNodeId: node.id,
      );
      intent = DragIntent.mergeIntoRow;
      dropIndex = null;
      debugPrint(
        '[DragService] ✅ dropTarget 설정: mergeIntoRow, rowId=${node.id}, isFromLeft=$isFromLeft',
      );
      return {'dropIndex': null};
    }

    if (dragMode == DragType.imagePageViewMerge) {
      final insertIdx = _targetPageViewInsertIndex ?? 0;
      dropTarget = DropTarget.mergeIntoPageView(
        pageViewId: node.id,
        insertIndex: insertIdx,
        targetNodeId: node.id,
      );
      intent = DragIntent.mergeIntoPageView;
      dropIndex = null;
      debugPrint(
        '[DragService] ✅ dropTarget 설정: mergeIntoPageView, pageViewId=${node.id}, insertIndex=$insertIdx',
      );
      return {'dropIndex': null};
    }

    // 🎯 빈 문단 자동 삭제를 고려한 드롭 인덱스 조정
    if (finalCandidate != null) {
      // 빈 문단을 건너뛰어 실제 삽입될 위치 계산
      final adjustedIndex = _adjustDropIndexForEmptyParagraphs(
        finalCandidate,
        documentLength,
      );

      // 범위 검증
      final validDropIndex = adjustedIndex.clamp(0, documentLength);
      if (validDropIndex != finalCandidate) {
        debugPrint(
          '[DragService] 📍 dropIndex 조정: $finalCandidate -> $validDropIndex (빈 문단 고려)',
        );
      }
      // ✅ 멘션 드롭 시 인접 멘션 위/아래로 놓이면, 최종적으로는 병합된다.
      // (reorder + EditorService._mergeAdjacentMentionNodesAround)
      if (draggingNodeType == NodeType.mention &&
          targetNodeType == NodeType.mention &&
          draggingNodeId != null &&
          draggingNodeId != node.id) {
        dropTarget = DropTarget.mergeMentions(
          mentionId: node.id,
          insertIndex: validDropIndex,
        );
        debugPrint(
          '[DragService] ✅ dropTarget 설정: mergeMentions, mentionId=${node.id}, insertIndex=$validDropIndex',
        );
      } else {
        dropTarget = DropTarget.insertBetweenNodes(validDropIndex);
        debugPrint(
          '[DragService] ✅ dropTarget 설정: insertBetweenNodes, insertIndex=$validDropIndex (조정 전: $finalCandidate)',
        );
      }
      // splitFromRow를 시작한 세션이라도, "문서 사이 삽입" 타겟을 잡았을 때는 reorder로 판단(실제 split은 endDrag에서 commit)
      intent = DragIntent.reorderNode;
      dropIndex = validDropIndex;
      return {'dropIndex': validDropIndex};
    }

    dropTarget = const DropTarget.none();
    dropIndex = null;
    debugPrint('[DragService] ❌ dropTarget 설정: none (finalCandidate=null)');
    return {'dropIndex': null};
  }

  /// 노드 ID로 현재 노드의 인덱스 찾기
  int getNodeIndex(String nodeId) {
    return editorService.document.getNodeIndexById(nodeId);
  }

  /// 🎯 빈 문단 자동 삭제를 고려한 드롭 인덱스 조정
  /// 빈 문단 위/아래로 드롭할 때, 드롭 후 빈 문단이 삭제되면
  /// 실제 삽입 위치가 예상과 다를 수 있으므로 미리 조정
  int _adjustDropIndexForEmptyParagraphs(
    int candidateIndex,
    int documentLength,
  ) {
    if (candidateIndex < 0 || candidateIndex > documentLength) {
      return candidateIndex;
    }

    final doc = editorService.document;

    // 🎯 드롭 위치 바로 위에 빈 문단이 있으면 건너뛰기
    // (빈 문단 위로 드롭하면 빈 문단이 삭제되고 그 위치에 삽입됨)
    if (candidateIndex > 0) {
      final prevNode = doc.getNodeAt(candidateIndex - 1);
      if (prevNode != null && NodeTypeChecker.isEmptyParagraph(prevNode)) {
        // 빈 문단 위로 드롭하는 경우, 빈 문단 위치로 조정
        return candidateIndex - 1;
      }
    }

    // 🎯 드롭 위치에 빈 문단이 있으면 그대로 유지
    // (빈 문단 위로 드롭하면 빈 문단이 삭제되고 그 위치에 삽입되므로
    //  빈 문단 위치가 실제 삽입 위치가 됨 - 조정 불필요)
    if (candidateIndex < documentLength) {
      final currentNode = doc.getNodeAt(candidateIndex);
      if (currentNode != null &&
          NodeTypeChecker.isEmptyParagraph(currentNode)) {
        // 빈 문단 위치로 드롭하는 경우, 그대로 유지 (빈 문단이 삭제되고 그 위치에 삽입)
        return candidateIndex;
      }
    }

    return candidateIndex;
  }

  /// ClipNode 클릭 처리 - 버튼 영역 판단 및 액션 반환
  String? handleClipNodeTap(String nodeId, Offset globalTapPosition) {
    final nodeRect = getNodeGlobalRect(nodeId);
    if (nodeRect == null) {
      debugPrint('[DragService] ClipNode: nodeRect가 null입니다');
      return null;
    }

    final localTap = Offset(
      globalTapPosition.dx - nodeRect.left,
      globalTapPosition.dy - nodeRect.top,
    );

    // 화면 가로 너비 (SuperEditor context 필요)
    final screenWidth = 400.0; // TODO: 실제 화면 너비 전달

    // 우측 하단 음소거 버튼 영역 확대 (하단 모서리까지)
    final muteButtonSize = 66.0; // 버튼 영역을 더 크게
    final buttonRight = screenWidth;
    final buttonLeft = buttonRight - muteButtonSize;
    final buttonBottom = nodeRect.height;
    final buttonTop = buttonBottom - muteButtonSize;

    debugPrint(
      '[DragService] ClipNode: nodeRect=$nodeRect, localTap=$localTap',
    );
    debugPrint(
      '[DragService] ClipNode: Button area: left=$buttonLeft, right=$buttonRight, top=$buttonTop, bottom=$buttonBottom',
    );

    final isMuteButtonArea =
        localTap.dx > buttonLeft &&
        localTap.dx < buttonRight &&
        localTap.dy > buttonTop &&
        localTap.dy < buttonBottom;

    debugPrint('[DragService] ClipNode: isMuteButtonArea=$isMuteButtonArea');

    if (isMuteButtonArea) {
      debugPrint('[DragService] ClipNode: 음소거 버튼 클릭!');
      return 'toggleMute';
    }

    // 중앙 다시보기 버튼 영역 체크
    final isCenterArea =
        localTap.dx > (screenWidth / 2 - 100) &&
        localTap.dx < (screenWidth / 2 + 100) &&
        localTap.dy > (nodeRect.height / 2 - 25) &&
        localTap.dy < (nodeRect.height / 2 + 25);

    debugPrint('[DragService] ClipNode: isCenterArea=$isCenterArea');

    if (isCenterArea) {
      // 비디오가 끝났는지 확인
      final clipNode = editorService.document.getNodeById(nodeId);
      if (clipNode is ClipNode) {
        final key = videoPlayerProxyKey(
          namespace: 'editor',
          url: clipNode.url,
          localPath: clipNode.localPath,
        );
        final controller = videoPlayerControllers[key];

        // 비디오가 완전히 끝났을 때만 다시보기 버튼 반응
        if (controller?.hasPlayedOnce != null && controller!.hasPlayedOnce!()) {
          debugPrint('[DragService] ClipNode: 다시보기 버튼 클릭!');
          return 'restartVideo';
        } else {
          debugPrint('[DragService] ClipNode: 비디오가 아직 끝나지 않음');
          return null;
        }
      }

      debugPrint('[DragService] ClipNode: 다시보기 버튼 클릭!');
      return 'restartVideo';
    }

    debugPrint('[DragService] ClipNode: 일반 영역 클릭');
    return null;
  }

  /// 모든 비디오 일시정지
  void _pauseAllVideos() {
    for (final entry in videoPlayerControllers.entries) {
      final controller = entry.value;
      if (controller.pause != null) {
        controller.pause!();
        debugPrint('[DragService] 비디오 일시정지: ${entry.key}');
      }
    }
  }
}
