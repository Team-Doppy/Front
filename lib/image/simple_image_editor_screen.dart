import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'crop_editor.dart';

/// 간단한 커스텀 이미지 편집 화면
/// 바텀시트 기반 UI, Undo/Redo, 실시간 미리보기 제공
class SimpleImageEditorScreen extends StatefulWidget {
  const SimpleImageEditorScreen({
    super.key,
    this.imageBytes,
    this.imageBytesList,
  }) : assert(
         imageBytes != null || imageBytesList != null,
         'imageBytes 또는 imageBytesList 중 하나는 필수입니다.',
       );

  final Uint8List? imageBytes;
  final List<Uint8List>? imageBytesList;

  @override
  State<SimpleImageEditorScreen> createState() =>
      _SimpleImageEditorScreenState();
}

enum _EditMode { none, crop, adjust, filter }

// 이미지별 편집 상태
class _ImageEditState {
  // 회전 관련 상태
  int rotation = 0;

  // 자르기 관련 상태
  String? selectedAspectRatio; // null = 자유, '1:1', '4:5', '16:9' 등
  final CropState cropState = CropState(); // 크롭 상태 관리

  // 보정 관련 상태
  double brightness = 0.0; // -100 ~ 100
  double contrast = 0.0; // -100 ~ 100
  double saturation = 0.0; // -100 ~ 100
  double warmth = 0.0; // -100 ~ 100

  // 필터 관련 상태
  FilterType selectedFilter = FilterType.none;
  double filterIntensity = 1.0;

  // 이미지 이동 및 스케일 관련 상태
  Offset imageOffset = Offset.zero;
  double imageScale = 1.0;
}

enum FilterType { none, clear, lucent, bright, tender }

class _SimpleImageEditorScreenState extends State<SimpleImageEditorScreen>
    with TickerProviderStateMixin {
  late final List<Uint8List> _images;
  late final PageController _pageController;
  int _currentIndex = 0;
  _EditMode _editMode = _EditMode.none;
  final Map<int, Uint8List> _editedImages = {};
  final Map<int, ui.Image?> _uiImageCache = {};
  static const int _maxImageCacheSize = 10; // 최대 UI 이미지 캐시 크기

  // 이미지별 편집 상태 관리
  final Map<int, _ImageEditState> _imageEditStates = {};

  // Undo/Redo 스택 (이미지별) - 최대 20개로 제한됨
  final Map<int, List<Uint8List>> _history = {};
  final Map<int, List<Uint8List>> _redoStack = {};

  // 바텀시트 관련
  bool _isBottomSheetOpen = false;
  late AnimationController _bottomSheetController;
  late Animation<double> _bottomSheetAnimation;
  double _dragOffset = 0.0;

  // 옵션별 바텀시트 높이 (간격을 줄이기 위해 높이 감소)
  double get bottomSheetHeight {
    switch (_editMode) {
      case _EditMode.crop:
        return 200; // 크롭: 가로 스크롤 옵션 (간격 줄임)
      case _EditMode.filter:
        return 250; // 필터: 가로 스크롤 필터 미리보기 (간격 줄임)
      case _EditMode.adjust:
        return 380; // 조정: 세로 슬라이더들 (간격 줄임)
      case _EditMode.none:
        return 250; // 기본값
    }
  }

  // UI 토글
  bool _showUI = true;

  // 필터 스와이프 관련
  bool _hasSwiped = false;

  // 크롭 관련 상태
  CropHandleType? _activeCropHandle;
  final Map<int, Size> _imageDisplaySizes = {}; // 이미지별 표시 크기

  @override
  void initState() {
    super.initState();
    if (widget.imageBytesList != null && widget.imageBytesList!.isNotEmpty) {
      _images = List.from(widget.imageBytesList!);
    } else if (widget.imageBytes != null) {
      _images = [widget.imageBytes!];
    } else {
      _images = [];
    }
    _pageController = PageController(initialPage: 0);

    // 애니메이션 컨트롤러 초기화
    _bottomSheetController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _bottomSheetAnimation = CurvedAnimation(
      parent: _bottomSheetController,
      curve: Curves.easeInOut,
    );

    _preloadImages();
  }

  Future<void> _preloadImages() async {
    for (int i = 0; i < _images.length; i++) {
      _loadImageToCache(i, _images[i]);
    }
  }

  Future<void> _loadImageToCache(int index, Uint8List bytes) async {
    if (_uiImageCache[index] != null) return;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _uiImageCache[index] = frame.image;
          // 🚀 캐시 크기 제한 초과 시 오래된 항목 제거
          _cleanupImageCache();
        });
      }
    } catch (e) {
      debugPrint('이미지 로드 오류: $e');
    }
  }

  /// 🚀 UI 이미지 캐시 정리 (최대 크기 초과 시 오래된 항목 제거)
  void _cleanupImageCache() {
    if (_uiImageCache.length <= _maxImageCacheSize) return;

    // 현재 인덱스와 가까운 항목들은 유지하고, 먼 항목부터 제거
    final keys = _uiImageCache.keys.toList()..sort();
    final itemsToRemove = _uiImageCache.length - _maxImageCacheSize;

    for (int i = 0; i < itemsToRemove; i++) {
      // 현재 인덱스와 가장 먼 항목 제거
      int removeIndex = 0;
      int maxDistance = 0;
      for (int j = 0; j < keys.length; j++) {
        final distance = (keys[j] - _currentIndex).abs();
        if (distance > maxDistance) {
          maxDistance = distance;
          removeIndex = j;
        }
      }
      if (keys.isNotEmpty) {
        _uiImageCache.remove(keys[removeIndex]);
        keys.removeAt(removeIndex);
      }
    }
  }

  @override
  void dispose() {
    // 🚀 모든 캐시 정리 (메모리 최적화)
    for (final image in _uiImageCache.values) {
      image?.dispose();
    }
    _uiImageCache.clear();
    _history.clear();
    _redoStack.clear();

    _pageController.dispose();
    _bottomSheetController.dispose();
    super.dispose();
  }

  bool get _isMultiImage => _images.length > 1;

  _ImageEditState _getCurrentEditState() {
    return _imageEditStates.putIfAbsent(_currentIndex, () => _ImageEditState());
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onImageEdited(int index, Uint8List editedBytes) {
    setState(() {
      _editedImages[index] = editedBytes;
      _uiImageCache[index] = null;
      _saveToHistory(index, editedBytes);
    });
    _loadImageToCache(index, editedBytes);
  }

  void _saveToHistory(int index, Uint8List imageBytes) {
    _history.putIfAbsent(index, () => []).add(imageBytes);
    _redoStack.putIfAbsent(index, () => []).clear();
    if (_history[index]!.length > 20) {
      _history[index]!.removeAt(0);
    }
  }

  void _undo() {
    final history = _history[_currentIndex];
    if (history == null || history.length <= 1) return;

    setState(() {
      _redoStack
          .putIfAbsent(_currentIndex, () => [])
          .add(_editedImages[_currentIndex] ?? _images[_currentIndex]);
      history.removeLast();
      final previousImage = history.last;
      _editedImages[_currentIndex] = previousImage;
      _uiImageCache[_currentIndex] = null;
    });
    _loadImageToCache(_currentIndex, _editedImages[_currentIndex]!);
  }

  void _redo() {
    final redoStack = _redoStack[_currentIndex];
    if (redoStack == null || redoStack.isEmpty) return;

    setState(() {
      final redoImage = redoStack.removeLast();
      _history.putIfAbsent(_currentIndex, () => []).add(redoImage);
      _editedImages[_currentIndex] = redoImage;
      _uiImageCache[_currentIndex] = null;
    });
    _loadImageToCache(_currentIndex, _editedImages[_currentIndex]!);
  }

  void _handleDone() {
    final List<Uint8List> result = [];
    for (int i = 0; i < _images.length; i++) {
      result.add(_editedImages[i] ?? _images[i]);
    }
    if (result.length == 1) {
      Navigator.pop(context, result.first);
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 글래스 블러 배경
          Positioned.fill(
            child: GestureDetector(
              onTap: _isBottomSheetOpen ? null : () => Navigator.pop(context),
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: bgColor.withOpacity(0.8)),
                ),
              ),
            ),
          ),

          // 메인 컨테이너
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // 앱바 (바텀시트가 올라올 때 위로 사라짐)
                  AnimatedBuilder(
                    animation: _bottomSheetAnimation,
                    builder: (context, child) {
                      final p = _bottomSheetAnimation.value;
                      final currentHeight = kToolbarHeight * (1 - p);
                      final opacity =
                          _showUI && !_isBottomSheetOpen ? 1.0 : 0.0;

                      if (currentHeight <= 0) {
                        return const SizedBox.shrink();
                      }

                      return ClipRect(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedOpacity(
                            opacity: opacity,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              height: currentHeight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          if (_isBottomSheetOpen) {
                                            _closeBottomSheet();
                                          } else {
                                            Navigator.pop(context);
                                          }
                                        },
                                        icon: Icon(
                                          _isBottomSheetOpen
                                              ? Icons.arrow_back
                                              : Icons.close,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (!_isBottomSheetOpen) ...[
                                        IconButton(
                                          onPressed:
                                              ((_history[_currentIndex]
                                                              ?.length ??
                                                          0) >
                                                      1)
                                                  ? _undo
                                                  : null,
                                          icon: Icon(
                                            Icons.undo,
                                            color:
                                                ((_history[_currentIndex]
                                                                ?.length ??
                                                            0) >
                                                        1)
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(
                                                      0.3,
                                                    ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed:
                                              (_redoStack[_currentIndex]
                                                          ?.isNotEmpty ??
                                                      false)
                                                  ? _redo
                                                  : null,
                                          icon: Icon(
                                            Icons.redo,
                                            color:
                                                (_redoStack[_currentIndex]
                                                            ?.isNotEmpty ??
                                                        false)
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(
                                                      0.3,
                                                    ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (!_isBottomSheetOpen)
                                    GestureDetector(
                                      onTap: _handleDone,
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
                      );
                    },
                  ),

                  // 이미지 미리보기 (Expanded가 자동으로 조정됨)
                  Expanded(
                    child:
                        _isMultiImage
                            ? PageView.builder(
                              controller: _pageController,
                              onPageChanged: _onPageChanged,
                              physics:
                                  _editMode != _EditMode.none
                                      ? const NeverScrollableScrollPhysics()
                                      : const PageScrollPhysics(),
                              itemCount: _images.length,
                              itemBuilder: (context, index) {
                                return _buildImagePreview(
                                  context,
                                  index,
                                  _editedImages[index] ?? _images[index],
                                );
                              },
                            )
                            : _buildImagePreview(context, 0, _images[0]),
                  ),

                  // 메인 툴바 (바텀시트가 열리면 완전히 제거하여 간격 줄임)
                  if (!_isBottomSheetOpen)
                    AnimatedOpacity(
                      opacity: _showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _GlassToolButton(
                                    icon: Icons.tune,
                                    label: '조정',
                                    onTap: _toggleAdjustment,
                                    isActive: _editMode == _EditMode.adjust,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 40,
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                  _GlassToolButton(
                                    icon: Icons.crop,
                                    label: '자르기',
                                    onTap: _toggleCrop,
                                    isActive: _editMode == _EditMode.crop,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 40,
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                  _GlassToolButton(
                                    icon: Icons.color_lens,
                                    label: '필터',
                                    onTap: _toggleFilter,
                                    isActive: _editMode == _EditMode.filter,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 바텀시트 (일반 위젯으로 올라오고 내려감)
                  AnimatedBuilder(
                    animation: _bottomSheetAnimation,
                    builder: (context, child) {
                      final currentHeight =
                          bottomSheetHeight * _bottomSheetAnimation.value;

                      if (currentHeight <= 0) {
                        return const SizedBox.shrink();
                      }

                      return GestureDetector(
                        onPanStart: _onBottomSheetDragStart,
                        onPanUpdate: _onBottomSheetDragUpdate,
                        onPanEnd: _onBottomSheetDragEnd,
                        child: Container(
                          height: currentHeight,
                          decoration: BoxDecoration(
                            color: bgColor.withOpacity(1),
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
                                  color: fgColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child:
                                    _editMode == _EditMode.crop
                                        ? _buildCropBottomSheet()
                                        : _editMode == _EditMode.filter
                                        ? _buildFilterBottomSheet()
                                        : _buildAdjustmentBottomSheet(),
                              ),
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
                                      onPressed: _closeBottomSheet,
                                      child: Text(
                                        '취소',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: fgColor.withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        _applyEdit();
                                        _closeBottomSheet();
                                      },
                                      child: Text(
                                        _editMode == _EditMode.crop
                                            ? '적용'
                                            : '완료',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: fgColor.withOpacity(0.7),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(
    BuildContext context,
    int index,
    Uint8List imageBytes,
  ) {
    final state = _getCurrentEditState();
    final currentImageBytes = _editedImages[index] ?? imageBytes;

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);

        // 크롭 모드일 때 크롭 영역 초기화
        if (_editMode == _EditMode.crop &&
            !state.cropState.isCropRectInitialized) {
          if (_uiImageCache[index] != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              CropUtils.initializeCropRect(
                image: _uiImageCache[index]!,
                containerSize: containerSize,
                cropState: state.cropState,
                onDisplaySizeChanged: (size) {
                  _imageDisplaySizes[index] = size;
                },
              );
              setState(() {});
            });
          }
        }

        return Stack(
          children: [
            GestureDetector(
              onTap: _toggleUI,
              // 크롭 모드에서는 CropEditor가 모든 제스처를 처리
              onPanUpdate:
                  _editMode == _EditMode.filter ? _onFilterSwipe : null,
              onPanEnd:
                  _editMode == _EditMode.filter ? _onFilterSwipeEnd : null,
              child:
                  _getColorFilter(state) != null
                      ? ColorFiltered(
                        key: ValueKey(
                          '${state.selectedFilter}_${state.brightness}_${state.contrast}_${state.saturation}',
                        ),
                        colorFilter: _getColorFilter(state)!,
                        child:
                            _uiImageCache[index] != null
                                ? CustomPaint(
                                  painter: _ImagePainter(
                                    _uiImageCache[index]!,
                                    imageOffset:
                                        _editMode == _EditMode.crop
                                            ? state.imageOffset
                                            : Offset.zero,
                                    imageScale:
                                        _editMode == _EditMode.crop
                                            ? state.imageScale
                                            : 1.0,
                                  ),
                                  size: Size.infinite,
                                )
                                : Center(
                                  child: FutureBuilder<ui.Image>(
                                    future: _loadImage(currentImageBytes),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return CircularProgressIndicator(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        );
                                      }
                                      if (snapshot.hasError ||
                                          !snapshot.hasData) {
                                        return const Icon(Icons.error);
                                      }
                                      if (snapshot.hasData) {
                                        _uiImageCache[index] = snapshot.data!;
                                      }
                                      return CustomPaint(
                                        painter: _ImagePainter(
                                          snapshot.data!,
                                          imageOffset:
                                              _editMode == _EditMode.crop
                                                  ? state.imageOffset
                                                  : Offset.zero,
                                          imageScale:
                                              _editMode == _EditMode.crop
                                                  ? state.imageScale
                                                  : 1.0,
                                        ),
                                        size: Size.infinite,
                                      );
                                    },
                                  ),
                                ),
                      )
                      : (_uiImageCache[index] != null
                          ? CustomPaint(
                            painter: _ImagePainter(
                              _uiImageCache[index]!,
                              imageOffset:
                                  _editMode == _EditMode.crop
                                      ? state.imageOffset
                                      : Offset.zero,
                              imageScale:
                                  _editMode == _EditMode.crop
                                      ? state.imageScale
                                      : 1.0,
                            ),
                            size: Size.infinite,
                          )
                          : Center(
                            child: FutureBuilder<ui.Image>(
                              future: _loadImage(currentImageBytes),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return CircularProgressIndicator(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  );
                                }
                                if (snapshot.hasError || !snapshot.hasData) {
                                  return const Icon(Icons.error);
                                }
                                if (snapshot.hasData) {
                                  _uiImageCache[index] = snapshot.data!;
                                }
                                return CustomPaint(
                                  painter: _ImagePainter(
                                    snapshot.data!,
                                    imageOffset:
                                        _editMode == _EditMode.crop
                                            ? state.imageOffset
                                            : Offset.zero,
                                    imageScale:
                                        _editMode == _EditMode.crop
                                            ? state.imageScale
                                            : 1.0,
                                  ),
                                  size: Size.infinite,
                                );
                              },
                            ),
                          )),
            ),
            // 크롭 오버레이
            if (_editMode == _EditMode.crop &&
                state.cropState.isCropRectInitialized)
              CropEditor(
                cropState: state.cropState,
                imageSize:
                    _uiImageCache[index] != null
                        ? Size(
                          _uiImageCache[index]!.width.toDouble(),
                          _uiImageCache[index]!.height.toDouble(),
                        )
                        : Size.zero,
                containerSize: containerSize,
                onCropRectChanged: (rect) {
                  setState(() {});
                },
                onImageTransformChanged: (transform) {
                  setState(() {
                    state.imageOffset = transform.offset;
                    state.imageScale = transform.scale;
                  });
                },
                activeHandle: _activeCropHandle,
              ),
          ],
        );
      },
    );
  }

  Future<ui.Image> _loadImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  ColorFilter? _getColorFilter(_ImageEditState state) {
    // 필터 + 조정 결합
    final filterMatrix = _getFilterMatrix(state.selectedFilter);
    final adjustmentMatrix = _getAdjustmentMatrix(state);

    // 행렬 곱셈 (간단한 결합)
    if (filterMatrix != null && adjustmentMatrix != null) {
      return ColorFilter.matrix(
        _multiplyMatrices(filterMatrix, adjustmentMatrix),
      );
    } else if (filterMatrix != null) {
      return ColorFilter.matrix(filterMatrix);
    } else if (adjustmentMatrix != null) {
      return ColorFilter.matrix(adjustmentMatrix);
    }
    return null;
  }

  List<double>? _getFilterMatrix(FilterType filter) {
    switch (filter) {
      case FilterType.none:
        return null;
      case FilterType.clear:
        return [
          1.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          1.1,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          1.1,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
        ];
      case FilterType.lucent:
        return [
          1.1,
          0.0,
          0.0,
          0.0,
          10.0,
          0.0,
          1.1,
          0.0,
          0.0,
          10.0,
          0.0,
          0.0,
          1.1,
          0.0,
          10.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
        ];
      case FilterType.bright:
        return [
          1.2,
          0.0,
          0.0,
          0.0,
          20.0,
          0.0,
          1.2,
          0.0,
          0.0,
          20.0,
          0.0,
          0.0,
          1.2,
          0.0,
          20.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
        ];
      case FilterType.tender:
        return [
          1.0,
          0.1,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.1,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
        ];
    }
  }

  List<double>? _getAdjustmentMatrix(_ImageEditState state) {
    if (state.brightness == 0.0 &&
        state.contrast == 0.0 &&
        state.saturation == 0.0) {
      return null;
    }

    // 밝기: +value는 밝게, -value는 어둡게
    final brightness = state.brightness / 100.0;
    // 대비: +value는 대비 증가, -value는 대비 감소
    final contrast = 1.0 + (state.contrast / 100.0);
    // 채도: +value는 채도 증가, -value는 채도 감소
    final saturation = 1.0 + (state.saturation / 100.0);

    // 간단한 행렬 계산 (채도 포함)
    final lumR = 0.299;
    final lumG = 0.587;
    final lumB = 0.114;
    final sr = (1.0 - saturation) * lumR;
    final sg = (1.0 - saturation) * lumG;
    final sb = (1.0 - saturation) * lumB;

    return [
      (sr + saturation) * contrast,
      sg * contrast,
      sb * contrast,
      0.0,
      brightness * 255,
      sr * contrast,
      (sg + saturation) * contrast,
      sb * contrast,
      0.0,
      brightness * 255,
      sr * contrast,
      sg * contrast,
      (sb + saturation) * contrast,
      0.0,
      brightness * 255,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    ];
  }

  List<double> _multiplyMatrices(List<double> a, List<double> b) {
    // 간단한 행렬 곱셈 (4x5 행렬)
    final result = List<double>.filled(20, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += a[i * 5 + k] * b[k * 5 + j];
        }
        result[i * 5 + j] = sum;
      }
    }
    return result;
  }

  void _toggleUI() {
    if (!_isBottomSheetOpen) {
      setState(() {
        _showUI = !_showUI;
      });
    }
  }

  void _toggleCrop() {
    final state = _getCurrentEditState();
    final wasInCropMode = _editMode == _EditMode.crop;

    setState(() {
      _editMode = _editMode == _EditMode.crop ? _EditMode.none : _EditMode.crop;
      _isBottomSheetOpen = _editMode == _EditMode.crop;
      if (_isBottomSheetOpen) {
        _bottomSheetController.forward();
      } else {
        // 크롭 모드에서 나갈 때 이미지 transform을 부드럽게 초기화
        if (wasInCropMode) {
          _resetImageTransformSmoothly(state);
        }
        _bottomSheetController.reverse();
      }
    });
  }

  void _resetImageTransformSmoothly(_ImageEditState state) {
    final startOffset = state.imageOffset;
    final startScale = state.imageScale;
    final endOffset = Offset.zero;
    final endScale = 1.0;

    // 애니메이션으로 부드럽게 초기화
    void animationListener() {
      if (!_bottomSheetController.isAnimating &&
          _bottomSheetController.value == 0.0) {
        // 애니메이션 완료 후 최종 값 설정
        setState(() {
          state.imageOffset = endOffset;
          state.imageScale = endScale;
        });
        _bottomSheetController.removeListener(animationListener);
      } else {
        // 애니메이션 중간 값 보간
        final progress = 1.0 - _bottomSheetController.value; // reverse이므로 반대로
        setState(() {
          state.imageOffset = Offset.lerp(startOffset, endOffset, progress)!;
          state.imageScale = startScale + (endScale - startScale) * progress;
        });
      }
    }

    _bottomSheetController.addListener(animationListener);
  }

  void _toggleFilter() {
    setState(() {
      _editMode =
          _editMode == _EditMode.filter ? _EditMode.none : _EditMode.filter;
      _isBottomSheetOpen = _editMode == _EditMode.filter;
      if (_isBottomSheetOpen) {
        _bottomSheetController.forward();
      } else {
        _bottomSheetController.reverse();
      }
    });
  }

  void _toggleAdjustment() {
    setState(() {
      _editMode =
          _editMode == _EditMode.adjust ? _EditMode.none : _EditMode.adjust;
      _isBottomSheetOpen = _editMode == _EditMode.adjust;
      if (_isBottomSheetOpen) {
        _bottomSheetController.forward();
      } else {
        _bottomSheetController.reverse();
      }
    });
  }

  void _closeBottomSheet() {
    setState(() {
      _isBottomSheetOpen = false;
      _editMode = _EditMode.none;
      _dragOffset = 0.0;
    });
    _bottomSheetController.reverse();
  }

  void _onBottomSheetDragStart(DragStartDetails details) {
    _bottomSheetController.stop();
  }

  void _onBottomSheetDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(
        0.0,
        bottomSheetHeight,
      );
      final progress = 1.0 - (_dragOffset / bottomSheetHeight);
      _bottomSheetController.value = progress;
    });
  }

  void _onBottomSheetDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissThreshold = 200.0;
    if (_dragOffset > dismissThreshold || velocity > 300) {
      _closeBottomSheet();
    } else {
      setState(() {
        _dragOffset = 0.0;
      });
      _bottomSheetController.forward();
    }
  }

  void _onFilterSwipe(DragUpdateDetails details) {
    final deltaX = details.delta.dx;
    if (deltaX.abs() > 20 && !_hasSwiped) {
      _hasSwiped = true;
      final state = _getCurrentEditState();
      final filters = FilterType.values;
      final currentIndex = filters.indexOf(state.selectedFilter);
      int newIndex;
      if (deltaX > 0) {
        newIndex = currentIndex > 0 ? currentIndex - 1 : filters.length - 1;
      } else {
        newIndex = currentIndex < filters.length - 1 ? currentIndex + 1 : 0;
      }
      setState(() {
        state.selectedFilter = filters[newIndex];
      });
    }
  }

  void _onFilterSwipeEnd(DragEndDetails details) {
    _hasSwiped = false;
  }

  void _applyEdit() {
    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];

    if (_editMode == _EditMode.crop) {
      // 크롭 적용
      _applyCrop(_currentIndex, currentImageBytes);
    } else {
      // 필터와 조정은 실시간 적용되므로 히스토리에 저장
      _saveToHistory(_currentIndex, currentImageBytes);
    }
  }

  Future<void> _applyCrop(int index, Uint8List imageBytes) async {
    final state = _getCurrentEditState();
    if (!state.cropState.isCropRectInitialized ||
        _imageDisplaySizes[index] == null ||
        _uiImageCache[index] == null) {
      return;
    }

    final result = await CropUtils.applyCrop(
      imageBytes: imageBytes,
      cropRect: state.cropState.cropRect,
      imageDisplaySize: _imageDisplaySizes[index]!,
      uiImage: _uiImageCache[index]!,
      containerSize: MediaQuery.of(context).size,
      rotation: state.rotation,
    );

    if (result != null) {
      _onImageEdited(index, result);
    }
  }

  Widget _buildCropBottomSheet() {
    final state = _getCurrentEditState();
    final cropOptions = [
      {'label': '재설정', 'ratio': 'reset', 'icon': Icons.refresh},
      {'label': '회전', 'ratio': 'rotate', 'icon': Icons.rotate_right},
      {'label': '자유', 'ratio': null, 'icon': null},
      {'label': '원본', 'ratio': 'original', 'icon': null},
      {'label': '1:1', 'ratio': '1:1', 'icon': null},
      {'label': '4:5', 'ratio': '4:5', 'icon': null},
      {'label': '16:9', 'ratio': '16:9', 'icon': null},
      {'label': '9:16', 'ratio': '9:16', 'icon': null},
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 10, bottom: 30),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              cropOptions.map((option) {
                final isSelected = state.selectedAspectRatio == option['ratio'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      if (option['ratio'] == 'reset') {
                        setState(() {
                          state.selectedAspectRatio = null;
                          state.cropState.reset();
                        });
                        // 크롭 영역 재초기화
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _uiImageCache[_currentIndex] != null) {
                            final containerSize = MediaQuery.of(context).size;
                            CropUtils.initializeCropRect(
                              image: _uiImageCache[_currentIndex]!,
                              containerSize: containerSize,
                              cropState: state.cropState,
                              onDisplaySizeChanged: (size) {
                                _imageDisplaySizes[_currentIndex] = size;
                              },
                            );
                            setState(() {});
                          }
                        });
                      } else if (option['ratio'] == 'rotate') {
                        setState(() {
                          state.rotation = (state.rotation + 90) % 360;
                        });
                      } else {
                        setState(() {
                          state.selectedAspectRatio =
                              option['ratio'] as String?;
                          state.cropState.isCropRectInitialized = false;
                        });
                        // 크롭 영역 재초기화
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _uiImageCache[_currentIndex] != null) {
                            final containerSize = MediaQuery.of(context).size;
                            CropUtils.initializeCropRect(
                              image: _uiImageCache[_currentIndex]!,
                              containerSize: containerSize,
                              cropState: state.cropState,
                              onDisplaySizeChanged: (size) {
                                _imageDisplaySizes[_currentIndex] = size;
                              },
                            );
                            setState(() {});
                          }
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
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (option['icon'] != null)
                            Icon(
                              option['icon'] as IconData,
                              color: isSelected ? Colors.white : Colors.white,
                              size: 18,
                            ),
                          if (option['icon'] != null) const SizedBox(width: 4),
                          Text(
                            option['label'] as String,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterBottomSheet() {
    final state = _getCurrentEditState();
    final filters = [
      {'name': '원본', 'filter': FilterType.none},
      {'name': 'Clear', 'filter': FilterType.clear},
      {'name': 'Lucent', 'filter': FilterType.lucent},
      {'name': 'Bright', 'filter': FilterType.bright},
      {'name': 'Tender', 'filter': FilterType.tender},
    ];

    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 10, bottom: 40),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              filters.map((filter) {
                final filterType = filter['filter'] as FilterType;
                final isSelected = state.selectedFilter == filterType;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            state.selectedFilter = filterType;
                          });
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white.withOpacity(0.2),
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: FutureBuilder<ui.Image>(
                              future: _loadImage(currentImageBytes),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return ColorFiltered(
                                    colorFilter: ColorFilter.matrix(
                                      _getFilterMatrix(filterType) ??
                                          [
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
                                          ],
                                    ),
                                    child: CustomPaint(
                                      painter: _ImagePainter(snapshot.data!),
                                      size: Size.infinite,
                                    ),
                                  );
                                }
                                return Container(
                                  color: Colors.white.withOpacity(0.1),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        filter['name'] as String,
                        style: TextStyle(
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildAdjustmentBottomSheet() {
    final state = _getCurrentEditState();
    final adjustments = [
      {'label': '밝기', 'type': 'brightness', 'icon': Icons.brightness_6},
      {'label': '대비', 'type': 'contrast', 'icon': Icons.contrast},
      {'label': '채도', 'type': 'saturation', 'icon': Icons.palette},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children:
            adjustments.map((adj) {
              final type = adj['type'] as String;
              double value = 0.0;
              if (type == 'brightness') value = state.brightness;
              if (type == 'contrast') value = state.contrast;
              if (type == 'saturation') value = state.saturation;

              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          adj['icon'] as IconData,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          adj['label'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          value.toStringAsFixed(0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: value,
                      min: -100,
                      max: 100,
                      onChanged: (newValue) {
                        setState(() {
                          if (type == 'brightness') state.brightness = newValue;
                          if (type == 'contrast') state.contrast = newValue;
                          if (type == 'saturation') state.saturation = newValue;
                        });
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _GlassToolButton extends StatelessWidget {
  const _GlassToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  final Offset imageOffset;
  final double imageScale;

  _ImagePainter(
    this.image, {
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageAspectRatio = image.width / image.height;
    final canvasAspectRatio = size.width / size.height;

    double drawWidth, drawHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspectRatio > canvasAspectRatio) {
      drawWidth = size.width;
      drawHeight = size.width / imageAspectRatio;
      offsetY = (size.height - drawHeight) / 2;
    } else {
      drawHeight = size.height;
      drawWidth = size.height * imageAspectRatio;
      offsetX = (size.width - drawWidth) / 2;
    }

    // 스케일 적용
    final scaledWidth = drawWidth * imageScale;
    final scaledHeight = drawHeight * imageScale;

    // 오프셋 적용 (크롭 영역 중심에 맞춤)
    final finalOffsetX = offsetX + imageOffset.dx;
    final finalOffsetY = offsetY + imageOffset.dy;

    final rect = Rect.fromLTWH(
      finalOffsetX,
      finalOffsetY,
      scaledWidth,
      scaledHeight,
    );

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.imageOffset != imageOffset ||
        oldDelegate.imageScale != imageScale;
  }
}
