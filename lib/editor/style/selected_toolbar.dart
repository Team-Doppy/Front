import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/component/row_image_component.dart';

class SelectedToolbar extends StatefulWidget {
  const SelectedToolbar({
    super.key,
    required this.selectedId,
    required this.node,
    required this.onEdit,
    required this.onDelete,
    this.onChangeAlignment,
  });

  final String? selectedId;
  final DocumentNode? node;
  final VoidCallback onEdit;
  final void Function(DocumentNode node, String selectedId) onDelete;
  final void Function(DocumentNode node, String selectedId)? onChangeAlignment;

  @override
  State<SelectedToolbar> createState() => _SelectedToolbarState();
}

class _SelectedToolbarState extends State<SelectedToolbar> {
  @override
  Widget build(BuildContext context) {
    if (widget.node == null || widget.selectedId == null)
      return const SizedBox.shrink();

    // 현재 노드의 padding 상태 확인
    bool isExpanded = false;
    if (widget.node is ImageNode) {
      final meta = (widget.node as dynamic).metadata as Map<String, dynamic>?;
      isExpanded = meta?['padding'] == 'full';
    } else if (widget.node is ImageRowNode) {
      final meta = (widget.node as ImageRowNode).metadata;
      isExpanded = meta['padding'] == 'full';
    }
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
              fontSize: 17,
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
          if (widget.node is ImageNode || widget.node is ImageRowNode) ...[
            // 스포일러 토글
            _buildSvgToggleIcon(
              svgPath: 'assets/icons/spoiler.svg',
              isActive: false,
              label: '스포일러',
              onTap: () {
                if (widget.selectedId != null) {
                  NodeComponentService().toggleSpoiler(widget.selectedId!);
                }
              },
              size: 28,
            ),
            SizedBox(width: 8),

            _buildMainSvgIcon(
              context: context,
              svgPath:
                  isExpanded
                      ? 'assets/icons/arrow-double-shrink.svg' // 확장됨 → 축소 아이콘
                      : 'assets/icons/arrow-double-expand.svg', // 축소됨 → 확장 아이콘
              isActive: true,
              onTap: () {
                if (widget.onChangeAlignment != null &&
                    widget.selectedId != null) {
                  widget.onChangeAlignment!(widget.node!, widget.selectedId!);
                }
              },
            ),
            SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _buildMainSvgIcon(
                size: 28,
                context: context,
                svgPath: 'assets/icons/crop.svg',
                isActive: false,
                onTap: widget.onEdit,
              ),
            ),
          ],
          SizedBox(width: 8),

          _buildMainSvgIcon(
            size: 28,
            context: context,
            svgPath: 'assets/icons/delete.svg',
            isActive: false,
            onTap:
                (widget.node != null && widget.selectedId != null)
                    ? () => widget.onDelete(widget.node!, widget.selectedId!)
                    : () {},
          ),
        ],
      ),
    );
  }

  Widget _buildMainSvgIcon({
    required BuildContext context,
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    double? size,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color = onSurface.withOpacity(0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 40,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            svgPath,
            width: size ?? (isActive ? 28 : 25),
            height: size ?? (isActive ? 28 : 25),
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  Widget _buildSvgToggleIcon({
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    required String label,
    double? size,
  }) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface =
        isActive
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

    return Material(
      color: isActive ? surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            svgPath,
            width: size ?? 24,
            height: size ?? 24,
            colorFilter: ColorFilter.mode(onSurface, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
