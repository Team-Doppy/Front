import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 이미지 표시 rect 계산 유틸리티 (단일 소스)
/// 모든 곳에서 동일한 계산 로직 사용
class ImageRectUtils {
  ImageRectUtils._();

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
/// pro_image_editor 구조: imageBounds는 스냅샷, cropRect는 pixel 단일 소스
class CropState {
  String? selectedAspectRatio; // null = 자유, '1:1', '4:5', '16:9' 등
  Rect cropRect = Rect.zero; // 크롭 영역 (화면 좌표) - 유일한 조작 대상
  Rect? fixedImageBounds; // 이미지 bounds 스냅샷 (크롭 시작 시 1회만 설정, 이후 고정)
  // 정규화된 크롭 좌표 (0~1 범위) - 저장/applyCrop 전용, 실시간 기준 아님
  double normalizedLeft = 0.0;
  double normalizedTop = 0.0;
  double normalizedWidth = 1.0;
  double normalizedHeight = 1.0;
  bool isCropRectInitialized = false;
  int rotation = 0; // 회전 각도

  void reset() {
    selectedAspectRatio = null;
    cropRect = Rect.zero;
    fixedImageBounds = null;
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

/// 크롭 에디터 위젯
class CropEditor extends StatefulWidget {
  const CropEditor({
    super.key,
    required this.cropState,
    required this.imageSize,
    required this.containerSize,
    required this.onCropRectChanged,
    this.activeHandle,
  });

  final CropState cropState;
  final Size imageSize;
  final Size containerSize;
  final ValueChanged<Rect> onCropRectChanged;
  final CropHandleType? activeHandle;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  CropHandleType? _activeHandle;
  Offset _panStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    // ❌ initState에서는 fixedImageBounds 설정하지 않음
    // initializeCropRect에서만 담당
  }

  @override
  Widget build(BuildContext context) {
    // ❌ build() = pure render만, 상태 변경 절대 금지
    // fixedImageBounds가 없으면 아무것도 그리지 않음
    final fixedBounds = widget.cropState.fixedImageBounds;
    if (fixedBounds == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      // 크롭 영역 내부 드래그로 이동
      onPanStart: (details) {
        final cropRect = widget.cropState.cropRect;
        final pos = details.localPosition;
        // 핸들 영역이 아닌 경우에만 이동
        if (!_isHandleArea(pos, cropRect)) {
          setState(() {
            _panStart = details.globalPosition;
          });
        }
      },
      onPanUpdate: (details) {
        final cropRect = widget.cropState.cropRect;
        final pos = details.localPosition;
        // 핸들이 활성화되지 않았고, 크롭 영역 내부인 경우 이동
        if (_activeHandle == null && cropRect.contains(pos)) {
          final delta = details.globalPosition - _panStart;
          _moveCropRect(delta);
          _panStart = details.globalPosition;
        }
      },
      onPanEnd: (_) {
        setState(() {
          _panStart = Offset.zero;
        });
      },
      // 더블 탭으로 리셋
      onDoubleTap: () {
        _resetCropRect();
      },
      child: ClipRect(
        clipper: _ImageRectClipper(fixedBounds),
        child: CustomPaint(
          painter: _CropOverlayPainter(
            cropRect: widget.cropState.cropRect,
            activeHandle: widget.activeHandle ?? _activeHandle,
          ),
          size: widget.containerSize,
          child: _buildCropHandles(),
        ),
      ),
    );
  }

  bool _isHandleArea(Offset pos, Rect cropRect) {
    const handleTouchRadius = 30.0; // 감지 영역 확대
    final handles = [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
      Offset(cropRect.center.dx, cropRect.top),
      Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.left, cropRect.center.dy),
      Offset(cropRect.right, cropRect.center.dy),
    ];

    for (final handlePos in handles) {
      if ((pos - handlePos).distance < handleTouchRadius) {
        return true;
      }
    }
    return false;
  }

  void _moveCropRect(Offset delta) {
    final state = widget.cropState;
    final fixedBounds = state.fixedImageBounds;
    if (fixedBounds == null) return;

    // pro_image_editor 방식: 단순 clamp
    final dx = (delta.dx).clamp(
      fixedBounds.left - state.cropRect.left,
      fixedBounds.right - state.cropRect.right,
    );
    final dy = (delta.dy).clamp(
      fixedBounds.top - state.cropRect.top,
      fixedBounds.bottom - state.cropRect.bottom,
    );

    // 이동: 위치만 조정, 크기 절대 변경 없음
    final newRect = state.cropRect.shift(Offset(dx, dy));

    // cropRect 업데이트 (pixel 단일 소스)
    state.cropRect = newRect;
    widget.onCropRectChanged(newRect);
    setState(() {});
  }

  void _resetCropRect() {
    final fixedBounds = widget.cropState.fixedImageBounds;
    if (fixedBounds == null) return;

    // 크롭 영역을 이미지 전체로 리셋
    widget.cropState.cropRect = fixedBounds;
    widget.cropState.normalizedLeft = 0.0;
    widget.cropState.normalizedTop = 0.0;
    widget.cropState.normalizedWidth = 1.0;
    widget.cropState.normalizedHeight = 1.0;
    widget.onCropRectChanged(fixedBounds);

    setState(() {});
  }

  Widget _buildCropHandles() {
    final cropRect = widget.cropState.cropRect;
    final fixedBounds = widget.cropState.fixedImageBounds;
    final aspectRatio = _parseAspectRatio(widget.cropState.selectedAspectRatio);
    final isAspectRatioLocked = aspectRatio != null;

    // 비율 고정 시 핸들 숨김 (이동만 가능)
    if (isAspectRatioLocked || fixedBounds == null) {
      return const SizedBox.shrink();
    }

    // 🎯 핸들 위치를 fixedBounds 내로 clamp (핸들이 이미지 밖에 그려지지 않도록)
    clampHandle(Offset pos) {
      return Offset(
        pos.dx.clamp(fixedBounds.left, fixedBounds.right),
        pos.dy.clamp(fixedBounds.top, fixedBounds.bottom),
      );
    }

    // 자유 비율일 때만 모든 핸들 표시
    return Stack(
      children: [
        // 모서리 핸들 (경계 내로 clamp)
        _buildHandle(
          clampHandle(cropRect.topLeft),
          CropHandleType.topLeft,
          false,
        ),
        _buildHandle(
          clampHandle(cropRect.topRight),
          CropHandleType.topRight,
          false,
        ),
        _buildHandle(
          clampHandle(cropRect.bottomLeft),
          CropHandleType.bottomLeft,
          false,
        ),
        _buildHandle(
          clampHandle(cropRect.bottomRight),
          CropHandleType.bottomRight,
          false,
        ),
        // 중간 핸들 (경계 내로 clamp)
        _buildHandle(
          clampHandle(Offset(cropRect.center.dx, cropRect.top)),
          CropHandleType.top,
          false,
        ),
        _buildHandle(
          clampHandle(Offset(cropRect.center.dx, cropRect.bottom)),
          CropHandleType.bottom,
          false,
        ),
        _buildHandle(
          clampHandle(Offset(cropRect.left, cropRect.center.dy)),
          CropHandleType.left,
          false,
        ),
        _buildHandle(
          clampHandle(Offset(cropRect.right, cropRect.center.dy)),
          CropHandleType.right,
          false,
        ),
      ],
    );
  }

  Widget _buildHandle(
    Offset position,
    CropHandleType type,
    bool isAspectRatioLocked,
  ) {
    final isActive = _activeHandle == type;
    final handleSize = isActive ? 40.0 : 30.0; // 활성화 시 크기 증가
    final touchSize = 44.0; // 터치 영역 확대

    return Positioned(
      left: position.dx - touchSize / 2,
      top: position.dy - touchSize / 2,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _activeHandle = type;
            _panStart = details.globalPosition;
          });
        },
        onPanUpdate: (details) {
          final delta = details.globalPosition - _panStart;
          _updateCropRect(type, delta);
          _panStart = details.globalPosition;
        },
        onPanEnd: (_) {
          setState(() {
            _activeHandle = null;
          });
          // 크롭 영역 조정 종료 시 자동 정렬 (pro_image_editor 로직)
          // _onCropResizeEnd();
        },
        child: Center(child: _buildCornerHandle(type, handleSize, isActive)),
      ),
    );
  }

  Widget _buildCornerHandle(
    CropHandleType type,
    double handleSize,
    bool isActive,
  ) {
    final handleThickness = isActive ? 5.0 : 4.0; // 활성화 시 두께 증가
    final handleLength = handleSize * 0.6; // 핸들 길이
    final handleColor = Colors.white; // 항상 흰색

    return Container(
      width: handleSize,
      height: handleSize,
      child: CustomPaint(
        painter: _CornerHandlePainter(
          type: type,
          handleLength: handleLength,
          handleThickness: handleThickness,
          handleColor: handleColor,
        ),
      ),
    );
  }

  void _updateCropRect(CropHandleType handle, Offset delta) {
    final aspectRatio = _parseAspectRatio(widget.cropState.selectedAspectRatio);

    // 비율 고정 시에는 핸들로 크기 조정 불가 (이미 핸들이 숨겨져 있지만 안전장치)
    if (aspectRatio != null) {
      return;
    }

    // 자유 비율일 때만 크기 조정 가능
    // minSize를 fixedBounds의 작은 쪽 크기의 10%로 설정 (비율 기반)
    final fixedBounds = widget.cropState.fixedImageBounds;
    if (fixedBounds == null) return;
    final minSize =
        (fixedBounds.width < fixedBounds.height
            ? fixedBounds.width
            : fixedBounds.height) *
        0.1;
    _updateCropRectFree(handle, delta, minSize);
  }

  void _updateCropRectFree(
    CropHandleType handle,
    Offset delta,
    double minSize,
  ) {
    final state = widget.cropState;
    final fixedBounds = state.fixedImageBounds;
    if (fixedBounds == null) return;

    Rect newRect = state.cropRect;

    switch (handle) {
      case CropHandleType.topLeft:
        newRect = Rect.fromLTRB(
          (state.cropRect.left + delta.dx).clamp(
            fixedBounds.left,
            state.cropRect.right - minSize,
          ),
          (state.cropRect.top + delta.dy).clamp(
            fixedBounds.top,
            state.cropRect.bottom - minSize,
          ),
          state.cropRect.right,
          state.cropRect.bottom,
        );
        break;
      case CropHandleType.topRight:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          (state.cropRect.top + delta.dy).clamp(
            fixedBounds.top,
            state.cropRect.bottom - minSize,
          ),
          (state.cropRect.right + delta.dx).clamp(
            state.cropRect.left + minSize,
            fixedBounds.right,
          ),
          state.cropRect.bottom,
        );
        break;
      case CropHandleType.bottomLeft:
        newRect = Rect.fromLTRB(
          (state.cropRect.left + delta.dx).clamp(
            fixedBounds.left,
            state.cropRect.right - minSize,
          ),
          state.cropRect.top,
          state.cropRect.right,
          (state.cropRect.bottom + delta.dy).clamp(
            state.cropRect.top + minSize,
            fixedBounds.bottom,
          ),
        );
        break;
      case CropHandleType.bottomRight:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          state.cropRect.top,
          (state.cropRect.right + delta.dx).clamp(
            state.cropRect.left + minSize,
            fixedBounds.right,
          ),
          (state.cropRect.bottom + delta.dy).clamp(
            state.cropRect.top + minSize,
            fixedBounds.bottom,
          ),
        );
        break;
      case CropHandleType.top:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          (state.cropRect.top + delta.dy).clamp(
            fixedBounds.top,
            state.cropRect.bottom - minSize,
          ),
          state.cropRect.right,
          state.cropRect.bottom,
        );
        break;
      case CropHandleType.bottom:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          state.cropRect.top,
          state.cropRect.right,
          (state.cropRect.bottom + delta.dy).clamp(
            state.cropRect.top + minSize,
            fixedBounds.bottom,
          ),
        );
        break;
      case CropHandleType.left:
        newRect = Rect.fromLTRB(
          (state.cropRect.left + delta.dx).clamp(
            fixedBounds.left,
            state.cropRect.right - minSize,
          ),
          state.cropRect.top,
          state.cropRect.right,
          state.cropRect.bottom,
        );
        break;
      case CropHandleType.right:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          state.cropRect.top,
          (state.cropRect.right + delta.dx).clamp(
            state.cropRect.left + minSize,
            fixedBounds.right,
          ),
          state.cropRect.bottom,
        );
        break;
    }

    // fixedBounds 기준으로 경계 제한 (단순화)
    newRect = _clampResize(newRect, fixedBounds, minSize);

    // cropRect 업데이트 (pixel 단일 소스)
    state.cropRect = newRect;
    widget.onCropRectChanged(newRect);
    setState(() {});
  }

  /// 리사이즈 시 경계 제한 (단순화)
  Rect _clampResize(Rect rect, Rect bounds, double minSize) {
    // 좌표를 bounds 내로 제한
    double left = rect.left.clamp(bounds.left, bounds.right);
    double top = rect.top.clamp(bounds.top, bounds.bottom);
    double right = rect.right.clamp(bounds.left, bounds.right);
    double bottom = rect.bottom.clamp(bounds.top, bounds.bottom);

    // 최소 크기 보장
    if (right - left < minSize) {
      if (left == bounds.left) {
        right = bounds.left + minSize;
      } else {
        left = right - minSize;
      }
    }
    if (bottom - top < minSize) {
      if (top == bounds.top) {
        bottom = bounds.top + minSize;
      } else {
        top = bottom - minSize;
      }
    }

    // 최종 경계 재확인
    left = left.clamp(bounds.left, bounds.right);
    top = top.clamp(bounds.top, bounds.bottom);
    right = right.clamp(bounds.left, bounds.right);
    bottom = bottom.clamp(bounds.top, bounds.bottom);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// 크롭 영역 조정 종료 시 자동 정렬 (pro_image_editor의 _onScaleEnd 로직)
  // 주석 처리: 현재 사용하지 않음 (크롭 중에는 transform 고정)
  // ignore: unused_element
  void _onCropResizeEnd() {
    // ❌ 크롭 중에는 transform 변경 금지 (pro_image_editor 구조)
    // transform은 크롭 모드 종료 시에만 적용
    return;
  }

  double? _parseAspectRatio(String? ratio) {
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
}

/// 크롭 오버레이 Painter
/// 이미지 영역으로 clip하는 CustomClipper
class _ImageRectClipper extends CustomClipper<Rect> {
  final Rect imageRect;

  _ImageRectClipper(this.imageRect);

  @override
  Rect getClip(Size size) => imageRect;

  @override
  bool shouldReclip(_ImageRectClipper oldClipper) =>
      oldClipper.imageRect != imageRect;
}

/// ❌ painter는 state를 믿고 그대로 그림, clamp 절대 금지
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final CropHandleType? activeHandle;

  _CropOverlayPainter({required this.cropRect, this.activeHandle});

  @override
  void paint(Canvas canvas, Size size) {
    // ❌ painter에서 clamp 절대 금지 - state를 그대로 그림

    // 격자선 그리기 (3x3) - 더 선명하게
    final gridPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;

    // 세로선 2개
    canvas.drawLine(
      Offset(cropRect.left + cropRect.width / 3, cropRect.top),
      Offset(cropRect.left + cropRect.width / 3, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.top),
      Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.bottom),
      gridPaint,
    );

    // 가로선 2개
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cropRect.height / 3),
      Offset(cropRect.right, cropRect.top + cropRect.height / 3),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + cropRect.height * 2 / 3),
      Offset(cropRect.right, cropRect.top + cropRect.height * 2 / 3),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.activeHandle != activeHandle;
  }
}

/// 각진 크롭 핸들 Painter
class _CornerHandlePainter extends CustomPainter {
  final CropHandleType type;
  final double handleLength;
  final double handleThickness;
  final Color handleColor;

  _CornerHandlePainter({
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
          ..strokeCap = StrokeCap.square; // 각진 끝

    // 코너 브래킷을 모서리에만 짧게 그리기
    final bracketLength = handleLength;

    switch (type) {
      case CropHandleType.topLeft:
        // 왼쪽 위 모서리 - ┐ 모양 (모서리에서 시작)
        // 가로선: 왼쪽 모서리에서 오른쪽으로
        canvas.drawLine(Offset(0, 0), Offset(bracketLength, 0), paint);
        // 세로선: 왼쪽 모서리에서 아래로
        canvas.drawLine(Offset(0, 0), Offset(0, bracketLength), paint);
        break;
      case CropHandleType.topRight:
        // 오른쪽 위 모서리 - ┌ 모양 (모서리에서 시작)
        // 가로선: 오른쪽 모서리에서 왼쪽으로
        canvas.drawLine(
          Offset(size.width - bracketLength, 0),
          Offset(size.width, 0),
          paint,
        );
        // 세로선: 오른쪽 모서리에서 아래로
        canvas.drawLine(
          Offset(size.width, 0),
          Offset(size.width, bracketLength),
          paint,
        );
        break;
      case CropHandleType.bottomLeft:
        // 왼쪽 아래 모서리 - └ 모양 (모서리에서 시작)
        // 가로선: 왼쪽 모서리에서 오른쪽으로
        canvas.drawLine(
          Offset(0, size.height),
          Offset(bracketLength, size.height),
          paint,
        );
        // 세로선: 왼쪽 모서리에서 위로
        canvas.drawLine(
          Offset(0, size.height - bracketLength),
          Offset(0, size.height),
          paint,
        );
        break;
      case CropHandleType.bottomRight:
        // 오른쪽 아래 모서리 - ┘ 모양 (모서리에서 시작)
        // 가로선: 오른쪽 모서리에서 왼쪽으로
        canvas.drawLine(
          Offset(size.width - bracketLength, size.height),
          Offset(size.width, size.height),
          paint,
        );
        // 세로선: 오른쪽 모서리에서 위로
        canvas.drawLine(
          Offset(size.width, size.height - bracketLength),
          Offset(size.width, size.height),
          paint,
        );
        break;
      case CropHandleType.top:
        // 위쪽 중간 - 가로선 (중앙)
        final center = Offset(size.width / 2, size.height / 2);
        final halfLength = handleLength / 2;
        canvas.drawLine(
          Offset(center.dx - halfLength, center.dy),
          Offset(center.dx + halfLength, center.dy),
          paint,
        );
        break;
      case CropHandleType.bottom:
        // 아래쪽 중간 - 가로선 (중앙)
        final centerBottom = Offset(size.width / 2, size.height / 2);
        final halfLengthBottom = handleLength / 2;
        canvas.drawLine(
          Offset(centerBottom.dx - halfLengthBottom, centerBottom.dy),
          Offset(centerBottom.dx + halfLengthBottom, centerBottom.dy),
          paint,
        );
        break;
      case CropHandleType.left:
        // 왼쪽 중간 - 세로선 (중앙)
        final centerLeft = Offset(size.width / 2, size.height / 2);
        final halfLengthLeft = handleLength / 2;
        canvas.drawLine(
          Offset(centerLeft.dx, centerLeft.dy - halfLengthLeft),
          Offset(centerLeft.dx, centerLeft.dy + halfLengthLeft),
          paint,
        );
        break;
      case CropHandleType.right:
        // 오른쪽 중간 - 세로선 (중앙)
        final centerRight = Offset(size.width / 2, size.height / 2);
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
  bool shouldRepaint(_CornerHandlePainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.handleLength != handleLength ||
        oldDelegate.handleThickness != handleThickness ||
        oldDelegate.handleColor != handleColor;
  }
}

/// 크롭 유틸리티 클래스
class CropUtils {
  CropUtils._();

  /// 크롭 영역 초기화 (크롭 시작 시 1회만 호출)
  /// imageBounds 스냅샷 저장 및 초기 cropRect 설정
  static void initializeCropRect({
    required ui.Image image,
    required Size containerSize,
    required CropState cropState,
    required ValueChanged<Size> onDisplaySizeChanged,
    double scale = 1.0,
    Offset offset = Offset.zero,
  }) {
    // 통합 함수로 imageBounds 계산 (1회만)
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: scale,
      offset: offset,
    );

    onDisplaySizeChanged(Size(imageRect.width, imageRect.height));

    // 🎯 FIXED_imageBounds 스냅샷 저장 (이후 고정)
    cropState.fixedImageBounds = imageRect;

    // 크롭 영역 초기화 (이미지 rect에 정확히 맞게)
    final aspectRatio = _parseAspectRatio(cropState.selectedAspectRatio);
    double cropWidth, cropHeight;

    if (aspectRatio != null) {
      if (aspectRatio > imageRect.width / imageRect.height) {
        cropWidth = imageRect.width;
        cropHeight = cropWidth / aspectRatio;
      } else {
        cropHeight = imageRect.height;
        cropWidth = cropHeight * aspectRatio;
      }
    } else {
      cropWidth = imageRect.width;
      cropHeight = imageRect.height;
    }

    // 크롭 박스가 이미지 경계를 벗어나지 않도록 제한
    cropWidth = cropWidth.clamp(0.0, imageRect.width);
    cropHeight = cropHeight.clamp(0.0, imageRect.height);

    // 중심점 계산 (이미지 경계 내에 있도록)
    final centerX = imageRect.center.dx;
    final centerY = imageRect.center.dy;

    // 크롭 박스 위치 계산 (이미지 경계 내에 완전히 포함되도록)
    final cropLeft = (centerX - cropWidth / 2).clamp(
      imageRect.left,
      imageRect.right - cropWidth,
    );
    final cropTop = (centerY - cropHeight / 2).clamp(
      imageRect.top,
      imageRect.bottom - cropHeight,
    );
    final cropRight = cropLeft + cropWidth;
    final cropBottom = cropTop + cropHeight;

    // 크롭 박스 rect 생성
    final cropRect = Rect.fromLTRB(cropLeft, cropTop, cropRight, cropBottom);

    // 경계 내로 제한 (intersect 대신 clamp 사용)
    final finalCropRect = Rect.fromLTRB(
      cropRect.left.clamp(imageRect.left, imageRect.right),
      cropRect.top.clamp(imageRect.top, imageRect.bottom),
      cropRect.right.clamp(imageRect.left, imageRect.right),
      cropRect.bottom.clamp(imageRect.top, imageRect.bottom),
    );

    // cropRect 설정 (pixel 단일 소스)
    cropState.cropRect = finalCropRect;

    // 정규화된 좌표도 저장 (applyCrop용)
    cropState.fromPixelRect(finalCropRect, imageRect);

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

      // 🎯 fixedImageBounds 사용 (스냅샷)
      final fixedBounds = cropState.fixedImageBounds;
      if (fixedBounds == null) {
        debugPrint('⚠️ fixedImageBounds가 없습니다.');
        return null;
      }

      // pixel cropRect를 normalized로 변환 (이미 저장되어 있지만 재확인)
      cropState.fromPixelRect(cropState.cropRect, fixedBounds);

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

/// 이미지와 크롭 오버레이를 함께 그리는 Painter
/// 이미지와 크롭 박스가 항상 같은 좌표계를 공유
class ImageWithCropPainter extends CustomPainter {
  final ui.Image image;
  final Offset imageOffset;
  final double imageScale;
  final CropState? cropState;

  ImageWithCropPainter(
    this.image, {
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
    this.cropState,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 이미지 rect 계산
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageRect = ImageRectUtils.computeImageRect(
      containerSize: size,
      imageSize: imageSize,
      scale: imageScale,
      offset: imageOffset,
    );

    // 이미지 그리기
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint(),
    );

    // 크롭 모드일 때만 오버레이 그리기
    if (cropState != null && cropState!.isCropRectInitialized) {
      final cropRect = cropState!.cropRect;
      final fixedBounds = cropState!.fixedImageBounds;

      if (fixedBounds != null && fixedBounds.overlaps(cropRect)) {
        // 어두운 오버레이 (크롭 영역 외부)
        final overlayPaint =
            Paint()
              ..color = Colors.black.withOpacity(0.5)
              ..style = PaintingStyle.fill;

        // 상단
        canvas.drawRect(
          Rect.fromLTRB(0, 0, size.width, cropRect.top),
          overlayPaint,
        );
        // 하단
        canvas.drawRect(
          Rect.fromLTRB(0, cropRect.bottom, size.width, size.height),
          overlayPaint,
        );
        // 좌측
        canvas.drawRect(
          Rect.fromLTRB(0, cropRect.top, cropRect.left, cropRect.bottom),
          overlayPaint,
        );
        // 우측
        canvas.drawRect(
          Rect.fromLTRB(
            cropRect.right,
            cropRect.top,
            size.width,
            cropRect.bottom,
          ),
          overlayPaint,
        );

        // 크롭 박스 테두리
        final borderPaint =
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;

        canvas.drawRect(cropRect, borderPaint);

        // 격자선 (3x3)
        final gridPaint =
            Paint()
              ..color = Colors.white.withOpacity(0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0;

        // 세로선 2개
        canvas.drawLine(
          Offset(cropRect.left + cropRect.width / 3, cropRect.top),
          Offset(cropRect.left + cropRect.width / 3, cropRect.bottom),
          gridPaint,
        );
        canvas.drawLine(
          Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.top),
          Offset(cropRect.left + cropRect.width * 2 / 3, cropRect.bottom),
          gridPaint,
        );

        // 가로선 2개
        canvas.drawLine(
          Offset(cropRect.left, cropRect.top + cropRect.height / 3),
          Offset(cropRect.right, cropRect.top + cropRect.height / 3),
          gridPaint,
        );
        canvas.drawLine(
          Offset(cropRect.left, cropRect.top + cropRect.height * 2 / 3),
          Offset(cropRect.right, cropRect.top + cropRect.height * 2 / 3),
          gridPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(ImageWithCropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.imageOffset != imageOffset ||
        oldDelegate.imageScale != imageScale ||
        oldDelegate.cropState?.cropRect != cropState?.cropRect ||
        oldDelegate.cropState?.isCropRectInitialized !=
            cropState?.isCropRectInitialized;
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

  /// 크롭 영역 이동
  static void updateCropRectMove(Offset delta, CropState cropState) {
    final fixedBounds = cropState.fixedImageBounds;
    if (fixedBounds == null) return;

    final dx = (delta.dx).clamp(
      fixedBounds.left - cropState.cropRect.left,
      fixedBounds.right - cropState.cropRect.right,
    );
    final dy = (delta.dy).clamp(
      fixedBounds.top - cropState.cropRect.top,
      fixedBounds.bottom - cropState.cropRect.bottom,
    );

    cropState.cropRect = cropState.cropRect.shift(Offset(dx, dy));
  }

  /// 크롭 영역 리사이즈
  static void updateCropRectResize(
    CropHandleType handle,
    Offset delta,
    CropState cropState,
  ) {
    final fixedBounds = cropState.fixedImageBounds;
    if (fixedBounds == null) return;

    final minSize =
        (fixedBounds.width < fixedBounds.height
            ? fixedBounds.width
            : fixedBounds.height) *
        0.1;

    Rect newRect = cropState.cropRect;

    switch (handle) {
      case CropHandleType.topLeft:
        newRect = Rect.fromLTRB(
          (cropState.cropRect.left + delta.dx).clamp(
            fixedBounds.left,
            cropState.cropRect.right - minSize,
          ),
          (cropState.cropRect.top + delta.dy).clamp(
            fixedBounds.top,
            cropState.cropRect.bottom - minSize,
          ),
          cropState.cropRect.right,
          cropState.cropRect.bottom,
        );
        break;
      case CropHandleType.topRight:
        newRect = Rect.fromLTRB(
          cropState.cropRect.left,
          (cropState.cropRect.top + delta.dy).clamp(
            fixedBounds.top,
            cropState.cropRect.bottom - minSize,
          ),
          (cropState.cropRect.right + delta.dx).clamp(
            cropState.cropRect.left + minSize,
            fixedBounds.right,
          ),
          cropState.cropRect.bottom,
        );
        break;
      case CropHandleType.bottomLeft:
        newRect = Rect.fromLTRB(
          (cropState.cropRect.left + delta.dx).clamp(
            fixedBounds.left,
            cropState.cropRect.right - minSize,
          ),
          cropState.cropRect.top,
          cropState.cropRect.right,
          (cropState.cropRect.bottom + delta.dy).clamp(
            cropState.cropRect.top + minSize,
            fixedBounds.bottom,
          ),
        );
        break;
      case CropHandleType.bottomRight:
        newRect = Rect.fromLTRB(
          cropState.cropRect.left,
          cropState.cropRect.top,
          (cropState.cropRect.right + delta.dx).clamp(
            cropState.cropRect.left + minSize,
            fixedBounds.right,
          ),
          (cropState.cropRect.bottom + delta.dy).clamp(
            cropState.cropRect.top + minSize,
            fixedBounds.bottom,
          ),
        );
        break;
      case CropHandleType.top:
        newRect = Rect.fromLTRB(
          cropState.cropRect.left,
          (cropState.cropRect.top + delta.dy).clamp(
            fixedBounds.top,
            cropState.cropRect.bottom - minSize,
          ),
          cropState.cropRect.right,
          cropState.cropRect.bottom,
        );
        break;
      case CropHandleType.bottom:
        newRect = Rect.fromLTRB(
          cropState.cropRect.left,
          cropState.cropRect.top,
          cropState.cropRect.right,
          (cropState.cropRect.bottom + delta.dy).clamp(
            cropState.cropRect.top + minSize,
            fixedBounds.bottom,
          ),
        );
        break;
      case CropHandleType.left:
        newRect = Rect.fromLTRB(
          (cropState.cropRect.left + delta.dx).clamp(
            fixedBounds.left,
            cropState.cropRect.right - minSize,
          ),
          cropState.cropRect.top,
          cropState.cropRect.right,
          cropState.cropRect.bottom,
        );
        break;
      case CropHandleType.right:
        newRect = Rect.fromLTRB(
          cropState.cropRect.left,
          cropState.cropRect.top,
          (cropState.cropRect.right + delta.dx).clamp(
            cropState.cropRect.left + minSize,
            fixedBounds.right,
          ),
          cropState.cropRect.bottom,
        );
        break;
    }

    cropState.cropRect = newRect;
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
  static Widget buildCropHandles({
    required CropState cropState,
    required CropHandleType? activeHandle,
    required ValueChanged<CropHandleType?> onHandleChanged,
    required VoidCallback onUpdate,
  }) {
    final cropRect = cropState.cropRect;
    final fixedBounds = cropState.fixedImageBounds;
    final aspectRatio = CropGestureUtils.parseAspectRatio(
      cropState.selectedAspectRatio,
    );
    final isAspectRatioLocked = aspectRatio != null;

    if (isAspectRatioLocked || fixedBounds == null) {
      return const SizedBox.shrink();
    }

    final clampHandle = (Offset pos) {
      return Offset(
        pos.dx.clamp(fixedBounds.left, fixedBounds.right),
        pos.dy.clamp(fixedBounds.top, fixedBounds.bottom),
      );
    };

    return Stack(
      children: [
        _CropHandleWidget(
          position: clampHandle(cropRect.topLeft),
          type: CropHandleType.topLeft,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(cropRect.topRight),
          type: CropHandleType.topRight,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(cropRect.bottomLeft),
          type: CropHandleType.bottomLeft,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(cropRect.bottomRight),
          type: CropHandleType.bottomRight,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(Offset(cropRect.center.dx, cropRect.top)),
          type: CropHandleType.top,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(Offset(cropRect.center.dx, cropRect.bottom)),
          type: CropHandleType.bottom,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(Offset(cropRect.left, cropRect.center.dy)),
          type: CropHandleType.left,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
        ),
        _CropHandleWidget(
          position: clampHandle(Offset(cropRect.right, cropRect.center.dy)),
          type: CropHandleType.right,
          activeHandle: activeHandle,
          cropState: cropState,
          onHandleChanged: onHandleChanged,
          onUpdate: onUpdate,
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

  const _CropHandleWidget({
    required this.position,
    required this.type,
    required this.activeHandle,
    required this.cropState,
    required this.onHandleChanged,
    required this.onUpdate,
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
          CropGestureUtils.updateCropRectResize(
            widget.type,
            delta,
            widget.cropState,
          );
          setState(() {
            _panStart = details.globalPosition;
          });
          widget.onUpdate();
        },
        onPanEnd: (_) {
          widget.onHandleChanged(null);
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
