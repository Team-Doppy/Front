import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'crop_editor.dart'
    show
        CropState,
        CropUtils,
        CropHandleType,
        ImageRectUtils,
        ImagePainter,
        CropOverlayPainter,
        CropGestureUtils,
        CropHandleBuilder;

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
  // ✅ 원본 이미지 보관 (절대 변경되지 않음, 필요시 복원용)
  // 현재는 사용되지 않지만, 향후 "모두 되돌리기" 기능 등에서 활용 가능
  // ignore: unused_field
  late final List<Uint8List> _originalImages;
  // ✅ 현재 표시할 이미지 리스트 (편집이 반영된 이미지)
  late final List<Uint8List> _images;
  late final PageController _pageController;
  int _currentIndex = 0;
  _EditMode _editMode = _EditMode.none;
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
  final Map<int, Size> _containerSizes = {}; // 이미지별 컨테이너 크기 (LayoutBuilder 기준)
  bool _isBottomSheetAnimationComplete = false; // 바텀시트 애니메이션 완료 여부
  Offset? _lastPanPosition; // 드래그 시작 위치 추적

  // ✅ 드래그 중 크롭박스 고정을 위한 상태
  bool _isDraggingImage = false;
  Rect? _frozenImageRect; // 드래그 중 고정된 이미지 rect
  Rect? _frozenCropRectScreen; // 드래그 중 고정된 크롭박스 위치

  @override
  void initState() {
    super.initState();
    // ✅ 원본 이미지와 현재 이미지를 분리하여 관리
    if (widget.imageBytesList != null && widget.imageBytesList!.isNotEmpty) {
      _originalImages = List.from(widget.imageBytesList!);
      _images = List.from(widget.imageBytesList!);
    } else if (widget.imageBytes != null) {
      _originalImages = [widget.imageBytes!];
      _images = [widget.imageBytes!];
    } else {
      _originalImages = [];
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

    // 애니메이션 완료 리스너 추가
    _bottomSheetController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isBottomSheetOpen) {
        setState(() {
          _isBottomSheetAnimationComplete = true;
        });
      } else if (status == AnimationStatus.dismissed) {
        setState(() {
          _isBottomSheetAnimationComplete = false;
        });
      }
    });

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

  /// 이미지 편집 완료 (필터/조정 등 실시간 편집)
  /// 현재는 필터/조정이 실시간 적용되므로 직접 사용되지 않지만,
  /// 필요시 필터/조정 완료 시점에 호출하여 이미지 저장 가능
  // ignore: unused_element
  void _onImageEdited(int index, Uint8List editedBytes) {
    setState(() {
      _images[index] = editedBytes; // ✅ 현재 이미지 리스트 직접 업데이트
      _uiImageCache[index] = null;
      _saveToHistory(index, editedBytes);
    });
    _loadImageToCache(index, editedBytes);
  }

  /// 크롭 적용 (완전히 새로운 이미지로 교체 + transform 초기화)
  void _onCropApplied(int index, Uint8List croppedBytes) {
    setState(() {
      // ✅ 크롭된 이미지로 완전히 교체
      _images[index] = croppedBytes;
      _uiImageCache[index] = null;

      // ✅ transform 상태 초기화 (크롭 후에는 새로운 이미지이므로)
      final state = _imageEditStates[index];
      if (state != null) {
        state.imageOffset = Offset.zero;
        state.imageScale = 1.0;
        state.cropState.reset();
      }

      // ✅ 히스토리에 저장 (언두/리두용)
      _saveToHistory(index, croppedBytes);
    });
    _loadImageToCache(index, croppedBytes);
  }

  void _saveToHistory(int index, Uint8List imageBytes) {
    // ✅ 히스토리가 비어있으면 현재 이미지를 첫 번째로 추가 (원본 보존)
    if (!_history.containsKey(index) || _history[index]!.isEmpty) {
      _history[index] = [_images[index]]; // 원본 또는 현재 이미지를 첫 번째로
    }
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
      // ✅ 현재 이미지를 redo 스택에 추가
      _redoStack
          .putIfAbsent(_currentIndex, () => [])
          .add(_images[_currentIndex]);

      // ✅ 이전 이미지로 복원
      history.removeLast();
      final previousImage = history.last;
      _images[_currentIndex] = previousImage;
      _uiImageCache[_currentIndex] = null;
    });
    _loadImageToCache(_currentIndex, _images[_currentIndex]);
  }

  void _redo() {
    final redoStack = _redoStack[_currentIndex];
    if (redoStack == null || redoStack.isEmpty) return;

    setState(() {
      final redoImage = redoStack.removeLast();
      _history.putIfAbsent(_currentIndex, () => []).add(redoImage);
      _images[_currentIndex] = redoImage; // ✅ 현재 이미지 리스트 직접 업데이트
      _uiImageCache[_currentIndex] = null;
    });
    _loadImageToCache(_currentIndex, _images[_currentIndex]);
  }

  void _handleDone() {
    // ✅ 현재 이미지 리스트를 그대로 반환 (이미 편집이 반영되어 있음)
    if (_images.length == 1) {
      Navigator.pop(context, _images.first);
    } else {
      Navigator.pop(context, List<Uint8List>.from(_images));
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
              behavior: HitTestBehavior.translucent,
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
                                  _images[index],
                                );
                              },
                            )
                            : _buildImagePreview(context, 0, _images[0]),
                  ),

                  // 메인 툴바 (바텀시트가 열리면 완전히 제거하여 간격 줄임)
                  if (!_isBottomSheetOpen)
                    GestureDetector(
                      // ✅ 툴바 영역 터치 이벤트 차단 (배경 GestureDetector와 충돌 방지)
                      onTap: () {}, // 빈 핸들러로 터치 이벤트 소비
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedOpacity(
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
                    ),

                  // 바텀시트 (일반 위젯으로 올라오고 내려감)
                  AnimatedBuilder(
                    animation: _bottomSheetAnimation,
                    builder: (context, child) {
                      if (_bottomSheetAnimation.value <= 0) {
                        return const SizedBox.shrink();
                      }

                      return GestureDetector(
                        onPanStart: _onBottomSheetDragStart,
                        onPanUpdate: _onBottomSheetDragUpdate,
                        onPanEnd: _onBottomSheetDragEnd,
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: _bottomSheetAnimation.value,
                            child: Container(
                              height: bottomSheetHeight,
                              decoration: BoxDecoration(
                                color: bgColor.withOpacity(1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(30),
                                  topRight: Radius.circular(30),
                                ),
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
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
                                  _editMode == _EditMode.crop ? '적용' : '완료',
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
    final currentImageBytes = imageBytes; // ✅ 이미 _images[index]가 전달됨

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        // LayoutBuilder의 containerSize 저장 (MediaQuery.size 대신 사용)
        _containerSizes[index] = containerSize;

        // 크롭 모드일 때 크롭 영역 초기화
        // ✅ 바텀시트가 완전히 올라온 상태에서만 초기화 (애니메이션 완료 후)
        if (_editMode == _EditMode.crop &&
            !state.cropState.isCropRectInitialized &&
            _isBottomSheetAnimationComplete) {
          // 바텀시트 완전히 올라온 상태
          if (_uiImageCache[index] != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              CropUtils.initializeCropRect(
                image: _uiImageCache[index]!,
                containerSize: containerSize,
                cropState: state.cropState,
                scale: state.imageScale,
                offset: state.imageOffset,
                onDisplaySizeChanged: (size) {
                  _imageDisplaySizes[index] = size;
                },
              );
              setState(() {});
            });
          }
        }

        // ✅ 레이어 분리: 이미지와 크롭 오버레이를 별도 레이어로 분리
        final uiImage = _uiImageCache[index];
        final imageSize =
            uiImage != null
                ? Size(uiImage.width.toDouble(), uiImage.height.toDouble())
                : null;

        // ✅ 현재 이미지 rect 계산
        final currentImageRect =
            imageSize != null
                ? ImageRectUtils.computeImageRect(
                  containerSize: containerSize,
                  imageSize: imageSize,
                  scale: state.imageScale,
                  offset: state.imageOffset,
                )
                : null;

        // ✅ 크롭 관련 계산용 imageRect (드래그 중이면 freeze된 값 사용)
        final imageRectForCrop =
            _isDraggingImage && _frozenImageRect != null
                ? _frozenImageRect!
                : currentImageRect;

        // 크롭 오버레이용 screen 좌표 계산
        // ✅ build에서는 단순히 imageToScreenRect만 수행 (중앙 정렬은 AutoZoom에서만)
        Rect? cropRectScreen;
        if (_editMode == _EditMode.crop &&
            state.cropState.isCropRectInitialized &&
            state.cropState.cropRectImage != null &&
            imageRectForCrop != null &&
            imageSize != null) {
          if (_frozenCropRectScreen != null) {
            // 드래그 시작 후: 고정된 크롭박스 위치 사용 (드래그 종료 후에도 계속 유지)
            cropRectScreen = _frozenCropRectScreen;
          } else {
            // 드래그 중이 아닐 때: 정상적으로 계산 (중앙 정렬은 AutoZoom에서 처리)
            cropRectScreen = ImageRectUtils.imageToScreenRect(
              imageRect: state.cropState.cropRectImage!,
              screenImageRect: imageRectForCrop,
              imageSize: imageSize,
            );
          }
        }

        return GestureDetector(
          // ✅ GestureDetector를 Stack 최상위로 올려서 모든 레이어의 이벤트를 받음
          behavior: HitTestBehavior.translucent,
          onTap:
              _isBottomSheetOpen
                  ? null
                  : _toggleUI, // ✅ 바텀시트 열려있을 때는 UI 토글 비활성화
          // ✅ 핀치/팬 통합: crop 모드에서는 ScaleGesture로 처리
          onScaleStart:
              _editMode == _EditMode.crop
                  ? (details) =>
                      _onCropScaleStart(details, index, containerSize)
                  : null,
          onScaleUpdate:
              _editMode == _EditMode.crop
                  ? (details) =>
                      _onCropScaleUpdate(details, index, containerSize)
                  : null,
          onScaleEnd:
              _editMode == _EditMode.crop
                  ? (details) => _onCropScaleEnd(details, index, containerSize)
                  : null,
          // 필터 모드는 기존 Pan 유지
          onPanUpdate: _editMode == _EditMode.filter ? _onFilterSwipe : null,
          onPanEnd: _editMode == _EditMode.filter ? _onFilterSwipeEnd : null,
          child: Stack(
            children: [
              // 1️⃣ 이미지 레이어 (transform 적용)
              IgnorePointer(
                // 이미지 레이어는 터치 이벤트를 차단 (GestureDetector가 처리)
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
                                    painter: ImagePainter(
                                      _uiImageCache[index]!,
                                      imageOffset: state.imageOffset,
                                      imageScale: state.imageScale,
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
                                          painter: ImagePainter(
                                            snapshot.data!,
                                            imageOffset: state.imageOffset,
                                            imageScale: state.imageScale,
                                          ),
                                          size: Size.infinite,
                                        );
                                      },
                                    ),
                                  ),
                        )
                        : (_uiImageCache[index] != null
                            ? CustomPaint(
                              painter: ImagePainter(
                                _uiImageCache[index]!,
                                imageOffset: state.imageOffset,
                                imageScale: state.imageScale,
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
                                  if (snapshot.hasError || !snapshot.hasData) {
                                    return const Icon(Icons.error);
                                  }
                                  if (snapshot.hasData) {
                                    _uiImageCache[index] = snapshot.data!;
                                  }
                                  return CustomPaint(
                                    painter: ImagePainter(
                                      snapshot.data!,
                                      imageOffset: state.imageOffset,
                                      imageScale: state.imageScale,
                                    ),
                                    size: Size.infinite,
                                  );
                                },
                              ),
                            )),
              ),
              // 2️⃣ 크롭 오버레이 레이어 (transform 미적용 - screen 좌표로 직접 그림)
              if (_editMode == _EditMode.crop &&
                  cropRectScreen != null &&
                  imageRectForCrop != null)
                IgnorePointer(
                  // 크롭 오버레이는 터치 이벤트를 차단 (이미지 드래그를 위해)
                  child: CustomPaint(
                    painter: CropOverlayPainter(
                      cropRectScreen: cropRectScreen,
                      imageRect: imageRectForCrop,
                    ),
                    size: Size.infinite,
                  ),
                ),
              // 3️⃣ 크롭 핸들들 (이미 screen 좌표 사용 중)
              // ✅ 드래그 중이면 고정된 cropRectScreen 전달
              if (_editMode == _EditMode.crop &&
                  state.cropState.isCropRectInitialized &&
                  imageRectForCrop != null &&
                  imageSize != null)
                CropHandleBuilder.buildCropHandles(
                  cropState: state.cropState,
                  activeHandle: _activeCropHandle,
                  onHandleChanged: (handle) {
                    debugPrint(
                      '🔄 [onHandleChanged] 이전: $_activeCropHandle → 새로운: $handle',
                    );
                    setState(() {
                      _activeCropHandle = handle;
                    });
                  },
                  onUpdate: () {
                    setState(() {});
                  },
                  onResize: (handle, delta) {
                    // 🎯 기본 리사이즈 로직 사용 (각 핸들 방향으로만 움직임, center 고정 안 함)
                    debugPrint('🔵 [리사이즈 중] handle: $handle, delta: $delta');
                    final uiImage = _uiImageCache[index];
                    if (uiImage != null) {
                      final containerSize = _containerSizes[index];
                      if (containerSize != null) {
                        final imageSize = Size(
                          uiImage.width.toDouble(),
                          uiImage.height.toDouble(),
                        );
                        // ✅ 리사이즈 중에도 freeze된 imageRect 사용
                        final resizeImageRect =
                            _isDraggingImage && _frozenImageRect != null
                                ? _frozenImageRect!
                                : ImageRectUtils.computeImageRect(
                                  containerSize: containerSize,
                                  imageSize: imageSize,
                                  scale: state.imageScale,
                                  offset: state.imageOffset,
                                );
                        CropGestureUtils.updateCropRectResize(
                          handle: handle,
                          screenDelta: delta,
                          cropState: state.cropState,
                          screenImageRect: resizeImageRect,
                          imageSize: imageSize,
                        );
                        // 🎯 리사이즈 후 이미지 좌표로 변환 (이미 updateCropRectResize에서 처리됨)
                        // 추가 clamp는 불필요 (이미지 좌표 기준으로 clamp 완료)
                      }
                    }
                  },
                  onResizeEnd: () {
                    // 🎯 리사이즈 완료 시 Auto Zoom 실행 (안정적으로 항상 실행)
                    debugPrint('✅ [onResizeEnd] 리사이즈 완료 - Auto Zoom 실행');
                    final containerSize = _containerSizes[index];
                    if (containerSize != null) {
                      // PostFrameCallback으로 다음 프레임에서 실행 (setState 완료 후)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _autoZoomToCrop(index, containerSize);
                      });
                    } else {
                      debugPrint('❌ [Auto Zoom 실패] containerSize가 null');
                    }
                  },
                  screenImageRect: imageRectForCrop, // ✅ freeze된 imageRect 사용
                  imageSize: imageSize,
                  cropRectScreen: cropRectScreen, // ✅ 드래그 중 고정된 크롭박스 위치 전달
                ),
            ],
          ),
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

    setState(() {
      if (_editMode != _EditMode.crop) {
        // ✅ 크롭 진입 시 transform 초기화
        state.imageOffset = Offset.zero;
        state.imageScale = 1.0;
        // 크롭 모드 진입 시 초기화 플래그 리셋
        state.cropState.isCropRectInitialized = false;
        _isBottomSheetAnimationComplete = false;
        // 크롭 모드 진입 시 freeze 상태 초기화
        _frozenCropRectScreen = null;
        _frozenImageRect = null;
        _isDraggingImage = false;
      } else {
        // 크롭 모드 종료 시 freeze 상태 초기화
        _frozenCropRectScreen = null;
        _frozenImageRect = null;
        _isDraggingImage = false;
      }

      _editMode = _editMode == _EditMode.crop ? _EditMode.none : _EditMode.crop;
      _isBottomSheetOpen = _editMode == _EditMode.crop;
      if (_isBottomSheetOpen) {
        _bottomSheetController.forward();
      } else {
        _bottomSheetController.reverse();
      }
    });
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
    // ✅ 애니메이션이 완전히 끝난 후에만 상태 변경 (오버플로우 방지)
    _bottomSheetController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _isBottomSheetOpen = false;
        _editMode = _EditMode.none;
        _dragOffset = 0.0;
        // ✅ 취소 시: 이미지는 그대로 유지 (transform 상태도 유지)
        // 크롭 적용 시에만 새로운 이미지로 교체됨
      });
    });
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
    final currentImageBytes = _images[_currentIndex];

    if (_editMode == _EditMode.crop) {
      // 크롭 적용
      _applyCrop(_currentIndex, currentImageBytes);
    } else {
      // 필터와 조정은 실시간 적용되므로 히스토리에 저장
      _saveToHistory(_currentIndex, currentImageBytes);
    }
  }

  // 크롭 제스처 처리
  void _onCropScaleStart(
    ScaleStartDetails details,
    int index,
    Size containerSize,
  ) {
    // 드래그 시작 위치 저장
    _lastPanPosition = details.focalPoint;

    // ✅ 드래그 시작 시 크롭박스 위치 고정
    final state = _getCurrentEditState();
    if (state.cropState.isCropRectInitialized &&
        state.cropState.cropRectImage != null) {
      final uiImage = _uiImageCache[index];
      if (uiImage != null) {
        final imageSize = Size(
          uiImage.width.toDouble(),
          uiImage.height.toDouble(),
        );
        final currentImageRect = ImageRectUtils.computeImageRect(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: state.imageScale,
          offset: state.imageOffset,
        );

        // ✅ imageRect와 cropRectScreen을 동시에 freeze
        _frozenImageRect = currentImageRect;

        final computedCropRectScreen = ImageRectUtils.imageToScreenRect(
          imageRect: state.cropState.cropRectImage!,
          screenImageRect: currentImageRect,
          imageSize: imageSize,
        );

        // 크롭박스를 화면 중앙에 고정
        final containerCenter = Offset(
          containerSize.width / 2,
          containerSize.height / 2,
        );
        final cropCenter = computedCropRectScreen.center;
        final centerDiff = containerCenter - cropCenter;

        // 크롭박스를 화면 중앙으로 이동하여 고정
        _frozenCropRectScreen = computedCropRectScreen.shift(centerDiff);
        _isDraggingImage = true;
        setState(() {}); // 고정된 크롭박스 표시를 위해 업데이트
      }
    }
  }

  void _onCropScaleUpdate(
    ScaleUpdateDetails details,
    int index,
    Size containerSize,
  ) {
    final state = _getCurrentEditState();
    if (!state.cropState.isCropRectInitialized) return;
    // 핸들 드래그 중이면 무시
    if (_activeCropHandle != null) return;

    // 핀치 줌이 아닌 경우 (scale이 1.0에 가까움) = 일반 드래그
    if ((details.scale - 1.0).abs() < 0.001) {
      // (1) delta 계산 (이전 위치와 현재 위치의 차이)
      if (_lastPanPosition == null) {
        _lastPanPosition = details.focalPoint;
        return;
      }
      final delta = details.focalPoint - _lastPanPosition!;
      _lastPanPosition = details.focalPoint;
      final proposedOffset = state.imageOffset + delta;

      final uiImage = _uiImageCache[index];
      if (uiImage == null) return;
      final imageSize = Size(
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      );

      // (2) 고무줄 감쇠 판정
      // ✅ freeze된 크롭박스를 기준으로 판정 (드래그 중에는 freeze된 값 사용)
      Rect? testCropRectScreen;
      if (_isDraggingImage && _frozenCropRectScreen != null) {
        // 드래그 중: freeze된 크롭박스에 delta를 적용한 위치로 판정
        testCropRectScreen = _frozenCropRectScreen!.shift(delta);
      } else {
        // 드래그 중이 아닐 때: proposedOffset 적용 시의 crop 위치 계산
        final testImageRect = ImageRectUtils.computeImageRect(
          containerSize: containerSize,
          imageSize: imageSize,
          scale: state.imageScale,
          offset: proposedOffset,
        );
        testCropRectScreen = ImageRectUtils.imageToScreenRect(
          imageRect: state.cropState.cropRectImage!,
          screenImageRect: testImageRect,
          imageSize: imageSize,
        );
      }

      // (3) 고무줄 감쇠 적용
      double dx = delta.dx;
      double dy = delta.dy;

      const resistance = 0.25; // 0.15 ~ 0.35 사이에서 튜닝

      if (testCropRectScreen.left < 0 ||
          testCropRectScreen.right > containerSize.width) {
        dx *= resistance;
      }

      if (testCropRectScreen.top < 0 ||
          testCropRectScreen.bottom > containerSize.height) {
        dy *= resistance;
      }

      // (4) imageOffset만 업데이트
      // ❗ cropRect는 여기서 절대 수정하지 않는다
      // ✅ scale을 고려하여 delta 조정 (scale > 1일 때 실제 이동 거리 감소)
      state.imageOffset += Offset(dx / state.imageScale, dy / state.imageScale);

      setState(() {});
    }
  }

  void _onCropScaleEnd(ScaleEndDetails details, int index, Size containerSize) {
    // 드래그 종료 시 위치 초기화
    _lastPanPosition = null;

    final state = _getCurrentEditState();
    final uiImage = _uiImageCache[index];

    // ✅ 이미지가 크롭 영역 밖으로 나갔는지 확인하고 크롭 영역 안으로 복귀시킴
    if (uiImage != null &&
        _frozenCropRectScreen != null &&
        state.cropState.isCropRectInitialized) {
      final imageSize = Size(
        uiImage.width.toDouble(),
        uiImage.height.toDouble(),
      );

      // 현재 이미지 rect (최종 offset 기준)
      final currentImageRect = ImageRectUtils.computeImageRect(
        containerSize: containerSize,
        imageSize: imageSize,
        scale: state.imageScale,
        offset: state.imageOffset,
      );

      // 크롭박스는 고정 위치 사용
      final cropRectScreen = _frozenCropRectScreen!;

      // 이미지가 크롭박스 밖으로 나갔는지 확인하고 조정
      double adjustX = 0.0;
      double adjustY = 0.0;

      // 이미지가 크롭박스 왼쪽으로 벗어나면 오른쪽으로 이동
      if (currentImageRect.left > cropRectScreen.left) {
        adjustX = cropRectScreen.left - currentImageRect.left;
      }
      // 이미지가 크롭박스 오른쪽으로 벗어나면 왼쪽으로 이동
      else if (currentImageRect.right < cropRectScreen.right) {
        adjustX = cropRectScreen.right - currentImageRect.right;
      }

      // 이미지가 크롭박스 위로 벗어나면 아래로 이동
      if (currentImageRect.top > cropRectScreen.top) {
        adjustY = cropRectScreen.top - currentImageRect.top;
      }
      // 이미지가 크롭박스 아래로 벗어나면 위로 이동
      else if (currentImageRect.bottom < cropRectScreen.bottom) {
        adjustY = cropRectScreen.bottom - currentImageRect.bottom;
      }

      // offset 보정 적용 (이미지가 크롭박스 안으로 들어오도록)
      if (adjustX != 0.0 || adjustY != 0.0) {
        state.imageOffset += Offset(adjustX, adjustY);
      }
    }

    // ✅ 드래그 종료 후에도 크롭박스는 고정 위치 유지
    // _frozenCropRectScreen은 해제하지 않음 (크롭박스가 고정 위치에 계속 유지됨)
    // _frozenImageRect만 해제 (드래그 종료 후에는 현재 imageOffset 기준으로 계산)
    _isDraggingImage = false;
    _frozenImageRect = null;
    // _frozenCropRectScreen은 유지 (크롭박스 고정 위치 유지)

    setState(() {});
  }

  /// 🎯 Auto Zoom to Crop (단순화된 버전)
  /// 크롭 윈도우가 화면의 50%~65% 범위를 유지하도록 자동 줌
  /// 크롭 윈도우 중심을 화면 중앙에 맞춤 (크롭은 고정, 이미지만 이동)
  void _autoZoomToCrop(int index, Size containerSize) {
    // ✅ 드래그 중이면 AutoZoom 실행 안 함
    if (_isDraggingImage) return;

    final uiImage = _uiImageCache[index];
    if (uiImage == null) return;

    final state = _getCurrentEditState();
    final imageSize = Size(uiImage.width.toDouble(), uiImage.height.toDouble());
    final cropState = state.cropState;

    if (cropState.cropRectImage == null) return;

    final width = containerSize.width;
    final height = containerSize.height;
    final containerCenter = Offset(width / 2, height / 2);

    // ✅ image 좌표 기준으로 한 번만 계산 (screen 좌표 재사용 금지)
    // 1) 크롭 중심을 image 좌표에서 직접 가져오기
    final cropCenterImage = cropState.cropRectImage!.center;

    // 2) 현재 scale 기준으로 크롭 크기 계산 (scale 결정용)
    final currentImageRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: state.imageScale,
      offset: Offset.zero, // offset은 scale 계산에 영향 없음
    );

    final currentCropRectScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropState.cropRectImage!,
      screenImageRect: currentImageRect,
      imageSize: imageSize,
    );

    // 3) 크롭 윈도우 크기에 따라 scale 계산
    const maxZoom = 5.0;
    const minRatio = 0.65; // 최소 65% (줌 인 증가)
    const maxRatio = 0.75; // 최대 75% (줌 아웃 기준 상향)

    final cropRatioX = currentCropRectScreen.width / width;
    final cropRatioY = currentCropRectScreen.height / height;
    final cropRatio = cropRatioX < cropRatioY ? cropRatioX : cropRatioY;

    double targetScale = state.imageScale;

    // 크롭이 너무 작으면 줌 인
    if (cropRatio < minRatio && state.imageScale < maxZoom) {
      targetScale = (state.imageScale / cropRatio * minRatio).clamp(
        1.0,
        maxZoom,
      );
    }
    // 크롭이 너무 크면 줌 아웃 (단, scale이 1보다 클 때만)
    else if (cropRatio > maxRatio && state.imageScale > 1.0) {
      targetScale = (state.imageScale / cropRatio * maxRatio).clamp(
        1.0,
        maxZoom,
      );
    }

    // 4) targetScale 적용 후 이미지 rect 계산 (offset=0 기준)
    final imageRectAtTargetScale = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: targetScale,
      offset: Offset.zero,
    );

    // 5) crop 중심을 image 좌표에서 직접 screen 좌표로 변환 (한 번만)
    final scaleX = imageRectAtTargetScale.width / imageSize.width;
    final scaleY = imageRectAtTargetScale.height / imageSize.height;

    final cropCenterScreenAtTargetScale = Offset(
      imageRectAtTargetScale.left + cropCenterImage.dx * scaleX,
      imageRectAtTargetScale.top + cropCenterImage.dy * scaleY,
    );

    // 6) offset 계산 (한 줄)
    final targetOffset = containerCenter - cropCenterScreenAtTargetScale;

    // 7) 업데이트
    state.imageScale = targetScale;
    state.imageOffset = targetOffset;

    setState(() {});
  }

  Future<void> _applyCrop(int index, Uint8List imageBytes) async {
    final state = _getCurrentEditState();
    if (!state.cropState.isCropRectInitialized ||
        _uiImageCache[index] == null) {
      return;
    }

    // LayoutBuilder의 constraints를 사용 (MediaQuery.size 사용 금지)
    final containerSize = _containerSizes[index];
    if (containerSize == null) {
      debugPrint('⚠️ containerSize가 없습니다. LayoutBuilder에서 설정되지 않았습니다.');
      return;
    }

    final result = await CropUtils.applyCrop(
      imageBytes: imageBytes,
      cropState: state.cropState,
      uiImage: _uiImageCache[index]!,
      containerSize: containerSize,
      scale: state.imageScale,
      offset: state.imageOffset,
      rotation: state.rotation,
    );

    if (result != null) {
      // ✅ 크롭 적용: 완전히 새로운 이미지로 교체 + transform 초기화
      _onCropApplied(index, result);
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
                          // transform 초기화
                          state.imageOffset = Offset.zero;
                          state.imageScale = 1.0;
                        });
                        // 크롭 영역 재초기화
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _uiImageCache[_currentIndex] != null) {
                            // LayoutBuilder constraints 사용
                            final containerSize =
                                _containerSizes[_currentIndex];
                            if (containerSize != null) {
                              CropUtils.initializeCropRect(
                                image: _uiImageCache[_currentIndex]!,
                                containerSize: containerSize,
                                cropState: state.cropState,
                                scale: state.imageScale,
                                offset: state.imageOffset,
                                onDisplaySizeChanged: (size) {
                                  _imageDisplaySizes[_currentIndex] = size;
                                },
                              );
                              setState(() {});
                            }
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
                          // transform 초기화
                          state.imageOffset = Offset.zero;
                          state.imageScale = 1.0;
                        });
                        // 크롭 영역 재초기화
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _uiImageCache[_currentIndex] != null) {
                            // LayoutBuilder constraints 사용
                            final containerSize =
                                _containerSizes[_currentIndex];
                            if (containerSize != null) {
                              CropUtils.initializeCropRect(
                                image: _uiImageCache[_currentIndex]!,
                                containerSize: containerSize,
                                cropState: state.cropState,
                                scale: state.imageScale,
                                offset: state.imageOffset,
                                onDisplaySizeChanged: (size) {
                                  _imageDisplaySizes[_currentIndex] = size;
                                },
                              );
                              setState(() {});
                            }
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

    final currentImageBytes = _images[_currentIndex];

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
                                      painter: ImagePainter(
                                        snapshot.data!,
                                        imageOffset: Offset.zero,
                                        imageScale: 1.0,
                                      ),
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
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // ✅ 버튼 영역만 터치 받도록 명시
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
