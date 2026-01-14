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

  /// ✅ 크롭과 동일한 재투영 로직: frozen displayRect 기준의 image 좌표를
  /// new displayRect 기준의 image 좌표로 변환
  ///
  /// 의미:
  /// - old displayRect 기준 image 좌표 → screen 좌표 (frozen)
  /// - screen 좌표 → new displayRect 기준 image 좌표
  static Offset? projectImageOffsetToNewDisplayRect({
    required Offset imageOffset, // old displayRect 기준 image 좌표
    required Size imageSize,
    required Rect frozenDisplayRect, // 제스처 시작 시 freeze된 displayRect
    required Rect newDisplayRect, // 제스처 종료 시 새로운 displayRect
  }) {
    // ✅ 1. old displayRect 기준 image 좌표 → screen 좌표 변환
    final screenOffset = imageToScreenOffset(
      imageOffset: imageOffset,
      imageSize: imageSize,
      displayRect: frozenDisplayRect,
    );

    // ✅ 2. screen 좌표 → new displayRect 기준 image 좌표 변환
    final sx = newDisplayRect.width / imageSize.width;
    final sy = newDisplayRect.height / imageSize.height;
    if (sx <= 0 || sy <= 0) return null;

    final projectedX = (screenOffset.dx - newDisplayRect.left) / sx;
    final projectedY = (screenOffset.dy - newDisplayRect.top) / sy;

    // ✅ 이미지 경계 내로 clamp
    final clampedX = projectedX.clamp(0.0, imageSize.width);
    final clampedY = projectedY.clamp(0.0, imageSize.height);

    return Offset(clampedX, clampedY);
  }
}
