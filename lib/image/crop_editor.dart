import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 이미지 표시 rect 계산 유틸리티 (단일 소스)
/// 모든 곳에서 동일한 계산 로직 사용
class ImageRectUtils {
  ImageRectUtils._();

  /// 🎯 이미지 좌표 → 화면 좌표 변환
  static Rect imageToScreenRect({
    required Rect imageRect,
    required Rect screenImageRect,
    required Size imageSize,
  }) {
    final sx = screenImageRect.width / imageSize.width;
    final sy = screenImageRect.height / imageSize.height;

    return Rect.fromLTWH(
      screenImageRect.left + imageRect.left * sx,
      screenImageRect.top + imageRect.top * sy,
      imageRect.width * sx,
      imageRect.height * sy,
    );
  }

  /// 🎯 화면 델타 → 이미지 델타 변환
  static Offset screenDeltaToImageDelta({
    required Offset screenDelta,
    required Rect screenImageRect,
    required Size imageSize,
  }) {
    final sx = screenImageRect.width / imageSize.width;
    final sy = screenImageRect.height / imageSize.height;
    return Offset(screenDelta.dx / sx, screenDelta.dy / sy);
  }

  /// 이미지 표시 영역 계산 (통합 함수)
  /// 모든 곳에서 이 함수만 사용하여 좌표계 일치 보장
  static Rect computeImageRect({
    required Size containerSize,
    required Size imageSize,
    double scale = 1.0,
    Offset offset = Offset.zero,
    double topMargin = 0.0,
    double bottomMargin = 0.0,
    double leftMargin = 0.0,
    double rightMargin = 0.0,
  }) {
    final imageAspect = imageSize.width / imageSize.height;

    // 마진을 적용한 실제 컨테이너 크기
    final availableWidth = containerSize.width - leftMargin - rightMargin;
    final availableHeight = containerSize.height - topMargin - bottomMargin;
    final availableSize = Size(availableWidth, availableHeight);
    final containerAspect = availableSize.width / availableSize.height;

    // 기본 표시 크기 계산 (scale 1.0 기준)
    double baseDisplayWidth, baseDisplayHeight;
    double baseImageOffsetX = 0, baseImageOffsetY = 0;

    if (imageAspect > containerAspect) {
      baseDisplayWidth = availableSize.width;
      baseDisplayHeight = availableSize.width / imageAspect;
      baseImageOffsetX = leftMargin;
      baseImageOffsetY =
          topMargin + (availableSize.height - baseDisplayHeight) / 2;
    } else {
      baseDisplayHeight = availableSize.height;
      baseDisplayWidth = availableSize.height * imageAspect;
      baseImageOffsetX =
          leftMargin + (availableSize.width - baseDisplayWidth) / 2;
      baseImageOffsetY = topMargin;
    }

    // 스케일 적용 (이미지 중심 기준으로 확대)
    final scaledWidth = baseDisplayWidth * scale;
    final scaledHeight = baseDisplayHeight * scale;

    // 스케일 적용 시 이미지 중심 기준으로 확대되므로 오프셋 조정
    final scaledImageOffsetX =
        baseImageOffsetX - (scaledWidth - baseDisplayWidth) / 2;
    final scaledImageOffsetY =
        baseImageOffsetY - (scaledHeight - baseDisplayHeight) / 2;

    // 추가 오프셋 적용
    final finalImageOffsetX = scaledImageOffsetX + offset.dx;
    final finalImageOffsetY = scaledImageOffsetY + offset.dy;

    return Rect.fromLTWH(
      finalImageOffsetX,
      finalImageOffsetY,
      scaledWidth,
      scaledHeight,
    );
  }

  /// 크롭 모드용 이미지 rect 계산 (항상 마진 적용)
  /// 크롭 모드에서는 항상 이 함수를 사용하여 마진이 보장되도록 함
  static Rect computeImageRectForCrop({
    required Size containerSize,
    required Size imageSize,
    double scale = 1.0,
    Offset offset = Offset.zero,
  }) {
    return computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
      topMargin: 4.0,
      bottomMargin: 4.0,
      leftMargin: 4.0,
      rightMargin: 4.0,
    );
  }
}

/// 크롭 핸들 타입
enum CropHandleType {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

/// 크롭 상태 관리 클래스
/// 🎯 상태의 진실은 오직 하나: image 좌표 cropRectImage
/// 화면 cropRect는 매번 계산해서 그리는 값
class CropState {
  String? selectedAspectRatio; // null = 자유, '1:1', '4:5', '16:9' 등
  Rect? cropRectImage; // 크롭 영역 (이미지 좌표계, 픽셀 기준) - 단일 진실
  // 정규화된 크롭 좌표 (0~1 범위) - 저장/복원용으로만 사용, 실시간 로직에서는 절대 사용 안 함
  double normalizedLeft = 0.0;
  double normalizedTop = 0.0;
  double normalizedWidth = 1.0;
  double normalizedHeight = 1.0;
  bool isCropRectInitialized = false;
  int rotation = 0; // 회전 각도

  void reset() {
    selectedAspectRatio = null;
    cropRectImage = null;
    normalizedLeft = 0.0;
    normalizedTop = 0.0;
    normalizedWidth = 1.0;
    normalizedHeight = 1.0;
    isCropRectInitialized = false;
    rotation = 0;
  }

  /// 정규화된 좌표를 픽셀 좌표로 변환 (크롭 시작 시 1회만 사용)
  Rect toPixelRect(Rect imageRect) {
    return Rect.fromLTWH(
      imageRect.left + normalizedLeft * imageRect.width,
      imageRect.top + normalizedTop * imageRect.height,
      normalizedWidth * imageRect.width,
      normalizedHeight * imageRect.height,
    );
  }

  /// 픽셀 좌표를 정규화된 좌표로 변환 (applyCrop 전용)
  void fromPixelRect(Rect pixelRect, Rect imageRect) {
    if (imageRect.width <= 0 || imageRect.height <= 0) return;

    normalizedLeft = ((pixelRect.left - imageRect.left) / imageRect.width)
        .clamp(0.0, 1.0);
    normalizedTop = ((pixelRect.top - imageRect.top) / imageRect.height).clamp(
      0.0,
      1.0,
    );
    normalizedWidth = (pixelRect.width / imageRect.width).clamp(0.0, 1.0);
    normalizedHeight = (pixelRect.height / imageRect.height).clamp(0.0, 1.0);
  }
}

/// 크롭 유틸리티 클래스
class CropUtils {
  CropUtils._();

  /// 크롭 영역 초기화
  static void initializeCropRect({
    required ui.Image image,
    required Size containerSize,
    required CropState cropState,
    double scale = 1.0,
    Offset offset = Offset.zero,
    Function(Size)? onDisplaySizeChanged,
  }) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // ✅ 실제 화면에 표시된 이미지 rect 계산 (scale과 offset 반영)
    // 크롭 모드이므로 상하좌우 마진 4픽셀 적용
    final displayImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );

    if (onDisplaySizeChanged != null) {
      onDisplaySizeChanged(
        Size(displayImageRect.width, displayImageRect.height),
      );
    }

    // ✅ 화면에 실제로 보이는 이미지 영역 계산 (containerSize와의 교집합)
    final visibleImageRect = displayImageRect.intersect(
      Rect.fromLTWH(0, 0, containerSize.width, containerSize.height),
    );

    // ✅ 비율 확인
    final targetAspectRatio =
        cropState.selectedAspectRatio != null
            ? CropGestureUtils.parseAspectRatio(cropState.selectedAspectRatio)
            : null;

    // ✅ 기본 크롭 영역 계산 (비율이 있으면 비율 적용)
    final margin = 0.0; // 여백 없음 - 이미지 경계에 완전히 붙임
    double cropWidth;
    double cropHeight;

    if (targetAspectRatio != null) {
      // 비율이 지정된 경우: 비율에 맞게 크롭 영역 계산
      // 화면에 보이는 이미지 영역의 80% 정도를 차지하도록 설정
      const targetCropRatio = 0.8;
      final targetVisibleWidth = visibleImageRect.width * targetCropRatio;
      final targetVisibleHeight = visibleImageRect.height * targetCropRatio;

      final targetAspect = targetAspectRatio;
      final targetVisibleAspect = targetVisibleWidth / targetVisibleHeight;

      if (targetAspect > targetVisibleAspect) {
        // 비율이 더 넓음: 너비를 기준으로 높이 계산
        cropWidth = targetVisibleWidth;
        cropHeight = targetVisibleWidth / targetAspect;
      } else {
        // 비율이 더 높음: 높이를 기준으로 너비 계산
        cropHeight = targetVisibleHeight;
        cropWidth = targetVisibleHeight * targetAspect;
      }

      // 화면에 보이는 영역을 초과하지 않도록 제한
      cropWidth = cropWidth.clamp(0.0, visibleImageRect.width);
      cropHeight = cropHeight.clamp(0.0, visibleImageRect.height);
    } else {
      // 비율이 없는 경우: 전체 영역 사용
      cropWidth = (visibleImageRect.width - margin * 2).clamp(
        0.0,
        visibleImageRect.width,
      );
      cropHeight = (visibleImageRect.height - margin * 2).clamp(
        0.0,
        visibleImageRect.height,
      );
    }

    final cropLeft =
        visibleImageRect.left + (visibleImageRect.width - cropWidth) / 2;
    final cropTop =
        visibleImageRect.top + (visibleImageRect.height - cropHeight) / 2;

    // ✅ 화면 좌표를 이미지 좌표로 변환
    final scaleX = imageSize.width / displayImageRect.width;
    final scaleY = imageSize.height / displayImageRect.height;

    // ✅ 화면 좌표의 크롭 박스를 이미지 좌표로 변환
    // displayImageRect 기준으로 상대 좌표 계산
    final cropRectImageLeft = (cropLeft - displayImageRect.left) * scaleX;
    final cropRectImageTop = (cropTop - displayImageRect.top) * scaleY;
    final cropRectImageWidth = cropWidth * scaleX;
    final cropRectImageHeight = cropHeight * scaleY;

    // ✅ 최종적으로 이미지 경계 내로 클램프
    cropState.cropRectImage = Rect.fromLTWH(
      cropRectImageLeft.clamp(0.0, imageSize.width),
      cropRectImageTop.clamp(0.0, imageSize.height),
      cropRectImageWidth.clamp(
        0.0,
        imageSize.width - cropRectImageLeft.clamp(0.0, imageSize.width),
      ),
      cropRectImageHeight.clamp(
        0.0,
        imageSize.height - cropRectImageTop.clamp(0.0, imageSize.height),
      ),
    );
    cropState.isCropRectInitialized = true;
  }

  /// 크롭 적용
  static Future<Uint8List?> applyCrop({
    required Uint8List imageBytes,
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double scale,
    required Offset offset,
    required int rotation,
  }) async {
    if (cropState.cropRectImage == null) return null;

    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // 회전 적용
      img.Image rotatedImage = image;
      if (rotation != 0) {
        rotatedImage = img.copyRotate(image, angle: rotation.toDouble());
      }

      // 크롭 영역을 이미지 좌표계에서 픽셀 좌표로 변환
      // scale과 offset을 고려하여 실제 이미지에서 크롭할 영역 계산
      final imageSize = Size(
        rotatedImage.width.toDouble(),
        rotatedImage.height.toDouble(),
      );

      // cropRectImage는 이미 이미지 좌표계이므로 그대로 사용
      final cropRect = cropState.cropRectImage!;

      // 이미지 경계 내로 클램프
      final clampedCropRect = Rect.fromLTWH(
        cropRect.left.clamp(0.0, imageSize.width),
        cropRect.top.clamp(0.0, imageSize.height),
        cropRect.width.clamp(0.0, imageSize.width - cropRect.left),
        cropRect.height.clamp(0.0, imageSize.height - cropRect.top),
      );

      // 크롭 실행
      final cropped = img.copyCrop(
        rotatedImage,
        x: clampedCropRect.left.toInt(),
        y: clampedCropRect.top.toInt(),
        width: clampedCropRect.width.toInt(),
        height: clampedCropRect.height.toInt(),
      );

      // Uint8List로 변환
      return Uint8List.fromList(img.encodePng(cropped));
    } catch (e) {
      debugPrint('크롭 적용 오류: $e');
      return null;
    }
  }
}

/// 이미지 Painter
class ImagePainter extends CustomPainter {
  final ui.Image image;
  final Offset imageOffset;
  final double imageScale;

  ImagePainter(this.image, this.imageOffset, this.imageScale);

  @override
  void paint(Canvas canvas, Size size) {
    // image는 항상 non-null이므로 null 체크 불필요

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = size.width / size.height;

    double baseDisplayWidth, baseDisplayHeight;
    double baseImageOffsetX = 0, baseImageOffsetY = 0;

    // ImagePainter는 크롭 모드에서만 사용되므로 항상 마진 적용
    const topMargin = 4.0;
    const bottomMargin = 4.0;
    final availableHeight = size.height - topMargin - bottomMargin;

    if (imageAspect > containerAspect) {
      baseDisplayWidth = size.width;
      baseDisplayHeight = size.width / imageAspect;
      baseImageOffsetY = topMargin + (availableHeight - baseDisplayHeight) / 2;
    } else {
      baseDisplayHeight = availableHeight;
      baseDisplayWidth = availableHeight * imageAspect;
      baseImageOffsetX = (size.width - baseDisplayWidth) / 2;
      baseImageOffsetY = topMargin;
    }

    final scaledWidth = baseDisplayWidth * imageScale;
    final scaledHeight = baseDisplayHeight * imageScale;

    final scaledImageOffsetX =
        baseImageOffsetX - (scaledWidth - baseDisplayWidth) / 2;
    final scaledImageOffsetY =
        baseImageOffsetY - (scaledHeight - baseDisplayHeight) / 2;

    final finalImageOffsetX = scaledImageOffsetX + imageOffset.dx;
    final finalImageOffsetY = scaledImageOffsetY + imageOffset.dy;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(
      finalImageOffsetX,
      finalImageOffsetY,
      scaledWidth,
      scaledHeight,
    );

    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }

  @override
  bool shouldRepaint(ImagePainter oldDelegate) {
    return oldDelegate.imageOffset != imageOffset ||
        oldDelegate.imageScale != imageScale ||
        oldDelegate.image != image;
  }
}

/// 크롭 오버레이 Painter
class CropOverlayPainter extends CustomPainter {
  final Rect cropRectScreen;
  final Rect imageRect;

  CropOverlayPainter({required this.cropRectScreen, required this.imageRect});

  @override
  void paint(Canvas canvas, Size size) {
    // 어두운 배경 (크롭 영역 외부만) - 크롭 박스 안은 제외
    final darkPaint = Paint()..color = Colors.black.withOpacity(0.8);

    // 크롭 영역을 제외한 4개의 사각형 영역에 어두운 필터 적용
    // 위쪽 영역
    if (cropRectScreen.top > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, cropRectScreen.top),
        darkPaint,
      );
    }

    // 아래쪽 영역
    if (cropRectScreen.bottom < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          cropRectScreen.bottom,
          size.width,
          size.height - cropRectScreen.bottom,
        ),
        darkPaint,
      );
    }

    // 왼쪽 영역
    if (cropRectScreen.left > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          cropRectScreen.top,
          cropRectScreen.left,
          cropRectScreen.height,
        ),
        darkPaint,
      );
    }

    // 오른쪽 영역
    if (cropRectScreen.right < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(
          cropRectScreen.right,
          cropRectScreen.top,
          size.width - cropRectScreen.right,
          cropRectScreen.height,
        ),
        darkPaint,
      );
    }

    // 크롭 박스 테두리
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    canvas.drawRect(cropRectScreen, borderPaint);

    // 3x3 그리드
    final gridPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

    final thirdWidth = cropRectScreen.width / 3;
    final thirdHeight = cropRectScreen.height / 3;

    // 세로 선 2개
    for (int i = 1; i < 3; i++) {
      final x = cropRectScreen.left + thirdWidth * i;
      canvas.drawLine(
        Offset(x, cropRectScreen.top),
        Offset(x, cropRectScreen.bottom),
        gridPaint,
      );
    }

    // 가로 선 2개
    for (int i = 1; i < 3; i++) {
      final y = cropRectScreen.top + thirdHeight * i;
      canvas.drawLine(
        Offset(cropRectScreen.left, y),
        Offset(cropRectScreen.right, y),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRectScreen != cropRectScreen ||
        oldDelegate.imageRect != imageRect;
  }
}

/// 크롭 핸들 코너 Painter
class CropCornerHandlePainter extends CustomPainter {
  final CropHandleType type;
  final double handleLength;
  final double handleThickness;
  final Color handleColor;

  CropCornerHandlePainter({
    required this.type,
    required this.handleLength,
    required this.handleThickness,
    required this.handleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = handleColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = handleThickness
          ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final halfLength = handleLength / 2;

    switch (type) {
      case CropHandleType.topLeft:
        // ┘ 모양 (좌우+상하 반전: 아래쪽과 오른쪽으로)
        canvas.drawLine(
          Offset(center.dx, center.dy + halfLength),
          center,
          paint,
        );
        canvas.drawLine(
          center,
          Offset(center.dx + halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.topRight:
        // └ 모양 (좌우+상하 반전: 아래쪽과 왼쪽으로)
        canvas.drawLine(
          Offset(center.dx, center.dy + halfLength),
          center,
          paint,
        );
        canvas.drawLine(
          center,
          Offset(center.dx - halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.bottomLeft:
        // ┐ 모양 (좌우+상하 반전: 위쪽과 오른쪽으로)
        canvas.drawLine(
          Offset(center.dx, center.dy - halfLength),
          center,
          paint,
        );
        canvas.drawLine(
          center,
          Offset(center.dx + halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.bottomRight:
        // ┌ 모양 (좌우+상하 반전: 위쪽과 왼쪽으로)
        canvas.drawLine(
          Offset(center.dx, center.dy - halfLength),
          center,
          paint,
        );
        canvas.drawLine(
          center,
          Offset(center.dx - halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.top:
        // ─ 모양 (위)
        canvas.drawLine(
          Offset(center.dx - halfLength, center.dy),
          Offset(center.dx + halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.bottom:
        // ─ 모양 (아래)
        canvas.drawLine(
          Offset(center.dx - halfLength, center.dy),
          Offset(center.dx + halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.left:
        // │ 모양 (왼쪽)
        canvas.drawLine(
          Offset(center.dx, center.dy - halfLength),
          Offset(center.dx, center.dy + halfLength),
          paint,
        );
        break;
      case CropHandleType.right:
        // │ 모양 (오른쪽)
        canvas.drawLine(
          Offset(center.dx, center.dy - halfLength),
          Offset(center.dx, center.dy + halfLength),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(CropCornerHandlePainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.handleLength != handleLength ||
        oldDelegate.handleThickness != handleThickness ||
        oldDelegate.handleColor != handleColor;
  }
}

/// 크롭 제스처 및 핸들 관리 유틸리티
class CropGestureUtils {
  CropGestureUtils._();

  /// 핸들 위치에서 핸들 타입 찾기
  static CropHandleType? getHandleAtPosition(Offset pos, Rect cropRect) {
    const handleTouchRadius = 30.0;
    final handles = [
      (cropRect.topLeft, CropHandleType.topLeft),
      (cropRect.topRight, CropHandleType.topRight),
      (cropRect.bottomLeft, CropHandleType.bottomLeft),
      (cropRect.bottomRight, CropHandleType.bottomRight),
      (Offset(cropRect.center.dx, cropRect.top), CropHandleType.top),
      (Offset(cropRect.center.dx, cropRect.bottom), CropHandleType.bottom),
      (Offset(cropRect.left, cropRect.center.dy), CropHandleType.left),
      (Offset(cropRect.right, cropRect.center.dy), CropHandleType.right),
    ];

    for (final (handlePos, type) in handles) {
      if ((pos - handlePos).distance < handleTouchRadius) {
        return type;
      }
    }
    return null;
  }

  /// ❌ updateCropRectMove 제거됨 - 크롭 이동은 금지, 이미지만 이동 가능

  /// 크롭 영역 리사이즈 (이미지 좌표 기준)
  static void updateCropRectResize({
    required CropHandleType handle,
    required Offset screenDelta,
    required CropState cropState,
    required Rect screenImageRect,
    required Size imageSize,
  }) {
    if (cropState.cropRectImage == null) return;

    // 🎯 화면 델타 → 이미지 델타 변환
    final imageDelta = ImageRectUtils.screenDeltaToImageDelta(
      screenDelta: screenDelta,
      screenImageRect: screenImageRect,
      imageSize: imageSize,
    );

    final minSize =
        (imageSize.width < imageSize.height
            ? imageSize.width
            : imageSize.height) *
        0.1;

    // ✅ 비율 확인
    final aspectRatio = parseAspectRatio(cropState.selectedAspectRatio);

    Rect newRect = cropState.cropRectImage!;

    if (aspectRatio != null) {
      // ✅ 비율 모드: 한 핸들을 드래그하면 중심점 기준으로 크기가 조정되고 모든 핸들이 함께 움직임
      final currentRect = cropState.cropRectImage!;
      final centerX = currentRect.center.dx;
      final centerY = currentRect.center.dy;

      // ✅ 경계에 도달했는지 확인 (비율 깨짐 방지)
      const tolerance = 0.1;
      final isAtLeftEdge = currentRect.left <= tolerance;
      final isAtRightEdge = currentRect.right >= imageSize.width - tolerance;
      final isAtTopEdge = currentRect.top <= tolerance;
      final isAtBottomEdge = currentRect.bottom >= imageSize.height - tolerance;

      // 드래그된 핸들의 이동량에 따라 크롭박스 크기 변화 계산
      double widthDelta = 0.0;
      double heightDelta = 0.0;

      switch (handle) {
        case CropHandleType.topLeft:
          // 왼쪽 위로 드래그: 크기 감소 또는 증가
          // 왼쪽 경계 도달 + 왼쪽으로 확대 시도 → 차단
          if (isAtLeftEdge && imageDelta.dx < 0) {
            return; // 비율 깨짐 방지
          }
          // 위쪽 경계 도달 + 위로 확대 시도 → 차단
          if (isAtTopEdge && imageDelta.dy < 0) {
            return; // 비율 깨짐 방지
          }
          widthDelta = -imageDelta.dx * 2;
          heightDelta = -imageDelta.dy * 2;
          break;
        case CropHandleType.topRight:
          // 오른쪽 위로 드래그: 너비 증가, 높이 감소
          // 오른쪽 경계 도달 + 오른쪽으로 확대 시도 → 차단
          if (isAtRightEdge && imageDelta.dx > 0) {
            return; // 비율 깨짐 방지
          }
          // 위쪽 경계 도달 + 위로 확대 시도 → 차단
          if (isAtTopEdge && imageDelta.dy < 0) {
            return; // 비율 깨짐 방지
          }
          widthDelta = imageDelta.dx * 2;
          heightDelta = -imageDelta.dy * 2;
          break;
        case CropHandleType.bottomLeft:
          // 왼쪽 아래로 드래그: 너비 감소, 높이 증가
          // 왼쪽 경계 도달 + 왼쪽으로 확대 시도 → 차단
          if (isAtLeftEdge && imageDelta.dx < 0) {
            return; // 비율 깨짐 방지
          }
          // 아래쪽 경계 도달 + 아래로 확대 시도 → 차단
          if (isAtBottomEdge && imageDelta.dy > 0) {
            return; // 비율 깨짐 방지
          }
          widthDelta = -imageDelta.dx * 2;
          heightDelta = imageDelta.dy * 2;
          break;
        case CropHandleType.bottomRight:
          // 오른쪽 아래로 드래그: 크기 증가
          // 오른쪽 경계 도달 + 오른쪽으로 확대 시도 → 차단
          if (isAtRightEdge && imageDelta.dx > 0) {
            return; // 비율 깨짐 방지
          }
          // 아래쪽 경계 도달 + 아래로 확대 시도 → 차단
          if (isAtBottomEdge && imageDelta.dy > 0) {
            return; // 비율 깨짐 방지
          }
          widthDelta = imageDelta.dx * 2;
          heightDelta = imageDelta.dy * 2;
          break;
        case CropHandleType.top:
          // 위로 드래그: 높이 감소
          // 위쪽 경계 도달 + 위로 확대 시도 → 차단
          if (isAtTopEdge && imageDelta.dy < 0) {
            return; // 비율 깨짐 방지
          }
          heightDelta = -imageDelta.dy * 2;
          break;
        case CropHandleType.bottom:
          // 아래로 드래그: 높이 증가
          // 아래쪽 경계 도달 + 아래로 확대 시도 → 차단
          if (isAtBottomEdge && imageDelta.dy > 0) {
            return; // 비율 깨짐 방지
          }
          heightDelta = imageDelta.dy * 2;
          break;
        case CropHandleType.left:
          // 왼쪽으로 드래그: 너비 감소
          // 왼쪽 경계 도달 + 왼쪽으로 확대 시도 → 차단
          if (isAtLeftEdge && imageDelta.dx < 0) {
            return; // 비율 깨짐 방지
          }
          widthDelta = -imageDelta.dx * 2;
          break;
        case CropHandleType.right:
          // 오른쪽으로 드래그: 너비 증가
          // 오른쪽 경계 도달 + 오른쪽으로 확대 시도 → 차단
          if (isAtRightEdge && imageDelta.dx > 0) {
            return; // 비율 깨짐 방지
          }
          widthDelta = imageDelta.dx * 2;
          break;
      }

      // 새로운 크기 계산
      double newWidth = currentRect.width + widthDelta;
      double newHeight = currentRect.height + heightDelta;

      // aspectRatio가 null이 아님은 위의 if 조건으로 보장됨
      final targetAspect = aspectRatio;

      // 비율에 맞게 조정 (더 큰 변화를 기준으로)
      final widthChangeRatio = widthDelta.abs() / currentRect.width;
      final heightChangeRatio = heightDelta.abs() / currentRect.height;

      if (widthChangeRatio > heightChangeRatio) {
        // 너비 변화가 더 큼: 너비를 기준으로 높이 조정
        newHeight = newWidth / targetAspect;
      } else {
        // 높이 변화가 더 큼: 높이를 기준으로 너비 조정
        newWidth = newHeight * targetAspect;
      }

      // ✅ 비율 조정 직후 비율 검증: 비율이 깨지면 스킵
      final adjustedAspect = newWidth / newHeight;
      if ((adjustedAspect - targetAspect).abs() > 0.001) {
        // 비율이 깨졌으면 이번 업데이트를 스킵
        return;
      }

      // 최소 크기 보장
      newWidth = newWidth.clamp(minSize, imageSize.width);
      newHeight = newHeight.clamp(minSize, imageSize.height);

      // 최소 크기 클램프 후 비율 검증: 비율이 깨지면 스킵
      final clampedAspect = newWidth / newHeight;
      if ((clampedAspect - targetAspect).abs() > 0.001) {
        // 최소 크기 클램프로 비율이 깨졌으면 이번 업데이트를 스킵
        return;
      }

      // 중심점을 기준으로 새 크롭박스 생성 (비율 모드에서는 모든 핸들이 함께 움직임)
      newRect = Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: newWidth,
        height: newHeight,
      );

      // 이미지 경계 내로 클램프
      if (newRect.left < 0) {
        newRect = newRect.shift(Offset(-newRect.left, 0));
      }
      if (newRect.top < 0) {
        newRect = newRect.shift(Offset(0, -newRect.top));
      }
      if (newRect.right > imageSize.width) {
        newRect = newRect.shift(Offset(imageSize.width - newRect.right, 0));
      }
      if (newRect.bottom > imageSize.height) {
        newRect = newRect.shift(Offset(0, imageSize.height - newRect.bottom));
      }
    } else {
      // ✅ 자유 모드: 각 핸들을 개별적으로 움직임
      switch (handle) {
        case CropHandleType.topLeft:
          newRect = Rect.fromLTRB(
            (cropState.cropRectImage!.left + imageDelta.dx).clamp(
              0.0,
              cropState.cropRectImage!.right - minSize,
            ),
            (cropState.cropRectImage!.top + imageDelta.dy).clamp(
              0.0,
              cropState.cropRectImage!.bottom - minSize,
            ),
            cropState.cropRectImage!.right,
            cropState.cropRectImage!.bottom,
          );
          break;
        case CropHandleType.topRight:
          newRect = Rect.fromLTRB(
            cropState.cropRectImage!.left,
            (cropState.cropRectImage!.top + imageDelta.dy).clamp(
              0.0,
              cropState.cropRectImage!.bottom - minSize,
            ),
            (cropState.cropRectImage!.right + imageDelta.dx).clamp(
              cropState.cropRectImage!.left + minSize,
              imageSize.width,
            ),
            cropState.cropRectImage!.bottom,
          );
          break;
        case CropHandleType.bottomLeft:
          newRect = Rect.fromLTRB(
            (cropState.cropRectImage!.left + imageDelta.dx).clamp(
              0.0,
              cropState.cropRectImage!.right - minSize,
            ),
            cropState.cropRectImage!.top,
            cropState.cropRectImage!.right,
            (cropState.cropRectImage!.bottom + imageDelta.dy).clamp(
              cropState.cropRectImage!.top + minSize,
              imageSize.height,
            ),
          );
          break;
        case CropHandleType.bottomRight:
          newRect = Rect.fromLTRB(
            cropState.cropRectImage!.left,
            cropState.cropRectImage!.top,
            (cropState.cropRectImage!.right + imageDelta.dx).clamp(
              cropState.cropRectImage!.left + minSize,
              imageSize.width,
            ),
            (cropState.cropRectImage!.bottom + imageDelta.dy).clamp(
              cropState.cropRectImage!.top + minSize,
              imageSize.height,
            ),
          );
          break;
        case CropHandleType.top:
          newRect = Rect.fromLTRB(
            cropState.cropRectImage!.left,
            (cropState.cropRectImage!.top + imageDelta.dy).clamp(
              0.0,
              cropState.cropRectImage!.bottom - minSize,
            ),
            cropState.cropRectImage!.right,
            cropState.cropRectImage!.bottom,
          );
          break;
        case CropHandleType.bottom:
          newRect = Rect.fromLTRB(
            cropState.cropRectImage!.left,
            cropState.cropRectImage!.top,
            cropState.cropRectImage!.right,
            (cropState.cropRectImage!.bottom + imageDelta.dy).clamp(
              cropState.cropRectImage!.top + minSize,
              imageSize.height,
            ),
          );
          break;
        case CropHandleType.left:
          newRect = Rect.fromLTRB(
            (cropState.cropRectImage!.left + imageDelta.dx).clamp(
              0.0,
              cropState.cropRectImage!.right - minSize,
            ),
            cropState.cropRectImage!.top,
            cropState.cropRectImage!.right,
            cropState.cropRectImage!.bottom,
          );
          break;
        case CropHandleType.right:
          newRect = Rect.fromLTRB(
            cropState.cropRectImage!.left,
            cropState.cropRectImage!.top,
            (cropState.cropRectImage!.right + imageDelta.dx).clamp(
              cropState.cropRectImage!.left + minSize,
              imageSize.width,
            ),
            cropState.cropRectImage!.bottom,
          );
          break;
      }
    }

    // 🎯 최종 검증: 이미지 경계 내로 clamp
    newRect = newRect.intersect(
      Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
    );

    // 최소 크기 보장
    if (newRect.width < minSize || newRect.height < minSize) {
      return; // 최소 크기보다 작아지면 무시
    }

    cropState.cropRectImage = newRect;
  }

  /// 비율 파싱
  static double? parseAspectRatio(String? ratio) {
    if (ratio == null) return null;
    final parts = ratio.split(':');
    if (parts.length != 2) return null;
    final w = double.tryParse(parts[0]);
    final h = double.tryParse(parts[1]);
    if (w == null || h == null || h == 0) return null;
    return w / h;
  }
}

/// 크롭 핸들 빌더
class CropHandleBuilder {
  CropHandleBuilder._();

  /// 크롭 핸들들 빌드
  /// 🎯 screenImageRect와 imageSize를 받아서 화면 좌표 cropRect 계산
  static Widget buildCropHandles({
    required CropState cropState,
    required CropHandleType? activeHandle,
    required ValueChanged<CropHandleType?> onHandleChanged,
    required VoidCallback onUpdate,
    Function(CropHandleType, Offset)? onResize,
    VoidCallback? onResizeEnd,
    required Rect screenImageRect,
    required Size imageSize,
    Rect? cropRectScreen, // ✅ 옵셔널: 드래그 중 고정된 크롭박스 위치
  }) {
    if (cropState.cropRectImage == null) {
      return const SizedBox.shrink();
    }

    // 🎯 화면 좌표 cropRect 계산
    // ✅ cropRectScreen이 제공되면 사용, 없으면 재계산
    final finalCropRectScreen =
        cropRectScreen ??
        ImageRectUtils.imageToScreenRect(
          imageRect: cropState.cropRectImage!,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        );

    // ✅ 핸들은 크롭박스 좌표를 기준으로 직접 배치 (clamp 없이)
    // 비율 모드에서도 핸들이 보이지만, 리사이즈 시 비율이 유지됨
    return Stack(
      children: [
        _CropHandleWidget(
          position: finalCropRectScreen.topLeft,
          type: CropHandleType.topLeft,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: finalCropRectScreen.topRight,
          type: CropHandleType.topRight,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: finalCropRectScreen.bottomLeft,
          type: CropHandleType.bottomLeft,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: finalCropRectScreen.bottomRight,
          type: CropHandleType.bottomRight,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: Offset(
            finalCropRectScreen.center.dx,
            finalCropRectScreen.top,
          ),
          type: CropHandleType.top,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: Offset(
            finalCropRectScreen.center.dx,
            finalCropRectScreen.bottom,
          ),
          type: CropHandleType.bottom,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: Offset(
            finalCropRectScreen.left,
            finalCropRectScreen.center.dy,
          ),
          type: CropHandleType.left,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
        _CropHandleWidget(
          position: Offset(
            finalCropRectScreen.right,
            finalCropRectScreen.center.dy,
          ),
          type: CropHandleType.right,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
          screenImageRect: screenImageRect,
          imageSize: imageSize,
        ),
      ],
    );
  }
}

/// 개별 크롭 핸들 위젯 (각 핸들마다 독립적인 상태 관리)
class _CropHandleWidget extends StatefulWidget {
  final Offset position;
  final CropHandleType type;
  final CropHandleType? activeHandle;
  final CropState cropState;
  final ValueChanged<CropHandleType?> onHandleChanged;
  final VoidCallback onUpdate;
  final Function(CropHandleType, Offset)? onResize;
  final VoidCallback? onResizeEnd;
  final Rect screenImageRect;
  final Size imageSize;

  const _CropHandleWidget({
    required this.position,
    required this.type,
    required this.activeHandle,
    required this.cropState,
    required this.onHandleChanged,
    required this.onUpdate,
    this.onResize,
    this.onResizeEnd,
    required this.screenImageRect,
    required this.imageSize,
  });

  @override
  State<_CropHandleWidget> createState() => _CropHandleWidgetState();
}

class _CropHandleWidgetState extends State<_CropHandleWidget> {
  Offset? _panStart;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.activeHandle == widget.type;
    final handleSize = 30.0; // 액티브 상태와 관계없이 항상 같은 크기
    final touchSize = 44.0;

    return Positioned(
      left: widget.position.dx - touchSize / 2,
      top: widget.position.dy - touchSize / 2,
      child: GestureDetector(
        onPanStart: (details) {
          widget.onHandleChanged(widget.type);
          setState(() {
            // ✅ localPosition 사용 (위젯 기준 좌표)
            _panStart = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          if (_panStart == null) return;
          // ✅ localPosition 사용 (위젯 기준 좌표)
          final delta = details.localPosition - _panStart!;
          // 외부 리사이즈 콜백이 있으면 사용, 없으면 기본 동작
          if (widget.onResize != null) {
            widget.onResize!(widget.type, delta);
          } else {
            CropGestureUtils.updateCropRectResize(
              handle: widget.type,
              screenDelta: delta,
              cropState: widget.cropState,
              screenImageRect: widget.screenImageRect,
              imageSize: widget.imageSize,
            );
          }
          setState(() {
            // ✅ localPosition 사용 (위젯 기준 좌표)
            _panStart = details.localPosition;
          });
          widget.onUpdate();
        },
        onPanEnd: (_) {
          debugPrint('🟢 [_CropHandleWidget onPanEnd] handle: ${widget.type}');
          widget.onHandleChanged(null);
          // 🎯 리사이즈 완료 콜백 호출 (안정적으로 실행되도록)
          if (widget.onResizeEnd != null) {
            widget.onResizeEnd!();
          }
          setState(() {
            _panStart = null;
          });
        },
        child: SizedBox(
          width: touchSize,
          height: touchSize,
          child: Center(
            child: _buildCornerHandle(widget.type, handleSize, isActive),
          ),
        ),
      ),
    );
  }

  Widget _buildCornerHandle(
    CropHandleType type,
    double handleSize,
    bool isActive,
  ) {
    final handleThickness = 4.0; // 액티브 상태와 관계없이 항상 같은 두께
    final handleLength = handleSize * 0.6;

    return Container(
      width: handleSize,
      height: handleSize,
      child: CustomPaint(
        painter: CropCornerHandlePainter(
          type: type,
          handleLength: handleLength,
          handleThickness: handleThickness,
          handleColor: Colors.white,
        ),
      ),
    );
  }
}

/// 🎯 크롭 제스처 핸들러 클래스
/// 크롭 관련 모든 제스처 처리를 담당
class CropGestureHandler {
  // 드래그 중 상태
  bool _isDraggingImage = false;
  Rect? _frozenImageRect;
  Rect? _frozenCropRectScreen;
  Offset? _lastPanPosition;
  CropHandleType? _activeCropHandle;

  // 핀치 줌 상태
  double? _initialScale; // 핀치 시작 시 초기 scale
  bool _isPinching = false;

  // 드래그 감도 및 복귀 감도
  static const double _dragResistance = 0.6;
  static const double _snapBackStrength = 1.5;
  static const double _minImageScale = 1.0; // 최소 줌 레벨 (축소 제한)

  /// 드래그 시작 처리
  void onScaleStart({
    required ScaleStartDetails details,
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    _lastPanPosition = details.focalPoint;
    _initialScale = imageScale; // 핀치 줌을 위한 초기 scale 저장
    _isPinching = false;

    if (cropState.isCropRectInitialized && cropState.cropRectImage != null) {
      final imageSize = Size(
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      );
      final currentImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: imageScale,
        offset: imageOffset,
      );

      // ✅ 드래그 시작 시 imageRect와 cropRectScreen 모두 freeze (복귀 기준으로 사용)
      _frozenImageRect = currentImageRect;
      _frozenCropRectScreen = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: currentImageRect,
        imageSize: imageSize,
      );
      _isDraggingImage = true;
    }
  }

  /// 드래그 업데이트 처리 (고무줄 저항 포함) + 핀치 줌 처리
  ScaleUpdateResult? onScaleUpdate({
    required ScaleUpdateDetails details,
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
    required VoidCallback onStateChanged,
  }) {
    if (!cropState.isCropRectInitialized) return null;
    // 핸들 드래그 중이면 무시
    if (_activeCropHandle != null) return null;

    // 핀치 줌 처리 (scale 변화가 있을 때)
    if ((details.scale - 1.0).abs() >= 0.001) {
      _isPinching = true;
      _initialScale ??= imageScale;

      final imageSize = Size(
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      );

      // 새로운 scale 계산 (초기 scale * 현재 scale 변화)
      double newScale = _initialScale! * details.scale;

      // ✅ 축소 시도 시: 현재 스케일이 이미 1.0 이하면 더 이상 축소 불가
      if (details.scale < 1.0 && imageScale <= _minImageScale) {
        // 축소 시도 무시
        return null;
      }

      // ✅ 핀치 축소 허용 조건: 이미지가 cropRect를 덮고 있어야 함
      if (details.scale < 1.0 && cropState.cropRectImage != null) {
        final testImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: newScale,
          offset: imageOffset,
        );

        final testCropRectScreen = ImageRectUtils.imageToScreenRect(
          imageRect: cropState.cropRectImage!,
          screenImageRect: testImageRect,
          imageSize: imageSize,
        );

        // ✅ 이미지가 cropRect를 완전히 덮지 못하면 축소 금지
        if (testImageRect.left > testCropRectScreen.left ||
            testImageRect.top > testCropRectScreen.top ||
            testImageRect.right < testCropRectScreen.right ||
            testImageRect.bottom < testCropRectScreen.bottom) {
          // 축소 금지: 현재 scale 유지
          return null;
        }
      }

      // 최소 scale 제한
      if (newScale < _minImageScale) {
        return null;
      }

      // 최대 scale 제한
      newScale = newScale.clamp(_minImageScale, 5.0);

      return ScaleUpdateResult(
        scale: newScale,
        offset: null, // 핀치 줌 중에는 offset 변경 없음
      );
    }

    // 핀치 줌이 아닌 경우 (scale이 1.0에 가까움) = 일반 드래그
    _isPinching = false;
    // (1) delta 계산 (이전 위치와 현재 위치의 차이)
    if (_lastPanPosition == null) {
      _lastPanPosition = details.focalPoint;
      return null;
    }
    final delta = details.focalPoint - _lastPanPosition!;
    _lastPanPosition = details.focalPoint;

    final imageSize = Size(uiImage.width.toDouble(), uiImage.height.toDouble());

    // ✅ 스케일이 1.0 이하이고 크롭박스가 이미지 경계에 붙어있으면 드래그 막기
    if (imageScale <= _minImageScale && cropState.cropRectImage != null) {
      const tolerance = 0.1; // 경계 판정 여유값
      final cropRect = cropState.cropRectImage!;

      // 왼쪽으로 드래그하려고 하는데 왼쪽 경계에 붙어있으면 막기
      if (delta.dx < 0 && cropRect.left <= tolerance) {
        return null;
      }
      // 오른쪽으로 드래그하려고 하는데 오른쪽 경계에 붙어있으면 막기
      if (delta.dx > 0 && cropRect.right >= imageSize.width - tolerance) {
        return null;
      }
      // 위로 드래그하려고 하는데 위쪽 경계에 붙어있으면 막기
      if (delta.dy < 0 && cropRect.top <= tolerance) {
        return null;
      }
      // 아래로 드래그하려고 하는데 아래쪽 경계에 붙어있으면 막기
      if (delta.dy > 0 && cropRect.bottom >= imageSize.height - tolerance) {
        return null;
      }
    }

    final proposedOffset = imageOffset + delta;

    // (2) 고무줄 감쇠 판정
    final testImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: imageScale,
      offset: proposedOffset,
    );
    final testCropRectScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropState.cropRectImage!,
      screenImageRect: testImageRect,
      imageSize: imageSize,
    );

    // (3) 고무줄 감쇠 적용
    double dx = delta.dx;
    double dy = delta.dy;

    if (testCropRectScreen.left < 0 ||
        testCropRectScreen.right > containerSize.width) {
      dx *= _dragResistance;
    }

    if (testCropRectScreen.top < 0 ||
        testCropRectScreen.bottom > containerSize.height) {
      dy *= _dragResistance;
    }

    // (4) 새로운 offset 반환
    return ScaleUpdateResult(
      scale: null,
      offset: Offset(dx / imageScale, dy / imageScale),
    );
  }

  /// 드래그 종료 처리 (복귀 로직 포함) + 핀치 줌 종료 처리
  CropDragEndResult? onScaleEnd({
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    _lastPanPosition = null;

    // ✅ 핸들 리사이즈 중이면 복귀 로직 스킵
    if (_activeCropHandle != null) {
      _isDraggingImage = false;
      _frozenImageRect = null;
      _frozenCropRectScreen = null;
      _initialScale = null;
      _isPinching = false;
      return null;
    }

    // ✅ 핀치 줌이 끝났을 때 처리
    if (_isPinching) {
      // scale이 최소값보다 작으면 복귀
      if (imageScale < _minImageScale) {
        _isDraggingImage = false;
        _frozenImageRect = null;
        _frozenCropRectScreen = null;
        _initialScale = null;
        _isPinching = false;

        // scale을 최소값으로 복귀
        return CropDragEndResult(
          snapBackOffset: null,
          cropRectImagePosition: null,
          cropRectImageSize: null,
          snapBackScale: _minImageScale, // 복귀할 scale 값
        );
      }

      // ✅ 핀치 줌 후: 크롭박스가 이미지 영역 밖으로 나갔는지 확인 후 복귀
      final imageSize = Size(
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      );

      // 현재 scale 기준으로 이미지 rect 계산
      final currentImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: imageScale,
        offset: imageOffset,
      );

      // 화면에서 크롭박스 위치는 고정 (_frozenCropRectScreen 기준)
      if (_frozenCropRectScreen != null) {
        // ✅ 드래그 종료와 동일한 로직: 크롭박스가 이미지 영역 밖으로 나갔는지 확인
        double adjustX = 0.0;
        double adjustY = 0.0;

        // 이미지가 고정된 크롭박스 왼쪽으로 벗어나면 오른쪽으로 이동
        if (currentImageRect.left > _frozenCropRectScreen!.left) {
          adjustX = _frozenCropRectScreen!.left - currentImageRect.left;
        }
        // 이미지가 고정된 크롭박스 오른쪽으로 벗어나면 왼쪽으로 이동
        else if (currentImageRect.right < _frozenCropRectScreen!.right) {
          adjustX = _frozenCropRectScreen!.right - currentImageRect.right;
        }

        // 이미지가 고정된 크롭박스 위로 벗어나면 아래로 이동
        if (currentImageRect.top > _frozenCropRectScreen!.top) {
          adjustY = _frozenCropRectScreen!.top - currentImageRect.top;
        }
        // 이미지가 고정된 크롭박스 아래로 벗어나면 위로 이동
        else if (currentImageRect.bottom < _frozenCropRectScreen!.bottom) {
          adjustY = _frozenCropRectScreen!.bottom - currentImageRect.bottom;
        }

        Offset? snapBackOffset;

        // ✅ 벗어났으면 offset 조정하여 복귀
        if (adjustX != 0.0 || adjustY != 0.0) {
          snapBackOffset = Offset(
            (adjustX / imageScale) * _snapBackStrength,
            (adjustY / imageScale) * _snapBackStrength,
          );
        }

        // ✅ 핀치 줌 완료 시: 화면 중앙 기준으로 cropRectImage 재계산
        final finalImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: imageScale,
          offset:
              snapBackOffset != null
                  ? imageOffset + snapBackOffset
                  : imageOffset,
        );
        final containerCenter = Offset(
          containerSize.width / 2,
          containerSize.height / 2,
        );
        final sx = finalImageRect.width / imageSize.width;
        final sy = finalImageRect.height / imageSize.height;
        final cropSizeScreen = Size(
          cropState.cropRectImage!.width * sx,
          cropState.cropRectImage!.height * sy,
        );
        final centerScreenRect = Rect.fromCenter(
          center: containerCenter,
          width: cropSizeScreen.width,
          height: cropSizeScreen.height,
        );
        // 화면 좌표 → 이미지 좌표 변환
        final cropRectImageUpdate = Offset(
          (centerScreenRect.left - finalImageRect.left) / sx,
          (centerScreenRect.top - finalImageRect.top) / sy,
        );

        _isDraggingImage = false;
        _frozenImageRect = null;
        _frozenCropRectScreen = null;
        _initialScale = null;
        _isPinching = false;

        return CropDragEndResult(
          snapBackOffset: snapBackOffset,
          cropRectImagePosition: cropRectImageUpdate, // ✅ 화면 중앙 기준으로 재계산
          cropRectImageSize: Size(
            cropState.cropRectImage!.width,
            cropState.cropRectImage!.height,
          ),
          snapBackScale: null,
        );
      }

      _isDraggingImage = false;
      _frozenImageRect = null;
      _frozenCropRectScreen = null;
      _initialScale = null;
      _isPinching = false;
      return null;
    }

    // ✅ 드래그 완료 시: 고정된 기준으로 크롭박스 밖으로 나갔는지 확인 후 복귀
    if (cropState.isCropRectInitialized &&
        _isDraggingImage &&
        _frozenCropRectScreen != null) {
      final imageSize = Size(
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      );

      // 현재 이미지 rect (최종 offset 기준)
      final currentImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: imageScale,
        offset: imageOffset,
      );

      // ✅ 고정된 기준(_frozenCropRectScreen)으로 벗어남 확인
      double adjustX = 0.0;
      double adjustY = 0.0;

      // 이미지가 고정된 크롭박스 왼쪽으로 벗어나면 오른쪽으로 이동
      if (currentImageRect.left > _frozenCropRectScreen!.left) {
        adjustX = _frozenCropRectScreen!.left - currentImageRect.left;
      }
      // 이미지가 고정된 크롭박스 오른쪽으로 벗어나면 왼쪽으로 이동
      else if (currentImageRect.right < _frozenCropRectScreen!.right) {
        adjustX = _frozenCropRectScreen!.right - currentImageRect.right;
      }

      // 이미지가 고정된 크롭박스 위로 벗어나면 아래로 이동
      if (currentImageRect.top > _frozenCropRectScreen!.top) {
        adjustY = _frozenCropRectScreen!.top - currentImageRect.top;
      }
      // 이미지가 고정된 크롭박스 아래로 벗어나면 위로 이동
      else if (currentImageRect.bottom < _frozenCropRectScreen!.bottom) {
        adjustY = _frozenCropRectScreen!.bottom - currentImageRect.bottom;
      }

      Offset? snapBackOffset;

      // ✅ 벗어났으면 offset 조정하여 복귀
      if (adjustX != 0.0 || adjustY != 0.0) {
        snapBackOffset = Offset(
          (adjustX / imageScale) * _snapBackStrength,
          (adjustY / imageScale) * _snapBackStrength,
        );
      }

      // ✅ 드래그 완료 시: 화면 중앙 기준으로 cropRectImage 재계산
      final finalImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: imageScale,
        offset:
            snapBackOffset != null ? imageOffset + snapBackOffset : imageOffset,
      );
      final containerCenter = Offset(
        containerSize.width / 2,
        containerSize.height / 2,
      );
      final sx = finalImageRect.width / imageSize.width;
      final sy = finalImageRect.height / imageSize.height;
      final cropSizeScreen = Size(
        cropState.cropRectImage!.width * sx,
        cropState.cropRectImage!.height * sy,
      );
      final centerScreenRect = Rect.fromCenter(
        center: containerCenter,
        width: cropSizeScreen.width,
        height: cropSizeScreen.height,
      );
      // 화면 좌표 → 이미지 좌표 변환
      final cropRectImageUpdate = Offset(
        (centerScreenRect.left - finalImageRect.left) / sx,
        (centerScreenRect.top - finalImageRect.top) / sy,
      );

      // ✅ 드래그 종료 시 freeze 해제
      _isDraggingImage = false;
      _frozenImageRect = null;
      _frozenCropRectScreen = null;

      return CropDragEndResult(
        snapBackOffset: snapBackOffset,
        cropRectImagePosition: cropRectImageUpdate, // ✅ 화면 중앙 기준으로 재계산
        cropRectImageSize: Size(
          cropState.cropRectImage!.width,
          cropState.cropRectImage!.height,
        ),
      );
    }

    // ✅ 드래그 종료 시 freeze 해제
    _isDraggingImage = false;
    _frozenImageRect = null;
    _frozenCropRectScreen = null;
    _initialScale = null;
    _isPinching = false;

    return null;
  }

  /// 활성 핸들 설정
  void setActiveHandle(CropHandleType? handle) {
    _activeCropHandle = handle;
  }

  /// 활성 핸들 가져오기
  CropHandleType? get activeHandle => _activeCropHandle;

  /// 드래그 중 여부
  bool get isDraggingImage => _isDraggingImage;

  /// Freeze된 이미지 rect 가져오기
  Rect? get frozenImageRect => _frozenImageRect;

  /// Freeze된 크롭 rect (화면 좌표) 가져오기
  Rect? get frozenCropRectScreen => _frozenCropRectScreen;

  /// 리셋
  void reset() {
    _isDraggingImage = false;
    _frozenImageRect = null;
    _frozenCropRectScreen = null;
    _lastPanPosition = null;
    _activeCropHandle = null;
    _initialScale = null;
    _isPinching = false;
  }
}

/// 드래그 종료 결과
class CropDragEndResult {
  final Offset? snapBackOffset;
  final Offset? cropRectImagePosition;
  final Size? cropRectImageSize; // nullable로 변경 (snap-back에서는 null)
  final double? snapBackScale; // 핀치 줌 복귀용 scale

  CropDragEndResult({
    this.snapBackOffset,
    this.cropRectImagePosition,
    this.cropRectImageSize,
    this.snapBackScale,
  });
}

/// 스케일 업데이트 결과
class ScaleUpdateResult {
  final double? scale;
  final Offset? offset;

  ScaleUpdateResult({this.scale, this.offset});
}

/// Auto Zoom 유틸리티
class CropAutoZoom {
  CropAutoZoom._();

  /// 크롭 윈도우가 화면의 80% 범위를 유지하도록 자동 줌
  /// 크롭 윈도우 중심을 화면 중앙에 맞춤
  static AutoZoomResult autoZoomToCrop({
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double currentScale,
    required Offset currentOffset,
  }) {
    final imageSize = Size(uiImage.width.toDouble(), uiImage.height.toDouble());

    if (cropState.cropRectImage == null) {
      return AutoZoomResult(scale: currentScale, offset: currentOffset);
    }

    final width = containerSize.width;
    final height = containerSize.height;
    final containerCenter = Offset(width / 2, height / 2);

    // ✅ image 좌표 기준으로 한 번만 계산
    // 1) 크롭 중심을 image 좌표에서 직접 가져오기
    final cropCenterImage = cropState.cropRectImage!.center;

    // 2) 현재 scale 기준으로 크롭 크기 계산 (scale 결정용)
    final currentImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: currentScale,
      offset: Offset.zero,
    );

    final currentCropRectScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropState.cropRectImage!,
      screenImageRect: currentImageRect,
      imageSize: imageSize,
    );

    // 3) 크롭 윈도우 크기에 따라 scale 계산
    const maxZoom = 5.0;
    const minRatio = 0.75; // 최소 80% (줌 인 - 리사이즈 후 크롭박스가 화면의 80% 차지)
    const maxRatio = 0.8; // 최대 85% (줌 아웃 기준)

    final cropRatioX = currentCropRectScreen.width / width;
    final cropRatioY = currentCropRectScreen.height / height;
    final cropRatio = cropRatioX < cropRatioY ? cropRatioX : cropRatioY;

    double targetScale = currentScale;

    // 크롭이 너무 작으면 줌 인
    if (cropRatio < minRatio && currentScale < maxZoom) {
      targetScale = (currentScale / cropRatio * minRatio).clamp(1.0, maxZoom);
    }
    // 크롭이 너무 크면 줌 아웃 (단, scale이 1보다 클 때만)
    else if (cropRatio > maxRatio && currentScale > 1.0) {
      targetScale = (currentScale / cropRatio * maxRatio).clamp(1.0, maxZoom);
    }

    // ✅ targetScale 적용 후 실제 이미지 rect가 화면 안에 들어오는지 검증
    double finalTargetScale = targetScale;

    // targetScale로 계산된 이미지 rect 확인
    final testImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: targetScale,
      offset: Offset.zero,
    );

    // 이미지가 화면 안에 들어오는지 확인
    if (testImageRect.left < 0 ||
        testImageRect.top < 0 ||
        testImageRect.right > width ||
        testImageRect.bottom > height) {
      // 이미지가 화면 안에 들어오는 최대 scale 계산
      final imageAspect = imageSize.width / imageSize.height;
      final containerAspect = width / height;

      double maxValidScale;
      if (imageAspect > containerAspect) {
        final baseDisplayHeight = width / imageAspect;
        maxValidScale = height / baseDisplayHeight;
      } else {
        final baseDisplayWidth = height * imageAspect;
        final maxScaleByWidth = width / baseDisplayWidth;

        final cropWidth = cropState.cropRectImage!.width;
        final cropHeight = cropState.cropRectImage!.height;

        final maxScaleByCropWidth =
            (width * imageSize.width) / (cropWidth * height * imageAspect);
        final maxScaleByCropHeight =
            (height * imageSize.height) / (cropHeight * height);

        final maxScaleByCrop =
            maxScaleByCropWidth < maxScaleByCropHeight
                ? maxScaleByCropWidth
                : maxScaleByCropHeight;

        maxValidScale =
            maxScaleByWidth < maxScaleByCrop ? maxScaleByWidth : maxScaleByCrop;
      }

      maxValidScale = maxValidScale > maxZoom ? maxZoom : maxValidScale;

      // 추가로 크롭박스 크기 기준으로도 제한
      final testCropRect = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: testImageRect,
        imageSize: imageSize,
      );

      if (testCropRect.width > width || testCropRect.height > height) {
        final cropWidthRatio = testCropRect.width / width;
        final cropHeightRatio = testCropRect.height / height;
        final cropMaxRatio =
            cropWidthRatio > cropHeightRatio ? cropWidthRatio : cropHeightRatio;
        final maxCropScale = targetScale / cropMaxRatio;
        maxValidScale =
            maxValidScale < maxCropScale ? maxValidScale : maxCropScale;
      }

      finalTargetScale = targetScale.clamp(1.0, maxValidScale);
    }

    targetScale = finalTargetScale;

    // 4) targetScale 적용 후 이미지 rect 계산 (offset=0 기준)
    final imageRectAtTargetScale = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: targetScale,
      offset: Offset.zero,
    );

    // 5) crop 중심을 image 좌표에서 직접 screen 좌표로 변환
    final scaleX = imageRectAtTargetScale.width / imageSize.width;
    final scaleY = imageRectAtTargetScale.height / imageSize.height;

    final cropCenterScreenAtTargetScale = Offset(
      imageRectAtTargetScale.left + cropCenterImage.dx * scaleX,
      imageRectAtTargetScale.top + cropCenterImage.dy * scaleY,
    );

    // 6) offset 계산
    final targetOffset = containerCenter - cropCenterScreenAtTargetScale;

    return AutoZoomResult(scale: targetScale, offset: targetOffset);
  }
}

/// Auto Zoom 결과
class AutoZoomResult {
  final double scale;
  final Offset offset;

  AutoZoomResult({required this.scale, required this.offset});
}
