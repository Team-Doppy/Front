import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

enum DragMode { none, reorder, imageRowMerge }

/// 노드의 글로벌 위치 정보를 관리하는 헬퍼 클래스
class NodeBounds {
  final String nodeId;
  final Offset topLeft;
  final Offset bottomRight;
  final Offset center;
  final Size size;
  final double top;
  final double bottom;
  final double left;
  final double right;

  const NodeBounds({
    required this.nodeId,
    required this.topLeft,
    required this.bottomRight,
    required this.center,
    required this.size,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });
}

class DragService extends ChangeNotifier {
  final EditorService editorService;

  String? draggingNodeId;
  NodeType? draggingNodeType;
  String? targetNodeId;
  NodeType? targetNodeType;
  DragMode dragMode = DragMode.none;

  Offset? dragPosition;
  int? dropIndex;
  Offset? lastMovedPosition;

  // 캐싱 시스템
  final Map<String, NodeBounds> _nodeBoundsCache = {};
  bool _cacheValid = false;
  int _lastDocumentLength = 0;

  DragService({required this.editorService});

  void startDrag(String nodeId, BuildContext context, Offset globalPosition) {
    _rebuildCache(); // 드래그 시작 시 캐시 구축

    draggingNodeId = nodeId;
    draggingNodeType = editorService.getNodeType(nodeId);
    dragPosition = globalPosition;
    lastMovedPosition = globalPosition;

    final dropInfo = computeDropInfo(globalPosition);
    if (dropInfo != null) {
      dropIndex = dropInfo['dropIndex'] as int?;
    }

    notifyListeners();
  }

  void updateDrag(Offset globalPosition, BuildContext context) {
    Map<String, dynamic>? dropInfo;
    dragPosition = globalPosition;
    if (lastMovedPosition != null &&
        (lastMovedPosition! - globalPosition).distance > 20) {
      lastMovedPosition = globalPosition;
      dropInfo = computeDropInfo(globalPosition);
    }

    if (dropInfo != null) {
      if (dropInfo['dropIndex'] != null) {
        final newDropIndex = dropInfo['dropIndex'] as int;
        dropIndex = newDropIndex;
      } else {
        dropIndex = null;
      }
    }

    // 드래그 모드 결정
    if (dropIndex == null) {
      dragMode = DragMode.none;
    } else if ((draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow) &&
        targetNodeType == NodeType.image &&
        draggingNodeId != targetNodeId) {
      dragMode = DragMode.imageRowMerge;
    } else {
      dragMode = DragMode.reorder;
    }

    // 항상 UI 업데이트 (드래그 오버레이 부드러운 이동을 위해)
    notifyListeners();
  }

  void endDrag() {
    if (draggingNodeId == null) {
      _cleanup();
      return;
    }

    // 실제 노드 이동 실행
    switch (dragMode) {
      case DragMode.reorder:
        if (dropIndex != null) {
          editorService.reorderNode(draggingNodeId!, dropIndex!);
        }
        break;
      case DragMode.imageRowMerge:
        if (targetNodeId != null) {
          editorService.mergeImagesIntoRow(
            draggingNodeId!,
            targetNodeId!,
            isFromLeft: isDraggingFromLeft,
          );
        }
        break;
      case DragMode.none:
        break;
    }

    _cleanup();
  }

  void _cleanup() {
    draggingNodeId = null;
    draggingNodeType = null;
    targetNodeId = null;
    targetNodeType = null;
    dragMode = DragMode.none;
    dropIndex = null;
    dragPosition = null;
    lastMovedPosition = null; // 마지막 이동 위치 초기화
    _invalidateCache(); // 드래그 종료 시 캐시 정리
    notifyListeners();
  }

  /// 드래그 방향을 계산 (왼쪽에서 오는지 오른쪽에서 오는지)
  bool get isDraggingFromLeft {
    if (dragPosition == null || targetNodeId == null) {
      return true; // 기본값은 왼쪽
    }

    final targetBounds = getNodeGlobalBounds(targetNodeId!);
    if (targetBounds == null) return true;

    final targetCenterX = targetBounds.center.dx;
    final currentX = dragPosition!.dx;

    return currentX < targetCenterX; // 현재 위치가 타겟 중심보다 왼쪽이면 true
  }

  // =================== 내부 함수 ===================

  NodeBounds? getNodeGlobalBounds(String nodeId) {
    if (!_cacheValid ||
        _lastDocumentLength != editorService.editor.document.length) {
      _rebuildCache();
    }

    return _nodeBoundsCache[nodeId];
  }

  void _invalidateCache() {
    _cacheValid = false;
    _nodeBoundsCache.clear();
  }

  void _rebuildCache() {
    _nodeBoundsCache.clear();
    _lastDocumentLength = editorService.editor.document.length;

    for (final node in editorService.editor.document) {
      final bounds = _calculateNodeBounds(node);
      if (bounds != null) {
        _nodeBoundsCache[node.id] = bounds;
      }
    }
    _cacheValid = true;
  }

  NodeBounds? _calculateNodeBounds(DocumentNode node) {
    final documentLayout =
        editorService.documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return null;

    // RenderBox를 통해 정확한 글로벌 좌표 계산
    final renderObject =
        editorService.documentLayoutKey?.currentContext?.findRenderObject();
    RenderBox? renderBox;
    if (renderObject is RenderSliverToBoxAdapter) {
      renderBox = renderObject.child;
    } else if (renderObject is RenderBox) {
      renderBox = renderObject;
    }
    if (renderBox == null) return null;

    for (double y = 0; y < 2000; y += 5) {
      final testPosition = documentLayout.getDocumentPositionNearestToOffset(
        Offset(0, y),
      );
      if (testPosition?.nodeId == node.id) {
        final startRect = documentLayout.getRectForPosition(testPosition!);
        if (startRect != null) {
          // 노드의 끝 위치 찾기
          Rect? endRect = startRect;
          for (double checkY = y + 5; checkY < y + 500; checkY += 5) {
            final checkPosition = documentLayout
                .getDocumentPositionNearestToOffset(Offset(0, checkY));
            if (checkPosition?.nodeId == node.id) {
              final checkRect = documentLayout.getRectForPosition(
                checkPosition!,
              );
              if (checkRect != null) {
                endRect = checkRect;
              }
            } else {
              break;
            }
          }

          // DocumentLayout의 로컬 좌표를 글로벌 좌표로 변환
          final globalTopLeft = renderBox.localToGlobal(startRect.topLeft);
          final globalBottomRight = renderBox.localToGlobal(
            endRect?.bottomRight ?? startRect.bottomRight,
          );

          return NodeBounds(
            nodeId: node.id,
            topLeft: globalTopLeft,
            bottomRight: globalBottomRight,
            center: Offset(
              (globalTopLeft.dx + globalBottomRight.dx) / 2,
              (globalTopLeft.dy + globalBottomRight.dy) / 2,
            ),
            size: Size(
              globalBottomRight.dx - globalTopLeft.dx,
              globalBottomRight.dy - globalTopLeft.dy,
            ),
            top: globalTopLeft.dy,
            bottom: globalBottomRight.dy,
            left: globalTopLeft.dx,
            right: globalBottomRight.dx,
          );
        }
      }
    }

    return null;
  }

  /// 드롭 인덱스와 라인 위치를 한 번에 계산
  Map<String, dynamic>? computeDropInfo(Offset globalPosition) {
    // 글로벌 좌표를 그대로 사용 (이미 글로벌 좌표이므로)
    final correctedPosition = globalPosition;

    // 타겟 노드 찾기 (이미지 겹침 감지를 위해)
    DocumentNode? targetNode;
    for (final node in editorService.editor.document) {
      final bounds = getNodeGlobalBounds(node.id);
      if (bounds != null &&
          correctedPosition.dx >= bounds.left &&
          correctedPosition.dx <= bounds.right &&
          correctedPosition.dy >= bounds.top &&
          correctedPosition.dy <= bounds.bottom) {
        targetNode = node;
        break;
      }
    }

    int index = 0;
    int? candidate;
    Offset? linePosition;

    // 현재 드래그 중인 노드의 인덱스 찾기
    int draggingNodeIndex = -1;
    if (draggingNodeId != null) {
      for (int i = 0; i < editorService.editor.document.length; i++) {
        if (editorService.editor.document.getNodeAt(i)?.id == draggingNodeId) {
          draggingNodeIndex = i;
          break;
        }
      }
    }

    for (final node in editorService.editor.document) {
      final bounds = getNodeGlobalBounds(node.id);
      if (bounds == null) {
        index += 1;
        continue;
      }

      final top = bounds.top;
      final bottom = bounds.bottom;
      final center = bounds.center;

      if (correctedPosition.dy < top) {
        candidate = index;
        linePosition = Offset(0, top - 1);
        break;
      }

      if (correctedPosition.dy >= top && correctedPosition.dy <= bottom) {
        candidate = correctedPosition.dy < center.dy ? index : index + 1;
        if (candidate == index) {
          linePosition = Offset(0, top - 1);
        } else {
          linePosition = Offset(0, bottom + 1);
        }
        break;
      }

      candidate = index + 1;
      index += 1;
    }

    // 마지막 위치 처리
    if (candidate == editorService.editor.document.length) {
      final lastNode = editorService.editor.document.last;
      final lastBounds = getNodeGlobalBounds(lastNode.id);
      if (lastBounds != null) {
        linePosition = Offset(0, lastBounds.bottom + 1);
      }
    }

    // 자기 자신의 위치면 드롭 인덱스 무효화
    if (draggingNodeIndex != -1 && candidate != null) {
      // 정확히 같은 위치일 때만 무효화
      if (candidate == draggingNodeIndex) {
        candidate = null;
        linePosition = null;
      }
    }

    // 드래그 모드 결정
    if (targetNode != null &&
        (draggingNodeType == NodeType.image ||
            draggingNodeType == NodeType.imageRow)) {
      final targetNodeType = editorService.getNodeType(targetNode.id);
      if (targetNodeType == NodeType.image) {
        dragMode = DragMode.imageRowMerge;
      } else {
        dragMode = DragMode.reorder;
      }
    } else {
      dragMode = DragMode.reorder;
    }

    // 이미지 가로 배치 모드일 때 세로 라인 정보 계산
    Map<String, dynamic>? imageRowLineInfo;
    if (dragMode == DragMode.imageRowMerge && targetNode != null) {
      final bounds = getNodeGlobalBounds(targetNode.id);
      if (bounds != null) {
        final isFromLeft = correctedPosition.dx < bounds.center.dx;
        imageRowLineInfo = {'bounds': bounds, 'isFromLeft': isFromLeft};
      }
    }

    // 타겟 노드 정보 업데이트
    if (targetNode != null) {
      targetNodeId = targetNode.id;
      targetNodeType = editorService.getNodeType(targetNode.id);
    } else {
      targetNodeId = null;
      targetNodeType = null;
    }

    return {
      'dropIndex': candidate,
      'linePosition': linePosition,
      'imageRowLineInfo': imageRowLineInfo,
    };
  }
}
