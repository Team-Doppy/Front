import 'package:flutter/material.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/widgets/drag_overlay_widget.dart';
import '../../editor/service/drag_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/style/style_sheet.dart';
import '../config/editor_config.dart' as NodeTypeChecker;
import 'package:super_editor/super_editor.dart';

/// PostwriteScreen의 UI 빌드 및 이벤트 핸들링 관련 기능을 분리한 mixin
mixin PostwriteScreenUI<T extends StatefulWidget> on State<T> {
  // Required getters - State 클래스에서 제공해야 함
  bool get mounted;
  FocusNode get editorFocusNode;
  DragService get dragService;
  EditorService get editorService;
  NodeComponentService get nodeComponentService;
  MutableDocument get document;
  GlobalKey get editorBodyStackKey;

  /// 스타일시트 빌드
  Stylesheet buildStylesheet(BuildContext context) {
    return buildCustomStylesheet(context).copyWith(
      documentPadding: const EdgeInsets.only(
        top: 10,
        left: 0,
        right: 0,
        bottom: 100,
      ),
    );
  }

  /// 드래그 오버레이 빌드
  Widget buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

    // DragService는 globalPosition을 저장한다.
    // 하지만 DragOverlayWidget은 현재 Stack(=Scaffold body) 좌표계를 기준으로 Positioned 된다.
    // 따라서 global -> local 변환을 하지 않으면 손가락을 "안 따라오는 것처럼" 보일 수 있다.
    final RenderBox? overlayBox =
        editorBodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset localPos = overlayBox != null
        ? overlayBox.globalToLocal(pos)
        : pos;

    // 이미지 행 분리 모드
    if (dragService.hasSplitImageInfo) {
      final splitInfo = dragService.getSplitImageInfo();
      final rowNode =
          document.getNodeById(splitInfo?['rowId']) as ImageRowNode?;
      final imageIndex = splitInfo?['imageIndex'] as int?;

      if (rowNode != null &&
          imageIndex != null &&
          imageIndex < rowNode.imageUrls.length) {
        return DragOverlayWidget(
          position: localPos,
          document: document,
          splitImageUrl: rowNode.imageUrls[imageIndex],
        );
      }
    }

    // PageView 이미지 분리 모드
    if (dragService.isPageViewItemDrag) {
      final pageViewNode =
          document.getNodeById(dragService.subjectPageViewId ?? '')
              as PageViewImageNode?;
      final imageIndex = dragService.subjectPageViewImageIndex;

      if (pageViewNode != null &&
          imageIndex != null &&
          imageIndex >= 0 &&
          imageIndex < pageViewNode.imageUrls.length) {
        return DragOverlayWidget(
          position: localPos,
          document: document,
          splitImageUrl: pageViewNode.imageUrls[imageIndex],
        );
      }
    }

    // 일반 노드 드래그
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    return DragOverlayWidget(
      node: node,
      position: localPos,
      document: document,
      previewImageUrl: dragService.previewImageUrl,
      previewImageLocalPath: dragService.previewImageLocalPath,
    );
  }

  /// 노드 선택 변경 리스너 (키보드 숨김용)
  void onNodeSelectionChanged() {
    if (mounted && nodeComponentService.selectedNodeId != null) {
      editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  /// 마지막 특수 노드 아래 탭 처리
  void handleTapBelowLastSpecialNode(Offset globalPosition) {
    dragService.invalidateNodeRectCache();

    final lastIndex = document.nodeCount - 1;
    if (lastIndex < 0) {
      return;
    }

    final lastNode = document.getNodeAt(lastIndex);
    if (lastNode == null) {
      return;
    }

    final isSpecial = NodeTypeChecker.isSpecialNode(lastNode);
    if (!isSpecial) {
      return;
    }

    final lastNodeRect = dragService.getNodeGlobalRect(lastNode.id);
    if (lastNodeRect == null) {
      return;
    }

    final tapY = globalPosition.dy;
    final isBelowNode = tapY > lastNodeRect.bottom;

    if (isBelowNode) {
      final hitTestResult = editorService.findNodeByHitTest(
        globalPosition,
        dragService,
      );

      // consider empty space if hit test result is null or last node
      final isEmpty =
          hitTestResult == null ||
          hitTestResult.key == null ||
          hitTestResult.key!.id == lastNode.id;

      if (isEmpty) {
        editorService.insertEmptyParagraphAtIndex(lastIndex + 1);
        nodeComponentService.selectNode(null);
      }
    }
  }
}
