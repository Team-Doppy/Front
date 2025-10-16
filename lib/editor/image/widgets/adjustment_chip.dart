import 'package:flutter/material.dart';
import 'package:doppy/editor/image/models/image_adjustment.dart';

/// 조정 타입 선택 칩
class AdjustmentChip extends StatelessWidget {
  const AdjustmentChip({
    super.key,
    required this.type,
    required this.isSelected,
    required this.onTap,
    this.hasValue = false,
  });

  final AdjustmentType type;
  final bool isSelected;
  final VoidCallback onTap;
  final bool hasValue; // 기본값에서 변경되었는지

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.white.withOpacity(0.3)
                  : hasValue
                  ? Colors.white.withOpacity(0.2) // 적용된 값이 있을 때 더 밝게
                  : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AdjustmentTypeUtils.getIcon(type),
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              AdjustmentTypeUtils.getLabel(type),
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
