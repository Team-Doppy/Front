import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 오버레이의 "진실 좌표계"는 이미지 픽셀 좌표(image space)로 둔다.
@immutable
class OverlayTransform {
  const OverlayTransform({
    required this.anchorImage,
    required this.baseSizeImage,
    this.scale = 1.0,
    this.rotationRad = 0.0,
  });

  /// 이미지 좌표계에서의 중심점(px)
  final Offset anchorImage;

  /// 이미지 좌표계에서의 기본 크기(px)
  final Size baseSizeImage;

  /// 오버레이 자체 추가 스케일(균일)
  final double scale;

  /// 라디안(시계 방향 +)
  final double rotationRad;

  OverlayTransform copyWith({
    Offset? anchorImage,
    Size? baseSizeImage,
    double? scale,
    double? rotationRad,
  }) {
    return OverlayTransform(
      anchorImage: anchorImage ?? this.anchorImage,
      baseSizeImage: baseSizeImage ?? this.baseSizeImage,
      scale: scale ?? this.scale,
      rotationRad: rotationRad ?? this.rotationRad,
    );
  }
}
