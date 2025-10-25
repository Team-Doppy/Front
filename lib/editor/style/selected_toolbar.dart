import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class SelectedToolbar extends StatelessWidget {
  const SelectedToolbar({
    super.key,
    required this.selectedId,
    required this.node,
    required this.onEdit,
    required this.onDelete,
  });

  final String? selectedId;
  final DocumentNode? node;
  final VoidCallback onEdit;
  final void Function(DocumentNode node, String selectedId) onDelete;

  @override
  Widget build(BuildContext context) {
    if (node == null || selectedId == null) return const SizedBox.shrink();
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),

      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            '선택됨',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          /*
          Text(
            '선택됨: ${node.runtimeType}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
         */
          const Spacer(),
          if (node is ImageNode)
            IconButton(
              tooltip: '수정',
              onPressed: onEdit,
              icon: Icon(
                Icons.crop,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),

          IconButton(
            tooltip: '삭제',
            onPressed:
                node != null && selectedId != null
                    ? () => onDelete(node!, selectedId!)
                    : null,
            icon: Icon(
              size: 20,
              Icons.delete,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
