import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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
class CropState {
  String? selectedAspectRatio; // null = 자유, '1:1', '4:5', '16:9' 등
  Rect cropRect = Rect.zero; // 크롭 영역 (화면 좌표)
  bool isCropRectInitialized = false;
  int rotation = 0; // 회전 각도

  void reset() {
    selectedAspectRatio = null;
    cropRect = Rect.zero;
    isCropRectInitialized = false;
    rotation = 0;
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
    this.onImageTransformChanged,
    this.currentImageScale = 1.0,
    this.currentImageOffset = Offset.zero,
  });

  final CropState cropState;
  final Size imageSize;
  final Size containerSize;
  final ValueChanged<Rect> onCropRectChanged;
  final CropHandleType? activeHandle;
  final ValueChanged<({Offset offset, double scale})>? onImageTransformChanged;
  final double currentImageScale;
  final Offset currentImageOffset;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  CropHandleType? _activeHandle;
  Offset _panStart = Offset.zero;
  Rect? _viewRect; // 이미지 표시 영역 (pro_image_editor의 _viewRect 개념)

  @override
  void initState() {
    super.initState();
    // _viewRect 초기화 (이미지 표시 영역)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _viewRect = _getImageDisplayBounds();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // _viewRect가 없으면 초기화
    _viewRect ??= _getImageDisplayBounds();

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
      child: CustomPaint(
        painter: _CropOverlayPainter(
          cropRect: widget.cropState.cropRect,
          activeHandle: widget.activeHandle ?? _activeHandle,
        ),
        size: widget.containerSize,
        child: _buildCropHandles(),
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
    final imageBounds = _getImageDisplayBounds();
    const handlePadding = 22.0; // 핸들 크기의 절반 (터치 영역 44 / 2)

    // 이미지 경계에서 패딩을 뺀 실제 사용 가능한 영역
    final availableBounds = Rect.fromLTRB(
      imageBounds.left + handlePadding,
      imageBounds.top + handlePadding,
      imageBounds.right - handlePadding,
      imageBounds.bottom - handlePadding,
    );

    Rect newRect = state.cropRect.shift(delta);

    // 이미지 표시 영역 경계 제한 (패딩 고려)
    if (newRect.left < availableBounds.left) {
      newRect = newRect.shift(Offset(availableBounds.left - newRect.left, 0));
    }
    if (newRect.top < availableBounds.top) {
      newRect = newRect.shift(Offset(0, availableBounds.top - newRect.top));
    }
    if (newRect.right > availableBounds.right) {
      newRect = newRect.shift(Offset(availableBounds.right - newRect.right, 0));
    }
    if (newRect.bottom > availableBounds.bottom) {
      newRect = newRect.shift(
        Offset(0, availableBounds.bottom - newRect.bottom),
      );
    }

    // 크롭 영역 이동 시에는 이미지 변환 업데이트하지 않음 (이미지 고정)
    state.cropRect = newRect;
    widget.onCropRectChanged(newRect);
    setState(() {});
  }

  Rect _getImageDisplayBounds() {
    final containerSize = widget.containerSize;
    final imageSize = widget.imageSize;

    // 이미지 표시 크기 계산 (스케일 1.0 기준)
    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = containerSize.width / containerSize.height;

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

    // 현재 스케일과 오프셋을 적용한 실제 이미지 표시 영역 계산
    final scaledWidth = baseDisplayWidth * widget.currentImageScale;
    final scaledHeight = baseDisplayHeight * widget.currentImageScale;

    // 스케일 적용 시 이미지 중심 기준으로 확대되므로 오프셋 조정
    final scaledImageOffsetX =
        baseImageOffsetX - (scaledWidth - baseDisplayWidth) / 2;
    final scaledImageOffsetY =
        baseImageOffsetY - (scaledHeight - baseDisplayHeight) / 2;

    // 추가 오프셋 적용
    final finalImageOffsetX = scaledImageOffsetX + widget.currentImageOffset.dx;
    final finalImageOffsetY = scaledImageOffsetY + widget.currentImageOffset.dy;

    return Rect.fromLTWH(
      finalImageOffsetX,
      finalImageOffsetY,
      scaledWidth,
      scaledHeight,
    );
  }

  void _resetCropRect() {
    // 크롭 영역을 이미지 전체로 리셋 (핸들 패딩 고려)
    final imageBounds = _getImageDisplayBounds();
    const handlePadding = 22.0; // 핸들 크기의 절반 (터치 영역 44 / 2)

    // 이미지 경계에서 패딩을 뺀 실제 사용 가능한 영역
    final availableBounds = Rect.fromLTRB(
      imageBounds.left + handlePadding,
      imageBounds.top + handlePadding,
      imageBounds.right - handlePadding,
      imageBounds.bottom - handlePadding,
    );

    final newRect = Rect.fromLTWH(
      availableBounds.left,
      availableBounds.top,
      availableBounds.width,
      availableBounds.height,
    );

    widget.cropState.cropRect = newRect;
    widget.onCropRectChanged(newRect);
    _viewRect = newRect;

    // 이미지 원래 위치로 복귀
    if (widget.onImageTransformChanged != null) {
      widget.onImageTransformChanged!((offset: Offset.zero, scale: 1.0));
    }
    setState(() {});
  }

  Widget _buildCropHandles() {
    final cropRect = widget.cropState.cropRect;
    final aspectRatio = _parseAspectRatio(widget.cropState.selectedAspectRatio);
    final isAspectRatioLocked = aspectRatio != null;

    // 비율 고정 시 핸들 숨김 (이동만 가능)
    if (isAspectRatioLocked) {
      return const SizedBox.shrink();
    }

    // 자유 비율일 때만 모든 핸들 표시
    return Stack(
      children: [
        // 모서리 핸들
        _buildHandle(cropRect.topLeft, CropHandleType.topLeft, false),
        _buildHandle(cropRect.topRight, CropHandleType.topRight, false),
        _buildHandle(cropRect.bottomLeft, CropHandleType.bottomLeft, false),
        _buildHandle(cropRect.bottomRight, CropHandleType.bottomRight, false),
        // 중간 핸들
        _buildHandle(
          Offset(cropRect.center.dx, cropRect.top),
          CropHandleType.top,
          false,
        ),
        _buildHandle(
          Offset(cropRect.center.dx, cropRect.bottom),
          CropHandleType.bottom,
          false,
        ),
        _buildHandle(
          Offset(cropRect.left, cropRect.center.dy),
          CropHandleType.left,
          false,
        ),
        _buildHandle(
          Offset(cropRect.right, cropRect.center.dy),
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
            // _viewRect 초기화 (이미지 표시 영역)
            _viewRect ??= _getImageDisplayBounds();
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
    final screenSize = MediaQuery.of(context).size;
    final minSize = 100.0;
    final padding = 20.0;
    _updateCropRectFree(handle, delta, screenSize, minSize, padding);
  }

  void _updateCropRectFree(
    CropHandleType handle,
    Offset delta,
    Size screenSize,
    double minSize,
    double padding,
  ) {
    final state = widget.cropState;
    final imageBounds = _getImageDisplayBounds();
    const handlePadding = 22.0; // 핸들 크기의 절반 (터치 영역 44 / 2)

    // 이미지 경계에서 패딩을 뺀 실제 사용 가능한 영역
    final availableBounds = Rect.fromLTRB(
      imageBounds.left + handlePadding,
      imageBounds.top + handlePadding,
      imageBounds.right - handlePadding,
      imageBounds.bottom - handlePadding,
    );

    Rect newRect = state.cropRect;

    switch (handle) {
      case CropHandleType.topLeft:
        newRect = Rect.fromLTRB(
          (state.cropRect.left + delta.dx).clamp(
            availableBounds.left,
            state.cropRect.right - minSize,
          ),
          (state.cropRect.top + delta.dy).clamp(
            availableBounds.top,
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
            availableBounds.top,
            state.cropRect.bottom - minSize,
          ),
          (state.cropRect.right + delta.dx).clamp(
            state.cropRect.left + minSize,
            availableBounds.right,
          ),
          state.cropRect.bottom,
        );
        break;
      case CropHandleType.bottomLeft:
        newRect = Rect.fromLTRB(
          (state.cropRect.left + delta.dx).clamp(
            availableBounds.left,
            state.cropRect.right - minSize,
          ),
          state.cropRect.top,
          state.cropRect.right,
          (state.cropRect.bottom + delta.dy).clamp(
            state.cropRect.top + minSize,
            availableBounds.bottom,
          ),
        );
        break;
      case CropHandleType.bottomRight:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          state.cropRect.top,
          (state.cropRect.right + delta.dx).clamp(
            state.cropRect.left + minSize,
            availableBounds.right,
          ),
          (state.cropRect.bottom + delta.dy).clamp(
            state.cropRect.top + minSize,
            availableBounds.bottom,
          ),
        );
        break;
      case CropHandleType.top:
        newRect = Rect.fromLTRB(
          state.cropRect.left,
          (state.cropRect.top + delta.dy).clamp(
            availableBounds.top,
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
            availableBounds.bottom,
          ),
        );
        break;
      case CropHandleType.left:
        newRect = Rect.fromLTRB(
          (state.cropRect.left + delta.dx).clamp(
            availableBounds.left,
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
            availableBounds.right,
          ),
          state.cropRect.bottom,
        );
        break;
    }

    newRect = _constrainCropRectToImageBounds(newRect, availableBounds);
    widget.cropState.cropRect = newRect;
    widget.onCropRectChanged(newRect);
    // pro_image_editor 로직: 크롭 영역 조정 중에는 이미지 고정 (변환 업데이트 안 함)
    setState(() {});
  }

  Rect _constrainCropRectToImageBounds(Rect rect, Rect availableBounds) {
    // 크롭 영역이 사용 가능한 영역을 벗어나지 않도록 제한
    if (rect.left < availableBounds.left) {
      rect = rect.shift(Offset(availableBounds.left - rect.left, 0));
    }
    if (rect.top < availableBounds.top) {
      rect = rect.shift(Offset(0, availableBounds.top - rect.top));
    }
    if (rect.right > availableBounds.right) {
      rect = rect.shift(Offset(availableBounds.right - rect.right, 0));
    }
    if (rect.bottom > availableBounds.bottom) {
      rect = rect.shift(Offset(0, availableBounds.bottom - rect.bottom));
    }
    return rect;
  }

  /// 크롭 영역 조정 종료 시 자동 정렬 (pro_image_editor의 _onScaleEnd 로직)
  void _onCropResizeEnd() {
    if (widget.onImageTransformChanged == null) return;

    // _viewRect 초기화 (이미지 표시 영역)
    _viewRect ??= _getImageDisplayBounds();

    final cropRect = widget.cropState.cropRect;
    final viewRect = _viewRect!;

    // 크롭 영역이 이미지 표시 영역과 같으면 아무것도 안 함
    if ((cropRect.left - viewRect.left).abs() < 1 &&
        (cropRect.top - viewRect.top).abs() < 1 &&
        (cropRect.width - viewRect.width).abs() < 1 &&
        (cropRect.height - viewRect.height).abs() < 1) {
      return;
    }

    // 크롭 영역이 이미지 표시 영역보다 작으면 이미지 확대 및 이동
    final isCropSmallerThanImage =
        cropRect.width < viewRect.width - 1 ||
        cropRect.height < viewRect.height - 1;

    if (isCropSmallerThanImage) {
      // 이미지 확대 비율 계산
      final scaleX = viewRect.width / cropRect.width;
      final scaleY = viewRect.height / cropRect.height;
      final scale = math.min(scaleX, scaleY).clamp(1.0, 3.0); // 최대 3배까지 확대

      // 이미지 오프셋 계산: 크롭 영역 중심이 이미지 중심에 오도록
      final containerSize = widget.containerSize;
      final imageSize = widget.imageSize;

      final imageAspect = imageSize.width / imageSize.height;
      final containerAspect = containerSize.width / containerSize.height;

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

      // 확대된 이미지의 중심점
      final scaledDisplayWidth = baseDisplayWidth * scale;
      final scaledDisplayHeight = baseDisplayHeight * scale;
      final scaledImageOffsetX =
          baseImageOffsetX - (scaledDisplayWidth - baseDisplayWidth) / 2;
      final scaledImageOffsetY =
          baseImageOffsetY - (scaledDisplayHeight - baseDisplayHeight) / 2;

      final scaledImageCenter = Offset(
        scaledImageOffsetX + scaledDisplayWidth / 2,
        scaledImageOffsetY + scaledDisplayHeight / 2,
      );

      // 크롭 영역 중심에 맞춰 이미지 오프셋 계산
      final offset = cropRect.center - scaledImageCenter;

      widget.onImageTransformChanged!((offset: offset, scale: scale));
    } else {
      // 크롭 영역이 이미지 표시 영역과 같거나 클 때: 이미지 원래 위치로 복귀
      widget.onImageTransformChanged!((offset: Offset.zero, scale: 1.0));
      // _viewRect도 업데이트
      _viewRect = cropRect;
    }
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
class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final CropHandleType? activeHandle;

  _CropOverlayPainter({required this.cropRect, this.activeHandle});

  @override
  void paint(Canvas canvas, Size size) {
    // 테두리 제거 (미니멀한 디자인)

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

  /// 크롭 영역 초기화
  static void initializeCropRect({
    required ui.Image image,
    required Size containerSize,
    required CropState cropState,
    required ValueChanged<Size> onDisplaySizeChanged,
  }) {
    final imageAspect = image.width / image.height;
    final containerAspect = containerSize.width / containerSize.height;

    // 이미지 표시 크기 계산
    double displayWidth, displayHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspect > containerAspect) {
      displayWidth = containerSize.width;
      displayHeight = containerSize.width / imageAspect;
      offsetY = (containerSize.height - displayHeight) / 2;
    } else {
      displayHeight = containerSize.height;
      displayWidth = containerSize.height * imageAspect;
      offsetX = (containerSize.width - displayWidth) / 2;
    }

    onDisplaySizeChanged(Size(displayWidth, displayHeight));

    // 핸들이 이미지 안쪽에 위치하도록 패딩 추가
    const handlePadding = 22.0; // 핸들 크기의 절반 (터치 영역 44 / 2)
    final availableWidth = displayWidth - (handlePadding * 2);
    final availableHeight = displayHeight - (handlePadding * 2);
    final availableOffsetX = offsetX + handlePadding;
    final availableOffsetY = offsetY + handlePadding;

    // 크롭 영역 초기화 (이미지 전체, 패딩 고려)
    final aspectRatio = _parseAspectRatio(cropState.selectedAspectRatio);
    double cropWidth, cropHeight;

    if (aspectRatio != null) {
      if (aspectRatio > availableWidth / availableHeight) {
        cropWidth = availableWidth;
        cropHeight = cropWidth / aspectRatio;
      } else {
        cropHeight = availableHeight;
        cropWidth = cropHeight * aspectRatio;
      }
    } else {
      cropWidth = availableWidth;
      cropHeight = availableHeight;
    }

    final centerX = availableOffsetX + availableWidth / 2;
    final centerY = availableOffsetY + availableHeight / 2;

    cropState.cropRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: cropWidth,
      height: cropHeight,
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
  static Future<Uint8List?> applyCrop({
    required Uint8List imageBytes,
    required Rect cropRect,
    required Size imageDisplaySize,
    required ui.Image uiImage,
    required Size containerSize,
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

      // 크롭 영역을 이미지 좌표로 변환
      final scaleX = processed.width / imageDisplaySize.width;
      final scaleY = processed.height / imageDisplaySize.height;

      final imageAspect = uiImage.width / uiImage.height;
      final containerAspect = containerSize.width / containerSize.height;

      double offsetX = 0, offsetY = 0;
      if (imageAspect > containerAspect) {
        offsetY = (containerSize.height - imageDisplaySize.height) / 2;
      } else {
        offsetX = (containerSize.width - imageDisplaySize.width) / 2;
      }

      final cropX =
          ((cropRect.left - offsetX) * scaleX)
              .clamp(0.0, processed.width.toDouble())
              .toInt();
      final cropY =
          ((cropRect.top - offsetY) * scaleY)
              .clamp(0.0, processed.height.toDouble())
              .toInt();
      final cropWidth =
          (cropRect.width * scaleX)
              .clamp(0.0, (processed.width - cropX).toDouble())
              .toInt();
      final cropHeight =
          (cropRect.height * scaleY)
              .clamp(0.0, (processed.height - cropY).toDouble())
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
