import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:doppy/image/video_edit_spec.dart';
import 'crop_editor.dart'
    show
        CropState,
        CropUtils,
        CropEditorBottomSheet,
        ImageRectUtils,
        CropOverlayPainter,
        CropGestureUtils,
        CropHandleBuilder,
        CropHandleType,
        ScaleUpdateResult,
        CropDragEndResult,
        AutoZoomResult;
import 'adjustment_editor.dart';
import 'filter_editor.dart';
import 'speed_editor.dart';
import 'utils/filter_presets.dart';

/// 간단한 커스텀 비디오 편집 화면
/// 바텀시트 기반 UI, Undo/Redo, 실시간 미리보기 제공
class SimpleVideoEditorScreen extends StatefulWidget {
  const SimpleVideoEditorScreen({
    super.key,
    this.videoFile,
    this.videoFileList,
    this.isExistingNodeEdit = false,
    this.doneLabelOverride,
    this.onDone,
    this.initialEditSpec,
    this.initialEditSpecs,
  }) : assert(
         videoFile != null || videoFileList != null,
         'videoFile 또는 videoFileList 중 하나는 필수입니다.',
       ),
       assert(
         initialEditSpec == null || initialEditSpecs == null,
         'initialEditSpec과 initialEditSpecs는 동시에 사용할 수 없습니다.',
       );

  final File? videoFile;
  final List<File>? videoFileList;

  /// ✅ 기존 문서 노드(비디오) 편집에서 진입한 경우 true.
  /// - 상단 버튼 텍스트를 "적용"으로 바꾼다.
  final bool isExistingNodeEdit;

  /// 상단 완료 버튼 텍스트 강제 오버라이드 (필요 시).
  final String? doneLabelOverride;

  /// ✅ 완료 시 결과를 "Navigator.pop(result)"로 반환하지 않고, 호출자에게 위임하고 싶을 때 사용.
  /// (예: MediaPicker가 에디터/피커를 동시에 닫아야 하는 경우)
  final Future<void> Function(BuildContext editorContext, dynamic result)?
  onDone;

  /// ✅ 편집 화면을 다시 열 때(예: 트리머에서 뒤로) 이전 편집 상태를 복원하기 위한 초기 스펙(단일 비디오).
  final VideoEditSpec? initialEditSpec;

  /// ✅ 여러 비디오 편집 시, 인덱스별 초기 스펙.
  final List<VideoEditSpec>? initialEditSpecs;

  @override
  State<SimpleVideoEditorScreen> createState() =>
      _SimpleVideoEditorScreenState();
}

enum _EditMode { none, crop, adjust, filter, speed }

// 비디오별 편집 상태
class _VideoEditState {
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
  double luminance = 0.0; // -100 ~ 100
  double exposure = 0.0; // -100 ~ 100
  double sharpness = 0.0; // 0 ~ 100
  double temperature = 0.0; // -100 ~ 100 (차갑게 ~ 따뜻하게)
  double blur = 0.0; // 0 ~ 100
  double vignette = 0.0; // 0 ~ 100

  // 필터 관련 상태
  FilterModel? selectedFilter;
  double filterIntensity = 1.0;

  // 이미지 이동 및 스케일 관련 상태
  Offset imageOffset = Offset.zero;
  double imageScale = 1.0;

  // 재생 속도 (미리보기)
  double playbackSpeed = 1.0; // 0.5 ~ 2.0
}

class _CropSessionSnapshot {
  const _CropSessionSnapshot({
    required this.videoFile,
    required this.controller,
    required this.rotation,
    required this.rotationQuarterTurns,
    required this.flipHorizontal,
    required this.flipVertical,
    required this.cropRectImage,
    required this.isCropRectInitialized,
    required this.imageOffset,
    required this.imageScale,
    required this.selectedAspectRatio,
  });

  final File videoFile;
  final VideoPlayerController? controller;
  final int rotation;
  final int rotationQuarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final Rect? cropRectImage;
  final bool isCropRectInitialized;
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
    required this.luminance,
    required this.exposure,
    required this.sharpness,
    required this.temperature,
    required this.blur,
    required this.vignette,
    required this.selectedFilter,
    required this.filterIntensity,
    required this.playbackSpeed,
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
  final double luminance;
  final double exposure;
  final double sharpness;
  final double temperature;
  final double blur;
  final double vignette;

  final FilterModel? selectedFilter;
  final double filterIntensity;
  final double playbackSpeed;

  static _EditSnapshot fromState(_VideoEditState s) {
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
      luminance: s.luminance,
      exposure: s.exposure,
      sharpness: s.sharpness,
      temperature: s.temperature,
      blur: s.blur,
      vignette: s.vignette,
      selectedFilter: s.selectedFilter,
      filterIntensity: s.filterIntensity,
      playbackSpeed: s.playbackSpeed,
    );
  }

  void applyTo(_VideoEditState s) {
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
    s.luminance = luminance;
    s.exposure = exposure;
    s.sharpness = sharpness;
    s.temperature = temperature;
    s.blur = blur;
    s.vignette = vignette;

    s.selectedFilter = selectedFilter;
    s.filterIntensity = filterIntensity;
    s.playbackSpeed = playbackSpeed;
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
        luminance == other.luminance &&
        exposure == other.exposure &&
        sharpness == other.sharpness &&
        temperature == other.temperature &&
        blur == other.blur &&
        vignette == other.vignette &&
        selectedFilter == other.selectedFilter &&
        filterIntensity == other.filterIntensity &&
        playbackSpeed == other.playbackSpeed;
  }
}

/// 비디오용 크롭 제스처 핸들러
/// CropGestureHandler의 로직을 참고하여 Size 기반으로 구현
class VideoCropGestureHandler {
  // 드래그 중 상태
  bool _isDraggingImage = false;
  Rect? _frozenImageRect;
  Offset? _lastPanPosition;
  CropHandleType? _activeCropHandle;

  // 핀치 줌 상태
  double? _initialScale; // 핀치 시작 시 초기 scale
  bool _isPinching = false;

  // 드래그 감도 및 복귀 감도
  static const double _dragResistance = 0.6;
  static const double _minImageScale = 1.0; // 최소 줌 레벨 (축소 제한)
  static const double _maxImageScale = 5.0; // 최대 줌 레벨
  static const double _pinchEpsilon = 0.001; // 핀치로 판단할 최소 scale 변화량
  static const double _snapTolerancePx = 0.5; // 스냅백/커버 판정 픽셀 오차 허용치
  static const double _edgeToleranceImagePx = 0.1; // 이미지 좌표 경계 판정 여유값

  /// snapBackOffset이 있으면 반영한 최종 offset을 반환한다.
  Offset _applySnapBackOffset(Offset imageOffset, Offset? snapBackOffset) {
    return snapBackOffset != null
        ? (imageOffset + snapBackOffset)
        : imageOffset;
  }

  /// freeze(렌더 기준)로 고정된 screen cropRect를, 특정 screenImageRect 기준의 image 좌표로 1회 재투영한다.
  Rect? _projectScreenRectToImageRect({
    required Rect screenCropRect,
    required Rect screenImageRect,
    required Size imageSize,
  }) {
    final sx = screenImageRect.width / imageSize.width;
    final sy = screenImageRect.height / imageSize.height;
    if (sx <= 0 || sy <= 0) return null;

    final projectedLeft = (screenCropRect.left - screenImageRect.left) / sx;
    final projectedTop = (screenCropRect.top - screenImageRect.top) / sy;
    final projectedWidth = screenCropRect.width / sx;
    final projectedHeight = screenCropRect.height / sy;

    final clampedLeft = projectedLeft.clamp(0.0, imageSize.width);
    final clampedTop = projectedTop.clamp(0.0, imageSize.height);
    final clampedWidth = projectedWidth.clamp(
      0.0,
      imageSize.width - clampedLeft,
    );
    final clampedHeight = projectedHeight.clamp(
      0.0,
      imageSize.height - clampedTop,
    );

    return Rect.fromLTWH(clampedLeft, clampedTop, clampedWidth, clampedHeight);
  }

  /// 제스처 종료 후 공통 상태 리셋
  void _resetGestureState({required bool clearFrozen}) {
    _isDraggingImage = false;
    if (clearFrozen) _frozenImageRect = null;
    _initialScale = null;
    _isPinching = false;
  }

  /// 현재 이미지가 screenCropRect(=고정된 크롭 박스)를 완전히 덮지 못하면,
  /// 그 차이를 기준으로 snapBackOffset을 계산한다.
  Offset? _computeSnapBackOffset({
    required Rect currentImageRect,
    required Rect screenCropRect,
  }) {
    double adjustX = 0.0;
    double adjustY = 0.0;

    // 좌/우
    if (currentImageRect.left > screenCropRect.left + _snapTolerancePx) {
      adjustX = screenCropRect.left - currentImageRect.left;
    } else if (currentImageRect.right <
        screenCropRect.right - _snapTolerancePx) {
      adjustX = screenCropRect.right - currentImageRect.right;
    }

    // 상/하
    if (currentImageRect.top > screenCropRect.top + _snapTolerancePx) {
      adjustY = screenCropRect.top - currentImageRect.top;
    } else if (currentImageRect.bottom <
        screenCropRect.bottom - _snapTolerancePx) {
      adjustY = screenCropRect.bottom - currentImageRect.bottom;
    }

    if (adjustX == 0.0 && adjustY == 0.0) return null;

    return Offset(adjustX, adjustY);
  }

  /// 드래그 시작 처리
  void onScaleStart({
    required ScaleStartDetails details,
    required CropState cropState,
    required Size videoSize,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    _lastPanPosition = details.focalPoint;
    _initialScale = imageScale; // 핀치 줌을 위한 초기 scale 저장
    _isPinching = false;

    if (cropState.isCropRectInitialized && cropState.cropRectImage != null) {
      final currentImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: videoSize,
        scale: imageScale,
        offset: imageOffset,
      );

      // ✅ 드래그/핀치 시작 시 imageRect만 freeze (렌더 기준/복귀 기준)
      _frozenImageRect = currentImageRect;
      _isDraggingImage = true;
    }
  }

  /// 드래그 업데이트 처리 (고무줄 저항 포함) + 핀치 줌 처리
  ScaleUpdateResult? onScaleUpdate({
    required ScaleUpdateDetails details,
    required CropState cropState,
    required Size videoSize,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
    required VoidCallback onStateChanged,
  }) {
    if (!cropState.isCropRectInitialized) return null;
    // 핸들 드래그 중이면 무시
    if (_activeCropHandle != null) return null;

    // 핀치 줌 처리 (scale 변화가 있을 때)
    if ((details.scale - 1.0).abs() >= _pinchEpsilon) {
      _isPinching = true;
      _initialScale ??= imageScale;

      // ✅ 핀치 감도 조정: details.scale에 감쇠 적용 (너무 민감하지 않도록)
      // details.scale은 누적값이므로, 증분만큼만 적용
      final scaleDelta = details.scale - 1.0;
      final dampedScaleDelta = scaleDelta * 0.5; // 감도 50%로 감쇠
      final dampedScale = 1.0 + dampedScaleDelta;

      // 새로운 scale 계산 (초기 scale * 감쇠된 scale 변화)
      double newScale = _initialScale! * dampedScale;

      // ✅ 축소 시도 시: 현재 스케일이 이미 1.0 이하면 더 이상 축소 불가
      if (dampedScale < 1.0 && imageScale <= _minImageScale) {
        // 축소 시도 무시
        return null;
      }

      // ✅ 핀치 축소 허용 조건: 이미지가 cropRect를 덮고 있어야 함
      // 단, newScale이 1.0 이상이면 체크 스킵 (1.0 미만으로만 제한)
      if (dampedScale < 1.0 &&
          newScale < _minImageScale &&
          cropState.cropRectImage != null) {
        final Rect? frozenCropRectScreen =
            (_frozenImageRect != null)
                ? ImageRectUtils.imageToScreenRect(
                  imageRect: cropState.cropRectImage!,
                  screenImageRect: _frozenImageRect!,
                  imageSize: videoSize,
                )
                : null;

        final testImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: videoSize,
          scale: newScale,
          offset: imageOffset,
        );

        final testCropRectScreen =
            frozenCropRectScreen ??
            ImageRectUtils.imageToScreenRect(
              imageRect: cropState.cropRectImage!,
              screenImageRect: testImageRect,
              imageSize: videoSize,
            );

        // ✅ 이미지가 cropRect를 완전히 덮지 못하면 축소 금지
        if (testImageRect.left > testCropRectScreen.left + _snapTolerancePx ||
            testImageRect.top > testCropRectScreen.top + _snapTolerancePx ||
            testImageRect.right < testCropRectScreen.right - _snapTolerancePx ||
            testImageRect.bottom <
                testCropRectScreen.bottom - _snapTolerancePx) {
          // 축소 금지: 현재 scale 유지
          return null;
        }
      }

      // 최소 scale 제한
      if (newScale < _minImageScale) {
        return null;
      }

      // 최대 scale 제한
      newScale = newScale.clamp(_minImageScale, _maxImageScale);

      // ✅ 핀치 중에는 cropRectImage를 변경하지 않음 (크롭박스 고정)
      // 오직 imageScale만 변경하여 영상만 작아지고 커지게 함
      // cropRectImage 재투영은 핀치 종료 시에만 수행

      return ScaleUpdateResult(scale: newScale, offset: null);
    }

    // 핀치 줌이 아닌 경우 (scale이 1.0에 가까움) = 일반 드래그
    _isPinching = false;
    // (1) delta 계산 (이전 위치와 현재 위치의 차이)
    if (_lastPanPosition == null) {
      _lastPanPosition = details.focalPoint;
      return null;
    }
    final delta = details.focalPoint - _lastPanPosition!;
    _lastPanPosition = details.focalPoint;

    // ✅ 스케일이 1.0 이하이고 크롭박스가 이미지 경계에 붙어있으면 드래그 막기
    if (imageScale <= _minImageScale && cropState.cropRectImage != null) {
      final cropRect = cropState.cropRectImage!;

      // 왼쪽으로 드래그하려고 하는데 왼쪽 경계에 붙어있으면 막기
      if (delta.dx < 0 && cropRect.left <= _edgeToleranceImagePx) {
        return null;
      }
      // 오른쪽으로 드래그하려고 하는데 오른쪽 경계에 붙어있으면 막기
      if (delta.dx > 0 &&
          cropRect.right >= videoSize.width - _edgeToleranceImagePx) {
        return null;
      }
      // 위로 드래그하려고 하는데 위쪽 경계에 붙어있으면 막기
      if (delta.dy < 0 && cropRect.top <= _edgeToleranceImagePx) {
        return null;
      }
      // 아래로 드래그하려고 하는데 아래쪽 경계에 붙어있으면 막기
      if (delta.dy > 0 &&
          cropRect.bottom >= videoSize.height - _edgeToleranceImagePx) {
        return null;
      }
    }

    final proposedOffset = imageOffset + delta;

    // (2) 고무줄 감쇠 판정
    final testImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: imageScale,
      offset: proposedOffset,
    );
    // ✅ 중요한 기준 통일:
    // - 크롭 모드에서 사용자가 보는 크롭박스(screen)는 "frozenImageRect 기준"으로 고정돼야 한다.
    final Rect cropRectScreen =
        (_frozenImageRect != null)
            ? ImageRectUtils.imageToScreenRect(
              imageRect: cropState.cropRectImage!,
              screenImageRect: _frozenImageRect!,
              imageSize: videoSize,
            )
            : ImageRectUtils.imageToScreenRect(
              imageRect: cropState.cropRectImage!,
              screenImageRect: testImageRect,
              imageSize: videoSize,
            );

    // (3) 고무줄 감쇠 적용
    double dx = delta.dx;
    double dy = delta.dy;

    // ✅ 이미지가 고정 크롭박스를 덮지 못하려고 하면 저항을 준다.
    final outX =
        testImageRect.left > cropRectScreen.left + _snapTolerancePx ||
        testImageRect.right < cropRectScreen.right - _snapTolerancePx;
    final outY =
        testImageRect.top > cropRectScreen.top + _snapTolerancePx ||
        testImageRect.bottom < cropRectScreen.bottom - _snapTolerancePx;

    if (outX) {
      dx *= _dragResistance;
    }

    if (outY) {
      dy *= _dragResistance;
    }

    // (4) 새로운 offset 반환
    return ScaleUpdateResult(
      scale: null,
      offset: Offset(dx / imageScale, dy / imageScale),
    );
  }

  /// 드래그 종료 처리 (복귀 로직 포함) + 핀치 줌 종료 처리
  CropDragEndResult? onScaleEnd({
    required CropState cropState,
    required Size videoSize,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    _lastPanPosition = null;

    // ✅ 핸들 리사이즈 중이면 복귀 로직 스킵
    if (_activeCropHandle != null) {
      _resetGestureState(clearFrozen: true);
      return null;
    }

    // ✅ 핀치 줌이 끝났을 때 처리
    if (_isPinching) {
      return _handlePinchEnd(
        cropState: cropState,
        videoSize: videoSize,
        containerSize: containerSize,
        imageScale: imageScale,
        imageOffset: imageOffset,
      );
    }

    return _handleDragEnd(
      cropState: cropState,
      videoSize: videoSize,
      containerSize: containerSize,
      imageScale: imageScale,
      imageOffset: imageOffset,
    );
  }

  // ----------------------------
  // onScaleEnd 내부 책임 분리
  // ----------------------------
  CropDragEndResult? _handlePinchEnd({
    required CropState cropState,
    required Size videoSize,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    // scale이 최소값보다 작으면 복귀
    if (imageScale < _minImageScale) {
      _resetGestureState(clearFrozen: true);

      // scale을 최소값으로 복귀
      return CropDragEndResult(
        snapBackOffset: null,
        cropRectImagePosition: null,
        cropRectImageSize: null,
        snapBackScale: _minImageScale, // 복귀할 scale 값
      );
    }

    // ✅ 핀치 줌 후: 확대/축소 구분하여 처리
    // 현재 scale 기준으로 이미지 rect 계산
    final currentImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: imageScale,
      offset: imageOffset,
    );

    // 화면에서 크롭박스 위치는 고정 (frozenImageRect 기준으로 즉시 계산)
    if (_frozenImageRect != null && _initialScale != null) {
      final frozenCropRectScreen = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: _frozenImageRect!,
        imageSize: videoSize,
      );
      // ✅ 확대/축소 판단: 초기 scale과 현재 scale 비교
      final isZoomIn = imageScale > _initialScale!; // 확대
      final isZoomOut = imageScale < _initialScale!; // 축소

      final snapBackOffset = _computeSnapBackOffset(
        currentImageRect: currentImageRect,
        screenCropRect: frozenCropRectScreen,
      );

      // ✅ 확대 핀치: cropRectImage 절대 재계산하지 않음 (고정)
      if (isZoomIn) {
        // 스냅백이 적용된 최종 offset 기준으로 imageRect를 계산해야, 재투영이 일관된다.
        final finalOffset = _applySnapBackOffset(imageOffset, snapBackOffset);
        final finalImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: videoSize,
          scale: imageScale,
          offset: finalOffset,
        );

        final projected = _projectScreenRectToImageRect(
          screenCropRect: frozenCropRectScreen,
          screenImageRect: finalImageRect,
          imageSize: videoSize,
        );
        if (projected == null) {
          _resetGestureState(clearFrozen: true);
          return CropDragEndResult(
            snapBackOffset: snapBackOffset,
            cropRectImagePosition: null,
            cropRectImageSize: null,
            snapBackScale: null,
          );
        }

        // zoom-in 종료 후에는 freeze 해제
        _resetGestureState(clearFrozen: true);

        return CropDragEndResult(
          snapBackOffset: snapBackOffset,
          cropRectImagePosition: projected.topLeft,
          cropRectImageSize: projected.size,
          snapBackScale: null,
        );
      }

      // ✅ 축소 핀치: 화면에서 크롭박스 고정 (확대와 동일한 방식)
      // - 축소 중에도 크롭 박스(screen)는 고정되어야 함
      // - zoom-out 종료 시점에 "고정된 screen cropRect"를 최종 imageRect 기준으로 재투영
      // - 크롭박스 크기는 유지하고 위치만 조정하여 화면에서 고정 유지
      if (isZoomOut) {
        // 스냅백이 적용된 최종 offset 기준으로 imageRect를 계산해야, 재투영이 일관된다.
        final finalOffset = _applySnapBackOffset(imageOffset, snapBackOffset);
        final finalImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: videoSize,
          scale: imageScale,
          offset: finalOffset,
        );

        // ✅ frozenCropRectScreen을 기준으로 재투영 (크롭박스 화면 고정)
        final projected = _projectScreenRectToImageRect(
          screenCropRect: frozenCropRectScreen,
          screenImageRect: finalImageRect,
          imageSize: videoSize,
        );
        if (projected == null) {
          _resetGestureState(clearFrozen: true);
          return CropDragEndResult(
            snapBackOffset: snapBackOffset,
            cropRectImagePosition: null,
            cropRectImageSize: null,
            snapBackScale: null,
          );
        }

        // zoom-out 종료 후에는 freeze 해제 (크롭박스는 재투영으로 고정 유지)
        _resetGestureState(clearFrozen: true);

        return CropDragEndResult(
          snapBackOffset: snapBackOffset,
          cropRectImagePosition: projected.topLeft,
          cropRectImageSize: projected.size,
          snapBackScale: null,
        );
      }
    }

    _resetGestureState(clearFrozen: true);
    return null;
  }

  CropDragEndResult? _handleDragEnd({
    required CropState cropState,
    required Size videoSize,
    required Size containerSize,
    required double imageScale,
    required Offset imageOffset,
  }) {
    // ✅ 드래그 완료 시: 고정된 기준으로 크롭박스 밖으로 나갔는지 확인 후 복귀
    if (cropState.isCropRectInitialized &&
        _isDraggingImage &&
        _frozenImageRect != null) {
      // 현재 이미지 rect (최종 offset 기준)
      final currentImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: videoSize,
        scale: imageScale,
        offset: imageOffset,
      );

      // ✅ 고정된 기준(frozenImageRect)으로 "화면 크롭박스"를 즉시 계산해 벗어남 확인
      final frozenCropRectScreen = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: _frozenImageRect!,
        imageSize: videoSize,
      );
      final snapBackOffset = _computeSnapBackOffset(
        currentImageRect: currentImageRect,
        screenCropRect: frozenCropRectScreen,
      );

      // ✅ 드래그 완료 시: 화면 중앙 기준으로 cropRectImage 재계산
      final finalOffset = _applySnapBackOffset(imageOffset, snapBackOffset);
      final finalImageRect = ImageRectUtils.computeImageRectForCrop(
        containerSize: containerSize,
        imageSize: videoSize,
        scale: imageScale,
        offset: finalOffset,
      );
      final containerCenter = Offset(
        containerSize.width / 2,
        containerSize.height / 2,
      );
      final sx = finalImageRect.width / videoSize.width;
      final sy = finalImageRect.height / videoSize.height;
      final cropSizeScreen = Size(
        cropState.cropRectImage!.width * sx,
        cropState.cropRectImage!.height * sy,
      );
      final centerScreenRect = Rect.fromCenter(
        center: containerCenter,
        width: cropSizeScreen.width,
        height: cropSizeScreen.height,
      );
      // 화면 좌표 → 이미지 좌표 변환
      final cropRectImageUpdate = Offset(
        (centerScreenRect.left - finalImageRect.left) / sx,
        (centerScreenRect.top - finalImageRect.top) / sy,
      );

      // ✅ 드래그 종료 시 freeze 해제
      _isDraggingImage = false;
      _frozenImageRect = null;
      _initialScale = null;
      _isPinching = false;

      return CropDragEndResult(
        snapBackOffset: snapBackOffset,
        cropRectImagePosition: cropRectImageUpdate, // ✅ 화면 중앙 기준으로 재계산
        cropRectImageSize: Size(
          cropState.cropRectImage!.width,
          cropState.cropRectImage!.height,
        ),
      );
    }

    // ✅ 드래그 종료 시 freeze 해제
    _isDraggingImage = false;
    _frozenImageRect = null;
    _initialScale = null;
    _isPinching = false;

    return null;
  }

  /// 활성 핸들 설정
  void setActiveHandle(CropHandleType? handle) {
    _activeCropHandle = handle;
  }

  /// 활성 핸들 가져오기
  CropHandleType? get activeHandle => _activeCropHandle;

  /// 드래그 중 여부
  bool get isDraggingImage => _isDraggingImage;

  /// 핀치 중 여부
  bool get isPinching => _isPinching;

  /// Freeze된 이미지 rect 가져오기
  Rect? get frozenImageRect => _frozenImageRect;

  /// 리셋
  void reset() {
    _isDraggingImage = false;
    _frozenImageRect = null;
    _lastPanPosition = null;
    _activeCropHandle = null;
    _initialScale = null;
    _isPinching = false;
  }
}

/// 비디오용 Auto Zoom 유틸리티
class VideoCropAutoZoom {
  VideoCropAutoZoom._();

  /// 크롭 윈도우가 화면의 80% 범위를 유지하도록 자동 줌
  /// 크롭 윈도우 중심을 화면 중앙에 맞춤
  static AutoZoomResult autoZoomToCrop({
    required CropState cropState,
    required Size videoSize,
    required Size containerSize,
    required double currentScale,
    required Offset currentOffset,
  }) {
    if (cropState.cropRectImage == null) {
      return AutoZoomResult(scale: currentScale, offset: currentOffset);
    }

    final width = containerSize.width;
    final height = containerSize.height;
    final containerCenter = Offset(width / 2, height / 2);

    // ✅ image 좌표 기준으로 한 번만 계산
    // 1) 크롭 중심을 image 좌표에서 직접 가져오기
    final cropCenterImage = cropState.cropRectImage!.center;

    // 2) 현재 scale 기준으로 크롭 크기 계산 (scale 결정용)
    final currentImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: currentScale,
      offset: Offset.zero,
    );

    final currentCropRectScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropState.cropRectImage!,
      screenImageRect: currentImageRect,
      imageSize: videoSize,
    );

    // 3) 크롭 윈도우 크기에 따라 scale 계산
    const maxZoom = 5.0;
    const minRatio = 0.75; // 최소 75% (줌 인 - 리사이즈 후 크롭박스가 화면의 75% 차지)
    const maxRatio = 0.8; // 최대 80% (줌 아웃 기준)

    final cropRatioX = currentCropRectScreen.width / width;
    final cropRatioY = currentCropRectScreen.height / height;
    final cropRatio = cropRatioX < cropRatioY ? cropRatioX : cropRatioY;

    double targetScale = currentScale;

    // 크롭이 너무 작으면 줌 인
    if (cropRatio < minRatio && currentScale < maxZoom) {
      targetScale = (currentScale / cropRatio * minRatio).clamp(1.0, maxZoom);
    }
    // 크롭이 너무 크면 줌 아웃 (단, scale이 1보다 클 때만)
    else if (cropRatio > maxRatio && currentScale > 1.0) {
      targetScale = (currentScale / cropRatio * maxRatio).clamp(1.0, maxZoom);
    }

    // ✅ targetScale 적용 후 실제 이미지 rect가 화면 안에 들어오는지 검증
    double finalTargetScale = targetScale;

    // targetScale로 계산된 이미지 rect 확인
    final testImageRect = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: targetScale,
      offset: Offset.zero,
    );

    // 이미지가 화면 안에 들어오는지 확인
    if (testImageRect.left < 0 ||
        testImageRect.top < 0 ||
        testImageRect.right > width ||
        testImageRect.bottom > height) {
      // 이미지가 화면 안에 들어오는 최대 scale 계산
      final imageAspect = videoSize.width / videoSize.height;
      final containerAspect = width / height;

      double maxValidScale;
      if (imageAspect > containerAspect) {
        final baseDisplayHeight = width / imageAspect;
        maxValidScale = height / baseDisplayHeight;
      } else {
        final baseDisplayWidth = height * imageAspect;
        final maxScaleByWidth = width / baseDisplayWidth;

        final cropWidth = cropState.cropRectImage!.width;
        final cropHeight = cropState.cropRectImage!.height;

        final maxScaleByCropWidth =
            (width * videoSize.width) / (cropWidth * height * imageAspect);
        final maxScaleByCropHeight =
            (height * videoSize.height) / (cropHeight * height);

        final maxScaleByCrop =
            maxScaleByCropWidth < maxScaleByCropHeight
                ? maxScaleByCropWidth
                : maxScaleByCropHeight;

        maxValidScale =
            maxScaleByWidth < maxScaleByCrop ? maxScaleByWidth : maxScaleByCrop;
      }

      maxValidScale = maxValidScale > maxZoom ? maxZoom : maxValidScale;

      // 추가로 크롭박스 크기 기준으로도 제한
      final testCropRect = ImageRectUtils.imageToScreenRect(
        imageRect: cropState.cropRectImage!,
        screenImageRect: testImageRect,
        imageSize: videoSize,
      );

      if (testCropRect.width > width || testCropRect.height > height) {
        final cropWidthRatio = testCropRect.width / width;
        final cropHeightRatio = testCropRect.height / height;
        final cropMaxRatio =
            cropWidthRatio > cropHeightRatio ? cropWidthRatio : cropHeightRatio;
        final maxCropScale = targetScale / cropMaxRatio;
        maxValidScale =
            maxValidScale < maxCropScale ? maxValidScale : maxCropScale;
      }

      finalTargetScale = targetScale.clamp(1.0, maxValidScale);
    }

    targetScale = finalTargetScale;

    // 4) targetScale 적용 후 이미지 rect 계산 (offset=0 기준)
    final imageRectAtTargetScale = ImageRectUtils.computeImageRectForCrop(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: targetScale,
      offset: Offset.zero,
    );

    // 5) crop 중심을 image 좌표에서 직접 screen 좌표로 변환
    final scaleX = imageRectAtTargetScale.width / videoSize.width;
    final scaleY = imageRectAtTargetScale.height / videoSize.height;

    final cropCenterScreenAtTargetScale = Offset(
      imageRectAtTargetScale.left + cropCenterImage.dx * scaleX,
      imageRectAtTargetScale.top + cropCenterImage.dy * scaleY,
    );

    // 6) offset 계산
    final targetOffset = containerCenter - cropCenterScreenAtTargetScale;

    return AutoZoomResult(scale: targetScale, offset: targetOffset);
  }
}

class _SimpleVideoEditorScreenState extends State<SimpleVideoEditorScreen>
    with TickerProviderStateMixin {
  static const Duration _cropSnapBackDuration = Duration(milliseconds: 180);

  AnimationController? _cropSnapBackController;
  // ✅ 현재 표시할 비디오 파일 리스트 (편집이 반영된 비디오)
  late final List<File> _videos;
  late final PageController _pageController;
  int _currentIndex = 0;
  _EditMode _editMode = _EditMode.none;
  // ✅ 비디오 컨트롤러 캐시
  final Map<int, VideoPlayerController?> _videoControllers = {};
  // ✅ 초기화 중인 컨트롤러 추적 (중복 초기화 방지)
  final Map<int, Future<VideoPlayerController>> _initializingControllers = {};
  static const int _maxVideoCacheSize = 10; // 최대 비디오 컨트롤러 캐시 크기

  // ✅ 필터 모드용 썸네일 캐시 (깜빡임 방지)
  final Map<int, Uint8List?> _thumbnailCache = {};
  final Map<int, Future<Uint8List?>> _thumbnailFutures = {};

  // ✅ “확 바뀌는 것” 방지용: 이전 프레임 비디오 보관 + 크로스페이드
  final Map<int, int> _applyAnimVersion = {};
  static const Duration _applySettleDuration = Duration(milliseconds: 140);

  // 비디오별 편집 상태 관리
  final Map<int, _VideoEditState> _videoEditStates = {};

  // Undo/Redo 스택 (비디오별, "Apply 단위" 스냅샷) - 최대 20개로 제한됨
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
      case _EditMode.speed:
        return 320;
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
            : _editMode == _EditMode.speed
            ? _buildSpeedBottomSheet()
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

  // ✅ 조정 상세(슬라이더) 모드 여부
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
  bool _isBottomSheetAnimationComplete = false; // 바텀시트 애니메이션 완료 여부

  // ✅ 크롭 제스처 핸들러 (이미지별)
  final Map<int, VideoCropGestureHandler> _cropGestureHandlers = {};

  // ✅ 크롭(통합 편집) 진입 전 스냅샷: 취소/드래그 닫기 시 "진입 전 상태"로 복원
  final Map<int, _CropSessionSnapshot> _cropSessionSnapshots = {};

  // ✅ 조정/필터 진입 전 스냅샷: 취소 시 "진입 전 상태"로 복원
  // (크롭은 별도 스냅샷 구조를 사용하므로 여기에는 포함하지 않는다)
  final Map<int, _EditSnapshot> _panelSessionSnapshots = {};
  // ✅ 조정/필터 세션 시작 시점의 히스토리 길이: 취소 시 세션 중 쌓인 스냅샷을 롤백하기 위함
  final Map<int, int> _panelSessionHistoryLengths = {};

  _EditSnapshot _snapshotOf(int index) {
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    return _EditSnapshot.fromState(state);
  }

  void _applySnapshotToIndex(int index, _EditSnapshot snap) {
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    snap.applyTo(state);
    // crop 제스처 임시 상태는 초기화
    _getCropGestureHandler(index).reset();

    // ✅ 미리보기 컨트롤러 동기화 (속도 등)
    final c = _videoControllers[index];
    if (c != null && c.value.isInitialized) {
      // video_player는 0.5~2.0 범위 권장
      final v = state.playbackSpeed.clamp(0.5, 2.0);
      // ignore: discarded_futures
      c.setPlaybackSpeed(v);
    }
  }

  // (표준 비파괴 편집) bytes 기반 커밋이 없으므로 "커밋 후 state 리셋" 유틸은 사용하지 않는다.

  _CropSessionSnapshot _makeCropSnapshot(int index) {
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    return _CropSessionSnapshot(
      videoFile: _videos[index],
      controller: _videoControllers[index],
      rotation: state.rotation,
      rotationQuarterTurns: state.rotationQuarterTurns,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
      cropRectImage: state.cropState.cropRectImage,
      isCropRectInitialized: state.cropState.isCropRectInitialized,
      imageOffset: state.imageOffset,
      imageScale: state.imageScale,
      selectedAspectRatio: state.selectedAspectRatio,
    );
  }

  void _restoreCropSnapshotIfAny(int index) {
    final snap = _cropSessionSnapshots.remove(index);
    if (snap == null) return;

    // 비디오 파일 복원
    _videos[index] = snap.videoFile;

    // 비디오 컨트롤러 복원(가능하면 즉시), 없으면 초기화
    if (snap.controller != null && snap.controller!.value.isInitialized) {
      _videoControllers[index] = snap.controller;
    } else {
      _videoControllers[index] = null;
      // ✅ Future를 기다리지 않고 백그라운드에서 초기화 (await 제거)
      _initializeVideoController(index, snap.videoFile);
    }

    // 편집 상태 복원 (특히 rotation/flip이 남아있으면 취소 후 화면이 "이상"해짐)
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    state.rotation = snap.rotation;
    state.rotationQuarterTurns = snap.rotationQuarterTurns;
    state.flipHorizontal = snap.flipHorizontal;
    state.flipVertical = snap.flipVertical;
    state.imageOffset = snap.imageOffset;
    state.imageScale = snap.imageScale;
    state.selectedAspectRatio = snap.selectedAspectRatio;
    // ✅ 중요: 크롭 세션 취소는 "진입 전 상태"로 복원해야 한다.
    // (이미 적용되어 있던 cropRect까지 포함해서) 따라서 reset 금지.
    state.cropState.selectedAspectRatio = snap.selectedAspectRatio;
    state.cropState.cropRectImage = snap.cropRectImage;
    state.cropState.isCropRectInitialized = snap.isCropRectInitialized;

    // crop gesture handler도 초기화
    _getCropGestureHandler(index).reset();
  }

  @override
  void initState() {
    super.initState();
    if (widget.videoFileList != null && widget.videoFileList!.isNotEmpty) {
      _videos = List.from(widget.videoFileList!);
    } else if (widget.videoFile != null) {
      _videos = [widget.videoFile!];
    } else {
      _videos = [];
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

    _preloadVideos();
  }

  Future<void> _preloadVideos() async {
    for (int i = 0; i < _videos.length; i++) {
      _initializeVideoController(i, _videos[i]);
      // ✅ 원본 비디오 컨트롤러는 미리 만들지 않음 (불필요한 2번째 컨트롤러/동시재생 방지)
      // 필요 시(정말 원본 복원이 필요할 때) lazy로 초기화한다.
      // ✅ 히스토리 시드(표준): 파일이 아니라 "편집 상태 스냅샷"을 1개 넣어둔다
      final s = _videoEditStates.putIfAbsent(i, () => _VideoEditState());
      _history.putIfAbsent(i, () => []).add(_EditSnapshot.fromState(s));
      _redoStack.putIfAbsent(i, () => []).clear();
    }
  }

  Future<VideoPlayerController> _initializeVideoController(
    int index,
    File videoFile,
  ) async {
    // ✅ 이미 초기화되어 있으면 반환
    if (_videoControllers[index] != null &&
        _videoControllers[index]!.value.isInitialized) {
      return _videoControllers[index]!;
    }

    // ✅ 이미 초기화 중이면 기존 Future 반환 (중복 초기화 방지)
    if (_initializingControllers.containsKey(index)) {
      return _initializingControllers[index]!;
    }

    // ✅ 초기화 시작
    final future = _initializeVideoControllerInternal(index, videoFile);
    _initializingControllers[index] = future;

    try {
      final controller = await future;
      _initializingControllers.remove(index);
      return controller;
    } catch (e) {
      _initializingControllers.remove(index);
      rethrow;
    }
  }

  Future<VideoPlayerController> _initializeVideoControllerInternal(
    int index,
    File videoFile,
  ) async {
    try {
      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      // ✅ 비디오 자동 재생 및 루프 설정
      controller.setLooping(true);
      // ✅ 기본은 무음 재생
      controller.setVolume(0.0);
      // ✅ 재생속도 적용 (state 기반)
      final s = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
      await controller.setPlaybackSpeed(s.playbackSpeed.clamp(0.5, 2.0));
      await controller.play();
      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
          // 🚀 캐시 크기 제한 초과 시 오래된 항목 제거
          _cleanupVideoCache();
        });
      }
      return controller;
    } catch (e) {
      debugPrint('비디오 로드 오류: $e');
      rethrow;
    }
  }

  /// 🚀 비디오 컨트롤러 캐시 정리 (최대 크기 초과 시 오래된 항목 제거)
  void _cleanupVideoCache() {
    if (_videoControllers.length <= _maxVideoCacheSize) return;

    // 현재 인덱스와 가까운 항목들은 유지하고, 먼 항목부터 제거
    final keys = _videoControllers.keys.toList()..sort();
    final itemsToRemove = _videoControllers.length - _maxVideoCacheSize;

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
        final controller = _videoControllers.remove(keys[removeIndex]);
        controller?.dispose();
        keys.removeAt(removeIndex);
      }
    }
  }

  // (표준 비파괴 편집) Apply/Undo/Redo에서 bytes를 교체하지 않으므로
  // _setImageBytesWithFade는 현재 사용하지 않는다.

  /// 비디오 코어 위젯 (Positioned 없는 순수 비디오 위젯)
  /// Positioned는 Stack의 직접 자식이어야 하므로, 배치는 호출부에서 처리한다.
  /// ✅ 재생/소리 버튼은 Transform 밖에 배치하기 위해 여기서는 순수 VideoPlayer만 반환
  Widget _buildVideoCore(
    VideoPlayerController controller,
    _VideoEditState state,
  ) {
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  /// 앱바용 재생/뮤트 버튼 (작은 크기)
  Widget _buildAppBarPlaybackControls(Color fgColor) {
    final controller = _videoControllers[_currentIndex];
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    // ✅ 옵션(크롭/조정/필터) 진입 시 재생/소리 버튼 숨김
    final showPlaybackControls =
        !_isBottomSheetOpen && _editMode == _EditMode.none;
    if (!showPlaybackControls) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final isPlaying = value.isPlaying;
        final isMuted = value.volume == 0.0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 재생/일시정지 버튼
            GestureDetector(
              onTap: () {
                if (isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: fgColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 8),
            // 소리 버튼
            GestureDetector(
              onTap: () {
                controller.setVolume(isMuted ? 1.0 : 0.0);
              },
              behavior: HitTestBehavior.opaque,
              child: Icon(
                isMuted ? Icons.volume_off : Icons.volume_up,
                color: fgColor,
                size: 24,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // 🚀 모든 비디오 컨트롤러 정리 (메모리 최적화)
    for (final controller in _videoControllers.values) {
      controller?.dispose();
    }
    _videoControllers.clear();
    // ✅ 초기화 중인 컨트롤러 추적도 정리
    _initializingControllers.clear();
    // ✅ 썸네일 캐시 정리
    _thumbnailCache.clear();
    _thumbnailFutures.clear();
    _history.clear();
    _redoStack.clear();

    _pageController.dispose();
    _bottomSheetController.dispose();
    _cropSnapBackController?.dispose();
    super.dispose();
  }

  void _animateCropSnapBackOffset(int index, Offset delta) {
    if (delta == Offset.zero) return;
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());

    _cropSnapBackController?.stop();
    _cropSnapBackController?.dispose();
    _cropSnapBackController = AnimationController(
      vsync: this,
      duration: _cropSnapBackDuration,
    );

    final begin = state.imageOffset;
    final end = begin + delta;
    final animation = Tween<Offset>(begin: begin, end: end).animate(
      CurvedAnimation(parent: _cropSnapBackController!, curve: Curves.easeOut),
    );

    _cropSnapBackController!.addListener(() {
      if (!mounted) return;
      setState(() {
        state.imageOffset = animation.value;
      });
    });
    _cropSnapBackController!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _cropSnapBackController?.dispose();
        _cropSnapBackController = null;
      }
    });
    _cropSnapBackController!.forward();
  }

  void _animateCropSnapBackScale(int index, double targetScale) {
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    if ((state.imageScale - targetScale).abs() < 0.001) return;

    _cropSnapBackController?.stop();
    _cropSnapBackController?.dispose();
    _cropSnapBackController = AnimationController(
      vsync: this,
      duration: _cropSnapBackDuration,
    );

    final begin = state.imageScale;
    final end = targetScale;
    final animation = Tween<double>(begin: begin, end: end).animate(
      CurvedAnimation(parent: _cropSnapBackController!, curve: Curves.easeOut),
    );

    _cropSnapBackController!.addListener(() {
      if (!mounted) return;
      setState(() {
        state.imageScale = animation.value;
      });
    });
    _cropSnapBackController!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _cropSnapBackController?.dispose();
        _cropSnapBackController = null;
      }
    });
    _cropSnapBackController!.forward();
  }

  bool get _isMultiVideo => _videos.length > 1;

  _VideoEditState _getCurrentEditState() {
    return _videoEditStates.putIfAbsent(_currentIndex, () => _VideoEditState());
  }

  void _resetFilterToOriginal() {
    final state = _getCurrentEditState();
    setState(() {
      state.selectedFilter = null;
      state.filterIntensity = 1.0;
    });
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
        case AdjustmentType.luminance:
          state.luminance = 0.0;
          break;
        case AdjustmentType.exposure:
          state.exposure = 0.0;
          break;
        case AdjustmentType.sharpness:
          state.sharpness = 0.0;
          break;
        case AdjustmentType.temperature:
          state.temperature = 0.0;
          break;
        case AdjustmentType.blur:
          state.blur = 0.0;
          break;
        case AdjustmentType.vignette:
          state.vignette = 0.0;
          break;
      }
      _saveToHistorySnapshot(_currentIndex);
    });
  }

  /// 크롭 제스처 핸들러 가져오기 (비디오별)
  VideoCropGestureHandler _getCropGestureHandler(int index) {
    return _cropGestureHandlers.putIfAbsent(
      index,
      () => VideoCropGestureHandler(),
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _snapPageViewToNearestPageIfNeeded() {
    if (!_isMultiVideo) return;
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
      // ✅ 정책: 이 화면은 FFmpeg로 파일을 굽지 않고, "편집 스펙"만 반환한다.
      // (trim + edit + compress는 업로드 단계에서 FFmpeg 1회로 처리)
      if (_videos.length == 1) {
        final spec = _buildEditSpecForIndex(0);
        if (!mounted) return;

        // ✅ 비디오 컨트롤러 pause 및 dispose
        await _pauseAndDisposeAllControllers();

        if (widget.onDone != null) {
          await widget.onDone!(context, spec);
          return;
        }
        Navigator.pop(context, spec);
        return;
      }

      final specs = <VideoEditSpec>[];
      for (int i = 0; i < _videos.length; i++) {
        final spec = _buildEditSpecForIndex(i);
        specs.add(spec);
      }
      if (!mounted) return;

      // ✅ 비디오 컨트롤러 pause 및 dispose
      await _pauseAndDisposeAllControllers();

      if (widget.onDone != null) {
        await widget.onDone!(context, specs);
        return;
      }
      Navigator.pop(context, specs);
      return;
    } finally {
      sw.stop();
      debugPrint(
        '[SimpleVideoEditor] 완료(spec 반환) 소요: ${sw.elapsedMilliseconds}ms',
      );
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 모든 비디오 컨트롤러를 pause하고 dispose
  Future<void> _pauseAndDisposeAllControllers() async {
    for (final controller in _videoControllers.values) {
      if (controller != null && controller.value.isInitialized) {
        await controller.pause();
      }
    }
    // dispose는 dispose() 메서드에서 처리되므로 여기서는 pause만 수행
  }

  VideoEditSpec _buildEditSpecForIndex(int index) {
    final s = _videoEditStates.putIfAbsent(index, () => _VideoEditState());

    // ✅ 크롭 정보 디버깅 및 검증
    debugPrint(
      '🔍 [VideoEditSpec] index=$index, '
      'isCropRectInitialized=${s.cropState.isCropRectInitialized}, '
      'cropRectImage=${s.cropState.cropRectImage}',
    );

    if (s.cropState.isCropRectInitialized &&
        s.cropState.cropRectImage == null) {
      debugPrint(
        '⚠️ [VideoEditSpec] 크롭이 초기화되었지만 cropRectImage가 null입니다. index: $index',
      );
    }

    if (s.cropState.cropRectImage != null) {
      debugPrint(
        '✅ [VideoEditSpec] 크롭 정보 저장: index=$index, '
        'cropRect=${s.cropState.cropRectImage}, '
        'width=${s.cropState.cropRectImage!.width}, '
        'height=${s.cropState.cropRectImage!.height}',
      );
    } else {
      debugPrint('ℹ️ [VideoEditSpec] 크롭 정보 없음: index=$index');
    }

    return VideoEditSpec(
      rotation: s.rotation,
      rotationQuarterTurns: s.rotationQuarterTurns,
      flipHorizontal: s.flipHorizontal,
      flipVertical: s.flipVertical,
      cropRectImage: s.cropState.cropRectImage,
      playbackSpeed: s.playbackSpeed,
      brightness: s.brightness,
      contrast: s.contrast,
      saturation: s.saturation,
      luminance: s.luminance,
      exposure: s.exposure,
      sharpness: s.sharpness,
      temperature: s.temperature,
      blur: s.blur,
      vignette: s.vignette,
      filterName: s.selectedFilter?.name,
      filterIntensity: s.filterIntensity,
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
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 2.0,
                                          right: 4,
                                        ),
                                        child: IconButton(
                                          onPressed: () {
                                            if (_isBottomSheetOpen) {
                                              _closeBottomSheet(cancel: true);
                                            } else {
                                              Navigator.pop(context);
                                            }
                                          },
                                          icon: Icon(
                                            _isBottomSheetOpen
                                                ? null
                                                : Icons.close,
                                            color: fgColor,
                                            size: 26,
                                          ),
                                        ),
                                      ),
                                      if (!_isBottomSheetOpen) ...[
                                        GestureDetector(
                                          onTap:
                                              ((_history[_currentIndex]
                                                              ?.length ??
                                                          0) >
                                                      1)
                                                  ? (_isExporting
                                                      ? null
                                                      : _undo)
                                                  : null,
                                          child: SvgPicture.asset(
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
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap:
                                              (_redoStack[_currentIndex]
                                                          ?.isNotEmpty ??
                                                      false)
                                                  ? (_isExporting
                                                      ? null
                                                      : _redo)
                                                  : null,
                                          child: SvgPicture.asset(
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
                                        const SizedBox(width: 16),
                                        // 재생/뮤트 버튼
                                        _buildAppBarPlaybackControls(fgColor),
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
                                                                    '${_videos.length}',
                                                                  )),
                                                      style: TextStyle(
                                                        color: fgColor,
                                                        fontSize: 16,
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
                        return _isMultiVideo
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
                                itemCount: _videos.length,
                                itemBuilder: (context, index) {
                                  return _buildVideoPreview(
                                    context,
                                    index,
                                    _videos[index],
                                  );
                                },
                              ),
                            )
                            : _buildVideoPreview(context, 0, _videos[0]);
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
                                        _isMultiVideo)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: _mainToolbarHeight + 20,
                                        child: IgnorePointer(
                                          child: Center(
                                            child: Text(
                                              '${_currentIndex + 1}/${_videos.length}',
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
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 20,
                                sigmaY: 20,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: bgColor.withOpacity(0.8),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 4px 간격 (블러 오버레이 내부)
                                    SizedBox(height: 4.0),
                                    // 바텀시트 콘텐츠
                                    child!,
                                  ],
                                ),
                              ),
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
                                      // ✅ 조정 상세(슬라이더) 모드: 뒤로(버튼 모드로)
                                      _adjustmentEditorKey.currentState
                                          ?.resetToButtonMode();
                                      setState(() {
                                        _isAdjustmentSliderMode = false;
                                      });
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
                                // ✅ 크롭/조정/필터/속도: 진입 즉시 옵션 제목 + 리셋 버튼 표시
                                if (_editMode == _EditMode.crop)
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            // ✅ 영상 편집에서는 회전 옵션을 제거하므로 타이틀은 "자르기"
                                            l10n.t('crop'),
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              // 요구사항: 취소~완료 사이 텍스트/아이콘은 opacity 0.7
                                              color: fgColor.withOpacity(0.7),
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
                                              // 요구사항: 취소~완료 사이 텍스트/아이콘은 opacity 0.7
                                              color: fgColor.withOpacity(0.7),
                                            ),
                                          ),
                                          // ✅ 요구사항: 상세 조정(슬라이더) 모드일 때만 리프레시 노출
                                          if (_isAdjustmentSliderMode) ...[
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap:
                                                  _resetCurrentAdjustmentValue,
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Icon(
                                                  Icons.refresh,
                                                  size: 24,
                                                  color: fgColor.withOpacity(
                                                    0.7,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
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
                                              final hasDetailName =
                                                  state.selectedFilter !=
                                                      null &&
                                                  state.selectedFilter!.name !=
                                                      '원본';
                                              final name =
                                                  hasDetailName
                                                      ? (state
                                                              .selectedFilter
                                                              ?.name ??
                                                          l10n.t('filter'))
                                                      : l10n.t('filter');
                                              return Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                  // 요구사항: 취소~완료 사이 텍스트/아이콘은 opacity 0.7
                                                  color: fgColor.withOpacity(
                                                    0.7,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          // 요구사항: "상세 필터명이 뜰 때만" 리셋 노출
                                          Builder(
                                            builder: (context) {
                                              final state =
                                                  _getCurrentEditState();
                                              final showReset =
                                                  state.selectedFilter !=
                                                      null &&
                                                  state.selectedFilter!.name !=
                                                      '원본';
                                              if (!showReset) {
                                                return const SizedBox.shrink();
                                              }
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const SizedBox(width: 8),
                                                  GestureDetector(
                                                    onTap:
                                                        _resetFilterToOriginal,
                                                    behavior:
                                                        HitTestBehavior
                                                            .translucent,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            6,
                                                          ),
                                                      child: Icon(
                                                        Icons.refresh,
                                                        size: 24,
                                                        // 요구사항: opacity 0.7
                                                        color: fgColor
                                                            .withOpacity(0.7),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else if (_editMode == _EditMode.speed)
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            l10n.t('speed'),
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              color: fgColor.withOpacity(0.7),
                                            ),
                                          ),
                                          Builder(
                                            builder: (context) {
                                              final state =
                                                  _getCurrentEditState();
                                              final showReset =
                                                  (state.playbackSpeed - 1.0)
                                                      .abs() >
                                                  0.01;
                                              if (!showReset) {
                                                return const SizedBox.shrink();
                                              }
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const SizedBox(width: 8),
                                                  GestureDetector(
                                                    onTap: () {
                                                      final s =
                                                          _getCurrentEditState();
                                                      s.playbackSpeed = 1.0;
                                                      final c =
                                                          _videoControllers[_currentIndex];
                                                      if (c != null &&
                                                          c
                                                              .value
                                                              .isInitialized) {
                                                        // ignore: discarded_futures
                                                        c.setPlaybackSpeed(1.0);
                                                      }
                                                      _saveToHistorySnapshot(
                                                        _currentIndex,
                                                      );
                                                      setState(() {});
                                                    },
                                                    behavior:
                                                        HitTestBehavior
                                                            .translucent,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            6,
                                                          ),
                                                      child: Icon(
                                                        Icons.refresh,
                                                        size: 24,
                                                        color: fgColor
                                                            .withOpacity(0.7),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
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
                                    // 요구사항: "완료" 대신 "적용"으로 통일
                                    l10n.t('apply'),
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

          // 상단 SafeArea 반투명 블러 오버레이
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedBuilder(
              animation: _bottomSheetAnimation,
              builder: (context, _) {
                if (_bottomSheetAnimation.value <= 0) {
                  return const SizedBox.shrink();
                }
                final safeAreaTop = MediaQuery.of(context).padding.top;
                if (safeAreaTop <= 0) {
                  return const SizedBox.shrink();
                }
                return ClipRRect(
                  child: Opacity(
                    opacity: _bottomSheetAnimation.value,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: safeAreaTop,
                        decoration: BoxDecoration(
                          color: bgColor.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 하단 SafeArea 반투명 블러 오버레이
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _bottomSheetAnimation,
              builder: (context, _) {
                if (_bottomSheetAnimation.value <= 0) {
                  return const SizedBox.shrink();
                }
                final safeAreaBottom = MediaQuery.of(context).padding.bottom;
                if (safeAreaBottom <= 0) {
                  return const SizedBox.shrink();
                }
                return ClipRRect(
                  child: Opacity(
                    opacity: _bottomSheetAnimation.value,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: safeAreaBottom,
                        decoration: BoxDecoration(
                          color: bgColor.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
                      width: 20,
                      height: 20,
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
                      icon: Icons.speed,
                      label: l10n.t('speed'),
                      onTap: _toggleSpeed,
                      isActive: _editMode == _EditMode.speed,
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

  /// 크롭 모드용 회전 적용 비디오 위젯 (Positioned 내부에서 사용)
  /// anchor는 Positioned 내부의 로컬 좌표계 기준 (center = Size(width/2, height/2))
  Widget _buildRotatedVideoForCrop(
    VideoPlayerController controller,
    _VideoEditState state,
    Rect? cropRectScreen,
    Rect imageRectForCrop,
  ) {
    final totalRotationDeg = state.rotation + (state.rotationQuarterTurns * 90);
    final rotationRadians = totalRotationDeg * (3.14159265359 / 180.0);

    final baseVideo = _buildVideoCore(controller, state);

    // ColorFilter, Blur, Vignette 적용
    Widget videoWidget = baseVideo;
    final blurSigma = (state.blur / 100.0) * 20.0;
    final vignetteIntensity = state.vignette / 100.0;

    if (_getColorFilter(state) != null) {
      videoWidget = ColorFiltered(
        colorFilter: _getColorFilter(state)!,
        child: videoWidget,
      );
    }

    videoWidget = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: videoWidget,
    );

    videoWidget = CustomPaint(
      painter: _VignettePainter(intensity: vignetteIntensity),
      child: videoWidget,
    );

    // Positioned 내부이므로 anchor는 로컬 좌표계 기준 (비디오 중심)
    // LayoutBuilder를 사용하여 실제 크기를 가져와서 center 계산
    return LayoutBuilder(
      builder: (context, constraints) {
        final anchor = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );

        // ✅ 크롭 모드: 회전 시 크롭 박스를 덮도록 하는 k 값 계산 (이미지 에디터와 동일)
        double k = 1.0;
        if (cropRectScreen != null) {
          // Positioned 내부 로컬 좌표계로 cropRectScreen 변환
          // imageRectForCrop을 constraints 크기로 스케일링하여 변환
          final localImageRect = Rect.fromLTWH(
            0,
            0,
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final scaleX = localImageRect.width / imageRectForCrop.width;
          final scaleY = localImageRect.height / imageRectForCrop.height;
          final localCropRectScreen = Rect.fromLTWH(
            (cropRectScreen.left - imageRectForCrop.left) * scaleX,
            (cropRectScreen.top - imageRectForCrop.top) * scaleY,
            cropRectScreen.width * scaleX,
            cropRectScreen.height * scaleY,
          );

          k = CropUtils.coverScaleToContainCropRect(
            imageRectScreen: localImageRect,
            cropRectScreen: localCropRectScreen,
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

        return Transform(transform: m, child: videoWidget);
      },
    );
  }

  /// 회전을 적용한 비디오 위젯 빌드 (조정/필터 모드용)
  Widget _buildRotatedVideo(
    BuildContext context,
    int index,
    File currentVideoFile,
    _VideoEditState state,
    Rect? cropRectScreen,
    Rect? imageRectForCrop,
    Rect? currentImageRect, // ✅ currentImageRect 추가
  ) {
    final totalRotationDeg = state.rotation + (state.rotationQuarterTurns * 90);
    final rotationRadians = totalRotationDeg * (3.14159265359 / 180.0);

    // ✅ 조정/필터 모드: 비디오 코어만 가져오기 (Positioned는 호출부에서 처리)
    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final baseVideo = _buildVideoCore(controller, state);

    // ✅ 필터/조정 모드에서 위젯 재생성 방지를 위한 고정 key
    final widgetKey =
        _editMode == _EditMode.adjust
            ? ValueKey('adjust_mode_$index')
            : _editMode == _EditMode.filter
            ? ValueKey('filter_mode_$index')
            : null;

    // ✅ 조정 모드일 때는 key를 고정하여 위젯 재생성 방지 (비디오 크기 고정)
    // ✅ blur/vignette도 항상 적용하여 위젯 트리 구조를 일정하게 유지 (깜빡임 방지)
    final blurSigma = (state.blur / 100.0) * 20.0;
    final vignetteIntensity = state.vignette / 100.0;

    Widget videoWidget = baseVideo;

    // ColorFilter 적용 (blur/vignette 제외)
    if (_getColorFilter(state) != null) {
      videoWidget = ColorFiltered(
        key:
            _editMode == _EditMode.adjust
                ? ValueKey('adjust_mode_$index') // 조정 모드일 때는 고정 key
                : _editMode == _EditMode.filter
                ? ValueKey('filter_mode_$index') // 필터 모드일 때는 고정 key (깜빡임 방지)
                : ValueKey(
                  '${state.selectedFilter}_${state.brightness}_${state.contrast}_${state.saturation}',
                ),
        colorFilter: _getColorFilter(state)!,
        child: videoWidget,
      );
    }

    // Blur 적용 (항상 적용하되, blur가 0이면 sigma도 0으로 설정)
    videoWidget = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: videoWidget,
    );

    // Vignette 적용 (항상 적용하되, vignette가 0이면 intensity도 0으로 설정)
    videoWidget = CustomPaint(
      painter: _VignettePainter(intensity: vignetteIntensity),
      child: videoWidget,
    );

    // ✅ 크롭이 적용된 경우(조정/필터 모드): Positioned로 배치할 예정이므로 클리핑은 호출부에서 처리
    // 크롭 모드가 아닐 때 크롭이 적용된 경우에는 내부 클리핑을 하지 않음
    final isCropApplied =
        (_isClosingAfterCropApply || _editMode != _EditMode.crop) &&
        state.cropState.isCropRectInitialized &&
        state.cropState.cropRectImage != null;

    // ✅ 크롭이 적용된 경우: currentImageRect 중심을 anchor로 사용 (원본 비율 유지)
    // 크롭 모드: cropRectScreen 중심을 anchor로 사용
    final anchor =
        (isCropApplied && currentImageRect != null)
            ? currentImageRect.center
            : (cropRectScreen?.center ??
                Offset(
                  MediaQuery.of(context).size.width / 2,
                  MediaQuery.of(context).size.height / 2,
                ));

    // 표준: 회전된 외접 사각형이 cropRect를 덮도록 하는 최소 배율(상태값은 건드리지 않음)
    // ✅ 적용 후(메인/조정/필터)에서도 cropRect를 클리핑해서 보여주기 때문에,
    // 회전이 들어오면 k를 계산하지 않으면 빈 공간/잘림처럼 보일 수 있다.
    double k = 1.0;
    if (cropRectScreen != null && imageRectForCrop != null) {
      // ✅ 크롭 모드 + 적용 후 프리뷰 공통: cropRect를 덮도록 하는 k 값 계산
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

    Widget result = Transform(transform: m, child: videoWidget);

    // ✅ 필터/조정 모드에서 위젯 재생성 방지를 위한 고정 key 적용
    if (widgetKey != null) {
      result = RepaintBoundary(key: widgetKey, child: result);
    } else {
      result = RepaintBoundary(child: result);
    }

    return result;
  }

  Widget _buildVideoPreview(BuildContext context, int index, File videoFile) {
    // ✅ 중요: PageView는 index별로 렌더링되므로, state도 index별로 가져와야 한다.
    // (현재 페이지 state(_currentIndex)를 쓰면 페이지 넘길 때마다 "편집이 풀리거나 섞이는" 현상이 발생)
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    final currentVideoFile = videoFile; // ✅ 이미 _videos[index]가 전달됨
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        // LayoutBuilder의 containerSize 저장 (MediaQuery.size 대신 사용)
        _containerSizes[index] = containerSize;

        // ✅ 크롭 모드: 순수 좌표계 사용 (패딩 없음)
        return AnimatedBuilder(
          animation: _bottomSheetAnimation,
          builder: (context, _) {
            // ✅ 크롭 모드에서도 containerSize 직접 사용 (패딩 제거)
            final effectiveContainerSize = containerSize;

            // 크롭 모드일 때 크롭 영역 초기화
            // ✅ 바텀시트가 완전히 올라온 상태에서만 초기화 (애니메이션 완료 후)
            if (_editMode == _EditMode.crop &&
                !state.cropState.isCropRectInitialized &&
                _isBottomSheetAnimationComplete) {
              // 바텀시트 완전히 올라온 상태
              final controller = _videoControllers[index];
              if (controller != null && controller.value.isInitialized) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final videoSize = Size(
                    controller.value.size.width.toDouble(),
                    controller.value.size.height.toDouble(),
                  );

                  // ✅ 실제 화면에 표시된 이미지 rect 계산 (scale과 offset 반영)
                  // 순수 좌표계 사용 (패딩 없음)
                  final displayImageRect =
                      ImageRectUtils.computeImageRectForCrop(
                        containerSize: effectiveContainerSize,
                        imageSize: videoSize,
                        scale: state.imageScale,
                        offset: state.imageOffset,
                      );

                  _imageDisplaySizes[index] = displayImageRect.size;

                  // ✅ 화면에 실제로 보이는 이미지 영역 계산 (순수 좌표계)
                  final visibleImageRect = displayImageRect.intersect(
                    Rect.fromLTWH(
                      0,
                      0,
                      effectiveContainerSize.width,
                      effectiveContainerSize.height,
                    ),
                  );

                  // ✅ 비율 확인
                  final targetAspectRatio =
                      state.cropState.selectedAspectRatio != null
                          ? CropGestureUtils.parseAspectRatio(
                            state.cropState.selectedAspectRatio,
                          )
                          : null;

                  // ✅ 기본 크롭 영역 계산 (비율이 있으면 비율 적용)
                  final margin = 0.0; // 여백 없음 - 이미지 경계에 완전히 붙임
                  double cropWidth;
                  double cropHeight;

                  if (targetAspectRatio != null) {
                    // 비율이 지정된 경우: 비율에 맞게 크롭 영역 계산
                    // 화면에 보이는 이미지 영역의 80% 정도를 차지하도록 설정
                    const targetCropRatio = 0.8;
                    final targetVisibleWidth =
                        visibleImageRect.width * targetCropRatio;
                    final targetVisibleHeight =
                        visibleImageRect.height * targetCropRatio;

                    final targetAspect = targetAspectRatio;
                    final targetVisibleAspect =
                        targetVisibleWidth / targetVisibleHeight;

                    if (targetAspect > targetVisibleAspect) {
                      // 비율이 더 넓음: 너비를 기준으로 높이 계산
                      cropWidth = targetVisibleWidth;
                      cropHeight = targetVisibleWidth / targetAspect;
                    } else {
                      // 비율이 더 높음: 높이를 기준으로 너비 계산
                      cropHeight = targetVisibleHeight;
                      cropWidth = targetVisibleHeight * targetAspect;
                    }

                    // 화면에 보이는 영역을 초과하지 않도록 제한
                    cropWidth = cropWidth.clamp(0.0, visibleImageRect.width);
                    cropHeight = cropHeight.clamp(0.0, visibleImageRect.height);
                  } else {
                    // 비율이 없는 경우: 전체 영역 사용
                    cropWidth = (visibleImageRect.width - margin * 2).clamp(
                      0.0,
                      visibleImageRect.width,
                    );
                    cropHeight = (visibleImageRect.height - margin * 2).clamp(
                      0.0,
                      visibleImageRect.height,
                    );
                  }

                  final cropLeft =
                      visibleImageRect.left +
                      (visibleImageRect.width - cropWidth) / 2;
                  final cropTop =
                      visibleImageRect.top +
                      (visibleImageRect.height - cropHeight) / 2;

                  // ✅ 화면 좌표를 이미지 좌표로 변환
                  final scaleX = videoSize.width / displayImageRect.width;
                  final scaleY = videoSize.height / displayImageRect.height;

                  // ✅ 화면 좌표의 크롭 박스를 이미지 좌표로 변환
                  // displayImageRect 기준으로 상대 좌표 계산
                  final cropRectImageLeft =
                      (cropLeft - displayImageRect.left) * scaleX;
                  final cropRectImageTop =
                      (cropTop - displayImageRect.top) * scaleY;
                  final cropRectImageWidth = cropWidth * scaleX;
                  final cropRectImageHeight = cropHeight * scaleY;

                  // ✅ 최종적으로 이미지 경계 내로 클램프
                  state.cropState.cropRectImage = Rect.fromLTWH(
                    cropRectImageLeft.clamp(0.0, videoSize.width),
                    cropRectImageTop.clamp(0.0, videoSize.height),
                    cropRectImageWidth.clamp(
                      0.0,
                      videoSize.width -
                          cropRectImageLeft.clamp(0.0, videoSize.width),
                    ),
                    cropRectImageHeight.clamp(
                      0.0,
                      videoSize.height -
                          cropRectImageTop.clamp(0.0, videoSize.height),
                    ),
                  );
                  state.cropState.isCropRectInitialized = true;

                  // ✅ 크롭 초기화 시 imageScale과 imageOffset도 초기화 (중앙 정렬)
                  state.imageScale = 1.0;
                  state.imageOffset = Offset.zero;

                  setState(() {});
                });
              }
            }

            // ✅ 레이어 분리: 비디오와 크롭 오버레이를 별도 레이어로 분리
            final controller = _videoControllers[index];
            final videoSize =
                controller != null && controller.value.isInitialized
                    ? Size(
                      controller.value.size.width.toDouble(),
                      controller.value.size.height.toDouble(),
                    )
                    : null;

            // ✅ 현재 비디오 rect 계산
            // 크롭 모드: 순수 좌표계 사용 (패딩 없음)
            // 조정/필터 모드: 비디오 rect를 캐싱하여 크기 고정 (깜빡임 방지)
            Rect? currentImageRect;
            if (videoSize != null) {
              if (_editMode == _EditMode.crop) {
                currentImageRect = ImageRectUtils.computeImageRectForCrop(
                  containerSize: effectiveContainerSize,
                  imageSize: videoSize,
                  scale: state.imageScale,
                  offset: state.imageOffset,
                );
              } else if (_editMode == _EditMode.adjust ||
                  _editMode == _EditMode.filter) {
                // ✅ 조정/필터 모드일 때는 캐시된 rect 사용 (크기 고정)
                final cachedSize = _imageDisplaySizes[index];
                if (cachedSize == null) {
                  // 최초 계산 시에만 계산하고 저장
                  currentImageRect = ImageRectUtils.computeImageRect(
                    containerSize: containerSize,
                    imageSize: videoSize,
                    scale: state.imageScale,
                    offset: state.imageOffset,
                  );
                  _imageDisplaySizes[index] = currentImageRect.size;
                } else {
                  // 캐시된 크기로 rect 재구성 (오프셋만 현재 값 사용)
                  final baseRect = ImageRectUtils.computeImageRect(
                    containerSize: containerSize,
                    imageSize: videoSize,
                    scale: 1.0, // scale 1.0 기준으로 계산
                    offset: Offset.zero,
                  );
                  // baseRect는 null이 될 수 없음 (videoSize가 null이 아니므로)
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
                  imageSize: videoSize,
                  scale: state.imageScale,
                  offset: state.imageOffset,
                );
              }
            }

            // ✅ 크롭 관련 계산용 imageRect (드래그/핀치 중이면 freeze된 값 사용)
            final cropHandler = _getCropGestureHandler(index);
            final imageRectForCrop =
                (cropHandler.isDraggingImage || cropHandler.isPinching) &&
                        cropHandler.frozenImageRect != null
                    ? cropHandler.frozenImageRect!
                    : currentImageRect;

            // ✅ 크롭 모드: 순수 좌표계 사용 (패딩 없음)
            final currentImageRectForPreview = currentImageRect;

            // 크롭 오버레이용 screen 좌표 계산
            // ✅ 항상 imageToScreenRect로 계산만 (절대 저장/freeze 금지)
            // ✅ 크롭박스는 항상 표시 (크롭이 초기화되어 있으면)
            Rect? cropRectScreen;
            if (state.cropState.isCropRectInitialized &&
                state.cropState.cropRectImage != null &&
                imageRectForCrop != null &&
                videoSize != null) {
              cropRectScreen = ImageRectUtils.imageToScreenRect(
                imageRect: state.cropState.cropRectImage!,
                screenImageRect: imageRectForCrop,
                imageSize: videoSize,
              );
            }

            final preview = GestureDetector(
              // ✅ GestureDetector를 Stack 최상위로 올려서 모든 레이어의 이벤트를 받음
              behavior: HitTestBehavior.translucent,
              onTap:
                  _isBottomSheetOpen
                      ? null
                      : _toggleUI, // ✅ 바텀시트 열려있을 때는 UI 토글 비활성화
              // ✅ 핀치/팬 통합: crop 모드에서는 ScaleGesture로 처리 (순수 좌표계)
              onScaleStart:
                  _editMode == _EditMode.crop
                      ? (details) => _onCropScaleStart(
                        details,
                        index,
                        effectiveContainerSize,
                      )
                      : null,
              onScaleUpdate:
                  _editMode == _EditMode.crop
                      ? (details) => _onCropScaleUpdate(
                        details,
                        index,
                        effectiveContainerSize,
                      )
                      : null,
              onScaleEnd:
                  _editMode == _EditMode.crop
                      ? (details) => _onCropScaleEnd(
                        details,
                        index,
                        effectiveContainerSize,
                      )
                      : null,
              // 필터 모드는 기존 Pan 유지
              onPanUpdate:
                  _editMode == _EditMode.filter ? _onFilterSwipe : null,
              onPanEnd:
                  _editMode == _EditMode.filter ? _onFilterSwipeEnd : null,
              child: Stack(
                children: [
                  // 1️⃣ 비디오 레이어 (transform 적용)
                  if (_editMode == _EditMode.crop &&
                      currentImageRectForPreview != null &&
                      imageRectForCrop != null)
                    // ✅ 크롭 모드: Positioned를 Stack의 직접 자식으로 배치 + 회전 적용
                    // (Positioned는 반드시 Stack의 direct child여야 함)
                    Builder(
                      builder: (context) {
                        final controller = _videoControllers[index];
                        final v = _applyAnimVersion[index] ?? 0;
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        final fgColor =
                            isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary;

                        // ✅ 크롭 모드에서는 비디오 컨트롤러를 생성하지 않음
                        // _preloadVideos()에서 이미 초기화했으므로, 컨트롤러가 없으면 로딩 표시만
                        if (controller == null ||
                            !controller.value.isInitialized) {
                          return Positioned(
                            left: currentImageRectForPreview.left,
                            top: currentImageRectForPreview.top,
                            width: currentImageRectForPreview.width,
                            height: currentImageRectForPreview.height,
                            child: Center(
                              child:
                                  widget.isExistingNodeEdit
                                      ? const SizedBox.shrink()
                                      : SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 4,
                                          color: fgColor,
                                        ),
                                      ),
                            ),
                          );
                        }

                        // ✅ 스냅 교체 + "살짝 정착(zoom settle)" + 회전 적용
                        return Positioned(
                          left: currentImageRectForPreview.left,
                          top: currentImageRectForPreview.top,
                          width: currentImageRectForPreview.width,
                          height: currentImageRectForPreview.height,
                          child: IgnorePointer(
                            // 비디오 레이어는 터치 이벤트를 차단 (GestureDetector가 처리)
                            child: RepaintBoundary(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('apply_settle_$index\_$v'),
                                tween: Tween(begin: 1.02, end: 1.0),
                                duration: _applySettleDuration,
                                curve: Curves.easeOutCubic,
                                builder: (context, s, _) {
                                  return Transform.scale(
                                    scale: s,
                                    alignment: Alignment.center,
                                    child: _buildRotatedVideoForCrop(
                                      controller,
                                      state,
                                      cropRectScreen,
                                      imageRectForCrop,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    // ✅ 조정/필터 모드: 재생/소리 버튼이 작동하도록 IgnorePointer 제거
                    // 크롭이 적용된 경우 크롭박스 위치에 맞게 배치
                    Builder(
                      builder: (context) {
                        // ✅ 크롭이 적용된 경우: 원본 비율 유지하며 크롭박스 영역만 클리핑
                        if (state.cropState.isCropRectInitialized &&
                            cropRectScreen != null &&
                            currentImageRect != null) {
                          final videoWidget = _buildRotatedVideo(
                            context,
                            index,
                            currentVideoFile,
                            state,
                            cropRectScreen,
                            imageRectForCrop,
                            currentImageRect,
                          );

                          // 원본 비율 유지하며 currentImageRect 위치에 배치
                          // 크롭박스 영역만 클리핑
                          final clipRect = Rect.fromLTWH(
                            cropRectScreen.left - currentImageRect.left,
                            cropRectScreen.top - currentImageRect.top,
                            cropRectScreen.width,
                            cropRectScreen.height,
                          );

                          return Positioned(
                            left: currentImageRect.left,
                            top: currentImageRect.top,
                            width: currentImageRect.width,
                            height: currentImageRect.height,
                            child: ClipRect(
                              clipper: _CustomRectClipper(clipRect),
                              child: videoWidget,
                            ),
                          );
                        }

                        // 크롭이 없는 경우 기존대로 중앙 배치
                        if (currentImageRect != null) {
                          return Positioned(
                            left: currentImageRect.left,
                            top: currentImageRect.top,
                            width: currentImageRect.width,
                            height: currentImageRect.height,
                            child: _buildRotatedVideo(
                              context,
                              index,
                              currentVideoFile,
                              state,
                              cropRectScreen,
                              imageRectForCrop,
                              currentImageRect,
                            ),
                          );
                        }

                        return _buildRotatedVideo(
                          context,
                          index,
                          currentVideoFile,
                          state,
                          cropRectScreen,
                          imageRectForCrop,
                          currentImageRect,
                        );
                      },
                    ),
                  // 3️⃣ 크롭 핸들들 (이미 screen 좌표 사용 중)
                  // ✅ 드래그 중이면 고정된 cropRectScreen 전달
                  if (_editMode == _EditMode.crop &&
                      !_isClosingAfterCropApply &&
                      state.cropState.isCropRectInitialized &&
                      imageRectForCrop != null &&
                      cropRectScreen != null &&
                      videoSize != null)
                    AnimatedBuilder(
                      animation: _bottomSheetAnimation,
                      builder: (context, _) {
                        // ✅ 바텀시트가 열릴수록(1.0) 핸들이 보이고, 닫힐수록(0.0) 사라짐
                        final handlesOpacity = _bottomSheetAnimation.value;
                        // ✅ 핸들은 순수 좌표계 사용 (패딩 없음)
                        return Opacity(
                          opacity: handlesOpacity,
                          child: CropHandleBuilder.buildCropHandles(
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
                            // 요구사항: 크롭박스/핸들 색상은 primary
                            handleColor: primaryColor,
                            onResize: (handle, delta) {
                              // 🎯 기본 리사이즈 로직 사용 (각 핸들 방향으로만 움직임, center 고정 안 함)
                              debugPrint(
                                '🔵 [리사이즈 중] handle: $handle, delta: $delta',
                              );

                              final controller = _videoControllers[index];
                              if (controller != null &&
                                  controller.value.isInitialized) {
                                final imageSize = Size(
                                  controller.value.size.width.toDouble(),
                                  controller.value.size.height.toDouble(),
                                );
                                // ✅ 리사이즈 중에도 freeze된 imageRect 사용
                                final cropHandler = _getCropGestureHandler(
                                  index,
                                );
                                final resizeImageRect =
                                    cropHandler.isDraggingImage &&
                                            cropHandler.frozenImageRect != null
                                        ? cropHandler.frozenImageRect!
                                        : (_editMode == _EditMode.crop
                                            ? ImageRectUtils.computeImageRectForCrop(
                                              containerSize:
                                                  effectiveContainerSize,
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
                            },
                            onResizeEnd: () {
                              // 🎯 리사이즈 완료 시 즉시 Auto Zoom 실행
                              debugPrint(
                                '✅ [onResizeEnd] 리사이즈 완료 - Auto Zoom 실행',
                              );
                              final containerSize = _containerSizes[index];
                              if (containerSize != null) {
                                final controller = _videoControllers[index];
                                if (controller != null &&
                                    controller.value.isInitialized) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    _autoZoomToCrop(index, containerSize);
                                  });
                                }
                              } else {
                                debugPrint(
                                  '❌ [Auto Zoom 실패] containerSize가 null',
                                );
                              }
                            },
                            screenImageRect: imageRectForCrop,
                            imageSize: videoSize,
                            cropRectScreen: cropRectScreen,
                          ),
                        );
                      },
                    ),
                ],
              ),
            );

            // ✅ 크롭박스는 크롭 모드일 때만 표시
            // ✅ 핸들들은 크롭 모드일 때만 표시 (조정은 크롭 옵션일 때만)
            return Stack(
              children: [
                // ✅ 비디오와 핸들 (패딩 없이 직접 배치)
                preview,
                // 2️⃣ 크롭 오버레이 레이어 (순수 좌표계)
                // ✅ 크롭 모드일 때만 크롭박스 표시
                if (_editMode == _EditMode.crop &&
                    cropRectScreen != null &&
                    imageRectForCrop != null)
                  Builder(
                    builder: (context) {
                      final Rect screenRect = cropRectScreen!;
                      final Rect imageRect = imageRectForCrop;

                      // ✅ 크롭 모드일 때는 바텀시트 애니메이션에 따라 opacity 조절
                      return AnimatedBuilder(
                        animation: _bottomSheetAnimation,
                        builder: (context, _) {
                          return IgnorePointer(
                            // 크롭 오버레이는 터치 이벤트를 차단 (이미지 드래그를 위해)
                            child: Opacity(
                              opacity: _bottomSheetAnimation.value,
                              child: CustomPaint(
                                painter: CropOverlayPainter(
                                  cropRectScreen: screenRect,
                                  imageRect: imageRect,
                                  overlayColor: bgColor.withOpacity(0.8),
                                  // 요구사항: 크롭박스 색상은 primary
                                  borderColor: primaryColor,
                                ),
                                // ✅ container 좌표계 기준 (순수 좌표)
                                size: containerSize,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  ColorFilter? _getColorFilter(_VideoEditState state) {
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

  List<double>? _getAdjustmentMatrix(_VideoEditState state) {
    return AdjustmentUtils.getAdjustmentMatrix(
      brightness: state.brightness,
      contrast: state.contrast,
      saturation: state.saturation,
      luminance: state.luminance,
      exposure: state.exposure,
      sharpness: state.sharpness,
      temperature: state.temperature,
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

        // ✅ 첫 번째 크롭 진입 시: 현재 VideoPlayer의 실제 표시 rect를 계산하여 동기화
        // (암묵적 transform → 명시적 transform 전환 시 기준점 불일치 해결)
        final isFirstCropEntry = !state.cropState.isCropRectInitialized;
        if (isFirstCropEntry) {
          final controller = _videoControllers[_currentIndex];
          if (controller != null && controller.value.isInitialized) {
            final videoSize = Size(
              controller.value.size.width.toDouble(),
              controller.value.size.height.toDouble(),
            );
            final containerSize = _containerSizes[_currentIndex];
            if (containerSize != null) {
              // ✅ 현재 VideoPlayer의 실제 표시 rect 계산 (조정/필터 모드 기준)
              final actualDisplayRect = ImageRectUtils.computeImageRect(
                containerSize: containerSize,
                imageSize: videoSize,
                scale: state.imageScale,
                offset: state.imageOffset,
              );

              // ✅ 실제 표시 rect를 기준으로 scale=1, offset=0으로 동기화
              // 이 rect를 imageRect로 설정하고, scale/offset을 리셋
              _imageDisplaySizes[_currentIndex] = actualDisplayRect.size;
              state.imageScale = 1.0;
              state.imageOffset = Offset.zero;
            }
          }
        }

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
    // ✅ 이미 열려있으면: "토글로 닫기"도 취소와 동일하게 처리(적용 안 했으므로)
    if (_editMode == _EditMode.filter && _isBottomSheetOpen) {
      _closeBottomSheet(cancel: true);
      return;
    }

    setState(() {
      // ✅ 진입 전 상태 저장(취소 시 복원) - 세션 중에는 덮어쓰지 않음
      _panelSessionSnapshots.putIfAbsent(
        _currentIndex,
        () => _snapshotOf(_currentIndex),
      );
      _panelSessionHistoryLengths.putIfAbsent(
        _currentIndex,
        () => _history[_currentIndex]?.length ?? 0,
      );

      _editMode = _EditMode.filter;
      _isBottomSheetOpen = true;
      _bottomSheetController.forward();
    });
  }

  void _toggleSpeed() {
    if (_isPageScrolling) return;
    _snapPageViewToNearestPageIfNeeded();
    // ✅ 이미 열려있으면: "토글로 닫기"도 취소와 동일하게 처리(적용 안 했으므로)
    if (_editMode == _EditMode.speed && _isBottomSheetOpen) {
      _closeBottomSheet(cancel: true);
      return;
    }

    setState(() {
      // ✅ 진입 전 상태 저장(취소 시 복원) - 세션 중에는 덮어쓰지 않음
      _panelSessionSnapshots.putIfAbsent(
        _currentIndex,
        () => _snapshotOf(_currentIndex),
      );
      _panelSessionHistoryLengths.putIfAbsent(
        _currentIndex,
        () => _history[_currentIndex]?.length ?? 0,
      );

      _editMode = _EditMode.speed;
      _isBottomSheetOpen = true;
      _bottomSheetController.forward();
    });
  }

  void _toggleAdjustment() {
    if (_isPageScrolling) return;
    _snapPageViewToNearestPageIfNeeded();
    // ✅ 이미 열려있으면: "토글로 닫기"도 취소와 동일하게 처리(적용 안 했으므로)
    if (_editMode == _EditMode.adjust && _isBottomSheetOpen) {
      _closeBottomSheet(cancel: true);
      return;
    }

    setState(() {
      // ✅ 조정 탭 재진입 시 헤더 상태 초기화 (상세 모드 잔상 방지)
      _isAdjustmentSliderMode = false;
      // ✅ 진입 전 상태 저장(취소 시 복원) - 세션 중에는 덮어쓰지 않음
      _panelSessionSnapshots.putIfAbsent(
        _currentIndex,
        () => _snapshotOf(_currentIndex),
      );
      _panelSessionHistoryLengths.putIfAbsent(
        _currentIndex,
        () => _history[_currentIndex]?.length ?? 0,
      );

      _editMode = _EditMode.adjust;
      _isBottomSheetOpen = true;
      _bottomSheetController.forward();
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
    if (cancel &&
        (_editMode == _EditMode.filter || _editMode == _EditMode.adjust)) {
      // ✅ 조정/필터 취소: 진입 전 스냅샷으로 복원 (기존에 적용되어 있던 값은 유지)
      final snap = _panelSessionSnapshots.remove(_currentIndex);
      final historyLen = _panelSessionHistoryLengths.remove(_currentIndex);
      if (snap != null) {
        setState(() {
          _applySnapshotToIndex(_currentIndex, snap);
        });
      }
      // ✅ 취소 시: 세션 중 쌓인 히스토리/리두도 롤백 (적용 전 변경이 남지 않도록)
      final history = _history[_currentIndex];
      if (historyLen != null &&
          history != null &&
          history.length > historyLen) {
        history.removeRange(historyLen, history.length);
      }
      _redoStack[_currentIndex]?.clear();
    } else {
      // cancel이 아니거나(=적용/완료) 다른 모드면 세션 스냅샷은 정리
      _panelSessionSnapshots.remove(_currentIndex);
      _panelSessionHistoryLengths.remove(_currentIndex);
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
        _isAdjustmentSliderMode = false;
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
    final state = _getCurrentEditState();

    // ✅ 크롭 모드에서 적용 시: 현재 화면의 크롭 영역을 cropRectImage로 저장
    if (_editMode == _EditMode.crop) {
      final containerSize = _containerSizes[_currentIndex];
      final controller = _videoControllers[_currentIndex];
      if (containerSize != null &&
          controller != null &&
          controller.value.isInitialized) {
        final videoSize = Size(
          controller.value.size.width.toDouble(),
          controller.value.size.height.toDouble(),
        );

        // 현재 화면에 표시된 이미지 rect 계산
        final displayImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: videoSize,
          scale: state.imageScale,
          offset: state.imageOffset,
        );

        // ✅ 현재 화면에 보이는 크롭박스 (screen 좌표) 직접 계산
        // cropRectImage가 있으면 그것을 screen으로 변환, 없으면 기본값 사용
        Rect currentCropRectScreen;
        if (state.cropState.isCropRectInitialized &&
            state.cropState.cropRectImage != null) {
          // 기존 cropRectImage를 screen 좌표로 변환 (현재 화면 기준)
          final screenRect = ImageRectUtils.imageToScreenRect(
            imageRect: state.cropState.cropRectImage!,
            screenImageRect: displayImageRect,
            imageSize: videoSize,
          );
          currentCropRectScreen = screenRect;
        } else {
          // 크롭 영역이 없으면 기본 크롭 영역 계산
          final visibleImageRect = displayImageRect.intersect(
            Rect.fromLTWH(0, 0, containerSize.width, containerSize.height),
          );

          final targetAspectRatio =
              state.cropState.selectedAspectRatio != null
                  ? CropGestureUtils.parseAspectRatio(
                    state.cropState.selectedAspectRatio,
                  )
                  : null;

          double cropWidth;
          double cropHeight;

          if (targetAspectRatio != null) {
            const targetCropRatio = 0.8;
            final targetVisibleWidth = visibleImageRect.width * targetCropRatio;
            final targetVisibleHeight =
                visibleImageRect.height * targetCropRatio;
            final targetAspect = targetAspectRatio;
            final targetVisibleAspect =
                targetVisibleWidth / targetVisibleHeight;

            if (targetAspect > targetVisibleAspect) {
              cropWidth = targetVisibleWidth;
              cropHeight = targetVisibleWidth / targetAspect;
            } else {
              cropHeight = targetVisibleHeight;
              cropWidth = targetVisibleHeight * targetAspect;
            }
          } else {
            cropWidth = visibleImageRect.width * 0.8;
            cropHeight = visibleImageRect.height * 0.8;
          }

          final cropLeft =
              visibleImageRect.left + (visibleImageRect.width - cropWidth) / 2;
          final cropTop =
              visibleImageRect.top + (visibleImageRect.height - cropHeight) / 2;

          currentCropRectScreen = Rect.fromLTWH(
            cropLeft,
            cropTop,
            cropWidth,
            cropHeight,
          );
        }

        // ✅ screen 좌표를 image 좌표로 변환하여 저장 (정확한 변환)
        final scaleX = videoSize.width / displayImageRect.width;
        final scaleY = videoSize.height / displayImageRect.height;

        final cropRectImageLeft =
            (currentCropRectScreen.left - displayImageRect.left) * scaleX;
        final cropRectImageTop =
            (currentCropRectScreen.top - displayImageRect.top) * scaleY;
        final cropRectImageWidth = currentCropRectScreen.width * scaleX;
        final cropRectImageHeight = currentCropRectScreen.height * scaleY;

        // ✅ 최종 cropRectImage 저장 (이미지 경계 내로 clamp)
        final finalCropRectImage = Rect.fromLTWH(
          cropRectImageLeft.clamp(0.0, videoSize.width),
          cropRectImageTop.clamp(0.0, videoSize.height),
          cropRectImageWidth.clamp(
            0.0,
            videoSize.width - cropRectImageLeft.clamp(0.0, videoSize.width),
          ),
          cropRectImageHeight.clamp(
            0.0,
            videoSize.height - cropRectImageTop.clamp(0.0, videoSize.height),
          ),
        );

        state.cropState.cropRectImage = finalCropRectImage;
        state.cropState.isCropRectInitialized = true;

        // ✅ 크롭 적용 후: 크롭박스가 화면(옵션 섹션 위 영역)을 꽉 채우도록 조정
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final availableSize = containerSize;

          // 현재 화면에서 크롭박스 크기
          final currentCropWidth = currentCropRectScreen.width;
          final currentCropHeight = currentCropRectScreen.height;

          double scaleX = availableSize.width / currentCropWidth;
          double scaleY = availableSize.height / currentCropHeight;

          // 비율 유지 + "crop 영역이 화면 안에 완전히 들어오도록(contain)" 최소 스케일 선택
          // - 가로로 긴 crop(landscape)이면 width 기준(scaleX)이 더 작아져야 함
          // - 세로로 긴 crop(portrait)이면 height 기준(scaleY)이 더 작아져야 함
          final targetScaleFactor = math.min(scaleX, scaleY);

          // 새로운 imageScale 계산
          final newImageScale = state.imageScale * targetScaleFactor;

          // 새로운 scale로 이미지 rect 계산 (offset=0 기준)
          final newImageRect = ImageRectUtils.computeImageRect(
            containerSize: availableSize,
            imageSize: videoSize,
            scale: newImageScale,
            offset: Offset.zero,
          );

          // 새로운 이미지 rect 기준으로 크롭박스 위치 계산
          final scaleXNew = newImageRect.width / videoSize.width;
          final scaleYNew = newImageRect.height / videoSize.height;
          final newCropRectScreen = Rect.fromLTWH(
            newImageRect.left + finalCropRectImage.left * scaleXNew,
            newImageRect.top + finalCropRectImage.top * scaleYNew,
            finalCropRectImage.width * scaleXNew,
            finalCropRectImage.height * scaleYNew,
          );

          // 크롭박스 중심을 화면 중심에 맞추도록 offset 조정
          final containerCenter = Offset(
            availableSize.width / 2,
            availableSize.height / 2,
          );
          final newCropCenter = newCropRectScreen.center;
          final offsetDelta = containerCenter - newCropCenter;

          // imageScale과 imageOffset 업데이트
          setState(() {
            state.imageScale = newImageScale;
            // ✅ imageOffset은 screen px 기준 (computeImageRect에서 그대로 더해짐)
            // scale로 나누면 누적 오차/드리프트가 발생한다.
            state.imageOffset = offsetDelta;
            // ✅ 조정/필터 모드의 "크기 고정 캐시"도 커밋된 크기로 갱신
            _imageDisplaySizes[_currentIndex] = newImageRect.size;
          });
        });

        debugPrint(
          '✅ [크롭 적용] cropRectImage 저장: ${state.cropState.cropRectImage}, '
          'videoSize: $videoSize, '
          'currentCropRectScreen: $currentCropRectScreen',
        );
      }
    }

    _saveToHistorySnapshot(_currentIndex);
    // ✅ 적용 후에는 세션 스냅샷 제거 (취소 복원 대상 아님)
    _panelSessionSnapshots.remove(_currentIndex);
    _panelSessionHistoryLengths.remove(_currentIndex);
  }

  // 크롭 제스처 처리 (VideoCropGestureHandler 위임)
  void _onCropScaleStart(
    ScaleStartDetails details,
    int index,
    Size containerSize,
  ) {
    // ✅ PageView 구조에서는 반드시 index 기반 state를 사용해야 한다.
    // (_currentIndex 기반 state를 쓰면 스크롤/프레임 타이밍에 다른 비디오 state를 건드릴 수 있음)
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) return;

    final videoSize = Size(
      controller.value.size.width.toDouble(),
      controller.value.size.height.toDouble(),
    );

    final cropHandler = _getCropGestureHandler(index);
    cropHandler.onScaleStart(
      details: details,
      cropState: state.cropState,
      videoSize: videoSize,
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
    // ✅ PageView 구조에서는 반드시 index 기반 state를 사용해야 한다.
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    if (!state.cropState.isCropRectInitialized) return;

    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) return;

    final videoSize = Size(
      controller.value.size.width.toDouble(),
      controller.value.size.height.toDouble(),
    );

    final cropHandler = _getCropGestureHandler(index);
    final updateResult = cropHandler.onScaleUpdate(
      details: details,
      cropState: state.cropState,
      videoSize: videoSize,
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
    // ✅ PageView 구조에서는 반드시 index 기반 state를 사용해야 한다.
    final state = _videoEditStates.putIfAbsent(index, () => _VideoEditState());
    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) return;

    final videoSize = Size(
      controller.value.size.width.toDouble(),
      controller.value.size.height.toDouble(),
    );

    final cropHandler = _getCropGestureHandler(index);
    final result = cropHandler.onScaleEnd(
      cropState: state.cropState,
      videoSize: videoSize,
      containerSize: containerSize,
      imageScale: state.imageScale,
      imageOffset: state.imageOffset,
    );

    if (result != null) {
      // ✅ snap-back offset 적용
      if (result.snapBackOffset != null) {
        _animateCropSnapBackOffset(index, result.snapBackOffset!);
      }

      // ✅ snap-back scale 적용
      if (result.snapBackScale != null) {
        _animateCropSnapBackScale(index, result.snapBackScale!);
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

  /// Auto Zoom to Crop (VideoCropAutoZoom 위임)
  void _autoZoomToCrop(int index, Size containerSize) {
    final cropHandler = _getCropGestureHandler(index);
    if (cropHandler.isDraggingImage) return;

    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) return;

    final videoSize = Size(
      controller.value.size.width.toDouble(),
      controller.value.size.height.toDouble(),
    );

    final state = _getCurrentEditState();
    final result = VideoCropAutoZoom.autoZoomToCrop(
      cropState: state.cropState,
      videoSize: videoSize,
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

    void reinitCropRect() {
      final containerSize = _containerSizes[_currentIndex];
      final controller = _videoControllers[_currentIndex];
      if (controller != null &&
          controller.value.isInitialized &&
          containerSize != null) {
        final videoSize = Size(
          controller.value.size.width.toDouble(),
          controller.value.size.height.toDouble(),
        );

        // ✅ 이미지 에디터와 동일한 로직 사용
        // ✅ 실제 화면에 표시된 이미지 rect 계산 (scale과 offset 반영)
        final displayImageRect = ImageRectUtils.computeImageRectForCrop(
          containerSize: containerSize,
          imageSize: videoSize,
          scale: state.imageScale,
          offset: state.imageOffset,
        );

        _imageDisplaySizes[_currentIndex] = displayImageRect.size;

        // ✅ 화면에 실제로 보이는 이미지 영역 계산 (containerSize와의 교집합)
        final visibleImageRect = displayImageRect.intersect(
          Rect.fromLTWH(0, 0, containerSize.width, containerSize.height),
        );

        // ✅ 비율 확인
        final targetAspectRatio =
            state.cropState.selectedAspectRatio != null
                ? CropGestureUtils.parseAspectRatio(
                  state.cropState.selectedAspectRatio,
                )
                : null;

        // ✅ 기본 크롭 영역 계산 (비율이 있으면 비율 적용)
        final margin = 0.0; // 여백 없음 - 이미지 경계에 완전히 붙임
        double cropWidth;
        double cropHeight;

        if (targetAspectRatio != null) {
          // 비율이 지정된 경우: 비율에 맞게 크롭 영역 계산
          // 화면에 보이는 이미지 영역의 80% 정도를 차지하도록 설정
          const targetCropRatio = 0.8;
          final targetVisibleWidth = visibleImageRect.width * targetCropRatio;
          final targetVisibleHeight = visibleImageRect.height * targetCropRatio;

          final targetAspect = targetAspectRatio;
          final targetVisibleAspect = targetVisibleWidth / targetVisibleHeight;

          if (targetAspect > targetVisibleAspect) {
            // 비율이 더 넓음: 너비를 기준으로 높이 계산
            cropWidth = targetVisibleWidth;
            cropHeight = targetVisibleWidth / targetAspect;
          } else {
            // 비율이 더 높음: 높이를 기준으로 너비 계산
            cropHeight = targetVisibleHeight;
            cropWidth = targetVisibleHeight * targetAspect;
          }

          // 화면에 보이는 영역을 초과하지 않도록 제한
          cropWidth = cropWidth.clamp(0.0, visibleImageRect.width);
          cropHeight = cropHeight.clamp(0.0, visibleImageRect.height);
        } else {
          // 비율이 없는 경우: 전체 영역 사용
          cropWidth = (visibleImageRect.width - margin * 2).clamp(
            0.0,
            visibleImageRect.width,
          );
          cropHeight = (visibleImageRect.height - margin * 2).clamp(
            0.0,
            visibleImageRect.height,
          );
        }

        final cropLeft =
            visibleImageRect.left + (visibleImageRect.width - cropWidth) / 2;
        final cropTop =
            visibleImageRect.top + (visibleImageRect.height - cropHeight) / 2;

        // ✅ 화면 좌표를 이미지 좌표로 변환
        final scaleX = videoSize.width / displayImageRect.width;
        final scaleY = videoSize.height / displayImageRect.height;

        // ✅ 화면 좌표의 크롭 박스를 이미지 좌표로 변환
        // displayImageRect 기준으로 상대 좌표 계산
        final cropRectImageLeft = (cropLeft - displayImageRect.left) * scaleX;
        final cropRectImageTop = (cropTop - displayImageRect.top) * scaleY;
        final cropRectImageWidth = cropWidth * scaleX;
        final cropRectImageHeight = cropHeight * scaleY;

        // ✅ 최종적으로 이미지 경계 내로 클램프
        state.cropState.cropRectImage = Rect.fromLTWH(
          cropRectImageLeft.clamp(0.0, videoSize.width),
          cropRectImageTop.clamp(0.0, videoSize.height),
          cropRectImageWidth.clamp(
            0.0,
            videoSize.width - cropRectImageLeft.clamp(0.0, videoSize.width),
          ),
          cropRectImageHeight.clamp(
            0.0,
            videoSize.height - cropRectImageTop.clamp(0.0, videoSize.height),
          ),
        );
        state.cropState.isCropRectInitialized = true;

        // ✅ 크롭 초기화 시 imageScale과 imageOffset도 초기화 (중앙 정렬)
        state.imageScale = 1.0;
        state.imageOffset = Offset.zero;
      }
    }

    return CropEditorBottomSheet(
      selectedAspectRatio: state.selectedAspectRatio,
      rotation: state.rotation,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
      enableRotation: false, // ✅ 영상 편집에서는 회전 옵션 제거
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
      onRotationChanged:
          (v) => setState(() {
            // ✅ ±45도로 제한
            state.rotation = v.clamp(-45, 45);
          }),

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
    final currentVideoFile = _videos[_currentIndex];

    // ✅ 썸네일 캐시 사용 (깜빡임 방지)
    final cachedThumbnail = _thumbnailCache[_currentIndex];
    final thumbnailFuture =
        cachedThumbnail != null
            ? Future.value(cachedThumbnail)
            : _getOrGenerateThumbnail(_currentIndex, currentVideoFile);

    return FutureBuilder<Uint8List?>(
      key: ValueKey('filter_thumbnail_$_currentIndex'), // ✅ key로 재생성 방지
      future: thumbnailFuture,
      builder: (context, snapshot) {
        return FilterEditorBottomSheet(
          selectedFilter: state.selectedFilter,
          filterIntensity: state.filterIntensity,
          imageBytes: snapshot.data ?? Uint8List(0), // 썸네일이 없으면 빈 리스트
          isExistingNodeEdit: widget.isExistingNodeEdit,
          onFilterChanged: (filter) {
            // ✅ 필터 선택만 하고 히스토리는 저장하지 않음 (바텀시트 닫을 때만 저장)
            // ✅ setState는 필수이지만, 비디오 위젯은 key로 재사용됨
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
      },
    );
  }

  /// 썸네일 가져오기 또는 생성 (캐싱)
  Future<Uint8List?> _getOrGenerateThumbnail(int index, File videoFile) {
    // 이미 캐시되어 있으면 반환
    if (_thumbnailCache.containsKey(index) && _thumbnailCache[index] != null) {
      return Future.value(_thumbnailCache[index]);
    }

    // 이미 생성 중이면 기존 Future 반환
    if (_thumbnailFutures.containsKey(index)) {
      return _thumbnailFutures[index]!;
    }

    // 새로 생성
    final future = _generateVideoThumbnail(videoFile)
        .then((bytes) {
          if (mounted) {
            _thumbnailCache[index] = bytes;
            _thumbnailFutures.remove(index);
          }
          return bytes;
        })
        .catchError((e) {
          _thumbnailFutures.remove(index);
          return null;
        });

    _thumbnailFutures[index] = future;
    return future;
  }

  /// 비디오 파일에서 썸네일 생성 (필터 프리뷰용)
  Future<Uint8List?> _generateVideoThumbnail(File videoFile) async {
    try {
      if (!await videoFile.exists()) {
        return null;
      }

      // ✅ 비디오의 첫 프레임(또는 중간 프레임)을 썸네일로 생성
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0, // 첫 프레임
        quality: 75,
      );

      return thumbnailBytes;
    } catch (e) {
      debugPrint('[SimpleVideoEditor] 썸네일 생성 오류: $e');
      return null;
    }
  }

  Widget _buildSpeedBottomSheet() {
    final state = _getCurrentEditState();
    final controller = _videoControllers[_currentIndex];

    return SpeedEditorBottomSheet(
      speed: state.playbackSpeed,
      onSpeedChanged: (v) {
        setState(() {
          state.playbackSpeed = v;
        });
        if (controller != null && controller.value.isInitialized) {
          // ignore: discarded_futures
          controller.setPlaybackSpeed(v.clamp(0.5, 2.0));
        }
      },
      onDragEnd: () {
        _saveToHistorySnapshot(_currentIndex);
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
          ..saturation = state.saturation
          ..luminance = state.luminance
          ..exposure = state.exposure
          ..sharpness = state.sharpness
          ..temperature = state.temperature
          ..blur = state.blur
          ..vignette = state.vignette;

    return AdjustmentEditorBottomSheet(
      key: _adjustmentEditorKey,
      state: adjustmentState,
      onStateChanged: (newState) {
        setState(() {
          state.brightness = newState.brightness;
          state.contrast = newState.contrast;
          state.saturation = newState.saturation;
          state.luminance = newState.luminance;
          state.exposure = newState.exposure;
          state.sharpness = newState.sharpness;
          state.temperature = newState.temperature;
          state.blur = newState.blur;
          state.vignette = newState.vignette;
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

/// Vignette 효과 페인터
class _VignettePainter extends CustomPainter {
  final double intensity; // 0.0 ~ 1.0

  _VignettePainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.0) return;

    final maxRadius = math.max(size.width, size.height) * 0.8;

    // 그라데이션으로 비네팅 효과 생성
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: maxRadius,
      colors: [Colors.transparent, Colors.black.withOpacity(intensity * 0.6)],
      stops: const [0.3, 1.0],
    );

    final paint =
        Paint()
          ..shader = gradient.createShader(
            Rect.fromLTWH(0, 0, size.width, size.height),
          )
          ..blendMode = BlendMode.multiply;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_VignettePainter oldDelegate) {
    return oldDelegate.intensity != intensity;
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

/// 커스텀 Rect 클리퍼 (크롭 영역만 보여주기 위함)
class _CustomRectClipper extends CustomClipper<Rect> {
  _CustomRectClipper(this.clipRect);

  final Rect clipRect;

  @override
  Rect getClip(Size size) {
    return clipRect;
  }

  @override
  bool shouldReclip(covariant _CustomRectClipper oldClipper) {
    return oldClipper.clipRect != clipRect;
  }
}
