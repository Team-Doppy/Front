import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doppy/image/adjustment_editor.dart';
import 'package:doppy/image/crop_editor.dart' show CropUtils, ImageRectUtils;
import 'package:doppy/image/filter_editor.dart' show FilterUtils;
import 'package:doppy/image/utils/filter_presets.dart';
import 'package:doppy/image/video_edit_spec.dart';
import 'package:doppy/image/video_trim_spec.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/editor/utils/video_upload_utils.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 비디오 트림 결과 (비파괴: 실제 ffmpeg 트림을 하지 않고 구간만 반환)
class VideoTrimResult {
  final VideoTrimSpec trim;
  // ✅ 트림/편집 스펙이 적용된 썸네일(파일) 경로
  // MediaPicker에서 노드 생성 시 즉시 적용하여 "원본 비율/원본 썸네일"로 보이는 문제를 방지한다.
  final String? thumbnailPath;
  VideoTrimResult({required this.trim, this.thumbnailPath});
}

/// 트림 범위 설정 (도메인 규칙)
class TrimRangeConfig {
  /// 최소 트림 길이 (초)
  static const double minLength = 1.0;

  /// 최대 트림 길이 (초)
  static const double maxTrimLength = 60.0;

  /// 선택 최소 간격 (초) - 현재는 minLength와 동일하게 사용
  static const double selectionMinGap = 1.0;
}

/// Trimmer 클래스 - video_trimmer 패키지 구조와 동일
/// 비디오 상태를 관리하는 ChangeNotifier
class Trimmer extends ChangeNotifier {
  VideoPlayerController? _videoPlayerController;
  File? _videoFile;
  Duration? _videoDuration;

  double _startValue = 0.0;
  double _endValue = 60.0;
  // ✅ 편집(속도) 스펙이 있는 경우: "최종 결과물 기준" 길이 제한 계산에 사용
  // - 예: playbackSpeed=2.0이면 원본에서 최대 120초까지 선택 가능(최종 60초)
  // - 예: playbackSpeed=0.5이면 원본에서 최대 30초까지 선택 가능(최종 60초)
  double _playbackSpeed = 1.0;
  // 🎯 ValueNotifier로 currentPosition 최적화 (100ms 타이머 업데이트 최적화)
  final ValueNotifier<double> _currentPositionNotifier = ValueNotifier<double>(
    0.0,
  );
  bool _isPlaying = false;
  bool _isInitialized = false;

  // 썸네일
  List<Uint8List?> _thumbnails = [];
  bool _isLoadingThumbnails = false;

  Timer? _playbackTimer;

  // 🎯 핸들 드래그 상태 (타이머 보정 충돌 방지용)
  bool _isHandleDragging = false;
  // 🎯 재생바 드래그 상태 (타이머 보정 충돌 방지용)
  bool _isPlaybackBarDragging = false;

  VideoPlayerController? get videoPlayerController => _videoPlayerController;
  File? get videoFile => _videoFile;
  Duration? get videoDuration => _videoDuration;
  double get startValue => _startValue;
  double get endValue => _endValue;
  double get currentPosition => _currentPositionNotifier.value;
  ValueNotifier<double> get currentPositionNotifier => _currentPositionNotifier;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  List<Uint8List?> get thumbnails => _thumbnails;
  bool get isLoadingThumbnails => _isLoadingThumbnails;
  double get playbackSpeed => _playbackSpeed;

  // 🎯 도메인 규칙 접근
  double get minLength => TrimRangeConfig.minLength;
  double get maxTrimLength => TrimRangeConfig.maxTrimLength * _playbackSpeed;
  double get selectionMinGap => TrimRangeConfig.selectionMinGap;

  /// ✅ 편집 스펙(재생 속도)에 맞춰 "최종 결과물 기준" 트림 최대 길이를 조정한다.
  /// - 속도 변경은 (현재 파일에서는) 트리머 진입 시 1회만 적용되는 용도
  void setPlaybackSpeed(double speed) {
    final next = speed.clamp(0.5, 2.0);
    if (_playbackSpeed == next) return;
    _playbackSpeed = next;

    // 이미 로드된 상태라면, 현재 선택 구간이 새로운 maxTrimLength를 넘지 않게 보정
    final maxSeconds = _videoDuration?.inSeconds.toDouble() ?? 0.0;
    if (maxSeconds > 0) {
      final effectiveMaxEnd = math.min(maxSeconds, maxTrimLength);
      if (_endValue > effectiveMaxEnd) {
        _endValue = effectiveMaxEnd;
      }
      if (_startValue > _endValue) {
        _startValue = (_endValue - selectionMinGap).clamp(0.0, _endValue);
      }
      _currentPositionNotifier.value = _currentPositionNotifier.value.clamp(
        _startValue,
        _endValue,
      );
    }
    notifyListeners();
  }

  /// 비디오 로드
  Future<void> loadVideo({
    required File videoFile,
    required Duration videoDuration,
  }) async {
    _videoFile = videoFile;
    _videoDuration = videoDuration;

    final maxSeconds = videoDuration.inSeconds.toDouble();
    _startValue = 0.0;
    _endValue = maxSeconds < maxTrimLength ? maxSeconds : maxTrimLength;
    _currentPositionNotifier.value = _startValue;

    try {
      _videoPlayerController = VideoPlayerController.file(videoFile);
      await _videoPlayerController!.initialize();

      _isInitialized = true;
      _videoPlayerController!.seekTo(
        Duration(milliseconds: (_startValue * 1000).toInt()),
      );

      _startPlaybackTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('[Trimmer] 비디오 초기화 오류: $e');
      rethrow;
    }
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    // 🎯 재생바 동기화를 위해 타이머 주기를 더 빠르게 (100ms -> 33ms, 약 30fps)
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_videoPlayerController == null || !_isInitialized) {
        timer.cancel();
        return;
      }

      // 🎯 핸들/재생바 드래그 중에는 타이머 보정 개입 금지 (타이밍 충돌 방지)
      if (_isHandleDragging || _isPlaybackBarDragging) {
        return;
      }

      final position =
          _videoPlayerController!.value.position.inMilliseconds / 1000.0;
      final isPlaying = _videoPlayerController!.value.isPlaying;

      bool needsUpdate = false;

      // 🎯 재생 범위 체크 (재생 중일 때만)
      if (isPlaying) {
        // 🎯 재생바 중심이 핸들 경계에 도달하면 즉시 정지 (핸들 두께 고려)
        // 재생바 중심이 endValue에 거의 도달하면 정지 (0.005초 여유로 더 정밀하게)
        final stopThreshold = _endValue - 0.005;

        if (position >= stopThreshold) {
          // 끝 도달: 일시정지하고 시작으로 이동
          _videoPlayerController!.pause();
          final startMs =
              ((_startValue.clamp(0.0, double.infinity)) * 1000).toInt();
          if (startMs < 0) return; // 음수 방지
          _videoPlayerController!.seekTo(Duration(milliseconds: startMs));
          _isPlaying = false;
          _currentPositionNotifier.value = _startValue.clamp(
            0.0,
            double.infinity,
          );
          needsUpdate = true;
        } else if (position < _startValue - 0.01) {
          // 시작 이전: 시작으로 이동 (0.01초 여유를 두어 시작 핸들과 붙어있을 때 재생 가능)
          final startMs =
              ((_startValue.clamp(0.0, double.infinity)) * 1000).toInt();
          if (startMs < 0) return; // 음수 방지
          _videoPlayerController!.seekTo(Duration(milliseconds: startMs));
          _currentPositionNotifier.value = _startValue.clamp(
            0.0,
            double.infinity,
          );
          needsUpdate = true;
        } else {
          // 정상 범위 내
          // 🎯 ValueNotifier는 자체적으로 리스너를 가지므로 notifyListeners 불필요
          final clampedPosition = position.clamp(0.0, double.infinity);
          if (_currentPositionNotifier.value != clampedPosition) {
            _currentPositionNotifier.value = clampedPosition;
            // currentPosition 변경은 ValueNotifier가 처리하므로 needsUpdate는 false
          }
        }
      }

      // 재생 상태 동기화
      if (_isPlaying != isPlaying) {
        _isPlaying = isPlaying;
        needsUpdate = true;
      }

      if (needsUpdate) {
        notifyListeners();
      }
    });
  }

  /// 재생/일시정지 토글
  void videoPlaybackControl() async {
    if (_videoPlayerController == null || !_isInitialized) {
      return;
    }

    if (_isPlaying) {
      _videoPlayerController!.pause();
      _isPlaying = false;
    } else {
      // 🎯 현재 위치 확인 및 범위 내로 조정
      final currentPos = _currentPositionNotifier.value;

      // 범위를 벗어났거나 끝에 도달했거나 시작 핸들과 붙어있으면 시작 지점으로 이동
      // 0.01초 여유를 두어 시작 핸들과 붙어있을 때도 재생 가능하도록 함
      if (currentPos >= _endValue - 0.01 || currentPos <= _startValue + 0.01) {
        // 시작 지점으로 이동 (비동기 완료 대기)
        await seekTo(_startValue);
        // 🎯 seekTo 완료 후 즉시 위치 업데이트 (재생바가 바로 움직이도록)
        _currentPositionNotifier.value = _startValue;
        // 재생 시작
        await _videoPlayerController!.play();
        _isPlaying = true;
        // 🎯 재생 시작 직후 즉시 위치 업데이트 (지연 없이 재생바 움직임)
        Future.microtask(() {
          if (_videoPlayerController != null && _isInitialized) {
            final videoPos =
                _videoPlayerController!.value.position.inMilliseconds / 1000.0;
            _currentPositionNotifier.value = videoPos.clamp(
              _startValue,
              _endValue,
            );
          }
        });
      } else {
        // 🎯 재생 시작 시 즉시 현재 위치를 업데이트 (재생바가 즉시 움직이도록)
        final videoPos =
            _videoPlayerController!.value.position.inMilliseconds / 1000.0;
        _currentPositionNotifier.value = videoPos.clamp(_startValue, _endValue);
        // 범위 내에 있으면 바로 재생
        await _videoPlayerController!.play();
        _isPlaying = true;
        // 🎯 재생 시작 직후 즉시 위치 업데이트 (지연 없이 재생바 움직임)
        Future.microtask(() {
          if (_videoPlayerController != null && _isInitialized) {
            final videoPos =
                _videoPlayerController!.value.position.inMilliseconds / 1000.0;
            _currentPositionNotifier.value = videoPos.clamp(
              _startValue,
              _endValue,
            );
          }
        });
      }
    }
    notifyListeners();
  }

  /// 재생 위치 이동 (명시적 사용자 액션에서만 사용)
  /// [clampToRange]가 true이면 startValue와 endValue 사이로 클램프,
  /// false이면 전체 비디오 길이 내로만 클램프 (오버레이 드래그용)
  Future<void> seekTo(double position, {bool clampToRange = true}) async {
    if (_videoPlayerController == null || !_isInitialized) {
      return;
    }

    final maxSeconds = _videoDuration?.inSeconds.toDouble() ?? 0.0;

    // 🎯 클램프 적용
    final clampedPosition =
        clampToRange
            ? position.clamp(
              _startValue.clamp(0.0, double.infinity),
              _endValue.clamp(0.0, double.infinity),
            )
            : position.clamp(
              0.0,
              maxSeconds > 0 ? maxSeconds : double.infinity,
            );

    // 🎯 Duration 생성 시 음수 방지
    final milliseconds = (clampedPosition * 1000).toInt();
    if (milliseconds < 0) return; // 음수 방지

    // 🎯 재생 중이 아니어도 프레임이 업데이트되도록 시크 수행
    await _videoPlayerController!.seekTo(Duration(milliseconds: milliseconds));

    // 🎯 즉시 UI 업데이트 (비디오 프레임은 seekTo가 비동기로 처리)
    _currentPositionNotifier.value = clampedPosition;
    notifyListeners();

    debugPrint(
      '[Trimmer] seekTo: ${clampedPosition.toStringAsFixed(2)}s (${milliseconds}ms), clampToRange: $clampToRange',
    );
  }

  /// 시작 값 변경
  void onChangeStart(double value) {
    // 🎯 유효하지 않은 값 방지
    if (value.isNaN || value.isInfinite || value < 0) return;
    final maxSeconds = _videoDuration?.inSeconds.toDouble() ?? 0.0;
    if (maxSeconds > 0 && value > maxSeconds) return;

    // 🎯 핸들 위치 역전 방지: 시작 값이 끝 값보다 크거나 같으면 무시
    if (value >= _endValue) return;

    _startValue = value.clamp(
      0.0,
      maxSeconds > 0 ? maxSeconds : double.infinity,
    );
    // 🎯 currentPosition 즉시 클램프 (타이머 보정 충돌 방지)
    _currentPositionNotifier.value = _currentPositionNotifier.value.clamp(
      _startValue,
      _endValue,
    );
    notifyListeners();
  }

  /// 끝 값 변경
  void onChangeEnd(double value) {
    // 🎯 유효하지 않은 값 방지
    if (value.isNaN || value.isInfinite || value < 0) return;
    final maxSeconds = _videoDuration?.inSeconds.toDouble() ?? 0.0;
    if (maxSeconds > 0 && value > maxSeconds) return;

    // 🎯 핸들 위치 역전 방지: 끝 값이 시작 값보다 작거나 같으면 무시
    if (value <= _startValue) return;

    _endValue = value.clamp(0.0, maxSeconds > 0 ? maxSeconds : double.infinity);
    // 🎯 currentPosition 즉시 클램프 (타이머 보정 충돌 방지)
    _currentPositionNotifier.value = _currentPositionNotifier.value.clamp(
      _startValue,
      _endValue,
    );
    notifyListeners();
  }

  /// 핸들 드래그 상태 설정 (타이머 보정 충돌 방지용)
  void setHandleDragging(bool isDragging) {
    _isHandleDragging = isDragging;
  }

  /// 재생바 드래그 상태 설정 (타이머 보정 충돌 방지용)
  void setPlaybackBarDragging(bool isDragging) {
    _isPlaybackBarDragging = isDragging;
  }

  /// 썸네일 로드
  Future<void> loadThumbnails() async {
    if (_videoFile == null || _videoDuration == null) return;

    _isLoadingThumbnails = true;
    notifyListeners();

    try {
      if (!await _videoFile!.exists()) {
        _isLoadingThumbnails = false;
        notifyListeners();
        return;
      }

      final totalSeconds = _videoDuration!.inSeconds.toDouble();
      if (totalSeconds <= 0) {
        _isLoadingThumbnails = false;
        notifyListeners();
        return;
      }

      // 🎯 영상 길이에 비례해서 프레임 간격 조정
      const int maxFrames = 30;
      const int minFrames = 5;

      // 🎯 영상 길이에 따라 프레임 간격 결정
      double intervalSeconds;
      if (totalSeconds <= 30) {
        // 짧은 영상: 1초 간격
        intervalSeconds = 1.0;
      } else if (totalSeconds <= 60) {
        // 중간 영상: 2초 간격
        intervalSeconds = 2.0;
      } else if (totalSeconds <= 120) {
        // 긴 영상: 3초 간격
        intervalSeconds = 3.0;
      } else {
        // 매우 긴 영상: 4초 간격
        intervalSeconds = 4.0;
      }

      int frameCount = (totalSeconds / intervalSeconds).ceil();
      frameCount = frameCount.clamp(minFrames, maxFrames);

      // 🎯 실제 간격 재계산 (프레임 개수에 맞춰)
      intervalSeconds = totalSeconds / frameCount;

      // 🎯 썸네일 리스트를 미리 초기화하여 즉시 렌더링 가능하도록 함
      _thumbnails = List<Uint8List?>.filled(frameCount, null);
      notifyListeners();

      // 🎯 각 썸네일을 비동기로 생성하고 완료되는 대로 즉시 업데이트
      for (int i = 0; i < frameCount; i++) {
        final timeMs = (i * intervalSeconds * 1000).toInt();

        // 🎯 각 썸네일을 독립적으로 생성 (순차 대기하지 않음)
        VideoThumbnail.thumbnailData(
              video: _videoFile!.path,
              imageFormat: ImageFormat.JPEG,
              timeMs: timeMs,
              quality: 70,
            )
            .then((bytes) {
              // 🎯 완료된 썸네일을 즉시 해당 인덱스에 업데이트
              if (i < _thumbnails.length) {
                _thumbnails[i] = bytes;
                notifyListeners();
              }
            })
            .catchError((e) {
              debugPrint('[Trimmer] 썸네일 생성 실패 ($timeMs ms): $e');
              // 실패한 경우 null로 유지 (이미 null로 초기화됨)
            });
      }

      // 🎯 모든 썸네일 생성이 완료될 때까지 대기하지 않고 즉시 반환
      // 각 썸네일은 완료되는 대로 개별적으로 업데이트됨
      _isLoadingThumbnails = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Trimmer] 썸네일 로드 오류: $e');
      _isLoadingThumbnails = false;
      notifyListeners();
    }
  }

  /// 트리밍된 비디오 저장 (썸네일 포함)
  /// ✅ 크롭이 있으면 트림+크롭, 없으면 트림만 수행
  /// 압축은 플레이스홀더 상태에서 업로드 시 진행
  VideoTrimSpec buildTrimSpec() {
    return VideoTrimSpec(startSeconds: _startValue, endSeconds: _endValue);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _currentPositionNotifier.dispose();
    super.dispose();
  }
}

/// VideoViewer 위젯 - video_trimmer 패키지 구조와 동일
class VideoViewer extends StatelessWidget {
  final Trimmer trimmer;
  final VideoEditSpec? editSpec;

  const VideoViewer({super.key, required this.trimmer, this.editSpec});

  /// editor의 `_applyEdit()`(크롭 적용 후)와 동일한 방식으로
  /// cropRectImage가 화면을 “꽉 채우도록(contain + center)” 만드는 scale/offset을 계산한다.
  /// 반환값:
  /// - imageRect: VideoPlayer를 배치할 rect (screen)
  /// - cropRectScreen: imageRect 기준으로 변환된 crop rect (screen)
  ({Rect imageRect, Rect cropRectScreen}) _computeCropLayout({
    required Size containerSize,
    required Size videoSize,
    required Rect cropRectImage,
  }) {
    // 1) scale=1, offset=0 기준 rect
    final baseRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: 1.0,
      offset: Offset.zero,
    );

    // 2) baseRect에서 cropRectScreen 계산
    final baseCropScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropRectImage,
      screenImageRect: baseRect,
      imageSize: videoSize,
    );

    // 3) crop이 화면 안에 완전히 들어오도록(contain) 최소 스케일 선택
    final scaleFactor = math.min(
      containerSize.width / baseCropScreen.width,
      containerSize.height / baseCropScreen.height,
    );

    // 4) 새 스케일 적용 (offset=0 기준)
    final scaledRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: scaleFactor,
      offset: Offset.zero,
    );

    final scaledCropScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropRectImage,
      screenImageRect: scaledRect,
      imageSize: videoSize,
    );

    // 5) crop 중심을 화면 중심으로 이동시키는 offsetDelta
    final containerCenter = Offset(
      containerSize.width / 2,
      containerSize.height / 2,
    );
    final offsetDelta = containerCenter - scaledCropScreen.center;

    // 6) 최종 rect + 최종 crop rect
    final finalRect = ImageRectUtils.computeImageRect(
      containerSize: containerSize,
      imageSize: videoSize,
      scale: scaleFactor,
      offset: offsetDelta,
    );
    final finalCropScreen = ImageRectUtils.imageToScreenRect(
      imageRect: cropRectImage,
      screenImageRect: finalRect,
      imageSize: videoSize,
    );

    return (imageRect: finalRect, cropRectScreen: finalCropScreen);
  }

  ColorFilter? _getColorFilterFromSpec(VideoEditSpec? spec) {
    if (spec == null) return null;

    final FilterModel? filter =
        (spec.filterName == null)
            ? null
            : presetFiltersList.cast<FilterModel?>().firstWhere(
              (f) => f?.name == spec.filterName,
              orElse: () => null,
            );

    final filterMatrix = FilterUtils.getFilterMatrix(
      filter,
      intensity: spec.filterIntensity,
    );
    final adjustmentMatrix = AdjustmentUtils.getAdjustmentMatrix(
      brightness: spec.brightness,
      contrast: spec.contrast,
      saturation: spec.saturation,
      luminance: spec.luminance,
      exposure: spec.exposure,
      temperature: spec.temperature,
    );

    if (filterMatrix != null && adjustmentMatrix != null) {
      return ColorFilter.matrix(
        _multiplyColorMatrices(filterMatrix, adjustmentMatrix),
      );
    } else if (filterMatrix != null) {
      return ColorFilter.matrix(filterMatrix);
    } else if (adjustmentMatrix != null) {
      return ColorFilter.matrix(adjustmentMatrix);
    }
    return null;
  }

  // 4x5 행렬 곱셈
  List<double> _multiplyColorMatrices(List<double> a, List<double> b) {
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: trimmer,
      builder: (context, _) {
        if (!trimmer.isInitialized || trimmer.videoPlayerController == null) {
          return const Center(child: CupertinoActivityIndicator());
        }

        final controller = trimmer.videoPlayerController!;
        final spec = editSpec;

        return LayoutBuilder(
          builder: (context, constraints) {
            final containerSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final videoSize = Size(
              controller.value.size.width.toDouble(),
              controller.value.size.height.toDouble(),
            );

            // ✅ 원본 비디오가 표시될 rect (screen)
            final fullImageRect = ImageRectUtils.computeImageRect(
              containerSize: containerSize,
              imageSize: videoSize,
              scale: 1.0,
              offset: Offset.zero,
            );

            // ✅ crop이 있으면: editor와 동일한 방식으로 imageRect/cropRectScreen 재계산
            Rect imageRect = fullImageRect;
            Rect? cropRectScreen;
            if (spec?.cropRectImage != null) {
              final r = _computeCropLayout(
                containerSize: containerSize,
                videoSize: videoSize,
                cropRectImage: spec!.cropRectImage!,
              );
              imageRect = r.imageRect;
              cropRectScreen = r.cropRectScreen;
            }

            // base video (fullImageRect에 맞게 배치될 예정)
            Widget videoWidget = SizedBox.expand(
              child: VideoPlayer(controller),
            );

            // ColorFilter
            final cf = _getColorFilterFromSpec(spec);
            if (cf != null) {
              videoWidget = ColorFiltered(colorFilter: cf, child: videoWidget);
            }

            // Blur
            // ✅ 프리뷰 블러는 "노드/저장 결과" 기준으로 보정한다.
            // - export/노드는 원본 해상도(px) 좌표계에서 blur가 적용되므로,
            //   프리뷰에서는 displayWidth/sourceWidth 비율만큼 sigma를 낮춘다.
            final sigma = AdjustmentUtils.blurSigmaForPreview(
              blur: (spec?.blur ?? 0.0),
              sourceWidthPx: videoSize.width,
              displayWidthPx: imageRect.width,
            );
            videoWidget = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: videoWidget,
            );

            // Vignette
            final vignetteIntensity = (spec?.vignette ?? 0.0) / 100.0;
            videoWidget = CustomPaint(
              painter: _TrimmerVignettePainter(intensity: vignetteIntensity),
              child: videoWidget,
            );

            // rotation/flip (+ 회전 시 빈공간 방지용 cover scale)
            final totalRotationDeg =
                (spec?.rotation ?? 0) +
                ((spec?.rotationQuarterTurns ?? 0) * 90);
            final rotationRadians = totalRotationDeg * (3.14159265359 / 180.0);

            // ✅ editor 메인 프리뷰와 동일: (crop clip) + (rotation/flip) + (cover k)
            final anchor = imageRect.center;
            double kCover = 1.0;
            if (cropRectScreen != null) {
              kCover = CropUtils.coverScaleToContainCropRect(
                imageRectScreen: imageRect,
                cropRectScreen: cropRectScreen,
                pivot: anchor,
                thetaRad: rotationRadians,
              );
            }
            final sx = ((spec?.flipHorizontal ?? false) ? -1.0 : 1.0) * kCover;
            final sy = ((spec?.flipVertical ?? false) ? -1.0 : 1.0) * kCover;

            final m =
                Matrix4.identity()
                  ..translate(anchor.dx, anchor.dy)
                  ..rotateZ(rotationRadians)
                  ..scale(sx, sy)
                  ..translate(-anchor.dx, -anchor.dy);

            Widget finalVideo = Transform(transform: m, child: videoWidget);

            // crop clip (imageRect 기준)
            if (cropRectScreen != null) {
              final clipRect = Rect.fromLTWH(
                cropRectScreen.left - imageRect.left,
                cropRectScreen.top - imageRect.top,
                cropRectScreen.width,
                cropRectScreen.height,
              );
              finalVideo = ClipRect(
                clipper: _TrimmerRectClipper(clipRect),
                child: finalVideo,
              );
            }

            final positionedVideo = Positioned(
              left: imageRect.left,
              top: imageRect.top,
              width: imageRect.width,
              height: imageRect.height,
              child: finalVideo,
            );

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      debugPrint('[VideoViewer] 재생 버튼 탭 감지!');
                      trimmer.videoPlaybackControl();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Stack(children: [positionedVideo]),
                  ),
                ),
                // 재생/일시정지 아이콘 오버레이
                IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        trimmer.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TrimmerRectClipper extends CustomClipper<Rect> {
  final Rect rect;
  _TrimmerRectClipper(this.rect);

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _TrimmerRectClipper oldClipper) =>
      oldClipper.rect != rect;
}

class _TrimmerVignettePainter extends CustomPainter {
  final double intensity; // 0..1
  _TrimmerVignettePainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final rect = Offset.zero & size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) * 1.05;

    final shader = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [Colors.transparent, Colors.black.withOpacity(0.55 * intensity)],
      stops: const [0.55, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    final paint = Paint()..shader = shader;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _TrimmerVignettePainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}

/// 크롭 핸들 UI 커스텀 페인터 (핸들 + 가로선)
class _CropHandlePainter extends CustomPainter {
  final Color color;
  final Color innerBarColor; // 핸들 중앙 이너 바 색상
  final Color borderColor; // 핸들 보더 색상
  final double startX;
  final double endX;
  final double handleWidth;
  final double timelineHeight;
  final double handleExtension; // 위아래 확장 크기 (더 두껍게)

  _CropHandlePainter({
    required this.color,
    required this.innerBarColor,
    required this.borderColor,
    required this.startX,
    required this.endX,
    required this.handleWidth,
    required this.timelineHeight,
    this.handleExtension = 12, // 위아래 라인 두께 증가 (8.0 -> 10.0, 핸들보다 바깥쪽으로 더 두껍게)
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    // 🎯 실제 타임라인 높이 사용 (size.height)
    final actualTimelineHeight = size.height;

    // 🎯 핸들 위치 계산
    // - startX/endX는 "경계선(시간)" 좌표라서 0/width일 수 있음
    // - 하지만 핸들은 두께(handleWidth)가 있어, 그대로 그리면 화면 밖(-x)으로 나가 hit-test가 안 잡힘
    // - 따라서 핸들 Rect는 항상 화면 내부(0~size.width)에 clamp해서 "완전 왼쪽 끝"에서도 드래그 가능하게 함
    final rawLeftHandleX = startX - handleWidth / 2;
    final rawRightHandleX = endX - handleWidth / 2;
    final leftHandleX = rawLeftHandleX.clamp(0.0, size.width - handleWidth);
    final rightHandleX = rawRightHandleX.clamp(0.0, size.width - handleWidth);
    final borderWidth = 2.5; // 핸들 보더 두께

    // 🎯 가로선 위치: 핸들 보더 안쪽 경계에 정확히 맞춤
    // 핸들 보더는 stroke이므로 중심선이 경계에 있음
    // 보더 중심선에서 안쪽으로 borderWidth/2만큼 이동
    // ✅ startX/endX가 화면 경계에 붙을 때는 "clamp된 핸들 Rect" 기준으로 계산해야 겹침/어긋남이 없음
    final horizontalLineStartX =
        leftHandleX + handleWidth - borderWidth / 2; // 왼쪽 핸들 보더 안쪽 경계
    final horizontalLineEndX =
        rightHandleX + borderWidth / 2; // 오른쪽 핸들 보더 안쪽 경계
    final horizontalLineWidth = horizontalLineEndX - horizontalLineStartX;

    // 🎯 가로선 두께를 핸들보다 더 두껍게 (핸들 위쪽으로 더 확장)
    // 핸들 높이는 handleExtension에 의존하지만, 가로선만 더 두껍게 그리기
    final topHorizontalLineThickness = handleExtension + 1.5; // 위쪽 가로선 두께
    final bottomHorizontalLineThickness = handleExtension + 4.0; // 아래쪽 가로선 두께

    // 🎯 위쪽 가로선 (핸들 보더 안쪽 경계에 정확히 맞춤, 더 두껍게)
    if (horizontalLineWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          horizontalLineStartX,
          -topHorizontalLineThickness, // 핸들보다 더 위로 확장
          horizontalLineWidth,
          topHorizontalLineThickness,
        ),
        paint,
      );
    }

    // 🎯 아래쪽 가로선 (핸들 보더 안쪽 경계에 정확히 맞춤, 더 두껍게)
    if (horizontalLineWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          horizontalLineStartX,
          actualTimelineHeight,
          horizontalLineWidth,
          bottomHorizontalLineThickness, // 핸들보다 더 아래로 확장
        ),
        paint,
      );
    }

    // 🎯 왼쪽 핸들 (바깥쪽 위아래에만 보더 레디어스)
    final leftHandleRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        leftHandleX,
        -handleExtension,
        handleWidth,
        actualTimelineHeight + handleExtension * 2 + 2,
      ),
      topLeft: const Radius.circular(6), // 바깥쪽 위
      bottomLeft: const Radius.circular(6), // 바깥쪽 아래
      topRight: Radius.zero, // 안쪽 위
      bottomRight: Radius.zero, // 안쪽 아래
    );
    // 핸들 채우기
    canvas.drawRRect(leftHandleRect, paint);
    // 핸들 보더 (두껍게) - 가로선 위에 그려서 가로선을 덮음
    final borderPaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth; // 보더 두께
    canvas.drawRRect(leftHandleRect, borderPaint);

    // 🎯 오른쪽 핸들 (바깥쪽 위아래에만 보더 레디어스)
    final rightHandleRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        rightHandleX,
        -handleExtension,
        handleWidth,
        actualTimelineHeight + handleExtension * 2 + 2,
      ),
      topLeft: Radius.zero, // 안쪽 위
      bottomLeft: Radius.zero, // 안쪽 아래
      topRight: const Radius.circular(6), // 바깥쪽 위
      bottomRight: const Radius.circular(6), // 바깥쪽 아래
    );
    // 핸들 채우기
    canvas.drawRRect(rightHandleRect, paint);
    // 핸들 보더 (두껍게) - 가로선 위에 그려서 가로선을 덮음
    canvas.drawRRect(rightHandleRect, borderPaint);

    // 🎯 핸들 중앙 얇은 이너 바 (surface 색상, 높이는 핸들 높이의 1/4)
    final innerBarWidth = 2.0; // 얇은 이너 바 두께
    final handleHeight =
        actualTimelineHeight + handleExtension * 2 - 2; // 핸들 높이 2px 감소
    final innerBarHeight = handleHeight / 4; // 핸들 높이의 1/4
    final innerBarTop =
        (handleHeight - innerBarHeight) / 2 - handleExtension; // 중앙 정렬

    final innerBarPaint =
        Paint()
          ..color = innerBarColor
          ..style = PaintingStyle.fill;

    final leftCenterX = leftHandleX + handleWidth / 2;
    final rightCenterX = rightHandleX + handleWidth / 2;

    // 왼쪽 핸들 중앙 이너 바 (높이 1/4, 중앙 배치)
    canvas.drawRect(
      Rect.fromLTWH(
        leftCenterX - innerBarWidth / 2,
        innerBarTop,
        innerBarWidth,
        innerBarHeight,
      ),
      innerBarPaint,
    );

    // 오른쪽 핸들 중앙 이너 바 (높이 1/4, 중앙 배치)
    canvas.drawRect(
      Rect.fromLTWH(
        rightCenterX - innerBarWidth / 2,
        innerBarTop,
        innerBarWidth,
        innerBarHeight,
      ),
      innerBarPaint,
    );
  }

  @override
  bool shouldRepaint(_CropHandlePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.innerBarColor != innerBarColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.startX != startX ||
        oldDelegate.endX != endX ||
        oldDelegate.handleWidth != handleWidth ||
        oldDelegate.timelineHeight != timelineHeight;
  }
}

/// 핸들 커스텀 페인터 (개별 핸들용 - 레거시)
class _HandlePainter extends CustomPainter {
  final Color color;
  final bool isDragging;

  _HandlePainter({required this.color, this.isDragging = false});

  @override
  void paint(Canvas canvas, Size size) {
    // 🎯 이 페인터는 드래그 감지 영역용으로만 사용되며, 실제로는 아무것도 그리지 않음
    // 실제 핸들 UI는 _CropHandlePainter에서 그려지므로 여기서는 그리지 않음
    // 연한 이너라인 중복 방지를 위해 모든 그리기 코드 제거
  }

  @override
  bool shouldRepaint(_HandlePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isDragging != isDragging;
  }
}

/// TrimEditor 위젯 - video_trimmer 패키지 구조와 동일
class TrimEditor extends StatefulWidget {
  final Trimmer trimmer;
  final double viewerHeight;
  final double viewerWidth;
  final Duration? maxVideoLength;
  final Function(double)? onChangeStart;
  final Function(double)? onChangeEnd;
  final Function(bool)? onChangePlaybackState;

  const TrimEditor({
    super.key,
    required this.trimmer,
    this.viewerHeight = 50.0,
    this.viewerWidth = double.infinity,
    this.maxVideoLength,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangePlaybackState,
  });

  @override
  State<TrimEditor> createState() => _TrimEditorState();
}

class _TrimEditorState extends State<TrimEditor> {
  // 🎯 스크롤 컨트롤러 (타임라인 스크롤용)
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _timelineKey = GlobalKey();

  // 🎯 드래그 상태
  bool _isHandleDragging = false;
  bool _isPlaybackBarDragging = false;
  bool _isOverlayDragging = false; // 🎯 오버레이 드래그 상태 (핸들 움직임 방지용)

  // 🎯 드래그 시작 기준값 (누적 계산용)
  double? _dragStartValue;
  double? _dragStartTimelineX; // timeline absolute px (= localX + scrollOffset)
  double? _dragStartOppositeValue; // 🎯 반대쪽 핸들 값 (역전 방지용)
  double? _dragStartScrollOffset; // 🎯 드래그 시작 시점의 스크롤 오프셋(좌표계 고정)

  // 🎯 재생바 드래그 시작 기준값 (정밀 시크용)
  double? _playbackBarDragStartTimelineX; // timeline absolute px
  double? _playbackBarDragStartPosition; // seconds
  double? _playbackBarDragStartScrollOffset; // 🎯 재생바 드래그 시작 시점 스크롤 오프셋

  // 🎯 오버레이 드래그는 핸들 드래그와 동일한 변수 사용 (_dragStartValue, _dragStartOppositeValue, _dragStartTimelineX)
  // ✅ showOverlay=true(검정 반투명 영역)에서는 "구간 전체 이동"을 위해 별도 앵커 사용
  double? _overlayDragStartLocalX;
  double? _overlayDragStartScrollOffset;
  double? _overlayDragStartStartValue;
  double? _overlayDragStartEndValue;

  // ✅ 타임라인 스크롤 시 선택 구간(start/end)을 함께 이동시켜 "핸들 화면 위치 고정"
  bool _isTimelineScrollSyncActive = false;
  double? _timelineScrollAnchorStartPx; // startValue*pxPerSecond - scrollOffset
  double? _timelineScrollAnchorEndPx; // endValue*pxPerSecond - scrollOffset

  @override
  void initState() {
    super.initState();
    widget.trimmer.addListener(_onTrimmerUpdate);
  }

  @override
  void dispose() {
    widget.trimmer.removeListener(_onTrimmerUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTrimmerUpdate() {
    if (mounted) {
      setState(() {
        // UI 업데이트
      });
    }
  }

  // ✅ 드래그 감도(고정)
  // - 요청사항: "길이에 따른 감조절" 제거
  // - 검정 오버레이(구간 전체 이동) 드래그만 체감 감도를 더 높인다.
  static const double _overlayScrollSensitivity = 1.65;
  static const double _edgeDragSensitivity = 1.0;

  String _formatDuration(double seconds) {
    // 🎯 음수 방지 및 정수 변환
    final safeSeconds = seconds.clamp(0.0, double.infinity);
    final duration = Duration(
      milliseconds: (safeSeconds * 1000).toInt().clamp(0, 86400000),
    );
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${secs}s';
    }
  }

  String _formatDurationMMSS(double seconds) {
    // 🎯 음수 방지 및 정수 변환
    final safeSeconds = seconds.clamp(0.0, double.infinity);
    final duration = Duration(
      milliseconds: (safeSeconds * 1000).toInt().clamp(0, 86400000),
    );
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildTimeline() {
    if (widget.trimmer.isLoadingThumbnails) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalSeconds =
            widget.trimmer.videoDuration?.inSeconds.toDouble() ?? 0.0;

        if (totalSeconds <= 0 || totalWidth <= 0) {
          return const SizedBox.shrink();
        }

        // 🎯 도메인 규칙을 Trimmer에서 가져옴
        final maxTrimLength = widget.trimmer.maxTrimLength;
        final selectionMinGap = widget.trimmer.selectionMinGap;

        // 🎯 썸네일 스트립 너비 계산
        final thumbnailStripWidth =
            totalSeconds <= maxTrimLength
                ? totalWidth // 1분 미만: 화면 너비에 맞춤
                : (totalSeconds / maxTrimLength) *
                    (totalWidth * 2 / 3); // 1분 이상: 기존 방식

        final pxPerSecond = thumbnailStripWidth / totalSeconds;

        // 🎯 시간 → 픽셀 단방향 계산 (Trimmer의 시간 값이 단일 소스)
        final scrollOffset =
            _scrollController.hasClients ? _scrollController.offset : 0.0;

        // 🎯 시간 → 픽셀 변환 (전체 타임라인 기준, 단일 진실)
        final startPixel = widget.trimmer.startValue * pxPerSecond;
        final endPixel = widget.trimmer.endValue * pxPerSecond;

        // 🎯 경계선 좌표를 단일 clamp로 고정 (음수/초과 방지)
        double clampX(double x, double w) => x.clamp(0.0, w);
        final startBoundaryX = clampX(startPixel - scrollOffset, totalWidth);
        final endBoundaryX = clampX(endPixel - scrollOffset, totalWidth);

        // 🎯 검정 오버레이 계산 (경계선 기준)
        final leftOverlayWidth = startBoundaryX;
        final rightOverlayStart = endBoundaryX;
        final rightOverlayWidth = totalWidth - rightOverlayStart;

        // 🎯 핸들/드래그 영역 기준 통일: 핸들 중심 기준으로 계산
        const handleWidth = 8.0; // 핸들 두께 줄임
        const handleDragAreaWidth = 24.0; // 핸들 드래그 영역 넓이 (탭 감지 영역 확대)

        return Stack(
          key: _timelineKey,
          clipBehavior: Clip.none, // 🎯 핸들이 타임라인 밖으로 나가도 잘리지 않도록
          children: [
            // 🎯 ClipRect로 감싼 타임라인 콘텐츠
            ClipRect(
              child: Stack(
                children: [
                  // 썸네일 스트립 배경 (화면 전체 채우기)
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final colorScheme = Theme.of(context).colorScheme;
                        return Container(color: colorScheme.surface);
                      },
                    ),
                  ),

                  // 썸네일 스트립 (ScrollController 사용)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // ✅ 드래그(핸들/재생바/오버레이) 중에는 스크롤-선택구간 동기화 금지
                        if (_isHandleDragging ||
                            _isPlaybackBarDragging ||
                            _isOverlayDragging) {
                          return false;
                        }

                        if (!_scrollController.hasClients) return false;
                        if (pxPerSecond <= 0 ||
                            pxPerSecond.isNaN ||
                            pxPerSecond.isInfinite) {
                          return false;
                        }

                        // ✅ 1분+에서 사용자가 히스토리를 드래그(스크롤)할 때:
                        //    scrollOffset 변화에 맞춰 start/end를 같이 이동시켜
                        //    화면 상의 핸들 위치가 "고정"되도록 한다.
                        if (notification is ScrollStartNotification) {
                          _isTimelineScrollSyncActive = true;
                          final offset = _scrollController.offset;
                          _timelineScrollAnchorStartPx =
                              (widget.trimmer.startValue * pxPerSecond) -
                              offset;
                          _timelineScrollAnchorEndPx =
                              (widget.trimmer.endValue * pxPerSecond) - offset;
                        } else if (notification is ScrollUpdateNotification ||
                            notification is OverscrollNotification) {
                          if (!_isTimelineScrollSyncActive ||
                              _timelineScrollAnchorStartPx == null ||
                              _timelineScrollAnchorEndPx == null) {
                            // 혹시 모를 누락 대비: 즉시 앵커 재설정
                            _isTimelineScrollSyncActive = true;
                            final offset = _scrollController.offset;
                            _timelineScrollAnchorStartPx =
                                (widget.trimmer.startValue * pxPerSecond) -
                                offset;
                            _timelineScrollAnchorEndPx =
                                (widget.trimmer.endValue * pxPerSecond) -
                                offset;
                          }

                          final offset = _scrollController.offset;
                          final totalSeconds =
                              widget.trimmer.videoDuration?.inSeconds
                                  .toDouble() ??
                              0.0;
                          if (totalSeconds <= 0) return false;

                          final anchorStart = _timelineScrollAnchorStartPx!;
                          final anchorEnd = _timelineScrollAnchorEndPx!;

                          var newStart = (offset + anchorStart) / pxPerSecond;
                          var newEnd = (offset + anchorEnd) / pxPerSecond;

                          // ✅ 시간 범위 클램프 (길이 유지)
                          final length = newEnd - newStart;
                          if (length > 0) {
                            if (newStart < 0) {
                              newEnd -= newStart;
                              newStart = 0.0;
                            }
                            if (newEnd > totalSeconds) {
                              final over = newEnd - totalSeconds;
                              newStart -= over;
                              newEnd = totalSeconds;
                              if (newStart < 0) {
                                newStart = 0.0;
                                newEnd = (length).clamp(0.0, totalSeconds);
                              }
                            }
                          }

                          widget.trimmer.onChangeStart(newStart);
                          widget.trimmer.onChangeEnd(newEnd);
                        } else if (notification is ScrollEndNotification) {
                          _isTimelineScrollSyncActive = false;
                          _timelineScrollAnchorStartPx = null;
                          _timelineScrollAnchorEndPx = null;
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        // 🎯 핸들/재생바/오버레이 드래그 중 스크롤 잠금: 좌표계 흔들림(점프/걸림) 방지
                        physics:
                            (_isHandleDragging ||
                                    _isPlaybackBarDragging ||
                                    _isOverlayDragging)
                                ? const NeverScrollableScrollPhysics()
                                : const ClampingScrollPhysics(),
                        child: Builder(
                          builder: (context) {
                            // 🎯 청크 최소 너비 설정 (항상 긴 청크 보장)
                            const minChunkWidth = 60.0;
                            final thumbnails = widget.trimmer.thumbnails;

                            if (thumbnails.isEmpty) {
                              return SizedBox(
                                width: thumbnailStripWidth,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Builder(
                                        builder: (context) {
                                          final colorScheme =
                                              Theme.of(context).colorScheme;
                                          return Container(
                                            color:
                                                colorScheme
                                                    .surfaceContainerHighest,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // 🎯 청크 개수 계산: 최소 너비를 보장하면서 가능한 많은 청크 표시
                            final calculatedChunkWidth =
                                thumbnailStripWidth / thumbnails.length;
                            final effectiveChunkCount =
                                calculatedChunkWidth < minChunkWidth
                                    ? (thumbnailStripWidth / minChunkWidth)
                                        .floor()
                                        .clamp(1, thumbnails.length)
                                    : thumbnails.length;

                            // 🎯 실제 청크 너비 (최소 너비 보장)
                            final actualChunkWidth = (thumbnailStripWidth /
                                    effectiveChunkCount)
                                .clamp(minChunkWidth, double.infinity);

                            // 🎯 청크 인덱스 간격 계산 (원본 썸네일에서 샘플링)
                            final step =
                                thumbnails.length / effectiveChunkCount;

                            return SizedBox(
                              width: thumbnailStripWidth,
                              child: Row(
                                children: List.generate(effectiveChunkCount, (
                                  index,
                                ) {
                                  final sourceIndex = (index * step)
                                      .floor()
                                      .clamp(0, thumbnails.length - 1);
                                  final thumb = thumbnails[sourceIndex];

                                  return SizedBox(
                                    width: actualChunkWidth,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      transitionBuilder: (
                                        Widget child,
                                        Animation<double> animation,
                                      ) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                      child:
                                          thumb != null
                                              ? Image.memory(
                                                thumb,
                                                key: ValueKey<int>(
                                                  sourceIndex,
                                                ), // 각 청크를 고유하게 식별
                                                fit: BoxFit.cover,
                                                height: double.infinity,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => Container(),
                                              )
                                              : Builder(
                                                key: ValueKey<int>(sourceIndex),
                                                builder: (context) {
                                                  final colorScheme =
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme;
                                                  return Container(
                                                    color:
                                                        colorScheme
                                                            .surfaceContainerHighest,
                                                  );
                                                },
                                              ),
                                    ),
                                  );
                                }),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  // 🎯 선택 범위 외부 어두운 오버레이 (왼쪽) - 드래그 가능
                  if (leftOverlayWidth > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: leftOverlayWidth,
                      child: _buildDraggableOverlay(
                        isStart: true,
                        pxPerSecond: pxPerSecond,
                        scrollOffset: scrollOffset,
                        totalSeconds: totalSeconds,
                        maxTrimLength: maxTrimLength,
                        selectionMinGap: selectionMinGap,
                        showOverlay: true,
                      ),
                    ),

                  // 🎯 왼쪽 경계선 드래그 영역 (오버레이가 없을 때도 드래그 가능, 투명)
                  if (leftOverlayWidth == 0 &&
                      startBoundaryX >= 0 &&
                      startBoundaryX <= totalWidth)
                    Positioned(
                      left: (startBoundaryX - 20).clamp(0.0, totalWidth - 40),
                      top: 0,
                      bottom: 0,
                      width: 40,
                      child: _buildDraggableOverlay(
                        isStart: true,
                        pxPerSecond: pxPerSecond,
                        scrollOffset: scrollOffset,
                        totalSeconds: totalSeconds,
                        maxTrimLength: maxTrimLength,
                        selectionMinGap: selectionMinGap,
                        showOverlay: false, // 🎯 투명하게 (오버레이 없을 때만)
                      ),
                    ),

                  // 🎯 선택 범위 외부 어두운 오버레이 (오른쪽) - 드래그 가능
                  if (rightOverlayWidth > 0 && rightOverlayStart < totalWidth)
                    Positioned(
                      left: rightOverlayStart,
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: _buildDraggableOverlay(
                        isStart: false,
                        pxPerSecond: pxPerSecond,
                        scrollOffset: scrollOffset,
                        totalSeconds: totalSeconds,
                        maxTrimLength: maxTrimLength,
                        selectionMinGap: selectionMinGap,
                        showOverlay: true,
                      ),
                    ),

                  // 🎯 오른쪽 경계선 드래그 영역 (오버레이가 없을 때도 드래그 가능, 투명)
                  if (rightOverlayWidth == 0 &&
                      endBoundaryX >= 0 &&
                      endBoundaryX <= totalWidth)
                    Positioned(
                      left: (endBoundaryX - 20).clamp(0.0, totalWidth - 40),
                      top: 0,
                      bottom: 0,
                      width: 40,
                      child: _buildDraggableOverlay(
                        isStart: false,
                        pxPerSecond: pxPerSecond,
                        scrollOffset: scrollOffset,
                        totalSeconds: totalSeconds,
                        maxTrimLength: maxTrimLength,
                        selectionMinGap: selectionMinGap,
                        showOverlay: false, // 🎯 투명하게 (오버레이 없을 때만)
                      ),
                    ),

                  // 🎯 재생 시간 표시 (선택 구간 표시 박스 위에, 가운데 정렬)
                  Positioned(
                    top: -60,
                    left: startBoundaryX + (endBoundaryX - startBoundaryX) / 2,
                    child: Transform.translate(
                      offset: const Offset(-30, 0),
                      child: Builder(
                        builder: (context) {
                          final colorScheme = Theme.of(context).colorScheme;
                          return ValueListenableBuilder<double>(
                            valueListenable:
                                widget.trimmer.currentPositionNotifier,
                            builder: (context, currentPosition, _) {
                              final clampedPosition = currentPosition.clamp(
                                widget.trimmer.startValue,
                                widget.trimmer.endValue,
                              );
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: colorScheme.outline.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _formatDurationMMSS(clampedPosition),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // 🎯 선택 구간 표시 박스 (경계선 사이 위에) - 항상 표시
                  Positioned(
                    top: -30,
                    left: startBoundaryX + (endBoundaryX - startBoundaryX) / 2,
                    child: Transform.translate(
                      offset: const Offset(-50, 0),
                      child: Builder(
                        builder: (context) {
                          final colorScheme = Theme.of(context).colorScheme;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: colorScheme.outline.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${_formatDuration(widget.trimmer.startValue)} - ${_formatDuration(widget.trimmer.endValue)} (${_formatDuration(widget.trimmer.endValue - widget.trimmer.startValue)})',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // 🎯 재생 위치 바 (경계선 사이)
                  _buildPlaybackBar(
                    startX: startBoundaryX,
                    endX: endBoundaryX,
                    pxPerSecond: pxPerSecond,
                    maxVisibleWidth: totalWidth,
                  ),
                ],
              ),
            ),

            // 🎯 크롭 핸들 UI (CustomPainter로 통합) - 드래그 영역 위에 그리기
            Positioned.fill(
              child: IgnorePointer(
                child: Builder(
                  builder: (context) {
                    final colorScheme = Theme.of(context).colorScheme;
                    return CustomPaint(
                      painter: _CropHandlePainter(
                        color: colorScheme.onSurface,
                        innerBarColor: colorScheme.surface,
                        borderColor: colorScheme.outline,
                        startX: startBoundaryX,
                        endX: endBoundaryX,
                        handleWidth: handleWidth,
                        timelineHeight: 120.0, // 기본값 (실제로는 size.height 사용)
                        handleExtension: 2.0,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 🎯 왼쪽 핸들 드래그 영역 (탭 감지 영역 확대)
            // 🎯 화면 왼쪽 끝에서도 드래그 가능하도록 영역 확장
            Positioned(
              left: 0.0,
              top: -2,
              bottom: -2,
              width: math.max(
                handleDragAreaWidth,
                startBoundaryX + handleDragAreaWidth / 2,
              ),
              child: _buildHandle(
                isStart: true,
                pxPerSecond: pxPerSecond,
                scrollOffset: scrollOffset,
                totalSeconds: totalSeconds,
                totalWidth: totalWidth,
                maxTrimLength: maxTrimLength,
                selectionMinGap: selectionMinGap,
              ),
            ),

            // 🎯 오른쪽 핸들 드래그 영역 (탭 감지 영역 확대)
            // 🎯 화면 오른쪽 끝에서도 드래그 가능하도록 영역 확장
            Positioned(
              left: math.min(
                endBoundaryX - handleDragAreaWidth / 2,
                totalWidth - handleDragAreaWidth,
              ),
              top: -2,
              bottom: -2,
              width:
                  endBoundaryX > totalWidth - handleDragAreaWidth / 2
                      ? (totalWidth -
                          math.min(
                            endBoundaryX - handleDragAreaWidth / 2,
                            totalWidth - handleDragAreaWidth,
                          ))
                      : handleDragAreaWidth,
              child: _buildHandle(
                isStart: false,
                pxPerSecond: pxPerSecond,
                scrollOffset: scrollOffset,
                totalSeconds: totalSeconds,
                totalWidth: totalWidth,
                maxTrimLength: maxTrimLength,
                selectionMinGap: selectionMinGap,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 재생 위치 바
  Widget _buildPlaybackBar({
    required double startX,
    required double endX,
    required double pxPerSecond,
    required double maxVisibleWidth,
  }) {
    // 🎯 실제 startValue/endValue 사용 (정확한 동기화)
    final startValue = widget.trimmer.startValue;
    final endValue = widget.trimmer.endValue;

    // 🎯 선택 범위 길이(초)
    final rangeLength = endValue - startValue;
    if (rangeLength <= 0) {
      return const SizedBox.shrink();
    }

    // 🎯 핸들 경계를 기준으로 재생바 위치 계산
    // startX/endX는 경계선(=트림 시작/끝 시간의 픽셀 위치)임
    const handleWidth = 8.0; // 핸들 실제 두께 (드래그 영역이 아닌 실제 핸들)
    // 🎯 시작 핸들의 우측 끝 = startX + handleWidth/2
    // 🎯 엔드 핸들의 좌측 끝 = endX - handleWidth/2
    final innerStartX = startX + handleWidth / 2; // 시작 핸들 우측 끝
    final innerEndX = endX - handleWidth / 2; // 엔드 핸들 좌측 끝
    if (innerEndX <= innerStartX) {
      return const SizedBox.shrink();
    }

    // 🎯 재생바 두께/터치 영역 (항상 활성화)
    final barWidth = _isPlaybackBarDragging ? 4.0 : 3.0; // 두께 더 얇게
    final hitWidth = barWidth + 28.0;

    // 🎯 ValueListenableBuilder로 currentPosition 실시간 업데이트
    return ValueListenableBuilder<double>(
      valueListenable: widget.trimmer.currentPositionNotifier,
      builder: (context, currentPos, _) {
        // 🎯 현재 위치를 범위 내로 클램프
        final clampedCurrentPos = currentPos.clamp(startValue, endValue);

        // 🎯 시간 → 픽셀(화면 좌표) : pxPerSecond 단일 진실로 정밀 매핑
        // 핸들 경계(시작 핸들 우측 끝, 엔드 핸들 좌측 끝)를 기준으로 계산
        final rangeLength = endValue - startValue;
        final progress =
            rangeLength > 0
                ? (clampedCurrentPos - startValue) / rangeLength
                : 0.0;
        final rawCenterX = innerStartX + (progress * (innerEndX - innerStartX));

        // 🎯 "핸들 경계 사이" 내부에서만 이동 (바 두께 고려)
        final minCenterX = innerStartX + (barWidth / 2);
        final maxCenterX = innerEndX - (barWidth / 2);
        final clampedCenterX = rawCenterX.clamp(minCenterX, maxCenterX);

        return Positioned(
          left: clampedCenterX - (hitWidth / 2),
          top: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              if (_isHandleDragging) return;

              final box =
                  _timelineKey.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;

              // 재생 중이면 일시정지 후 드래그 시크 (정확도/UX)
              if (widget.trimmer.isPlaying) {
                widget.trimmer.videoPlaybackControl();
              }

              // ✅ 관성 스크롤이 남아있으면 즉시 멈추고, 드래그 동안 오프셋을 고정
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(_scrollController.offset);
              }

              final localX = box.globalToLocal(details.globalPosition).dx;
              final startScrollOffset =
                  _scrollController.hasClients ? _scrollController.offset : 0.0;
              final timelineX = localX + startScrollOffset;

              setState(() {
                _isPlaybackBarDragging = true;
                _playbackBarDragStartTimelineX = timelineX;
                _playbackBarDragStartPosition = currentPos;
                _playbackBarDragStartScrollOffset = startScrollOffset;
              });
              // 🎯 재생바 드래그 시작 시 Trimmer에 상태 전달 (타이머 보정 충돌 방지)
              widget.trimmer.setPlaybackBarDragging(true);
            },
            onPanUpdate: (details) {
              if (!_isPlaybackBarDragging ||
                  _playbackBarDragStartTimelineX == null ||
                  _playbackBarDragStartPosition == null ||
                  _playbackBarDragStartScrollOffset == null) {
                return;
              }

              final box =
                  _timelineKey.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;

              final localX = box.globalToLocal(details.globalPosition).dx;
              // ✅ 드래그 시작 시점의 스크롤 오프셋을 사용 (좌표계 고정)
              final timelineX = localX + _playbackBarDragStartScrollOffset!;

              // 🎯 픽셀 → 시간 (pxPerSecond 단일 진실로 정밀 매핑)
              final dx = timelineX - _playbackBarDragStartTimelineX!;
              final deltaSeconds = dx / pxPerSecond;

              var newPosition = _playbackBarDragStartPosition! + deltaSeconds;
              newPosition = newPosition.clamp(startValue, endValue);

              widget.trimmer.seekTo(newPosition);
            },
            onPanEnd: (_) {
              setState(() {
                _isPlaybackBarDragging = false;
                _playbackBarDragStartTimelineX = null;
                _playbackBarDragStartPosition = null;
                _playbackBarDragStartScrollOffset = null;
              });
              // 🎯 재생바 드래그 종료 시 Trimmer에 상태 전달
              widget.trimmer.setPlaybackBarDragging(false);
            },
            child: SizedBox(
              width: hitWidth,
              child: Center(
                child: Builder(
                  builder: (context) {
                    final colorScheme = Theme.of(context).colorScheme;
                    return Container(
                      width: barWidth,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(barWidth / 2),
                        // 보더 제거
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.30),
                            blurRadius: _isPlaybackBarDragging ? 8 : 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 드래그 가능한 오버레이 (핸들 드래그 로직 사용)
  Widget _buildDraggableOverlay({
    required bool isStart,
    required double pxPerSecond,
    required double scrollOffset,
    required double totalSeconds,
    required double maxTrimLength,
    required double selectionMinGap,
    bool showOverlay = true, // 🎯 오버레이 표시 여부 (경계선 드래그 영역은 false)
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        // 🎯 핸들 드래그 중이면 오버레이 드래그 무시
        if (_isHandleDragging) return;

        final box =
            _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = box.globalToLocal(details.globalPosition).dx;

        setState(() {
          _isOverlayDragging = true; // 오버레이 드래그 상태 설정
          // 재생 중이면 일시정지
          if (widget.trimmer.isPlaying) {
            widget.trimmer.videoPlaybackControl();
          }

          // ✅ 관성 스크롤이 남아있으면 즉시 멈춘다 (좌표계 점프 방지)
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.offset);
          }

          if (showOverlay) {
            // ✅ 검정 반투명 오버레이: 선택 구간 전체 이동(translation)
            _overlayDragStartLocalX = localX;
            _overlayDragStartScrollOffset =
                _scrollController.hasClients ? _scrollController.offset : 0.0;
            _overlayDragStartStartValue = widget.trimmer.startValue;
            _overlayDragStartEndValue = widget.trimmer.endValue;
          } else {
            // ✅ 경계선 드래그 영역(투명): 기존처럼 한쪽 핸들 조정, 다만 오프셋은 고정
            _dragStartScrollOffset =
                _scrollController.hasClients ? _scrollController.offset : 0.0;
            _dragStartValue =
                isStart ? widget.trimmer.startValue : widget.trimmer.endValue;
            _dragStartOppositeValue =
                isStart ? widget.trimmer.endValue : widget.trimmer.startValue;
            _dragStartTimelineX = localX + _dragStartScrollOffset!;
          }
        });
        widget.trimmer.setHandleDragging(true);
      },
      onPanUpdate: (details) {
        if (!_isOverlayDragging) return;

        final box =
            _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = box.globalToLocal(details.globalPosition).dx;

        // ✅ 검정 반투명 오버레이: 선택 구간 전체 이동(translation) + 핸들 화면 위치 고정
        if (showOverlay) {
          if (_overlayDragStartLocalX == null ||
              _overlayDragStartScrollOffset == null ||
              _overlayDragStartStartValue == null ||
              _overlayDragStartEndValue == null) {
            return;
          }
          if (!_scrollController.hasClients) return;
          if (pxPerSecond <= 0 || pxPerSecond.isNaN || pxPerSecond.isInfinite) {
            return;
          }
          if (totalSeconds <= 0) return;

          final start0 = _overlayDragStartStartValue!;
          final end0 = _overlayDragStartEndValue!;
          final offset0 = _overlayDragStartScrollOffset!;

          final dxScreen = localX - _overlayDragStartLocalX!;
          final sensitivity = _overlayScrollSensitivity;
          final desiredDeltaScroll =
              -dxScreen * sensitivity; // drag-right => scrollOffset 감소 방향

          final maxExtent = _scrollController.position.maxScrollExtent;

          // ✅ (스크롤 한계) + (시간 한계) 동시 만족 클램프
          final minDeltaScrollFromScroll = -offset0;
          final maxDeltaScrollFromScroll = maxExtent - offset0;
          final minDeltaScrollFromTime = -(start0 * pxPerSecond);
          final maxDeltaScrollFromTime = ((totalSeconds - end0) * pxPerSecond);

          final minDeltaScroll = math.max(
            minDeltaScrollFromScroll,
            minDeltaScrollFromTime,
          );
          final maxDeltaScroll = math.min(
            maxDeltaScrollFromScroll,
            maxDeltaScrollFromTime,
          );

          final clampedDeltaScroll = desiredDeltaScroll.clamp(
            minDeltaScroll,
            maxDeltaScroll,
          );

          final newOffset = offset0 + clampedDeltaScroll;
          final deltaSeconds = clampedDeltaScroll / pxPerSecond;
          final newStart = start0 + deltaSeconds;
          final newEnd = end0 + deltaSeconds;

          _scrollController.jumpTo(newOffset);
          widget.trimmer.onChangeStart(newStart);
          widget.trimmer.onChangeEnd(newEnd);
          widget.onChangeStart?.call(newStart);
          widget.onChangeEnd?.call(newEnd);
          return;
        }

        // ✅ 경계선 드래그 영역(투명): 한쪽 핸들 조정 + 좌표계 고정
        if (_dragStartValue == null ||
            _dragStartTimelineX == null ||
            _dragStartOppositeValue == null ||
            _dragStartScrollOffset == null) {
          return;
        }

        final timelineX = localX + _dragStartScrollOffset!;

        // 🎯 핸들 드래그와 동일한 계산 로직 (더 안전한 검증 추가)
        final dx = timelineX - _dragStartTimelineX!;

        // 🎯 pxPerSecond가 0이거나 유효하지 않으면 무시
        if (pxPerSecond <= 0 || pxPerSecond.isNaN || pxPerSecond.isInfinite) {
          return;
        }

        // ✅ 길이에 따른 감도 조절 제거: 고정 감도
        final adjustedDx = dx * 0.9 * _edgeDragSensitivity;
        final deltaSeconds = adjustedDx / pxPerSecond;
        final minLength = widget.trimmer.minLength;

        // 🎯 deltaSeconds가 너무 크면 무시 (비정상적인 값 방지)
        if (deltaSeconds.abs() > totalSeconds * 2) {
          return;
        }

        // 🎯 deltaSeconds가 너무 작으면 무시 (미세한 움직임 무시)
        if (deltaSeconds.abs() < 0.01) {
          return;
        }

        // 🎯 현재 반대쪽 핸들의 실제 값을 사용 (드래그 시작 시점의 고정 값이 아닌)
        // 오버레이 드래그 시 반대쪽 핸들이 실제로 변경되었을 수 있으므로 현재 값을 사용
        final currentOppositeValue =
            isStart ? widget.trimmer.endValue : widget.trimmer.startValue;

        if (isStart) {
          var newStart = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 현재 반대쪽 핸들 값과 비교
          if (newStart >= currentOppositeValue) return;

          // 🎯 유효성 검증 먼저 수행
          if (newStart.isNaN || newStart.isInfinite) return;

          newStart = newStart.clamp(
            0.0,
            (currentOppositeValue - minLength).clamp(0.0, totalSeconds),
          );

          if (newStart < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newStart >= currentOppositeValue) return;

          final proposedLength = currentOppositeValue - newStart;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;

          // 🎯 최종 클램프 및 검증
          newStart = newStart.clamp(0.0, totalSeconds);
          if (newStart.isNaN || newStart.isInfinite) return;

          widget.trimmer.onChangeStart(newStart);
          widget.onChangeStart?.call(newStart);
          setState(() {});
        } else {
          var newEnd = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 현재 반대쪽 핸들 값과 비교
          if (newEnd <= currentOppositeValue) return;

          // 🎯 유효성 검증 먼저 수행
          if (newEnd.isNaN || newEnd.isInfinite) return;

          newEnd = newEnd.clamp(
            (currentOppositeValue + minLength).clamp(0.0, totalSeconds),
            totalSeconds,
          );

          if (newEnd < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newEnd <= currentOppositeValue) return;

          final proposedLength = newEnd - currentOppositeValue;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;

          // 🎯 최종 클램프 및 검증
          newEnd = newEnd.clamp(0.0, totalSeconds);
          if (newEnd.isNaN || newEnd.isInfinite) return;

          widget.trimmer.onChangeEnd(newEnd);
          widget.onChangeEnd?.call(newEnd);
          setState(() {});
        }
      },
      onPanEnd: (_) {
        setState(() {
          _isOverlayDragging = false;
          _dragStartValue = null;
          _dragStartOppositeValue = null;
          _dragStartTimelineX = null;
          _dragStartScrollOffset = null;

          _overlayDragStartLocalX = null;
          _overlayDragStartScrollOffset = null;
          _overlayDragStartStartValue = null;
          _overlayDragStartEndValue = null;
        });
        widget.trimmer.setHandleDragging(false);

        // 🎯 핸들 드래그 종료 시 비디오 위치를 범위 내로 조정
        final currentPos = widget.trimmer.currentPosition;
        final startValue = widget.trimmer.startValue;
        final endValue = widget.trimmer.endValue;

        // 현재 위치가 범위를 벗어나면 조정
        if (currentPos < startValue) {
          widget.trimmer.seekTo(startValue);
        } else if (currentPos > endValue) {
          widget.trimmer.seekTo(endValue);
        } else {
          // 범위 내에 있으면 현재 위치 유지 (핸들 위치에 맞게)
          widget.trimmer.seekTo(currentPos);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color:
              showOverlay
                  ? Colors.black.withOpacity(0.5)
                  : Colors.transparent, // 🎯 경계선 드래그 영역은 투명
          borderRadius: BorderRadius.only(
            topLeft: isStart ? const Radius.circular(6) : Radius.zero,
            bottomLeft: isStart ? const Radius.circular(6) : Radius.zero,
            topRight: isStart ? Radius.zero : const Radius.circular(6),
            bottomRight: isStart ? Radius.zero : const Radius.circular(6),
          ),
        ),
      ),
    );
  }

  /// 경계선 핸들 UI
  Widget _buildHandle({
    required bool isStart,
    required double pxPerSecond,
    required double scrollOffset,
    required double totalSeconds,
    required double totalWidth,
    required double maxTrimLength,
    required double selectionMinGap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        // 🎯 오버레이 드래그 중이면 핸들 드래그 무시
        if (_isOverlayDragging) return;

        final box =
            _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = box.globalToLocal(details.globalPosition).dx;

        setState(() {
          _isHandleDragging = true;
          // ✅ 관성 스크롤이 남아있으면 즉시 멈추고, 드래그 동안 오프셋을 고정
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.offset);
          }
          _dragStartScrollOffset =
              _scrollController.hasClients ? _scrollController.offset : 0.0;
          _dragStartValue =
              isStart ? widget.trimmer.startValue : widget.trimmer.endValue;
          // 🎯 반대쪽 핸들 값 저장 (역전 방지용)
          _dragStartOppositeValue =
              isStart ? widget.trimmer.endValue : widget.trimmer.startValue;
          _dragStartTimelineX = localX + _dragStartScrollOffset!;
        });
        widget.trimmer.setHandleDragging(true);
      },
      onPanUpdate: (details) {
        if (_dragStartValue == null ||
            _dragStartTimelineX == null ||
            _dragStartOppositeValue == null ||
            _dragStartScrollOffset == null)
          return;

        final box =
            _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = box.globalToLocal(details.globalPosition).dx;
        // ✅ 드래그 시작 시점의 스크롤 오프셋을 사용 (좌표계 고정)
        final timelineX = localX + _dragStartScrollOffset!;

        // 🎯 pxPerSecond 유효성 검증
        if (pxPerSecond <= 0 || pxPerSecond.isNaN || pxPerSecond.isInfinite) {
          return;
        }

        final dx = timelineX - _dragStartTimelineX!;
        // ✅ 길이에 따른 감도 조절 제거: 고정 감도
        final deltaSeconds = (dx * _edgeDragSensitivity) / pxPerSecond;
        final minLength = widget.trimmer.minLength;

        // 🎯 deltaSeconds가 너무 크면 무시 (비정상적인 값 방지)
        if (deltaSeconds.abs() > totalSeconds * 2) {
          return;
        }

        if (isStart) {
          var newStart = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 드래그 시작 시 저장된 반대쪽 값과 비교
          if (newStart >= _dragStartOppositeValue!) return;

          // 🎯 유효성 검증 먼저 수행
          if (newStart.isNaN || newStart.isInfinite) return;

          newStart = newStart.clamp(
            0.0,
            (_dragStartOppositeValue! - minLength).clamp(0.0, totalSeconds),
          );

          if (newStart < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newStart >= _dragStartOppositeValue!) return;

          final proposedLength = _dragStartOppositeValue! - newStart;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;

          // 🎯 최종 클램프 및 검증
          newStart = newStart.clamp(0.0, totalSeconds);
          if (newStart.isNaN || newStart.isInfinite) return;

          widget.trimmer.onChangeStart(newStart);
          widget.onChangeStart?.call(newStart);
          setState(() {});
        } else {
          var newEnd = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 드래그 시작 시 저장된 반대쪽 값과 비교
          if (newEnd <= _dragStartOppositeValue!) return;

          // 🎯 유효성 검증 먼저 수행
          if (newEnd.isNaN || newEnd.isInfinite) return;

          newEnd = newEnd.clamp(
            (_dragStartOppositeValue! + minLength).clamp(0.0, totalSeconds),
            totalSeconds,
          );

          if (newEnd < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newEnd <= _dragStartOppositeValue!) return;

          final proposedLength = newEnd - _dragStartOppositeValue!;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;

          // 🎯 최종 클램프 및 검증
          newEnd = newEnd.clamp(0.0, totalSeconds);
          if (newEnd.isNaN || newEnd.isInfinite) return;

          widget.trimmer.onChangeEnd(newEnd);
          widget.onChangeEnd?.call(newEnd);
          setState(() {});
        }
      },
      onPanEnd: (_) {
        setState(() {
          _isHandleDragging = false;
          _dragStartValue = null;
          _dragStartOppositeValue = null;
          _dragStartTimelineX = null;
          _dragStartScrollOffset = null;
        });
        widget.trimmer.setHandleDragging(false);

        // 🎯 핸들 드래그 종료 시 비디오 위치를 범위 내로 조정
        final currentPos = widget.trimmer.currentPosition;
        final startValue = widget.trimmer.startValue;
        final endValue = widget.trimmer.endValue;

        // 현재 위치가 범위를 벗어나면 조정
        if (currentPos < startValue) {
          widget.trimmer.seekTo(startValue);
        } else if (currentPos > endValue) {
          widget.trimmer.seekTo(endValue);
        } else {
          // 범위 내에 있으면 현재 위치 유지 (핸들 위치에 맞게)
          widget.trimmer.seekTo(currentPos);
        }
      },
      child: Builder(
        builder: (context) {
          // 🎯 핸들 감지 영역은 투명하게 (보라색 제거)
          return CustomPaint(
            painter: _HandlePainter(
              color: Colors.transparent,
              isDragging: _isHandleDragging,
            ),
            size: const Size(8, double.infinity),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      child: Column(
        children: [
          // 타임라인
          Stack(
            children: [
              Container(
                height: 120,
                color: colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: _buildTimeline(),
              ),
              // ✅ 재생 중이 아닐 때 effectiveRelative를 타임라인 위에 표시
              ValueListenableBuilder<double>(
                valueListenable: widget.trimmer.currentPositionNotifier,
                builder: (context, currentPos, _) {
                  if (widget.trimmer.isPlaying) {
                    return const SizedBox.shrink();
                  }

                  final start = widget.trimmer.startValue;
                  final end = widget.trimmer.endValue;
                  final rawTrimLength = (end - start).clamp(0.0, 86400.0);
                  final rawRelative = (currentPos - start).clamp(
                    0.0,
                    rawTrimLength,
                  );

                  final speed = widget.trimmer.playbackSpeed;
                  final effectiveRelative =
                      speed > 0 ? (rawRelative / speed) : rawRelative;

                  return Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        _formatDurationMMSS(effectiveRelative),
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          // 시간 표시
          Container(
            color: colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            // ✅ 가운데 "전체 길이" 텍스트가 좌/우 텍스트 폭 변화로 요동치는 문제 방지:
            // Stack으로 left/center/right를 고정 배치한다.
            child: SizedBox(
              height: 20,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatDurationMMSS(widget.trimmer.startValue),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.trimmer.currentPositionNotifier,
                      builder: (context, currentPos, _) {
                        final start = widget.trimmer.startValue;
                        final end = widget.trimmer.endValue;
                        final rawTrimLength = (end - start).clamp(0.0, 86400.0);

                        // ✅ 재생 중일 때만 effectiveRelative 표시, 아니면 잘린 시간 표시
                        if (widget.trimmer.isPlaying) {
                          final rawRelative = (currentPos - start).clamp(
                            0.0,
                            rawTrimLength,
                          );

                          final speed = widget.trimmer.playbackSpeed;
                          final effectiveRelative =
                              speed > 0 ? (rawRelative / speed) : rawRelative;

                          return Text(
                            _formatDurationMMSS(effectiveRelative),
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        } else {
                          // 재생 중이 아닐 때: 잘린 시간 표시
                          return Text(
                            _formatDurationMMSS(rawTrimLength),
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatDurationMMSS(widget.trimmer.endValue),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
}

/// 영상 트리밍 화면 - video_trimmer 패키지 구조와 동일
class VideoTrimScreen extends StatefulWidget {
  final File videoFile;
  final Duration videoDuration;
  final VideoEditSpec? editSpec;
  final bool fromEditor;

  const VideoTrimScreen({
    super.key,
    required this.videoFile,
    required this.videoDuration,
    this.editSpec,
    this.fromEditor = false,
  });

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  late final Trimmer _trimmer;
  bool _isTrimming = false;

  @override
  void initState() {
    super.initState();
    _trimmer = Trimmer();
    _initializeTrimmer();
  }

  Future<void> _initializeTrimmer() async {
    try {
      // ✅ 편집(에디터)에서 넘어온 속도 스펙을 "길이 제한/표시"에도 적용
      // - 최종 결과물 60초 기준으로 제한하기 위해, 원본 선택 가능한 최대 길이를 speed에 맞게 스케일한다.
      final initialSpeed = widget.editSpec?.playbackSpeed;
      if (initialSpeed != null) {
        _trimmer.setPlaybackSpeed(initialSpeed);
      }

      await _trimmer.loadVideo(
        videoFile: widget.videoFile,
        videoDuration: widget.videoDuration,
      );

      // ✅ 편집에서 넘어온 경우: 트리머에서도 동일한 재생 속도 적용(미리보기용)
      final controller = _trimmer.videoPlayerController;
      final speed = widget.editSpec?.playbackSpeed;
      if (controller != null &&
          controller.value.isInitialized &&
          speed != null) {
        // ignore: discarded_futures
        controller.setPlaybackSpeed(speed.clamp(0.5, 2.0));
      }

      // 썸네일 로드
      _trimmer.loadThumbnails();
    } catch (e) {
      debugPrint('[VideoTrimScreen] 초기화 오류: $e');
      if (!mounted) return;

      await DialogUtils.showInfoDialog(
        context,
        title: AppLocalizations.of(context).t('error'),
        message: '영상을 불러올 수 없습니다.',
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _trimVideo() async {
    if (_isTrimming) return;

    setState(() {
      _isTrimming = true;
    });

    try {
      final trimSpec = _trimmer.buildTrimSpec();

      // ✅ pop 전에 썸네일을 확정한다 (트림+편집(transform) 반영)
      // - 트림 화면에서 잠깐 로딩(20x20 스피너) 후, 노드에 썸네일이 들어간 상태로 pop되도록
      String? thumbnailPath;
      try {
        final thumb = await VideoUploadUtils.generateThumbnail(
          widget.videoFile.path,
          // FFmpeg 경로를 타도록 스펙 전달
          trimSpec: trimSpec,
          editSpec: widget.editSpec,
          quality: 60,
        );
        thumbnailPath = thumb?.path;
      } catch (e) {
        debugPrint('[VideoTrimScreen] 썸네일 생성 실패(계속 진행): $e');
      }

      final result = VideoTrimResult(
        trim: trimSpec,
        thumbnailPath: thumbnailPath,
      );
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      debugPrint('[VideoTrimScreen] 트림 결과 생성 오류: $e');
      if (!mounted) return;
      await DialogUtils.showInfoDialog(
        context,
        title: AppLocalizations.of(context).t('error'),
        message: AppLocalizations.of(context).t('video_trim_failed'),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isTrimming = false;
      });
    }
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CupertinoPageScaffold(
      backgroundColor: colorScheme.surface,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.onSurface.withOpacity(0.1),
            width: 0.5,
          ),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            // 🎯 편집 화면에서 온 경우: null을 반환하여 편집 화면으로 돌아가도록 함
            if (widget.fromEditor) {
              Navigator.of(context).pop(null);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Text(
            widget.fromEditor ? '뒤로' : AppLocalizations.of(context).t('cancel'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),

        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isTrimming ? null : _trimVideo,
          child:
              _isTrimming
                  ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.onSurface,
                      ),
                    ),
                  )
                  : Text(
                    AppLocalizations.of(context).t('add'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
        ),
      ),
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: VideoViewer(
                    trimmer: _trimmer,
                    editSpec: widget.editSpec,
                  ),
                ),
                TrimEditor(
                  trimmer: _trimmer,
                  onChangeStart: (value) {
                    // 콜백 처리
                  },
                  onChangeEnd: (value) {
                    // 콜백 처리
                  },
                  onChangePlaybackState: (value) {
                    // 콜백 처리
                  },
                ),
              ],
            ),
          ),
          // ✅ 비디오 히스토리 UI 준비 중 로딩 오버레이
          ListenableBuilder(
            listenable: _trimmer,
            builder: (context, _) {
              if (_trimmer.isLoadingThumbnails) {
                return Positioned.fill(
                  child: Container(
                    color: colorScheme.surface.withOpacity(0.95),
                    child: const DoppyLoadingLogo(),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
