import 'package:super_editor/super_editor.dart';

/// 특수 노드 정보 저장 구조체
class SpecialNodeInfo {
  final DocumentNode node;
  final int index;
  final DocumentSelection? selection;
  final bool isAtDownstream;

  SpecialNodeInfo({
    required this.node,
    required this.index,
    this.selection,
    required this.isAtDownstream,
  });
}
