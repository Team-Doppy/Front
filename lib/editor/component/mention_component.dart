import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';

// 언급 블록 노드
class MentionNode extends BlockNode {
  MentionNode({required this.id, required this.usernames});

  @override
  final String id;
  final List<String> usernames;

  @override
  bool get isDeletable => false;

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
      MentionNode(id: id, usernames: usernames);

  @override
  String? copyContent(NodeSelection selection) => usernames.join(',');

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      MentionNode(id: id, usernames: usernames);
}

class MentionComponentViewModel extends SingleColumnLayoutComponentViewModel {
  MentionComponentViewModel({
    required super.nodeId,
    required this.usernames,
    required this.mainAxis,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final List<String> usernames;
  final MainAxisAlignment mainAxis;

  @override
  SingleColumnLayoutComponentViewModel copy() => MentionComponentViewModel(
    nodeId: nodeId,
    usernames: List<String>.from(usernames),
    mainAxis: mainAxis,
  );
}

class MentionComponentBuilder implements ComponentBuilder {
  const MentionComponentBuilder({this.dragService});
  final DragService? dragService;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is MentionComponentViewModel) {
      return _MentionComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        usernames: viewModel.usernames,
        mainAxis: viewModel.mainAxis,
        dragService: dragService,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is MentionNode) {
      // 인접 문단 정렬 값을 추론하여 정렬 적용
      MainAxisAlignment align = MainAxisAlignment.center;
      final int idx = document.getNodeIndexById(node.id);
      String? alignStr;
      // 이전 문단 우선
      for (int i = idx - 1; i >= 0; i--) {
        final prev = document.getNodeAt(i);
        if (prev is ParagraphNode) {
          alignStr = prev.metadata['textAlign'] as String?;
          break;
        }
      }
      // 다음 문단 보조
      if (alignStr == null) {
        for (int i = idx + 1; i < document.length; i++) {
          final next = document.getNodeAt(i);
          if (next is ParagraphNode) {
            alignStr = next.metadata['textAlign'] as String?;
            break;
          }
        }
      }
      switch (alignStr) {
        case 'left':
          align = MainAxisAlignment.start;
          break;
        case 'right':
          align = MainAxisAlignment.end;
          break;
        case 'center':
        default:
          align = MainAxisAlignment.center;
      }

      return MentionComponentViewModel(
        nodeId: node.id,
        usernames: node.usernames,
        mainAxis: align,
      );
    }
    return null;
  }
}

class _MentionComponent extends StatefulWidget {
  const _MentionComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.usernames,
    required this.mainAxis,
    this.dragService,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final List<String> usernames;
  final MainAxisAlignment mainAxis;
  final DragService? dragService;

  @override
  State<_MentionComponent> createState() => _MentionComponentState();
}

class _MentionComponentState extends State<_MentionComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  static const double marginTop = 4;
  static const double marginBottom = 2;
  static const double paddingWithText = 5;

  @override
  Widget build(BuildContext context) {
    // selection 핸들이 언급 노드를 포함하는지 확인
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection = seState?.editContext.composer.selection;
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;

    final bool hasMentionAbove =
        doc == null ? false : _hasNeighborMention(doc, widget.nodeId, -1);
    final bool hasMentionBelow =
        doc == null ? false : _hasNeighborMention(doc, widget.nodeId, 1);

    // 이웃하는 다른 타입의 노드들도 체크 (이미지, 링크)
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);
    final bool hasLinkAbove =
        doc == null ? false : _hasNeighborLink(doc, widget.nodeId, -1);
    final bool hasLinkBelow =
        doc == null ? false : _hasNeighborLink(doc, widget.nodeId, 1);

    final imageService = context.watch<NodeComponentService>();
    final isSelected = imageService.selectedImageId == widget.nodeId;

    bool isSelectionHighlighted = false;
    if (composerSelection != null &&
        !composerSelection.isCollapsed &&
        doc != null) {
      isSelectionHighlighted = _isNodeCoveredBySelection(
        doc,
        composerSelection,
        widget.nodeId,
      );
    }

    final pillContent = GestureDetector(
      onTap: () {
        imageService.selectImage(widget.nodeId);
      },
      child: Container(
        margin: EdgeInsets.only(top: marginTop, bottom: marginBottom),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Builder(
          builder: (context) {
            final CrossAxisAlignment cross =
                widget.mainAxis == MainAxisAlignment.start
                    ? CrossAxisAlignment.start
                    : widget.mainAxis == MainAxisAlignment.end
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.center;
            return Column(
              crossAxisAlignment: cross,
              children: [
                for (final u in widget.usernames)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.alternate_email,
                          color: AppColors.darkTextPrimary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          u,
                          style: const TextStyle(
                            color: AppColors.darkTextPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    return Column(
      children: [
        // 위쪽 패딩: 멘션이나 이미지, 링크가 위에 있으면 패딩 제거
        if (!hasMentionAbove && !hasImageAbove && !hasLinkAbove)
          SizedBox(height: paddingWithText),
        Stack(
          children: [
            Row(mainAxisAlignment: widget.mainAxis, children: [pillContent]),
            // 선택 하이라이트 오버레이
            if (isSelectionHighlighted)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: marginTop + 4,
                      bottom: marginBottom + 4,
                      left: 50,
                      right: 50,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                    ),
                  ),
                ),
              ),
            // 선택 테두리
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: marginTop,
                      bottom: marginBottom,
                      left: 50,
                      right: 50,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary, width: 3),
                    ),
                  ),
                ),
              ),
            // 드래그 삽입 라인
            if (_shouldShowTopDropLine())
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(height: 5, color: AppColors.primary),
                ),
              ),
            if (_shouldShowBottomDropLine())
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(height: 5, color: AppColors.primary),
                ),
              ),
          ],
        ),
        // 아래쪽 패딩: 멘션이나 이미지, 링크가 아래에 있으면 패딩 제거
        if (!hasMentionBelow && !hasImageBelow && !hasLinkBelow)
          SizedBox(height: paddingWithText),
      ],
    );
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

  bool _shouldShowTopDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = svc.getNodeIndex(widget.nodeId);
    if (current == -1) return false;

    // 이 노드 위에 삽입하는 경우
    if (di == current) {
      return _shouldShowInsertionLine(current, true);
    }
    return false;
  }

  bool _shouldShowBottomDropLine() {
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = svc.getNodeIndex(widget.nodeId);
    if (current == -1) return false;

    // 마지막 노드인지 확인
    final documentLength = svc.editorService.document.length;
    final isLastNode = current == documentLength - 1;

    if (isLastNode) {
      // 마지막 노드일 때는 문서 끝에 삽입하는 경우만 표시
      return di == documentLength;
    }

    // 다음 인덱스에 삽입하는 경우
    if (di == current + 1) {
      return _shouldShowInsertionLine(current, false);
    }
    return false;
  }

  /// 삽입 라인 표시 여부를 결정하는 공통 로직
  bool _shouldShowInsertionLine(int currentNodeIndex, bool isTopLine) {
    final svc = widget.dragService;
    if (svc == null) return false;

    final doc = svc.editorService.document;
    final documentLength = doc.length;

    // 특수 노드 타입 체크
    bool isSpecialNode(DocumentNode? node) {
      if (node == null) return false;
      return node is LinkNode ||
          node is MentionNode ||
          node is ImageNode ||
          node is ImageRowNode;
    }

    // 텍스트 노드 타입 체크
    bool isTextNode(DocumentNode? node) {
      if (node == null) return false;
      return node is ParagraphNode;
    }

    if (isTopLine) {
      // 위쪽 라인 표시 로직
      if (currentNodeIndex > 0) {
        final prevNode = doc.getNodeAt(currentNodeIndex - 1);

        // 케이스 1: 앞이 특수 노드인 경우 - 이 노드에서는 라인을 표시하지 않음
        // (위쪽 특수 노드가 아래쪽 라인을 표시하므로)
        if (isSpecialNode(prevNode)) {
          return false;
        }
      }
      return true;
    } else {
      // 아래쪽 라인 표시 로직
      if (currentNodeIndex + 1 < documentLength) {
        final nextNode = doc.getNodeAt(currentNodeIndex + 1);

        // 케이스 1: 뒤가 특수 노드인 경우 - 이 노드에서는 라인을 표시함
        // (특수-특수 사이에서는 위쪽 특수 노드가 아래쪽 라인을 표시)
        if (isSpecialNode(nextNode)) {
          return true;
        }

        // 케이스 2: 뒤가 텍스트 노드인 경우 - 이 노드에서는 라인을 표시함
        if (isTextNode(nextNode)) {
          return true;
        }
      }
      return true;
    }
  }

  // selection이 이 언급 노드를 포함하는지 계산
  bool _isNodeCoveredBySelection(
    Document doc,
    DocumentSelection selection,
    String nodeId,
  ) {
    final baseIndex = doc.getNodeIndexById(selection.base.nodeId);
    final extentIndex = doc.getNodeIndexById(selection.extent.nodeId);
    final myIndex = doc.getNodeIndexById(nodeId);
    if (baseIndex == -1 || extentIndex == -1 || myIndex == -1) return false;

    final start = math.min(baseIndex, extentIndex);
    final end = math.max(baseIndex, extentIndex);
    if (myIndex < start || myIndex > end) return false;

    // 시작 경계가 이 노드인 경우
    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    // 끝 경계가 이 노드인 경우
    if (myIndex == end) {
      final boundary = extentIndex == end ? selection.extent : selection.base;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    // 범위 내부에 완전히 포함
    return true;
  }

  bool _hasNeighborMention(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is MentionNode;
  }

  bool _hasNeighborLink(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is LinkNode;
  }

  bool _hasNeighborImage(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is ImageNode || neighbor is ImageRowNode;
  }
}
