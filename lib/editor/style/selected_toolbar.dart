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
  bool _isPlaceholderMedia(DocumentNode? node) {
    if (node == null) return false;
    try {
      // 단일 이미지(AppImageNode / ImageNode)
      if (node is ImageNode) {
        final dynamic dyn = node;
        final String url = (dyn.imageUrl as String?) ?? '';
        final Map<String, dynamic>? meta =
            (dyn.metadata as Map<String, dynamic>?) ?? {};
        final bool isPlaceholder = (meta?['isPlaceholder'] == true);
        if (isPlaceholder) return true;
        if (url.isEmpty || url.startsWith('file://')) return true;
        return false;
      }
      // 이미지 행(ImageRowNode): 내부에 로컬 경로가 하나라도 있으면 플레이스홀더로 간주
      if (node is ImageRowNode) {
        final hasLocal = node.imageUrls.any(
          (u) => u.isEmpty || u.startsWith('file://'),
        );
        return hasLocal;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.node == null || widget.selectedId == null)
      return const SizedBox.shrink();

    final bool isPlaceholder = _isPlaceholderMedia(widget.node);

    // 이미지 스포일러 적용 여부
    bool isImageSpoiler = false;
    if (widget.node is ImageNode || widget.node is ImageRowNode) {
      try {
        final nodeService = NodeComponentService();
        Map<String, dynamic>? meta;
        if (widget.node is ImageNode) {
          meta = (widget.node as dynamic).metadata as Map<String, dynamic>?;
        } else if (widget.node is ImageRowNode) {
          meta = (widget.node as ImageRowNode).metadata;
        }
        isImageSpoiler = nodeService.shouldShowImageSpoiler(
          widget.selectedId ?? '',
          meta,
        );
      } catch (_) {}
    }

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
          if (!isPlaceholder &&
              (widget.node is ImageNode || widget.node is ImageRowNode)) ...[
            // 스포일러 토글
            if (widget.node is ImageNode || widget.node is ImageRowNode)
              _buildSvgToggleIcon(
                svgPath: 'assets/icons/spoiler.svg',
                isActive: isImageSpoiler,
                label: '스포일러',
                onTap: () {
                  if (widget.selectedId != null) {
                    // 현재 상태의 반대로 설정 (toggleSpoiler 대신 setSpoiler 사용)
                    NodeComponentService().setSpoiler(
                      widget.selectedId!,
                      !isImageSpoiler,
                    );
                    if (mounted) setState(() {});
                  }
                },
                size: 28,
              ),
            SizedBox(width: 8),

            if (widget.node is ImageNode) ...[
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
              SizedBox(width: 8),
            ],
          ],

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
