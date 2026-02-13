import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import 'list_paragraph_meta.dart';

/// 맨 위(첫 번째) 노드가 빈 리스트 문단일 때 백스페이스로 일반 문단으로 전환.
/// deleteUpstream()은 nodeBefore == null 이면 요청을 보내지 않으므로, 키보드 액션에서 직접 요청을 보낸다.
ExecutionInstruction backspaceClearEmptyListParagraphWhenFirstNode({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null || !selection.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final extent = selection.extent;
  final nodePos = extent.nodePosition;
  if (nodePos is! TextNodePosition || nodePos.offset != 0) {
    return ExecutionInstruction.continueExecution;
  }

  final doc = editContext.document;
  final node = doc.getNodeById(extent.nodeId);
  if (node is! ParagraphNode) return ExecutionInstruction.continueExecution;
  if (node.text.text.trim().isNotEmpty) return ExecutionInstruction.continueExecution;
  if (!ListParagraphMeta.isListParagraph(node.metadata)) {
    return ExecutionInstruction.continueExecution;
  }

  final nodeIndex = doc.getNodeIndexById(node.id);
  if (nodeIndex != 0) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    DeleteUpstreamAtBeginningOfNodeRequest(node),
  ]);
  return ExecutionInstruction.haltExecution;
}
