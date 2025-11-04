import 'dart:io';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 드래그 중인 컴포넌트의 미리보기를 보여주는 오버레이 위젯
class DragOverlayWidget extends StatefulWidget {
  const DragOverlayWidget({
    required this.nodeId,
    required this.nodeType,
    required this.position,
    required this.document,
    this.splitImageUrl,
    super.key,
  });

  final String nodeId;
  final String nodeType;
  final Offset position;
  final Document document;
  final String? splitImageUrl;

  @override
  State<DragOverlayWidget> createState() => _DragOverlayWidgetState();
}

class _DragOverlayWidgetState extends State<DragOverlayWidget> {
  final GlobalKey _previewKey = GlobalKey();
  Size? _childSize;

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

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChild());

    final double width = _childSize?.width ?? 160.0;
    final double height = _childSize?.height ?? 120.0;
    final double left = widget.position.dx - (width / 2);
    final double top = widget.position.dy - (height / 2);

    return Positioned(
      left: left,
      top: top,
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
    );
  }

  Widget _buildNodePreview(BuildContext context) {
    // 커스텀 이미지 URL이 있으면 해당 이미지 표시
    if (widget.splitImageUrl != null && widget.nodeType == 'image') {
      return _buildSplitImagePreview(widget.splitImageUrl!);
    }

    final node = widget.document.getNodeById(widget.nodeId);
    if (node == null) return const SizedBox.shrink();

    Widget preview;

    switch (widget.nodeType) {
      case 'image':
        preview = _buildImagePreview(node);
        break;
      case 'imageRow':
        preview = _buildImageRowPreview(node as ImageRowNode);
        break;
      case 'divider':
        preview = _buildDividerPreview();
        break;
      case 'clip':
        preview = _buildClipPreview(node as ClipNode);
        break;

      case 'paragraph':
        preview = _buildParagraphPreview(node as dynamic, context); // 타입 캐스팅 제거
        break;
      case 'link':
        preview = _buildLinkPreview(node as LinkNode);
        break;
      default:
        preview = _buildDefaultPreview(node);
    }

    return preview;
  }

  Widget _buildLinkPreview(LinkNode node) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,

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
                  child: Image.network(
                    node.thumbnailUrl,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stack) => ImageErrorPlaceholder(),
                  ),
                )
              else
                Container(
                  width: 100,
                  height: 100,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(Icons.link, color: Colors.white54),
                ),
            ],
          ),
        ),
        if (node.thumbnailUrl.isNotEmpty)
          Positioned(child: Icon(Icons.link, color: Colors.white54)),
      ],
    );
  }

  Widget _buildImagePreview(dynamic node) {
    // AppImageNode 또는 ImageNode 모두 지원: placeholder면 로컬 경로 + 로딩 오버레이
    String imageUrl = '';
    try {
      imageUrl = (node as dynamic).imageUrl as String? ?? '';
    } catch (_) {}
    Map<String, dynamic>? meta;
    try {
      meta = (node as dynamic).metadata as Map<String, dynamic>?;
    } catch (_) {}
    final bool isPlaceholder =
        imageUrl.isEmpty ||
        (meta != null && meta['isPlaceholder'] == true) ||
        imageUrl.startsWith('file://');
    String? localPath;
    try {
      localPath = meta != null ? (meta['localPath']?.toString()) : null;
    } catch (_) {}

    Widget baseImage;
    if (isPlaceholder && (localPath != null && localPath.isNotEmpty)) {
      baseImage = Image.file(File(localPath), fit: BoxFit.cover);
    } else if (imageUrl.startsWith('http://') ||
        imageUrl.startsWith('https://')) {
      baseImage = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => ImageErrorPlaceholder(),
      );
    } else if (imageUrl.startsWith('file://')) {
      baseImage = Image.file(
        File(Uri.parse(imageUrl).toFilePath()),
        fit: BoxFit.cover,
      );
    } else {
      baseImage = ImageErrorPlaceholder();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 350),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Positioned.fill(child: baseImage),
            if (isPlaceholder)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageRowPreview(ImageRowNode node) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: _ImageRowPreviewContent(
          imageUrls: node.imageUrls,
          spacing: node.spacing,
        ),
      ),
    );
  }

  Widget _buildParagraphPreview(dynamic node, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        node.text.text,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: 1,
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

  Widget _buildClipPreview(ClipNode node) {
    // placeholder: url 비어있고 localPath/thumbnailPath 존재 → 썸네일 파일 + 로딩 오버레이
    final bool isPlaceholder = node.url.isEmpty && node.localPath.isNotEmpty;
    final String thumb =
        (node.thumbnailPath.isNotEmpty) ? node.thumbnailPath : node.localPath;

    Widget base;
    if (isPlaceholder && thumb.isNotEmpty) {
      base = Image.file(File(thumb), fit: BoxFit.cover);
    } else if (node.url.isNotEmpty) {
      base = Image.network(
        node.url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => ImageErrorPlaceholder(),
      );
    } else {
      base = Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.videocam, color: Colors.black45)),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 180),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(child: base),
            if (isPlaceholder)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitImagePreview(String imageUrl) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 350),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return ImageErrorPlaceholder();
          },
        ),
      ),
    );
  }

  Widget _buildDividerPreview() {
    final Color lineColor = Colors.black.withOpacity(0.06);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 260,
        minWidth: 180,
        minHeight: 44,
        maxHeight: 64,
      ),
      child: Container(
        width: 240,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.06)),
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
  final Map<String, Size> _imageSizes = {};
  double? _unifiedHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        return Row(
          children:
              widget.imageUrls.map((imageUrl) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 1),
                    child: SizedBox(
                      height: _unifiedHeight ?? 200,
                      child: _buildRowImageTile(imageUrl, availableWidth),
                    ),
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildRowImageTile(String imageUrl, double availableWidth) {
    final bool isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final bool isFileUrl = imageUrl.startsWith('file://');
    final bool isLocalPath = !isNetwork && !isFileUrl && imageUrl.isNotEmpty;

    Widget imageWidget;
    if (isNetwork) {
      imageWidget = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => ImageErrorPlaceholder(),
        frameBuilder: (context, child, frame, wasSync) {
          if (frame == null) return child;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _calculateImageSize(imageUrl, availableWidth);
          });
          return child;
        },
      );
    } else if (isFileUrl || isLocalPath) {
      final String path =
          isFileUrl ? Uri.parse(imageUrl).toFilePath() : imageUrl;
      imageWidget = Image.file(File(path), fit: BoxFit.cover);
    } else {
      imageWidget = ImageErrorPlaceholder();
    }

    final bool showOverlay = (isFileUrl || isLocalPath);

    return Stack(
      children: [
        Positioned.fill(child: imageWidget),
        if (showOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.18),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _calculateImageSize(String imageUrl, double availableWidth) {
    if (_imageSizes.containsKey(imageUrl)) return;

    Image.network(imageUrl).image
        .resolve(const ImageConfiguration())
        .addListener(
          ImageStreamListener((ImageInfo info, bool synchronousCall) {
            if (mounted) {
              _imageSizes[imageUrl] = Size(
                info.image.width.toDouble(),
                info.image.height.toDouble(),
              );

              if (_imageSizes.length == widget.imageUrls.length) {
                final count = widget.imageUrls.length;
                final spacingWidth = widget.spacing * (count - 1);
                final eachWidth = (availableWidth - spacingWidth) / count;

                final heights = <double>[];
                for (final url in widget.imageUrls) {
                  final s = _imageSizes[url];
                  if (s == null || s.width == 0) continue;
                  heights.add(eachWidth * (s.height / s.width));
                }
                if (heights.isEmpty) return;

                heights.sort();
                final start = (heights.length * 0.2).floor();
                final end = (heights.length * 0.8).ceil();
                final filtered = heights.sublist(start, end);
                final avg = filtered.reduce((a, b) => a + b) / filtered.length;

                final unified = avg.clamp(150.0, 400.0);
                if (_unifiedHeight != unified) {
                  setState(() => _unifiedHeight = unified);
                }
              }
            }
          }),
        );
  }
}
