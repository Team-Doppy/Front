import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

// Services
import 'package:doppy/editor/service/image_service.dart';

// Models
import 'package:doppy/editor/image/models/filter_preset.dart';
import 'package:doppy/editor/image/models/crop_aspect_ratio.dart';
import 'package:doppy/editor/image/models/image_adjustment.dart';

// Widgets
import 'package:doppy/editor/image/widgets/crop_overlay.dart';
import 'package:doppy/editor/image/widgets/editor_tool_button.dart';
import 'package:doppy/editor/image/widgets/ratio_chip.dart';
import 'package:doppy/editor/image/widgets/filter_chip.dart';
import 'package:doppy/editor/image/widgets/adjustment_chip.dart';
import 'package:doppy/editor/image/widgets/adjustment_slider.dart';

/// image_editor_plus 기반의 간단한 편집 화면
/// - 입력: Uint8List 이미지 바이트
/// - 출력: Navigator.pop 으로 편집된 Uint8List 반환 (취소 시 null)
class ImageEditorPlusScreen extends StatelessWidget {
  const ImageEditorPlusScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    // ImageEditor 자체가 편집 UI와 완료/취소 동작을 내장하고 있음
    // 완료 시 Navigator.pop(context, Uint8List) 호출
    return ImageEditor(image: imageBytes);
  }
}

/// 헬퍼: 에디터를 열고 결과 바이트를 돌려받는다. (취소 시 null)
Future<Uint8List?> openImageEditorPlus(
  BuildContext context, {
  required Uint8List imageBytes,
}) async {
  // 커스텀 에디터 화면 오픈
  final edited = await Navigator.push<Uint8List?>(
    context,
    MaterialPageRoute(
      builder: (context) => CustomImageEditorScreen(imageBytes: imageBytes),
      fullscreenDialog: true,
    ),
  );
  return edited;
}

class CustomImageEditorScreen extends StatefulWidget {
  const CustomImageEditorScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CustomImageEditorScreen> createState() =>
      _CustomImageEditorScreenState();
}

class _CustomImageEditorScreenState extends State<CustomImageEditorScreen>
    with TickerProviderStateMixin {
  late Uint8List _currentImage;
  bool _isCropping = false;
  bool _isFiltering = false;
  bool _isAdjusting = false;
  double bottomSheetHeight = 300;

  // 자르기 영역 (비율 기준 0~1)
  Rect _cropRect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
  CropAspectRatio _selectedRatio = CropAspectRatio.free;
  Size? _cachedImageSize; // 이미지 크기 캐시

  // 필터 관련
  FilterType _selectedFilter = FilterType.none;
  double _filterIntensity = 1.0;
  bool _hasSwiped = false; // 스와이프 상태 추적

  // 조정 관련
  ImageAdjustmentState _adjustmentState = const ImageAdjustmentState();
  AdjustmentType? _selectedAdjustmentType;
  bool _isAdjustmentDetailMode = false; // 상세 조정 모드 여부

  // 바텀시트 관련
  bool _isBottomSheetOpen = false;
  late AnimationController _bottomSheetController;
  late Animation<double> _bottomSheetAnimation;
  late Animation<double> _imageScaleAnimation;
  double _dragOffset = 0.0; // 드래그 오프셋

  // UI 토글
  bool _showUI = true;

  // Undo/Redo 스택
  final List<Uint8List> _history = [];
  final List<Uint8List> _redoStack = [];

  @override
  void initState() {
    _currentImage = widget.imageBytes;
    _history.add(widget.imageBytes); // 초기 이미지 저장

    // 애니메이션 컨트롤러 초기화
    _bottomSheetController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _bottomSheetAnimation = CurvedAnimation(
      parent: _bottomSheetController,
      curve: Curves.easeInOut,
    );

    _imageScaleAnimation = Tween<double>(begin: 1.0, end: 0.7).animate(
      CurvedAnimation(parent: _bottomSheetController, curve: Curves.easeInOut),
    );
    // 바텀시트 올라올 때 이미지도 위로 이동

    super.initState();
  }

  @override
  void dispose() {
    _bottomSheetController.dispose();
    super.dispose();
  }

  void _saveToHistory() {
    _history.add(_currentImage);
    _redoStack.clear(); // 새로운 작업 시 redo 스택 초기화
    if (_history.length > 20) {
      _history.removeAt(0); // 메모리 관리를 위해 20개로 제한
    }
  }

  void _undo() {
    if (_history.length <= 1) return;

    setState(() {
      _redoStack.add(_currentImage);
      _history.removeLast();
      _currentImage = _history.last;
      _cachedImageSize = null; // 캐시 초기화
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;

    setState(() {
      final redoImage = _redoStack.removeLast();
      _history.add(redoImage);
      _currentImage = redoImage;
      _cachedImageSize = null; // 캐시 초기화
    });
  }

  void _applyAspectRatio(CropAspectRatio ratio) {
    setState(() {
      _selectedRatio = ratio;

      // 현재 자르기 영역의 중심점
      final centerX = _cropRect.left + _cropRect.width / 2;
      final centerY = _cropRect.top + _cropRect.height / 2;

      double newWidth = _cropRect.width;
      double newHeight = _cropRect.height;

      switch (ratio) {
        case CropAspectRatio.square: // 1:1
          final size =
              _cropRect.width < _cropRect.height
                  ? _cropRect.width
                  : _cropRect.height;
          newWidth = size;
          newHeight = size;
          break;
        case CropAspectRatio.ratio3_4: // 3:4
          newHeight = newWidth * 4 / 3;
          if (newHeight > 0.8) {
            newHeight = 0.8;
            newWidth = newHeight * 3 / 4;
          }
          break;
        case CropAspectRatio.ratio4_3: // 4:3
          newWidth = newHeight * 4 / 3;
          if (newWidth > 0.8) {
            newWidth = 0.8;
            newHeight = newWidth * 3 / 4;
          }
          break;
        case CropAspectRatio.ratio9_16: // 9:16
          newHeight = newWidth * 16 / 9;
          if (newHeight > 0.8) {
            newHeight = 0.8;
            newWidth = newHeight * 9 / 16;
          }
          break;
        case CropAspectRatio.ratio16_9: // 16:9
          newWidth = newHeight * 16 / 9;
          if (newWidth > 0.8) {
            newWidth = 0.8;
            newHeight = newWidth * 9 / 16;
          }
          break;
        case CropAspectRatio.free:
          // 자유 비율 - 변경 없음
          return;
      }

      // 새로운 영역 계산 (중심점 유지)
      final left = (centerX - newWidth / 2).clamp(0.0, 1.0 - newWidth);
      final top = (centerY - newHeight / 2).clamp(0.0, 1.0 - newHeight);

      _cropRect = Rect.fromLTWH(left, top, newWidth, newHeight);
    });
  }

  Future<void> _applyCrop() async {
    try {
      // image 패키지로 자르기
      final image = img.decodeImage(_currentImage);
      if (image == null) return;

      // 비율 좌표를 픽셀 좌표로 변환
      final x = (_cropRect.left * image.width).round().clamp(0, image.width);
      final y = (_cropRect.top * image.height).round().clamp(0, image.height);
      final w = (_cropRect.width * image.width).round().clamp(
        1,
        image.width - x,
      );
      final h = (_cropRect.height * image.height).round().clamp(
        1,
        image.height - y,
      );

      final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);

      final croppedBytes = Uint8List.fromList(
        img.encodeJpg(cropped, quality: 95),
      );

      setState(() {
        _currentImage = croppedBytes;
        _cachedImageSize = null; // 캐시 초기화
        _saveToHistory(); // 히스토리에 저장
        _isCropping = false;
        _cropRect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8); // 리셋
        _selectedRatio = CropAspectRatio.free; // 비율 리셋
      });
    } catch (e) {
      print('자르기 오류: $e');
    }
  }

  void _onFilter() {
    _toggleFilter();
  }

  void _onDone() {
    // 편집 결과를 ImageService에 반영. 선택된 이미지가 존재하는 경우에만.
    final imageService = context.read<NodeComponentService>();
    final selectedId = imageService.selectedImageId;
    if (selectedId != null) {
      imageService.applyEditedBytes(nodeId: selectedId, bytes: _currentImage);
    }
    Navigator.pop(context, _currentImage);
  }

  void _updateCropRect(Offset delta, String handle) {
    setState(() {
      double left = _cropRect.left;
      double top = _cropRect.top;
      double right = _cropRect.right;
      double bottom = _cropRect.bottom;

      if (handle == 'move') {
        // 이동은 비율 관계없이 동일
        final width = _cropRect.width;
        final height = _cropRect.height;
        left = (left + delta.dx).clamp(0.0, 1.0 - width);
        top = (top + delta.dy).clamp(0.0, 1.0 - height);
        right = left + width;
        bottom = top + height;
      } else {
        // 핸들 드래그 시 비율 유지 여부 확인
        if (_selectedRatio == CropAspectRatio.free) {
          // 자유 비율 - 기존 로직
          switch (handle) {
            case 'topLeft':
              left = (left + delta.dx).clamp(0.0, right - 0.1);
              top = (top + delta.dy).clamp(0.0, bottom - 0.1);
              break;
            case 'topRight':
              right = (right + delta.dx).clamp(left + 0.1, 1.0);
              top = (top + delta.dy).clamp(0.0, bottom - 0.1);
              break;
            case 'bottomLeft':
              left = (left + delta.dx).clamp(0.0, right - 0.1);
              bottom = (bottom + delta.dy).clamp(top + 0.1, 1.0);
              break;
            case 'bottomRight':
              right = (right + delta.dx).clamp(left + 0.1, 1.0);
              bottom = (bottom + delta.dy).clamp(top + 0.1, 1.0);
              break;
          }
        } else {
          // 비율 유지 - 대각선 드래그만 허용하고 비율 유지
          final aspectRatio = CropAspectRatioUtils.getValue(_selectedRatio);
          final centerX = _cropRect.left + _cropRect.width / 2;
          final centerY = _cropRect.top + _cropRect.height / 2;

          // 드래그 방향에 따라 크기 조정 (중심점 유지)
          double newWidth = _cropRect.width;
          double newHeight = _cropRect.height;

          switch (handle) {
            case 'topLeft':
            case 'bottomLeft':
              // 왼쪽 핸들 - width 변경 기준
              newWidth = (newWidth - delta.dx).clamp(0.1, 1.0);
              newHeight = newWidth / aspectRatio;
              break;
            case 'topRight':
            case 'bottomRight':
              // 오른쪽 핸들 - width 변경 기준
              newWidth = (newWidth + delta.dx).clamp(0.1, 1.0);
              newHeight = newWidth / aspectRatio;
              break;
          }

          // 새 영역이 화면을 벗어나지 않도록 조정
          if (newWidth > 1.0) {
            newWidth = 1.0;
            newHeight = newWidth / aspectRatio;
          }
          if (newHeight > 1.0) {
            newHeight = 1.0;
            newWidth = newHeight * aspectRatio;
          }

          // 중심점 기준으로 새 영역 계산
          left = (centerX - newWidth / 2).clamp(0.0, 1.0 - newWidth);
          top = (centerY - newHeight / 2).clamp(0.0, 1.0 - newHeight);
          right = left + newWidth;
          bottom = top + newHeight;
        }
      }

      _cropRect = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  Future<Size> _getImageSize() async {
    // 캐시된 크기가 있으면 반환
    if (_cachedImageSize != null) {
      return _cachedImageSize!;
    }

    // 이미지의 실제 크기 계산 및 캐시
    final codec = await ui.instantiateImageCodec(_currentImage);
    final frame = await codec.getNextFrame();
    _cachedImageSize = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    return _cachedImageSize!;
  }

  void _toggleFilter() {
    setState(() {
      _isFiltering = !_isFiltering;
      _isBottomSheetOpen = _isFiltering;
      if (!_isFiltering) {
        _selectedFilter = FilterType.none;

        _bottomSheetController.reverse();
      } else {
        _bottomSheetController.forward();
      }
    });
  }

  void _toggleCrop() {
    setState(() {
      _isCropping = !_isCropping;
      _isBottomSheetOpen = _isCropping;
      if (_isCropping) {
        _bottomSheetController.forward();
        // 자르기 모드 진입 시 이미지 크기 미리 캐시
        if (_cachedImageSize == null) {
          _getImageSize();
        }
      } else {
        _bottomSheetController.reverse();
      }
    });
  }

  void _toggleAdjustment() {
    setState(() {
      _isAdjusting = !_isAdjusting;
      _isBottomSheetOpen = _isAdjusting;
      if (_isAdjusting) {
        _bottomSheetController.forward();
        // 기본 조정 타입 선택
        _selectedAdjustmentType = AdjustmentType.brightness;
        _isAdjustmentDetailMode = false; // 상세 모드 초기화
      } else {
        _bottomSheetController.reverse();
        _selectedAdjustmentType = null;
        _isAdjustmentDetailMode = false; // 상세 모드 초기화
      }
    });
  }

  void _closeBottomSheet() {
    setState(() {
      _isBottomSheetOpen = false;
      _isFiltering = false;
      _isCropping = false;
      _isAdjusting = false;
      _selectedFilter = FilterType.none;
      _selectedAdjustmentType = null;
      _isAdjustmentDetailMode = false; // 상세 모드 초기화
      _dragOffset = 0.0;
    });
    _bottomSheetController.reverse();
  }

  void _updateAdjustment(AdjustmentType type, double value) {
    setState(() {
      _adjustmentState = _adjustmentState.setValue(type, value);
    });
  }

  void _selectAdjustmentType(AdjustmentType type) {
    setState(() {
      _selectedAdjustmentType = type;
      _isAdjustmentDetailMode = true; // 상세 모드로 전환
    });
  }

  void _exitAdjustmentDetailMode() {
    setState(() {
      _isAdjustmentDetailMode = false;
      _selectedAdjustmentType = null;
    });
  }

  void _resetAllAdjustments() {
    setState(() {
      _adjustmentState = const ImageAdjustmentState();
      _selectedAdjustmentType = null;
      _isAdjustmentDetailMode = false; // 상세 모드 초기화
    });
  }

  void _toggleUI() {
    // 편집 모드가 아닐 때만 UI 토글 가능
    if (!_isBottomSheetOpen) {
      setState(() {
        _showUI = !_showUI;
      });
    }
  }

  void _onBottomSheetDragStart(DragStartDetails details) {
    // 드래그 시작 시 애니메이션 중지
    _bottomSheetController.stop();
  }

  void _onBottomSheetDragUpdate(DragUpdateDetails details) {
    setState(() {
      // 드래그 오프셋 업데이트 (아래로만 가능, 최대 bottomSheetHeight)
      _dragOffset = (_dragOffset + details.delta.dy).clamp(
        0.0,
        bottomSheetHeight,
      );

      // 애니메이션 값 직접 조정
      final progress = 1.0 - (_dragOffset / bottomSheetHeight);
      _bottomSheetController.value = progress;
    });
  }

  void _onBottomSheetDragEnd(DragEndDetails details) {
    // 드래그 속도 또는 위치에 따라 열림/닫힘 결정
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissThreshold = 200.0; // 150px 이상 내리면 닫기

    if (_dragOffset > dismissThreshold || velocity > 300) {
      // 닫기
      _closeBottomSheet();
    } else {
      // 다시 열기
      setState(() {
        _dragOffset = 0.0;
      });
      _bottomSheetController.forward();
    }
  }

  void _applyFilter(FilterType filterType) {
    setState(() {
      _selectedFilter = filterType;
    });
  }

  void _onFilterSwipe(DragUpdateDetails details) {
    // 스와이프 방향에 따라 필터 변경 (스냅 동작)
    final deltaX = details.delta.dx;
    if (deltaX.abs() > 20 && !_hasSwiped) {
      // 최소 스와이프 거리와 중복 방지
      _hasSwiped = true;

      final currentIndex = FilterPresets.defaults.indexWhere(
        (preset) => preset.type == _selectedFilter,
      );

      int newIndex;
      if (deltaX > 0) {
        // 오른쪽 스와이프 - 이전 필터
        newIndex =
            currentIndex > 0
                ? currentIndex - 1
                : FilterPresets.defaults.length - 1;
      } else {
        // 왼쪽 스와이프 - 다음 필터
        newIndex =
            currentIndex < FilterPresets.defaults.length - 1
                ? currentIndex + 1
                : 0;
      }

      setState(() {
        _selectedFilter = FilterPresets.defaults[newIndex].type;
      });
    }
  }

  void _onFilterSwipeEnd(DragEndDetails details) {
    // 스와이프 종료 시 상태 리셋
    _hasSwiped = false;
  }

  ColorFilter? _getColorFilter(FilterPreset preset) {
    return FilterUtils.getColorFilter(preset, intensity: _filterIntensity);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              key: ValueKey(_selectedFilter),
              colorFilter:
                  _getColorFilter(
                    FilterPresets.defaults.firstWhere(
                      (preset) => preset.type == _selectedFilter,
                      orElse: () => FilterPresets.defaults.first,
                    ),
                  ) ??
                  const ColorFilter.matrix([
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
              child: Image.memory(widget.imageBytes, fit: BoxFit.cover),
            ),
          ),
          // 글래스 블러 배경
          Positioned.fill(
            child: GestureDetector(
              onTap: _isCropping ? null : () => Navigator.pop(context),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.background.withOpacity(0.8),
                  ),
                ),
              ),
            ),
          ),

          // 이미지 컨테이너
          AnimatedBuilder(
            animation: _bottomSheetController,
            builder: (context, child) {
              return Positioned(
                left: 0,
                right: 0,
                top: -_imageScaleAnimation.value,
                bottom: 0,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: (!_isBottomSheetOpen && _showUI) ? 60.0 : 60.0,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        if (_isCropping) {
                                          _toggleCrop();
                                        } else if (_isFiltering) {
                                          _toggleFilter();
                                        } else if (_isAdjusting) {
                                          if (_isAdjustmentDetailMode) {
                                            _exitAdjustmentDetailMode();
                                          } else {
                                            _toggleAdjustment();
                                          }
                                        } else {
                                          Navigator.pop(context);
                                        }
                                      },
                                      icon: Icon(
                                        _isCropping ||
                                                _isFiltering ||
                                                (_isAdjusting &&
                                                    !_isAdjustmentDetailMode)
                                            ? null
                                            : Icons.close,
                                      ),
                                    ),
                                    // Undo/Redo 버튼 (편집 모드가 아닐 때만)
                                    if (!_isCropping &&
                                        !_isFiltering &&
                                        !_isAdjusting) ...[
                                      IconButton(
                                        onPressed:
                                            _history.length > 1 ? _undo : null,
                                        icon: Icon(
                                          Icons.undo,
                                          color:
                                              _history.length > 1
                                                  ? Colors.white
                                                  : Colors.white.withOpacity(
                                                    0.3,
                                                  ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed:
                                            _redoStack.isNotEmpty
                                                ? _redo
                                                : null,
                                        icon: Icon(
                                          Icons.redo,
                                          color:
                                              _redoStack.isNotEmpty
                                                  ? Colors.white
                                                  : Colors.white.withOpacity(
                                                    0.3,
                                                  ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                // 완료/적용 버튼 (바텀시트가 열렸을 때는 숨김)
                                if (!_isBottomSheetOpen)
                                  GestureDetector(
                                    onTap: _onDone,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: BackdropFilter(
                                        filter: ui.ImageFilter.blur(
                                          sigmaX: 10,
                                          sigmaY: 10,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                          child: const Text(
                                            '완료',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 이미지 미리보기
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _bottomSheetController,
                          builder: (context, child) {
                            return Transform.scale(
                              alignment: Alignment.topCenter,
                              scale: _imageScaleAnimation.value,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: GestureDetector(
                                        onTap: _toggleUI,
                                        onPanUpdate:
                                            _isFiltering
                                                ? _onFilterSwipe
                                                : null,
                                        onPanEnd:
                                            _isFiltering
                                                ? _onFilterSwipeEnd
                                                : null,

                                        child: Transform(
                                          transform:
                                              ImageAdjustmentUtils.getTransform(
                                                _adjustmentState,
                                              ),
                                          alignment: Alignment.center,
                                          child: ColorFiltered(
                                            key: ValueKey(
                                              '${_selectedFilter}_${_adjustmentState.hashCode}',
                                            ),
                                            colorFilter:
                                                // 조정과 필터를 결합 (조정이 우선)
                                                ImageAdjustmentUtils.getColorFilter(
                                                  _adjustmentState,
                                                ) ??
                                                _getColorFilter(
                                                  FilterPresets.defaults
                                                      .firstWhere(
                                                        (preset) =>
                                                            preset.type ==
                                                            _selectedFilter,
                                                        orElse:
                                                            () =>
                                                                FilterPresets
                                                                    .defaults
                                                                    .first,
                                                      ),
                                                ) ??
                                                const ColorFilter.matrix([
                                                  1,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  1,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  1,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  0,
                                                  1,
                                                  0,
                                                ]),
                                            child: Image.memory(
                                              _currentImage,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 자르기 오버레이
                                    if (_isCropping)
                                      FutureBuilder<Size>(
                                        key: ValueKey(_currentImage.hashCode),
                                        future: _getImageSize(),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            return CropOverlay(
                                              cropRect: _cropRect,
                                              onUpdate: _updateCropRect,
                                              imageSize: snapshot.data!,
                                              containerSize: Size(
                                                MediaQuery.of(
                                                      context,
                                                    ).size.width -
                                                    20,
                                                MediaQuery.of(
                                                      context,
                                                    ).size.height *
                                                    0.6,
                                              ),
                                              scale: _imageScaleAnimation.value,
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 메인 툴바
                      AnimatedOpacity(
                        opacity: _showUI ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ClipRRect(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    GlassToolButton(
                                      icon: Icons.tune,
                                      label: '조정',
                                      onTap: _toggleAdjustment,
                                      isActive: _isAdjusting,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                    GlassToolButton(
                                      icon: Icons.crop,
                                      label: '자르기',
                                      onTap: _toggleCrop,
                                      isActive: _isCropping,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                    GlassToolButton(
                                      icon: Icons.color_lens,
                                      label: '필터',
                                      onTap: _onFilter,
                                      isActive: _isFiltering,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          ),

          // 바텀시트
          if (_isBottomSheetOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanStart: _onBottomSheetDragStart,
                onPanUpdate: _onBottomSheetDragUpdate,
                onPanEnd: _onBottomSheetDragEnd,
                child: AnimatedBuilder(
                  animation: _bottomSheetAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                        0,
                        bottomSheetHeight * (1 - _bottomSheetAnimation.value),
                      ),
                      child: Container(
                        height: bottomSheetHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(30),
                            topRight: Radius.circular(30),
                          ),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            Container(
                              height: 4,
                              width: 80,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            // 상단: 뒤로가기 버튼
                            const SizedBox(height: 12),
                            // 바텀시트 내용
                            Expanded(
                              child:
                                  _isCropping
                                      ? _buildCropBottomSheet()
                                      : _isFiltering
                                      ? _buildFilterBottomSheet()
                                      : _buildAdjustmentBottomSheet(),
                            ),
                            if (!_isAdjustmentDetailMode)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 8.0,
                                  right: 8.0,
                                  bottom: 30.0,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        _closeBottomSheet();
                                      },
                                      style: ElevatedButton.styleFrom(),
                                      child: Text(
                                        '취소',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _isCropping
                                          ? '자르기'
                                          : _isFiltering
                                          ? '필터'
                                          : '조정',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.7),
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        if (_isCropping) {
                                          _applyCrop();
                                        } else if (_isFiltering) {
                                          _toggleFilter();
                                        } else if (_isAdjusting) {
                                          _toggleAdjustment();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(),
                                      child: Text(
                                        _isCropping ? '적용' : '완료',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCropBottomSheet() {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 10, bottom: 40),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              CropAspectRatioUtils.allRatios.map((ratio) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: RatioChip(
                    label: CropAspectRatioUtils.getLabel(ratio),
                    isSelected: _selectedRatio == ratio,
                    onTap: () => _applyAspectRatio(ratio),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterBottomSheet() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 10, bottom: 40),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              FilterPresets.defaults.map((preset) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChipWidget(
                    preset: preset,
                    isSelected: _selectedFilter == preset.type,
                    onTap: () => _applyFilter(preset.type),
                    imageBytes: _currentImage,
                    getColorFilter: _getColorFilter,
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildAdjustmentBottomSheet() {
    if (_isAdjustmentDetailMode && _selectedAdjustmentType != null) {
      // 상세 모드: 선택된 조정 타입의 슬라이더만 표시
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    _exitAdjustmentDetailMode();
                  },
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white.withOpacity(0.7),
                    size: 18,
                  ),
                ),
                Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 14, top: 4),
                  child: Text(
                    AdjustmentTypeUtils.getLabel(_selectedAdjustmentType!),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AdjustmentSlider(
              type: _selectedAdjustmentType!,
              value: _adjustmentState.getValue(_selectedAdjustmentType!),
              onChanged: (value) {
                _updateAdjustment(_selectedAdjustmentType!, value);
              },
              onReset: () {
                _updateAdjustment(_selectedAdjustmentType!, 0.0);
              },
            ),
          ),
        ],
      );
    } else {
      // 일반 모드: 조정 타입 선택 칩들만 표시
      return SizedBox(
        height: 100,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // 전체 리셋 버튼

              // 조정 타입 칩들
              ...AdjustmentTypeUtils.allTypes.map((type) {
                final hasValue = _adjustmentState.getValue(type) != 0.0;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdjustmentChip(
                    type: type,
                    isSelected: _selectedAdjustmentType == type,
                    onTap: () => _selectAdjustmentType(type),
                    hasValue: hasValue,
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      );
    }
  }
}
