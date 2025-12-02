import 'package:super_editor/super_editor.dart' show ImageNode, ExpectedSize;

/// 앱 전용 이미지 노드: 백스페이스로 삭제되지 않도록 보호
class AppImageNode extends ImageNode {
  AppImageNode({
    required String id,
    required String imageUrl,
    ExpectedSize? expectedBitmapSize,
    String altText = '',
    Map<String, dynamic>? metadata,
  }) : super(
         id: id,
         imageUrl: imageUrl,
         expectedBitmapSize: expectedBitmapSize,
         altText: altText,
         metadata: metadata,
       );

  @override
  bool get isDeletable => true;
}
