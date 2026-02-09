import 'dart:ui';

import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:doppy/utils/link_meta_fetcher.dart';

/// 텍스트와 독립적인 링크 블록 노드
class LinkNode extends BlockNode {
  LinkNode({
    required this.id,
    required this.url,
    this.title = '',
    this.description = '',
    this.thumbnailUrl = '',
    Map<String, dynamic>? metadata,
  }) : _metadata = metadata ?? const {};

  @override
  bool get isDeletable => true;
  String get nodeType => 'link';

  @override
  final String id;
  final String url;
  final String title;
  final String description;
  final String thumbnailUrl;
  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

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
      metadata: newMetadata,
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
      metadata: {...metadata, ...newProperties},
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
    required EdgeInsets padding, // 🎯 ClipComponent와 동일: metadata 기반 padding 전달
  }) : super(padding: padding, createdAt: DateTime.now());

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
    padding: padding as EdgeInsets, // 🎯 복사 시에도 padding 유지
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
      // 🎯 ClipComponent와 동일: 메타데이터에서 padding 모드 읽기
      final paddingMode = node.metadata['padding'] as String? ?? 'center';
      final horizontalPadding = paddingMode == 'full' ? 0.0 : 20.0;
      return LinkComponentViewModel(
        nodeId: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
        padding: EdgeInsets.only(
          left: horizontalPadding,
          right: horizontalPadding,
        ),
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

  static const double marginTop = 2.5;
  static const double marginBottom = 2.5;

  // ✅ 링크 썸네일도 이미지 컴포넌트처럼 "마지막 성공 렌더"를 캐시해서 깜빡임을 줄인다.
  Widget? _lastRenderedThumbnail;

  // 🎯 메타데이터 재조회 시도 여부 (1번만 시도)
  bool _hasTriedFetchingMeta = false;

  Widget _buildThumbnail(BoxConstraints constraints) {
    final decodeWidth =
        widget.isEditing
            ? EditorImageProvider.editingDecodeWidth(
              context,
              constraints.maxWidth,
            )
            : null;

    final built = EditorImageProvider.build(
      url: widget.thumbnailUrl,
      isEditing: widget.isEditing,
      decodeWidth: decodeWidth,
    );

    return Image(
      image: built.effectiveProvider,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded || frame != null) {
          _lastRenderedThumbnail = child;
          return child;
        }
        return _lastRenderedThumbnail ?? _buildIconPlaceholder();
      },
      errorBuilder: (_, __, ___) => _buildIconPlaceholder(),
    );
  }

  bool _isCompactViewMode(Document? doc) {
    try {
      final node = doc?.getNodeById(widget.nodeId);
      if (node is LinkNode) {
        final v = node.metadata['viewMode'] as String?;
        return v == 'compact';
      }
    } catch (_) {}
    return false;
  }

  // 🎯 특수 노드 사이 클릭 감지 플래그
  bool _isSpecialNodeGapTap = false;

  // 🎯 특수 노드 사이 클릭 감지 (true: 특수 노드 사이 클릭, false: 일반 클릭)
  bool _handleSpecialNodeTap(Offset globalPosition) {
    if (widget.dragService == null) return false;
    final editorService = widget.dragService!.editorService;
    final doc = editorService.document;
    final dragService = widget.dragService!;

    // 자신의 인덱스와 Rect 확인
    final currentNodeIndex = doc.getNodeIndexById(widget.nodeId);
    if (currentNodeIndex == -1) return false;

    final nodeRect = dragService.getNodeGlobalRect(widget.nodeId);
    if (nodeRect == null) return false;

    // 🎯 위쪽 이웃 노드 확인
    if (currentNodeIndex > 0) {
      final prevNode = doc.getNodeAt(currentNodeIndex - 1);
      if (prevNode != null) {
        if (NodeTypeChecker.isSpecialNode(prevNode)) {
          final prevRect = dragService.getNodeGlobalRect(prevNode.id);
          if (prevRect != null) {
            // 위쪽 노드와 자신 사이의 간격 확인 (위쪽 노드 아래 20px ~ 자신 위쪽 20px)
            final gapTop = prevRect.bottom - 20;
            final gapBottom = nodeRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }

    // 🎯 아래쪽 이웃 노드 확인
    if (currentNodeIndex < doc.nodeCount - 1) {
      final nextNode = doc.getNodeAt(currentNodeIndex + 1);
      if (nextNode != null) {
        if (NodeTypeChecker.isSpecialNode(nextNode)) {
          final nextRect = dragService.getNodeGlobalRect(nextNode.id);
          if (nextRect != null) {
            // 자신과 아래쪽 노드 사이의 간격 확인 (자신 아래 20px ~ 아래쪽 노드 위쪽 20px)
            final gapTop = nodeRect.bottom - 20;
            final gapBottom = nextRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex + 1);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return true;
            }
          }
        }
      }
    }
    return false;
  }

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

    // 🎯 thumbnailUrl이 비어있으면 메타데이터 재조회
    if (widget.thumbnailUrl.isEmpty && widget.url.isNotEmpty) {
      _fetchLinkMetaIfNeeded();
    }
  }

  /// 링크 메타데이터 재조회 (thumbnailUrl이 비어있을 때, 1번만 시도)
  Future<void> _fetchLinkMetaIfNeeded() async {
    // 🎯 이미 시도했으면 재시도하지 않음
    if (_hasTriedFetchingMeta || !mounted) return;

    _hasTriedFetchingMeta = true;

    final normalizedUrl = LinkMetaFetcher.normalizeUrl(widget.url);
    if (normalizedUrl == null) return;

    try {
      final meta = await LinkMetaFetcher.fetchMeta(normalizedUrl);
      if (meta != null && mounted) {
        // 메타데이터가 있고 thumbnailUrl이 업데이트되었으면 노드 업데이트
        if (meta.thumbnailUrl != null && meta.thumbnailUrl!.isNotEmpty) {
          final editorService = widget.dragService?.editorService;
          if (editorService != null) {
            editorService.updateLinkNode(
              nodeId: widget.nodeId,
              title: meta.title,
              description: meta.description,
              thumbnailUrl: meta.thumbnailUrl,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[LinkComponent] 메타데이터 재조회 실패: $e');
    }
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
                      decoration: BoxDecoration(color: theme.surface),
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
    // 🎯 읽기 모드에서도 doc에 접근하여 특수 노드 간격 확인 (포스트 라이트와 동일하게)
    // ✅ metadata 기반 렌더링(간략/풀)과 이웃 노드 판정은 EditorService의 문서를 기준으로 한다.
    // (SuperEditorState.editContext 접근은 패키지 내부 제한으로 lint 경고 발생)
    final editorService = widget.dragService?.editorService;
    // ✅ 편집 모드에서는 EditorService.document, 읽기 모드(드래그 서비스 없음)에서는 SuperEditorState로 fallback
    Document? doc = editorService?.document;
    if (doc == null) {
      // ignore: invalid_use_of_visible_for_testing_member
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      // ignore: invalid_use_of_visible_for_testing_member
      doc = seState?.editContext.editor.document;
    }

    final composerSelection =
        editorService?.editor.composer.selectionNotifier.value;

    // 이웃하는 특수 노드 체크 (이미지, 클립, 링크)
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);

    final imageService = context.watch<NodeComponentService>();
    final bool isSelected =
        widget.isEditing && imageService.selectedImageId == widget.nodeId;

    // 🎯 downstream 위치에 커서가 있을 때도 selection 효과 표시
    bool isDownstreamSelected = false;
    if (composerSelection != null &&
        composerSelection.isCollapsed &&
        composerSelection.extent.nodeId == widget.nodeId) {
      final position = composerSelection.extent.nodePosition;
      if (position is UpstreamDownstreamNodePosition &&
          position == const UpstreamDownstreamNodePosition.downstream()) {
        isDownstreamSelected = true;
      }
    }

    // 🎯 selection 핸들이 링크 노드를 포함할 때만, 그리고 경계가 링크인 경우 Downstream일 때만 하이라이트
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

    // 🎯 RepaintBoundary로 감싸서 키보드 애니메이션 시 불필요한 repaint 방지
    return RepaintBoundary(
      child: Column(
        children: [
          if (!hasImageAbove)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
          // 실제 링크 내용
          LayoutBuilder(
            builder: (context, constraints) {
              // ✅ 좌우 패딩은 stylesheet(`style_sheet.dart`)에서 LinkNode에 이미 적용한다.
              // 여기서 또 20px 패딩을 주면 내용만 안으로 밀리고 caret/selection은 바깥 기준으로 잡혀
              // "링크 옆 여백"처럼 보인다.
              final linkContent = Container(
                decoration: BoxDecoration(
                  color:
                      widget.isDarkMode
                          ? const Color(0xFF1C1C1E)
                          : Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ✅ 표시 모드: full(default)=썸네일까지 표시, compact=썸네일 영역 제거
                    // ✅ 토글 시 레이아웃 점프/빨간 에러 화면 방지: AnimatedSize + AnimatedSwitcher로 부드럽게 전환
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder:
                            (child, anim) =>
                                FadeTransition(opacity: anim, child: child),
                        child:
                            _isCompactViewMode(doc)
                                ? const SizedBox.shrink(
                                  key: ValueKey('link_thumb_compact'),
                                )
                                : (widget.thumbnailUrl.isNotEmpty
                                    ? AspectRatio(
                                      key: const ValueKey('link_thumb_image'),
                                      aspectRatio: 16 / 9,
                                      child: _buildThumbnail(constraints),
                                    )
                                    : AspectRatio(
                                      key: const ValueKey('link_thumb_icon'),
                                      aspectRatio: 16 / 9,
                                      child: _buildIconPlaceholder(),
                                    )),
                      ),
                    ),

                    // 아래: 텍스트 정보
                    Container(
                      decoration: BoxDecoration(
                        color:
                            widget.isDarkMode
                                ? const Color(0xFF1C1C1E)
                                : Colors.grey.shade100,
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
                              color:
                                  widget.isDarkMode
                                      ? Colors.white
                                      : Colors.black,
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
                        ],
                      ),
                    ),
                  ],
                ),
              );

              return Stack(
                children: [
                  // 🎯 편집 모드에서 탭/롱프레스 처리
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
                              final isGapTap = _handleSpecialNodeTap(
                                details.globalPosition,
                              );
                              setState(() {
                                _isSpecialNodeGapTap = isGapTap;
                              });
                            }
                            : null,
                    onTap:
                        widget.isEditing && widget.dragService != null
                            ? () {
                              // 🎯 특수 노드 사이 클릭이면 셀렉 보류
                              if (_isSpecialNodeGapTap) {
                                setState(() {
                                  _isSpecialNodeGapTap = false;
                                });
                                return;
                              }
                              imageService.selectImage(widget.nodeId);
                            }
                            : null,
                    onLongPressStart:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 🎯 키보드 내리기 + 포커스 해제 (드래그 시작 시)
                              FocusManager.instance.primaryFocus?.unfocus();
                              FocusScope.of(context).unfocus();
                              // 드래그 시작
                              widget.dragService!.startDrag(
                                widget.nodeId,
                                context,
                                details.globalPosition,
                              );
                            }
                            : (d) => _showPreview(d.globalPosition),
                    onLongPressMoveUpdate:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 드래그 업데이트
                              widget.dragService!.updateDrag(
                                details.globalPosition,
                                context,
                              );
                            }
                            : (d) => _updatePreviewPosition(d.globalPosition),
                    onLongPressEnd:
                        widget.isEditing && widget.dragService != null
                            ? (_) {
                              // 드래그 종료
                              widget.dragService!.endDrag();
                            }
                            : (_) => _hidePreview(),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: marginTop,
                        bottom: marginBottom,
                      ),
                      child: Stack(
                        children: [
                          linkContent,
                          if (isSelectionHighlighted)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.4),
                                ),
                              ),
                            ),
                          if (isSelected || isDownstreamSelected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedSelectionBorder(
                                  isVisible: true,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        width: 4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // ✅ 드롭라인: dragService 변경 시 자동 rebuild (single_image_component와 동일한 방식)
                  if (widget.isEditing && widget.dragService != null)
                    Positioned.fill(
                      child: ListenableBuilder(
                        listenable: widget.dragService!,
                        builder: (context, _) {
                          return Stack(
                            children: [
                              if (_shouldShowTopDropLine())
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: AnimatedDropLine(
                                      child: Container(
                                        height: 5,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_shouldShowBottomDropLine())
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: AnimatedDropLine(
                                      child: Container(
                                        height: 5,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          // 아래쪽 패딩: 링크나 이미지, 멘션이 아래에 있으면 패딩 제거
          if (!hasImageBelow)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
        ],
      ),
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
    if (box == null) return Rect.zero;

    // upstream/downstream 위치일 때는 커서를 표시하지 않음 (사용자 요청)
    // selection 효과만 표시
    if (nodePosition is UpstreamDownstreamNodePosition) {
      return Offset.zero & box.size;
    }

    return Offset.zero & box.size;
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
      // 🎯 upstream 위치로 커서가 가지 못하도록 항상 downstream 반환
      const UpstreamDownstreamNodePosition.downstream();
  @override
  NodePosition getEndPositionNearX(double x) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  // 드래그 삽입 라인 표시 로직
  bool _shouldShowTopDropLine() {
    if (!widget.isEditing) return false;
    return DropLineConfig.shouldShowTopDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowBottomDropLine() {
    if (!widget.isEditing) return false;
    return DropLineConfig.shouldShowBottomDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
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
        // ✅ start 경계는 upstream일 때 포함 (아래→위 드래그 대칭 보장)
        return pos.affinity == TextAffinity.upstream;
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

  bool _hasNeighborImage(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;

    // 🎯 바로 인접한 노드 확인
    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        // 바로 인접한 노드가 특수 노드인 경우
        if (isSpecialNode(immediateNeighbor)) {
          return true;
        }

        // 바로 인접한 노드가 빈 ParagraphNode인 경우
        if (immediateNeighbor is ParagraphNode) {
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;

          // 빈 ParagraphNode면 그 다음 노드를 확인
          if (isEmpty) {
            // 빈 ParagraphNode 다음 노드 확인
            final nextIndex = immediateIndex + direction;
            if (nextIndex >= 0 && nextIndex < doc.nodeCount) {
              final nextNeighbor = doc.getNodeAt(nextIndex);
              if (isSpecialNode(nextNeighbor)) {
                // 빈 ParagraphNode를 사이에 둔 특수 노드 → 패딩 필요 (false 반환)
                return false;
              }
            }
            // 빈 ParagraphNode 다음에 특수 노드가 없으면 계속 검색
          } else if (!isEmpty) {
            // 텍스트가 있는 ParagraphNode → 패딩 필요
            return false;
          }
        } else {
          // 다른 타입의 노드면 패딩 필요
          return false;
        }
      }
    }

    // 🎯 빈 ParagraphNode를 건너뛰고 실제 특수 노드나 텍스트가 있는 노드를 찾음
    int searchIndex = myIndex + direction;
    while (searchIndex >= 0 && searchIndex < doc.nodeCount) {
      final neighbor = doc.getNodeAt(searchIndex);
      if (neighbor == null) break;

      // 특수 노드인 경우
      if (isSpecialNode(neighbor)) {
        return true;
      }

      // 빈 ParagraphNode가 아니면 (텍스트가 있는 경우) 패딩 필요
      if (neighbor is ParagraphNode) {
        final isEmpty = neighbor.text.text.trim().isEmpty;
        // 비어있지 않으면 텍스트 노드이므로 패딩 필요
        if (!isEmpty) {
          return false; // 텍스트 노드가 있으면 패딩 필요
        }
        // 빈 ParagraphNode면 계속 검색
      } else {
        // 다른 타입의 노드면 패딩 필요
        return false;
      }

      searchIndex += direction;
    }

    return false;
  }

  /// 썸네일 없을 때 아이콘 플레이스홀더
  Widget _buildIconPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color:
            widget.isDarkMode
                ? const Color(0xFF2C2C2E)
                : const Color(0xFFF2F2F7),
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
