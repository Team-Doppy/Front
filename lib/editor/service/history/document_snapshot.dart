import 'package:super_editor/super_editor.dart';

/// 🎯 문서 스냅샷 (전체 노드 + 순서 + 커서)
class DocumentSnapshot {
  final Map<String, DocumentNode> nodes; // nodeId -> node
  final List<String> order; // 노드 순서
  final DocumentSelection? selection; // 커서 위치

  DocumentSnapshot({required this.nodes, required this.order, this.selection});
}
