import 'package:flutter/material.dart';
import 'dart:ui';
import 'image/image_util.dart';

/// 🔲 격자 좌표
class GridCoordinate {
  final int x;
  final int y;

  const GridCoordinate({required this.x, required this.y});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridCoordinate &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  @override
  String toString() => 'GridCoordinate(x: $x, y: $y)';
}

/// 🔲 격자 시스템
class GridSystem {
  final double screenWidth;
  final double gridSize;

  GridSystem({required this.screenWidth})
      : gridSize = screenWidth / SystemConstants.gridSize;

  Path createGridPath(Size canvasSize) {
    final path = Path();

    // 세로선 그리기
    for (double x = 0; x <= canvasSize.width; x += gridSize) {
      path.moveTo(x, 0);
      path.lineTo(x, canvasSize.height);
    }

    // 가로선 그리기
    for (double y = 0; y <= canvasSize.height; y += gridSize) {
      path.moveTo(0, y);
      path.lineTo(canvasSize.width, y);
    }

    return path;
  }
}
