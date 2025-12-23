import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 노드 관리 전담 서비스
/// - 노드 복사 유틸리티
class NodeManagementService {
  final MutableDocument document;
  final Function(DocumentNode) isSpecialNode;

  NodeManagementService({required this.document, required this.isSpecialNode});

  void dispose() {
    // 레지스트리 관련 로직 제거됨
  }

  /// 🎯 노드 deep copy
  DocumentNode copyNode(DocumentNode node) {
    if (node is ParagraphNode) {
      // metadata에는 textAlign, isTitle, fontFamily 등이 포함됨
      final copiedMetadata = Map<String, dynamic>.from(node.metadata);
      final isMention = copiedMetadata['mention'] == true;

      // 🎯 AttributedText 전체 복사 (모든 스타일 유지: bold, italic, color, font, highlight, spoiler 등)
      final AttributedText attributed = node.text.copyText(0, node.text.length);

      // 🎯 멘션 노드인데 볼드가 없으면 추가
      if (isMention && node.text.text.isNotEmpty) {
        final hasBold =
            attributed
                .getAttributionSpansInRange(
                  attributionFilter: (attr) => attr == boldAttribution,
                  range: SpanRange(0, node.text.text.length - 1),
                )
                .isNotEmpty;

        if (!hasBold) {
          attributed.addAttribution(
            boldAttribution,
            SpanRange(0, node.text.text.length - 1),
          );
        }
      }

      return ParagraphNode(
        id: node.id,
        text: attributed,
        metadata: copiedMetadata, // ✅ 정렬, 제목 여부 등 모두 복사됨
      );
    }
    if (node is ImageNode) {
      return AppImageNode(
        id: node.id,
        imageUrl: node.imageUrl,
        altText: node.altText,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ImageRowNode) {
      return ImageRowNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is LinkNode) {
      return LinkNode(
        id: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
      );
    }
    if (node is ClipNode) {
      return ClipNode(
        id: node.id,
        url: node.url,
        label: node.label,
        colorHex: node.colorHex,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is DividerNode) {
      return DividerNode(id: node.id);
    }
    if (node is PageViewImageNode) {
      return PageViewImageNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    // 기본: 그대로 반환
    return node;
  }
}
