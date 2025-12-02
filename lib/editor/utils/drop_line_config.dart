import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';

/// 🎯 드롭 라인 표시 규칙을 중앙에서 관리하는 Config
/// 모든 컴포넌트(SingleImage, RowImage, PageViewImage, Clip, Link)가 이 규칙을 주입받아 사용
///
/// 📌 로우 이미지 분리 시 특수 규칙:
/// 1. **분리 대상 노드만** 상단/하단 라인 표시 (draggingNodeId == nodeId)
/// 2. 분리 대상 노드 위의 노드는 하단 라인 숨김 (중복 방지)
/// 3. 다른 모든 노드는 드롭 라인 숨김
/// 4. 병합 모드 전환 시 세로 라인 표시
///
/// 📌 엣지 케이스 처리:
/// - 첫 번째 노드 분리: 상단 라인만 표시
/// - 마지막 노드 분리: 상단/하단 라인 모두 표시
/// - 다음이 특수 노드: 하단 라인 표시 (경계 구분)
/// - 연속된 특수 노드: 각 노드의 경계 라인 표시
/// - 텍스트 노드 사이: 경계 라인 표시
class DropLineConfig {
  DropLineConfig._();

  /// ===== 위쪽 드롭 라인 =====

  /// 위쪽 드롭 라인을 표시해야 하는지 확인
  static bool shouldShowTopDropLine({
    required String nodeId,
    required DragService? dragService,
    bool isRowImage = false, // 🎯 RowImageComponent인 경우 true
  }) {
    if (dragService == null) return false;
    final dropIndex = dragService.dropIndex;
    if (dropIndex == null) return false;

    final currentNodeIndex = dragService.getNodeIndex(nodeId);
    if (currentNodeIndex == -1) return false;

    // 🎯 로우 이미지 분리 시: **분리 대상 노드만** 예외 처리
    if (isRowImage && dragService.hasSplitImageInfo) {
      // 🎯 분리 대상 노드인지 확인 (draggingNodeId == 현재 nodeId)
      final isSplitTarget = dragService.draggingNodeId == nodeId;
      if (isSplitTarget && dropIndex == currentNodeIndex) {
        return true; // 분리 대상 노드의 위쪽 라인 표시
      }
    }

    // 이 노드 위에 삽입하는 경우
    if (dropIndex == currentNodeIndex) {
      return _shouldShowTopInsertionLine(
        currentNodeIndex: currentNodeIndex,
        dragService: dragService,
        nodeId: nodeId,
      );
    }
    return false;
  }

  /// 위쪽 삽입 라인 표시 여부
  static bool _shouldShowTopInsertionLine({
    required int currentNodeIndex,
    required DragService dragService,
    required String nodeId,
  }) {
    final doc = dragService.editorService.document;

    // 🎯 규칙 1: 이전 노드가 특수 노드이면 숨김
    // (특수 노드가 아래쪽 라인을 표시하므로 중복 방지)
    if (currentNodeIndex > 0) {
      final prevNode = doc.getNodeAt(currentNodeIndex - 1);
      if (NodeTypeChecker.isSpecialNode(prevNode)) {
        return false;
      }
    }

    return true;
  }

  /// ===== 아래쪽 드롭 라인 =====

  /// 아래쪽 드롭 라인을 표시해야 하는지 확인
  static bool shouldShowBottomDropLine({
    required String nodeId,
    required DragService? dragService,
    bool isRowImage = false, // 🎯 RowImageComponent인 경우 true
  }) {
    if (dragService == null) return false;
    final dropIndex = dragService.dropIndex;
    if (dropIndex == null) return false;

    final currentNodeIndex = dragService.getNodeIndex(nodeId);
    if (currentNodeIndex == -1) return false;

    final documentLength = dragService.editorService.document.length;
    final isLastNode = currentNodeIndex == documentLength - 1;

    // 🎯 로우 이미지 분리 시: **분리 대상 노드의 하단 라인도 표시**
    if (isRowImage && dragService.hasSplitImageInfo) {
      final isSplitTarget = dragService.draggingNodeId == nodeId;
      if (isSplitTarget && dropIndex == currentNodeIndex + 1) {
        return true; // 분리 대상 노드의 하단 라인 표시
      }
    }

    if (isLastNode) {
      // 마지막 노드일 때는 문서 끝에 삽입하는 경우
      return dropIndex == documentLength;
    } else {
      // 다음 인덱스에 삽입하는 경우
      if (dropIndex == currentNodeIndex + 1) {
        return _shouldShowBottomInsertionLine(
          currentNodeIndex: currentNodeIndex,
          dragService: dragService,
          nodeId: nodeId,
        );
      }
    }
    return false;
  }

  /// 아래쪽 삽입 라인 표시 여부
  static bool _shouldShowBottomInsertionLine({
    required int currentNodeIndex,
    required DragService dragService,
    required String nodeId,
  }) {
    final doc = dragService.editorService.document;
    final documentLength = doc.length;

    // 🎯 규칙 0: 로우 이미지 분리 중 - 분리 대상 바로 위 노드만 특수 처리
    final hasSplitImageInfo = dragService.hasSplitImageInfo;
    if (hasSplitImageInfo) {
      final draggingNodeId = dragService.draggingNodeId;
      if (draggingNodeId != null) {
        final draggingNodeIndex = doc.getNodeIndexById(draggingNodeId);

        // 🎯 분리 대상 노드의 바로 위 노드면 숨김
        // (분리 대상 노드가 상단 라인을 표시하므로 중복 방지)
        if (draggingNodeIndex != -1 &&
            currentNodeIndex == draggingNodeIndex - 1) {
          return false;
        }
        // 나머지 노드들은 일반 규칙 적용 (아래로 계속 진행)
      }
    }

    // 🎯 규칙 1: 다음 노드 확인 (일반 드래그)
    if (currentNodeIndex + 1 < documentLength) {
      final nextNode = doc.getNodeAt(currentNodeIndex + 1);

      // 다음이 특수 노드이면 숨김 (특수 노드는 자신의 상단 라인을 표시)
      if (NodeTypeChecker.isSpecialNode(nextNode)) {
        return false;
      }

      // 다음이 텍스트 노드이면 표시
      if (NodeTypeChecker.isTextNode(nextNode)) {
        return true;
      }
    }

    return false;
  }

  /// ===== 좌우 세로 라인 (이미지 병합용) =====

  /// 왼쪽 세로 라인을 표시해야 하는지 확인
  static bool shouldShowLeftVerticalLine({
    required String nodeId,
    required DragService? dragService,
  }) {
    if (dragService == null) return false;
    if (dragService.draggingNodeId == null) return false;
    if (dragService.dragPosition == null) return false;

    // 자기 자신을 드래그하는 경우 숨김
    if (dragService.draggingNodeId == nodeId) {
      return false;
    }

    // 현재 노드가 타겟 노드가 아니면 숨김
    if (dragService.targetNodeId != nodeId) {
      return false;
    }

    // dragMode가 imageRowMerge가 아니면 숨김
    if (dragService.dragMode != DragType.imageRowMerge) {
      return false;
    }

    // 왼쪽에서 드래그하는 경우만 표시
    return dragService.isDraggingFromLeft;
  }

  /// 오른쪽 세로 라인을 표시해야 하는지 확인
  static bool shouldShowRightVerticalLine({
    required String nodeId,
    required DragService? dragService,
  }) {
    if (dragService == null) return false;
    if (dragService.draggingNodeId == null) return false;
    if (dragService.dragPosition == null) return false;

    // 자기 자신을 드래그하는 경우 숨김
    if (dragService.draggingNodeId == nodeId) {
      return false;
    }

    // 현재 노드가 타겟 노드가 아니면 숨김
    if (dragService.targetNodeId != nodeId) {
      return false;
    }

    // dragMode가 imageRowMerge가 아니면 숨김
    if (dragService.dragMode != DragType.imageRowMerge) {
      return false;
    }

    // 오른쪽에서 드래그하는 경우만 표시
    return !dragService.isDraggingFromLeft;
  }
}
