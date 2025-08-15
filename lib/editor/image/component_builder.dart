import 'package:doppy/editor/image/image_component.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../simple_grid.dart';
import '../spatial_manager.dart';

/// ImageNode를 InteractiveFloatingImage로 렌더링하는 ComponentBuilder
class InteractiveFloatingImageComponentBuilder implements ComponentBuilder {
  final SpatialManager? spatialManager;
  final GridSystem? gridSystem;
  final VoidCallback? onLayoutUpdateNeeded;

  InteractiveFloatingImageComponentBuilder({
    this.spatialManager,
    this.gridSystem,
    this.onLayoutUpdateNeeded,
  });

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageComponentViewModel) {
      return DocumentInteractiveFloatingImage(
        key: componentContext.componentKey,
        nodeId: componentViewModel.nodeId,
        imageUrl: componentViewModel.imageUrl,
        size: Size(
          componentViewModel.expectedSize?.width?.toDouble() ?? 200.0,
          componentViewModel.expectedSize?.height?.toDouble() ?? 200.0,
        ),
        initialScale: 1.0,
        spatialManager: spatialManager,
        gridSystem: gridSystem,
        onLayoutUpdateNeeded: onLayoutUpdateNeeded,
      );
    }

    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    return null;
  }
}
