import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'crop_screen.dart';

/// 간단한 커스텀 이미지 편집 화면
/// 필터, 자르기, 보정, 회전 네 가지 기능 제공
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

  // 보정 관련 상태
  double brightness = 0.0; // -100 ~ 100
  double contrast = 0.0; // -100 ~ 100
  double saturation = 0.0; // -100 ~ 100
  double warmth = 0.0; // -100 ~ 100

  // 필터 관련 상태
  String? selectedFilter; // null = 원본

  // 이미지 이동 및 스케일 관련 상태
  Offset imageOffset = Offset.zero; // 편집 모드에서 이미지 위치
  double imageScale = 0.9; // 편집 모드에서 이미지 스케일 (0.9로 축소)
}

class _SimpleImageEditorScreenState extends State<SimpleImageEditorScreen> {
  late final List<Uint8List> _images;
  late final PageController _pageController;
  int _currentIndex = 0;
  _EditMode _editMode = _EditMode.none;
  final Map<int, Uint8List> _editedImages = {}; // 편집된 이미지 저장
  final Map<int, img.Image?> _decodedImages = {}; // 디코딩된 이미지 캐시
  final Map<int, ui.Image?> _uiImageCache = {}; // UI 이미지 캐시

  // 이미지별 편집 상태 관리
  final Map<int, _ImageEditState> _imageEditStates = {};

  // 현재 이미지의 편집 상태를 가져오는 헬퍼
  _ImageEditState _getCurrentEditState() {
    return _imageEditStates.putIfAbsent(_currentIndex, () => _ImageEditState());
  }

  @override
  void initState() {
    super.initState();
    // 단일 이미지 또는 다중 이미지 처리
    if (widget.imageBytesList != null && widget.imageBytesList!.isNotEmpty) {
      _images = List.from(widget.imageBytesList!);
    } else if (widget.imageBytes != null) {
      _images = [widget.imageBytes!];
    } else {
      _images = [];
    }
    _pageController = PageController(initialPage: 0);
    _preloadImages();
  }

  Future<void> _preloadImages() async {
    // 모든 이미지를 미리 로드
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
        });
      }
    } catch (e) {
      debugPrint('이미지 로드 오류: $e');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isMultiImage => _images.length > 1;

  Future<void> _decodeCurrentImage() async {
    final index = _currentIndex;
    if (_decodedImages[index] != null) return;

    try {
      final bytes = _editedImages[index] ?? _images[index];
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        _decodedImages[index] = decoded;
      }
    } catch (e) {
      debugPrint('이미지 디코딩 오류: $e');
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _decodeCurrentImage();
  }

  void _onImageEdited(int index, Uint8List editedBytes) {
    setState(() {
      _editedImages[index] = editedBytes;
      _decodedImages[index] = null; // 캐시 무효화
      _uiImageCache[index] = null; // UI 이미지 캐시 무효화
    });
    _loadImageToCache(index, editedBytes);
  }

  void _handleDone() {
    // 편집된 이미지가 있으면 그것을, 없으면 원본을 반환
    final List<Uint8List> result = [];
    for (int i = 0; i < _images.length; i++) {
      result.add(_editedImages[i] ?? _images[i]);
    }
    // 단일 이미지인 경우 Uint8List 반환, 다중 이미지인 경우 List<Uint8List> 반환
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
    final barBgColor =
        isDark
            ? AppColors.darkBackground.withOpacity(0.9)
            : AppColors.lightBackground.withOpacity(0.95);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false, // 하단은 툴바에서 처리
        child: Column(
          children: [
            // 앱바 (편집 모드가 아닐 때만 표시)
            if (_editMode == _EditMode.none)
              _buildAppBar(context, barBgColor, fgColor),
            // 이미지 미리보기 영역
            Expanded(
              child:
                  _editMode == _EditMode.none
                      ? _buildImagePreviewArea()
                      : _buildEditModeContent(),
            ),
            // 툴바
            _editMode == _EditMode.none
                ? _buildToolbar(context, bgColor, fgColor)
                : _buildEditModeToolbar(context, bgColor, fgColor),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Color barBgColor, Color fgColor) {
    return Container(
      height: kToolbarHeight,
      decoration: BoxDecoration(
        color: barBgColor,
        border: Border(
          bottom: BorderSide(color: fgColor.withOpacity(0.1), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: fgColor),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child:
                _isMultiImage
                    ? Center(
                      child: Text(
                        '${_currentIndex + 1} / ${_images.length}',
                        style: TextStyle(
                          color: fgColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                    : const SizedBox.shrink(),
          ),
          TextButton(
            onPressed: _handleDone,
            child: Text(
              '완료',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildImagePreview(
    BuildContext context,
    int index,
    Uint8List imageBytes,
  ) {
    // 캐시된 이미지가 있으면 바로 사용
    if (_uiImageCache[index] != null) {
      return CustomPaint(
        painter: _ImagePainter(_uiImageCache[index]!),
        size: Size.infinite,
      );
    }

    // 캐시가 없으면 로드
    _loadImageToCache(index, imageBytes);

    return Center(
      child: FutureBuilder<ui.Image>(
        future: _loadImage(imageBytes),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return CircularProgressIndicator(
              color: Theme.of(context).colorScheme.onSurface,
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Icon(Icons.error);
          }
          // 로드된 이미지를 캐시에 저장
          if (snapshot.hasData) {
            _uiImageCache[index] = snapshot.data!;
          }
          return CustomPaint(
            painter: _ImagePainter(snapshot.data!),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, Color bgColor, Color fgColor) {
    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];

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
        child: Container(
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToolButton(
                context,
                icon: Icons.crop,
                label: '자르기',
                onTap: () => _openCropEditor(_currentIndex, currentImageBytes),
                fgColor: fgColor,
              ),
              _buildToolButton(
                context,
                icon: Icons.tune,
                label: '보정',
                onTap:
                    () => _openAdjustEditor(_currentIndex, currentImageBytes),
                fgColor: fgColor,
              ),
              _buildToolButton(
                context,
                icon: Icons.auto_awesome,
                label: '필터',
                onTap:
                    () => _openFilterEditor(_currentIndex, currentImageBytes),
                fgColor: fgColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color fgColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fgColor, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: fgColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<ui.Image> _loadImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Widget _buildImagePreviewArea() {
    return _isMultiImage
        ? PageView.builder(
          key: const ValueKey('image_preview'),
          controller: _pageController,
          physics: const ClampingScrollPhysics(),
          onPageChanged: _onPageChanged,
          itemCount: _images.length,
          itemBuilder: (context, index) {
            return _buildImagePreview(
              context,
              index,
              _editedImages[index] ?? _images[index],
            );
          },
        )
        : _buildImagePreview(context, 0, _images[0]);
  }

  Widget _buildEditModeContent() {
    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];

    return switch (_editMode) {
      _EditMode.crop => _buildCropContent(currentImageBytes),
      _EditMode.adjust => _buildAdjustContent(currentImageBytes),
      _EditMode.filter => _buildFilterContent(currentImageBytes),
      _EditMode.none => _buildImagePreviewArea(),
    };
  }

  Widget _buildCropContent(Uint8List imageBytes) {
    final state = _getCurrentEditState();
    // 회전이 적용된 경우 회전된 이미지 표시
    if (state.rotation != 0) {
      return _buildEditableImage(
        key: ValueKey('crop_$_currentIndex'),
        imageBytes: imageBytes,
        child: FutureBuilder<ui.Image>(
          future: _getRotatedPreviewImage(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator(
                color: Theme.of(context).colorScheme.onSurface,
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Icon(Icons.error);
            }
            return CustomPaint(
              painter: _ImagePainter(snapshot.data!),
              size: Size.infinite,
            );
          },
        ),
      );
    }
    return _buildEditableImage(
      key: ValueKey('crop_$_currentIndex'),
      imageBytes: imageBytes,
      child: _buildImagePreview(context, _currentIndex, imageBytes),
    );
  }

  Widget _buildAdjustContent(Uint8List imageBytes) {
    return _buildEditableImage(
      key: ValueKey('adjust_$_currentIndex'),
      imageBytes: imageBytes,
      child: _buildImagePreview(context, _currentIndex, imageBytes),
    );
  }

  Widget _buildFilterContent(Uint8List imageBytes) {
    return _buildEditableImage(
      key: ValueKey('filter_$_currentIndex'),
      imageBytes: imageBytes,
      child: _buildImagePreview(context, _currentIndex, imageBytes),
    );
  }

  // 편집 모드에서 이미지를 이동 가능하게 하고 축소하는 위젯
  Widget _buildEditableImage({
    required Key key,
    required Uint8List imageBytes,
    required Widget child,
  }) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _getCurrentEditState().imageOffset += details.delta;
        });
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 10), // 상단 여유 공간
          child: Transform.translate(
            offset: _getCurrentEditState().imageOffset,
            child: Transform.scale(
              scale: _getCurrentEditState().imageScale,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<ui.Image> _getRotatedPreviewImage() async {
    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];
    final decoded = img.decodeImage(currentImageBytes);
    if (decoded == null) {
      final codec = await ui.instantiateImageCodec(currentImageBytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    }

    final state = _getCurrentEditState();
    img.Image rotated = decoded;
    if (state.rotation == 90) {
      rotated = img.copyRotate(decoded, angle: 90);
    } else if (state.rotation == 180) {
      rotated = img.copyRotate(decoded, angle: 180);
    } else if (state.rotation == 270) {
      rotated = img.copyRotate(decoded, angle: 270);
    }

    final bytes = Uint8List.fromList(img.encodePng(rotated));
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Widget _buildEditModeToolbar(
    BuildContext context,
    Color bgColor,
    Color fgColor,
  ) {
    // 각 편집 모드별 컨트롤 높이 계산
    double controlsHeight = 0;
    switch (_editMode) {
      case _EditMode.crop:
        controlsHeight = 100;
        break;
      case _EditMode.adjust:
        controlsHeight = 150;
        break;
      case _EditMode.filter:
        controlsHeight = 180;
        break;
      case _EditMode.none:
        controlsHeight = 0;
        break;
    }

    return Container(
      key: ValueKey('edit_toolbar_${_editMode}_$_currentIndex'),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: fgColor.withOpacity(0.1), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 편집 모드별 컨트롤
            SizedBox(
              height: controlsHeight,
              child: _buildEditModeControls(context, bgColor, fgColor),
            ),
            // 하단 버튼 (X, 체크)
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: fgColor, size: 28),
                    onPressed: () {
                      final savedIndex = _currentIndex; // 현재 인덱스 저장

                      // PageView를 먼저 올바른 페이지로 이동
                      if (_isMultiImage && _pageController.hasClients) {
                        _pageController.jumpToPage(savedIndex);
                      }

                      setState(() {
                        _editMode = _EditMode.none;
                        final state = _getCurrentEditState();
                        state.rotation = 0; // 회전 초기화
                        state.brightness = 0.0;
                        state.contrast = 0.0;
                        state.saturation = 0.0;
                        state.warmth = 0.0;
                        state.selectedFilter = null;
                        state.selectedAspectRatio = null;
                        state.imageOffset = Offset.zero; // 위치 초기화
                        state.imageScale = 0.9; // 편집 모드 기본 스케일
                      });

                      // setState 후에도 다시 한 번 확인하여 동기화
                      if (_isMultiImage) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _pageController.hasClients) {
                            final currentPage =
                                _pageController.page?.round() ?? 0;
                            if (currentPage != savedIndex) {
                              _pageController.jumpToPage(savedIndex);
                            }
                          }
                        });
                      }
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: fgColor.withOpacity(0.1),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.check, color: fgColor, size: 28),
                    onPressed: _applyEdit,
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

  Widget _buildEditModeControls(
    BuildContext context,
    Color bgColor,
    Color fgColor,
  ) {
    switch (_editMode) {
      case _EditMode.crop:
        return _buildCropControls(context, bgColor, fgColor);
      case _EditMode.adjust:
        return _buildAdjustControls(context, bgColor, fgColor);
      case _EditMode.filter:
        return _buildFilterControls(context, bgColor, fgColor);
      case _EditMode.none:
        return const SizedBox.shrink();
    }
  }

  // 자르기 컨트롤 (비율 선택)
  Widget _buildCropControls(
    BuildContext context,
    Color bgColor,
    Color fgColor,
  ) {
    // 현재 이미지의 편집 상태를 가져옴
    final state = _getCurrentEditState();
    final cropOptions = [
      {'label': '재설정', 'ratio': 'reset', 'icon': Icons.refresh},
      {'label': '회전', 'ratio': 'rotate', 'icon': Icons.rotate_right},
      {'label': '자유', 'ratio': null, 'icon': null}, // null = 자유
      {'label': '원본', 'ratio': 'original', 'icon': null},
      {'label': '16:9', 'ratio': '16:9', 'icon': null},
      {'label': '3:2', 'ratio': '3:2', 'icon': null},
    ];

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cropOptions.length,
        itemBuilder: (context, index) {
          final option = cropOptions[index];
          final isSelected = state.selectedAspectRatio == option['ratio'];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () {
                setState(() {
                  if (option['ratio'] == 'reset') {
                    // 재설정: 모든 편집 상태 초기화
                    state.selectedAspectRatio = null;
                    state.imageOffset = Offset.zero;
                    state.imageScale = 0.9;
                  } else if (option['ratio'] == 'rotate') {
                    // 회전은 자르기 모드 내에서 처리 (별도 모드 전환 없음)
                    // 회전 버튼은 단순히 회전만 수행
                    final state = _getCurrentEditState();
                    state.rotation = (state.rotation + 90) % 360;
                  } else {
                    _getCurrentEditState().selectedAspectRatio =
                        option['ratio'] as String?;
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
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
                            : fgColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option['icon'] != null)
                      Icon(
                        option['icon'] as IconData,
                        color: isSelected ? Colors.white : fgColor,
                        size: 18,
                      ),
                    if (option['icon'] != null) const SizedBox(width: 4),
                    Text(
                      option['label'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : fgColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 보정 컨트롤
  Widget _buildAdjustControls(
    BuildContext context,
    Color bgColor,
    Color fgColor,
  ) {
    final state = _getCurrentEditState();
    final adjustments = [
      {'label': '재설정', 'icon': Icons.refresh, 'type': 'reset'},
      {'label': '자동레벨', 'icon': Icons.auto_fix_high, 'type': 'auto_level'},
      {'label': '자동WB', 'icon': Icons.wb_auto, 'type': 'auto_wb'},
      {'label': '밝기', 'icon': Icons.brightness_6, 'type': 'brightness'},
      {'label': '대비', 'icon': Icons.contrast, 'type': 'contrast'},
      {'label': '채도', 'icon': Icons.palette, 'type': 'saturation'},
      {'label': '선명', 'icon': Icons.auto_awesome, 'type': 'sharpness'},
    ];

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // 타이틀
          Text(
            '보정',
            style: TextStyle(
              color: fgColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // 옵션 리스트
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: adjustments.length,
              itemBuilder: (context, index) {
                final adj = adjustments[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (adj['type'] == 'reset') {
                          state.brightness = 0.0;
                          state.contrast = 0.0;
                          state.saturation = 0.0;
                          state.warmth = 0.0;
                        }
                        // TODO: 다른 옵션들 구현
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            adj['icon'] as IconData,
                            color: fgColor,
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            adj['label'] as String,
                            style: TextStyle(
                              color: fgColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
        ],
      ),
    );
  }

  // 필터 컨트롤 (필터 썸네일)
  Widget _buildFilterControls(
    BuildContext context,
    Color bgColor,
    Color fgColor,
  ) {
    final state = _getCurrentEditState();
    final filters = [
      {'name': 'Original', 'filter': null},
      {'name': 'Clear', 'filter': 'clear'},
      {'name': 'Lucent', 'filter': 'lucent'},
      {'name': 'Bright', 'filter': 'bright'},
      {'name': 'Tender', 'filter': 'tender'},
    ];

    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // 타이틀
          Text(
            '필터',
            style: TextStyle(
              color: fgColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // 필터 썸네일 리스트
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              itemBuilder: (context, index) {
                final filter = filters[index];
                final isSelected = state.selectedFilter == filter['filter'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            state.selectedFilter = filter['filter'];
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
                                      : fgColor.withOpacity(0.2),
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: FutureBuilder<ui.Image>(
                              future: _loadImage(currentImageBytes),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return CustomPaint(
                                    painter: _ImagePainter(snapshot.data!),
                                    size: Size.infinite,
                                  );
                                }
                                return Container(
                                  color: fgColor.withOpacity(0.1),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
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
                                  : fgColor,
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _applyEdit() {
    final currentImageBytes =
        _editedImages[_currentIndex] ?? _images[_currentIndex];

    switch (_editMode) {
      case _EditMode.crop:
        // 자르기 모드에서 회전이 있으면 적용
        final state = _getCurrentEditState();
        if (state.rotation != 0) {
          _applyRotation(currentImageBytes);
        }
        // TODO: 자르기 적용 로직
        break;
      case _EditMode.adjust:
      case _EditMode.filter:
        // TODO: 각 편집 모드별 적용 로직
        break;
      case _EditMode.none:
        break;
    }

    final savedIndex = _currentIndex; // 현재 인덱스 저장

    // PageView를 먼저 올바른 페이지로 이동
    if (_isMultiImage && _pageController.hasClients) {
      _pageController.jumpToPage(savedIndex);
    }

    setState(() {
      _editMode = _EditMode.none;
      final state = _getCurrentEditState();
      // 회전은 초기화하지 않음 (이미 적용된 회전 유지)
      state.imageOffset = Offset.zero; // 위치 초기화
      state.imageScale = 0.9; // 편집 모드 기본 스케일
    });

    // setState 후에도 다시 한 번 확인하여 동기화
    if (_isMultiImage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          final currentPage = _pageController.page?.round() ?? 0;
          if (currentPage != savedIndex) {
            _pageController.jumpToPage(savedIndex);
          }
        }
      });
    }
  }

  void _applyRotation(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return;

    final state = _getCurrentEditState();
    img.Image rotated = decoded;
    if (state.rotation == 90) {
      rotated = img.copyRotate(decoded, angle: 90);
    } else if (state.rotation == 180) {
      rotated = img.copyRotate(decoded, angle: 180);
    } else if (state.rotation == 270) {
      rotated = img.copyRotate(decoded, angle: 270);
    }

    final bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
    _onImageEdited(_currentIndex, bytes);
  }

  Future<void> _openCropEditor(int index, Uint8List imageBytes) async {
    final state = _getCurrentEditState();
    final result = await Navigator.push<Uint8List>(
      context,
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => CropScreen(
              imageBytes: imageBytes,
              initialAspectRatio: state.selectedAspectRatio,
            ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    if (result != null && mounted) {
      _onImageEdited(index, result);
    }
  }

  void _openAdjustEditor(int index, Uint8List imageBytes) {
    setState(() {
      _editMode = _EditMode.adjust;
      final state = _getCurrentEditState();
      state.imageOffset = Offset.zero; // 위치 초기화
      state.imageScale = 0.9; // 축소
    });
  }

  void _openFilterEditor(int index, Uint8List imageBytes) {
    setState(() {
      _editMode = _EditMode.filter;
      final state = _getCurrentEditState();
      state.imageOffset = Offset.zero; // 위치 초기화
      state.imageScale = 0.9; // 축소
    });
  }
}

/// 이미지 그리기용 Painter
class _ImagePainter extends CustomPainter {
  final ui.Image image;

  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final imageAspectRatio = image.width / image.height;
    final canvasAspectRatio = size.width / size.height;

    double drawWidth, drawHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspectRatio > canvasAspectRatio) {
      // 이미지가 더 넓음
      drawWidth = size.width;
      drawHeight = size.width / imageAspectRatio;
      offsetY = (size.height - drawHeight) / 2;
    } else {
      // 이미지가 더 높음
      drawHeight = size.height;
      drawWidth = size.height * imageAspectRatio;
      offsetX = (size.width - drawWidth) / 2;
    }

    final rect = Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
