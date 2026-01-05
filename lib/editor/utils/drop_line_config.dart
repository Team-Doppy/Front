import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/editor/nodes/mention_node.dart';
import 'package:super_editor/super_editor.dart';

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

  /// MentionNode는 드롭라인 규칙에서는 "텍스트(Paragraph)"처럼 취급한다.
  /// - 즉, MentionNode 자체는 특수노드가 아니지만
  /// - 특수노드↔텍스트 경계에서 라인을 "특수노드의 bottom"으로 옮기는 예외 규칙에는 포함된다.
  static bool _isTextLikeForDropLine(DocumentNode? node) {
    return node is ParagraphNode || node is MentionNode;
  }

  /// 🎯 드롭라인 판단용 특수노드 체크
  /// MentionNode는 특수노드이지만 드롭라인 규칙에서는 일반 텍스트 노드처럼 처리
  static bool _isSpecialNodeForDropLine(DocumentNode? node) {
    if (node == null) return false;
    // MentionNode는 특수노드에서 제외 (일반 텍스트 노드처럼 처리)
    if (node is MentionNode) return false;
    return NodeTypeChecker.isSpecialNode(node);
  }

  /// 드롭 라인 표시 결과(한 노드 기준).
  ///
  /// - 핵심 입력은 `dragService.dropTarget` 하나다.
  /// - 나머지(현재 노드 인덱스/문서 길이/row fullness)는 렌더링을 위해 필요한 파생 정보.
  static ({bool top, bool bottom, bool left, bool right}) resolve({
    required String nodeId,
    required DragService? dragService,
  }) {
    if (dragService == null) {
      return (top: false, bottom: false, left: false, right: false);
    }

    // ✅ 업로드/압축(busy) 중에는 Drag&Drop 자체가 차단되므로 드롭라인도 절대 표시하지 않는다.
    // - draggingNodeId(드래그 주체) 또는 targetNodeId(현재 호버 타겟) 또는 이 nodeId 자체가 busy면 전체 off
    final draggingId = dragService.draggingNodeId;
    if (draggingId != null && dragService.isBusyRef(draggingId)) {
      return (top: false, bottom: false, left: false, right: false);
    }
    final targetId = dragService.targetNodeId;
    if (targetId != null && dragService.isBusyRef(targetId)) {
      return (top: false, bottom: false, left: false, right: false);
    }
    if (dragService.isBusyRef(nodeId)) {
      return (top: false, bottom: false, left: false, right: false);
    }

    final dt = dragService.dropTarget;
    switch (dt.kind) {
      case DropTargetKind.none:
        return (top: false, bottom: false, left: false, right: false);

      case DropTargetKind.insertBetweenNodes:
        final currentNodeIndex = dragService.getNodeIndex(nodeId);
        if (currentNodeIndex == -1) {
          return (top: false, bottom: false, left: false, right: false);
        }

        final insertIndex = dt.insertIndex;
        if (insertIndex == null) {
          return (top: false, bottom: false, left: false, right: false);
        }

        final doc = dragService.editorService.document;
        final docLen = doc.length;

        // 🎯 자기 자신을 드래그할 때 자기 위치의 드롭라인 숨김
        // - insertIndex == draggingNodeIndex: 자기 노드 위에 삽입 (원래 위치 위) → 자기 노드의 top 드롭라인 숨김
        // - insertIndex == draggingNodeIndex + 1: 자기 노드 아래에 삽입 (원래 위치 아래) → 자기 노드의 bottom 드롭라인 숨김
        // 🎯 예외: 로우 이미지 분리나 페이지뷰 분리 중에는 자기 위치에서도 드롭라인 표시 허용
        final draggingNodeId = dragService.draggingNodeId;
        if (draggingNodeId != null) {
          // 분리 작업 중이 아닐 때만 자기 위치 드롭라인 숨김
          final isSplitting =
              dragService.hasSplitImageInfo || dragService.hasSplitPageViewInfo;
          if (!isSplitting) {
            final draggingNodeIndex = dragService.getNodeIndex(draggingNodeId);
            if (draggingNodeIndex != -1) {
              // ✅ "자기 위치" 드롭라인 숨김의 기준은 "드롭라인이 실제로 표시되는 노드"다.
              // 현재 정책은 insertIndex == currentNodeIndex 인 노드의 top에 라인을 띄우므로,
              // insertIndex가 "원래 자리"(draggingIndex 또는 draggingIndex+1)일 때는
              // currentNodeIndex == insertIndex 인 노드에서 라인을 숨겨야 한다.
              final isOriginalSlot =
                  insertIndex == draggingNodeIndex ||
                  insertIndex == draggingNodeIndex + 1;
              if (isOriginalSlot) {
                // ✅ "원래 자리" 드롭라인 숨김은 라인이 어느 노드에 표시되든(텍스트 top / 특수노드 bottom)
                // 동일하게 적용되어야 한다.
                //
                // - 기본 정책: insertIndex==currentNodeIndex 인 노드의 top
                // - 예외 정책(특수노드 아래 텍스트): insertIndex==currentNodeIndex+1 인 특수노드의 bottom
                final bool isLineHostForThisInsertIndex =
                    // top 라인 host
                    currentNodeIndex == insertIndex ||
                    // bottom 라인 host (특수노드 bottom으로 옮겨 그리는 케이스)
                    (currentNodeIndex == insertIndex - 1 &&
                        currentNodeIndex + 1 < docLen &&
                        _isSpecialNodeForDropLine(
                          doc.getNodeAt(currentNodeIndex),
                        ) &&
                        _isTextLikeForDropLine(
                          doc.getNodeAt(currentNodeIndex + 1),
                        )) ||
                    // 문서 끝 삽입: 마지막 노드 bottom
                    (insertIndex == docLen && currentNodeIndex == docLen - 1);

                if (isLineHostForThisInsertIndex) {
                  return (top: false, bottom: false, left: false, right: false);
                }
              }
            }
          }
        }

        // 🎯 드롭라인 표시는 insertIndex 기준으로 계산
        // - computeDropInfo()에서 finalCandidate != null이면 DropTarget.insertBetweenNodes(validDropIndex) 설정
        // - split cancel zone에서는 finalCandidate = null이 되어 insertIndex가 설정되지 않음
        // - endDrag()에서 dragMode == DragType.reorder && validDropIndex != null이면 insertIndex 전달하여 분리
        // 따라서 insertIndex가 있으면 드롭라인 표시하고, endDrag()에서도 분리됨

        // ✅ 정책: "삽입 지점"에는 항상 수평 라인 1개만 표시한다.
        // - 일반 케이스: insertIndex == currentNodeIndex 인 노드의 "top"에만 표시 (다음 노드의 상단)
        // - 문서 끝 삽입(insertIndex == docLen): 마지막 노드의 "bottom"에만 표시
        bool top = insertIndex == currentNodeIndex;
        bool bottom = (currentNodeIndex == docLen - 1 && insertIndex == docLen);

        // ✅ 예외(요구사항):
        // 특수노드 바로 아래에 텍스트(Paragraph)가 붙어있을 때,
        // 라인을 텍스트의 top이 아니라 "특수노드의 bottom"으로 띄운다.
        //
        // 1) insertIndex == currentNodeIndex(=현재 노드 위 삽입)인데,
        //    직전 노드가 특수노드이고, 현재 노드가 텍스트(Paragraph/Mention)일 때만
        //    현재 노드의 top 라인을 숨긴다. (특수노드의 bottom 라인으로 대체될 예정)
        //    🎯 단, 현재 노드가 특수노드(이미지 등)이면 top 라인을 유지한다.
        //    🎯 MentionNode는 특수노드에서 제외 (일반 텍스트 노드처럼 처리)
        if (top && currentNodeIndex - 1 >= 0) {
          final prev = doc.getNodeAt(currentNodeIndex - 1);
          final currentNode = doc.getNodeAt(currentNodeIndex);
          // 직전이 특수노드(드롭라인 판단용)이고, 현재가 텍스트(Paragraph/Mention)일 때만 top 숨김
          if (_isSpecialNodeForDropLine(prev) &&
              _isTextLikeForDropLine(currentNode)) {
            top = false;
          }
        }

        // 2) 현재 노드가 특수노드(드롭라인 판단용)이고 insertIndex == currentNodeIndex + 1(=현재 노드 아래 삽입)이며,
        //    아래 노드가 "텍스트(Paragraph/Mention)"면 현재 특수노드 bottom 라인을 띄운다.
        //    (빈 문단도 포함 - 사용자 요구사항)
        //    🎯 MentionNode는 특수노드에서 제외 (일반 텍스트 노드처럼 처리)
        if (!bottom &&
            insertIndex == currentNodeIndex + 1 &&
            _isSpecialNodeForDropLine(doc.getNodeAt(currentNodeIndex))) {
          final next =
              (currentNodeIndex + 1 < docLen)
                  ? doc.getNodeAt(currentNodeIndex + 1)
                  : null;
          if (_isTextLikeForDropLine(next)) {
            bottom = true;
          }
        }

        return (top: top, bottom: bottom, left: false, right: false);

      case DropTargetKind.mergeIntoRow:
        // 🎯 mergeIntoRow는 싱글 이미지/로우 모두에서 쓰이므로 targetNodeId 우선, 없으면 targetRowId로 폴백
        final targetId = dt.targetNodeId ?? dt.targetRowId;
        if (targetId != nodeId) {
          return (top: false, bottom: false, left: false, right: false);
        }

        // 🎯 이미 3개가 다 차있는 로우 이미지에는 양옆 드롭라인 숨김
        final targetNode = dragService.editorService.document.getNodeById(
          nodeId,
        );
        if (targetNode is ImageRowNode && targetNode.imageUrls.length >= 3) {
          return (top: false, bottom: false, left: false, right: false);
        }

        final isFromLeft = dt.isFromLeft;
        return (
          top: false,
          bottom: false,
          left: isFromLeft == true,
          right: isFromLeft == false,
        );
      case DropTargetKind.mergeIntoPageView:
        // PageView 병합 모드: 드롭 라인 표시 안 함 (병합은 내부 인덱스로 처리)
        if (dt.targetRowId != nodeId) {
          return (top: false, bottom: false, left: false, right: false);
        }
        // 🎯 이미 6개가 다 차있는 PageView에는 드롭라인 숨김
        final targetNode = dragService.editorService.document.getNodeById(
          nodeId,
        );
        if (targetNode is PageViewImageNode &&
            targetNode.imageUrls.length >= 6) {
          return (top: false, bottom: false, left: false, right: false);
        }
        // PageView 병합 모드는 시각적 드롭 라인 없이 처리
        return (top: false, bottom: false, left: false, right: false);
      case DropTargetKind.mergeMentions:
        // 멘션 병합 미리보기: 수평 드롭라인 대신 멘션 컴포넌트 하이라이트로 처리
        return (top: false, bottom: false, left: false, right: false);
    }
  }

  /// ===== 위쪽 드롭 라인 =====
  static bool shouldShowTopDropLine({
    required String nodeId,
    required DragService? dragService,
    // ignore: unused_parameter
    bool isRowImage = false, // 🎯 기존 시그니처 유지
  }) {
    return resolve(nodeId: nodeId, dragService: dragService).top;
  }

  /// ===== 아래쪽 드롭 라인 =====
  static bool shouldShowBottomDropLine({
    required String nodeId,
    required DragService? dragService,
    // ignore: unused_parameter
    bool isRowImage = false, // 🎯 기존 시그니처 유지
  }) {
    return resolve(nodeId: nodeId, dragService: dragService).bottom;
  }

  /// ===== 좌우 세로 라인 (이미지 병합용) =====

  /// 왼쪽 세로 라인을 표시해야 하는지 확인
  static bool shouldShowLeftVerticalLine({
    required String nodeId,
    required DragService? dragService,
  }) {
    return resolve(nodeId: nodeId, dragService: dragService).left;
  }

  /// 오른쪽 세로 라인을 표시해야 하는지 확인
  static bool shouldShowRightVerticalLine({
    required String nodeId,
    required DragService? dragService,
  }) {
    return resolve(nodeId: nodeId, dragService: dragService).right;
  }
}
