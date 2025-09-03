import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

enum DragMode { none, textReorder, imageInsert, imageReorder }

class DragService extends ChangeNotifier {
  final EditorService editorService;

  String? draggingNodeId;
  NodeType? draggingNodeType;
  String? targetNodeId;
  NodeType? targetNodeType;
  DragMode dragMode = DragMode.none;

  Offset? dragPosition;
  int? dropIndex;

  DragService({required this.editorService});

  void startDrag(String nodeId, BuildContext context, Offset globalPosition) {
    draggingNodeId = nodeId;
    draggingNodeType = editorService.getNodeType(nodeId);
    dragPosition = globalPosition;

    // 다음 프레임에서 계산하도록 예약
    dropIndex = null;
    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (dragPosition != null) {
        final computed = _computeDropIndex(dragPosition!);
        dropIndex = computed;
        notifyListeners();
      }
    });
  }

  void updateDrag(Offset globalPosition, BuildContext context) {
    final hit = editorService.findNodeAtPosition(globalPosition);
    if (hit != null) {
      targetNodeId = hit.id;
      targetNodeType = editorService.getNodeType(hit.id);
    }

    dragPosition = globalPosition;
    final newDropIndex = _computeDropIndex(globalPosition);

    // dropIndex 변경 시 즉시 업데이트
    if (newDropIndex != dropIndex) {
      print("📢 Drop index changed from $dropIndex to $newDropIndex");
      dropIndex = newDropIndex;
    }

    // 플레이스 홀더를 위한 알림
    notifyListeners();

    // 드래그 모드 결정
    if (draggingNodeType == NodeType.paragraph &&
        targetNodeType == NodeType.paragraph) {
      dragMode = DragMode.textReorder;
    } else if (draggingNodeType == NodeType.paragraph &&
        targetNodeType == NodeType.image) {
      dragMode = DragMode.imageInsert;
    } else if (draggingNodeType == NodeType.image &&
        targetNodeType == NodeType.paragraph) {
      dragMode = DragMode.imageInsert;
    } else if (draggingNodeType == NodeType.image &&
        targetNodeType == NodeType.image) {
      dragMode = DragMode.imageReorder;
    } else {
      dragMode = DragMode.none;
    }
  }

  void endDrag() {
    _cleanup();
    if (draggingNodeId == null || targetNodeId == null) {
      return;
    }

    // 실제 노드 이동 실행
    switch (dragMode) {
      case DragMode.textReorder:
        //_moveNode(draggingNodeId!, targetNodeId!);
        print("textReorder");
        break;
      case DragMode.imageInsert:
        //_moveNode(draggingNodeId!, targetNodeId!);
        print("imageInsert");
        break;
      case DragMode.imageReorder:
        //_moveNode(draggingNodeId!, targetNodeId!);
        print("imageReorder");
        break;
      default:
        break;
    }

    _cleanup();
  }

  void _cleanup() {
    draggingNodeId = null;
    draggingNodeType = null;
    targetNodeId = null;
    targetNodeType = null;
    dragMode = DragMode.none;
    dropIndex = null;
    dragPosition = null;
    notifyListeners();
  }

  // =================== 내부 함수 ===================

  /// globalPosition 기준으로 문서 내 드롭 인덱스 계산
  int? _computeDropIndex(Offset globalPosition) {
    int index = 0;
    int? candidate;

    for (final node in editorService.editor.document) {
      final key = editorService.nodeKeys[node.id];
      if (key?.currentContext == null) {
        index += 1;
        continue;
      }

      final box = key!.currentContext!.findRenderObject() as RenderBox?;
      if (box == null) {
        index += 1;
        continue;
      }

      final top = box.localToGlobal(Offset.zero).dy;
      final height = box.size.height;
      final bottom = top + height;
      final center = top + height / 2;

      if (globalPosition.dy < top) {
        candidate = index;
        break;
      }

      if (globalPosition.dy >= top && globalPosition.dy <= bottom) {
        candidate = globalPosition.dy < center ? index : index + 1;
        break;
      }

      // 포인터가 현재 노드 아래면 다음 인덱스로 진행
      candidate = index + 1;
      index += 1;
    }

    return candidate;
  }
}
