import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 자르기 전용 화면
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    required this.imageBytes,
    this.initialAspectRatio,
  });

  final Uint8List imageBytes;
  final String? initialAspectRatio;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  String? _selectedAspectRatio;
  final CropEditorController _cropController = CropEditorController();

  @override
  void initState() {
    super.initState();
    _selectedAspectRatio = widget.initialAspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 이미지 미리보기 영역 (크롭 오버레이 포함)
            Expanded(
              child: Stack(
                children: [
                  // 이미지 배경
                  _buildImagePreview(),
                  // 크롭 오버레이
                  CropEditor(
                    imageBytes: widget.imageBytes,
                    initialAspectRatio: _selectedAspectRatio,
                    controller: _cropController,
                    onCropComplete: (croppedBytes) {
                      Navigator.pop(context, croppedBytes);
                    },
                    onCancel: () {
                      Navigator.pop(context);
                    },
                    onAspectRatioChanged: (ratio) {
                      setState(() {
                        _selectedAspectRatio = ratio;
                      });
                    },
                    onReset: () {
                      setState(() {
                        _selectedAspectRatio = null;
                      });
                    },
                    onRotate: () {
                      // 회전은 CropEditor 내부에서 처리
                    },
                  ),
                ],
              ),
            ),
            // 툴바
            // _buildToolbar(context, bgColor, fgColor),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 10), // 상단 여유 공간
        child: Transform.scale(
          scale: 0.9,
          child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, Color bgColor, Color fgColor) {
    final cropOptions = [
      {'label': '재설정', 'ratio': 'reset', 'icon': Icons.refresh},
      {'label': '회전', 'ratio': 'rotate', 'icon': Icons.rotate_90_degrees_ccw},
      {'label': '자유', 'ratio': null},
      {'label': '원본', 'ratio': 'original'},
      {'label': '1:1', 'ratio': '1:1'},
      {'label': '4:5', 'ratio': '4:5'},
      {'label': '16:9', 'ratio': '16:9'},
      {'label': '9:16', 'ratio': '9:16'},
    ];

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: fgColor.withOpacity(0.1), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 비율 선택
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                itemCount: cropOptions.length,
                itemBuilder: (context, index) {
                  final option = cropOptions[index];
                  final isSelected = _selectedAspectRatio == option['ratio'];
                  final hasIcon = option['icon'] != null;

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () {
                        if (hasIcon) {
                          if (option['label'] == '재설정') {
                            _cropController.reset();
                            setState(() {
                              _selectedAspectRatio = null;
                            });
                          } else if (option['label'] == '회전') {
                            _cropController.rotate();
                          }
                        } else {
                          final ratio =
                              option['ratio'] == 'original'
                                  ? null
                                  : option['ratio'] as String?;
                          _cropController.setAspectRatio(ratio);
                          setState(() {
                            _selectedAspectRatio = ratio;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : fgColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : fgColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasIcon)
                              Icon(
                                option['icon'] as IconData,
                                color: isSelected ? Colors.white : fgColor,
                                size: 18,
                              ),
                            if (hasIcon) const SizedBox(width: 4),
                            Text(
                              option['label'] as String,
                              style: TextStyle(
                                color: isSelected ? Colors.white : fgColor,
                                fontSize: 14,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // 하단 버튼 (X, 체크)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: fgColor, size: 28),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: fgColor.withOpacity(0.1),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.white, size: 28),
                    onPressed: () {
                      _cropController.applyCrop();
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 자르기 편집기 위젯 (인스타그램/네이버 블로그 스타일)
class CropEditor extends StatefulWidget {
  const CropEditor({
    super.key,
    required this.imageBytes,
    required this.onCropComplete,
    required this.onCancel,
    this.initialAspectRatio,
    this.onAspectRatioChanged,
    this.onReset,
    this.onRotate,
    this.controller,
  });

  final Uint8List imageBytes;
  final Function(Uint8List) onCropComplete;
  final VoidCallback onCancel;
  final String? initialAspectRatio;
  final Function(String?)? onAspectRatioChanged;
  final VoidCallback? onReset;
  final VoidCallback? onRotate;
  final CropEditorController? controller;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late ui.Image _uiImage;
  bool _isImageLoaded = false;
  String? _selectedAspectRatio;

  // 크롭 영역 (격자) - 화면 좌표
  Rect _cropRect = Rect.zero;

  // 이미지 변환 상태
  double _imageScale = 1.0;
  Offset _imageOffset = Offset.zero;
  int _rotation = 0;

  // 제스처 상태
  Offset _panStart = Offset.zero;
  bool _isPanning = false;
  CropHandleType? _activeHandle;

  // 이미지 원본 크기와 표시 크기
  Size _imageSize = Size.zero;
  Size _displaySize = Size.zero;

  @override
  void initState() {
    super.initState();
    _selectedAspectRatio = widget.initialAspectRatio;
    _loadImage();
    widget.controller?._setState(this);
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _uiImage = frame.image;
      _isImageLoaded = true;
      _imageSize = Size(_uiImage.width.toDouble(), _uiImage.height.toDouble());
      _initializeCropRect();
    });
  }

  void _initializeCropRect() {
    if (!_isImageLoaded) return;

    final screenSize = MediaQuery.of(context).size;
    final availableHeight = screenSize.height * 0.9 - 20; // 상단 여유 공간 고려
    final availableWidth = screenSize.width * 0.9;

    // 이미지 비율 계산
    final imageAspect = _imageSize.width / _imageSize.height;

    // 표시 크기 계산 (0.9 스케일 적용)
    if (imageAspect > availableWidth / availableHeight) {
      _displaySize = Size(
        availableWidth * 0.9,
        (availableWidth * 0.9) / imageAspect,
      );
    } else {
      _displaySize = Size(
        availableHeight * imageAspect * 0.9,
        availableHeight * 0.9,
      );
    }

    // 크롭 영역 초기화 - 이미지 전체를 포함하도록 최대 크기로
    double cropWidth, cropHeight;

    if (_selectedAspectRatio != null && _selectedAspectRatio != 'original') {
      final aspectRatio = _parseAspectRatio(_selectedAspectRatio!);
      if (aspectRatio != null) {
        // 비율이 지정된 경우
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
    } else {
      // 자유 비율 또는 원본 비율
      if (imageAspect > availableWidth / availableHeight) {
        cropWidth = availableWidth;
        cropHeight = cropWidth / imageAspect;
      } else {
        cropHeight = availableHeight;
        cropWidth = cropHeight * imageAspect;
      }
    }

    final centerX = screenSize.width / 2;
    final centerY = screenSize.height / 2;

    _cropRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: cropWidth,
      height: cropHeight,
    );

    // 이미지가 크롭 영역에 맞도록 스케일과 오프셋 계산
    _adjustImageToCropRect();
  }

  void _adjustImageToCropRect() {
    if (!_isImageLoaded) return;

    // 크롭 영역에 이미지가 완전히 들어가도록 스케일 계산
    final scaleX = _cropRect.width / _displaySize.width;
    final scaleY = _cropRect.height / _displaySize.height;
    _imageScale = scaleX > scaleY ? scaleX : scaleY;

    // 이미지가 크롭 영역 중앙에 오도록 오프셋 계산
    _imageOffset = Offset.zero;
  }

  double? _parseAspectRatio(String ratio) {
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

  @override
  Widget build(BuildContext context) {
    if (!_isImageLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        painter: _CropPainter(
          image: _uiImage,
          cropRect: _cropRect,
          imageScale: _imageScale,
          imageOffset: _imageOffset,
          rotation: _rotation,
          displaySize: _displaySize,
        ),
        size: Size.infinite,
        child: _buildCropHandles(),
      ),
    );
  }

  Widget _buildCropHandles() {
    return Stack(
      children: [
        // 모서리 핸들
        _buildHandle(_cropRect.topLeft, CropHandleType.topLeft),
        _buildHandle(_cropRect.topRight, CropHandleType.topRight),
        _buildHandle(_cropRect.bottomLeft, CropHandleType.bottomLeft),
        _buildHandle(_cropRect.bottomRight, CropHandleType.bottomRight),
        // 중간 핸들
        _buildHandle(
          Offset(_cropRect.center.dx, _cropRect.top),
          CropHandleType.top,
        ),
        _buildHandle(
          Offset(_cropRect.center.dx, _cropRect.bottom),
          CropHandleType.bottom,
        ),
        _buildHandle(
          Offset(_cropRect.left, _cropRect.center.dy),
          CropHandleType.left,
        ),
        _buildHandle(
          Offset(_cropRect.right, _cropRect.center.dy),
          CropHandleType.right,
        ),
      ],
    );
  }

  Widget _buildHandle(Offset position, CropHandleType type) {
    return Positioned(
      left: position.dx - 15,
      top: position.dy - 15,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _activeHandle = type;
            _isPanning = true;
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
            _isPanning = false;
          });
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.blue, width: 2),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    if (_cropRect.contains(details.localPosition)) {
      setState(() {
        _isPanning = true;
        _panStart = details.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isPanning && _activeHandle == null) {
      // 크롭 영역 전체 이동
      setState(() {
        _cropRect = _cropRect.shift(details.delta);
        _constrainCropRect();
        _adjustImageToCropRect();
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isPanning = false;
    });
  }

  void _constrainCropRect() {
    final screenSize = MediaQuery.of(context).size;
    final padding = 20.0;

    if (_cropRect.left < padding) {
      _cropRect = _cropRect.shift(Offset(padding - _cropRect.left, 0));
    }
    if (_cropRect.top < padding) {
      _cropRect = _cropRect.shift(Offset(0, padding - _cropRect.top));
    }
    if (_cropRect.right > screenSize.width - padding) {
      _cropRect = _cropRect.shift(
        Offset(screenSize.width - padding - _cropRect.right, 0),
      );
    }
    if (_cropRect.bottom > screenSize.height - padding) {
      _cropRect = _cropRect.shift(
        Offset(0, screenSize.height - padding - _cropRect.bottom),
      );
    }
  }

  void _updateCropRect(CropHandleType handle, Offset delta) {
    if (_selectedAspectRatio != null && _selectedAspectRatio != 'original') {
      _updateCropRectWithAspectRatio(handle, delta);
    } else {
      _updateCropRectFree(handle, delta);
    }
    _adjustImageToCropRect();
  }

  void _updateCropRectFree(CropHandleType handle, Offset delta) {
    setState(() {
      final screenSize = MediaQuery.of(context).size;
      final minSize = 100.0;
      final padding = 20.0;

      switch (handle) {
        case CropHandleType.topLeft:
          _cropRect = Rect.fromLTRB(
            (_cropRect.left + delta.dx).clamp(
              padding,
              _cropRect.right - minSize,
            ),
            (_cropRect.top + delta.dy).clamp(
              padding,
              _cropRect.bottom - minSize,
            ),
            _cropRect.right,
            _cropRect.bottom,
          );
          break;
        case CropHandleType.topRight:
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            (_cropRect.top + delta.dy).clamp(
              padding,
              _cropRect.bottom - minSize,
            ),
            (_cropRect.right + delta.dx).clamp(
              _cropRect.left + minSize,
              screenSize.width - padding,
            ),
            _cropRect.bottom,
          );
          break;
        case CropHandleType.bottomLeft:
          _cropRect = Rect.fromLTRB(
            (_cropRect.left + delta.dx).clamp(
              padding,
              _cropRect.right - minSize,
            ),
            _cropRect.top,
            _cropRect.right,
            (_cropRect.bottom + delta.dy).clamp(
              _cropRect.top + minSize,
              screenSize.height - padding,
            ),
          );
          break;
        case CropHandleType.bottomRight:
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            _cropRect.top,
            (_cropRect.right + delta.dx).clamp(
              _cropRect.left + minSize,
              screenSize.width - padding,
            ),
            (_cropRect.bottom + delta.dy).clamp(
              _cropRect.top + minSize,
              screenSize.height - padding,
            ),
          );
          break;
        case CropHandleType.top:
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            (_cropRect.top + delta.dy).clamp(
              padding,
              _cropRect.bottom - minSize,
            ),
            _cropRect.right,
            _cropRect.bottom,
          );
          break;
        case CropHandleType.bottom:
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            _cropRect.top,
            _cropRect.right,
            (_cropRect.bottom + delta.dy).clamp(
              _cropRect.top + minSize,
              screenSize.height - padding,
            ),
          );
          break;
        case CropHandleType.left:
          _cropRect = Rect.fromLTRB(
            (_cropRect.left + delta.dx).clamp(
              padding,
              _cropRect.right - minSize,
            ),
            _cropRect.top,
            _cropRect.right,
            _cropRect.bottom,
          );
          break;
        case CropHandleType.right:
          _cropRect = Rect.fromLTRB(
            _cropRect.left,
            _cropRect.top,
            (_cropRect.right + delta.dx).clamp(
              _cropRect.left + minSize,
              screenSize.width - padding,
            ),
            _cropRect.bottom,
          );
          break;
      }
    });
  }

  void _updateCropRectWithAspectRatio(CropHandleType handle, Offset delta) {
    final aspectRatio = _parseAspectRatio(_selectedAspectRatio!);
    if (aspectRatio == null) return;

    setState(() {
      final screenSize = MediaQuery.of(context).size;
      final minSize = 100.0;
      final padding = 20.0;

      double newWidth = _cropRect.width;
      double newHeight = _cropRect.height;
      Offset newCenter = _cropRect.center;

      switch (handle) {
        case CropHandleType.topLeft:
        case CropHandleType.topRight:
        case CropHandleType.bottomLeft:
        case CropHandleType.bottomRight:
          // 대각선 핸들: 비율 유지하며 크기 조정
          final distance = (delta.dx.abs() + delta.dy.abs()) / 2;
          if (handle == CropHandleType.topLeft ||
              handle == CropHandleType.bottomRight) {
            newWidth = (_cropRect.width + distance).clamp(
              minSize,
              screenSize.width - padding * 2,
            );
          } else {
            newWidth = (_cropRect.width - distance).clamp(
              minSize,
              screenSize.width - padding * 2,
            );
          }
          newHeight = newWidth / aspectRatio;
          if (newHeight > screenSize.height - padding * 2) {
            newHeight = screenSize.height - padding * 2;
            newWidth = newHeight * aspectRatio;
          }
          break;
        case CropHandleType.top:
        case CropHandleType.bottom:
          newHeight = (_cropRect.height +
                  (handle == CropHandleType.bottom ? delta.dy : -delta.dy))
              .clamp(minSize, screenSize.height - padding * 2);
          newWidth = newHeight * aspectRatio;
          if (newWidth > screenSize.width - padding * 2) {
            newWidth = screenSize.width - padding * 2;
            newHeight = newWidth / aspectRatio;
          }
          break;
        case CropHandleType.left:
        case CropHandleType.right:
          newWidth = (_cropRect.width +
                  (handle == CropHandleType.right ? delta.dx : -delta.dx))
              .clamp(minSize, screenSize.width - padding * 2);
          newHeight = newWidth / aspectRatio;
          if (newHeight > screenSize.height - padding * 2) {
            newHeight = screenSize.height - padding * 2;
            newWidth = newHeight * aspectRatio;
          }
          break;
      }

      _cropRect = Rect.fromCenter(
        center: newCenter,
        width: newWidth,
        height: newHeight,
      );

      _constrainCropRect();
    });
  }

  void _resetCrop() {
    setState(() {
      _rotation = 0;
      _imageOffset = Offset.zero;
      _imageScale = 1.0;
      _selectedAspectRatio = null;
      _initializeCropRect();
    });
    widget.onReset?.call();
  }

  void _rotateImage() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
      // 회전 후 크롭 영역 재조정
      _initializeCropRect();
    });
    widget.onRotate?.call();
  }

  void setAspectRatioFromController(String? ratio) {
    setState(() {
      _selectedAspectRatio = ratio;
      _initializeCropRect();
    });
    widget.onAspectRatioChanged?.call(_selectedAspectRatio);
  }

  Future<void> _applyCrop() async {
    if (!_isImageLoaded) return;

    try {
      final decoded = img.decodeImage(widget.imageBytes);
      if (decoded == null) return;

      // 회전 적용
      img.Image processed = decoded;
      if (_rotation != 0) {
        processed = img.copyRotate(decoded, angle: _rotation.toDouble());
      }

      // 크롭 영역을 이미지 좌표로 변환
      final screenSize = MediaQuery.of(context).size;
      final imageAspect = _imageSize.width / _imageSize.height;
      final availableHeight = screenSize.height * 0.9 - 20;
      final availableWidth = screenSize.width * 0.9;

      double displayWidth, displayHeight;
      if (imageAspect > availableWidth / availableHeight) {
        displayWidth = availableWidth * 0.9;
        displayHeight = displayWidth / imageAspect;
      } else {
        displayHeight = availableHeight * 0.9;
        displayWidth = displayHeight * imageAspect;
      }

      // 크롭 영역의 실제 이미지 좌표 계산
      final scaleX = processed.width / displayWidth;
      final scaleY = processed.height / displayHeight;

      final cropX =
          ((_cropRect.left - (screenSize.width - displayWidth) / 2) * scaleX)
              .clamp(0.0, processed.width.toDouble())
              .toInt();
      final cropY =
          ((_cropRect.top - (screenSize.height - displayHeight) / 2 - 10) *
                  scaleY)
              .clamp(0.0, processed.height.toDouble())
              .toInt();
      final cropWidth =
          (_cropRect.width * scaleX)
              .clamp(0.0, (processed.width - cropX).toDouble())
              .toInt();
      final cropHeight =
          (_cropRect.height * scaleY)
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
      final result = Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
      widget.onCropComplete(result);
    } catch (e) {
      debugPrint('크롭 에러: $e');
    }
  }
}

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

/// CropEditor를 외부에서 제어하기 위한 컨트롤러
class CropEditorController {
  _CropEditorState? _state;

  void _setState(_CropEditorState state) {
    _state = state;
  }

  void reset() {
    _state?._resetCrop();
  }

  void rotate() {
    _state?._rotateImage();
  }

  void setAspectRatio(String? ratio) {
    _state?.setAspectRatioFromController(ratio);
  }

  void applyCrop() {
    _state?._applyCrop();
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;
  final double imageScale;
  final Offset imageOffset;
  final int rotation;
  final Size displaySize;

  _CropPainter({
    required this.image,
    required this.cropRect,
    required this.imageScale,
    required this.imageOffset,
    required this.rotation,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 크롭 영역 외부 어둡게
    final path =
        Path()
          ..addRect(Offset.zero & size)
          ..addRect(cropRect)
          ..fillType = PathFillType.evenOdd;

    final darkPaint = Paint()..color = Colors.black.withOpacity(0.7);
    canvas.drawPath(path, darkPaint);

    // 이미지 그리기 (크롭 영역에 맞춰서)
    final imageRect = Rect.fromCenter(
      center: cropRect.center + imageOffset,
      width: displaySize.width * imageScale,
      height: displaySize.height * imageScale,
    );

    canvas.save();
    canvas.clipRect(cropRect);
    canvas.translate(imageRect.center.dx, imageRect.center.dy);
    canvas.rotate(rotation * 3.14159 / 180);
    canvas.translate(-imageRect.center.dx, -imageRect.center.dy);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint(),
    );
    canvas.restore();

    // 크롭 영역 테두리
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawRect(cropRect, borderPaint);

    // 격자선 그리기 (3x3)
    final gridPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.5)
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
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.imageScale != imageScale ||
        oldDelegate.imageOffset != imageOffset ||
        oldDelegate.rotation != rotation ||
        oldDelegate.displaySize != displaySize;
  }
}
