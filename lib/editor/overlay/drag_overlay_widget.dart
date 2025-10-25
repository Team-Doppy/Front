import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
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
        preview = _buildImagePreview(node as ImageNode);
        break;
      case 'imageRow':
        preview = _buildImageRowPreview(node as ImageRowNode);
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

  Widget _buildImagePreview(ImageNode node) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 350),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: _ImagePreviewContent(imageUrl: node.imageUrl),
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
}

class _ImagePreviewContent extends StatelessWidget {
  const _ImagePreviewContent({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return ImageErrorPlaceholder();
      },
    );
  }
}

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
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loading) {
                          if (loading == null) return child;
                          return Container(
                            height: _unifiedHeight ?? 200,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          return ImageErrorPlaceholder();
                        },
                        frameBuilder: (
                          context,
                          child,
                          frame,
                          wasSynchronouslyLoaded,
                        ) {
                          if (frame == null) return child;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _calculateImageSize(imageUrl, availableWidth);
                          });
                          return child;
                        },
                      ),
                    ),
                  ),
                );
              }).toList(),
        );
      },
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
