import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:doppy/editor/component/image_row_component.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class RowImageComponentBuilder implements ComponentBuilder {
  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageRowComponentViewModel) {
      // ⚠️ 여기서 일반 위젯이 아니라 DocumentComponent를 리턴!
      return ImageRowComponent(
        nodeId: componentViewModel.nodeId,
        imageUrls: componentViewModel.imageUrls,
        spacing: componentViewModel.spacing,
        componentKey: componentContext.componentKey, // ← 매우 중요
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is ImageRowNode) {
      return ImageRowComponentViewModel(
        nodeId: node.id,
        imageUrls: node.imageUrls,
        spacing: node.spacing,
      );
    }
    return null;
  }
}
