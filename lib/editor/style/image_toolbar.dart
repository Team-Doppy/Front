import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';

/// 이미지 편집 전용 툴바
/// - 기본 툴바와 동일한 디자인
/// - 기능: 보정, 자르기, 삭제
class ImageEditingToolbar extends StatefulWidget {
  const ImageEditingToolbar({
    super.key,
    this.onAdjust,
    this.onCrop,
    this.onDelete,
  });

  final VoidCallback? onAdjust;
  final VoidCallback? onCrop;
  final VoidCallback? onDelete;

  @override
  State<ImageEditingToolbar> createState() => _ImageEditingToolbarState();
}

class _ImageEditingToolbarState extends State<ImageEditingToolbar> {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return SizedBox(
      height: 38,
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: AppColors.darkSurface),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '이미지 선택됨',
                style: TextStyle(
                  color: AppColors.darkTextPrimary.withOpacity(0.7),
                ),
              ),
            ),

            // 자르기 버튼
            _buildMainIcon(
              icon: Icons.crop,
              isActive: false,
              onTap: widget.onCrop,
            ),

            const SizedBox(width: 10),
            _buildDivider(),
            const SizedBox(width: 10),

            // 삭제 버튼
            _buildMainIcon(
              icon: Icons.delete_outline,
              isActive: false,
              onTap: widget.onDelete,
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildMainIcon({
    required IconData icon,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 22,
          color:
              icon == Icons.delete_outline
                  ? AppColors.error.withOpacity(0.8)
                  : isActive
                  ? Colors.white
                  : AppColors.darkTextSecondary,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 20, color: AppColors.darkBorder);
  }
}
