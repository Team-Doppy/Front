import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'overlay_transform.dart';

enum OverlayItemType { rect }

@immutable
class OverlayItem {
  const OverlayItem({
    required this.id,
    required this.type,
    required this.transform,
    this.zIndex = 0,
    this.color = const Color(0xFF4CAF50),
  });

  final String id;
  final OverlayItemType type;
  final OverlayTransform transform;
  final int zIndex;
  final Color color;

  OverlayItem copyWith({
    OverlayTransform? transform,
    int? zIndex,
    Color? color,
  }) {
    return OverlayItem(
      id: id,
      type: type,
      transform: transform ?? this.transform,
      zIndex: zIndex ?? this.zIndex,
      color: color ?? this.color,
    );
  }
}
