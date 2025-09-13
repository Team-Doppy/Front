import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';

/// 패키지 기본 ParagraphComponent를 사용하고,
/// 드래그 드롭 라인만 오버레이로 추가하는 경량 커스텀 빌더
class CustomParagraphComponentBuilder implements ComponentBuilder {
  const CustomParagraphComponentBuilder({
    required this.dragService,
    required this.editorService,
  });

  final DragService dragService;
  final EditorService editorService;
  static const ParagraphComponentBuilder _defaultBuilder =
      ParagraphComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    // 기본 빌더에 위임 (패키지 ParagraphNode만 대상)
    final result = _defaultBuilder.createViewModel(document, node);
    return result;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    // 문단이 아닌 경우 래핑 불필요
    if (componentViewModel is! ParagraphComponentViewModel) {
      return _defaultBuilder.createComponent(
        componentContext,
        componentViewModel,
      );
    }

    // 구분선 문단은 전용 DocumentComponent로 교체 (DocumentComponent 필요)
    try {
      final node = editorService.editor.document.getNodeById(
        componentViewModel.nodeId,
      );
      if (node is ParagraphNode && node.metadata['isDivider'] == true) {
        return _DividerDocumentComponent(
          nodeId: componentViewModel.nodeId,
          componentKey: componentContext.componentKey,
        );
      }
    } catch (_) {}

    // 기본 컴포넌트 생성
    final child = _defaultBuilder.createComponent(
      componentContext,
      componentViewModel,
    );
    if (child == null) return null;

    // 드래그 라인만 덧씌우는 얇은 래퍼
    return _ParagraphWithDropLines(
      nodeId: componentViewModel.nodeId,
      dragService: dragService,
      editorService: editorService,
      child: child,
    );
  }
}

class _ParagraphWithDropLines extends StatelessWidget {
  const _ParagraphWithDropLines({
    required this.nodeId,
    required this.dragService,
    required this.editorService,
    required this.child,
  });

  final String nodeId;
  final DragService dragService;
  final EditorService editorService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([dragService, editorService]),
      builder: (context, _) {
        final currentIndex = dragService.getNodeIndex(nodeId);
        final dropIndex = dragService.dropIndex;
        final isSelf = dragService.draggingNodeId == nodeId;
        final showTop =
            dropIndex != null &&
            !isSelf &&
            currentIndex != -1 &&
            dropIndex == currentIndex;

        // 중앙집중 규칙에 따른 텍스트 마진 적용
        final EdgeInsets margin = editorService.getParagraphMargin(nodeId);

        Widget content = DefaultTextStyle.merge(
          textAlign: _resolveTextAlign(),
          child: child,
        );

        return Stack(
          children: [
            Padding(padding: margin, child: content),
            if (showTop)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 3, color: AppColors.primary),
              ),

            // 하단 라인 비활성화(이중 라인 방지)
          ],
        );
      },
    );
  }

  TextAlign _resolveTextAlign() {
    TextAlign resolvedAlign = TextAlign.left;
    try {
      final node = editorService.editor.document.getNodeById(nodeId);
      if (node is ParagraphNode) {
        final alignName = node.metadata['textAlign'] as String?;
        if (alignName == 'center') {
          resolvedAlign = TextAlign.center;
        } else if (alignName == 'right') {
          resolvedAlign = TextAlign.right;
        } else if (alignName == 'left') {
          resolvedAlign = TextAlign.left;
        }
      }
    } catch (_) {}
    return resolvedAlign;
  }
}

/// 구분선 전용 DocumentComponent
class _DividerDocumentComponent extends StatefulWidget {
  const _DividerDocumentComponent({
    required this.nodeId,
    required GlobalKey componentKey,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final GlobalKey _componentKey;

  @override
  State<_DividerDocumentComponent> createState() =>
      _DividerDocumentComponentState();
}

class _DividerDocumentComponentState extends State<_DividerDocumentComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: double.infinity,
        height: 1.5,
        color: const Color(0xFFE5E5EA),
      ),
    );
  }

  // Minimal DocumentComponent implementation
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
    if (renderBox == null) return Rect.zero;
    return Offset.zero & renderBox.size;
  }

  @override
  Rect getRectForSelection(
    NodePosition baseNodePosition,
    NodePosition extentNodePosition,
  ) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return Rect.zero;
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
    if (renderBox == null) return Rect.zero;
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
      UpstreamDownstreamNodePosition.upstream();

  @override
  NodePosition getEndPositionNearX(double x) =>
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;
}
