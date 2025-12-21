import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/utils/config.dart' as config;
import 'package:super_editor/super_editor.dart';

/// 🎯 노드 타입 체커 유틸리티
class NodeTypeChecker {
  NodeTypeChecker._();

  /// 특수 노드인지 확인 (이미지, 영상, 링크, 구분선 등)
  /// 🎯 멘션 노드는 일반 텍스트로 처리하므로 특수 노드가 아님
  /// config.dart의 isSpecialNode()를 사용
  static bool isSpecialNode(DocumentNode? node) {
    return config.isSpecialNode(node);
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
    final isEmpty = node.text.text.trim().isEmpty;
    final isTitle = node.metadata['isTitle'] == true;
    return !isTitle && isEmpty;
  }

  /// 제목 노드인지 확인
  static bool isTitleNode(DocumentNode? node) {
    if (node is! ParagraphNode) return false;
    return node.metadata['isTitle'] == true;
  }

  /// 멘션 노드인지 확인
  static bool isMentionNode(DocumentNode? node) {
    if (node is! ParagraphNode) return false;
    return node.metadata['mention'] == true;
  }
}
