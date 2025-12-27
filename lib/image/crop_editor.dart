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
  }) {
    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = containerSize.width / containerSize.height;

    // 기본 표시 크기 계산 (scale 1.0 기준)
    double baseDisplayWidth, baseDisplayHeight;
    double baseImageOffsetX = 0, baseImageOffsetY = 0;

    if (imageAspect > containerAspect) {
      baseDisplayWidth = containerSize.width;
      baseDisplayHeight = containerSize.width / imageAspect;
      baseImageOffsetY = (containerSize.height - baseDisplayHeight) / 2;
    } else {
      baseDisplayHeight = containerSize.height;
      baseDisplayWidth = containerSize.height * imageAspect;
      baseImageOffsetX = (containerSize.width - baseDisplayWidth) / 2;
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

/// ❌ CropEditor 제거됨 - 크롭 이동은 금지, 이미지만 이동 가능

/// ❌ _CornerHandlePainter 제거됨 - CropEditor에서만 사용되었음

/// 크롭 유틸리티 클래스
class CropUtils {
  CropUtils._();

  /// 크롭 영역 초기화 (크롭 시작 시 1회만 호출)
  /// 🎯 이미지 좌표 기준으로 초기화
  static void initializeCropRect({
    required ui.Image image,
    required Size containerSize,
    required CropState cropState,
    required ValueChanged<Size> onDisplaySizeChanged,
    double scale = 1.0,
    Offset offset = Offset.zero,
  }) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: 1.0,
      offset: Offset.zero,
    );

    onDisplaySizeChanged(Size(imageRect.width, imageRect.height));

    // 🎯 이미지 좌표 기준으로 크롭 영역 초기화
    final aspectRatio = _parseAspectRatio(cropState.selectedAspectRatio);
    double cropWidth, cropHeight;

    if (aspectRatio != null) {
      if (aspectRatio > imageSize.width / imageSize.height) {
        cropWidth = imageSize.width;
        cropHeight = cropWidth / aspectRatio;
      } else {
        cropHeight = imageSize.height;
        cropWidth = cropHeight * aspectRatio;
      }
    } else {
      cropWidth = imageSize.width;
      cropHeight = imageSize.height;
    }

    // 크롭 박스가 이미지 경계를 벗어나지 않도록 제한
    cropWidth = cropWidth.clamp(0.0, imageSize.width);
    cropHeight = cropHeight.clamp(0.0, imageSize.height);

    // 중심점 계산 (이미지 경계 내에 있도록)
    final centerX = imageSize.width / 2;
    final centerY = imageSize.height / 2;

    // 크롭 박스 위치 계산 (이미지 좌표 기준)
    final cropLeft = (centerX - cropWidth / 2).clamp(
      0.0,
      imageSize.width - cropWidth,
    );
    final cropTop = (centerY - cropHeight / 2).clamp(
      0.0,
      imageSize.height - cropHeight,
    );

    // 🎯 cropRectImage 설정 (이미지 좌표, 단일 진실)
    cropState.cropRectImage = Rect.fromLTWH(
      cropLeft,
      cropTop,
      cropWidth,
      cropHeight,
    );

    cropState.isCropRectInitialized = true;
  }

  /// 비율 파싱
  static double? _parseAspectRatio(String? ratio) {
    if (ratio == null || ratio == 'original') return null;
    switch (ratio) {
      case '1:1':
        return 1.0;
      case '4:5':
        return 4 / 5;
      case '16:9':
        return 16 / 9;
      case '9:16':
        return 9 / 16;
      case '3:4':
        return 3 / 4;
      case '4:3':
        return 4 / 3;
      default:
        return null;
    }
  }

  /// 크롭 적용
  /// pixel cropRect → normalized → 실제 이미지 좌표 변환
  static Future<Uint8List?> applyCrop({
    required Uint8List imageBytes,
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    double scale = 1.0,
    Offset offset = Offset.zero,
    int rotation = 0,
  }) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      // 회전 적용
      img.Image processed = decoded;
      if (rotation != 0) {
        processed = img.copyRotate(decoded, angle: rotation.toDouble());
      }

      // 🎯 이미지 좌표계 cropRect 사용 (AutoZoom 후에도 동일한 이미지 영역 유지)
      if (cropState.cropRectImage != null) {
        // 이미지 좌표계 cropRect를 직접 사용
        final imageCrop = cropState.cropRectImage!;
        final imageSize = Size(
          uiImage.width.toDouble(),
          uiImage.height.toDouble(),
        );

        // 이미지 좌표를 정규화된 좌표로 변환
        cropState.normalizedLeft = (imageCrop.left / imageSize.width).clamp(
          0.0,
          1.0,
        );
        cropState.normalizedTop = (imageCrop.top / imageSize.height).clamp(
          0.0,
          1.0,
        );
        cropState.normalizedWidth = (imageCrop.width / imageSize.width).clamp(
          0.0,
          1.0,
        );
        cropState.normalizedHeight = (imageCrop.height / imageSize.height)
            .clamp(0.0, 1.0);
      } else {
        // fallback: normalized 값 사용 (저장/복원용)
        // normalized는 이미 올바른 값이어야 함
      }

      // normalized를 실제 이미지 좌표로 변환
      final imageSize = Size(
        processed.width.toDouble(),
        processed.height.toDouble(),
      );

      final cropX =
          (cropState.normalizedLeft * imageSize.width)
              .clamp(0.0, imageSize.width)
              .toInt();
      final cropY =
          (cropState.normalizedTop * imageSize.height)
              .clamp(0.0, imageSize.height)
              .toInt();
      final cropWidth =
          (cropState.normalizedWidth * imageSize.width)
              .clamp(0.0, (imageSize.width - cropX).toDouble())
              .toInt();
      final cropHeight =
          (cropState.normalizedHeight * imageSize.height)
              .clamp(0.0, (imageSize.height - cropY).toDouble())
              .toInt();

      // 크롭 적용
      final cropped = img.copyCrop(
        processed,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );

      // JPG로 인코딩
      return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
    } catch (e) {
      debugPrint('크롭 에러: $e');
      return null;
    }
  }

  /// 핸들 위치에서 핸들 타입 찾기
  static CropHandleType? getHandleAtPosition(Offset pos, Rect cropRect) {
    const handleSize = 30.0;
    const handleRadius = handleSize / 2;

    final handles = [
      (CropHandleType.topLeft, cropRect.topLeft),
      (CropHandleType.topRight, cropRect.topRight),
      (CropHandleType.bottomLeft, cropRect.bottomLeft),
      (CropHandleType.bottomRight, cropRect.bottomRight),
      (CropHandleType.top, Offset(cropRect.center.dx, cropRect.top)),
      (CropHandleType.bottom, Offset(cropRect.center.dx, cropRect.bottom)),
      (CropHandleType.left, Offset(cropRect.left, cropRect.center.dy)),
      (CropHandleType.right, Offset(cropRect.right, cropRect.center.dy)),
    ];

    for (final (type, position) in handles) {
      if ((pos - position).distance < handleRadius) {
        return type;
      }
    }
    return null;
  }
}

/// 이미지 전용 Painter (transform 적용)
/// ❗ 크롭 관련 코드는 모두 제거 - 레이어 분리
class ImagePainter extends CustomPainter {
  final ui.Image image;
  final Offset imageOffset;
  final double imageScale;

  ImagePainter(
    this.image, {
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // ✅ computeImageRect를 "유일한 진실"로 사용
    // canvas transform을 사용하지 않고, computeImageRect가 계산한 rect를 직접 사용
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: size,
      imageSize: imageSize,
      scale: imageScale,
      offset: imageOffset,
    );

    // 이미지 그리기 (transform 없이 직접 rect 사용)
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(ImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.imageOffset != imageOffset ||
        oldDelegate.imageScale != imageScale;
  }
}

/// 크롭 오버레이 전용 Painter (transform 미적용 - screen 좌표로 직접 그림)
/// ❗ 절대 canvas transform 사용 금지
class CropOverlayPainter extends CustomPainter {
  final Rect cropRectScreen;
  final Rect imageRect;

  CropOverlayPainter({required this.cropRectScreen, required this.imageRect});

  @override
  void paint(Canvas canvas, Size size) {
    // 이미지 영역과 겹치는지 확인
    if (!imageRect.overlaps(cropRectScreen)) {
      return;
    }

    // 어두운 오버레이 (크롭 영역 외부)
    final overlayPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.fill;

    // 상단
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, cropRectScreen.top),
      overlayPaint,
    );
    // 하단
    canvas.drawRect(
      Rect.fromLTRB(0, cropRectScreen.bottom, size.width, size.height),
      overlayPaint,
    );
    // 좌측
    canvas.drawRect(
      Rect.fromLTRB(
        0,
        cropRectScreen.top,
        cropRectScreen.left,
        cropRectScreen.bottom,
      ),
      overlayPaint,
    );
    // 우측
    canvas.drawRect(
      Rect.fromLTRB(
        cropRectScreen.right,
        cropRectScreen.top,
        size.width,
        cropRectScreen.bottom,
      ),
      overlayPaint,
    );

    // 크롭 박스 테두리
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    canvas.drawRect(cropRectScreen, borderPaint);

    // 격자선 (3x3)
    final gridPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

    // 세로선 2개
    canvas.drawLine(
      Offset(
        cropRectScreen.left + cropRectScreen.width / 3,
        cropRectScreen.top,
      ),
      Offset(
        cropRectScreen.left + cropRectScreen.width / 3,
        cropRectScreen.bottom,
      ),
      gridPaint,
    );
    canvas.drawLine(
      Offset(
        cropRectScreen.left + cropRectScreen.width * 2 / 3,
        cropRectScreen.top,
      ),
      Offset(
        cropRectScreen.left + cropRectScreen.width * 2 / 3,
        cropRectScreen.bottom,
      ),
      gridPaint,
    );

    // 가로선 2개
    canvas.drawLine(
      Offset(
        cropRectScreen.left,
        cropRectScreen.top + cropRectScreen.height / 3,
      ),
      Offset(
        cropRectScreen.right,
        cropRectScreen.top + cropRectScreen.height / 3,
      ),
      gridPaint,
    );
    canvas.drawLine(
      Offset(
        cropRectScreen.left,
        cropRectScreen.top + cropRectScreen.height * 2 / 3,
      ),
      Offset(
        cropRectScreen.right,
        cropRectScreen.top + cropRectScreen.height * 2 / 3,
      ),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRectScreen != cropRectScreen ||
        oldDelegate.imageRect != imageRect;
  }
}

/// 각진 크롭 핸들 Painter
class CropCornerHandlePainter extends CustomPainter {
  final CropHandleType type;
  final double handleLength;
  final double handleThickness;
  final Color handleColor;

  CropCornerHandlePainter({
    required this.type,
    required this.handleLength,
    required this.handleThickness,
    this.handleColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = handleColor
          ..strokeWidth = handleThickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.square;

    final bracketLength = handleLength;
    // 테두리 안쪽으로 더 넣기 (테두리 두께 + 여유 공간)
    // ImageWithCropPainter의 borderPaint strokeWidth = 2.0
    const borderWidth = 2.0;
    const extraInset = 14.0; // 추가 여유 공간
    final inset = borderWidth + extraInset;

    switch (type) {
      case CropHandleType.topLeft:
        canvas.drawLine(
          Offset(inset, inset),
          Offset(inset + bracketLength, inset),
          paint,
        );
        canvas.drawLine(
          Offset(inset, inset),
          Offset(inset, inset + bracketLength),
          paint,
        );
        break;
      case CropHandleType.topRight:
        canvas.drawLine(
          Offset(size.width - inset - bracketLength, inset),
          Offset(size.width - inset, inset),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - inset, inset),
          Offset(size.width - inset, inset + bracketLength),
          paint,
        );
        break;
      case CropHandleType.bottomLeft:
        canvas.drawLine(
          Offset(inset, size.height - inset - bracketLength),
          Offset(inset, size.height - inset),
          paint,
        );
        canvas.drawLine(
          Offset(inset, size.height - inset),
          Offset(inset + bracketLength, size.height - inset),
          paint,
        );
        break;
      case CropHandleType.bottomRight:
        canvas.drawLine(
          Offset(size.width - inset - bracketLength, size.height - inset),
          Offset(size.width - inset, size.height - inset),
          paint,
        );
        canvas.drawLine(
          Offset(size.width - inset, size.height - inset - bracketLength),
          Offset(size.width - inset, size.height - inset),
          paint,
        );
        break;
      case CropHandleType.top:
        // 위쪽 중간 - 테두리 라인 위에 정확히 위치 (inset 없음)
        final center = Offset(size.width / 2, inset);
        final halfLength = handleLength / 2;
        canvas.drawLine(
          Offset(center.dx - halfLength, center.dy),
          Offset(center.dx + halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.bottom:
        // 아래쪽 중간 - 테두리 라인 위에 정확히 위치 (inset 없음)
        final centerBottom = Offset(size.width / 2, size.height - inset);
        final halfLengthBottom = handleLength / 2;
        canvas.drawLine(
          Offset(centerBottom.dx - halfLengthBottom, centerBottom.dy),
          Offset(centerBottom.dx + halfLengthBottom, centerBottom.dy),
          paint,
        );
        break;
      case CropHandleType.left:
        // 왼쪽 중간 - inset만큼 안쪽에 위치
        final centerLeft = Offset(inset, size.height / 2);
        final halfLengthLeft = handleLength / 2;
        canvas.drawLine(
          Offset(centerLeft.dx, centerLeft.dy - halfLengthLeft),
          Offset(centerLeft.dx, centerLeft.dy + halfLengthLeft),
          paint,
        );
        break;
      case CropHandleType.right:
        // 오른쪽 중간 - inset만큼 안쪽에 위치
        final centerRight = Offset(size.width - inset, size.height / 2);
        final halfLengthRight = handleLength / 2;
        canvas.drawLine(
          Offset(centerRight.dx, centerRight.dy - halfLengthRight),
          Offset(centerRight.dx, centerRight.dy + halfLengthRight),
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

    Rect newRect = cropState.cropRectImage!;

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

    final aspectRatio = CropGestureUtils.parseAspectRatio(
      cropState.selectedAspectRatio,
    );
    final isAspectRatioLocked = aspectRatio != null;

    if (isAspectRatioLocked) {
      return const SizedBox.shrink();
    }

    // ✅ 핸들은 크롭박스 좌표를 기준으로 직접 배치 (clamp 없이)
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
    final handleSize = isActive ? 40.0 : 30.0;
    final touchSize = 44.0;

    return Positioned(
      left: widget.position.dx - touchSize / 2,
      top: widget.position.dy - touchSize / 2,
      child: GestureDetector(
        onPanStart: (details) {
          widget.onHandleChanged(widget.type);
          setState(() {
            _panStart = details.globalPosition;
          });
        },
        onPanUpdate: (details) {
          if (_panStart == null) return;
          final delta = details.globalPosition - _panStart!;
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
            _panStart = details.globalPosition;
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
    final handleThickness = isActive ? 5.0 : 4.0;
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
