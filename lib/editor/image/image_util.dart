import 'dart:ui';

class SystemConstants {
  // 🎯 이미지 기본 크기(기존 고정값 제거 → 런타임 비율 기반 계산에만 사용)
  static const double baseWidth = 120.0; // 레거시: 일부 계산에서만 남김
  static const double baseHeight = 80.0; // 레거시
  static const double displayWidth = 360.0; // 레거시(스케일 초기 추정치)
  static const double displayHeight = 200.0; // 레거시
  static const double documentMargin = 10.0;

  // 🎯 격자 시스템
  // 고정 그리드 칸 수(열) → 어떤 화면에서도 columns가 동일하게 유지되도록 함
  static const double gridSize = 21.0;

  // 🎯 드래그 임계값
  static const double dragDirectionThreshold = 25.0;
  static const double dragResetThreshold = 15.0;
  static const double verticalSwapThreshold = 25.0;
  static const double moveThreshold = 20.0;

  // 🎯 스케일 범위
  static const double scaleMin = 0.3;
  static const double scaleMax = 3.0;

  // 🎯 텍스트 스타일 (시스템 전체 통일)
  static const double defaultFontSize = 16.0;

  // 🎯 이미지 간격 (대칭적 여백을 위해 충분한 값 설정)
  static const double imagePadding = 8.0;
  static const double defaultLineHeight1 = 1.5;
}

class ImageSizeCalculator {
  static Size getActualSize(double scale) {
    // 실제 사용 경로에서 원본 비율 기반 displaySize를 사용하므로,
    // 이 함수는 더 이상 핵심 경로가 아님. 하위 호환 유지.
    return Size(
        SystemConstants.baseWidth * scale, SystemConstants.baseHeight * scale);
  }

  static Size getDisplaySize(double scale) {
    // 실제 표시 크기는 원본 비율 기반으로 DocumentInteractiveFloatingImage에서 계산함.
    // 여기서는 기존 경로 하위 호환만 유지.
    return Size(SystemConstants.displayWidth * scale,
        SystemConstants.displayHeight * scale);
  }

  static double getContainerHeight(double scale) {
    return SystemConstants.displayHeight * scale; // 사용처에서 동적계산으로 대체됨
  }

  static Offset calculateAbsolutePosition(
    Offset currentOffset,
    double screenWidth,
  ) {
    final actualWidth = SystemConstants.baseWidth;
    return Offset(
      currentOffset.dx + (screenWidth / 2) - (actualWidth / 2),
      currentOffset.dy,
    );
  }
}

class ImagePositionCalculator {
  static Offset getImageCenterOffset(
      Offset currentOffset, double screenWidth, double actualWidth) {
    return Offset(
      currentOffset.dx + (screenWidth / 2) - (actualWidth / 2),
      currentOffset.dy,
    );
  }

  static Rect getImageRect(
      Offset currentOffset, double screenWidth, Size actualSize) {
    final centerOffset =
        getImageCenterOffset(currentOffset, screenWidth, actualSize.width);
    return Rect.fromLTWH(
      centerOffset.dx,
      centerOffset.dy,
      actualSize.width,
      actualSize.height,
    );
  }

  static Offset getTouchOffset(
      Offset focalPoint, Offset currentOffset, double screenWidth) {
    final currentImageCenterX = (screenWidth / 2) + currentOffset.dx;
    final currentImageCenterY = 70 + currentOffset.dy;

    return Offset(
      focalPoint.dx - currentImageCenterX,
      focalPoint.dy - currentImageCenterY,
    );
  }
}

class DragDirectionDetector {
  static ({bool isHorizontal, bool isVertical}) detectDirection(
    double deltaX,
    double deltaY,
  ) {
    if (deltaX.abs() > deltaY.abs() &&
        deltaX.abs() > SystemConstants.dragDirectionThreshold) {
      return (isHorizontal: true, isVertical: false);
    } else if (deltaY.abs() > deltaX.abs() &&
        deltaY.abs() > SystemConstants.dragDirectionThreshold) {
      return (isHorizontal: false, isVertical: true);
    } else if (deltaX.abs() < SystemConstants.dragResetThreshold &&
        deltaY.abs() < SystemConstants.dragResetThreshold) {
      return (isHorizontal: false, isVertical: false);
    }
    return (isHorizontal: false, isVertical: false);
  }
}

class TargetYCalculator {
  static double calculateTargetY({
    required double baseY,
    required double imageHeight,
    required double dragOffset,
  }) {
    return baseY + dragOffset;
  }
}

class ImageDragInfo {
  double baseY = 0;
  double imageHeight = 0;
  double dragXOffset = 0;
  double dragYOffset = 0;

  ImageDragInfo({
    required this.baseY,
    required this.imageHeight,
    required this.dragXOffset,
    required this.dragYOffset,
  });
}
