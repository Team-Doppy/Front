import 'package:flutter/material.dart';

/// 이미지 좌표(image space) ↔ 화면 좌표(stage/screen space) 변환 유틸.
///
/// - imageSize: 원본 이미지 픽셀 크기
/// - displayRect: 현재 프리뷰에서 이미지가 화면에 그려지는 Rect
class OverlayCoords {
  OverlayCoords._();

  static Offset imageToScreenOffset({
    required Offset imageOffset,
    required Size imageSize,
    required Rect displayRect,
  }) {
    final sx = displayRect.width / imageSize.width;
    final sy = displayRect.height / imageSize.height;
    return Offset(
      displayRect.left + imageOffset.dx * sx,
      displayRect.top + imageOffset.dy * sy,
    );
  }

  static Offset screenDeltaToImageDelta({
    required Offset screenDelta,
    required Size imageSize,
    required Rect displayRect,
  }) {
    final sx = displayRect.width / imageSize.width;
    final sy = displayRect.height / imageSize.height;
    if (sx == 0 || sy == 0) return Offset.zero;
    return Offset(screenDelta.dx / sx, screenDelta.dy / sy);
  }

  static Size imageToScreenSize({
    required Size imageSizeValue,
    required Size imageSize,
    required Rect displayRect,
  }) {
    final sx = displayRect.width / imageSize.width;
    final sy = displayRect.height / imageSize.height;
    return Size(imageSizeValue.width * sx, imageSizeValue.height * sy);
  }
}
