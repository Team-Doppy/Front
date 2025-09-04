import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/model/image_row_node.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  GlobalKey? _documentLayoutKey;

  EditorService({required this.editor});

  void setDocumentLayoutKey(GlobalKey key) {
    _documentLayoutKey = key;
  }

  GlobalKey? get documentLayoutKey => _documentLayoutKey;

  void reorderNode(String nodeId, int targetIndex) {
    final node = editor.document.getNodeById(nodeId);
    if (node == null) return;

    // 현재 노드의 인덱스 찾기
    int currentIndex = -1;
    for (int i = 0; i < editor.document.length; i++) {
      if (editor.document.getNodeAt(i)?.id == nodeId) {
        currentIndex = i;
        break;
      }
    }

    if (currentIndex == -1) return;

    // 같은 위치면 이동하지 않음
    if (currentIndex == targetIndex) return;

    // 노드 삭제 후 새 위치에 삽입
    editor.document.deleteNode(nodeId);

    // targetIndex가 현재 인덱스보다 작으면 그대로 삽입
    // targetIndex가 현재 인덱스보다 크면 1을 빼서 삽입 (삭제로 인한 인덱스 변화)
    final insertIndex =
        targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
    editor.document.insertNodeAt(insertIndex, node);
    notifyListeners();
  }

  /// 두 이미지를 가로 배치로 합치는 함수
  void mergeImagesIntoRow(
    String draggingImageId,
    String targetImageId, {
    bool isFromLeft = true,
  }) {
    final draggingNode = editor.document.getNodeById(draggingImageId);
    final targetNode = editor.document.getNodeById(targetImageId);

    if (draggingNode == null || targetNode == null) return;
    if (draggingNode is! ImageNode || targetNode is! ImageNode) return;

    // 두 이미지의 URL 수집
    final imageUrls = <String>[];

    // 드래그 중인 이미지가 타겟 이미지보다 앞에 있으면 먼저 추가
    int draggingIndex = -1;
    int targetIndex = -1;

    for (int i = 0; i < editor.document.length; i++) {
      final node = editor.document.getNodeAt(i);
      if (node?.id == draggingImageId) draggingIndex = i;
      if (node?.id == targetImageId) targetIndex = i;
    }

    if (draggingIndex == -1 || targetIndex == -1) return;

    // 방향에 따라 이미지 순서 결정
    if (isFromLeft) {
      // 왼쪽에서 오는 경우: 드래그 이미지가 왼쪽에
      imageUrls.add(draggingNode.imageUrl);
      imageUrls.add(targetNode.imageUrl);
    } else {
      // 오른쪽에서 오는 경우: 타겟 이미지가 왼쪽에
      imageUrls.add(targetNode.imageUrl);
      imageUrls.add(draggingNode.imageUrl);
    }

    // ImageRowNode 생성
    final imageRowNode = ImageRowNode(
      id: 'imageRow_${DateTime.now().millisecondsSinceEpoch}',
      imageUrls: imageUrls,
      spacing: 8.0,
    );

    // 기존 이미지들 삭제
    editor.document.deleteNode(draggingImageId);
    editor.document.deleteNode(targetImageId);

    // ImageRowNode 삽입 (더 작은 인덱스 위치에)
    final insertIndex =
        draggingIndex < targetIndex ? draggingIndex : targetIndex;
    editor.document.insertNodeAt(insertIndex, imageRowNode);
    notifyListeners();
  }

  NodeType getNodeType(String nodeId) {
    final node = editor.document.getNodeById(nodeId);
    switch (node) {
      case ParagraphNode():
        // 이미지 노드는 특별한 텍스트로 구분
        if (node.text.text.contains('🖼️')) {
          return NodeType.image;
        }
        return NodeType.paragraph;
      case ImageNode():
        return NodeType.image;
      default:
        return NodeType.unknown;
    }
  }

  DocumentNode? findNodeAtPosition(Offset position) {
    position = Offset(position.dx, position.dy - 120);
    final documentLayout = _documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) return null;

    try {
      // SuperEditor 내장 함수 사용
      final documentPosition = documentLayout
          .getDocumentPositionNearestToOffset(position);
      if (documentPosition == null) return null;

      return editor.document.getNodeById(documentPosition.nodeId);
    } catch (e) {
      print("Error finding node at position: $e");
      return null;
    }
  }
}
