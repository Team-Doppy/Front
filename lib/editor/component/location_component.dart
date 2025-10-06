import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'package:super_editor/super_editor.dart';

/// 완전히 독립적인 커스텀 위치 노드
/// 텍스트와 완전히 분리되어 동작합니다
class LocationNode extends BlockNode {
  LocationNode({
    required this.id,
    required this.lat,
    required this.lng,
    this.title = '',
    this.address = '',
    this.description = '',
  });

  @override
  bool get isDeletable => true;

  @override
  final String id;

  final double lat;
  final double lng;
  final String title;
  final String address;
  final String description;

  String get nodeType => 'location';

  bool get hasContent => title.isNotEmpty || address.isNotEmpty;

  @override
  bool containsPosition(Object position) {
    return position is UpstreamDownstreamNodePosition;
  }

  Rect getRectForPosition(NodePosition nodePosition) {
    return const Rect.fromLTWH(0, 0, 0, 0);
  }

  NodeSelection getSelectionOfEverything() {
    return UpstreamDownstreamNodeSelection(
      base: const UpstreamDownstreamNodePosition.upstream(),
      extent: const UpstreamDownstreamNodePosition.downstream(),
    );
  }

  bool isVisualSelectionSupported() {
    return false;
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return LocationNode(
      id: id,
      lat: lat,
      lng: lng,
      title: title,
      address: address,
      description: description,
    );
  }

  @override
  String? copyContent(NodeSelection selection) {
    return null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return LocationNode(
      id: id,
      lat: lat,
      lng: lng,
      title: title,
      address: address,
      description: description,
    );
  }

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

  LocationNode copyWith({
    double? lat,
    double? lng,
    String? title,
    String? address,
    String? description,
  }) {
    return LocationNode(
      id: id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      title: title ?? this.title,
      address: address ?? this.address,
      description: description ?? this.description,
    );
  }

  @override
  String toString() {
    return 'LocationNode(id: $id, lat: $lat, lng: $lng, title: $title)';
  }
}

/// 위치 노드의 뷰모델
/// SuperEditor가 노드를 렌더링할 때 사용하는 데이터 모델입니다
class LocationComponentViewModel extends SingleColumnLayoutComponentViewModel {
  LocationComponentViewModel({
    required super.nodeId,
    required this.lat,
    required this.lng,
    required this.title,
    required this.address,
    required this.description,
  }) : super(createdAt: DateTime.now(), padding: EdgeInsets.zero);

  final double lat;
  final double lng;
  final String title;
  final String address;
  final String description;

  @override
  SingleColumnLayoutComponentViewModel copy() => LocationComponentViewModel(
    nodeId: nodeId,
    lat: lat,
    lng: lng,
    title: title,
    address: address,
    description: description,
  );
}

/// 위치 노드의 컴포넌트 빌더
/// SuperEditor가 LocationNode를 만나면 이 빌더를 사용해서 UI를 생성합니다
class LocationComponentBuilder implements ComponentBuilder {
  final DragService dragService;
  const LocationComponentBuilder({required this.dragService});

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is LocationComponentViewModel) {
      return _LocationComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        lat: viewModel.lat,
        lng: viewModel.lng,
        title: viewModel.title,
        address: viewModel.address,
        description: viewModel.description,
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
    if (node is LocationNode) {
      return LocationComponentViewModel(
        nodeId: node.id,
        lat: node.lat,
        lng: node.lng,
        title: node.title,
        address: node.address,
        description: node.description,
      );
    }
    return null;
  }
}

/// 실제 위치 카드 UI 컴포넌트
/// 여기서 완전히 커스텀한 디자인을 구현합니다
class _LocationComponent extends StatefulWidget {
  const _LocationComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.lat,
    required this.lng,
    required this.title,
    required this.address,
    required this.description,
    this.dragService,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final double lat;
  final double lng;
  final String title;
  final String address;
  final String description;
  final DragService? dragService;

  @override
  State<_LocationComponent> createState() => _LocationComponentState();
}

class _LocationComponentState extends State<_LocationComponent>
    with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  @override
  Widget build(BuildContext context) {
    final imageService = context.watch<ImageService>();
    final isSelected = imageService.selectedImageId == widget.nodeId;

    // selection 핸들이 위치 노드를 포함할 때만 하이라이트
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    final composerSelection = seState?.editContext.composer.selection;
    final doc = seState?.editContext.editor.document;
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

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 30),
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  // 위치 노드 선택
                  imageService.selectImage(widget.nodeId);
                },
                child: Column(
                  children: [
                    // 헤더 (위치 아이콘 + 제목)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            widget.title.isNotEmpty ? widget.title : '위치',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 주소 정보
                    if (!widget.address.isNotEmpty)
                      Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              widget.address,
                              style: const TextStyle(
                                color: Color(0xFFCCCCCC),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (isSelectionHighlighted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 드래그 앤 드롭 삽입 선들
        if (_shouldShowTopDropLine())
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 3, color: AppColors.primary),
          ),

        if (_shouldShowBottomDropLine())
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(height: 3, color: AppColors.primary),
          ),
      ],
    );
  }

  // DocumentComponent 필수 메서드들
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
        base: const UpstreamDownstreamNodePosition.downstream(),
        extent: const UpstreamDownstreamNodePosition.downstream(),
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

  // 드래그 앤 드롭 관련 메서드들
  bool _shouldShowTopDropLine() {
    if (widget.dragService == null) return false;

    final dropIndex = widget.dragService?.dropIndex;
    if (dropIndex == null) return false;

    // 현재 노드의 인덱스 찾기
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 드롭 인덱스가 현재 노드와 같으면 위쪽에 라인 표시
    return dropIndex == currentNodeIndex;
  }

  bool _shouldShowBottomDropLine() {
    if (widget.dragService == null) return false;

    final dropIndex = widget.dragService?.dropIndex;
    if (dropIndex == null) return false;

    // 현재 노드의 인덱스 찾기
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 마지막 노드인지 확인
    final documentLength =
        widget.dragService?.editorService.document.length ?? 0;
    final isLastNode = currentNodeIndex == documentLength - 1;

    if (isLastNode) {
      // 마지막 노드일 때는 문서 끝에 삽입하는 경우만 표시
      return dropIndex == documentLength;
    }

    // 일반적인 경우는 이중 표시 방지를 위해 하단 라인 비활성화
    return false;
  }

  int _getCurrentNodeIndex() {
    if (widget.dragService == null) return -1;
    return widget.dragService?.getNodeIndex(widget.nodeId) ?? -1;
  }

  // selection이 이 위치 노드를 포함하는지 계산
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

    // 시작 경계가 이 노드인 경우: base/extent 중 누가 start인지에 따라 affinity 체크
    if (myIndex == start) {
      final isBaseStart = baseIndex < extentIndex;
      final startPosition = isBaseStart ? selection.base : selection.extent;
      if (startPosition.nodePosition is UpstreamDownstreamNodePosition) {
        final upDown =
            startPosition.nodePosition as UpstreamDownstreamNodePosition;
        return upDown.affinity == TextAffinity.downstream;
      }
    }

    // 끝 경계가 이 노드인 경우: base/extent 중 누가 end인지에 따라 affinity 체크
    if (myIndex == end) {
      final isBaseEnd = baseIndex > extentIndex;
      final endPosition = isBaseEnd ? selection.base : selection.extent;
      if (endPosition.nodePosition is UpstreamDownstreamNodePosition) {
        final upDown =
            endPosition.nodePosition as UpstreamDownstreamNodePosition;
        return upDown.affinity == TextAffinity.downstream;
      }
    }

    return true;
  }
}
