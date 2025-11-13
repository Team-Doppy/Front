import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// 텍스트와 독립적인 링크 블록 노드
class LinkNode extends BlockNode {
  LinkNode({
    required this.id,
    required this.url,
    this.title = '',
    this.description = '',
    this.thumbnailUrl = '',
  });

  @override
  bool get isDeletable => false;
  String get nodeType => 'link';

  @override
  final String id;
  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;

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
    return LinkNode(
      id: id,
      url: url,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
    );
  }

  @override
  String? copyContent(NodeSelection selection) => url;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return LinkNode(
      id: id,
      url: url,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
    );
  }
}

class LinkComponentViewModel extends SingleColumnLayoutComponentViewModel {
  LinkComponentViewModel({
    required super.nodeId,
    required this.url,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;

  @override
  SingleColumnLayoutComponentViewModel copy() => LinkComponentViewModel(
    nodeId: nodeId,
    url: url,
    title: title,
    description: description,
    thumbnailUrl: thumbnailUrl,
  );
}

class LinkComponentBuilder implements ComponentBuilder {
  const LinkComponentBuilder({
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
  });
  final DragService? dragService;
  final bool isEditing;
  final bool isDarkMode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is LinkComponentViewModel) {
      return _LinkComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        url: viewModel.url,
        title: viewModel.title,
        description: viewModel.description,
        thumbnailUrl: viewModel.thumbnailUrl,
        dragService: dragService,
        isEditing: isEditing,
        isDarkMode: isDarkMode,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is LinkNode) {
      return LinkComponentViewModel(
        nodeId: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
      );
    }
    return null;
  }
}

class _LinkComponent extends StatefulWidget {
  const _LinkComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.url,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;
  final DragService? dragService;
  final bool isEditing;
  final bool isDarkMode;

  @override
  State<_LinkComponent> createState() => _LinkComponentState();
}

class _LinkComponentState extends State<_LinkComponent>
    with TickerProviderStateMixin, DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  static const double marginTop = 4;
  static const double marginBottom = 2;
  static const double paddingWithText = 15;

  OverlayEntry? _previewEntry;
  late final AnimationController _previewCtrl;
  WebViewController? _previewWebCtrl;
  Offset? _pressGlobalPos; // 손가락 전역 좌표
  Size? _overlaySize; // Overlay 크기 캐시
  double? _previewSize; // 정사각 미리보기 한 변 길이

  @override
  void initState() {
    super.initState();
    _previewCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _hidePreview();
    _previewCtrl.dispose();
    super.dispose();
  }

  void _showPreview(Offset globalPos) {
    if (widget.isEditing) return;
    _pressGlobalPos = globalPos;
    if (_previewEntry != null) {
      _previewEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context);

    // 링크 카드의 전역 위치/크기 계산 + Overlay 정보 수집
    final box = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    _overlaySize = overlayBox.size;

    // URL 정규화
    final String raw = widget.url.trim();
    if (raw.isEmpty) return;
    final String normalized =
        raw.startsWith('http://') || raw.startsWith('https://')
            ? raw
            : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;

    // 컨테이너 크기: 1:1 정사각, 화면 폭에 맞춰 조금 크게
    const double margin = 16;
    final double maxSize = _overlaySize!.width - margin * 2;
    _previewSize = maxSize.clamp(200, 240);

    // WebView 컨트롤러 준비 (플랫폼 추상화 기반)
    try {
      final params = const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params);
      if (controller.platform is AndroidWebViewController) {
        final androidCtrl = controller.platform as AndroidWebViewController;
        AndroidWebViewController.enableDebugging(true);
        androidCtrl.setMediaPlaybackRequiresUserGesture(false);
      }
      _previewWebCtrl =
          controller
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(Colors.transparent)
            ..loadRequest(uri);
    } catch (_) {
      return;
    }

    _previewEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context).colorScheme;
        final size = _previewSize ?? 240;
        final press = _pressGlobalPos;
        if (press == null) return const SizedBox.shrink();

        // 손가락 전역 좌표 -> Overlay 로컬 좌표 변환
        final local = overlayBox.globalToLocal(press);

        // 위치 계산: 손가락 위(기본), 부족하면 아래
        double left = local.dx - size / 2;
        left = left.clamp(16, _overlaySize!.width - size - 16);
        double top = local.dy - size - 12;
        if (top < 16) top = local.dy + 12;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: size,
              height: size,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _previewCtrl,
                  curve: Curves.easeOut,
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _previewCtrl,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child:
                          _previewWebCtrl == null
                              ? const SizedBox.shrink()
                              : WebViewWidget(controller: _previewWebCtrl!),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_previewEntry!);
    _previewCtrl.forward(from: 0.0);
  }

  void _updatePreviewPosition(Offset globalPos) {
    if (_previewEntry == null) return;
    _pressGlobalPos = globalPos;
    _previewEntry!.markNeedsBuild();
  }

  void _hidePreview() {
    _previewCtrl.reverse();
    _previewEntry?.remove();
    _previewEntry = null;
    _previewWebCtrl = null;
    _pressGlobalPos = null;
  }

  @override
  Widget build(BuildContext context) {
    // selection 핸들이 링크 노드를 포함하는지 확인 (편집 모드에서만)
    // ignore: invalid_use_of_visible_for_testing_member
    final seState =
        widget.isEditing
            // ignore: invalid_use_of_visible_for_testing_member
            ? context.findAncestorStateOfType<SuperEditorState>()
            : null;
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;

    final bool hasLinkAbove =
        doc == null ? false : _hasNeighborLink(doc, widget.nodeId, -1);
    final bool hasLinkBelow =
        doc == null ? false : _hasNeighborLink(doc, widget.nodeId, 1);

    // 이웃하는 다른 타입의 노드들도 체크 (이미지, 멘션)
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);

    final imageService = context.watch<NodeComponentService>();
    final bool isSelected =
        widget.isEditing && imageService.selectedImageId == widget.nodeId;

    bool isSelectionHighlighted = false;
    if (widget.isEditing && seState != null && doc != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      final selection = seState.editContext.composer.selection;
      if (selection != null && !selection.isCollapsed) {
        isSelectionHighlighted = _isNodeCoveredBySelection(
          doc,
          selection,
          widget.nodeId,
        );
      }
    }

    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // 🎯 불투명 영역만 탭 감지
        onTap:
            widget.isEditing
                ? () {
                  imageService.selectImage(widget.nodeId);
                }
                : null,
        onLongPressStart:
            widget.isEditing ? null : (d) => _showPreview(d.globalPosition),
        onLongPressMoveUpdate:
            widget.isEditing
                ? null
                : (d) => _updatePreviewPosition(d.globalPosition),
        onLongPressEnd: widget.isEditing ? null : (_) => _hidePreview(),
        child: Container(
          margin: EdgeInsets.only(top: marginTop, bottom: marginBottom),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 위: 썸네일
              if (widget.thumbnailUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      widget.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildIconPlaceholder(),
                    ),
                  ),
                )
              else
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildIconPlaceholder(),
                ),

              // 아래: 텍스트 정보
              Container(
                decoration: BoxDecoration(
                  color:
                      widget.isDarkMode
                          ? const Color(0xFF1C1C1E)
                          : Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 제목
                    Text(
                      widget.title.isNotEmpty ? widget.title : widget.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isDarkMode ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // URL
                    Text(
                      widget.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            widget.isDarkMode
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.5),
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    // 설명 (있을 경우)
                    if (widget.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              widget.isDarkMode
                                  ? Colors.white.withOpacity(0.65)
                                  : Colors.black.withOpacity(0.65),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      children: [
        // 위쪽 패딩: 링크나 이미지, 멘션이 위에 있으면 패딩 제거
        if (!hasLinkAbove && !hasImageAbove) SizedBox(height: paddingWithText),
        Stack(
          children: [
            card,
            // 선택 하이라이트 오버레이 (편집 모드에서만)
            if (widget.isEditing && isSelectionHighlighted)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: marginTop,
                      bottom: marginBottom,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            // 선택 테두리 (편집 모드에서만)
            if (widget.isEditing && isSelected)
              Positioned(
                top: 0,
                bottom: 0,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: marginTop,
                      bottom: marginBottom,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary, width: 5),
                    ),
                  ),
                ),
              ),
            // 드래그 삽입 라인 (편집 모드에서만)
            if (widget.isEditing && _shouldShowTopDropLine())
              Positioned(
                top: 0,
                left: 20,
                right: 20,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(height: 5, color: AppColors.primary),
                ),
              ),
            if (widget.isEditing && _shouldShowBottomDropLine())
              Positioned(
                bottom: 0,
                left: 20,
                right: 20,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(height: 5, color: AppColors.primary),
                ),
              ),
          ],
        ),
        // 아래쪽 패딩: 링크나 이미지, 멘션이 아래에 있으면 패딩 제거
        if (!hasLinkBelow && !hasImageBelow) SizedBox(height: paddingWithText),
      ],
    );
  }

  // DocumentComponent 최소 구현 (이미지/위치와 동일 정책)
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

  // 드래그 삽입 라인 표시 로직
  bool _shouldShowTopDropLine() {
    if (!widget.isEditing) return false;
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = _getCurrentNodeIndex();
    if (current == -1) return false;

    // 이 노드 위에 삽입하는 경우
    if (di == current) {
      return _shouldShowInsertionLine(current, true);
    }
    return false;
  }

  bool _shouldShowBottomDropLine() {
    if (!widget.isEditing) return false;
    final svc = widget.dragService;
    if (svc == null) return false;
    final di = svc.dropIndex;
    if (di == null) return false;
    final current = _getCurrentNodeIndex();
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
    if (!widget.isEditing) return false;
    final svc = widget.dragService;
    if (svc == null) return false;

    final doc = svc.editorService.document;
    final documentLength = doc.length;

    // 특수 노드 타입 체크
    bool isSpecialNode(DocumentNode? node) {
      if (node == null) return false;
      return node is LinkNode ||
          (node is ParagraphNode && node.metadata['mention'] == true) ||
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

  int _getCurrentNodeIndex() {
    final svc = widget.dragService;
    if (svc == null) return -1;
    return svc.getNodeIndex(widget.nodeId);
  }

  // selection이 이 링크 노드를 포함하는지 계산
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

  /// 썸네일 없을 때 아이콘 플레이스홀더
  Widget _buildIconPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color:
            widget.isDarkMode
                ? const Color(0xFF2C2C2E)
                : const Color(0xFFF2F2F7),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Center(
        child: Icon(
          Icons.link_rounded,
          color:
              widget.isDarkMode
                  ? Colors.white.withOpacity(0.3)
                  : Colors.black.withOpacity(0.3),
          size: 40,
        ),
      ),
    );
  }
}
