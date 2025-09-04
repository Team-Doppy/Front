import 'package:doppy/editor/config/config.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/component/image_row_component.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';

/// 드래그 중인 컴포넌트의 미리보기를 보여주는 오버레이 위젯
class DragOverlayWidget extends StatelessWidget {
  const DragOverlayWidget({
    required this.nodeId,
    required this.nodeType,
    required this.position,
    required this.document,
    super.key,
  });

  final String nodeId;
  final String nodeType;
  final Offset position;
  final Document document;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 100, // 오버레이 너비의 절반만큼 왼쪽으로 이동
      top: position.dy - 100, // 오버레이 높이의 절반만큼 위로 이동
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildNodePreview(context),
        ),
      ),
    );
  }

  Widget _buildNodePreview(BuildContext context) {
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    Widget preview;
    switch (nodeType) {
      case 'image':
        preview = _buildImagePreview(node as ImageNode);
        break;
      case 'imageRow':
        preview = _buildImageRowPreview(node as ImageRowNode);
        break;
      case 'paragraph':
        preview = _buildParagraphPreview(node as ParagraphNode);
        break;
      default:
        preview = _buildDefaultPreview(node);
    }

    return preview;
  }

  Widget _buildImagePreview(ImageNode node) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleImageComponent(
          nodeId: node.id,
          imageUrl: node.imageUrl,
          componentKey: GlobalKey(),
        ),
      ),
    );
  }

  Widget _buildImageRowPreview(ImageRowNode node) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ImageRowComponent(
          nodeId: node.id,
          imageUrls: node.imageUrls,
          spacing: node.spacing,
          componentKey: GlobalKey(),
        ),
      ),
    );
  }

  Widget _buildParagraphPreview(ParagraphNode node) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        node.text.text,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDefaultPreview(DocumentNode node) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description, size: 24, color: Colors.grey.shade600),
          const SizedBox(height: 8),
          Text(
            node.runtimeType.toString(),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
