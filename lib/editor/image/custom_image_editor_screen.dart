import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

// Services
import 'package:doppy/editor/service/node_component_service.dart';

// Models
import 'package:doppy/editor/image/models/filter_preset.dart';
import 'package:doppy/editor/image/models/crop_aspect_ratio.dart';
import 'package:doppy/editor/image/models/image_adjustment.dart';
import 'package:doppy/editor/image/models/text_overlay_model.dart';

// Widgets
import 'package:doppy/editor/image/widgets/crop_overlay.dart';
import 'package:doppy/editor/image/widgets/editor_tool_button.dart';
import 'package:doppy/editor/image/widgets/ratio_chip.dart';
import 'package:doppy/editor/image/widgets/filter_chip.dart';
import 'package:doppy/editor/image/widgets/adjustment_chip.dart';
import 'package:doppy/editor/image/widgets/adjustment_slider.dart';
import 'package:doppy/editor/image/widgets/text_overlay_editor.dart';
import 'package:doppy/editor/style/font_catalog.dart';

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
  int? _imageHeightPixels; // 이미지 세로 픽셀
  late Future<int?> _imageHeightFuture; // 이미지 높이 계산 Future

  // 필터 관련
  FilterType _selectedFilter = FilterType.none;
  double _filterIntensity = 1.0;
  bool _hasSwiped = false; // 스와이프 상태 추적

  // 조정 관련
  ImageAdjustmentState _adjustmentState = const ImageAdjustmentState();
  ImageAdjustmentState _savedAdjustmentState =
      const ImageAdjustmentState(); // 조정 모드 진입 시점의 상태 저장
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

  // 텍스트 오버레이 관련
  bool _isAddingText = false;
  List<TextOverlayData> _textOverlays = [];
  // 텍스트 드래그/삭제 상태
  String? _draggingOverlayId;
  Offset _dragFingerDeltaGlobal = Offset.zero;

  bool _showTrashBin = false;
  bool _isOverTrash = false;
  final GlobalKey _trashKey = GlobalKey();
  final GlobalKey _imageAreaKey = GlobalKey();
  // 텍스트 스케일(핀치줌)
  String? _scalingOverlayId;
  double _initialScaleFontSize = 0.0;

  // Undo/Redo 스택
  final List<Uint8List> _history = [];
  final List<Uint8List> _redoStack = [];

  @override
  void initState() {
    _currentImage = widget.imageBytes;
    _history.add(widget.imageBytes); // 초기 이미지 저장

    // 이미지 세로 픽셀 계산 Future 초기화
    _imageHeightFuture = _calculateImageHeightPixels();

    // 애니메이션 컨트롤러 초기화
    _bottomSheetController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _bottomSheetAnimation = CurvedAnimation(
      parent: _bottomSheetController,
      curve: Curves.easeInOut,
    );

    // 이미지 높이에 따른 동적 축소 비율 계산
    final scaleEnd = _calculateDynamicScale();
    _imageScaleAnimation = Tween<double>(begin: 1.0, end: scaleEnd).animate(
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

  Future<int?> _calculateImageHeightPixels() async {
    try {
      final codec = await ui.instantiateImageCodec(_currentImage);
      final frame = await codec.getNextFrame();
      _imageHeightPixels = frame.image.height;
      final scale = _calculateDynamicScale();
      print(
        '이미지 세로 픽셀: $_imageHeightPixels, 축소 비율: ${(scale * 100).toStringAsFixed(1)}%',
      );
      return _imageHeightPixels;
    } catch (e) {
      print('이미지 세로 픽셀 계산 오류: $e');
      _imageHeightPixels = null;
      return null;
    }
  }

  double _calculateDynamicScale() {
    if (_imageHeightPixels == null) return 0.96; // 기본값

    final height = _imageHeightPixels!;
    print('이미지 높이: $height');

    // 이미지 높이에 따른 축소 비율 계산 (더 급격한 축소)
    if (height >= 2000) {
      // 짧은 이미지 (500px 이하) - 약간 축소
      return 0.7;
    } else if (height >= 1000) {
      return 0.8;
    } else {
      return 0.96;
    }
  }

  void _saveToHistory() {
    _history.add(_currentImage);
    _redoStack.clear(); // 새로운 작업 시 redo 스택 초기화
    if (_history.length > 20) {
      _history.removeAt(0); // 메모리 관리를 위해 20개로 제한
    }
    // 이미지가 변경될 때마다 세로 픽셀 재계산 및 축소 비율 업데이트
    _imageHeightFuture = _calculateImageHeightPixels();
    _updateImageScaleAnimation();
  }

  void _updateImageScaleAnimation() {
    final scaleEnd = _calculateDynamicScale();
    _imageScaleAnimation = Tween<double>(begin: 1.0, end: scaleEnd).animate(
      CurvedAnimation(parent: _bottomSheetController, curve: Curves.easeInOut),
    );
  }

  double _getCurrentScale() {
    if (!_isBottomSheetOpen) return 1.0;

    final scaleEnd = _calculateDynamicScale();
    final progress = _bottomSheetController.value;

    // 1.0에서 scaleEnd로 애니메이션
    return 1.0 + (scaleEnd - 1.0) * progress;
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
        _isBottomSheetOpen = false; // 바텀시트 닫기
        _cropRect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8); // 리셋
        _selectedRatio = CropAspectRatio.free; // 비율 리셋
      });

      // 바텀시트 애니메이션 닫기
      _bottomSheetController.reverse();
    } catch (e) {
      print('자르기 오류: $e');
    }
  }

  void _onFilter() {
    _toggleFilter();
  }

  Future<void> _onDone() async {
    // 텍스트 오버레이 정보와 함께 편집 결과 반환
    final result = {
      'image': _currentImage,
      'textOverlays': _textOverlays,
      'adjustments': _adjustmentState,
      'filter': _selectedFilter,
      'cropRect': _isCropping ? _cropRect : null,
    };

    // 편집 결과를 ImageService에 반영. 선택된 이미지가 존재하는 경우에만.
    final imageService = context.read<NodeComponentService>();
    final selectedId = imageService.selectedImageId;
    if (selectedId != null) {
      imageService.applyEditedBytes(nodeId: selectedId, bytes: _currentImage);
    }
    Navigator.pop(context, result);
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
        // 조정 모드 진입 시 현재 상태 저장
        _savedAdjustmentState = _adjustmentState;
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

  void _cancelAdjustment() {
    setState(() {
      // 저장된 상태로 복원
      _adjustmentState = _savedAdjustmentState;
      _isAdjusting = false;
      _isBottomSheetOpen = false;
      _selectedAdjustmentType = null;
      _isAdjustmentDetailMode = false;
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

  void _toggleUI() {
    // 편집 모드가 아닐 때만 UI 토글 가능
    if (!_isBottomSheetOpen) {
      setState(() {
        _showUI = !_showUI;
      });
    }
  }

  void _toggleTextOverlay() {
    setState(() {
      _isAddingText = !_isAddingText;
      // 텍스트 오버레이 모드일 때 UI 숨김
      if (_isAddingText) {
        _showUI = false;
      } else {
        _showUI = true;
      }
    });
  }

  void _updateTextOverlays(List<TextOverlayData> overlays) {
    setState(() {
      _textOverlays = overlays;
    });
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
    print('이미지 높1이: $_imageHeightPixels');
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
                    ).colorScheme.background.withOpacity(1),
                  ),
                ),
              ),
            ),
          ),

          // 이미지 컨테이너
          FutureBuilder<int?>(
            future: _imageHeightFuture,
            builder: (context, snapshot) {
              return AnimatedBuilder(
                animation: _bottomSheetController,
                builder: (context, child) {
                  return Positioned(
                    left: 0,
                    right: 0,
                    top: 10,
                    bottom: 0,
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 이미지 미리보기
                          Expanded(
                            child: AnimatedBuilder(
                              animation: _bottomSheetController,
                              builder: (context, child) {
                                return Transform.scale(
                                  alignment: Alignment.topCenter,
                                  scale: _getCurrentScale(),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 50),
                                    child: Stack(
                                      children: [
                                        // 메인 이미지
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
                                            child: ColorFiltered(
                                              key: ValueKey(
                                                '${_selectedFilter}_${_adjustmentState.hashCode}',
                                              ),
                                              colorFilter:
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
                                              child: KeyedSubtree(
                                                key: _imageAreaKey,
                                                child: Image.memory(
                                                  _currentImage,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                        // 텍스트 오버레이 표시
                                        if (!_isAddingText &&
                                            _textOverlays.isNotEmpty)
                                          FutureBuilder<Size>(
                                            future: _getImageSize(),
                                            builder: (
                                              context,
                                              imageSizeSnapshot,
                                            ) {
                                              if (!imageSizeSnapshot.hasData) {
                                                return const SizedBox.shrink();
                                              }

                                              return LayoutBuilder(
                                                builder: (
                                                  context,
                                                  constraints,
                                                ) {
                                                  final containerSize = Size(
                                                    constraints.maxWidth,
                                                    constraints.maxHeight,
                                                  );

                                                  // 이미지의 실제 크기
                                                  final imageSize =
                                                      imageSizeSnapshot.data!;

                                                  // 이미지가 화면에 표시되는 크기 계산
                                                  final imageAspectRatio =
                                                      imageSize.width /
                                                      imageSize.height;
                                                  final containerAspectRatio =
                                                      containerSize.width /
                                                      containerSize.height;

                                                  late Size displaySize;
                                                  late Offset imageOffset;

                                                  if (imageAspectRatio >
                                                      containerAspectRatio) {
                                                    // 이미지가 더 넓음 - 너비에 맞춤
                                                    displaySize = Size(
                                                      containerSize.width,
                                                      containerSize.width /
                                                          imageAspectRatio,
                                                    );
                                                    imageOffset = Offset(
                                                      0,
                                                      (containerSize.height -
                                                              displaySize
                                                                  .height) /
                                                          2,
                                                    );
                                                  } else {
                                                    // 이미지가 더 높음 - 높이에 맞춤
                                                    displaySize = Size(
                                                      containerSize.height *
                                                          imageAspectRatio,
                                                      containerSize.height,
                                                    );
                                                    imageOffset = Offset(
                                                      (containerSize.width -
                                                              displaySize
                                                                  .width) /
                                                          2,
                                                      0,
                                                    );
                                                  }

                                                  return Stack(
                                                    children: [
                                                      ..._textOverlays.map((
                                                        overlay,
                                                      ) {
                                                        // 실제 텍스트 크기 측정 (정확한 경계 계산)
                                                        TextStyle style;
                                                        final item =
                                                            overlay.fontIdentifier !=
                                                                    null
                                                                ? FontCatalog.findByIdentifier(
                                                                  overlay
                                                                      .fontIdentifier!,
                                                                )
                                                                : null;
                                                        if (item != null) {
                                                          style = item.getTextStyle(
                                                            fontWeight:
                                                                overlay
                                                                    .fontWeight,
                                                            fontSize:
                                                                overlay
                                                                    .fontSize,
                                                            color:
                                                                overlay
                                                                    .textColor,
                                                          );
                                                        } else {
                                                          style = TextStyle(
                                                            color:
                                                                overlay
                                                                    .textColor,
                                                            fontSize:
                                                                overlay
                                                                    .fontSize,
                                                            fontWeight:
                                                                overlay
                                                                    .fontWeight,
                                                          );
                                                        }
                                                        final tp = TextPainter(
                                                          text: TextSpan(
                                                            text: overlay.text,
                                                            style: style,
                                                          ),
                                                          textDirection:
                                                              TextDirection.ltr,
                                                          maxLines: null,
                                                          textHeightBehavior:
                                                              const TextHeightBehavior(
                                                                applyHeightToFirstAscent:
                                                                    false,
                                                                applyHeightToLastDescent:
                                                                    false,
                                                              ),
                                                        )..layout(
                                                          maxWidth:
                                                              displaySize.width,
                                                        );
                                                        final double padH =
                                                            overlay.backgroundColor !=
                                                                    null
                                                                ? 16
                                                                : 0;
                                                        final double padV =
                                                            overlay.backgroundColor !=
                                                                    null
                                                                ? 8
                                                                : 0;
                                                        final double textWidth =
                                                            tp.width + padH * 2;
                                                        final double
                                                        textHeight =
                                                            tp.height +
                                                            padV * 2;
                                                        // 큰 폰트/여러 줄에서 하방 치우침 보정
                                                        const double
                                                        verticalBias = 0.0;

                                                        // 이미지 내에서의 상대적 위치를 실제 화면 좌표로 변환 (좌상단 기준)
                                                        final relativeX =
                                                            overlay.position.dx;
                                                        final relativeY =
                                                            overlay.position.dy;
                                                        final absoluteX =
                                                            imageOffset.dx +
                                                            (relativeX *
                                                                displaySize
                                                                    .width);
                                                        final absoluteY =
                                                            imageOffset.dy +
                                                            (relativeY *
                                                                displaySize
                                                                    .height) -
                                                            verticalBias;

                                                        final minLeft =
                                                            imageOffset.dx;
                                                        final double
                                                        maxLeftRaw =
                                                            imageOffset.dx +
                                                            displaySize.width -
                                                            textWidth;
                                                        final maxLeft =
                                                            maxLeftRaw < minLeft
                                                                ? minLeft
                                                                : maxLeftRaw;
                                                        final minTop =
                                                            imageOffset.dy;
                                                        final double maxTopRaw =
                                                            imageOffset.dy +
                                                            displaySize.height -
                                                            textHeight;
                                                        final maxTop =
                                                            maxTopRaw < minTop
                                                                ? minTop
                                                                : maxTopRaw;

                                                        final left =
                                                            absoluteX
                                                                .clamp(
                                                                  minLeft,
                                                                  maxLeft,
                                                                )
                                                                .toDouble();
                                                        final top =
                                                            absoluteY
                                                                .clamp(
                                                                  minTop,
                                                                  maxTop,
                                                                )
                                                                .toDouble();

                                                        return Positioned(
                                                          left: left,
                                                          top: top,
                                                          child: GestureDetector(
                                                            onTap: () {
                                                              setState(() {
                                                                _isAddingText =
                                                                    true;
                                                              });
                                                            },
                                                            onPanStart: null,
                                                            onScaleStart: (
                                                              details,
                                                            ) {
                                                              _scalingOverlayId =
                                                                  overlay.id;
                                                              _initialScaleFontSize =
                                                                  overlay
                                                                      .fontSize;
                                                              _draggingOverlayId =
                                                                  overlay.id;
                                                              // 손가락-텍스트 좌상단 델타(글로벌) 저장
                                                              final RenderBox?
                                                              imageBox =
                                                                  _imageAreaKey
                                                                          .currentContext
                                                                          ?.findRenderObject()
                                                                      as RenderBox?;
                                                              final Offset
                                                              imageGlobalTopLeft =
                                                                  imageBox
                                                                      ?.localToGlobal(
                                                                        Offset
                                                                            .zero,
                                                                      ) ??
                                                                  (context.findRenderObject()
                                                                              as RenderBox)
                                                                          .localToGlobal(Offset.zero) +
                                                                      imageOffset;
                                                              final Offset
                                                              textTopLeftGlobalAtStart =
                                                                  imageGlobalTopLeft +
                                                                  Offset(
                                                                    overlay
                                                                            .position
                                                                            .dx *
                                                                        displaySize
                                                                            .width,
                                                                    overlay
                                                                            .position
                                                                            .dy *
                                                                        displaySize
                                                                            .height,
                                                                  );
                                                              _dragFingerDeltaGlobal =
                                                                  details
                                                                      .focalPoint -
                                                                  textTopLeftGlobalAtStart;
                                                              _showTrashBin =
                                                                  true;
                                                              _isOverTrash =
                                                                  false;
                                                              setState(() {});
                                                            },
                                                            onScaleUpdate: (
                                                              details,
                                                            ) {
                                                              // 2손가락 이상 + 스케일 변화 → 폰트 크기 변경
                                                              if (_scalingOverlayId ==
                                                                      overlay
                                                                          .id &&
                                                                  details.pointerCount >=
                                                                      2 &&
                                                                  (details.scale -
                                                                              1.0)
                                                                          .abs() >
                                                                      0.01) {
                                                                // 새 폰트 크기 계산 및 영역 검증
                                                                final proposed =
                                                                    (_initialScaleFontSize *
                                                                            details.scale)
                                                                        .clamp(
                                                                          8.0,
                                                                          300.0,
                                                                        );
                                                                final tpScaled = TextPainter(
                                                                  text: TextSpan(
                                                                    text:
                                                                        overlay
                                                                            .text,
                                                                    style: style
                                                                        .copyWith(
                                                                          fontSize:
                                                                              proposed,
                                                                        ),
                                                                  ),
                                                                  textDirection:
                                                                      TextDirection
                                                                          .ltr,
                                                                  maxLines:
                                                                      null,
                                                                  textHeightBehavior: const TextHeightBehavior(
                                                                    applyHeightToFirstAscent:
                                                                        false,
                                                                    applyHeightToLastDescent:
                                                                        false,
                                                                  ),
                                                                )..layout();
                                                                final sw =
                                                                    tpScaled
                                                                        .width +
                                                                    padH * 2;
                                                                final sh =
                                                                    tpScaled
                                                                        .height +
                                                                    padV * 2;
                                                                // 스케일 시 텍스트가 이미지보다 커지는 경우 방지
                                                                double target =
                                                                    proposed
                                                                        .toDouble();
                                                                if (sw >
                                                                        displaySize
                                                                            .width ||
                                                                    sh >
                                                                        displaySize
                                                                            .height) {
                                                                  final widthScale =
                                                                      displaySize
                                                                          .width /
                                                                      sw;
                                                                  final heightScale =
                                                                      displaySize
                                                                          .height /
                                                                      sh;
                                                                  final safeScale = (widthScale <
                                                                              heightScale
                                                                          ? widthScale
                                                                          : heightScale)
                                                                      .clamp(
                                                                        0.1,
                                                                        1.0,
                                                                      );
                                                                  target = (_initialScaleFontSize *
                                                                          safeScale)
                                                                      .clamp(
                                                                        8.0,
                                                                        300.0,
                                                                      );
                                                                }
                                                                final updated = List<
                                                                  TextOverlayData
                                                                >.from(
                                                                  _textOverlays,
                                                                );
                                                                final idx = updated
                                                                    .indexWhere(
                                                                      (e) =>
                                                                          e.id ==
                                                                          overlay
                                                                              .id,
                                                                    );
                                                                if (idx != -1) {
                                                                  updated[idx] =
                                                                      overlay.copyWith(
                                                                        fontSize:
                                                                            target,
                                                                      );
                                                                  _updateTextOverlays(
                                                                    updated,
                                                                  );
                                                                }
                                                                return;
                                                              }

                                                              // 1손가락 드래그 → 위치 변경
                                                              // 글로벌 좌표 기준: 실제 이미지 위젯의 글로벌 좌상단/우하단을 직접 사용
                                                              final RenderBox?
                                                              imageBox =
                                                                  _imageAreaKey
                                                                          .currentContext
                                                                          ?.findRenderObject()
                                                                      as RenderBox?;
                                                              final Offset
                                                              imageGlobalTopLeft =
                                                                  imageBox
                                                                      ?.localToGlobal(
                                                                        Offset
                                                                            .zero,
                                                                      ) ??
                                                                  (context.findRenderObject()
                                                                              as RenderBox)
                                                                          .localToGlobal(Offset.zero) +
                                                                      imageOffset;

                                                              // 휴지통 hover 판정
                                                              final Offset
                                                              fingerGlobal =
                                                                  details
                                                                      .focalPoint;
                                                              final RenderObject?
                                                              trashObj =
                                                                  _trashKey
                                                                      .currentContext
                                                                      ?.findRenderObject();
                                                              if (trashObj
                                                                  is RenderBox) {
                                                                final Offset
                                                                trashTopLeft = trashObj
                                                                    .localToGlobal(
                                                                      Offset
                                                                          .zero,
                                                                    );
                                                                final Size
                                                                trashSize =
                                                                    trashObj
                                                                        .size;
                                                                _isOverTrash =
                                                                    Rect.fromLTWH(
                                                                      trashTopLeft
                                                                          .dx,
                                                                      trashTopLeft
                                                                          .dy,
                                                                      trashSize
                                                                          .width,
                                                                      trashSize
                                                                          .height,
                                                                    ).contains(
                                                                      fingerGlobal,
                                                                    );
                                                              } else {
                                                                _isOverTrash =
                                                                    false;
                                                              }

                                                              final Offset
                                                              textTopLeftGlobal =
                                                                  fingerGlobal -
                                                                  _dragFingerDeltaGlobal;
                                                              final tpDrag = TextPainter(
                                                                text: TextSpan(
                                                                  text:
                                                                      overlay
                                                                          .text,
                                                                  style: style,
                                                                ),
                                                                textDirection:
                                                                    TextDirection
                                                                        .ltr,
                                                                maxLines: null,
                                                                textHeightBehavior:
                                                                    const TextHeightBehavior(
                                                                      applyHeightToFirstAscent:
                                                                          false,
                                                                      applyHeightToLastDescent:
                                                                          false,
                                                                    ),
                                                              )..layout(
                                                                maxWidth:
                                                                    displaySize
                                                                        .width,
                                                              );
                                                              final double w =
                                                                  tpDrag.width +
                                                                  padH * 2;
                                                              final double h =
                                                                  tpDrag
                                                                      .height +
                                                                  padV * 2;
                                                              const double
                                                              verticalBiasDrag =
                                                                  0.0;

                                                              // 좌상단 기준 비율로 직접 계산 (손가락과 동일 좌표계)
                                                              final double
                                                              relXRaw =
                                                                  (textTopLeftGlobal
                                                                          .dx -
                                                                      imageGlobalTopLeft
                                                                          .dx) /
                                                                  displaySize
                                                                      .width;
                                                              final double
                                                              relYRaw =
                                                                  (textTopLeftGlobal
                                                                          .dy -
                                                                      imageGlobalTopLeft
                                                                          .dy) /
                                                                  displaySize
                                                                      .height;
                                                              final double
                                                              rawMaxRelX =
                                                                  (displaySize
                                                                          .width -
                                                                      w) /
                                                                  displaySize
                                                                      .width;
                                                              final double
                                                              rawMaxRelY =
                                                                  (displaySize
                                                                          .height -
                                                                      h) /
                                                                  displaySize
                                                                      .height;
                                                              final double
                                                              maxRelX =
                                                                  rawMaxRelX <
                                                                          0.0
                                                                      ? 0.0
                                                                      : (rawMaxRelX >
                                                                              1.0
                                                                          ? 1.0
                                                                          : rawMaxRelX);
                                                              final double
                                                              maxRelY =
                                                                  rawMaxRelY <
                                                                          0.0
                                                                      ? 0.0
                                                                      : (rawMaxRelY >
                                                                              1.0
                                                                          ? 1.0
                                                                          : rawMaxRelY);
                                                              final double
                                                              relX = (relXRaw)
                                                                  .clamp(
                                                                    0.0,
                                                                    maxRelX,
                                                                  );
                                                              final double
                                                              relY = (relYRaw)
                                                                  .clamp(
                                                                    0.0,
                                                                    maxRelY,
                                                                  );

                                                              final updatedOverlays =
                                                                  List<
                                                                    TextOverlayData
                                                                  >.from(
                                                                    _textOverlays,
                                                                  );
                                                              final index = updatedOverlays
                                                                  .indexWhere(
                                                                    (e) =>
                                                                        e.id ==
                                                                        overlay
                                                                            .id,
                                                                  );
                                                              if (index != -1) {
                                                                updatedOverlays[index] =
                                                                    overlay.copyWith(
                                                                      position:
                                                                          Offset(
                                                                            relX,
                                                                            relY,
                                                                          ),
                                                                    );
                                                                _updateTextOverlays(
                                                                  updatedOverlays,
                                                                );
                                                              }
                                                              setState(() {});
                                                            },
                                                            onScaleEnd: (_) {
                                                              if (_isOverTrash &&
                                                                  _draggingOverlayId !=
                                                                      null) {
                                                                final updated = List<
                                                                  TextOverlayData
                                                                >.from(
                                                                  _textOverlays,
                                                                )..removeWhere(
                                                                  (e) =>
                                                                      e.id ==
                                                                      _draggingOverlayId,
                                                                );
                                                                _updateTextOverlays(
                                                                  updated,
                                                                );
                                                              }
                                                              _scalingOverlayId =
                                                                  null;
                                                              _draggingOverlayId =
                                                                  null;
                                                              _showTrashBin =
                                                                  false;
                                                              _isOverTrash =
                                                                  false;
                                                              setState(() {});
                                                            },
                                                            child: Container(
                                                              padding: EdgeInsets.symmetric(
                                                                horizontal:
                                                                    overlay.backgroundColor !=
                                                                            null
                                                                        ? 16
                                                                        : 0,
                                                                vertical:
                                                                    overlay.backgroundColor !=
                                                                            null
                                                                        ? 8
                                                                        : 0,
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    overlay
                                                                        .backgroundColor,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                overlay.text,
                                                                textAlign:
                                                                    overlay
                                                                        .textAlign,
                                                                softWrap: false,
                                                                textHeightBehavior:
                                                                    const TextHeightBehavior(
                                                                      applyHeightToFirstAscent:
                                                                          false,
                                                                      applyHeightToLastDescent:
                                                                          false,
                                                                    ),
                                                                style:
                                                                    (() {
                                                                      // Google Fonts 적용
                                                                      if (overlay
                                                                              .fontIdentifier !=
                                                                          null) {
                                                                        final item = FontCatalog.findByIdentifier(
                                                                          overlay
                                                                              .fontIdentifier!,
                                                                        );
                                                                        if (item !=
                                                                            null) {
                                                                          return item.getTextStyle(
                                                                            fontWeight:
                                                                                overlay.fontWeight,
                                                                            fontSize:
                                                                                overlay.fontSize,
                                                                            color:
                                                                                overlay.textColor,
                                                                          );
                                                                        }
                                                                      }
                                                                      return TextStyle(
                                                                        color:
                                                                            overlay.textColor,
                                                                        fontSize:
                                                                            overlay.fontSize,
                                                                        fontWeight:
                                                                            overlay.fontWeight,
                                                                        shadows: [
                                                                          if (overlay.backgroundColor ==
                                                                              null)
                                                                            const Shadow(
                                                                              color:
                                                                                  Colors.black54,
                                                                              offset: Offset(
                                                                                0,
                                                                                2,
                                                                              ),
                                                                              blurRadius:
                                                                                  4,
                                                                            ),
                                                                        ],
                                                                      );
                                                                    })(),
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      }).toList(),

                                                      // 드래그 중 휴지통: 이미지 영역 내부 하단 중앙
                                                      if (_showTrashBin)
                                                        Positioned(
                                                          left:
                                                              imageOffset.dx +
                                                              (displaySize.width -
                                                                      (_isOverTrash
                                                                          ? 74
                                                                          : 64)) /
                                                                  2,
                                                          top:
                                                              imageOffset.dy +
                                                              displaySize
                                                                  .height -
                                                              (_isOverTrash
                                                                  ? 74
                                                                  : 64) -
                                                              12,
                                                          child: AnimatedContainer(
                                                            key: _trashKey,
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      120,
                                                                ),
                                                            width:
                                                                _isOverTrash
                                                                    ? 74
                                                                    : 64,
                                                            height:
                                                                _isOverTrash
                                                                    ? 74
                                                                    : 64,
                                                            decoration: BoxDecoration(
                                                              color: (_isOverTrash
                                                                      ? Colors
                                                                          .redAccent
                                                                      : Colors
                                                                          .black)
                                                                  .withOpacity(
                                                                    0.8,
                                                                  ),
                                                              shape:
                                                                  BoxShape
                                                                      .circle,
                                                            ),
                                                            child: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              color:
                                                                  Colors.white,
                                                              size: 30,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                          ),

                                        // 자르기 오버레이
                                        if (_isCropping)
                                          FutureBuilder<Size>(
                                            key: ValueKey(
                                              _currentImage.hashCode,
                                            ),
                                            future: _getImageSize(),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasData) {
                                                return CropOverlay(
                                                  cropRect: _cropRect,
                                                  onUpdate: _updateCropRect,
                                                  imageSize: snapshot.data!,
                                                  scale: _getCurrentScale(),
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

                          // 텍스트 오버레이 모드가 아닐 때만 하단 툴바 표시
                          AnimatedOpacity(
                            opacity: _showUI ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 0),
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
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
                                          icon: Icons.text_fields,
                                          label: '텍스트',
                                          onTap: _toggleTextOverlay,
                                          isActive: _isAddingText,
                                        ),
                                        Container(
                                          width: 1,
                                          height: 40,
                                          color: Colors.white.withOpacity(0.2),
                                        ),
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
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // 텍스트 오버레이 모드가 아닐 때만 상단 앱바 표시
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0,
              duration: const Duration(milliseconds: 200),
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
                                      (_isAdjusting && !_isAdjustmentDetailMode)
                                  ? null
                                  : Icons.close,
                            ),
                          ),
                          // Undo/Redo 버튼 (편집 모드가 아닐 때만)
                          if (!_isCropping &&
                              !_isFiltering &&
                              !_isAdjusting) ...[
                            GestureDetector(
                              onTap: _history.length > 1 ? _undo : null,
                              child: SvgPicture.asset(
                                'assets/icons/editor_undo.svg',
                                width: 24,
                                height: 24,
                                color:
                                    _history.length > 1
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                              ),
                            ),
                            GestureDetector(
                              onTap: _redoStack.isNotEmpty ? _redo : null,
                              child: SvgPicture.asset(
                                'assets/icons/editor_redo.svg',
                                width: 24,
                                height: 24,
                                color:
                                    _redoStack.isNotEmpty
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // 완료/적용 버튼 (바텀시트가 열렸을 때는 숨김)
                      if (!_isBottomSheetOpen)
                        GestureDetector(
                          onTap: _onDone,
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
                    ],
                  ),
                ),
              ),
            ),
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
                                        if (_isAdjusting) {
                                          _cancelAdjustment();
                                        } else {
                                          _closeBottomSheet();
                                        }
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
          // 텍스트 오버레이 편집 모드 (입력 영역을 약간 위로, 내부 스크롤 방지용 최대 크기 전달)
          if (_isAddingText)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (c, constraints) {
                  // 이미지 표시 영역 추정 (캐시가 있으면 더욱 정확)
                  final containerSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  Size displaySize;
                  if (_cachedImageSize == null) {
                    displaySize = containerSize;
                  } else {
                    final imgAR =
                        _cachedImageSize!.width / _cachedImageSize!.height;
                    final contAR = containerSize.width / containerSize.height;
                    if (imgAR > contAR) {
                      displaySize = Size(
                        containerSize.width,
                        containerSize.width / imgAR,
                      );
                    } else {
                      displaySize = Size(
                        containerSize.height * imgAR,
                        containerSize.height,
                      );
                    }
                  }

                  return TextOverlayEditor(
                    textOverlays: _textOverlays,
                    onTextOverlaysChanged: _updateTextOverlays,
                    imageBytes: _currentImage,
                    imageSize: _cachedImageSize,
                    maxTextWidth: displaySize.width,
                    maxTextHeight: displaySize.height * 0.8,
                    onFinish: () {
                      setState(() {
                        _isAddingText = false;
                        _showUI = true; // UI 다시 보이게 하기
                      });
                    },
                  );
                },
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
              // 전체 리셋 버튼z

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
