import 'package:super_editor/super_editor.dart';

/// ImageNode 확장: 키보드(백스페이스/딜리트)로 삭제되지 않도록 보호된 이미지 노드
class ProtectedImageNode extends ImageNode {
  ProtectedImageNode({required super.id, required super.imageUrl});

  @override
  bool get isDeletable => false;
}
