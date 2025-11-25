import 'dart:async';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

enum DragType { none, reorder, imageRowMerge }

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

  // 이미지 분리 정보
  String? _splitImageRowId;
  int? _splitImageIndex;
  // 이미지 행 타겟 삽입 정보
  String? _targetRowId;

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
  int? detectVerticalGapAt(Offset globalPos, {double pad = 10.0}) {
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

  void attachScrollController(ScrollController controller) {
    scrollController = controller;
  }

  // 분리할 이미지 정보 설정
  void setSplitImageInfo(String rowId, int imageIndex) {
    _splitImageRowId = rowId;
    _splitImageIndex = imageIndex;
  }

  // 분리할 이미지 정보 가져오기
  Map<String, dynamic>? getSplitImageInfo() {
    if (_splitImageRowId != null && _splitImageIndex != null) {
      return {'rowId': _splitImageRowId, 'imageIndex': _splitImageIndex};
    }
    return null;
  }

  void startDrag(String nodeId, BuildContext context, Offset globalPosition) {
    draggingNodeId = nodeId;
    draggingNodeIdNotifier.value = nodeId;
    draggingNodeType = editorService.getNodeType(nodeId);
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;
    _stopAutoScroll();
    _autoScrollDirection = 0.0;

    final dropInfo = computeDropInfo(globalPosition);
    if (dropInfo != null) {
      dropIndex = dropInfo['dropIndex'] as int?;
    }

    // ClipNode 드래그 시작 시 모든 비디오 일시정지
    final node = editorService.document.getNodeById(nodeId);
    if (node is ClipNode) {
      _pauseAllVideos();
    }

    notifyListeners();
  }

  void updateDrag(Offset globalPosition, BuildContext context) {
    Map<String, dynamic>? dropInfo;
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;
    dropInfo = computeDropInfo(globalPosition);

    if (dropInfo != null) {
      if (dropInfo['dropIndex'] != null) {
        final newDropIndex = dropInfo['dropIndex'] as int;
        dropIndex = newDropIndex;
      } else {
        dropIndex = null;
      }
    }

    // computeDropInfo에서 이미 dragMode와 targetNodeId를 설정했으므로
    // dropIndex가 null이고 dragMode도 none일 때만 정리
    if (dropIndex == null && dragMode == DragType.none) {
      targetNodeId = null;
      targetNodeType = null;
    }
    // 그 외의 경우는 computeDropInfo에서 설정한 값을 그대로 사용

    debugPrint('최종 dragMode: $dragMode');
    debugPrint('최종 dropIndex: $dropIndex');
    debugPrint('최종 targetNodeId: $targetNodeId');
    debugPrint('=== updateDrag 끝 ===');

    // 항상 UI 업데이트 (드래그 오버레이 부드러운 이동을 위해)
    notifyListeners();

    // 가장자리 자동 스크롤
    _maybeAutoScroll(context);
  }

  void endDrag() {
    draggingNodeIdNotifier.value = null;
    if (draggingNodeId == null) {
      _cleanup();
      return;
    }

    // 이미지 분리 예정이고, 원래 행으로 돌아왔으며 중앙 영역(=reorder) 드롭이면 분리 취소
    if (hasSplitImageInfo) {
      final backToOriginal =
          (targetNodeId != null && targetNodeId == _splitImageRowId) ||
          (_targetRowId != null && _targetRowId == _splitImageRowId);
      if (backToOriginal && dragMode != DragType.imageRowMerge) {
        imageService?.clearSelection();
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
        // 분리 확정 시점: targetRowId가 있으면 그 행에 삽입, 없으면 기존 로우 근처 단독 삽입
        final splitImageId = editorService.splitImageFromRow(
          rowId,
          imageIndex,
          insertIndex: (dragMode == DragType.reorder) ? dropIndex : null,
        );
        if (splitImageId != null) {
          draggingNodeId = splitImageId;
          draggingNodeType = editorService.getNodeType(splitImageId);
          handledBySplitInsertion =
              (dragMode == DragType.reorder && dropIndex != null);
        }
      }
    }

    // 실제 노드 이동 실행
    // 분리하면서 이미 원하는 위치로 삽입한 경우 추가 이동 불필요
    if (handledBySplitInsertion) {
      imageService?.clearSelection();
      _cleanup();
      return;
    }

    switch (dragMode) {
      case DragType.reorder:
        if (dropIndex != null) {
          editorService.reorderNode(draggingNodeId!, dropIndex!);
        }
        break;
      case DragType.imageRowMerge:
        {
          final String? mergeTargetId = _targetRowId ?? targetNodeId;
          if (mergeTargetId != null) {
            editorService.mergeImagesIntoRow(
              draggingNodeId!,
              mergeTargetId,
              isFromLeft: isDraggingFromLeft,
            );
          }
        }
        break;
      case DragType.none:
        break;
    }
    imageService?.clearSelection();
    _cleanup();
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

    // 분리 정보 초기화
    _splitImageRowId = null;
    _splitImageIndex = null;
    _targetRowId = null;

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

    debugPrint('=== 드래그 방향 계산 ===');
    debugPrint('드래그 위치: ${dragPosition!}');
    debugPrint('타겟 중앙: $targetCenter');
    debugPrint('왼쪽에서 오는가: $isFromLeft');

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

    final localPosition = renderBox.globalToLocal(globalPosition);

    // 문서 끝 부분 감지를 위한 추가 처리
    final documentLength = editorService.document.length;

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

    final node = editorService.document.getNodeById(position.nodeId);
    if (node == null) return null;

    // 노드 인덱스 찾기
    final nodeIndex = editorService.document.getNodeIndexById(node.id);
    if (nodeIndex == -1) return null;

    // 마지막 노드인지 확인
    final isLastNode = nodeIndex == documentLength - 1;

    // 타겟 노드 정보 업데이트
    final targetNodeType = editorService.getNodeType(node.id);
    targetNodeId = node.id;
    this.targetNodeType = targetNodeType;

    // 드래그 모드 결정
    // 이미지/이미지Row끼리일 때에도, 타겟의 좌/우 가장자리 근처에서만 병합 모드로 진입
    // 그 외 대부분 영역에서는 reorder가 되도록 한다.
    const double horizontalMergeEdgePx = 30.0; // 좌/우 가장자리 감지 폭

    if ((targetNodeType == NodeType.image ||
            targetNodeType == NodeType.imageRow) &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow) &&
        draggingNodeId != node.id) {
      // 문서 좌표계에서 타겟 노드의 사각형을 구해 좌/우 에지 근처인지 판단
      final Rect? targetRect = documentLayout.getRectForPosition(position);

      bool nearHorizontalEdge = false;
      if (targetRect != null) {
        final double leftEdge = targetRect.left + horizontalMergeEdgePx;
        final double rightEdge = targetRect.right - horizontalMergeEdgePx;
        // localPosition은 동일 좌표계(문서 좌표) 기준
        nearHorizontalEdge =
            localPosition.dx <= leftEdge || localPosition.dx >= rightEdge;
      }

      // 병합 모드 점착성 유지: 한 번 병합 모드에 들어가면 드래그가 끝날 때까지 유지
      if (dragMode == DragType.imageRowMerge || nearHorizontalEdge) {
        dragMode = DragType.imageRowMerge;
      } else {
        dragMode = DragType.reorder;
      }
    } else {
      dragMode = DragType.reorder;
    }

    // 드롭 인덱스 계산
    final draggingNodeIndex = editorService.document.getNodeIndexById(
      draggingNodeId!,
    );
    int? finalCandidate = nodeIndex;

    // 마지막 노드 처리
    if (isLastNode) {
      // 마지막 노드인 경우, 노드의 중간을 기준으로 위/아래 판단
      final Rect? targetRect = documentLayout.getRectForPosition(position);
      if (targetRect != null) {
        final nodeCenter = targetRect.center.dy;
        if (localPosition.dy > nodeCenter) {
          // 마지막 노드 아래쪽에 드롭 - 문서 끝에 삽입
          finalCandidate = documentLength;
        } else {
          // 마지막 노드 위쪽에 드롭 - 마지막 노드 앞에 삽입
          finalCandidate = nodeIndex;
        }
      } else {
        // targetRect를 가져올 수 없는 경우, 기본적으로 마지막 노드 앞에 삽입
        finalCandidate = nodeIndex;
      }
    } else if (draggingNodeId != null) {
      if (draggingNodeIndex != -1) {
        final bool isSplitDrag = hasSplitImageInfo; // 이미지 행에서 개별 이미지 분리 드래그 중인지

        if (isSplitDrag) {
          // 분리 드래그: 위/아래 제약 없음 (자기 자신, 바로 위/아래 모두 허용)
          finalCandidate = nodeIndex;
        } else {
          // 일반 드래그: 자기 자신과 바로 아래 위치 차단
          if (nodeIndex == draggingNodeIndex ||
              nodeIndex == draggingNodeIndex + 1) {
            finalCandidate = null;
          } else if (draggingNodeIndex < nodeIndex) {
            // 드래그 중인 노드가 타겟 노드보다 앞에 있으면, 타겟 노드 앞에 삽입
            finalCandidate = nodeIndex;
          } else {
            // 드래그 중인 노드가 타겟 노드보다 뒤에 있으면, 타겟 노드 앞에 삽입
            finalCandidate = nodeIndex;
          }
        }
      }
    } else {
      finalCandidate = nodeIndex;
    }

    // 맨 위 삽입을 위한 특별 처리
    // 첫 행(타이틀 아래) 배치 허용: 타이틀을 건드리지 않되, 그 아래로는 허용
    // finalCandidate가 0이면 이후 타이틀 보정에서 +1 처리됨

    // 타이틀 고정: 타이틀(isTitle=true) 위로는 드롭 불가 → 항상 타이틀 바로 아래로 보정
    try {
      if (finalCandidate != null) {
        final doc = editorService.document;
        int titleIndex = -1;
        final n = doc.getNodeAt(0);
        if (n is ParagraphNode && (n.metadata['isTitle'] == true)) {
          titleIndex = 0;
        }
        // 타이틀 바로 아래로 최소 보정. 타이틀 없으면 보정 생략
        if (titleIndex != -1 && finalCandidate <= titleIndex) {
          finalCandidate = titleIndex + 1;
        }
      }
    } catch (_) {}

    // 가로배치 모드일 때는 dropIndex를 null로 설정 (가로라인 표시 안함)
    if (dragMode == DragType.imageRowMerge) {
      finalCandidate = null;
    }

    // 분리 취소 감지(원래 행 + 중앙 영역) 시에도 드롭 라인을 표시하지 않음
    if (hasSplitImageInfo &&
        targetNodeId == _splitImageRowId &&
        dragMode == DragType.reorder) {
      finalCandidate = null;
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
        final Rect? targetRect = documentLayout.getRectForPosition(position);
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

    return {'dropIndex': finalCandidate};
  }

  /// 노드 ID로 현재 노드의 인덱스 찾기
  int getNodeIndex(String nodeId) {
    return editorService.document.getNodeIndexById(nodeId);
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
        final key = 'video_${clipNode.url.hashCode}';
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
