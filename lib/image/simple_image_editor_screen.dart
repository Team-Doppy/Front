import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:flutter_svg/svg.dart';
import 'package:image/image.dart' as img;
import 'crop_editor.dart'
    show
        CropState,
        CropUtils,
        CropEditorBottomSheet,
        ImageRectUtils,
        ImagePainter,
        CropOverlayPainter,
        CropGestureUtils,
        CropHandleBuilder,
        CropGestureHandler,
        CropAutoZoom;
import 'rotation_editor.dart';
import 'adjustment_editor.dart';
import 'filter_editor.dart';
import 'utils/filter_presets.dart';

/// 간단한 커스텀 이미지 편집 화면
/// 바텀시트 기반 UI, Undo/Redo, 실시간 미리보기 제공
class SimpleImageEditorScreen extends StatefulWidget {
  const SimpleImageEditorScreen({
    super.key,
    this.imageBytes,
    this.imageBytesList,
    this.isExistingNodeEdit = false,
    this.enableLayoutSelectionForMultiImage = true,
    this.doneLabelOverride,
    this.onDone,
  }) : assert(
         imageBytes != null || imageBytesList != null,
         'imageBytes 또는 imageBytesList 중 하나는 필수입니다.',
       );

  final Uint8List? imageBytes;
  final List<Uint8List>? imageBytesList;

  /// ✅ 기존 문서 노드(이미지/로우/페이지뷰) 편집에서 진입한 경우 true.
  /// - 상단 버튼 텍스트를 "적용"으로 바꾼다.
  /// - (기본 설정과 함께) 멀티 이미지에서도 레이아웃 선택 UI를 띄우지 않도록 사용한다.
  final bool isExistingNodeEdit;

  /// 멀티 이미지 완료 시 레이아웃 선택 UI 표시 여부.
  /// - 기존 노드 편집에서는 false여야 한다(요구사항).
  final bool enableLayoutSelectionForMultiImage;

  /// 상단 완료 버튼 텍스트 강제 오버라이드 (필요 시).
  final String? doneLabelOverride;

  /// ✅ 완료 시 결과를 "Navigator.pop(result)"로 반환하지 않고, 호출자에게 위임하고 싶을 때 사용.
  /// (예: MediaPicker가 에디터/피커를 동시에 닫아야 하는 경우)
  final Future<void> Function(BuildContext editorContext, dynamic result)?
  onDone;

  @override
  State<SimpleImageEditorScreen> createState() =>
      _SimpleImageEditorScreenState();
}

enum _EditMode { none, crop, adjust, filter }

// 이미지별 편집 상태
class _ImageEditState {
  // 회전 관련 상태
  /// ✅ 미세 회전(크롭 눈금 슬라이더): -45 ~ 45 (degree)
  int rotation = 0;

  /// ✅ 90도 회전(버튼): 0,1,2,3 (quarter turns)
  /// - 실제 렌더/내보내기에서는 `rotation + rotationQuarterTurns * 90`으로 합산한다.
  int rotationQuarterTurns = 0;
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
  FilterModel? selectedFilter;
  double filterIntensity = 1.0;

  // 이미지 이동 및 스케일 관련 상태
  Offset imageOffset = Offset.zero;
  double imageScale = 1.0;
}

class _CropSessionSnapshot {
  const _CropSessionSnapshot({
    required this.bytes,
    required this.uiImage,
    required this.rotation,
    required this.rotationQuarterTurns,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.imageOffset,
    required this.imageScale,
    required this.selectedAspectRatio,
  });

  final Uint8List bytes;
  final ui.Image? uiImage;
  final int rotation;
  final int rotationQuarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final Offset imageOffset;
  final double imageScale;
  final String? selectedAspectRatio;
}

class _EditSnapshot {
  const _EditSnapshot({
    required this.rotation,
    required this.rotationQuarterTurns,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.selectedAspectRatio,
    required this.cropRectImage,
    required this.isCropRectInitialized,
    required this.imageOffset,
    required this.imageScale,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.warmth,
    required this.selectedFilter,
    required this.filterIntensity,
  });

  final int rotation;
  final int rotationQuarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;

  final String? selectedAspectRatio;
  final Rect? cropRectImage;
  final bool isCropRectInitialized;

  final Offset imageOffset;
  final double imageScale;

  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  final FilterModel? selectedFilter;
  final double filterIntensity;

  static _EditSnapshot fromState(_ImageEditState s) {
    return _EditSnapshot(
      rotation: s.rotation,
      rotationQuarterTurns: s.rotationQuarterTurns,
      flipHorizontal: s.flipHorizontal,
      flipVertical: s.flipVertical,
      selectedAspectRatio: s.selectedAspectRatio,
      cropRectImage: s.cropState.cropRectImage,
      isCropRectInitialized: s.cropState.isCropRectInitialized,
      imageOffset: s.imageOffset,
      imageScale: s.imageScale,
      brightness: s.brightness,
      contrast: s.contrast,
      saturation: s.saturation,
      warmth: s.warmth,
      selectedFilter: s.selectedFilter,
      filterIntensity: s.filterIntensity,
    );
  }

  void applyTo(_ImageEditState s) {
    s.rotation = rotation;
    s.rotationQuarterTurns = rotationQuarterTurns;
    s.flipHorizontal = flipHorizontal;
    s.flipVertical = flipVertical;

    s.selectedAspectRatio = selectedAspectRatio;
    s.cropState.selectedAspectRatio = selectedAspectRatio;
    s.cropState.cropRectImage = cropRectImage;
    s.cropState.isCropRectInitialized = isCropRectInitialized;

    s.imageOffset = imageOffset;
    s.imageScale = imageScale;

    s.brightness = brightness;
    s.contrast = contrast;
    s.saturation = saturation;
    s.warmth = warmth;

    s.selectedFilter = selectedFilter;
    s.filterIntensity = filterIntensity;
  }

  bool sameAs(_EditSnapshot other) {
    return rotation == other.rotation &&
        flipHorizontal == other.flipHorizontal &&
        flipVertical == other.flipVertical &&
        selectedAspectRatio == other.selectedAspectRatio &&
        cropRectImage == other.cropRectImage &&
        isCropRectInitialized == other.isCropRectInitialized &&
        imageOffset == other.imageOffset &&
        imageScale == other.imageScale &&
        brightness == other.brightness &&
        contrast == other.contrast &&
        saturation == other.saturation &&
        warmth == other.warmth &&
        selectedFilter == other.selectedFilter &&
        filterIntensity == other.filterIntensity;
  }
}

// ===== isolate helpers (encode) =====
Future<Uint8List> _encodeJpegFromRgba(_EncodeJpegArgs args) async {
  final image = img.Image.fromBytes(
    width: args.width,
    height: args.height,
    bytes: args.rgba.buffer,
    bytesOffset: args.rgba.offsetInBytes,
    numChannels: 4,
  );
  final encoded = img.encodeJpg(image, quality: args.quality);
  return Uint8List.fromList(encoded);
}

class _EncodeJpegArgs {
  const _EncodeJpegArgs({
    required this.width,
    required this.height,
    required this.rgba,
    required this.quality,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final int quality;
}

/// ✅ 비파괴 커밋 프리뷰: "크롭 결과"를 bytes로 굽지 않고 화면에서만 출력
class _CommittedCropPreviewPainter extends CustomPainter {
  _CommittedCropPreviewPainter({
    required this.image,
    required this.state,
    required this.containerSize,
  });

  final ui.Image image;
  final _ImageEditState state;
  final Size containerSize;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // 편집 시 사용하던 동일한 좌표계(마진 포함)
    final displayImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: imageSize,
      scale: state.imageScale,
      offset: state.imageOffset,
    );

    final cropRectImage = state.cropState.cropRectImage;
    if (!state.cropState.isCropRectInitialized || cropRectImage == null) {
      // 크롭이 없으면 원본을 그냥 보여준다
      final src = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      final dst = ImageRectUtils.computeImageRectForCrop(
        containerSize: size,
        imageSize: imageSize,
        scale: 1.0,
        offset: Offset.zero,
      );
      canvas.drawImageRect(image, src, dst, Paint());
      return;
    }

    final cropRectScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropRectImage,
      screenImageRect: displayImageRect,
      imageSize: imageSize,
    );

    // crop 결과를 화면 전체에 "contain"으로 보여준다 (추가 크롭 방지)
    final scaleToFit = math.min(
      size.width / cropRectScreen.width,
      size.height / cropRectScreen.height,
    );

    // 커버 보정(k)도 포함해서, 회전 시 빈 영역이 보이지 않도록(편집 프리뷰와 동일)
    final totalRotationDeg = state.rotation + (state.rotationQuarterTurns * 90);
    final theta = totalRotationDeg * (3.14159265359 / 180.0);
    final k = CropUtils.coverScaleToContainCropRect(
      imageRectScreen: displayImageRect,
      cropRectScreen: cropRectScreen,
      pivot: cropRectScreen.center,
      thetaRad: theta,
    );

    canvas.save();
    // cropRectScreen을 화면 중앙으로 옮기고, scaleToFit 적용
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scaleToFit);
    canvas.translate(-cropRectScreen.center.dx, -cropRectScreen.center.dy);

    // crop 영역만 보이도록 클립
    canvas.clipRect(cropRectScreen);

    // 회전/반전/커버 스케일: crop 중심 기준
    canvas.save();
    final cx = cropRectScreen.center.dx;
    final cy = cropRectScreen.center.dy;
    canvas.translate(cx, cy);
    if (totalRotationDeg != 0) {
      canvas.rotate(theta);
    }
    final sx = (state.flipHorizontal ? -1.0 : 1.0) * k;
    final sy = (state.flipVertical ? -1.0 : 1.0) * k;
    canvas.scale(sx, sy);
    canvas.translate(-cx, -cy);

    final srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    canvas.drawImageRect(image, srcRect, displayImageRect, Paint());
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CommittedCropPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.containerSize != containerSize ||
        oldDelegate.state.rotation != state.rotation ||
        oldDelegate.state.rotationQuarterTurns != state.rotationQuarterTurns ||
        oldDelegate.state.flipHorizontal != state.flipHorizontal ||
        oldDelegate.state.flipVertical != state.flipVertical ||
        oldDelegate.state.imageOffset != state.imageOffset ||
        oldDelegate.state.imageScale != state.imageScale ||
        oldDelegate.state.cropState.cropRectImage !=
            state.cropState.cropRectImage ||
        oldDelegate.state.cropState.isCropRectInitialized !=
            state.cropState.isCropRectInitialized;
  }
}

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

  // Undo/Redo 스택 (이미지별, "Apply 단위" 스냅샷) - 최대 20개로 제한됨
  final Map<int, List<_EditSnapshot>> _history = {};
  final Map<int, List<_EditSnapshot>> _redoStack = {};

  // 바텀시트 관련
  bool _isBottomSheetOpen = false;
  late AnimationController _bottomSheetController;
  late Animation<double> _bottomSheetAnimation;
  double _dragOffset = 0.0;

  // 메인 툴바(조정/자르기/회전/필터) 시각적 높이(대략값).
  // - 툴바를 트리에서 제거하면 바텀시트가 내려오는 동안 이미지가 하단 영역까지 확장됐다가
  //   마지막에 툴바가 "툭" 등장하며 점프하는 문제가 생김.
  // - 따라서 바텀시트 애니메이션과 반대로(닫힐수록) 툴바 높이를 함께 늘려 점프를 제거한다.
  static const double _mainToolbarHeight = 100.0;

  /// 바텀시트는 고정 height를 쓰지 않고, 모드별 "최대 높이"만 둔다.
  /// (모드별 레이아웃 요구사항이 달라 고정 숫자는 구조적으로 항상 깨짐)
  double get _bottomSheetMaxHeight {
    // 모드별 적절한 최대 높이 설정 (과도하게 높지 않게)
    switch (_editMode) {
      case _EditMode.crop:
        // 패널별 높이 조절은 crop_editor.dart 내부 위젯에서 처리
        return 320;
      case _EditMode.filter:
        return 280;
      case _EditMode.adjust:
        return 320; // 크롭과 동일한 높이
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

  // 조정 슬라이더 모드 여부
  bool _isAdjustmentSliderMode = false;
  final GlobalKey<AdjustmentEditorBottomSheetState> _adjustmentEditorKey =
      GlobalKey<AdjustmentEditorBottomSheetState>();

  // ✅ 완료(내보내기) 중 UI 피드백
  bool _isExporting = false;

  // ✅ 페이지뷰 스크롤 중(스와이프 미완료)에는 모드 전환을 막고, 진입 전 스냅 처리
  bool _isPageScrolling = false;

  // ✅ 크롭 Apply로 닫히는 동안(바텀시트 내려오는 중)엔 "커밋 프리뷰"를 먼저 보여준다
  bool _isClosingAfterCropApply = false;

  // 크롭 관련 상태
  final Map<int, Size> _imageDisplaySizes = {}; // 이미지별 표시 크기
  final Map<int, Size> _containerSizes = {}; // 이미지별 컨테이너 크기 (LayoutBuilder 기준)
  Size? _lastContainerSize; // ✅ export fallback 용 (offscreen page 대비)
  bool _isBottomSheetAnimationComplete = false; // 바텀시트 애니메이션 완료 여부

  // ✅ 크롭 제스처 핸들러 (이미지별)
  final Map<int, CropGestureHandler> _cropGestureHandlers = {};

  // ✅ 크롭(통합 편집) 진입 전 스냅샷: 취소/드래그 닫기 시 "진입 전 상태"로 복원
  final Map<int, _CropSessionSnapshot> _cropSessionSnapshots = {};

  _EditSnapshot _snapshotOf(int index) {
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    return _EditSnapshot.fromState(state);
  }

  void _applySnapshotToIndex(int index, _EditSnapshot snap) {
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    snap.applyTo(state);
    // crop 제스처 임시 상태는 초기화
    _getCropGestureHandler(index).reset();
  }

  // (표준 비파괴 편집) bytes 기반 커밋이 없으므로 "커밋 후 state 리셋" 유틸은 사용하지 않는다.

  _CropSessionSnapshot _makeCropSnapshot(int index) {
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    return _CropSessionSnapshot(
      bytes: _images[index],
      uiImage: _uiImageCache[index],
      rotation: state.rotation,
      rotationQuarterTurns: state.rotationQuarterTurns,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
      imageOffset: state.imageOffset,
      imageScale: state.imageScale,
      selectedAspectRatio: state.selectedAspectRatio,
    );
  }

  void _restoreCropSnapshotIfAny(int index) {
    final snap = _cropSessionSnapshots.remove(index);
    if (snap == null) return;

    // bytes 복원
    _images[index] = snap.bytes;

    // ui.Image 캐시 복원(가능하면 즉시), 없으면 로드
    if (snap.uiImage != null) {
      _uiImageCache[index] = snap.uiImage;
    } else {
      _uiImageCache[index] = null;
      _loadImageToCache(index, snap.bytes);
    }

    // 편집 상태 복원 (특히 rotation/flip이 남아있으면 취소 후 화면이 "이상"해짐)
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    state.rotation = snap.rotation;
    state.rotationQuarterTurns = snap.rotationQuarterTurns;
    state.flipHorizontal = snap.flipHorizontal;
    state.flipVertical = snap.flipVertical;
    state.imageOffset = snap.imageOffset;
    state.imageScale = snap.imageScale;
    state.selectedAspectRatio = snap.selectedAspectRatio;
    state.cropState.reset();

    // crop gesture handler도 초기화
    _getCropGestureHandler(index).reset();
  }

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
      // ✅ 히스토리 시드(표준): bytes가 아니라 "편집 상태 스냅샷"을 1개 넣어둔다
      final s = _imageEditStates.putIfAbsent(i, () => _ImageEditState());
      _history.putIfAbsent(i, () => []).add(_EditSnapshot.fromState(s));
      _redoStack.putIfAbsent(i, () => []).clear();
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

  // (표준 비파괴 편집) Apply/Undo/Redo에서 bytes를 교체하지 않으므로
  // _setImageBytesWithFade는 현재 사용하지 않는다.

  Widget _buildPaintWithFade({
    required BuildContext context,
    required int index,
    required Uint8List bytesForFallbackLoad,
    required _ImageEditState state,
  }) {
    final curr = _uiImageCache[index];
    final v = _applyAnimVersion[index] ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    // 최초 로딩(캐시에 아무것도 없을 때만) — 적용 순간엔 여기에 잘 안 들어오게 만드는 게 목표
    if (curr == null) {
      return Center(
        child: FutureBuilder<ui.Image>(
          future: _loadImage(bytesForFallbackLoad),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // ✅ 기존 노드 편집 진입(isExistingNodeEdit)에서는 진입 전에 이미 로딩을 보여줬으므로
              // 여기서 초기 로딩 UI를 다시 띄우지 않는다.
              if (widget.isExistingNodeEdit) {
                return const SizedBox.shrink();
              }
              return SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: fgColor,
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

  void _resetCurrentAdjustmentValue() {
    final type = _adjustmentEditorKey.currentState?.selectedType;
    if (type == null) return;
    final state = _getCurrentEditState();

    setState(() {
      switch (type) {
        case AdjustmentType.brightness:
          state.brightness = 0.0;
          break;
        case AdjustmentType.contrast:
          state.contrast = 0.0;
          break;
        case AdjustmentType.saturation:
          state.saturation = 0.0;
          break;
        case AdjustmentType.temperature:
          // SimpleImageEditorScreen 내부 필드는 warmth로 관리
          state.warmth = 0.0;
          break;
        // 아직 bytes에 반영되지 않는 항목들은 no-op (추후 확장)
        case AdjustmentType.luminance:
        case AdjustmentType.exposure:
        case AdjustmentType.sharpness:
        case AdjustmentType.blur:
        case AdjustmentType.vignette:
          break;
      }
      // ✅ 리셋 후 히스토리에 저장 (언두 가능하도록)
      _saveToHistorySnapshot(_currentIndex);
    });
  }

  void _resetAllAdjustments() {
    final state = _getCurrentEditState();
    setState(() {
      state.brightness = 0.0;
      state.contrast = 0.0;
      state.saturation = 0.0;
      state.warmth = 0.0;
    });
  }

  void _resetFilterToOriginal() {
    final state = _getCurrentEditState();
    setState(() {
      state.selectedFilter = null;
      state.filterIntensity = 1.0;
    });
  }

  void _reinitCropRectForCurrent() {
    final containerSize = _containerSizes[_currentIndex];
    final uiImage = _uiImageCache[_currentIndex];
    if (uiImage == null || containerSize == null) return;
    final state = _getCurrentEditState();
    CropUtils.initializeCropRect(
      image: uiImage,
      containerSize: containerSize,
      cropState: state.cropState,
      scale: state.imageScale,
      offset: state.imageOffset,
      onDisplaySizeChanged: (size) {
        _imageDisplaySizes[_currentIndex] = size;
      },
    );
  }

  void _resetCropAll() {
    final state = _getCurrentEditState();
    setState(() {
      state.selectedAspectRatio = null;
      state.cropState.reset();
      state.rotation = 0;
      state.rotationQuarterTurns = 0;
      state.flipHorizontal = false;
      state.flipVertical = false;
      state.imageOffset = Offset.zero;
      state.imageScale = 1.0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_reinitCropRectForCurrent);
    });
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

  void _snapPageViewToNearestPageIfNeeded() {
    if (!_isMultiImage) return;
    if (!_pageController.hasClients) return;

    final p = _pageController.page;
    if (p == null) return;
    final target = p.round();
    if ((p - target).abs() < 0.001) return;

    // 중간 위치에서 편집 모드로 진입하면 옆 이미지가 "침범"해 보이므로 즉시 스냅
    _pageController.jumpToPage(target);
    _currentIndex = target;
  }

  // (표준 비파괴 편집) bytes를 중간에 교체하지 않으므로
  // _onImageEdited / _onCropApplied 같은 "bytes 커밋" 루틴은 사용하지 않는다.

  void _saveToHistorySnapshot(int index) {
    final history = _history.putIfAbsent(index, () => []);
    final snap = _snapshotOf(index);

    if (history.isEmpty) {
      history.add(snap);
      _redoStack.putIfAbsent(index, () => []).clear();
      return;
    }

    // ✅ 연속 중복 스냅샷 방지 (Apply 눌렀는데 변화 없으면 스택 증가 X)
    if (history.last.sameAs(snap)) return;

    history.add(snap);
    _redoStack.putIfAbsent(index, () => []).clear();
    if (history.length > 20) {
      history.removeAt(0);
    }
  }

  void _undo() {
    final history = _history[_currentIndex];
    if (history == null || history.length <= 1) return;

    history.removeLast();
    final previous = history.last;
    _redoStack
        .putIfAbsent(_currentIndex, () => [])
        .add(_snapshotOf(_currentIndex));
    setState(() {
      _applySnapshotToIndex(_currentIndex, previous);
    });
  }

  void _redo() {
    final redoStack = _redoStack[_currentIndex];
    if (redoStack == null || redoStack.isEmpty) return;

    final redoSnap = redoStack.removeLast();
    _history
        .putIfAbsent(_currentIndex, () => [])
        .add(_snapshotOf(_currentIndex));
    setState(() {
      _applySnapshotToIndex(_currentIndex, redoSnap);
    });
  }

  Future<void> _handleDone() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    // 화면 업데이트를 위해 한 프레임 대기
    await Future.delayed(Duration.zero);
    final sw = Stopwatch()..start();
    try {
      // ✅ 1) 멀티 이미지
      if (_images.length >= 2) {
        // ✅ 안전장치: 기존 노드 편집에서는 어떤 경우에도 레이아웃 선택 UI를 띄우지 않는다.
        final allowLayoutSelection =
            widget.enableLayoutSelectionForMultiImage &&
            !widget.isExistingNodeEdit;

        if (!allowLayoutSelection) {
          final bakedImages = await _bakeAllFinalBytes();
          if (!mounted) return;
          if (widget.onDone != null) {
            await widget.onDone!(context, bakedImages);
            return;
          }
          Navigator.pop(context, bakedImages);
          return;
        }

        // ✅ 신규/갤러리: 레이아웃 선택을 먼저 띄우고(즉시 반응), 그동안 백그라운드로 굽기 진행
        // preview는 "현재 bytes"로 충분 (레이아웃 선택용)
        final tempDir = await Directory.systemTemp.createTemp('image_preview_');
        final previewFiles = <File>[];
        for (int i = 0; i < _images.length; i++) {
          final f = File('${tempDir.path}/preview_$i.jpg');
          await f.writeAsBytes(_images[i]);
          previewFiles.add(f);
        }

        // 굽기 작업 시작 (선택 UI가 열린 동안 진행)
        final bakeFuture = _bakeAllFinalBytes();

        final layout = await showModalBottomSheet<GroupImageLayout>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: true,
          enableDrag: true,
          builder:
              (context) => FractionallySizedBox(
                heightFactor: 0.93,
                child: GroupImageLayoutSelector(previewImages: previewFiles),
              ),
        );

        // preview temp 정리 (실패해도 무시)
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}

        if (!mounted) return;
        if (layout == null) return;

        // 선택 후에는 "굽기 완료"를 기다리는 동안 로딩 표시
        if (!_isExporting) setState(() => _isExporting = true);
        await Future.delayed(Duration.zero);

        final bakedImages = await bakeFuture;

        if (!mounted) return;
        final payload = {'images': bakedImages, 'layout': layout};
        if (widget.onDone != null) {
          await widget.onDone!(context, payload);
          return;
        }
        Navigator.pop(context, payload);
        return;
      }

      // ✅ 2) 단일 이미지는 레이아웃 선택 없이 바로 1장만 굽고 반환
      final baked = await _exportFinalBytes(0);
      if (!mounted) return;
      if (widget.onDone != null) {
        await widget.onDone!(context, baked);
        return;
      }
      Navigator.pop(context, baked);
      return;
    } finally {
      sw.stop();
      debugPrint(
        '[SimpleImageEditor] 완료(export) 소요: ${sw.elapsedMilliseconds}ms',
      );
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<List<Uint8List>> _bakeAllFinalBytes() async {
    final out = <Uint8List>[];
    for (int i = 0; i < _images.length; i++) {
      // ✅ 변경 없는 이미지는 굽지 않고 원본 bytes 그대로 반환 (속도 최적화)
      final initial =
          _history[i]?.isNotEmpty == true ? _history[i]!.first : null;
      if (initial != null) {
        final current = _snapshotOf(i);
        if (current.sameAs(initial)) {
          out.add(_images[i]);
          continue;
        }
      }
      // UI에 프레임을 양보해서(특히 레이아웃 선택 중) 덜 끊기게
      await Future.delayed(Duration.zero);
      out.add(await _exportFinalBytes(i));
    }
    return out;
  }

  /// ✅ 표준(비파괴) 내보내기: 마지막 "추가/완료" 시점에만 1회 굽는다.
  ///
  /// - crop(회전/반전 포함)은 `CropUtils.applyCropWithTransform`로 최종 pixels 생성
  /// - 필터/보정은 마지막에 color matrix로 굽는다.
  Future<Uint8List> _exportFinalBytes(int index) async {
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    Uint8List bytes = _images[index];

    // 1) 크롭이 커밋되어 있으면: 크롭(+회전/반전)까지 한 번에 굽는다.
    if (state.cropState.isCropRectInitialized &&
        state.cropState.cropRectImage != null) {
      final uiImage = _uiImageCache[index] ?? await _loadImage(_images[index]);
      final containerSize = _containerSizes[index] ?? _lastContainerSize;
      if (containerSize != null) {
        try {
          final cropped = await CropUtils.applyCropWithTransform(
            uiImage: uiImage,
            cropState: state.cropState,
            containerSize: containerSize,
            scale: state.imageScale,
            offset: state.imageOffset,
            rotationDeg: state.rotation + (state.rotationQuarterTurns * 90),
            flipHorizontal: state.flipHorizontal,
            flipVertical: state.flipVertical,
          );
          if (cropped != null) {
            bytes = cropped;
          }
        } catch (e) {
          debugPrint('[SimpleImageEditor] 크롭 export 실패: $e');
        }
      } else {
        debugPrint('[SimpleImageEditor] containerSize가 없어 크롭 export를 스킵합니다.');
      }
    } else {
      // 2) 크롭이 없으면: 회전/반전만 bytes에 굽는다.
      try {
        if (state.flipHorizontal) {
          bytes = RotationEditor.flip(bytes, horizontal: true);
        }
        if (state.flipVertical) {
          bytes = RotationEditor.flip(bytes, horizontal: false);
        }
        final totalRotation =
            state.rotation + (state.rotationQuarterTurns * 90);
        if (totalRotation != 0) {
          bytes = RotationEditor.rotate(bytes, angle: totalRotation.toDouble());
        }
      } catch (e) {
        debugPrint('[SimpleImageEditor] 회전/반전 export 실패: $e');
      }
    }

    // 3) 필터/보정(밝기/대비/채도)은 화면 렌더링만 되므로 마지막에 굽는다.
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
    final filterMatrix = FilterUtils.getFilterMatrix(
      state.selectedFilter,
      intensity: state.filterIntensity,
    );
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

    // ✅ PNG 인코딩은 매우 느리고(특히 고해상도) 결과 bytes도 커짐 → JPEG로 변경
    // - rawRgba는 빠르게 뽑고, JPEG 인코딩은 isolate(compute)에서 수행
    final bd = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) throw StateError('toByteData returned null');

    // 기본 품질: 92 (용량/속도/품질 밸런스)
    const quality = 92;
    return await compute(
      _encodeJpegFromRgba,
      _EncodeJpegArgs(
        width: out.width,
        height: out.height,
        rgba: bd.buffer.asUint8List(),
        quality: quality,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Scaffold(
      // ✅ 에디터 진입 순간에도 배경색이 비지 않도록 Scaffold 레벨에서 기본 배경을 깔아준다.
      backgroundColor: bgColor.withOpacity(0.8),
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
                                          color: fgColor,
                                        ),
                                      ),
                                      if (!_isBottomSheetOpen) ...[
                                        IconButton(
                                          onPressed:
                                              ((_history[_currentIndex]
                                                              ?.length ??
                                                          0) >
                                                      1)
                                                  ? (_isExporting
                                                      ? null
                                                      : _undo)
                                                  : null,
                                          icon: SvgPicture.asset(
                                            'assets/icons/editor_undo.svg',
                                            width: 30,
                                            height: 30,
                                            colorFilter: ColorFilter.mode(
                                              ((_history[_currentIndex]
                                                              ?.length ??
                                                          0) >
                                                      1)
                                                  ? fgColor
                                                  : fgColor.withOpacity(0.3),
                                              BlendMode.srcIn,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed:
                                              (_redoStack[_currentIndex]
                                                          ?.isNotEmpty ??
                                                      false)
                                                  ? (_isExporting
                                                      ? null
                                                      : _redo)
                                                  : null,
                                          icon: SvgPicture.asset(
                                            'assets/icons/editor_redo.svg',
                                            width: 30,
                                            height: 30,
                                            colorFilter: ColorFilter.mode(
                                              (_redoStack[_currentIndex]
                                                          ?.isNotEmpty ??
                                                      false)
                                                  ? fgColor
                                                  : fgColor.withOpacity(0.3),
                                              BlendMode.srcIn,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (!_isBottomSheetOpen)
                                    GestureDetector(
                                      onTap:
                                          (_isExporting || _isPageScrolling)
                                              ? null
                                              : _handleDone,
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
                                            child:
                                                _isExporting
                                                    ? Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: const [],
                                                    )
                                                    : Text(
                                                      widget.doneLabelOverride ??
                                                          (widget.isExistingNodeEdit
                                                              ? l10n.t('apply')
                                                              : l10n
                                                                  .t(
                                                                    'add_with_count',
                                                                  )
                                                                  .replaceAll(
                                                                    '{count}',
                                                                    '${_images.length}',
                                                                  )),
                                                      style: TextStyle(
                                                        color: fgColor,
                                                        fontSize: 17,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                    child: AnimatedBuilder(
                      animation: _bottomSheetAnimation,
                      builder: (context, _) {
                        return _isMultiImage
                            ? NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                if (n is ScrollStartNotification) {
                                  if (!_isPageScrolling) {
                                    setState(() => _isPageScrolling = true);
                                  }
                                } else if (n is ScrollEndNotification) {
                                  if (_isPageScrolling) {
                                    setState(() => _isPageScrolling = false);
                                  }
                                }
                                return false;
                              },
                              child: PageView.builder(
                                controller: _pageController,
                                onPageChanged: _onPageChanged,
                                physics:
                                    (_isBottomSheetOpen ||
                                            _editMode != _EditMode.none)
                                        ? const NeverScrollableScrollPhysics()
                                        : const PageScrollPhysics(),
                                itemCount: _images.length,
                                itemBuilder: (context, index) {
                                  return _buildImagePreview(
                                    context,
                                    index,
                                    _images[index],
                                    shouldHideCropOverlay:
                                        _editMode == _EditMode.crop &&
                                        _bottomSheetAnimation.value < 1.0,
                                  );
                                },
                              ),
                            )
                            : _buildImagePreview(
                              context,
                              0,
                              _images[0],
                              shouldHideCropOverlay:
                                  _editMode == _EditMode.crop &&
                                  _bottomSheetAnimation.value < 1.0,
                            );
                      },
                    ),
                  ),

                  AnimatedBuilder(
                    animation: _bottomSheetAnimation,
                    builder: (context, _) {
                      // 바텀시트가 열려있을수록(1.0) 툴바는 0, 닫힐수록(0.0) 툴바는 1
                      final toolbarFactor = (1.0 - _bottomSheetAnimation.value)
                          .clamp(0.0, 1.0);

                      // UI 숨김 상태면 "보이진 않되" 레이아웃 점프 방지
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
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    // ✅ 페이지 인디케이터 (툴바와 간격 확보)
                                    if (_editMode == _EditMode.none &&
                                        _isMultiImage)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: _mainToolbarHeight + 20,
                                        child: IgnorePointer(
                                          child: Center(
                                            child: Text(
                                              '${_currentIndex + 1}/${_images.length}',
                                              style: TextStyle(
                                                color: fgColor.withOpacity(0.9),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // ✅ 기존 툴바 그대로
                                    _buildMainToolbar(),
                                  ],
                                ),
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    if (_editMode == _EditMode.adjust &&
                                        _isAdjustmentSliderMode) {
                                      // 조정 슬라이더 모드일 때는 버튼 모드로 돌아가기
                                      _adjustmentEditorKey.currentState
                                          ?.resetToButtonMode();
                                    } else {
                                      _closeBottomSheet(cancel: true);
                                    }
                                  },
                                  child: Text(
                                    _editMode == _EditMode.crop
                                        ? l10n.t('back')
                                        : (_editMode == _EditMode.adjust &&
                                            _isAdjustmentSliderMode)
                                        ? l10n.t('back')
                                        : l10n.t('cancel'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: fgColor.withOpacity(0.9),
                                    ),
                                  ),
                                ),
                                // ✅ 크롭/조정/필터: 진입 즉시 옵션 제목 + 리셋 버튼 표시
                                if (_editMode == _EditMode.crop)
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            l10n.t('crop'),
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              color: fgColor.withOpacity(0.9),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: _resetCropAll,
                                            behavior:
                                                HitTestBehavior.translucent,
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.refresh,
                                                size: 24,
                                                color: fgColor.withOpacity(0.9),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else if (_editMode == _EditMode.adjust)
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _isAdjustmentSliderMode
                                                ? (_adjustmentEditorKey
                                                        .currentState
                                                        ?.selectedType
                                                        ?.label ??
                                                    '')
                                                : l10n.t('adjust'),
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              color: fgColor.withOpacity(0.9),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap:
                                                _isAdjustmentSliderMode
                                                    ? _resetCurrentAdjustmentValue
                                                    : _resetAllAdjustments,
                                            behavior:
                                                HitTestBehavior.translucent,
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.refresh,
                                                size:
                                                    24, // ✅ 리셋 아이콘 크기 증가 (18 -> 24)
                                                color: fgColor.withOpacity(0.9),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else if (_editMode == _EditMode.filter)
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Builder(
                                            builder: (context) {
                                              final state =
                                                  _getCurrentEditState();
                                              final name =
                                                  (state.selectedFilter !=
                                                              null &&
                                                          state
                                                                  .selectedFilter!
                                                                  .name !=
                                                              '원본')
                                                      ? state
                                                              .selectedFilter
                                                              ?.name ??
                                                          l10n.t('filter')
                                                      : l10n.t('filter');
                                              return Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                  color: fgColor.withOpacity(
                                                    0.9,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: _resetFilterToOriginal,
                                            behavior:
                                                HitTestBehavior.translucent,
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.refresh,
                                                size: 24,
                                                color: fgColor.withOpacity(0.9),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  const Spacer(),
                                TextButton(
                                  onPressed: () async {
                                    await _applyEdit();
                                    if (_editMode == _EditMode.crop) {
                                      // ✅ 바텀시트가 내려오기 전에 먼저 "커밋 프리뷰"로 전환
                                      setState(() {
                                        _isClosingAfterCropApply = true;
                                      });
                                    }
                                    _closeBottomSheet(cancel: false);
                                  },
                                  child: Text(
                                    _editMode == _EditMode.crop
                                        ? l10n.t('apply')
                                        : l10n.t('complete'),
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

          // ✅ 완료(export) 중에는 즉시 피드백(로딩 오버레이)
          if (_isExporting)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: bgColor.withOpacity(0.25),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: fgColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainToolbar() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    return GestureDetector(
      // ✅ 툴바 영역 터치 이벤트 차단 (배경 GestureDetector와 충돌 방지)
      onTap: () {}, // 빈 핸들러로 터치 이벤트 소비
      behavior: HitTestBehavior.opaque,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: IgnorePointer(
            ignoring: _isExporting || _isPageScrolling,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _GlassToolButton(
                      icon: Icons.tune,
                      label: l10n.t('adjust'),
                      onTap: _toggleAdjustment,
                      isActive: _editMode == _EditMode.adjust,
                      textColor: fgColor,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: fgColor.withOpacity(0.2),
                    ),
                    _GlassToolButton(
                      icon: Icons.crop,
                      label: l10n.t('crop'),
                      onTap: _openCropPanel,
                      isActive: _editMode == _EditMode.crop,
                      textColor: fgColor,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: fgColor.withOpacity(0.2),
                    ),
                    _GlassToolButton(
                      icon: Icons.color_lens,
                      label: l10n.t('filter'),
                      onTap: _toggleFilter,
                      isActive: _editMode == _EditMode.filter,
                      textColor: fgColor,
                    ),
                  ],
                ),
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
    Rect? cropRectScreen,
    Rect? imageRectForCrop,
  ) {
    final totalRotationDeg = state.rotation + (state.rotationQuarterTurns * 90);
    final rotationRadians = totalRotationDeg * (3.14159265359 / 180.0);

    final basePaint = _buildPaintWithFade(
      context: context,
      index: index,
      bytesForFallbackLoad: currentImageBytes,
      state: state,
    );

    // ✅ 조정 모드일 때는 key를 고정하여 위젯 재생성 방지 (이미지 크기 고정)
    final imageWidget =
        _getColorFilter(state) != null
            ? ColorFiltered(
              key:
                  _editMode == _EditMode.adjust
                      ? ValueKey('adjust_mode_$index') // 조정 모드일 때는 고정 key
                      : ValueKey(
                        '${state.selectedFilter}_${state.brightness}_${state.contrast}_${state.saturation}',
                      ),
              colorFilter: _getColorFilter(state)!,
              child: basePaint,
            )
            : basePaint;

    final anchor =
        cropRectScreen?.center ??
        Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );

    // 표준: 회전된 외접 사각형이 cropRect를 덮도록 하는 최소 배율(상태값은 건드리지 않음)
    // ✅ 조정 모드일 때는 크롭 관련 계산을 하지 않아서 이미지 크기가 고정됨
    double k = 1.0;
    if (_editMode == _EditMode.crop &&
        cropRectScreen != null &&
        imageRectForCrop != null) {
      k = CropUtils.coverScaleToContainCropRect(
        imageRectScreen: imageRectForCrop,
        cropRectScreen: cropRectScreen,
        pivot: anchor,
        thetaRad: rotationRadians,
      );
    }

    final sx = (state.flipHorizontal ? -1.0 : 1.0) * k;
    final sy = (state.flipVertical ? -1.0 : 1.0) * k;

    final m =
        Matrix4.identity()
          ..translate(anchor.dx, anchor.dy)
          ..rotateZ(rotationRadians)
          ..scale(sx, sy)
          ..translate(-anchor.dx, -anchor.dy);

    return RepaintBoundary(child: Transform(transform: m, child: imageWidget));
  }

  Widget _buildImagePreview(
    BuildContext context,
    int index,
    Uint8List imageBytes, {
    bool shouldHideCropOverlay = false,
  }) {
    // ✅ 중요: PageView는 index별로 렌더링되므로, state도 index별로 가져와야 한다.
    // (현재 페이지 state(_currentIndex)를 쓰면 페이지 넘길 때마다 "편집이 풀리거나 섞이는" 현상이 발생)
    final state = _imageEditStates.putIfAbsent(index, () => _ImageEditState());
    final currentImageBytes = imageBytes; // ✅ 이미 _images[index]가 전달됨
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        // LayoutBuilder의 containerSize 저장 (MediaQuery.size 대신 사용)
        _containerSizes[index] = containerSize;
        _lastContainerSize = containerSize;

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
        // ✅ 조정 모드일 때는 이미지 rect를 캐싱하여 크기 고정
        Rect? currentImageRect;
        if (imageSize != null) {
          if (_editMode == _EditMode.crop) {
            currentImageRect = ImageRectUtils.computeImageRectForCrop(
              containerSize: containerSize,
              imageSize: imageSize,
              scale: state.imageScale,
              offset: state.imageOffset,
            );
          } else if (_editMode == _EditMode.adjust) {
            // ✅ 조정 모드일 때는 캐시된 rect 사용 (크기 고정)
            final cachedSize = _imageDisplaySizes[index];
            if (cachedSize == null) {
              // 최초 계산 시에만 계산하고 저장
              currentImageRect = ImageRectUtils.computeImageRect(
                containerSize: containerSize,
                imageSize: imageSize,
                scale: state.imageScale,
                offset: state.imageOffset,
              );
              _imageDisplaySizes[index] = currentImageRect.size;
            } else {
              // 캐시된 크기로 rect 재구성 (오프셋만 현재 값 사용)
              final baseRect = ImageRectUtils.computeImageRect(
                containerSize: containerSize,
                imageSize: imageSize,
                scale: 1.0, // scale 1.0 기준으로 계산
                offset: Offset.zero,
              );
              // baseRect는 null이 될 수 없음 (imageSize가 null이 아니므로)
              // 캐시된 크기 비율로 스케일 계산
              final scaleRatio = cachedSize.width / baseRect.width;
              final scaledWidth = baseRect.width * scaleRatio;
              final scaledHeight = baseRect.height * scaleRatio;
              final offsetX =
                  baseRect.left - (scaledWidth - baseRect.width) / 2;
              final offsetY =
                  baseRect.top - (scaledHeight - baseRect.height) / 2;
              currentImageRect = Rect.fromLTWH(
                offsetX + state.imageOffset.dx,
                offsetY + state.imageOffset.dy,
                scaledWidth,
                scaledHeight,
              );
            }
          } else {
            currentImageRect = ImageRectUtils.computeImageRect(
              containerSize: containerSize,
              imageSize: imageSize,
              scale: state.imageScale,
              offset: state.imageOffset,
            );
          }
        }

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
                child: AnimatedPadding(
                  // ✅ 크롭 모드일 때만 6px 패딩 적용 (부드러운 전환)
                  padding:
                      _editMode == _EditMode.crop
                          ? const EdgeInsets.all(6.0)
                          : EdgeInsets.zero,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: RepaintBoundary(
                    child:
                        ((_editMode != _EditMode.crop ||
                                    _isClosingAfterCropApply) &&
                                state.cropState.isCropRectInitialized &&
                                state.cropState.cropRectImage != null &&
                                _uiImageCache[index] != null)
                            ? (_getColorFilter(state) != null
                                ? ColorFiltered(
                                  colorFilter: _getColorFilter(state)!,
                                  child: CustomPaint(
                                    painter: _CommittedCropPreviewPainter(
                                      image: _uiImageCache[index]!,
                                      state: state,
                                      containerSize: containerSize,
                                    ),
                                    size: Size.infinite,
                                  ),
                                )
                                : CustomPaint(
                                  painter: _CommittedCropPreviewPainter(
                                    image: _uiImageCache[index]!,
                                    state: state,
                                    containerSize: containerSize,
                                  ),
                                  size: Size.infinite,
                                ))
                            : _buildRotatedImage(
                              context,
                              index,
                              currentImageBytes,
                              state,
                              cropRectScreen,
                              imageRectForCrop,
                            ),
                  ),
                ),
              ),
              // 2️⃣ 크롭 오버레이 레이어 (transform 미적용 - screen 좌표로 직접 그림)
              if (_editMode == _EditMode.crop &&
                  !shouldHideCropOverlay &&
                  !_isClosingAfterCropApply &&
                  cropRectScreen != null &&
                  imageRectForCrop != null)
                IgnorePointer(
                  // 크롭 오버레이는 터치 이벤트를 차단 (이미지 드래그를 위해)
                  child: CustomPaint(
                    painter: CropOverlayPainter(
                      cropRectScreen: cropRectScreen,
                      imageRect: imageRectForCrop,
                      overlayColor: bgColor.withOpacity(0.8),
                      borderColor: fgColor,
                    ),
                    size: Size.infinite,
                  ),
                ),
              // 3️⃣ 크롭 핸들들 (이미 screen 좌표 사용 중)
              // ✅ 드래그 중이면 고정된 cropRectScreen 전달
              if (_editMode == _EditMode.crop &&
                  !shouldHideCropOverlay &&
                  !_isClosingAfterCropApply &&
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
                  handleColor: fgColor,
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
                    // 🎯 리사이즈 완료 시 즉시 Auto Zoom 실행
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
    final filterMatrix = FilterUtils.getFilterMatrix(
      state.selectedFilter,
      intensity: state.filterIntensity,
    );
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

  List<double>? _getAdjustmentMatrix(_ImageEditState state) {
    return AdjustmentUtils.getAdjustmentMatrix(
      brightness: state.brightness,
      contrast: state.contrast,
      saturation: state.saturation,
    );
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

  void _openCropPanel() {
    final state = _getCurrentEditState();

    setState(() {
      if (_editMode != _EditMode.crop) {
        _isClosingAfterCropApply = false;
        // ✅ 스와이프 중 진입 방지 + 중간 페이지면 스냅
        _snapPageViewToNearestPageIfNeeded();

        // ✅ 크롭 진입 전 상태 저장(취소/드래그 닫기 시 복원)
        _cropSessionSnapshots[_currentIndex] = _makeCropSnapshot(_currentIndex);

        // ✅ 표준(비파괴): 기존 커밋 상태를 유지한 채 크롭 편집으로 진입
        // (이미 커밋된 cropRect/rotation/flip/scale/offset이 있으면 그대로 편집 이어가기)
        if (!state.cropState.isCropRectInitialized) {
          state.cropState.isCropRectInitialized = false;
        }
        _isBottomSheetAnimationComplete = false;
        _getCropGestureHandler(_currentIndex).reset();

        _editMode = _EditMode.crop;
        _isBottomSheetOpen = true;
        _bottomSheetController.forward();
      }
    });
  }

  void _toggleFilter() {
    if (_isPageScrolling) return;
    _snapPageViewToNearestPageIfNeeded();
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
    if (_isPageScrolling) return;
    _snapPageViewToNearestPageIfNeeded();
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
    // ✅ 취소 버튼을 누르거나 바텀시트를 내리면 즉시 크롭박스 숨기기
    if (cancel && _editMode == _EditMode.crop) {
      // ✅ 취소/드래그 닫기: "크롭 진입 전 이미지"로 즉시 복원 (애니메이션 내려가는 동안에도 정상 표시)
      _restoreCropSnapshotIfAny(_currentIndex);
      setState(() {});
    }
    // ✅ 필터 모드 취소 시 원본으로 복귀
    if (cancel && _editMode == _EditMode.filter) {
      final state = _getCurrentEditState();
      setState(() {
        state.selectedFilter = null;
        state.filterIntensity = 1.0;
      });
    }
    // ✅ 애니메이션이 완전히 끝난 후에만 상태 변경 (오버플로우 방지)
    _bottomSheetController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        // 취소 케이스 복원은 위에서 즉시 처리한다.

        _isBottomSheetOpen = false;
        _editMode = _EditMode.none;
        _dragOffset = 0.0;
        _isClosingAfterCropApply = false;
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
      final nextFilter = FilterUtils.getNextFilter(
        state.selectedFilter,
        deltaX,
      );
      setState(() {
        state.selectedFilter = nextFilter;
      });
    }
  }

  void _onFilterSwipeEnd(DragEndDetails details) {
    _hasSwiped = false;
  }

  Future<void> _applyEdit() async {
    // ✅ 표준(비파괴): Apply는 bytes 굽기/교체 없이 "상태 스냅샷"만 히스토리에 커밋한다.
    _saveToHistorySnapshot(_currentIndex);
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

  // (표준 비파괴 편집) 크롭 Apply에서 bytes를 바로 만들지 않는다.

  Widget _buildCropBottomSheet() {
    final state = _getCurrentEditState();

    String? _invertAspectRatio(String? ratio) {
      if (ratio == null) return null;
      final parts = ratio.split(':');
      if (parts.length != 2) return ratio;
      if (parts[0] == parts[1]) return ratio; // 1:1
      return '${parts[1]}:${parts[0]}';
    }

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
      onRotationChanged:
          (v) => setState(() {
            // ✅ ±45도로 제한
            state.rotation = v.clamp(-45, 45);
          }),
      onRotate90: () {
        // ✅ 요청사항: 90도 회전은 "완전히 새로운 이미지처럼" 취급
        // - 기존 크롭 영역/계산( cropRect / scale / offset / gesture frozen rect )을 모두 폐기하고
        // - 새 기준으로 cropRect를 다시 초기화한다.
        setState(() {
          // 1) 90도 회전(버튼) 누적
          state.rotationQuarterTurns = (state.rotationQuarterTurns + 1) % 4;

          // 2) 고정 비율이면 방향도 같이 뒤집기(예: 16:9 ↔ 9:16, 4:5 ↔ 5:4)
          state.selectedAspectRatio = _invertAspectRatio(
            state.selectedAspectRatio,
          );

          // 3) 기존 크롭 관련 상태 "전부" 초기화
          state.rotation = 0; // 미세 회전은 새 기준으로 다시 시작
          state.imageOffset = Offset.zero;
          state.imageScale = 1.0;

          // cropState.reset()은 비율도 날리므로, 비율은 다시 주입
          final keepRatio = state.selectedAspectRatio;
          state.cropState.reset();
          state.cropState.selectedAspectRatio = keepRatio;
        });

        // 4) 제스처 핸들러(Freeze 등)도 초기화하고, 다음 프레임에서 cropRect 재초기화
        _getCropGestureHandler(_currentIndex).reset();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(reinitCropRect);
        });
      },
      onResetRotation:
          () => setState(() {
            state.rotation = 0;
            state.rotationQuarterTurns = 0;
          }),
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
          state.rotationQuarterTurns = 0;
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
    final currentImageBytes = _images[_currentIndex];

    return FilterEditorBottomSheet(
      selectedFilter: state.selectedFilter,
      filterIntensity: state.filterIntensity,
      imageBytes: currentImageBytes,
      isExistingNodeEdit: widget.isExistingNodeEdit,
      onFilterChanged: (filter) {
        // ✅ 필터 선택만 하고 히스토리는 저장하지 않음 (바텀시트 닫을 때만 저장)
        setState(() {
          state.selectedFilter = filter;
        });
      },
      onFilterIntensityChanged: (intensity) {
        // ✅ 필터 강도 변경 (히스토리는 저장하지 않음)
        setState(() {
          state.filterIntensity = intensity;
        });
      },
    );
  }

  Widget _buildAdjustmentBottomSheet() {
    final state = _getCurrentEditState();

    // AdjustmentState로 변환
    final adjustmentState =
        AdjustmentState()
          ..brightness = state.brightness
          ..contrast = state.contrast
          ..saturation = state.saturation;

    return AdjustmentEditorBottomSheet(
      key: _adjustmentEditorKey,
      state: adjustmentState,
      onStateChanged: (newState) {
        setState(() {
          state.brightness = newState.brightness;
          state.contrast = newState.contrast;
          state.saturation = newState.saturation;
          // 추가 속성들 (향후 구현)
          // state.luminance = newState.luminance;
          // state.exposure = newState.exposure;
          // state.sharpness = newState.sharpness;
          // state.temperature = newState.temperature;
          // state.blur = newState.blur;
          // state.vignette = newState.vignette;
        });
        // ✅ 슬라이더 드래그 중에는 히스토리에 저장하지 않음 (드래그 종료 시 저장)
      },
      onSliderModeChanged: (isSliderMode) {
        setState(() {
          _isAdjustmentSliderMode = isSliderMode;
        });
      },
      onDragEnd: () {
        // ✅ 슬라이더 드래그 종료 시 히스토리에 저장 (언두/리두 가능하도록)
        _saveToHistorySnapshot(_currentIndex);
      },
    );
  }
}

class _GlassToolButton extends StatelessWidget {
  const _GlassToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // ✅ 버튼 영역만 터치 받도록 명시
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
