import 'package:doppy/editor/postwrite_screen.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  final Map<String, GlobalKey> nodeKeys = {};

  EditorService({required this.editor});

  void moveNodeToIndex(String nodeId, int targetIndex) {
    final node = editor.document.getNodeById(nodeId);
    if (node == null) return;
    editor.document.deleteNode(nodeId);
    editor.document.insertNodeAt(targetIndex, node);
    notifyListeners();
  }

  NodeType getNodeType(String nodeId) {
    final node = editor.document.getNodeById(nodeId);
    switch (node) {
      case ParagraphNode():
        return NodeType.paragraph;
      case ImageNode():
        return NodeType.image;
      default:
        return NodeType.unknown;
    }
  }

  DocumentNode? findNodeAtPosition(Offset position) {
    for (final node in editor.document) {
      final key = nodeKeys[node.id];
      if (key == null || key.currentContext == null) continue;

      final box = key.currentContext!.findRenderObject() as RenderBox?;
      if (box == null) continue;

      final topLeft = box.localToGlobal(Offset.zero);
      final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
      if (position.dx >= topLeft.dx &&
          position.dx <= bottomRight.dx &&
          position.dy >= topLeft.dy &&
          position.dy <= bottomRight.dy) {
        return node;
      }
    }
    return null;
  }
}
