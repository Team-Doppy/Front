import 'package:flutter/material.dart';

/// 이미지 편집 전용 툴바
/// - 디자인은 기존 툴바와 동일(아이콘 + 펼쳐지는 칩)
/// - 기능: 보정, 자르기, 삭제
class ImageEditingToolbar extends StatefulWidget {
  const ImageEditingToolbar({super.key, this.onAdjust, this.onDelete});

  final VoidCallback? onAdjust;
  final VoidCallback? onDelete;

  @override
  State<ImageEditingToolbar> createState() => _ImageEditingToolbarState();
}

enum ImageToolbarSection { none, edit }

class _ImageEditingToolbarState extends State<ImageEditingToolbar> {
  ImageToolbarSection _expanded = ImageToolbarSection.none;

  void _toggle(ImageToolbarSection section) {
    setState(() {
      _expanded = _expanded == section ? ImageToolbarSection.none : section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return SizedBox(
      height: 38,
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: Colors.white),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildChip(icon: Icons.tune, label: '보정', onTap: widget.onAdjust),
            const SizedBox(width: 6),
            _buildChip(
              icon: Icons.delete_outline,
              label: '삭제',
              onTap: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade900),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
