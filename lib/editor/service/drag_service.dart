import 'dart:async';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

enum DragType { none, reorder, imageRowMerge }

class DragService extends ChangeNotifier {
  final EditorService editorService;
  final ImageService imageService;
  ScrollController? scrollController;

  String? draggingNodeId;
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

  // Auto-scroll state
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0.0; // -1: up, 1: down, 0: none

  DragService({
    required this.editorService,
    required this.imageService,
    this.scrollController,
  });

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
    draggingNodeType = editorService.getNodeType(nodeId);
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;
    _stopAutoScroll();
    _autoScrollDirection = 0.0;

    final dropInfo = computeDropInfo(globalPosition);
    if (dropInfo != null) {
      dropIndex = dropInfo['dropIndex'] as int?;
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

    print('최종 dragMode: $dragMode');
    print('최종 dropIndex: $dropIndex');
    print('최종 targetNodeId: $targetNodeId');
    print('=== updateDrag 끝 ===');

    // 항상 UI 업데이트 (드래그 오버레이 부드러운 이동을 위해)
    notifyListeners();

    // 가장자리 자동 스크롤
    _maybeAutoScroll(context);
  }

  void endDrag() {
    if (draggingNodeId == null) {
      _cleanup();
      return;
    }

    // 이미지 분리 정보가 있으면 먼저 분리 실행
    if (hasSplitImageInfo) {
      final rowId = _splitImageRowId;
      final imageIndex = _splitImageIndex;

      if (rowId != null && imageIndex != null) {
        // 이미지 행에서 해당 이미지 분리
        final splitImageId = editorService.splitImageFromRow(rowId, imageIndex);

        if (splitImageId != null) {
          // 분리된 이미지의 ID로 드래그 노드 ID 업데이트
          draggingNodeId = splitImageId;
          draggingNodeType = editorService.getNodeType(splitImageId);
        }
      }
    }

    // 실제 노드 이동 실행
    switch (dragMode) {
      case DragType.reorder:
        if (dropIndex != null) {
          editorService.reorderNode(draggingNodeId!, dropIndex!);
        }
        break;
      case DragType.imageRowMerge:
        if (targetNodeId != null) {
          editorService.mergeImagesIntoRow(
            draggingNodeId!,
            targetNodeId!,
            isFromLeft: isDraggingFromLeft,
          );
        }
        break;
      case DragType.none:
        break;
    }

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

    print('=== 드래그 방향 계산 ===');
    print('드래그 위치: ${dragPosition!}');
    print('타겟 중앙: $targetCenter');
    print('왼쪽에서 오는가: $isFromLeft');

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

    // SuperEditor의 정확한 위치 계산 (로컬 좌표 사용)
    DocumentPosition? position;
    try {
      position = documentLayout.getDocumentPositionNearestToOffset(
        localPosition,
      );
    } catch (e) {
      print("DragService에서 getDocumentPositionNearestToOffset 오류: $e");
      return null;
    }

    if (position == null) return null;

    final node = editorService.editor.document.getNodeById(position.nodeId);
    if (node == null) return null;

    // 노드 인덱스 찾기
    final nodeIndex = editorService.editor.document.getNodeIndexById(node.id);
    if (nodeIndex == -1) return null;

    // 타겟 노드 정보 업데이트
    final targetNodeType = editorService.getNodeType(node.id);
    targetNodeId = node.id;
    this.targetNodeType = targetNodeType;

    // 드래그 모드 결정
    // 이미지 행 병합은 특정 조건에서만 발생 (예: 드래그 위치가 이미지 행의 중앙에 가까울 때)
    if ((targetNodeType == NodeType.image ||
            targetNodeType == NodeType.imageRow) &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow) &&
        draggingNodeId != node.id) {
      // 이미지 행 병합 조건: 타겟이 이미지 행이거나, 드래그 위치가 이미지의 중앙에 가까울 때
      if (targetNodeType == NodeType.imageRow) {
        dragMode = DragType.imageRowMerge;
      } else if (targetNodeType == NodeType.image) {
        // 단일 이미지의 경우, 드래그 위치가 이미지의 중앙에 가까우면 병합, 아니면 재정렬
        final component = documentLayout.getComponentByNodeId(node.id);
        if (component != null) {
          final renderBox = component.context.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final targetCenter =
                renderBox.localToGlobal(Offset.zero) +
                Offset(renderBox.size.width / 2, renderBox.size.height / 2);
            final distance = (globalPosition - targetCenter).distance;
            final threshold = renderBox.size.width * 0.3; // 이미지 너비의 30% 내에서 병합

            if (distance < threshold) {
              dragMode = DragType.imageRowMerge;
            } else {
              dragMode = DragType.reorder;
            }
          } else {
            dragMode = DragType.reorder;
          }
        } else {
          dragMode = DragType.reorder;
        }
      } else {
        dragMode = DragType.reorder;
      }
    } else {
      dragMode = DragType.reorder;
    }

    // 드롭 인덱스 계산
    int? finalCandidate = nodeIndex;
    if (draggingNodeId != null) {
      final draggingNodeIndex = editorService.editor.document.getNodeIndexById(
        draggingNodeId!,
      );
      if (draggingNodeIndex != -1) {
        // 원래 위치 근처로의 드롭 차단 (자기 자신과 바로 인접한 위치들)
        if (nodeIndex == draggingNodeIndex ||
            nodeIndex == draggingNodeIndex + 1 ||
            nodeIndex == draggingNodeIndex - 1) {
          finalCandidate = null;
        } else if (draggingNodeIndex < nodeIndex) {
          // 드래그 중인 노드가 타겟 노드보다 앞에 있으면, 타겟 노드 앞에 삽입
          finalCandidate = nodeIndex;
        } else {
          // 드래그 중인 노드가 타겟 노드보다 뒤에 있으면, 타겟 노드 뒤에 삽입
          finalCandidate = nodeIndex + 1;
        }
      }
    } else {
      finalCandidate = nodeIndex;
    }

    // 맨 위 삽입을 위한 특별 처리
    if (finalCandidate == 0) {
      finalCandidate = 0;
    }

    // 가로배치 모드일 때는 dropIndex를 null로 설정 (가로라인 표시 안함)
    if (dragMode == DragType.imageRowMerge) {
      finalCandidate = null;
    }

    // 디버그 로그
    /*
    print('=== 드롭 인덱스 계산 ===');
    print(
      '드래그 중인 노드: $draggingNodeId (인덱스: ${draggingNodeId != null ? getNodeIndex(draggingNodeId!) : -1})',
    );
    print('최종 드롭 인덱스: $finalCandidate');
    print('드래그 모드: $dragMode');
    */

    return {'dropIndex': finalCandidate};
  }

  /// 노드 ID로 현재 노드의 인덱스 찾기
  int getNodeIndex(String nodeId) {
    return editorService.editor.document.getNodeIndexById(nodeId);
  }
}
