import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 크롭 바텀시트 패널 타입(대표 버튼 → 펼침 패널)
enum CropEditorPanel { aspect, rotate, flip }

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

  /// ✅ 크롭 + 회전/반전(프리뷰와 동일)까지 한 번에 적용 (PNG)
  ///
  /// - `uiImage`(원본 decode 결과)를 기반으로 캔버스에 렌더링 후,
  /// - 크롭 프레임 영역만 잘라 최종 bytes로 반환한다.
  static Future<Uint8List?> applyCropWithTransform({
    required ui.Image uiImage,
    required CropState cropState,
    required Size containerSize,
    required double scale,
    required Offset offset,
    required int rotationDeg,
    required bool flipHorizontal,
    required bool flipVertical,
  }) async {
    if (!cropState.isCropRectInitialized || cropState.cropRectImage == null) {
      return null;
    }

    final imageSize = Size(uiImage.width.toDouble(), uiImage.height.toDouble());
    final displayImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );

    final cropRectScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropState.cropRectImage!,
      screenImageRect: displayImageRect,
      imageSize: imageSize,
    );

    // screen → image 픽셀 스케일 (캔버스 해상도)
    final scaleX = imageSize.width / displayImageRect.width;
    final scaleY = imageSize.height / displayImageRect.height;

    final outW = (cropRectScreen.width * scaleX).round().clamp(1, 1000000);
    final outH = (cropRectScreen.height * scaleY).round().clamp(1, 1000000);

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // output 픽셀 좌표계로 맞춘다
      canvas.scale(scaleX, scaleY);
      // 프레임의 좌상단을 (0,0)로 이동
      canvas.translate(-cropRectScreen.left, -cropRectScreen.top);

      // 프리뷰와 동일한 변환(Flip -> Rotate, center 기준)
      canvas.save();
      final cx = containerSize.width / 2;
      final cy = containerSize.height / 2;
      canvas.translate(cx, cy);
      final theta = rotationDeg * (3.14159265359 / 180.0);
      if (rotationDeg != 0) {
        canvas.rotate(theta);
      }
      final sx = flipHorizontal ? -1.0 : 1.0;
      final sy = flipVertical ? -1.0 : 1.0;
      if (sx != 1.0 || sy != 1.0) {
        canvas.scale(sx, sy);
      }
      canvas.translate(-cx, -cy);

      final srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      canvas.drawImageRect(uiImage, srcRect, displayImageRect, Paint());
      canvas.restore();

      final picture = recorder.endRecording();
      final outImage = await picture.toImage(outW, outH);
      final bd = await outImage.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      return bd.buffer.asUint8List();
    } catch (e) {
      debugPrint('크롭(통합: 회전/반전 포함) 적용 오류: $e');
      return null;
    }
  }
}

/// iOS 룰러 느낌 회전 슬라이더(크롭 바텀시트에서 재사용)
class RotationRulerSlider extends StatefulWidget {
  const RotationRulerSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.isDragging,
  });

  final int value; // 0-360
  final ValueChanged<int> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final bool isDragging;

  @override
  State<RotationRulerSlider> createState() => _RotationRulerSliderState();
}

class _RotationRulerSliderState extends State<RotationRulerSlider> {
  double? _dragStartX;
  int? _dragStartValue;

  void _onPanStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValue = widget.value;
    widget.onDragStart();
  }

  void _onPanUpdate(DragUpdateDetails details, double width) {
    if (_dragStartX == null || _dragStartValue == null) return;

    final deltaX = details.localPosition.dx - _dragStartX!;
    // 화면에 표시할 범위(중앙 기준 좌우 90도씩, 총 180도)
    final deltaDegree = (deltaX / width) * 180;
    final newValue = (_dragStartValue! + deltaDegree.round()) % 360;
    final normalizedValue = newValue < 0 ? newValue + 360 : newValue;
    widget.onChanged(normalizedValue);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragStartX = null;
    _dragStartValue = null;
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onPanStart,
          onHorizontalDragUpdate:
              (details) => _onPanUpdate(details, constraints.maxWidth),
          onHorizontalDragEnd: _onPanEnd,
          child: SizedBox(
            height: 40,
            child: CustomPaint(
              painter: _RotationRulerPainter(currentValue: widget.value),
              size: Size(constraints.maxWidth, 40),
            ),
          ),
        );
      },
    );
  }
}

class _RotationRulerPainter extends CustomPainter {
  final int currentValue;

  _RotationRulerPainter({required this.currentValue});

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    final majorTickPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.7)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    final centerPaint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final bottomY = size.height - 4;

    const totalTicks = 360;
    const visibleRange = 90.0;
    final pixelsPerDegree = size.width / (visibleRange * 2);

    for (int i = 0; i < totalTicks; i++) {
      final degree = i.toDouble();
      var relative = degree - currentValue.toDouble();
      if (relative > 180) relative -= 360;
      if (relative < -180) relative += 360;
      if (relative.abs() > visibleRange) continue;

      final x = centerX + relative * pixelsPerDegree;
      final isMajor = (i % 10 == 0);
      final isMedium = (i % 5 == 0);

      final tickHeight =
          (relative.abs() < 0.01)
              ? 18.0
              : isMajor
              ? 16.0
              : isMedium
              ? 12.0
              : 8.0;

      final paint =
          (relative.abs() < 0.01)
              ? centerPaint
              : isMajor
              ? majorTickPaint
              : tickPaint;

      canvas.drawLine(
        Offset(x, bottomY - tickHeight),
        Offset(x, bottomY),
        paint,
      );
    }

    // 중앙 아래 삼각형 포인터
    final trianglePaint = Paint()..color = Colors.white;
    final path = Path();
    path.moveTo(centerX, size.height);
    path.lineTo(centerX - 6, size.height - 8);
    path.lineTo(centerX + 6, size.height - 8);
    path.close();
    canvas.drawPath(path, trianglePaint);
  }

  @override
  bool shouldRepaint(_RotationRulerPainter oldDelegate) {
    return oldDelegate.currentValue != currentValue;
  }
}

/// 크롭/회전 통합 바텀시트 콘텐츠(대표 버튼 + 펼침 패널)
class CropEditorBottomSheet extends StatefulWidget {
  const CropEditorBottomSheet({
    super.key,
    required this.initialPanel,
    required this.selectedAspectRatio,
    required this.rotation,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.onSelectAspectRatio,
    required this.onResetAspectRatio,
    required this.onRotationChanged,
    required this.onRotate90,
    required this.onResetRotation,
    required this.onToggleFlipHorizontal,
    required this.onToggleFlipVertical,
    required this.onResetAll,
  });

  final CropEditorPanel initialPanel;
  final String? selectedAspectRatio;
  final int rotation;
  final bool flipHorizontal;
  final bool flipVertical;

  final ValueChanged<String?> onSelectAspectRatio;
  final VoidCallback onResetAspectRatio;

  final ValueChanged<int> onRotationChanged;
  final VoidCallback onRotate90;
  final VoidCallback onResetRotation;

  final VoidCallback onToggleFlipHorizontal;
  final VoidCallback onToggleFlipVertical;

  final VoidCallback onResetAll;

  @override
  State<CropEditorBottomSheet> createState() => _CropEditorBottomSheetState();
}

class _CropEditorBottomSheetState extends State<CropEditorBottomSheet> {
  late CropEditorPanel _panel;
  bool _isRotateDragging = false;

  @override
  void initState() {
    super.initState();
    _panel = widget.initialPanel;
  }

  @override
  void didUpdateWidget(covariant CropEditorBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 외부에서 "처음 열리는 패널"이 바뀌면 동기화
    if (oldWidget.initialPanel != widget.initialPanel) {
      _panel = widget.initialPanel;
      _isRotateDragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget circleButton({
      required Widget child,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.primary : Colors.white.withOpacity(0.3),
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: Center(child: child),
        ),
      );
    }

    Widget aspectPanel() {
      final cropOptions = [
        {'label': '재설정', 'ratio': 'reset', 'icon': Icons.refresh},
        {'label': '자유', 'ratio': null, 'icon': null},
        {'label': '1:1', 'ratio': '1:1', 'icon': null},
        {'label': '4:5', 'ratio': '4:5', 'icon': null},
        {'label': '16:9', 'ratio': '16:9', 'icon': null},
        {'label': '9:16', 'ratio': '9:16', 'icon': null},
      ];

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                cropOptions.map((option) {
                  final ratio = option['ratio'];
                  final isSelected = widget.selectedAspectRatio == ratio;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () {
                        if (ratio == 'reset') {
                          widget.onResetAspectRatio();
                          return;
                        }
                        widget.onSelectAspectRatio(ratio as String?);
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isSelected
                                    ? cs.primary
                                    : Colors.white.withOpacity(0.3),
                            width: isSelected ? 2.5 : 1.5,
                          ),
                        ),
                        child: Center(
                          child:
                              option['icon'] != null
                                  ? Icon(
                                    option['icon'] as IconData,
                                    color:
                                        isSelected ? cs.primary : Colors.white,
                                    size: 26,
                                  )
                                  : Text(
                                    option['label'] as String,
                                    style: TextStyle(
                                      color:
                                          isSelected
                                              ? cs.primary
                                              : Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      );
    }

    Widget rotatePanel() {
      final bubble = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.85),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '${widget.rotation}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRotateDragging)
              Center(child: bubble)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  circleButton(
                    selected: false,
                    onTap: widget.onRotate90,
                    child: const Icon(
                      Icons.rotate_right,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  circleButton(
                    selected: false,
                    onTap: widget.onResetRotation,
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            RotationRulerSlider(
              value: widget.rotation,
              onChanged: widget.onRotationChanged,
              onDragStart: () => setState(() => _isRotateDragging = true),
              onDragEnd: () => setState(() => _isRotateDragging = false),
              isDragging: _isRotateDragging,
            ),
          ],
        ),
      );
    }

    Widget flipPanel() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            circleButton(
              selected: widget.flipHorizontal,
              onTap: widget.onToggleFlipHorizontal,
              child: Icon(
                Icons.flip,
                color: widget.flipHorizontal ? cs.primary : Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            circleButton(
              selected: widget.flipVertical,
              onTap: widget.onToggleFlipVertical,
              child: Icon(
                Icons.flip_camera_ios,
                color: widget.flipVertical ? cs.primary : Colors.white,
                size: 26,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              circleButton(
                selected: _panel == CropEditorPanel.aspect,
                onTap:
                    () => setState(() {
                      _panel = CropEditorPanel.aspect;
                      _isRotateDragging = false;
                    }),
                child: Icon(
                  Icons.aspect_ratio,
                  color:
                      _panel == CropEditorPanel.aspect
                          ? cs.primary
                          : Colors.white,
                  size: 26,
                ),
              ),
              circleButton(
                selected: _panel == CropEditorPanel.rotate,
                onTap:
                    () => setState(() {
                      _panel = CropEditorPanel.rotate;
                      _isRotateDragging = false;
                    }),
                child: Icon(
                  Icons.rotate_right,
                  color:
                      _panel == CropEditorPanel.rotate
                          ? cs.primary
                          : Colors.white,
                  size: 26,
                ),
              ),
              circleButton(
                selected: _panel == CropEditorPanel.flip,
                onTap:
                    () => setState(() {
                      _panel = CropEditorPanel.flip;
                      _isRotateDragging = false;
                    }),
                child: Icon(
                  Icons.flip,
                  color:
                      _panel == CropEditorPanel.flip
                          ? cs.primary
                          : Colors.white,
                  size: 26,
                ),
              ),
              GestureDetector(
                onTap: widget.onResetAll,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_panel),
            child: switch (_panel) {
              CropEditorPanel.aspect => aspectPanel(),
              CropEditorPanel.rotate => rotatePanel(),
              CropEditorPanel.flip => flipPanel(),
            },
          ),
        ),
      ],
    );
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
  Offset? _lastPanPosition;
  CropHandleType? _activeCropHandle;

  // 핀치 줌 상태
  double? _initialScale; // 핀치 시작 시 초기 scale
  bool _isPinching = false;

  // 드래그 감도 및 복귀 감도
  static const double _dragResistance = 0.6;
  static const double _snapBackStrength = 1.5;
  static const double _minImageScale = 1.0; // 최소 줌 레벨 (축소 제한)
  static const double _maxImageScale = 5.0; // 최대 줌 레벨
  static const double _pinchEpsilon = 0.001; // 핀치로 판단할 최소 scale 변화량
  static const double _snapTolerancePx = 0.5; // 스냅백/커버 판정 픽셀 오차 허용치
  static const double _edgeToleranceImagePx = 0.1; // 이미지 좌표 경계 판정 여유값

  /// snapBackOffset이 있으면 반영한 최종 offset을 반환한다.
  Offset _applySnapBackOffset(Offset imageOffset, Offset? snapBackOffset) {
    return snapBackOffset != null
        ? (imageOffset + snapBackOffset)
        : imageOffset;
  }

  /// freeze(렌더 기준)로 고정된 screen cropRect를, 특정 screenImageRect 기준의 image 좌표로 1회 재투영한다.
  /// - cropRectImage는 image 좌표가 단일 진실이므로, 여기서만 갱신한다.
  /// - 결과는 항상 이미지 경계 내로 clamp 된다.
  Rect? _projectScreenRectToImageRect({
    required Rect screenCropRect,
    required Rect screenImageRect,
    required Size imageSize,
  }) {
    final sx = screenImageRect.width / imageSize.width;
    final sy = screenImageRect.height / imageSize.height;
    if (sx <= 0 || sy <= 0) return null;

    final projectedLeft = (screenCropRect.left - screenImageRect.left) / sx;
    final projectedTop = (screenCropRect.top - screenImageRect.top) / sy;
    final projectedWidth = screenCropRect.width / sx;
    final projectedHeight = screenCropRect.height / sy;

    final clampedLeft = projectedLeft.clamp(0.0, imageSize.width);
    final clampedTop = projectedTop.clamp(0.0, imageSize.height);
    final clampedWidth = projectedWidth.clamp(
      0.0,
      imageSize.width - clampedLeft,
    );
    final clampedHeight = projectedHeight.clamp(
      0.0,
      imageSize.height - clampedTop,
    );

    return Rect.fromLTWH(clampedLeft, clampedTop, clampedWidth, clampedHeight);
  }

  /// 제스처 종료 후 공통 상태 리셋
  void _resetGestureState({required bool clearFrozen}) {
    _isDraggingImage = false;
    if (clearFrozen) _frozenImageRect = null;
    _initialScale = null;
    _isPinching = false;
  }

  /// 현재 이미지가 screenCropRect(=고정된 크롭 박스)를 완전히 덮지 못하면,
  /// 그 차이를 기준으로 snapBackOffset을 계산한다.
  ///
  /// - snap 판정은 `_snapTolerancePx`를 반영해 경계 픽셀 오차로 인한 과도한 스냅을 줄인다.
  Offset? _computeSnapBackOffset({
    required Rect currentImageRect,
    required Rect screenCropRect,
    required double imageScale,
  }) {
    double adjustX = 0.0;
    double adjustY = 0.0;

    // 좌/우
    if (currentImageRect.left > screenCropRect.left + _snapTolerancePx) {
      adjustX = screenCropRect.left - currentImageRect.left;
    } else if (currentImageRect.right <
        screenCropRect.right - _snapTolerancePx) {
      adjustX = screenCropRect.right - currentImageRect.right;
    }

    // 상/하
    if (currentImageRect.top > screenCropRect.top + _snapTolerancePx) {
      adjustY = screenCropRect.top - currentImageRect.top;
    } else if (currentImageRect.bottom <
        screenCropRect.bottom - _snapTolerancePx) {
      adjustY = screenCropRect.bottom - currentImageRect.bottom;
    }

    if (adjustX == 0.0 && adjustY == 0.0) return null;

    return Offset(
      (adjustX / imageScale) * _snapBackStrength,
      (adjustY / imageScale) * _snapBackStrength,
    );
  }

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

      // ✅ 드래그/핀치 시작 시 imageRect만 freeze (렌더 기준/복귀 기준)
      // cropRectScreen은 cropRectImage(진실) + frozenImageRect(기준)으로 항상 계산 가능하므로
      // 파생값을 상태로 들고 있지 않는다.
      _frozenImageRect = currentImageRect;
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
    if ((details.scale - 1.0).abs() >= _pinchEpsilon) {
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
        // 🎯 중요: 축소 허용/차단 판정 기준을 "사용자가 실제로 보는 크롭 박스"로 통일한다.
        // - 핀치 중 UX는 cropRectScreen이 화면에 고정(frozen 기준)되어야 함
        // - 그런데 여기서 testImageRect 기준으로 cropRectScreen을 계산하면(=박스가 이미지에 종속),
        //   축소를 과하게 허용하게 되고, 종료 시점에 frozen 기준 스냅백이 과하게 걸릴 수 있다.
        //
        // 따라서 zoom-out(축소) 중에는 "frozen 기준 cropRectScreen"을 기준으로
        // 이미지가 그 박스를 계속 덮는지 검사한다.
        //
        // 경계 픽셀 오차로 인한 불필요 차단/스냅백 방지를 위해 tolerance를 둔다.
        // 핀치 시작 시점에 freeze된 imageRect가 없으면(예외 케이스) 기존 방식으로 폴백
        final Rect? frozenCropRectScreen =
            (_frozenImageRect != null)
                ? ImageRectUtils.imageToScreenRect(
                  imageRect: cropState.cropRectImage!,
                  screenImageRect: _frozenImageRect!,
                  imageSize: imageSize,
                )
                : null;

        final testImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: newScale,
          offset: imageOffset,
        );

        final testCropRectScreen =
            frozenCropRectScreen ??
            ImageRectUtils.imageToScreenRect(
              imageRect: cropState.cropRectImage!,
              screenImageRect: testImageRect,
              imageSize: imageSize,
            );

        // ✅ 이미지가 cropRect를 완전히 덮지 못하면 축소 금지
        if (testImageRect.left > testCropRectScreen.left + _snapTolerancePx ||
            testImageRect.top > testCropRectScreen.top + _snapTolerancePx ||
            testImageRect.right < testCropRectScreen.right - _snapTolerancePx ||
            testImageRect.bottom <
                testCropRectScreen.bottom - _snapTolerancePx) {
          // 축소 금지: 현재 scale 유지
          return null;
        }
      }

      // 최소 scale 제한
      if (newScale < _minImageScale) {
        return null;
      }

      // 최대 scale 제한
      newScale = newScale.clamp(_minImageScale, _maxImageScale);

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
      final cropRect = cropState.cropRectImage!;

      // 왼쪽으로 드래그하려고 하는데 왼쪽 경계에 붙어있으면 막기
      if (delta.dx < 0 && cropRect.left <= _edgeToleranceImagePx) {
        return null;
      }
      // 오른쪽으로 드래그하려고 하는데 오른쪽 경계에 붙어있으면 막기
      if (delta.dx > 0 &&
          cropRect.right >= imageSize.width - _edgeToleranceImagePx) {
        return null;
      }
      // 위로 드래그하려고 하는데 위쪽 경계에 붙어있으면 막기
      if (delta.dy < 0 && cropRect.top <= _edgeToleranceImagePx) {
        return null;
      }
      // 아래로 드래그하려고 하는데 아래쪽 경계에 붙어있으면 막기
      if (delta.dy > 0 &&
          cropRect.bottom >= imageSize.height - _edgeToleranceImagePx) {
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
      _resetGestureState(clearFrozen: true);
      return null;
    }

    // ✅ 핀치 줌이 끝났을 때 처리
    if (_isPinching) {
      return _handlePinchEnd(
        cropState: cropState,
        uiImage: uiImage,
        containerSize: containerSize,
        imageScale: imageScale,
        imageOffset: imageOffset,
      );
    }

    return _handleDragEnd(
      cropState: cropState,
      uiImage: uiImage,
      containerSize: containerSize,
      imageScale: imageScale,
      imageOffset: imageOffset,
    );
  }

  // ----------------------------
  // onScaleEnd 내부 책임 분리
  // ----------------------------
  CropDragEndResult? _handlePinchEnd({
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    // scale이 최소값보다 작으면 복귀
    if (imageScale < _minImageScale) {
      _resetGestureState(clearFrozen: true);

      // scale을 최소값으로 복귀
      return CropDragEndResult(
        snapBackOffset: null,
        cropRectImagePosition: null,
        cropRectImageSize: null,
        snapBackScale: _minImageScale, // 복귀할 scale 값
      );
    }

    // ✅ 핀치 줌 후: 확대/축소 구분하여 처리
    final imageSize = Size(uiImage.width.toDouble(), uiImage.height.toDouble());

    // 현재 scale 기준으로 이미지 rect 계산
    final currentImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: imageScale,
      offset: imageOffset,
    );

    // 화면에서 크롭박스 위치는 고정 (frozenImageRect 기준으로 즉시 계산)
    if (_frozenImageRect != null && _initialScale != null) {
      final frozenCropRectScreen = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: _frozenImageRect!,
        imageSize: imageSize,
      );
      // ✅ 확대/축소 판단: 초기 scale과 현재 scale 비교
      final isZoomIn = imageScale > _initialScale!; // 확대
      final isZoomOut = imageScale < _initialScale!; // 축소

      final snapBackOffset = _computeSnapBackOffset(
        currentImageRect: currentImageRect,
        screenCropRect: frozenCropRectScreen,
        imageScale: imageScale,
      );

      // ✅ 확대 핀치: cropRectImage 절대 재계산하지 않음 (고정)
      if (isZoomIn) {
        // ✅ zoom-in 종료의 정석화:
        // - zoom-in 중에는 cropRectScreen을 frozen 기준으로 고정 렌더(이미지 확대만 보이게)
        // - zoom-in 종료 시점에 한 번만 "고정된 screen cropRect"를 최종 imageRect 기준으로
        //   screen→image 재투영해서 cropRectImage(단일 진실)를 갱신한다.
        // - 그 후 freeze를 해제해도 cropRectScreen이 유지된다.

        // 스냅백이 적용된 최종 offset 기준으로 imageRect를 계산해야, 재투영이 일관된다.
        final finalOffset = _applySnapBackOffset(imageOffset, snapBackOffset);
        final finalImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: imageScale,
          offset: finalOffset,
        );

        final projected = _projectScreenRectToImageRect(
          screenCropRect: frozenCropRectScreen,
          screenImageRect: finalImageRect,
          imageSize: imageSize,
        );
        if (projected == null) {
          _resetGestureState(clearFrozen: true);
          return CropDragEndResult(
            snapBackOffset: snapBackOffset,
            cropRectImagePosition: null,
            cropRectImageSize: null,
            snapBackScale: null,
          );
        }

        // zoom-in 종료 후에는 freeze 해제 (이제 cropRectImage가 최종 기준에 맞게 재투영됨)
        _resetGestureState(clearFrozen: true);

        return CropDragEndResult(
          snapBackOffset: snapBackOffset,
          cropRectImagePosition: projected.topLeft,
          cropRectImageSize: projected.size,
          snapBackScale: null,
        );
      }

      // ✅ 축소 핀치: zoom-in과 동일하게 "재투영 1회"로 정석화한다.
      // - 축소 중에도 크롭 박스(screen)는 고정되어야 함
      // - 종료 시점에 한 번만 고정된 screen cropRect를 최종 imageRect 기준으로 image 좌표로 투영
      // - 이후 freeze를 해제해도 screen 크롭박스가 유지됨
      if (isZoomOut) {
        final finalOffset = _applySnapBackOffset(imageOffset, snapBackOffset);
        final finalImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: imageScale,
          offset: finalOffset,
        );
        final projected = _projectScreenRectToImageRect(
          screenCropRect: frozenCropRectScreen,
          screenImageRect: finalImageRect,
          imageSize: imageSize,
        );
        if (projected == null) {
          _resetGestureState(clearFrozen: true);
          return CropDragEndResult(
            snapBackOffset: snapBackOffset,
            cropRectImagePosition: null,
            cropRectImageSize: null,
            snapBackScale: null,
          );
        }

        _resetGestureState(clearFrozen: true);

        return CropDragEndResult(
          snapBackOffset: snapBackOffset,
          cropRectImagePosition: projected.topLeft,
          cropRectImageSize: projected.size,
          snapBackScale: null,
        );
      }
    }

    _resetGestureState(clearFrozen: true);
    return null;
  }

  CropDragEndResult? _handleDragEnd({
    required CropState cropState,
    required ui.Image uiImage,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    // ✅ 드래그 완료 시: 고정된 기준으로 크롭박스 밖으로 나갔는지 확인 후 복귀
    if (cropState.isCropRectInitialized &&
        _isDraggingImage &&
        _frozenImageRect != null) {
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

      // ✅ 고정된 기준(frozenImageRect)으로 “화면 크롭박스”를 즉시 계산해 벗어남 확인
      final frozenCropRectScreen = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: _frozenImageRect!,
        imageSize: imageSize,
      );
      final snapBackOffset = _computeSnapBackOffset(
        currentImageRect: currentImageRect,
        screenCropRect: frozenCropRectScreen,
        imageScale: imageScale,
      );

      // ✅ 드래그 완료 시: 화면 중앙 기준으로 cropRectImage 재계산
      final finalOffset = _applySnapBackOffset(imageOffset, snapBackOffset);
      final finalImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: imageScale,
        offset: finalOffset,
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
      _initialScale = null;
      _isPinching = false;

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

  /// 리셋
  void reset() {
    _isDraggingImage = false;
    _frozenImageRect = null;
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
