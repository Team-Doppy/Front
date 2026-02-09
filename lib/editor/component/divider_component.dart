import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:provider/provider.dart';

// 언급 블록 노드
class DividerNode extends BlockNode {
  DividerNode({required this.id, Map<String, dynamic>? metadata})
    : _metadata = metadata ?? {};

  @override
  final String id;

  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

  @override
  bool get isDeletable => true;

  @override
  bool containsPosition(Object position) =>
      position is UpstreamDownstreamNodePosition;

  @override
  UpstreamDownstreamNodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    return UpstreamDownstreamNodeSelection(
      base: base as UpstreamDownstreamNodePosition,
      extent: extent as UpstreamDownstreamNodePosition,
    );
  }

  @override
  UpstreamDownstreamNodePosition selectDownstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.upstream();

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      DividerNode(id: id, metadata: newMetadata);

  @override
  String? copyContent(NodeSelection selection) => null;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      DividerNode(id: id, metadata: {..._metadata, ...newProperties});
}

class DividerComponentViewModel extends SingleColumnLayoutComponentViewModel {
  DividerComponentViewModel({
    required super.nodeId,
    required this.mainAxis,
    this.templateText,
    this.textAlign,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final MainAxisAlignment mainAxis;
  final String? templateText;
  final TextAlign? textAlign;

  @override
  SingleColumnLayoutComponentViewModel copy() => DividerComponentViewModel(
    nodeId: nodeId,
    mainAxis: mainAxis,
    templateText: templateText,
    textAlign: textAlign,
  );
}

class DividerComponentBuilder implements ComponentBuilder {
  const DividerComponentBuilder({
    this.dragService,
    this.editor,
    this.focusNode,
  });
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is DividerComponentViewModel) {
      return _DividerComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        mainAxis: viewModel.mainAxis,
        templateText: viewModel.templateText,
        textAlign: viewModel.textAlign,
        dragService: dragService,
        editor: editor,
        focusNode: focusNode,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is DividerNode) {
      // ✅ 템플릿 텍스트가 있으면 metadata에서 읽기
      final templateText = node.metadata['templateText'] as String?;
      // ✅ 텍스트 정렬 읽기 (템플릿 노드일 때만 적용)
      TextAlign? textAlign;
      if (templateText != null) {
        // 1) node 자체 메타 우선
        String? alignStr = node.metadata['textAlign'] as String?;

        // 2) 없으면 주변 ParagraphNode의 정렬을 승계 (정렬 버튼이 Paragraph만 갱신하는 케이스 포함)
        if (alignStr == null || alignStr.isEmpty) {
          final int idx = document.getNodeIndexById(node.id);
          if (idx != -1) {
            // 이전 문단 우선
            for (int i = idx - 1; i >= 0; i--) {
              final prev = document.getNodeAt(i);
              if (prev is ParagraphNode) {
                alignStr = prev.metadata['textAlign'] as String?;
                break;
              }
            }
            // 다음 문단 보조
            if (alignStr == null || alignStr.isEmpty) {
              for (int i = idx + 1; i < document.length; i++) {
                final next = document.getNodeAt(i);
                if (next is ParagraphNode) {
                  alignStr = next.metadata['textAlign'] as String?;
                  break;
                }
              }
            }
          }
        }

        // 3) 최종 파싱 (기본값 center)
        switch (alignStr) {
          case 'left':
            textAlign = TextAlign.left;
            break;
          case 'right':
            textAlign = TextAlign.right;
            break;
          case 'center':
          default:
            textAlign = TextAlign.center;
        }
      }
      // ✅ 디바이더는 항상 가운데 정렬만 유지
      return DividerComponentViewModel(
        nodeId: node.id,
        mainAxis: MainAxisAlignment.center,
        templateText: templateText,
        textAlign: textAlign,
      );
    }
    return null;
  }
}

class _DividerComponent extends StatefulWidget {
  const _DividerComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.mainAxis,
    this.templateText,
    this.textAlign,
    this.dragService,
    this.editor,
    this.focusNode,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final MainAxisAlignment mainAxis;
  final String? templateText;
  final TextAlign? textAlign;
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;

  @override
  State<_DividerComponent> createState() => _DividerComponentState();
}

class _DividerComponentState extends State<_DividerComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    // ✅ 템플릿 텍스트가 있으면 텍스트 표시, 없으면 구분선 표시
    final Widget content;
    if (widget.templateText != null) {
      // ✅ 선택 상태 확인
      final isSelected = context.select<NodeComponentService, bool>(
        (service) => service.selectedImageId == widget.nodeId,
      );

      final colorScheme = Theme.of(context).colorScheme;
      // ✅ 선택되었을 때는 primary 색상, 아니면 onSurface with opacity
      final textColor =
          isSelected
              ? colorScheme.primary
              : colorScheme.onSurface.withOpacity(0.6);

      // ✅ 텍스트 정렬 적용 (템플릿 노드일 때만)
      final textAlign = widget.textAlign ?? TextAlign.left;
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Text(
          widget.templateText!,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: textColor,
            height: 1.5,
          ),
        ),
      );
    } else {
      final pillContent = Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 150,
                height: 1.5,
                color: AppColors.darkTextSecondary,
              ),
            ),
          ],
        ),
      );
      content = pillContent;
    }

    final aligned =
        widget.templateText != null
            ? content
            : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [content],
            );

    final tappable =
        widget.editor == null
            ? aligned
            : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              child: aligned,
            );

    if (widget.dragService == null) return tappable;

    return AnimatedBuilder(
      animation: widget.dragService!,
      builder: (context, _) {
        return Stack(
          children: [
            tappable,
            if (_shouldShowTopDropLine())
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedDropLine(
                  child: Container(
                    height: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            if (_shouldShowBottomDropLine())
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedDropLine(
                  child: Container(
                    height: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleTap() {
    final editor = widget.editor;
    if (editor == null) return;

    // ✅ 템플릿 노드일 때는 특수 노드처럼 선택 처리
    if (widget.templateText != null && widget.dragService != null) {
      try {
        final nodeService = context.read<NodeComponentService>();
        final currentSelected = nodeService.selectedImageId;

        if (currentSelected == widget.nodeId) {
          // 같은 노드 재탭: 선택 해제
          debugPrint('[DividerComponent] 템플릿 노드 선택 해제');
          nodeService.selectNode(null);
          widget.dragService?.invalidateNodeRectCache();
        } else {
          // 다른 노드 선택
          debugPrint('[DividerComponent] 템플릿 노드 선택: ${widget.nodeId}');
          nodeService.selectNode(widget.nodeId);
          widget.dragService?.invalidateNodeRectCache();

          // ✅ 선택 상태를 유지하기 위해 커서를 downstream으로 이동
          widget.focusNode?.requestFocus();
          editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: widget.nodeId,
                  nodePosition:
                      const UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
        }
        return;
      } catch (e) {
        debugPrint('[DividerComponent] 노드 선택 실패: $e');
      }
    }

    // ✅ 일반 Divider를 탭하면 "실제 caret"은 다음 문단(다운스트림)으로 이동시킨다.
    // - 이러면 바로 Backspace로 divider를 지우는 UX를 만들기 쉽다.
    widget.focusNode?.requestFocus();

    final doc = editor.document;
    final dividerIndex = doc.getNodeIndexById(widget.nodeId);
    if (dividerIndex < 0) return;

    ParagraphNode? downstreamParagraph;
    for (int i = dividerIndex + 1; i < doc.nodeCount; i++) {
      final n = doc.getNodeAt(i);
      if (n is ParagraphNode) {
        downstreamParagraph = n;
        break;
      }
    }

    if (downstreamParagraph == null) {
      // 문서 끝이면 빈 문단을 하나 만들고 그쪽으로 caret 이동
      final paragraphId = 'p_${DateTime.now().microsecondsSinceEpoch}';
      final newParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
      );
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: (dividerIndex + 1).clamp(0, doc.nodeCount),
          newNode: newParagraph,
        ),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: paragraphId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      return;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: downstreamParagraph.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
  }

  bool _shouldShowTopDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    return DropLineConfig.resolve(nodeId: widget.nodeId, dragService: svc).top;
  }

  bool _shouldShowBottomDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    return DropLineConfig.resolve(
      nodeId: widget.nodeId,
      dragService: svc,
    ).bottom;
  }

  // DocumentComponent 최소 구현
  @override
  NodePosition getBeginningPosition() =>
      const UpstreamDownstreamNodePosition.upstream();
  @override
  NodePosition getEndPosition() =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  NodePosition? getPositionAtOffset(Offset localOffset) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  Offset getOffsetForPosition(NodePosition nodePosition) => Offset.zero;
  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Rect.zero : (Offset.zero & box.size);
  }

  @override
  Rect getRectForSelection(NodePosition base, NodePosition extent) =>
      getRectForPosition(extent);
  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) =>
      UpstreamDownstreamNodeSelection(
        base: const UpstreamDownstreamNodePosition.upstream(),
        extent: const UpstreamDownstreamNodePosition.upstream(),
      );
  @override
  NodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) => UpstreamDownstreamNodeSelection(
    base: const UpstreamDownstreamNodePosition.upstream(),
    extent: const UpstreamDownstreamNodePosition.downstream(),
  );
  @override
  NodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) => null;
  @override
  NodeSelection getSelectionOfEverything() => UpstreamDownstreamNodeSelection(
    base: const UpstreamDownstreamNodePosition.upstream(),
    extent: const UpstreamDownstreamNodePosition.downstream(),
  );
  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Rect.zero : (Offset.zero & box.size);
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
      const UpstreamDownstreamNodePosition.upstream();
  @override
  NodePosition getEndPositionNearX(double x) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;
}
