import 'package:doppy/editor/image/image_component.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../simple_grid.dart';
import '../spatial_manager.dart';

/// ImageNode를 InteractiveFloatingImage로 렌더링하는 ComponentBuilder
class InteractiveFloatingImageComponentBuilder implements ComponentBuilder {
  final SpatialManager? spatialManager;
  final GridSystem gridSystem;
  final VoidCallback? onLayoutUpdateNeeded;
  final ValueChanged<bool>? onDragModeChanged;

  InteractiveFloatingImageComponentBuilder({
    this.spatialManager,
    required this.gridSystem,
    this.onLayoutUpdateNeeded,
    this.onDragModeChanged,
  });

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageComponentViewModel) {
      final fallbackSize = Size(
        componentViewModel.expectedSize?.width?.toDouble() ?? 200.0,
        componentViewModel.expectedSize?.height?.toDouble() ?? 200.0,
      );

      return DocumentInteractiveFloatingImage(
        key: componentContext.componentKey,
        nodeId: componentViewModel.nodeId,
        imageUrl: componentViewModel.imageUrl,
        size: fallbackSize,
        initialScale: 1.0,
        spatialManager: spatialManager,
        gridSystem: gridSystem,
        onLayoutUpdateNeeded: onLayoutUpdateNeeded,
        onDragModeChanged: onDragModeChanged,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is ImageNode) {
      // ImageNode의 메타데이터에서 로컬 파일 경로 확인
      final isLocalFile = node.metadata['isLocalFile'] == true;
      final localFilePath = node.metadata['localFilePath'] as String?;

      //  로컬 파일이면 localFilePath 사용, 아니면 imageUrl 사용
      final effectiveImageUrl =
          isLocalFile && localFilePath != null ? localFilePath : node.imageUrl;

      final expectedWidth = (node.metadata['pxW'] as num?)?.toInt() ?? 200;
      final expectedHeight = (node.metadata['pxH'] as num?)?.toInt() ?? 150;

      return ImageComponentViewModel(
        nodeId: node.id,
        imageUrl: effectiveImageUrl,
        expectedSize: ExpectedSize(expectedWidth, expectedHeight),
        selection: null,
        selectionColor: Colors.transparent,
      );
    }
    return null;
  }
}

/// 실제 이미지 픽셀 크기를 비동기로 추출하여 자식 위젯에 전달하는 래퍼
class _DynamicImageSizer extends StatefulWidget {
  final String imageUrl;
  final String nodeId;
  final SpatialManager? spatialManager;
  final GridSystem gridSystem;
  final Size fallbackSize;
  final Widget Function(Size size) builder;
  final VoidCallback? onResolved;

  const _DynamicImageSizer({
    required this.imageUrl,
    required this.nodeId,
    required this.fallbackSize,
    required this.builder,
    required this.spatialManager,
    required this.gridSystem,
    this.onResolved,
  });

  @override
  State<_DynamicImageSizer> createState() => _DynamicImageSizerState();
}

class _DynamicImageSizerState extends State<_DynamicImageSizer> {
  Size? _resolved;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _DynamicImageSizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _disposeStream();
      _resolved = null;
      _resolve();
    }
  }

  void _resolve() {
    // 네트워크/에셋 이미지 모두 지원
    final ImageProvider provider =
        widget.imageUrl.startsWith('http')
            ? NetworkImage(widget.imageUrl)
            : AssetImage(widget.imageUrl) as ImageProvider;

    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener(
      (ImageInfo info, bool sync) {
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        if (!mounted) return;

        setState(() {
          _resolved = Size(width, height);
        });

        // SpatialManager 메타데이터에 pxW/pxH 기록 (가능한 경우)
        try {
          if (widget.spatialManager != null) {
            final element = widget.spatialManager!.getElement(widget.nodeId);
            if (element != null) {
              final newMetadata = Map<String, dynamic>.from(element.metadata);
              newMetadata['pxW'] = width.toInt();
              newMetadata['pxH'] = height.toInt();
              newMetadata['isImageNode'] = true;
              widget.spatialManager!.updateElement(
                id: widget.nodeId,
                type: SpatialElementType.image,
                coordinates: element.coordinates,
                size: element.size,
                metadata: newMetadata,
              );
            }
          }
        } catch (_) {}

        widget.onResolved?.call();
      },
      onError: (dynamic _, __) {
        // 실패 시에는 fallback 유지
      },
    );
    _stream!.addListener(_listener!);
  }

  void _disposeStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _disposeStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _resolved ?? widget.fallbackSize;
    return widget.builder(size);
  }
}
