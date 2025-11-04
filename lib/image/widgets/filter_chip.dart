import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:doppy/image/models/filter_preset.dart';

/// 필터 칩 (미리보기 이미지)
class FilterChipWidget extends StatelessWidget {
  const FilterChipWidget({
    super.key,
    required this.preset,
    required this.isSelected,
    required this.onTap,
    required this.imageBytes,
    required this.getColorFilter,
  });

  final FilterPreset preset;
  final bool isSelected;
  final VoidCallback onTap;
  final Uint8List imageBytes;
  final ColorFilter? Function(FilterPreset) getColorFilter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color:
                    isSelected ? Colors.white : Colors.white.withOpacity(0.3),
                width: isSelected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColorFiltered(
                colorFilter:
                    getColorFilter(preset) ??
                    const ColorFilter.matrix([
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
                child: Image.memory(imageBytes, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            preset.name,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}
