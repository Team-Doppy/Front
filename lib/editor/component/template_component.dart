import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:provider/provider.dart';

// ✅ 템플릿 전용 노드 (DividerNode와 분리하여 undo/redo 시 메타데이터 보존)
class TemplateNode extends BlockNode {
  TemplateNode({required this.id, required this.templateText, this.textAlign})
    : _metadata = {
        'templateText': templateText,
        if (textAlign != null) 'textAlign': textAlign.name,
      };

  @override
  final String id;

  final String templateText;
  final TextAlign? textAlign;

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
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    final newTextAlign = newMetadata['textAlign'] as String?;
    return TemplateNode(
      id: id,
      templateText: newMetadata['templateText'] as String? ?? templateText,
      textAlign:
          newTextAlign != null
              ? TextAlign.values.firstWhere(
                (e) => e.name == newTextAlign,
                orElse: () => TextAlign.center,
              )
              : textAlign,
    );
  }

  @override
  String? copyContent(NodeSelection selection) => null;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    final merged = {..._metadata, ...newProperties};
    final newTextAlign = merged['textAlign'] as String?;
    return TemplateNode(
      id: id,
      templateText: merged['templateText'] as String? ?? templateText,
      textAlign:
          newTextAlign != null
              ? TextAlign.values.firstWhere(
                (e) => e.name == newTextAlign,
                orElse: () => TextAlign.center,
              )
              : textAlign,
    );
  }
}

class TemplateComponentViewModel extends SingleColumnLayoutComponentViewModel {
  TemplateComponentViewModel({
    required super.nodeId,
    required this.templateText,
    this.textAlign,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final String templateText;
  final TextAlign? textAlign;

  @override
  SingleColumnLayoutComponentViewModel copy() => TemplateComponentViewModel(
    nodeId: nodeId,
    templateText: templateText,
    textAlign: textAlign,
  );
}

class TemplateComponentBuilder implements ComponentBuilder {
  const TemplateComponentBuilder({
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
    if (viewModel is TemplateComponentViewModel) {
      return _TemplateComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
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
    if (node is TemplateNode) {
      // ✅ 텍스트 정렬 읽기
      TextAlign? textAlign;
      final alignStr = node.metadata['textAlign'] as String?;

      // 1) node 자체 메타 우선 (템플릿 노드는 항상 자체 정렬값 사용)
      if (alignStr != null && alignStr.isNotEmpty) {
        textAlign = TextAlign.values.firstWhere(
          (e) => e.name == alignStr,
          orElse: () => TextAlign.center,
        );
      }

      // ✅ 템플릿 노드는 항상 자체 정렬값을 사용 (주변 노드 상속하지 않음)
      // 최종 fallback은 center
      return TemplateComponentViewModel(
        nodeId: node.id,
        templateText: node.templateText,
        textAlign: textAlign ?? TextAlign.center,
      );
    }
    return null;
  }
}

class _TemplateComponent extends StatefulWidget {
  const _TemplateComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.templateText,
    this.textAlign,
    this.dragService,
    this.editor,
    this.focusNode,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final String templateText;
  final TextAlign? textAlign;
  final DragService? dragService;
  final Editor? editor;
  final FocusNode? focusNode;

  @override
  State<_TemplateComponent> createState() => _TemplateComponentState();
}

class _TemplateComponentState extends State<_TemplateComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
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

    // ✅ 텍스트 정렬 적용 (UI상으로 정렬이 맞도록)
    final textAlign = widget.textAlign ?? TextAlign.center;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      child: Align(
        alignment:
            textAlign == TextAlign.left
                ? Alignment.centerLeft
                : textAlign == TextAlign.right
                ? Alignment.centerRight
                : Alignment.center,
        child: Text(
          widget.templateText,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: textColor,
            height: 1.5,
          ),
        ),
      ),
    );

    final tappable =
        widget.editor == null
            ? content
            : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              child: content,
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
    if (widget.dragService != null) {
      try {
        final nodeService = context.read<NodeComponentService>();
        final currentSelected = nodeService.selectedImageId;

        if (currentSelected == widget.nodeId) {
          // 같은 노드 재탭: 선택 해제하고 다음 문단으로 이동
          debugPrint('[TemplateComponent] 템플릿 노드 선택 해제');
          nodeService.selectNode(null);
          widget.dragService?.invalidateNodeRectCache();

          // ✅ 다음 문단으로 커서 이동 (없으면 생성)
          final doc = editor.document;
          final templateIndex = doc.getNodeIndexById(widget.nodeId);
          if (templateIndex >= 0) {
            ParagraphNode? downstreamParagraph;
            for (int i = templateIndex + 1; i < doc.nodeCount; i++) {
              final n = doc.getNodeAt(i);
              if (n is ParagraphNode) {
                downstreamParagraph = n;
                break;
              }
            }

            if (downstreamParagraph != null) {
              widget.focusNode?.requestFocus();
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
            } else {
              // ✅ 다음 문단이 없으면 생성
              final paragraphId = Editor.createNodeId();
              final newParagraph = ParagraphNode(
                id: paragraphId,
                text: AttributedText(''),
                metadata: {'textAlign': 'center'},
              );
              widget.focusNode?.requestFocus();
              editor.execute([
                InsertNodeAtIndexRequest(
                  nodeIndex: templateIndex + 1,
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
            }
          }
        } else {
          // 다른 노드 선택
          debugPrint('[TemplateComponent] 템플릿 노드 선택: ${widget.nodeId}');
          nodeService.selectNode(widget.nodeId);
          widget.dragService?.invalidateNodeRectCache();

          // ✅ 템플릿 노드 바로 아래에 빈 노드가 없으면 생성
          final doc = editor.document;
          final templateIndex = doc.getNodeIndexById(widget.nodeId);
          if (templateIndex >= 0) {
            // 바로 다음 노드 확인
            ParagraphNode? nextParagraph;
            if (templateIndex + 1 < doc.nodeCount) {
              final nextNode = doc.getNodeAt(templateIndex + 1);
              if (nextNode is ParagraphNode) {
                nextParagraph = nextNode;
              }
            }

            if (nextParagraph == null) {
              // ✅ 바로 아래에 빈 노드가 없으면 생성
              final paragraphId = Editor.createNodeId();
              final newParagraph = ParagraphNode(
                id: paragraphId,
                text: AttributedText(''),
                metadata: {'textAlign': 'center'},
              );
              editor.execute([
                InsertNodeAtIndexRequest(
                  nodeIndex: templateIndex + 1,
                  newNode: newParagraph,
                ),
              ]);
              nextParagraph = newParagraph;
            }

            // ✅ 템플릿 노드는 선택되지만 커서는 다음 ParagraphNode로 이동
            widget.focusNode?.requestFocus();
            editor.execute([
              ChangeSelectionRequest(
                DocumentSelection.collapsed(
                  position: DocumentPosition(
                    nodeId: nextParagraph.id,
                    nodePosition: const TextNodePosition(offset: 0),
                  ),
                ),
                SelectionChangeType.placeCaret,
                SelectionReason.userInteraction,
              ),
            ]);
          }
        }
        return;
      } catch (e) {
        debugPrint('[TemplateComponent] 노드 선택 실패: $e');
      }
    }

    // ✅ 일반 탭: 다음 문단으로 이동
    widget.focusNode?.requestFocus();

    final doc = editor.document;
    final templateIndex = doc.getNodeIndexById(widget.nodeId);
    if (templateIndex < 0) return;

    ParagraphNode? downstreamParagraph;
    for (int i = templateIndex + 1; i < doc.nodeCount; i++) {
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
          nodeIndex: (templateIndex + 1).clamp(0, doc.nodeCount),
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
