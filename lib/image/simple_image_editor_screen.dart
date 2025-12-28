import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'crop_editor.dart'
    show
        CropState,
        CropUtils,
        CropEditorBottomSheet,
        CropEditorPanel,
        ImageRectUtils,
        ImagePainter,
        CropOverlayPainter,
        CropGestureUtils,
        CropHandleBuilder,
        CropGestureHandler,
        CropAutoZoom;
import 'rotation_editor.dart';

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

enum _EditMode { none, crop, rotate, adjust, filter }

// 이미지별 편집 상태
class _ImageEditState {
  // 회전 관련 상태
  int rotation = 0; // 0-360
  bool flipHorizontal = false;
  bool flipVertical = false;

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
  // ✅ 원본 이미지의 ui.Image 캐시 (크롭 취소 시 즉시 사용)
  final Map<int, ui.Image?> _originalUiImageCache = {};
  static const int _maxImageCacheSize = 10; // 최대 UI 이미지 캐시 크기

  // ✅ “확 바뀌는 것” 방지용: 이전 프레임 이미지 보관 + 크로스페이드
  final Map<int, int> _applyAnimVersion = {};
  static const Duration _applySettleDuration = Duration(milliseconds: 140);

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
  CropEditorPanel _initialCropPanelForOpen = CropEditorPanel.aspect;

  // 메인 툴바(조정/자르기/회전/필터) 시각적 높이(대략값).
  // - 툴바를 트리에서 제거하면 바텀시트가 내려오는 동안 이미지가 하단 영역까지 확장됐다가
  //   마지막에 툴바가 "툭" 등장하며 점프하는 문제가 생김.
  // - 따라서 바텀시트 애니메이션과 반대로(닫힐수록) 툴바 높이를 함께 늘려 점프를 제거한다.
  static const double _mainToolbarHeight = 90.0;

  /// 바텀시트는 고정 height를 쓰지 않고, 모드별 "최대 높이"만 둔다.
  /// (모드별 레이아웃 요구사항이 달라 고정 숫자는 구조적으로 항상 깨짐)
  double get _bottomSheetMaxHeight {
    // 모드별 적절한 최대 높이 설정 (과도하게 높지 않게)
    switch (_editMode) {
      case _EditMode.crop:
        // 패널별 높이 조절은 crop_editor.dart 내부 위젯에서 처리
        return 320;
      case _EditMode.rotate:
        return 240;
      case _EditMode.filter:
        return 280;
      case _EditMode.adjust:
        return 400;
      case _EditMode.none:
        return 250;
    }
  }

  Widget _buildBottomSheetEditorContent() {
    final content =
        _editMode == _EditMode.crop
            ? _buildCropBottomSheet()
            : _editMode == _EditMode.filter
            ? _buildFilterBottomSheet()
            : _buildAdjustmentBottomSheet();

    // ✅ editor 영역은 항상 스크롤 가능해야 overflow가 나지 않고 히트테스트도 안정적이다.
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      child: content,
    );
  }

  // UI 토글
  bool _showUI = true;

  // 필터 스와이프 관련
  bool _hasSwiped = false;

  // 크롭 관련 상태
  final Map<int, Size> _imageDisplaySizes = {}; // 이미지별 표시 크기
  final Map<int, Size> _containerSizes = {}; // 이미지별 컨테이너 크기 (LayoutBuilder 기준)
  bool _isBottomSheetAnimationComplete = false; // 바텀시트 애니메이션 완료 여부

  // ✅ 크롭 제스처 핸들러 (이미지별)
  final Map<int, CropGestureHandler> _cropGestureHandlers = {};

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
      // ✅ 원본 이미지의 ui.Image도 미리 로드
      _loadOriginalImageToCache(i, _originalImages[i]);
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

  /// ✅ 원본 이미지의 ui.Image를 캐시에 로드 (크롭 취소 시 즉시 사용)
  Future<void> _loadOriginalImageToCache(int index, Uint8List bytes) async {
    if (_originalUiImageCache[index] != null) return;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _originalUiImageCache[index] = frame.image;
        });
      }
    } catch (e) {
      debugPrint('원본 이미지 로드 오류: $e');
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

  Future<void> _setImageBytesWithFade(
    int index,
    Uint8List newBytes, {
    VoidCallback? mutateStateInsideSetState,
  }) async {
    // ✅ 기존 이미지를 유지한 채 새 이미지를 먼저 디코딩 (로딩 스피너/확 바뀜 방지)
    ui.Image? next;
    try {
      next = await _loadImage(newBytes);
    } catch (e) {
      debugPrint('[SimpleImageEditor] 이미지 디코딩 실패: $e');
      return;
    }

    if (!mounted) return;

    setState(() {
      _images[index] = newBytes;
      _uiImageCache[index] = next;

      // 스냅 교체 + 미세 settle 애니메이션 트리거
      _applyAnimVersion[index] = (_applyAnimVersion[index] ?? 0) + 1;

      // 호출자가 state reset 등을 같이 하고 싶으면 여기서 실행
      mutateStateInsideSetState?.call();

      // 캐시 정리
      _cleanupImageCache();
    });
  }

  Widget _buildPaintWithFade({
    required BuildContext context,
    required int index,
    required Uint8List bytesForFallbackLoad,
    required _ImageEditState state,
  }) {
    final curr = _uiImageCache[index];
    final v = _applyAnimVersion[index] ?? 0;

    // 최초 로딩(캐시에 아무것도 없을 때만) — 적용 순간엔 여기에 잘 안 들어오게 만드는 게 목표
    if (curr == null) {
      return Center(
        child: FutureBuilder<ui.Image>(
          future: _loadImage(bytesForFallbackLoad),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Icon(Icons.error);
            }
            _uiImageCache[index] = snapshot.data!;
            return CustomPaint(
              painter: ImagePainter(
                snapshot.data!,
                state.imageOffset,
                state.imageScale,
              ),
              size: Size.infinite,
            );
          },
        ),
      );
    }

    // ✅ 스냅 교체 + “살짝 정착(zoom settle)” (겹침 없음 → 덜 조잡/덜 어지러움)
    return TweenAnimationBuilder<double>(
      key: ValueKey('apply_settle_$index\_$v'),
      tween: Tween(begin: 1.02, end: 1.0),
      duration: _applySettleDuration,
      curve: Curves.easeOutCubic,
      builder: (context, s, _) {
        return Transform.scale(
          scale: s,
          alignment: Alignment.center,
          child: CustomPaint(
            painter: ImagePainter(curr, state.imageOffset, state.imageScale),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // 🚀 모든 캐시 정리 (메모리 최적화)
    for (final image in _uiImageCache.values) {
      image?.dispose();
    }
    _uiImageCache.clear();
    // ✅ 원본 이미지 캐시도 정리
    for (final image in _originalUiImageCache.values) {
      image?.dispose();
    }
    _originalUiImageCache.clear();
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

  /// 크롭 제스처 핸들러 가져오기 (이미지별)
  CropGestureHandler _getCropGestureHandler(int index) {
    return _cropGestureHandlers.putIfAbsent(index, () => CropGestureHandler());
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
    // ✅ “확 바뀜” 방지: 기존 이미지를 유지한 채 새 이미지 준비 후 페이드 교체
    _setImageBytesWithFade(
      index,
      croppedBytes,
      mutateStateInsideSetState: () {
        // transform 상태 초기화 (크롭 후에는 새로운 이미지이므로)
        final state = _imageEditStates[index];
        if (state != null) {
          state.imageOffset = Offset.zero;
          state.imageScale = 1.0;
          state.cropState.reset();
        }
        _saveToHistory(index, croppedBytes);
      },
    );
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

    // ✅ “확 바뀜” 방지: undo도 페이드로
    final currentBytes = _images[_currentIndex];
    history.removeLast();
    final previousBytes = history.last;
    _redoStack.putIfAbsent(_currentIndex, () => []).add(currentBytes);
    _setImageBytesWithFade(_currentIndex, previousBytes);
  }

  void _redo() {
    final redoStack = _redoStack[_currentIndex];
    if (redoStack == null || redoStack.isEmpty) return;

    // ✅ “확 바뀜” 방지: redo도 페이드로
    final redoBytes = redoStack.removeLast();
    _history.putIfAbsent(_currentIndex, () => []).add(redoBytes);
    _setImageBytesWithFade(_currentIndex, redoBytes);
  }

  Future<void> _handleDone() async {
    // ✅ 현재 보이는(필터/보정 포함) 결과를 실제 bytes로 "굽기"
    final exportedImages = <Uint8List>[];
    for (int i = 0; i < _images.length; i++) {
      exportedImages.add(await _exportFinalBytes(i));
    }

    // ✅ 이미지가 1개면 바로 반환
    if (exportedImages.length == 1) {
      Navigator.pop(context, exportedImages.first);
      return;
    }

    // ✅ 여러 이미지일 때 그룹 레이아웃 선택 페이지 표시
    try {
      // Uint8List를 임시 File로 변환
      final List<File> tempFiles = [];
      final tempDir = await Directory.systemTemp.createTemp('image_editor_');

      for (int i = 0; i < exportedImages.length; i++) {
        final tempFile = File('${tempDir.path}/image_$i.jpg');
        await tempFile.writeAsBytes(exportedImages[i]);
        tempFiles.add(tempFile);
      }

      if (!mounted) return;

      // 그룹 레이아웃 선택 페이지 표시
      final layout = await Navigator.push<GroupImageLayout>(
        context,
        MaterialPageRoute(
          builder:
              (context) => Scaffold(
                body: GroupImageLayoutSelector(previewImages: tempFiles),
              ),
          fullscreenDialog: false,
        ),
      );

      // 임시 파일 정리
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      if (!mounted) return;

      // 레이아웃 선택 취소 시 종료
      if (layout == null) return;

      // 레이아웃 정보와 함께 이미지 반환
      // 결과를 Map 형태로 반환: {images: List<Uint8List>, layout: GroupImageLayout}
      Navigator.pop(context, {
        'images': List<Uint8List>.from(exportedImages),
        'layout': layout,
      });
    } catch (e) {
      debugPrint('그룹 레이아웃 선택 오류: $e');
      // 오류 발생 시 기존 방식으로 반환
      if (mounted) {
        Navigator.pop(context, List<Uint8List>.from(exportedImages));
      }
    }
  }

  /// ✅ 현재 편집 상태(회전/반전 + 필터/보정)를 bytes로 "굽기"
  Future<Uint8List> _exportFinalBytes(int index) async {
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    Uint8List bytes = _images[index];

    // 1) 회전/반전이 아직 bytes로 적용되지 않았다면 여기서 반영
    try {
      if (state.flipHorizontal) {
        bytes = RotationEditor.flip(bytes, horizontal: true);
      }
      if (state.flipVertical) {
        bytes = RotationEditor.flip(bytes, horizontal: false);
      }
      if (state.rotation != 0) {
        bytes = RotationEditor.rotate(bytes, angle: state.rotation.toDouble());
      }
    } catch (e) {
      debugPrint('[SimpleImageEditor] 회전/반전 export 실패: $e');
    }

    // 2) 필터/보정(밝기/대비/채도)은 화면 렌더링만 되므로 실제로 굽는다
    final matrix = _getCombinedColorMatrix(state);
    if (matrix == null) return bytes;

    try {
      return await _applyColorMatrixToBytes(bytes, matrix);
    } catch (e) {
      debugPrint('[SimpleImageEditor] 필터/보정 export 실패: $e');
      return bytes;
    }
  }

  List<double>? _getCombinedColorMatrix(_ImageEditState state) {
    final filterMatrix = _getFilterMatrix(state.selectedFilter);
    final adjustmentMatrix = _getAdjustmentMatrix(state);

    if (filterMatrix != null && adjustmentMatrix != null) {
      return _multiplyMatrices(filterMatrix, adjustmentMatrix);
    }
    return filterMatrix ?? adjustmentMatrix;
  }

  Future<Uint8List> _applyColorMatrixToBytes(
    Uint8List imageBytes,
    List<double> matrix,
  ) async {
    final src = await _loadImage(imageBytes);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..colorFilter = ColorFilter.matrix(matrix);
    canvas.drawImage(src, Offset.zero, paint);

    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) {
      throw StateError('toByteData returned null');
    }
    return bd.buffer.asUint8List();
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
                                            _closeBottomSheet(cancel: true);
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
                                            child: Text(
                                              '추가(${_images.length})',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
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

                  // ✅ 메인 툴바: 바텀시트가 내려오는 동안(애니메이션 중) 툴바 높이를 함께 복원
                  // -> 이미지가 하단 영역을 침범했다가 마지막에 툴바가 튀는 점프 제거
                  AnimatedBuilder(
                    animation: _bottomSheetAnimation,
                    builder: (context, _) {
                      // 바텀시트가 열려있을수록(1.0) 툴바는 0, 닫힐수록(0.0) 툴바는 1
                      final toolbarFactor = (1.0 - _bottomSheetAnimation.value)
                          .clamp(0.0, 1.0);

                      // UI 숨김 상태면 "보이진 않되" 레이아웃 점프를 막기 위해 높이는 유지
                      final opacity = _showUI ? 1.0 : 0.0;

                      return ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: toolbarFactor,
                          child: SizedBox(
                            height: _mainToolbarHeight,
                            child: Opacity(
                              opacity: opacity * toolbarFactor,
                              child: IgnorePointer(
                                ignoring: toolbarFactor < 0.99,
                                child: _buildMainToolbar(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: _bottomSheetMaxHeight,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          Flexible(child: _buildBottomSheetEditorContent()),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 8.0,
                              right: 8.0,
                              bottom: 30.0,
                              top: 8.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed:
                                      () => _closeBottomSheet(cancel: true),
                                  child: Text(
                                    '취소',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: fgColor.withOpacity(0.9),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () async {
                                    await _applyEdit();
                                    _closeBottomSheet(cancel: false);
                                  },
                                  child: Text(
                                    (_editMode == _EditMode.crop ||
                                            _editMode == _EditMode.rotate)
                                        ? '적용'
                                        : '완료',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: fgColor.withOpacity(0.9),
                                    ),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainToolbar() {
    return GestureDetector(
      // ✅ 툴바 영역 터치 이벤트 차단 (배경 GestureDetector와 충돌 방지)
      onTap: () {}, // 빈 핸들러로 터치 이벤트 소비
      behavior: HitTestBehavior.opaque,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                    onTap: () => _openCropPanel(CropEditorPanel.aspect),
                    isActive: _editMode == _EditMode.crop,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  _GlassToolButton(
                    icon: Icons.rotate_right,
                    label: '회전',
                    onTap: () => _openCropPanel(CropEditorPanel.rotate),
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
    );
  }

  /// 회전을 적용한 이미지 위젯 빌드
  Widget _buildRotatedImage(
    BuildContext context,
    int index,
    Uint8List currentImageBytes,
    _ImageEditState state,
  ) {
    final rotationRadians = state.rotation * (3.14159265359 / 180.0);

    final basePaint = _buildPaintWithFade(
      context: context,
      index: index,
      bytesForFallbackLoad: currentImageBytes,
      state: state,
    );

    final imageWidget =
        _getColorFilter(state) != null
            ? ColorFiltered(
              key: ValueKey(
                '${state.selectedFilter}_${state.brightness}_${state.contrast}_${state.saturation}',
              ),
              colorFilter: _getColorFilter(state)!,
              child: basePaint,
            )
            : basePaint;

    Widget result = imageWidget;

    // Flip 적용 (먼저 flip, 그 다음 회전)
    if (state.flipHorizontal) {
      result = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0),
        child: result,
      );
    }
    if (state.flipVertical) {
      result = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(1.0, -1.0),
        child: result,
      );
    }

    // 회전 적용
    if (state.rotation != 0) {
      result = Transform.rotate(
        angle: rotationRadians,
        alignment: Alignment.center,
        child: result,
      );
    }

    return result;
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
        // 크롭 모드일 때는 항상 마진이 적용된 함수 사용
        final currentImageRect =
            imageSize != null
                ? (_editMode == _EditMode.crop
                    ? ImageRectUtils.computeImageRectForCrop(
                      containerSize: containerSize,
                      imageSize: imageSize,
                      scale: state.imageScale,
                      offset: state.imageOffset,
                    )
                    : ImageRectUtils.computeImageRect(
                      containerSize: containerSize,
                      imageSize: imageSize,
                      scale: state.imageScale,
                      offset: state.imageOffset,
                    ))
                : null;

        // ✅ 크롭 관련 계산용 imageRect (드래그 중이면 freeze된 값 사용)
        final cropHandler = _getCropGestureHandler(index);
        final imageRectForCrop =
            cropHandler.isDraggingImage && cropHandler.frozenImageRect != null
                ? cropHandler.frozenImageRect!
                : currentImageRect;

        // 크롭 오버레이용 screen 좌표 계산
        // ✅ 항상 imageToScreenRect로 계산만 (절대 저장/freeze 금지)
        Rect? cropRectScreen;
        if (_editMode == _EditMode.crop &&
            state.cropState.isCropRectInitialized &&
            state.cropState.cropRectImage != null &&
            imageRectForCrop != null &&
            imageSize != null) {
          cropRectScreen = ImageRectUtils.imageToScreenRect(
            imageRect: state.cropState.cropRectImage!,
            screenImageRect: imageRectForCrop,
            imageSize: imageSize,
          );
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
                child: _buildRotatedImage(
                  context,
                  index,
                  currentImageBytes,
                  state,
                ),
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
                  activeHandle: cropHandler.activeHandle,
                  onHandleChanged: (handle) {
                    debugPrint(
                      '🔄 [onHandleChanged] 이전: ${cropHandler.activeHandle} → 새로운: $handle',
                    );
                    cropHandler.setActiveHandle(handle);
                    setState(() {});
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
                        final cropHandler = _getCropGestureHandler(index);
                        final resizeImageRect =
                            cropHandler.isDraggingImage &&
                                    cropHandler.frozenImageRect != null
                                ? cropHandler.frozenImageRect!
                                : (_editMode == _EditMode.crop
                                    ? ImageRectUtils.computeImageRectForCrop(
                                      containerSize: containerSize,
                                      imageSize: imageSize,
                                      scale: state.imageScale,
                                      offset: state.imageOffset,
                                    )
                                    : ImageRectUtils.computeImageRect(
                                      containerSize: containerSize,
                                      imageSize: imageSize,
                                      scale: state.imageScale,
                                      offset: state.imageOffset,
                                    ));
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
                    // 🎯 리사이즈 완료 시 Auto Zoom 실행
                    debugPrint('✅ [onResizeEnd] 리사이즈 완료 - Auto Zoom 실행');
                    final containerSize = _containerSizes[index];
                    if (containerSize != null) {
                      final uiImage = _uiImageCache[index];
                      if (uiImage != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _autoZoomToCrop(index, containerSize);
                        });
                      }
                    } else {
                      debugPrint('❌ [Auto Zoom 실패] containerSize가 null');
                    }
                  },
                  screenImageRect: imageRectForCrop, // ✅ freeze된 imageRect 사용
                  imageSize: imageSize,
                  cropRectScreen: cropRectScreen, // ✅ 항상 계산된 값 전달 (freeze 금지)
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

  void _openCropPanel(CropEditorPanel panel) {
    final state = _getCurrentEditState();

    setState(() {
      _initialCropPanelForOpen = panel;

      if (_editMode != _EditMode.crop) {
        // 크롭(통합 편집)로 진입
        state.imageOffset = Offset.zero;
        state.imageScale = 1.0;
        state.cropState.isCropRectInitialized = false;
        _isBottomSheetAnimationComplete = false;
        _getCropGestureHandler(_currentIndex).reset();

        _editMode = _EditMode.crop;
        _isBottomSheetOpen = true;
        _bottomSheetController.forward();
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

  void _closeBottomSheet({required bool cancel}) {
    // ✅ 애니메이션이 완전히 끝난 후에만 상태 변경 (오버플로우 방지)
    _bottomSheetController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        // ✅ 취소로 닫는 경우에만 원본/상태 복원
        if (cancel && _editMode == _EditMode.crop) {
          if (_currentIndex < _originalImages.length) {
            _images[_currentIndex] = _originalImages[_currentIndex];

            // ✅ 원본 이미지의 ui.Image가 캐시에 있으면 즉시 사용 (로딩 없음)
            if (_originalUiImageCache[_currentIndex] != null) {
              _uiImageCache[_currentIndex] =
                  _originalUiImageCache[_currentIndex];
            } else {
              // 캐시에 없으면 로드 (초기 로드 시나리오)
              _uiImageCache[_currentIndex] = null;
              _loadImageToCache(_currentIndex, _originalImages[_currentIndex]);
            }

            // transform 상태도 초기화
            final state = _imageEditStates[_currentIndex];
            if (state != null) {
              state.imageOffset = Offset.zero;
              state.imageScale = 1.0;
              state.cropState.reset();
            }
          }
        }

        _isBottomSheetOpen = false;
        _editMode = _EditMode.none;
        _dragOffset = 0.0;
      });
    });
  }

  void _onBottomSheetDragStart(DragStartDetails details) {
    _bottomSheetController.stop();
  }

  void _onBottomSheetDragUpdate(DragUpdateDetails details) {
    setState(() {
      final maxH = _bottomSheetMaxHeight;
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, maxH);
      final progress = 1.0 - (_dragOffset / maxH);
      _bottomSheetController.value = progress;
    });
  }

  void _onBottomSheetDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dismissThreshold = _bottomSheetMaxHeight * 0.35;
    if (_dragOffset > dismissThreshold || velocity > 300) {
      _closeBottomSheet(cancel: true);
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

  Future<void> _applyEdit() async {
    final currentImageBytes = _images[_currentIndex];

    if (_editMode == _EditMode.crop) {
      // 크롭 적용
      await _applyCrop(_currentIndex, currentImageBytes);
    } else {
      // 필터와 조정은 실시간 적용되므로 히스토리에 저장
      _saveToHistory(_currentIndex, currentImageBytes);
    }
  }

  // 크롭 제스처 처리 (CropGestureHandler 위임)
  void _onCropScaleStart(
    ScaleStartDetails details,
    int index,
    Size containerSize,
  ) {
    final state = _getCurrentEditState();
    final uiImage = _uiImageCache[index];
    if (uiImage == null) return;

    final cropHandler = _getCropGestureHandler(index);
    cropHandler.onScaleStart(
      details: details,
      cropState: state.cropState,
      uiImage: uiImage,
      containerSize: containerSize,
      imageScale: state.imageScale,
      imageOffset: state.imageOffset,
    );
  }

  void _onCropScaleUpdate(
    ScaleUpdateDetails details,
    int index,
    Size containerSize,
  ) {
    final state = _getCurrentEditState();
    if (!state.cropState.isCropRectInitialized) return;

    final uiImage = _uiImageCache[index];
    if (uiImage == null) return;

    final cropHandler = _getCropGestureHandler(index);
    final updateResult = cropHandler.onScaleUpdate(
      details: details,
      cropState: state.cropState,
      uiImage: uiImage,
      containerSize: containerSize,
      imageScale: state.imageScale,
      imageOffset: state.imageOffset,
      onStateChanged: () => setState(() {}),
    );

    if (updateResult != null) {
      if (updateResult.scale != null) {
        // 핀치 줌: scale 업데이트
        state.imageScale = updateResult.scale!;
      }
      if (updateResult.offset != null) {
        // 드래그: offset 업데이트
        state.imageOffset += updateResult.offset!;
      }
      setState(() {});
    }
  }

  void _onCropScaleEnd(ScaleEndDetails details, int index, Size containerSize) {
    final state = _getCurrentEditState();
    final uiImage = _uiImageCache[index];
    if (uiImage == null) return;

    final cropHandler = _getCropGestureHandler(index);
    final result = cropHandler.onScaleEnd(
      cropState: state.cropState,
      uiImage: uiImage,
      containerSize: containerSize,
      imageScale: state.imageScale,
      imageOffset: state.imageOffset,
    );

    if (result != null) {
      // ✅ snap-back offset 적용
      if (result.snapBackOffset != null) {
        state.imageOffset += result.snapBackOffset!;
      }

      // ✅ cropRectImage 위치 업데이트 (크기 유지)
      // ❌ snap-back에서는 cropRectImage 변경하지 않음 (null이면 무시)
      if (result.cropRectImagePosition != null &&
          result.cropRectImageSize != null) {
        state.cropState.cropRectImage = Rect.fromLTWH(
          result.cropRectImagePosition!.dx,
          result.cropRectImagePosition!.dy,
          result.cropRectImageSize!.width,
          result.cropRectImageSize!.height,
        );
      }
    }

    setState(() {});
  }

  /// Auto Zoom to Crop (CropAutoZoom 위임)
  void _autoZoomToCrop(int index, Size containerSize) {
    final cropHandler = _getCropGestureHandler(index);
    if (cropHandler.isDraggingImage) return;

    final uiImage = _uiImageCache[index];
    if (uiImage == null) return;

    final state = _getCurrentEditState();
    final result = CropAutoZoom.autoZoomToCrop(
      cropState: state.cropState,
      uiImage: uiImage,
      containerSize: containerSize,
      currentScale: state.imageScale,
      currentOffset: state.imageOffset,
    );

    state.imageScale = result.scale;
    state.imageOffset = result.offset;
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

    final result = await CropUtils.applyCropWithTransform(
      uiImage: _uiImageCache[index]!,
      cropState: state.cropState,
      containerSize: containerSize,
      scale: state.imageScale,
      offset: state.imageOffset,
      rotationDeg: state.rotation,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
    );

    if (result != null) {
      // ✅ 크롭 적용: 완전히 새로운 이미지로 교체 + transform 초기화
      _onCropApplied(index, result);
    }
  }

  Widget _buildCropBottomSheet() {
    final state = _getCurrentEditState();

    void reinitCropRect() {
      final containerSize = _containerSizes[_currentIndex];
      if (_uiImageCache[_currentIndex] != null && containerSize != null) {
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
      }
    }

    return CropEditorBottomSheet(
      initialPanel: _initialCropPanelForOpen,
      selectedAspectRatio: state.selectedAspectRatio,
      rotation: state.rotation,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
      onSelectAspectRatio: (ratio) {
        setState(() {
          state.imageOffset = Offset.zero;
          state.imageScale = 1.0;
          state.selectedAspectRatio = ratio;
          state.cropState.selectedAspectRatio = ratio;
          reinitCropRect();
        });
      },
      onResetAspectRatio: () {
        setState(() {
          state.selectedAspectRatio = null;
          state.cropState.selectedAspectRatio = null;
          state.cropState.reset();
          state.imageOffset = Offset.zero;
          state.imageScale = 1.0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(reinitCropRect);
        });
      },
      onRotationChanged: (v) => setState(() => state.rotation = v),
      onRotate90:
          () => setState(() => state.rotation = (state.rotation + 90) % 360),
      onResetRotation: () => setState(() => state.rotation = 0),
      onToggleFlipHorizontal:
          () => setState(() {
            state.flipHorizontal = !state.flipHorizontal;
          }),
      onToggleFlipVertical:
          () => setState(() {
            state.flipVertical = !state.flipVertical;
          }),
      onResetAll: () {
        setState(() {
          state.selectedAspectRatio = null;
          state.cropState.reset();
          state.rotation = 0;
          state.flipHorizontal = false;
          state.flipVertical = false;
          state.imageOffset = Offset.zero;
          state.imageScale = 1.0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(reinitCropRect);
        });
      },
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
                                        Offset.zero,
                                        1.0,
                                      ),
                                      size: Size.infinite,
                                    ),
                                  );
                                }
                                return Container(
                                  color: Colors.white.withOpacity(0.1),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
