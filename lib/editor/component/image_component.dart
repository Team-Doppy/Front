import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class CustomImageComponentBuilder implements ComponentBuilder {
  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageComponentViewModel) {
      return Image.network(
        componentViewModel.imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.shade300,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.broken_image, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  "이미지를 불러올 수 없습니다.",
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          );
        },
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
