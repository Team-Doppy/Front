import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;

  EditorService({required this.editor, required this.document});

  void setDocumentLayoutKey(GlobalKey key) {
    _documentLayoutKey = key;
  }

  GlobalKey? get documentLayoutKey => _documentLayoutKey;

  void reorderNode(String nodeId, int targetIndex) {
    final node = document.getNodeById(nodeId);
    if (node == null) return;

    // 현재 노드의 인덱스 찾기
    int currentIndex = -1;
    for (int i = 0; i < document.length; i++) {
      if (document.getNodeAt(i)?.id == nodeId) {
        currentIndex = i;
        break;
      }
    }

    if (currentIndex == -1) return;

    // 같은 위치면 이동하지 않음
    if (currentIndex == targetIndex) return;

    // 노드 삭제 후 새 위치에 삽입
    document.deleteNode(nodeId);

    // targetIndex가 현재 인덱스보다 작으면 그대로 삽입
    final insertIndex =
        targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
    document.insertNodeAt(insertIndex, node);
    notifyListeners();
  }

  /// 두 이미지를 가로 배치로 합치는 함수
  void mergeImagesIntoRow(
    String draggingImageId,
    String targetImageId, {
    bool isFromLeft = true,
  }) {
    final draggingNode = document.getNodeById(draggingImageId);
    final targetNode = document.getNodeById(targetImageId);

    if (draggingNode == null || targetNode == null) return;

    // 타겟이 ImageRowNode인 경우
    if (targetNode is ImageRowNode) {
      _addImageToRow(draggingImageId, targetImageId, isFromLeft);
      return;
    }

    // 드래그 중인 노드가 ImageRowNode인 경우
    if (draggingNode is ImageRowNode) {
      _addImageToRow(targetImageId, draggingImageId, !isFromLeft);
      return;
    }

    // 둘 다 단일 이미지인 경우
    if (draggingNode is! ImageNode || targetNode is! ImageNode) return;

    // 두 이미지의 URL 수집 (최대 3개)
    final imageUrls = <String>[];

    // 드래그 중인 이미지가 타겟 이미지보다 앞에 있으면 먼저 추가
    int draggingIndex = -1;
    int targetIndex = -1;

    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
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

    // ImageRowNode 생성 (이미 3개 제한이 적용됨)
    final imageRowNode = ImageRowNode(
      id: 'imageRow_${DateTime.now().millisecondsSinceEpoch}',
      imageUrls: imageUrls,
      spacing: 8.0,
    );

    // 기존 이미지들 삭제
    document.deleteNode(draggingImageId);
    document.deleteNode(targetImageId);

    // ImageRowNode 삽입 (더 작은 인덱스 위치에)
    final insertIndex =
        draggingIndex < targetIndex ? draggingIndex : targetIndex;
    document.insertNodeAt(insertIndex, imageRowNode);
    notifyListeners();
  }

  void _addImageToRow(String imageId, String rowId, bool isFromLeft) {
    final imageNode = document.getNodeById(imageId);
    final rowNode = document.getNodeById(rowId);

    if (imageNode == null || rowNode == null) return;
    if (imageNode is! ImageNode || rowNode is! ImageRowNode) return;

    // 이미 3개가 있으면 추가하지 않음
    if (rowNode.imageUrls.length >= 3) return;

    // 새로운 이미지 URL 리스트 생성
    final newImageUrls = List<String>.from(rowNode.imageUrls);

    if (isFromLeft) {
      newImageUrls.insert(0, imageNode.imageUrl);
    } else {
      newImageUrls.add(imageNode.imageUrl);
    }

    // ImageRowNode 업데이트 (이미 3개 제한이 적용됨)
    final updatedRowNode = rowNode.copyWith(imageUrls: newImageUrls);
    document.replaceNodeById(rowId, updatedRowNode);

    // 기존 이미지 삭제
    document.deleteNode(imageId);
    notifyListeners();
  }

  NodeType getNodeType(String nodeId) {
    final node = document.getNodeById(nodeId);
    switch (node) {
      case ParagraphNode():
        return NodeType.paragraph;
      case ImageNode():
        return NodeType.image;
      case ImageRowNode():
        return NodeType.imageRow;
      default:
        return NodeType.unknown;
    }
  }

  DocumentNode? findNodeAtPosition(Offset position) {
    final documentLayout = _documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) {
      return null;
    }

    try {
      // 글로벌 좌표를 DocumentLayout의 로컬 좌표로 변환
      final renderObject =
          _documentLayoutKey?.currentContext?.findRenderObject();
      RenderBox? renderBox;
      if (renderObject is RenderSliverToBoxAdapter) {
        renderBox = renderObject.child;
      } else if (renderObject is RenderBox) {
        renderBox = renderObject;
      }

      if (renderBox == null) {
        return null;
      }

      // 글로벌 좌표를 DocumentLayout의 로컬 좌표로 변환
      final localPosition = renderBox.globalToLocal(position);

      // SuperEditor 내장 함수 사용 (안전한 처리)
      DocumentPosition? documentPosition;
      try {
        documentPosition = documentLayout.getDocumentPositionNearestToOffset(
          localPosition,
        );
      } catch (e) {
        return null;
      }

      if (documentPosition == null) {
        return null;
      }

      final node = document.getNodeById(documentPosition.nodeId);

      return node;
    } catch (e) {
      print("Error finding node at position: $e");
      return null;
    }
  }

  /// 이미지 행에서 특정 이미지를 분리하고 분리된 이미지 ID 반환
  String? splitImageFromRow(String rowId, int imageIndex) {
    final rowNode = document.getNodeById(rowId);
    if (rowNode == null || rowNode is! ImageRowNode) return null;
    if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) return null;

    // 분리할 이미지 URL
    final imageUrl = rowNode.imageUrls[imageIndex];

    // 이미지 행의 인덱스 찾기
    int rowIndex = -1;
    for (int i = 0; i < document.length; i++) {
      if (document.getNodeAt(i)?.id == rowId) {
        rowIndex = i;
        break;
      }
    }
    if (rowIndex == -1) return null;

    // 분리할 이미지의 새 ID 생성
    final newImageId = 'image_${DateTime.now().millisecondsSinceEpoch}';
    final newImageNode = ImageNode(id: newImageId, imageUrl: imageUrl);

    // 이미지 행에서 해당 이미지 제거
    final remainingUrls = List<String>.from(rowNode.imageUrls);
    remainingUrls.removeAt(imageIndex);

    if (remainingUrls.length == 1) {
      // 이미지가 1개만 남으면 단일 이미지로 변경
      final singleImageNode = ImageNode(
        id: rowId,
        imageUrl: remainingUrls.first,
      );
      document.replaceNodeById(rowId, singleImageNode);
    } else if (remainingUrls.isEmpty) {
      // 이미지가 없으면 행 삭제
      document.deleteNode(rowId);
    } else {
      // 이미지 행 업데이트
      final updatedRowNode = rowNode.copyWith(imageUrls: remainingUrls);
      document.replaceNodeById(rowId, updatedRowNode);
    }

    // 분리된 이미지를 원래 위치에 삽입
    document.insertNodeAt(rowIndex, newImageNode);
    notifyListeners();

    return newImageId;
  }
}
