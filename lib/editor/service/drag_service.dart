import 'dart:async';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

enum DragType { none, reorder, imageRowMerge }

class DragService extends ChangeNotifier {
  final EditorService editorService;
  ScrollController? scrollController;

  String? draggingNodeId;
  NodeType? draggingNodeType;
  String? targetNodeId;
  NodeType? targetNodeType;
  DragType dragMode = DragType.none;

  Offset? dragPosition;
  int? dropIndex;
  Offset? lastMovedPosition;

  // Auto-scroll state
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0.0; // -1: up, 1: down, 0: none

  DragService({required this.editorService, this.scrollController});

  void attachScrollController(ScrollController controller) {
    scrollController = controller;
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
    // dropIndex가 null일 때만 모드를 none으로 변경
    if (dropIndex == null) {
      dragMode = DragType.none;
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
    if (draggingNodeId == null) {
      _cleanup();
      return;
    }

    print('=== 드래그 종료 ===');
    print('드래그 모드: $dragMode');
    print('드래그 중인 노드: $draggingNodeId');
    print('타겟 노드: $targetNodeId');
    print('드롭 인덱스: $dropIndex');

    // 실제 노드 이동 실행
    switch (dragMode) {
      case DragType.reorder:
        if (dropIndex != null) {
          print('노드 재정렬 실행: $draggingNodeId -> 인덱스 $dropIndex');
          editorService.reorderNode(draggingNodeId!, dropIndex!);
        }
        break;
      case DragType.imageRowMerge:
        if (targetNodeId != null) {
          print(
            '이미지 행 병합 실행: $draggingNodeId + $targetNodeId (왼쪽에서: $isDraggingFromLeft)',
          );
          editorService.mergeImagesIntoRow(
            draggingNodeId!,
            targetNodeId!,
            isFromLeft: isDraggingFromLeft,
          );
        } else {
          print('타겟 노드가 null이어서 병합 실행 안됨');
        }
        break;
      case DragType.none:
        print('드래그 모드가 none이어서 아무것도 실행 안됨');
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

    // 문서 레이아웃의 로컬 좌표로 변환해서 화면 중앙 기준으로 좌/우 판정
    final renderObject =
        editorService.documentLayoutKey?.currentContext?.findRenderObject();
    RenderBox? renderBox;
    if (renderObject is RenderSliverToBoxAdapter) {
      renderBox = renderObject.child;
    } else if (renderObject is RenderBox) {
      renderBox = renderObject;
    }
    if (renderBox == null) return true;

    final local = renderBox.globalToLocal(dragPosition!);
    final halfWidth = renderBox.size.width / 2;
    return local.dx < halfWidth;
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
    final position = documentLayout.getDocumentPositionNearestToOffset(
      localPosition,
    );
    if (position == null) return null;

    final node = editorService.editor.document.getNodeById(position.nodeId);
    if (node == null) return null;

    // 노드 인덱스 찾기
    final nodeIndex = editorService.editor.document.getNodeIndexById(node.id);
    if (nodeIndex == -1) return null;

    // 드롭 인덱스 계산
    int? finalCandidate = nodeIndex;
    if (draggingNodeId != null) {
      final draggingNodeIndex = editorService.editor.document.getNodeIndexById(
        draggingNodeId!,
      );
      if (draggingNodeIndex != -1) {
        // 자기 자신의 위치만 드롭 인덱스 무효화 (바로 위아래는 허용)
        if (nodeIndex == draggingNodeIndex) {
          finalCandidate = null;
        } else if (draggingNodeIndex < nodeIndex) {
          // 드래그 중인 노드가 타겟 노드보다 앞에 있으면, 타겟 노드 앞에 삽입
          finalCandidate = nodeIndex;
        } else {
          // 드래그 중인 노드가 타겟 노드보다 뒤에 있으면, 타겟 노드 앞에 삽입
          finalCandidate = nodeIndex;
        }
      }
    } else {
      finalCandidate = nodeIndex;
    }

    // 맨 위 삽입을 위한 특별 처리
    if (finalCandidate == 0) {
      finalCandidate = 0;
    }

    // 드래그 모드 결정 (단일 이미지 또는 이미지 행 모두 가로배치 합치기 허용)
    final targetNodeType = editorService.getNodeType(node.id);
    if ((targetNodeType == NodeType.image ||
            targetNodeType == NodeType.imageRow) &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow) &&
        draggingNodeId != node.id) {
      dragMode = DragType.imageRowMerge;
    } else {
      dragMode = DragType.reorder;
    }

    // 타겟 노드 정보 업데이트
    targetNodeId = node.id;
    this.targetNodeType = targetNodeType;

    // 디버그 로그
    print('=== 드롭 인덱스 계산 ===');
    print('글로벌 좌표: $globalPosition');
    print('로컬 좌표: $localPosition');
    print(
      '드래그 중인 노드: $draggingNodeId (인덱스: ${draggingNodeId != null ? getNodeIndex(draggingNodeId!) : -1})',
    );
    print('타겟 노드: $targetNodeId (인덱스: $nodeIndex)');
    print('최종 드롭 인덱스: $finalCandidate');
    print('드래그 모드: $dragMode');

    return {'dropIndex': finalCandidate};
  }

  /// 노드 ID로 현재 노드의 인덱스 찾기
  int getNodeIndex(String nodeId) {
    return editorService.editor.document.getNodeIndexById(nodeId);
  }
}
