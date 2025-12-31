import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/editor/component/divider_component.dart' show DividerNode;
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/nodes/mention_node.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/image/utils/edit_image_cache_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

Widget _buildFastCachedNetworkImage(
  BuildContext context, {
  required String imageUrl,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  Widget? placeholder,
  Widget? errorWidget,
}) {
  final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
  final int? memCacheWidth = width != null ? (width * dpr).round() : null;
  final int? memCacheHeight = height != null ? (height * dpr).round() : null;

  return CachedNetworkImage(
    imageUrl: imageUrl,
    cacheKey: imageUrl, // 🎯 명시적 캐시 키 지정 (메인 에디터와 동일한 키 사용)
    cacheManager: EditImageCacheManager.instance, // 🎯 메인 에디터와 동일한 캐시 매니저 사용
    width: width,
    height: height,
    fit: fit,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    placeholderFadeInDuration: Duration.zero,
    useOldImageOnUrlChange: true,
    placeholder:
        (context, _) => placeholder ?? Container(color: Colors.black12),
    errorWidget: (context, _, __) => errorWidget ?? ImageErrorPlaceholder(),
  );
}

/// 드래그 중인 컴포넌트의 미리보기를 보여주는 오버레이 위젯
class DragOverlayWidget extends StatefulWidget {
  const DragOverlayWidget({
    required this.position,
    required this.document,
    this.node,
    this.splitImageUrl,
    this.previewImageLocalPath, // 🎯 클립 노드 썸네일 깜빡임 방지
    this.previewImageUrl, // 🚀 네트워크 URL (로컬-네트워크 혼용 구조)
    super.key,
  });

  final DocumentNode? node;
  final Offset position;
  final Document document;
  final String? splitImageUrl;
  final String? previewImageLocalPath;
  final String? previewImageUrl; // 🚀 네트워크 URL

  @override
  State<DragOverlayWidget> createState() => _DragOverlayWidgetState();
}

class _DragOverlayWidgetState extends State<DragOverlayWidget>
    with SingleTickerProviderStateMixin {
  final GlobalKey _previewKey = GlobalKey();
  Size? _childSize;
  bool _measureScheduled = false;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _measureChild() {
    final ctx = _previewKey.currentContext;
    if (ctx == null) return;
    final render = ctx.findRenderObject() as RenderBox?;
    if (render == null) return;
    final size = render.size;
    if (_childSize == null || _childSize != size) {
      setState(() => _childSize = size);
    }
  }

  void _scheduleMeasureIfNeeded() {
    if (_measureScheduled) return;
    // ClipNode는 고정 크기를 쓰므로 측정 불필요
    if (widget.node is ClipNode) return;
    // 이미 사이즈가 잡혔으면 드래그 중 매 프레임 측정하지 않음
    if (_childSize != null) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _measureChild();
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasureIfNeeded();

    // 🎯 클립 노드는 고정 크기 사용 (이미지 로드 중 깜빡임 방지)
    final bool isClipNode = widget.node is ClipNode;
    final double width;
    final double height;

    if (isClipNode) {
      // 클립 노드는 고정 크기 (이미지 노드와 동일)
      width = 150.0;
      height = 220.0;
    } else {
      width = _childSize?.width ?? 160.0;
      height = _childSize?.height ?? 120.0;
    }

    // ✅ 손가락 위치가 오버레이의 정확히 가운데에 오도록 설정
    final double left = widget.position.dx - (width / 2);
    final double top = widget.position.dy - (height / 2);

    return Positioned(
      left: left,
      top: top,
      // ⚠️ Positioned는 반드시 Stack의 direct child여야 한다.
      // IgnorePointer는 Positioned 안쪽에 두어 ParentDataWidget 사용 오류를 피한다.
      child: IgnorePointer(
        ignoring: true,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Opacity(
              opacity: 0.7, // 🎯 70% 투명도로 뒤의 텍스트가 보이게
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: KeyedSubtree(
                    key: _previewKey,
                    child: _buildNodePreview(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodePreview(BuildContext context) {
    // 🎯 분리 이미지 URL이 있으면 해당 이미지 표시
    if (widget.splitImageUrl != null) {
      return _buildSplitImagePreview(widget.splitImageUrl!);
    }

    final node = widget.node;
    if (node == null) {
      assert(() {
        debugPrint('[DragOverlay] 노드가 없음');
        return true;
      }());
      return const SizedBox.shrink();
    }

    assert(() {
      if (kDebugMode) {
        debugPrint('[DragOverlay] 노드 타입: ${node.runtimeType}');
      }
      return true;
    }());

    // 🎯 노드 타입에 따라 직접 분기
    if (node is ImageNode) {
      return _buildImagePreview(node);
    } else if (node is ImageRowNode) {
      return _buildImageRowPreview(node);
    } else if (node is PageViewImageNode) {
      return _buildPageViewImagePreview(node);
    } else if (node is ClipNode) {
      assert(() {
        if (kDebugMode) debugPrint('[DragOverlay] ClipNode 처리 시작');
        return true;
      }());
      return _ClipPreviewWidget(
        node: node,
        previewImageLocalPath: widget.previewImageLocalPath, // 🎯 미리 추출된 경로 전달
      );
    } else if (node is LinkNode) {
      return _buildLinkPreview(node);
    } else if (node is DividerNode) {
      return _buildDividerPreview();
    } else if (node is MentionNode) {
      return _buildMentionPreview(node, context);
    } else if (node is ParagraphNode) {
      return _buildParagraphPreview(node, context);
    } else {
      return _buildDefaultPreview(node);
    }
  }

  Widget _buildLinkPreview(LinkNode node) {
    return Stack(
      children: [
        Container(
          width: 130,
          height: 130,

          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (node.thumbnailUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                  child: _buildFastCachedNetworkImage(
                    context,
                    imageUrl: node.thumbnailUrl,
                    width: 130,
                    height: 130,
                    fit: BoxFit.contain,
                    placeholder: Container(
                      width: 130,
                      height: 130,
                      color: const Color(0xFF2A2A2A),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.link,
                        color: Colors.white54,
                        size: 28,
                      ),
                    ),
                    errorWidget: ImageErrorPlaceholder(),
                  ),
                )
              else
                Container(
                  width: 130,
                  height: 130,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(
                    Icons.link,
                    color: Colors.white54,
                    size: 28,
                  ),
                ),
            ],
          ),
        ),
        if (node.thumbnailUrl.isNotEmpty)
          Positioned(
            right: 8,
            top: 8,
            child: Icon(Icons.link, color: Colors.white54, size: 20),
          ),
      ],
    );
  }

  Widget _buildImagePreview(dynamic node) {
    String imageUrl = '';
    try {
      imageUrl = (node as dynamic).imageUrl as String? ?? '';
    } catch (_) {}
    Map<String, dynamic>? meta;
    try {
      meta = (node as dynamic).metadata as Map<String, dynamic>?;
    } catch (_) {}

    // 🚀 로컬-네트워크 혼용 구조: previewImageLocalPath 우선 사용
    String? localPath = widget.previewImageLocalPath;
    if (localPath == null || localPath.isEmpty) {
      // previewImageLocalPath가 없으면 노드에서 추출
      try {
        localPath = meta != null ? (meta['localPath']?.toString()) : null;
      } catch (_) {}

      // imageUrl이 로컬 경로인 경우도 확인
      if ((localPath == null || localPath.isEmpty) &&
          imageUrl.isNotEmpty &&
          !EditorService.isNetworkUrl(imageUrl) &&
          !imageUrl.startsWith('file://')) {
        localPath = imageUrl;
      }
    }

    Widget baseImage;
    // 🚀 로컬 경로 우선 처리
    if (localPath != null && localPath.isNotEmpty) {
      baseImage = Image.file(File(localPath), fit: BoxFit.contain);
    } else if (widget.previewImageUrl != null &&
        widget.previewImageUrl!.isNotEmpty) {
      // previewImageUrl 사용 (네트워크 URL)
      baseImage = _buildFastCachedNetworkImage(
        context,
        imageUrl: widget.previewImageUrl!,
        fit: BoxFit.contain,
        errorWidget: ImageErrorPlaceholder(),
      );
    } else if (EditorService.isNetworkUrl(imageUrl)) {
      // 노드의 imageUrl이 네트워크 URL인 경우
      baseImage = _buildFastCachedNetworkImage(
        context,
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        errorWidget: ImageErrorPlaceholder(),
      );
    } else if (imageUrl.startsWith('file://')) {
      baseImage = Image.file(
        File(Uri.parse(imageUrl).toFilePath()),
        fit: BoxFit.contain,
      );
    } else if (imageUrl.isNotEmpty) {
      // 로컬 경로로 간주
      baseImage = Image.file(File(imageUrl), fit: BoxFit.contain);
    } else {
      baseImage = ImageErrorPlaceholder();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: baseImage,
      ),
    );
  }

  Widget _buildImageRowPreview(ImageRowNode node) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, maxHeight: 180),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: _ImageRowPreviewContent(
          imageUrls: node.imageUrls,
          spacing: node.spacing,
        ),
      ),
    );
  }

  Widget _buildPageViewImagePreview(PageViewImageNode node) {
    // 🎯 분리 모드: previewImageUrl이나 previewImageLocalPath가 있으면 단일 이미지 표시
    if (widget.previewImageUrl != null && widget.previewImageUrl!.isNotEmpty) {
      return _buildSplitImagePreview(widget.previewImageUrl!);
    }
    if (widget.previewImageLocalPath != null &&
        widget.previewImageLocalPath!.isNotEmpty) {
      return _buildSplitImagePreview(widget.previewImageLocalPath!);
    }

    // 페이지뷰 느낌: 여러 이미지가 겹쳐있는 효과
    if (node.imageUrls.isEmpty) {
      return _buildDefaultPreview(node);
    }

    // 최대 3개의 이미지만 표시 (겹침 효과)
    final displayCount = node.imageUrls.length > 3 ? 3 : node.imageUrls.length;
    final imageUrls = node.imageUrls.take(displayCount).toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 뒤에서부터 앞으로 쌓기 (역순으로)
          for (int i = imageUrls.length - 1; i >= 0; i--)
            Positioned(
              left: i * 8.0, // 8px씩 오른쪽으로 이동
              top: i * 8.0, // 8px씩 아래로 이동
              child: Container(
                width: 150,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _buildPageViewImageTile(imageUrls[i]),
                ),
              ),
            ),
          // 이미지 개수 표시 (맨 앞 이미지 위에)
          Positioned(
            left: (displayCount - 1) * 8.0 + 6,
            bottom: (displayCount - 1) * 8.0 + 6,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${node.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageViewImageTile(String imageUrl) {
    final bool isNetwork = EditorService.isNetworkUrl(imageUrl);
    final bool isFileUrl = imageUrl.startsWith('file://');
    final bool isLocalPath = !isNetwork && !isFileUrl && imageUrl.isNotEmpty;

    Widget imageWidget;
    if (isNetwork) {
      imageWidget = _buildFastCachedNetworkImage(
        context,
        imageUrl: imageUrl,
        width: 150,
        height: 220,
        fit: BoxFit.contain,
        errorWidget: ImageErrorPlaceholder(),
      );
    } else if (isFileUrl || isLocalPath) {
      final String path =
          isFileUrl ? Uri.parse(imageUrl).toFilePath() : imageUrl;
      imageWidget = Image.file(File(path), fit: BoxFit.contain);
    } else {
      imageWidget = ImageErrorPlaceholder();
    }

    return imageWidget;
  }

  Widget _buildParagraphPreview(dynamic node, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        node.text.text,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDefaultPreview(DocumentNode node) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description, size: 24, color: Colors.grey.shade600),
          const SizedBox(height: 8),
          Text(
            node.runtimeType.toString(),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitImagePreview(String imageUrl) {
    // 🚀 로컬-네트워크 혼용 구조: 로컬 경로인지 확인
    final bool isNetwork = EditorService.isNetworkUrl(imageUrl);
    final bool isFileUrl = imageUrl.startsWith('file://');
    final bool isLocalPath = !isNetwork && !isFileUrl && imageUrl.isNotEmpty;

    Widget imageWidget;
    if (isNetwork) {
      // 네트워크 이미지
      imageWidget = _buildFastCachedNetworkImage(
        context,
        imageUrl: imageUrl,
        width: 150,
        height: 220,
        fit: BoxFit.contain,
        errorWidget: ImageErrorPlaceholder(),
      );
    } else if (isFileUrl || isLocalPath) {
      // 로컬 파일 경로
      final String path =
          isFileUrl ? Uri.parse(imageUrl).toFilePath() : imageUrl;
      imageWidget = Image.file(File(path), fit: BoxFit.contain);
    } else {
      imageWidget = ImageErrorPlaceholder();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: imageWidget,
      ),
    );
  }

  Widget _buildMentionPreview(MentionNode node, BuildContext context) {
    final usernames = node.usernames;
    if (usernames.isEmpty) {
      return _buildDefaultPreview(node);
    }

    final fontSize = (node.metadata['fontSize'] as num?)?.toDouble() ?? 16.0;
    final textAlign = node.metadata['textAlign'] as String?;

    // 정렬에 따라 CrossAxisAlignment 결정
    CrossAxisAlignment crossAlign;
    MainAxisAlignment mainAlign;
    switch (textAlign) {
      case 'left':
        crossAlign = CrossAxisAlignment.start;
        mainAlign = MainAxisAlignment.start;
        break;
      case 'right':
        crossAlign = CrossAxisAlignment.end;
        mainAlign = MainAxisAlignment.end;
        break;
      case 'center':
      default:
        crossAlign = CrossAxisAlignment.center;
        mainAlign = MainAxisAlignment.center;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 240),
      child: Row(
        mainAxisAlignment: mainAlign,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: crossAlign,
              mainAxisSize: MainAxisSize.min,
              children:
                  usernames.map((username) {
                    return Text(
                      '@$username',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDividerPreview() {
    final Color lineColor = Colors.white.withOpacity(0.3);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 260,
        minWidth: 180,
        minHeight: 44,
        maxHeight: 64,
      ),
      child: Container(
        width: 240,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // subtle background gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.grey.withOpacity(0.04),
                      Colors.grey.withOpacity(0.02),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // divider line
            Container(
              height: 2.2,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// (unused) legacy image preview widget removed after placeholder unification

class _ImageRowPreviewContent extends StatefulWidget {
  const _ImageRowPreviewContent({
    required this.imageUrls,
    required this.spacing,
  });

  final List<String> imageUrls;
  final double spacing;

  @override
  State<_ImageRowPreviewContent> createState() =>
      _ImageRowPreviewContentState();
}

class _ImageRowPreviewContentState extends State<_ImageRowPreviewContent> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children:
              widget.imageUrls.map((imageUrl) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 1),
                    child: SizedBox(
                      height: 180,
                      child: _buildRowImageTile(imageUrl),
                    ),
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildRowImageTile(String imageUrl) {
    final bool isNetwork = EditorService.isNetworkUrl(imageUrl);
    final bool isFileUrl = imageUrl.startsWith('file://');
    final bool isLocalPath = !isNetwork && !isFileUrl && imageUrl.isNotEmpty;

    Widget imageWidget;
    if (isNetwork) {
      imageWidget = _buildFastCachedNetworkImage(
        context,
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        errorWidget: ImageErrorPlaceholder(),
      );
    } else if (isFileUrl || isLocalPath) {
      final String path =
          isFileUrl ? Uri.parse(imageUrl).toFilePath() : imageUrl;
      imageWidget = Image.file(File(path), fit: BoxFit.contain);
    } else {
      imageWidget = ImageErrorPlaceholder();
    }

    return imageWidget;
  }
}

/// ClipNode 썸네일 미리보기 위젯 (썸네일이 없으면 동적으로 생성)
class _ClipPreviewWidget extends StatefulWidget {
  const _ClipPreviewWidget({
    required this.node,
    this.previewImageLocalPath, // 🎯 미리 추출된 로컬 경로 (깜빡임 방지)
  });

  final ClipNode node;
  final String? previewImageLocalPath;

  @override
  State<_ClipPreviewWidget> createState() => _ClipPreviewWidgetState();
}

class _ClipPreviewWidgetState extends State<_ClipPreviewWidget> {
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    // 🎯 미리 추출된 경로가 없을 때만 로드 (깜빡임 방지)
    if (widget.previewImageLocalPath == null ||
        widget.previewImageLocalPath!.isEmpty) {
      _loadThumbnail();
    }
  }

  void _loadThumbnail() {
    debugPrint('[DragOverlay] _loadThumbnail 시작: nodeId=${widget.node.id}');
    debugPrint('[DragOverlay] thumbnailPath: ${widget.node.thumbnailPath}');
    debugPrint('[DragOverlay] url: ${widget.node.url}');

    // 🎯 썸네일 이미지 사용 (thumbnailPath 우선, 없으면 전역 캐시 확인, 없으면 metadata의 thumbnailUrl)
    String? thumb;
    if (widget.node.thumbnailPath.isNotEmpty) {
      thumb = widget.node.thumbnailPath;
      debugPrint('[DragOverlay] 썸네일 경로 (thumbnailPath): $thumb');
    } else {
      // 🎯 전역 썸네일 캐시에서 확인
      if (videoThumbnailCache.containsKey(widget.node.url)) {
        final cachedBytes = videoThumbnailCache[widget.node.url];
        if (cachedBytes != null) {
          debugPrint(
            '[DragOverlay] 캐시에서 썸네일 발견: ${widget.node.url} (${cachedBytes.length} bytes)',
          );
          if (mounted) {
            setState(() {
              _thumbnailBytes = cachedBytes;
            });
          }
          return;
        }
      } else {
        // metadata에서 썸네일 URL 확인
        try {
          final meta = widget.node.metadata;
          if (meta['thumbnailUrl'] != null) {
            thumb = meta['thumbnailUrl'].toString();
            debugPrint('[DragOverlay] 썸네일 URL (metadata): $thumb');
          }
        } catch (_) {}
      }
    }

    // 썸네일 파일이 있으면 로드
    if (thumb != null && thumb.isNotEmpty) {
      if (EditorService.isNetworkUrl(thumb)) {
        // 네트워크 이미지는 그대로 사용 (이미지 위젯에서 처리)
        debugPrint('[DragOverlay] 네트워크 썸네일 URL: $thumb');
        return;
      } else {
        // 로컬 파일 경로
        try {
          final file = File(thumb);
          if (file.existsSync()) {
            debugPrint('[DragOverlay] 로컬 썸네일 파일 로드: $thumb');
            file.readAsBytes().then((bytes) {
              if (mounted) {
                setState(() {
                  _thumbnailBytes = bytes;
                });
              }
            });
          } else {
            debugPrint('[DragOverlay] 로컬 썸네일 파일이 존재하지 않음: $thumb');
          }
        } catch (e) {
          debugPrint('[DragOverlay] 로컬 파일 로드 오류: $e');
        }
      }
    } else {
      debugPrint('[DragOverlay] 썸네일 소스 없음 (캐시에도 없음)');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 미리 추출된 로컬 경로 우선 사용 (깜빡임 방지)
    String? thumb = widget.previewImageLocalPath;

    // 미리 추출된 값이 없으면 노드에서 가져오기
    if (thumb == null || thumb.isEmpty) {
      if (widget.node.thumbnailPath.isNotEmpty) {
        thumb = widget.node.thumbnailPath;
      } else {
        // 🎯 전역 썸네일 캐시에서 확인
        if (videoThumbnailCache.containsKey(widget.node.url)) {
          final cachedBytes = videoThumbnailCache[widget.node.url];
          if (cachedBytes != null && _thumbnailBytes == null) {
            if (mounted) {
              setState(() {
                _thumbnailBytes = cachedBytes;
              });
            }
          }
        } else {
          // metadata에서 썸네일 URL 확인
          try {
            final meta = widget.node.metadata;
            if (meta['thumbnailUrl'] != null) {
              thumb = meta['thumbnailUrl'].toString();
              debugPrint('[DragOverlay] 썸네일 URL (metadata): $thumb');
            }
          } catch (_) {}
        }
      }
    }

    Widget base;

    // 생성된 썸네일 바이트가 있으면 사용
    if (_thumbnailBytes != null) {
      debugPrint(
        '[DragOverlay] 생성된 썸네일 바이트 사용: ${_thumbnailBytes!.length} bytes',
      );
      base = Image.memory(_thumbnailBytes!, fit: BoxFit.contain);
    } else if (thumb != null && thumb.isNotEmpty) {
      // 썸네일 파일이 있으면 사용
      if (EditorService.isNetworkUrl(thumb)) {
        debugPrint('[DragOverlay] 네트워크 이미지 로드: $thumb');
        base = _buildFastCachedNetworkImage(
          context,
          imageUrl: thumb,
          width: 150,
          height: 220,
          fit: BoxFit.contain,
          errorWidget: _buildPlaceholder(),
          placeholder: Container(
            width: 150,
            height: 220,
            color: Colors.black12,
          ),
        );
      } else {
        // 로컬 파일 경로
        try {
          final file = File(thumb);
          if (file.existsSync()) {
            debugPrint('[DragOverlay] 로컬 파일 이미지 로드: $thumb');
            base = Image.file(file, fit: BoxFit.contain);
          } else {
            debugPrint('[DragOverlay] 로컬 파일이 존재하지 않음: $thumb');
            base = _buildPlaceholder();
          }
        } catch (e) {
          debugPrint('[DragOverlay] 로컬 파일 로드 오류: $e');
          base = _buildPlaceholder();
        }
      }
    } else {
      // 썸네일이 없으면 기본 placeholder 표시
      debugPrint(
        '[DragOverlay] 썸네일 없음 - 기본 placeholder 표시 (url: ${widget.node.url})',
      );
      base = _buildPlaceholder();
    }

    // 🎯 이미지 노드와 동일하게 고정 크기 사용 (AspectRatio 제거로 깜빡임 방지)
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Positioned.fill(child: base),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: const Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 150,
      height: 220,
      color: Colors.black12,
      child: const Center(
        child: Icon(Icons.videocam, color: Colors.black45, size: 48),
      ),
    );
  }
}
