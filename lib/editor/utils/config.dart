import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:super_editor/super_editor.dart';

class EditorConfig {
  static const double documentPadding = 0;
  static const double textPadding = 1;
  static const double imagePadding = 0;

  /// 특수 노드(이미지, 비디오, 링크)와 텍스트 노드 사이의 수직 패딩
  static const double specialNodePaddingWithText = 18.0;
}

/// 특수 노드인지 확인하는 전역 함수
/// 🎯 멘션 노드는 일반 텍스트로 처리하므로 특수 노드가 아님
bool isSpecialNode(DocumentNode? node) {
  if (node == null) return false;
  return node is ImageNode ||
      node is ImageRowNode ||
      node is PageViewImageNode ||
      node is ClipNode ||
      node is LinkNode;
}
