import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/editor/service/post_reader_service.dart';

/// VideoPlayer 컨트롤러를 저장하는 맵
final videoPlayerControllers = <String, VideoPlayerControllerProxy>{};

/// VideoPlayer 프록시 클래스
class VideoPlayerControllerProxy {
  void Function()? toggleMute;
  void Function()? restartVideo;
  bool Function()? hasPlayedOnce;
  void Function()? pause;
}

/// 모든 비디오 플레이어 정리
void cleanupAllVideoPlayers() {
  print('[ClipComponent] 모든 비디오 플레이어 정리 시작');
  for (final entry in videoPlayerControllers.entries) {
    final controller = entry.value;
    // 모든 비디오 일시정지
    controller.pause?.call();
  }
  // 맵 비우기
  videoPlayerControllers.clear();
  print('[ClipComponent] 모든 비디오 플레이어 정리 완료');
}

/// 텍스트와 독립적인 핀 블록 노드
class ClipNode extends BlockNode {
  ClipNode({
    required this.id,
    this.label = '',
    this.colorHex = '#FF5252',
    this.url = '',
    this.localPath = '',
    this.thumbnailPath = '',
  });

  @override
  bool get isDeletable => false;
  String get nodeType => 'pin';

  @override
  final String id;
  final String label;
  final String colorHex;
  final String url;
  final String localPath;
  final String thumbnailPath;

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
    return ClipNode(
      id: id,
      label: label,
      colorHex: colorHex,
      url: url,
      localPath: localPath,
      thumbnailPath: thumbnailPath,
    );
  }

  @override
  String? copyContent(NodeSelection selection) => label;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return ClipNode(
      id: id,
      label: label,
      colorHex: colorHex,
      url: url,
      localPath: localPath,
      thumbnailPath: thumbnailPath,
    );
  }
}

class PinComponentViewModel extends SingleColumnLayoutComponentViewModel {
  PinComponentViewModel({
    required super.nodeId,
    required this.label,
    required this.colorHex,
    required this.url,
    required this.localPath,
    required this.thumbnailPath,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final String label;
  final String colorHex;
  final String url;
  final String localPath;
  final String thumbnailPath;

  @override
  SingleColumnLayoutComponentViewModel copy() => PinComponentViewModel(
    nodeId: nodeId,
    label: label,
    colorHex: colorHex,
    url: url,
    localPath: localPath,
    thumbnailPath: thumbnailPath,
  );
}

class PinComponentBuilder implements ComponentBuilder {
  const PinComponentBuilder({this.dragService});
  final DragService? dragService;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is PinComponentViewModel) {
      return _PinComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        label: viewModel.label,
        colorHex: viewModel.colorHex,
        url: viewModel.url,
        localPath: viewModel.localPath,
        thumbnailPath: viewModel.thumbnailPath,
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
    if (node is ClipNode) {
      return PinComponentViewModel(
        nodeId: node.id,
        label: node.label,
        colorHex: node.colorHex,
        url: node.url,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
      );
    }
    return null;
  }
}

class _PinComponent extends StatefulWidget {
  const _PinComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.label,
    required this.colorHex,
    required this.url,
    required this.localPath,
    required this.thumbnailPath,
    this.dragService,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final String label;
  final String colorHex;
  final String url;
  final String localPath;
  final String thumbnailPath;
  final DragService? dragService;

  @override
  State<_PinComponent> createState() => _PinComponentState();
}

class _PinComponentState extends State<_PinComponent> with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  // VideoPlayer 액션 트리거용 키
  final _videoPlayerKey = GlobalKey<_VideoPlayerWidgetState>();

  static const double marginTop = 4;
  static const double marginBottom = 2;
  static const double paddingWithText = 15;

  @override
  Widget build(BuildContext context) {
    // selection 핸들이 링크 노드를 포함하는지 확인
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection = seState?.editContext.composer.selection;
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
    final bool hasMentionAbove =
        doc == null ? false : _hasNeighborMention(doc, widget.nodeId, -1);
    final bool hasMentionBelow =
        doc == null ? false : _hasNeighborMention(doc, widget.nodeId, 1);

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

    final card = Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: marginTop, bottom: marginBottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.25),
      ),
      child: _buildVideoContent(context),
    );

    return Stack(
      children: [
        Column(
          children: [
            // 위쪽 패딩: 링크나 이미지, 멘션이 위에 있으면 패딩 제거
            if (!hasLinkAbove && !hasImageAbove && !hasMentionAbove)
              SizedBox(height: paddingWithText),
            Stack(
              children: [
                card,
                // 선택 하이라이트 오버레이
                if (isSelectionHighlighted)
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
                // 선택 테두리
                if (isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: EdgeInsets.only(
                          top: marginTop,
                          bottom: marginBottom,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primary,
                            width: 3,
                          ),
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
            // 아래쪽 패딩: 링크나 이미지, 멘션이 아래에 있으면 패딩 제거
            if (!hasLinkBelow && !hasImageBelow && !hasMentionBelow)
              SizedBox(height: paddingWithText),
          ],
        ),
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
    final svc = widget.dragService;
    if (svc == null) return false;

    final doc = svc.editorService.document;
    final documentLength = doc.length;

    // 특수 노드 타입 체크
    bool isSpecialNode(DocumentNode? node) {
      if (node == null) return false;
      return node is ClipNode ||
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
    return neighbor is ClipNode;
  }

  bool _hasNeighborMention(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is MentionNode;
  }

  bool _hasNeighborImage(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is ImageNode || neighbor is ImageRowNode;
  }

  Widget _buildVideoContent(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxHeight = screenWidth * 1.5;

    // 로컬 파일 경로가 있으면 (placeholder 상태) 썸네일과 로딩 표시
    if (widget.localPath.isNotEmpty) {
      // 기본 비율로 계산한 높이
      final calculatedHeight = screenWidth / 16 * 9;
      final finalHeight =
          calculatedHeight > maxHeight ? maxHeight : calculatedHeight;

      // 썸네일 경로가 있으면 썸네일을 배경으로 사용
      if (widget.thumbnailPath.isNotEmpty) {
        return SizedBox(
          width: screenWidth,
          height: finalHeight,
          child: Stack(
            children: [
              // 썸네일 배경
              ClipRRect(
                child: Image.file(
                  File(widget.thumbnailPath),
                  fit: BoxFit.cover,
                  width: screenWidth,
                  height: calculatedHeight,
                ),
              ),
              // 로딩 오버레이 (투명 배경)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          '클립 업로드',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // 썸네일이 없으면 기본 아이콘 표시
      return SizedBox(
        width: screenWidth,
        height: finalHeight,
        child: ClipRRect(
          child: Image.file(
            File(widget.localPath),
            fit: BoxFit.cover,
            width: screenWidth,
            height: calculatedHeight,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: screenWidth,
                height: finalHeight,
                color: Colors.grey[200],
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.video_file, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('미리보기', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text(
                        widget.label.isNotEmpty ? widget.label : 'clip',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    // 네트워크 URL이 있으면 비디오 플레이어
    if (widget.url.isNotEmpty) {
      return _VisibilityAwareVideoPlayer(
        url: widget.url,
        thumbnailPath: widget.thumbnailPath,
        key: _videoPlayerKey,
      );
    }

    // 업로드 완료되지 않으면 텍스트만 표시
    return Row(
      children: [
        const SizedBox(width: 12),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              widget.label.isNotEmpty ? widget.label : 'clip',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// 가시성 감지 래퍼
class _VisibilityAwareVideoPlayer extends StatefulWidget {
  final String url;
  final String thumbnailPath;

  const _VisibilityAwareVideoPlayer({
    required this.url,
    required this.thumbnailPath,
    super.key,
  });

  @override
  State<_VisibilityAwareVideoPlayer> createState() =>
      _VisibilityAwareVideoPlayerState();
}

class _VisibilityAwareVideoPlayerState
    extends State<_VisibilityAwareVideoPlayer> {
  bool _isVisible = false;
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkVisibility();
  }

  void _checkVisibility() {
    // 주기적으로 가시성 체크
    Future.delayed(Duration(milliseconds: 100), () {
      if (!mounted) return;
      _updateVisibility();
      _checkVisibility();
    });
  }

  void _updateVisibility() {
    final context = _key.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);

    final screenHeight = MediaQuery.of(context).size.height;
    final viewportTop = 0.0;
    final viewportBottom = screenHeight;

    // 화면에 보이는 비율 계산
    final visibleTop = math.max(position.dy, viewportTop);
    final visibleBottom = math.min(position.dy + size.height, viewportBottom);
    final visibleHeight = math.max(0.0, visibleBottom - visibleTop);
    final visibleRatio = size.height > 0 ? visibleHeight / size.height : 0.0;

    // 보수적으로 설정: 비디오의 최소 50%가 화면에 보여야 재생
    // 그리고 중앙 부분이 화면 안에 있어야 함
    final centerY = position.dy + size.height / 2;
    final isCenterVisible = centerY > viewportTop && centerY < viewportBottom;

    final isVisible = visibleRatio >= 0.5 && isCenterVisible;

    if (_isVisible != isVisible) {
      setState(() {
        _isVisible = isVisible;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _key,
      child: _VideoPlayerWidget(
        key: widget.key, // 부모에서 전달받은 key 사용
        url: widget.url,
        thumbnailPath: widget.thumbnailPath,
        shouldAutoPlay: _isVisible,
      ),
    );
  }
}

/// 비디오 플레이어 위젯
class _VideoPlayerWidget extends StatefulWidget {
  final String url;
  final String thumbnailPath;
  final bool shouldAutoPlay;

  const _VideoPlayerWidget({
    required this.url,
    required this.thumbnailPath,
    this.shouldAutoPlay = true,
    super.key,
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isMuted = false;
  bool _hasPlayedOnce = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _registerVideoPlayerController();
  }

  void _registerVideoPlayerController() {
    final proxy = VideoPlayerControllerProxy();
    proxy.toggleMute = toggleMute;
    proxy.restartVideo = restartVideo;
    proxy.hasPlayedOnce = () => _hasPlayedOnce;
    proxy.pause = _pauseVideo;

    // nodeId 추출 (url을 사용하여 임시로 key 생성)
    final key = 'video_${widget.url.hashCode}';
    videoPlayerControllers[key] = proxy;

    print('[VideoPlayer] 컨트롤러 등록됨: $key');
  }

  @override
  void dispose() {
    // 컨트롤러 해제
    final key = 'video_${widget.url.hashCode}';
    videoPlayerControllers.remove(key);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // shouldAutoPlay가 변경되면 재생/정지
    if (oldWidget.shouldAutoPlay != widget.shouldAutoPlay &&
        _controller != null &&
        _isInitialized) {
      if (widget.shouldAutoPlay && !_isPlaying && !_hasPlayedOnce) {
        _playVideo();
      } else if (!widget.shouldAutoPlay && _isPlaying) {
        _pauseVideo();
      }
    }
  }

  Future<void> _initializeVideo() async {
    try {
      _controller =
          PostReaderService.takePreloadedController(widget.url) ??
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      // 프리로드 컨트롤러면 첫 프레임부터 초기화된 상태로 진입 → 스피너 방지
      if (!_controller!.value.isInitialized) {
        await _controller!.initialize();
      } else {
        _isInitialized = true;
      }

      // 음소거 설정
      await _controller!.setVolume(_isMuted ? 0.0 : 1.0);

      // 재생 완료 리스너
      _controller!.addListener(_onVideoStatusChanged);

      if (mounted) setState(() => _isInitialized = true);

      // 초기화 후 즉시 재생
      if (widget.shouldAutoPlay) {
        _playVideo();
      }
    } catch (e) {
      print('[VideoPlayer] 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _onVideoStatusChanged() {
    if (_controller == null) return;

    // 재생 상태 업데이트
    final isPlaying = _controller!.value.isPlaying;
    if (_isPlaying != isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
    }

    // 한 번 재생이 끝났는지 확인
    if (_controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero &&
        !_hasPlayedOnce) {
      setState(() {
        _hasPlayedOnce = true;
      });
    }
  }

  // 외부에서 호출하기 위한 public 메서드들
  void toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
    });
    _controller!.setVolume(_isMuted ? 0.0 : 1.0);
  }

  void restartVideo() {
    if (_controller == null) return;
    _controller!.seekTo(Duration.zero);
    _controller!.play();
    setState(() {
      _hasPlayedOnce = false;
    });
  }

  void _playVideo() {
    if (_controller == null || _isInitialized == false) return;
    _controller!.play();
  }

  void _pauseVideo() {
    if (_controller == null) return;
    _controller!.pause();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return AspectRatio(
        aspectRatio: 16 / 9, // 기본 비율
        child: Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.white),
                SizedBox(height: 8),
                Text('영상을 불러올 수 없습니다', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      // thumbnailPath가 있으면 썸네일 표시
      if (widget.thumbnailPath.isNotEmpty) {
        final screenWidth = MediaQuery.of(context).size.width;
        final maxHeight = screenWidth * 1.5;
        final calculatedHeight = screenWidth / 16 * 9; // 기본 비율

        return SizedBox(
          width: screenWidth,
          height: calculatedHeight > maxHeight ? maxHeight : calculatedHeight,
          child: ClipRRect(
            child: Image.file(
              File(widget.thumbnailPath),
              fit: BoxFit.cover,
              width: screenWidth,
              height: calculatedHeight,
            ),
          ),
        );
      }

      return AspectRatio(
        aspectRatio: 16 / 9, // 기본 비율
        child: Container(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    // 원본 비율 계산
    final videoSize = _controller!.value.size;
    final originalAspectRatio =
        videoSize.height > 0 ? videoSize.width / videoSize.height : 16 / 9;

    // 화면 너비 기준으로 최대 높이 제한 (1.5배)
    final screenWidth = MediaQuery.of(context).size.width;
    final maxHeight = screenWidth * 1.5;

    // 원본 비율에서 계산한 높이
    final calculatedHeight = screenWidth / originalAspectRatio;

    return SizedBox(
      width: screenWidth,
      height: calculatedHeight > maxHeight ? maxHeight : calculatedHeight,
      child: Stack(
        children: [
          ClipRRect(
            child: SizedBox(
              width: screenWidth,
              height: calculatedHeight,
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.center,
                child: SizedBox(
                  width: screenWidth,
                  height: calculatedHeight,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
          // 다시보기 버튼 배경 (한 번 재생 후 표시)
          if (_hasPlayedOnce)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.replay, color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text(
                          '다시보기',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 음소거 버튼
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
