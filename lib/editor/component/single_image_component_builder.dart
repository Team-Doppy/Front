import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/single_image_component.dart';

class SingleImageComponentBuilder implements ComponentBuilder {
  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageComponentViewModel) {
      return SingleImageComponent(
        nodeId: componentViewModel.nodeId,
        imageUrl: componentViewModel.imageUrl,
        componentKey: componentContext.componentKey,
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
      return ImageComponentViewModel(nodeId: node.id, imageUrl: node.imageUrl);
    }
    return null;
  }
}
