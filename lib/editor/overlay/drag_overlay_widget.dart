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

    // 🎯 클립 노드는 고정 크기 사용 (이미지 로드 중 깜빡임 방지)
    final bool isClipNode = widget.nodeType == 'clip';
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

    final double left = widget.position.dx - (width / 2);
    final double top = widget.position.dy - (height / 2);

    return Positioned(
      left: left,
      top: top,
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
    debugPrint('widget.nodeType: ${widget.nodeType}');

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
      case 'mention':
      case 'paragraph':
        preview = _buildParagraphPreview(node as dynamic, context);
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
                  child: Image.network(
                    node.thumbnailUrl,
                    width: 130,
                    height: 130,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => ImageErrorPlaceholder(),
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
      // 🎯 Image.network 사용
      baseImage = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ImageErrorPlaceholder(),
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
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Positioned.fill(child: baseImage),
            if (isPlaceholder)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
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

  Widget _buildClipPreview(ClipNode node) {
    // 🎯 썸네일 이미지 사용 (thumbnailPath 우선, 없으면 localPath, 없으면 metadata의 thumbnailUrl)
    String? thumb;
    if (node.thumbnailPath.isNotEmpty) {
      thumb = node.thumbnailPath;
    } else if (node.localPath.isNotEmpty) {
      thumb = node.localPath;
    } else {
      // metadata에서 썸네일 URL 확인
      try {
        final meta = node.metadata;
        if (meta['thumbnailUrl'] != null) {
          thumb = meta['thumbnailUrl'].toString();
        }
      } catch (_) {}
    }

    // placeholder: url 비어있고 localPath/thumbnailPath 존재 → 썸네일 파일 + 로딩 오버레이
    final bool isPlaceholder = node.url.isEmpty && node.localPath.isNotEmpty;

    Widget base;
    if (thumb != null && thumb.isNotEmpty) {
      // 썸네일 파일이 있으면 사용
      if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
        base = Image.network(
          thumb,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => ImageErrorPlaceholder(),
        );
      } else {
        // 로컬 파일 경로
        try {
          final file = File(thumb);
          if (file.existsSync()) {
            base = Image.file(file, fit: BoxFit.cover);
          } else {
            base = Container(
              color: Colors.black12,
              child: const Center(
                child: Icon(Icons.videocam, color: Colors.black45),
              ),
            );
          }
        } catch (_) {
          base = Container(
            color: Colors.black12,
            child: const Center(
              child: Icon(Icons.videocam, color: Colors.black45),
            ),
          );
        }
      }
    } else {
      // 썸네일이 없으면 기본 placeholder 표시 (비디오 URL을 이미지로 로드하지 않음)
      base = Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.videocam, color: Colors.black45)),
      );
    }

    // 🎯 이미지 노드와 동일하게 고정 크기 사용 (AspectRatio 제거로 깜빡임 방지)
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Positioned.fill(child: base),
            if (isPlaceholder)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.18),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                  ),
                ),
              ),
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

  Widget _buildSplitImagePreview(String imageUrl) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150, maxHeight: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => ImageErrorPlaceholder(),
        ),
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
    final bool isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final bool isFileUrl = imageUrl.startsWith('file://');
    final bool isLocalPath = !isNetwork && !isFileUrl && imageUrl.isNotEmpty;

    Widget imageWidget;
    if (isNetwork) {
      // 🎯 Image.network 사용
      imageWidget = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ImageErrorPlaceholder(),
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
}
