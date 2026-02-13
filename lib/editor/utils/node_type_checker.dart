import '../component/pageview_image_component.dart';
import '../component/row_image_component.dart';
import '../config/editor_config.dart' as EditorConfig;
import 'package:super_editor/super_editor.dart';

/// 🎯 노드 타입 체커 유틸리티
class NodeTypeChecker {
  NodeTypeChecker._();

  /// 특수 노드인지 확인 (이미지, 영상, 링크, 멘션 등)
  /// 🎯 멘션 노드도 특수 노드로 처리 (마지막 노드 아래 빈 공간 클릭 시 빈 텍스트 추가 기능을 위해)
  /// config.dart의 isSpecialNode()를 사용
  static bool isSpecialNode(DocumentNode? node) {
    return EditorConfig.isSpecialNode(node);
  }

  /// 이미지 노드인지 확인 (단일, 행, 페이지뷰)
  static bool isImageNode(DocumentNode? node) {
    if (node == null) return false;
    return node is ImageNode ||
        node is ImageRowNode ||
        node is PageViewImageNode;
  }

  /// 텍스트 노드인지 확인
  static bool isTextNode(DocumentNode? node) {
    if (node == null) return false;
    return node is ParagraphNode;
  }

  /// 빈 문단 노드인지 확인
  static bool isEmptyParagraph(DocumentNode? node) {
    if (node is! ParagraphNode) return false;
    return node.text.text.trim().isEmpty;
  }

  /// 제목 노드인지 확인 (더 이상 사용되지 않음)
  static bool isTitleNode(DocumentNode? node) {
    return false;
  }
}
