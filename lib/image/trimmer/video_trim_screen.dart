import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:doppy/image/video_trim_spec.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 비디오 트림 결과 (비파괴: 실제 ffmpeg 트림을 하지 않고 구간만 반환)
class VideoTrimResult {
  final VideoTrimSpec trim;
  VideoTrimResult({required this.trim});
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

  // 🎯 도메인 규칙 접근
  double get minLength => TrimRangeConfig.minLength;
  double get maxTrimLength => TrimRangeConfig.maxTrimLength;
  double get selectionMinGap => TrimRangeConfig.selectionMinGap;

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
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
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
        // 재생바 중심이 endValue에 거의 도달하면 정지 (0.02초 여유로 더 정밀하게)
        final stopThreshold = _endValue - 0.02;

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
        } else if (position < _startValue) {
          // 시작 이전: 시작으로 이동
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
      if (currentPos >= _endValue - 0.01 || currentPos < _startValue) {
        // 시작 지점으로 이동 (비동기 완료 대기)
        await seekTo(_startValue);
        // seekTo 완료 후 재생 시작
        await _videoPlayerController!.play();
        _isPlaying = true;
      } else {
        // 🎯 재생 시작 시 즉시 현재 위치를 업데이트 (재생바가 즉시 움직이도록)
        final videoPos =
            _videoPlayerController!.value.position.inMilliseconds / 1000.0;
        _currentPositionNotifier.value = videoPos.clamp(_startValue, _endValue);
        // 범위 내에 있으면 바로 재생
        await _videoPlayerController!.play();
        _isPlaying = true;
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

  const VideoViewer({super.key, required this.trimmer});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: trimmer,
      builder: (context, _) {
        if (!trimmer.isInitialized || trimmer.videoPlayerController == null) {
          return const Center(child: CupertinoActivityIndicator());
        }

        return Stack(
          children: [
            // 영상을 cover로 표시
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  debugPrint('[VideoViewer] 재생 버튼 탭 감지!');
                  trimmer.videoPlaybackControl();
                },
                behavior: HitTestBehavior.opaque,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: trimmer.videoPlayerController!.value.size.width,
                    height: trimmer.videoPlayerController!.value.size.height,
                    child: VideoPlayer(trimmer.videoPlayerController!),
                  ),
                ),
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

  // 🎯 재생바 드래그 시작 기준값 (정밀 시크용)
  double? _playbackBarDragStartTimelineX; // timeline absolute px
  double? _playbackBarDragStartPosition; // seconds

  // 🎯 오버레이 드래그 시작 기준값 (타임라인 스크롤용)
  double? _overlayDragStartTimelineX; // timeline absolute px
  double? _overlayDragStartScrollOffset; // 스크롤 오프셋 (핸들 위치 고정용)
  double? _overlayDragStartStartValue; // 시작 핸들 값 (핸들 위치 고정용)
  double? _overlayDragStartEndValue; // 끝 핸들 값 (핸들 위치 고정용)
  double? _overlayDragStartCurrentPosition; // 재생바 위치 (재생바 위치 고정용)

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
        const handleWidth = 14.0;

        return ClipRect(
          child: Stack(
            key: _timelineKey,
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
                  child: SizedBox(
                    width: thumbnailStripWidth,
                    child: Row(
                      children:
                          widget.trimmer.thumbnails.isEmpty
                              ? [
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final colorScheme =
                                          Theme.of(context).colorScheme;
                                      return Container(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                      );
                                    },
                                  ),
                                ),
                              ]
                              : widget.trimmer.thumbnails
                                  .map(
                                    (thumb) => SizedBox(
                                      // 🎯 각 프레임 최소 너비 설정 (더 길게)
                                      width:
                                          thumbnailStripWidth /
                                          widget.trimmer.thumbnails.length,
                                      child:
                                          thumb != null
                                              ? Image.memory(
                                                thumb,
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
                                  )
                                  .toList(),
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

              // 🎯 왼쪽 경계선 핸들 (핸들 중심 기준)
              Positioned(
                left: (startBoundaryX - handleWidth / 2).clamp(
                  0.0,
                  totalWidth - handleWidth,
                ),
                top: 0,
                bottom: 0,
                width: handleWidth,
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: 120, // 타임라인 높이
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
              ),

              // 🎯 오른쪽 경계선 핸들 (핸들 중심 기준)
              Positioned(
                left: (endBoundaryX - handleWidth / 2).clamp(
                  0.0,
                  totalWidth - handleWidth,
                ),
                top: 0,
                bottom: 0,
                width: handleWidth,
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: 120, // 타임라인 높이
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
                        valueListenable: widget.trimmer.currentPositionNotifier,
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

    // 🎯 핸들 폭을 제외한 "두 핸들 사이" 구간에서만 이동 (오버런 방지)
    // startX/endX는 경계선(=트림 시작/끝 시간의 픽셀 위치)임
    const handleWidth = 14.0; // 핸들 두께
    // 🎯 재생바와 핸들 사이 최소 거리 줄임 (핸들 폭의 절반만 여유)
    const minGapFromHandle = handleWidth / 2;
    final innerStartX = startX + minGapFromHandle;
    final innerEndX = endX - minGapFromHandle;
    if (innerEndX <= innerStartX) {
      return const SizedBox.shrink();
    }

    // 🎯 재생바 두께/터치 영역 (항상 활성화)
    final barWidth = _isPlaybackBarDragging ? 10.0 : 8.0;
    final hitWidth = barWidth + 28.0;

    // 🎯 ValueListenableBuilder로 currentPosition 실시간 업데이트
    return ValueListenableBuilder<double>(
      valueListenable: widget.trimmer.currentPositionNotifier,
      builder: (context, currentPos, _) {
        // 🎯 현재 위치를 범위 내로 클램프
        final clampedCurrentPos = currentPos.clamp(startValue, endValue);

        // 🎯 시간 → 픽셀(화면 좌표) : pxPerSecond 단일 진실로 정밀 매핑
        final rawCenterX =
            startX + ((clampedCurrentPos - startValue) * pxPerSecond);

        // 🎯 "핸들 사이" 내부에서만 이동 (바 두께 고려, 최소 거리 줄임)
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

              final localX = box.globalToLocal(details.globalPosition).dx;
              final currentScrollOffset =
                  _scrollController.hasClients ? _scrollController.offset : 0.0;
              final timelineX = localX + currentScrollOffset;

              setState(() {
                _isPlaybackBarDragging = true;
                _playbackBarDragStartTimelineX = timelineX;
                _playbackBarDragStartPosition = currentPos;
              });
              // 🎯 재생바 드래그 시작 시 Trimmer에 상태 전달 (타이머 보정 충돌 방지)
              widget.trimmer.setPlaybackBarDragging(true);
            },
            onPanUpdate: (details) {
              if (!_isPlaybackBarDragging ||
                  _playbackBarDragStartTimelineX == null ||
                  _playbackBarDragStartPosition == null) {
                return;
              }

              final box =
                  _timelineKey.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;

              final localX = box.globalToLocal(details.globalPosition).dx;
              final currentScrollOffset =
                  _scrollController.hasClients ? _scrollController.offset : 0.0;
              final timelineX = localX + currentScrollOffset;

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
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(barWidth / 2),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.35),
                          width: 1,
                        ),
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

  /// 드래그 가능한 오버레이 (타임라인 스크롤, 구간 조절은 핸들에서만)
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
          // 🎯 오버레이 드래그는 타임라인 스크롤
          _isOverlayDragging = true; // 오버레이 드래그 상태 설정
          // 재생 중이면 일시정지
          if (widget.trimmer.isPlaying) {
            widget.trimmer.videoPlaybackControl();
          }
          _overlayDragStartTimelineX = localX;
          // 🎯 드래그 시작 시점의 스크롤 오프셋, 핸들 값, 재생바 위치 저장
          _overlayDragStartScrollOffset =
              _scrollController.hasClients ? _scrollController.offset : 0.0;
          _overlayDragStartStartValue = widget.trimmer.startValue;
          _overlayDragStartEndValue = widget.trimmer.endValue;
          _overlayDragStartCurrentPosition = widget.trimmer.currentPosition;
        });
      },
      onPanUpdate: (details) {
        if (!_isOverlayDragging ||
            _overlayDragStartTimelineX == null ||
            _overlayDragStartScrollOffset == null ||
            _overlayDragStartStartValue == null ||
            _overlayDragStartEndValue == null ||
            _overlayDragStartCurrentPosition == null)
          return;

        if (!_scrollController.hasClients) return;

        final box =
            _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = box.globalToLocal(details.globalPosition).dx;

        // 🎯 픽셀 변화 계산 (로컬 좌표 기준)
        final dx = localX - _overlayDragStartTimelineX!;

        // 🎯 스크롤 감도 약간 낮추기 (0.85배)
        final adjustedDx = dx * 0.85;

        // 🎯 현재 스크롤 위치에서 반대 방향으로 스크롤 (드래그 방향과 반대로)
        final currentOffset = _scrollController.offset;
        final newOffset = (currentOffset - adjustedDx).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );

        // 🎯 스크롤 오프셋 변화량 계산
        final deltaScrollOffset = newOffset - _overlayDragStartScrollOffset!;

        // 🎯 스크롤 변화량을 시간으로 변환
        final deltaSeconds = deltaScrollOffset / pxPerSecond;

        // 🎯 핸들 값들을 스크롤 변화량만큼 업데이트 (화면상 위치 고정)
        final newStartValue = (_overlayDragStartStartValue! + deltaSeconds)
            .clamp(0.0, totalSeconds);
        final newEndValue = (_overlayDragStartEndValue! + deltaSeconds).clamp(
          0.0,
          totalSeconds,
        );

        // 🎯 재생바 위치도 스크롤 변화량만큼 업데이트 (화면상 위치 고정)
        final newCurrentPosition = (_overlayDragStartCurrentPosition! +
                deltaSeconds)
            .clamp(0.0, totalSeconds);

        // 🎯 핸들 값 업데이트 (역전 방지)
        if (newStartValue < newEndValue) {
          widget.trimmer.onChangeStart(newStartValue);
          widget.trimmer.onChangeEnd(newEndValue);
          widget.onChangeStart?.call(newStartValue);
          widget.onChangeEnd?.call(newEndValue);
        }

        // 🎯 재생바 위치 업데이트 (범위 내로 클램프)
        final clampedCurrentPos = newCurrentPosition.clamp(
          newStartValue,
          newEndValue,
        );
        widget.trimmer.seekTo(clampedCurrentPos, clampToRange: true);

        // 🎯 타임라인 스크롤 (부드럽게 즉시 이동)
        _scrollController.jumpTo(newOffset);

        setState(() {}); // UI 업데이트
      },
      onPanEnd: (_) {
        setState(() {
          _isOverlayDragging = false;
          _overlayDragStartTimelineX = null;
          _overlayDragStartScrollOffset = null;
          _overlayDragStartStartValue = null;
          _overlayDragStartEndValue = null;
          _overlayDragStartCurrentPosition = null;
        });
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
          _dragStartValue =
              isStart ? widget.trimmer.startValue : widget.trimmer.endValue;
          // 🎯 반대쪽 핸들 값 저장 (역전 방지용)
          _dragStartOppositeValue =
              isStart ? widget.trimmer.endValue : widget.trimmer.startValue;
          _dragStartTimelineX = localX + scrollOffset;
        });
        widget.trimmer.setHandleDragging(true);
      },
      onPanUpdate: (details) {
        if (_dragStartValue == null ||
            _dragStartTimelineX == null ||
            _dragStartOppositeValue == null)
          return;

        final box =
            _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = box.globalToLocal(details.globalPosition).dx;
        final currentScrollOffset =
            _scrollController.hasClients ? _scrollController.offset : 0.0;
        final timelineX = localX + currentScrollOffset;

        final dx = timelineX - _dragStartTimelineX!;
        final deltaSeconds = dx / pxPerSecond;
        final minLength = widget.trimmer.minLength;

        if (isStart) {
          var newStart = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 드래그 시작 시 저장된 반대쪽 값과 비교
          if (newStart >= _dragStartOppositeValue!) return;

          newStart = newStart.clamp(
            0.0,
            (_dragStartOppositeValue! - minLength).clamp(0.0, totalSeconds),
          );

          if (newStart.isNaN || newStart.isInfinite || newStart < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newStart >= _dragStartOppositeValue!) return;

          final proposedLength = _dragStartOppositeValue! - newStart;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;
          newStart = newStart.clamp(0.0, totalSeconds);

          widget.trimmer.onChangeStart(newStart);
          widget.onChangeStart?.call(newStart);
          setState(() {});
        } else {
          var newEnd = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 드래그 시작 시 저장된 반대쪽 값과 비교
          if (newEnd <= _dragStartOppositeValue!) return;

          newEnd = newEnd.clamp(
            (_dragStartOppositeValue! + minLength).clamp(0.0, totalSeconds),
            totalSeconds,
          );

          if (newEnd.isNaN || newEnd.isInfinite || newEnd < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newEnd <= _dragStartOppositeValue!) return;

          final proposedLength = newEnd - _dragStartOppositeValue!;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;
          newEnd = newEnd.clamp(0.0, totalSeconds);

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
          final colorScheme = Theme.of(context).colorScheme;
          return Container(
            width: 14, // 핸들 두께
            // 🎯 vertical margin 제거 (ClipRect 영향 제거)
            decoration: BoxDecoration(
              color: colorScheme.onSurface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.4),
                  blurRadius: _isHandleDragging ? 8 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
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
          ClipRect(
            child: Container(
              height: 120,
              color: colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _buildTimeline(),
            ),
          ),
          // 시간 표시
          Container(
            color: colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDurationMMSS(widget.trimmer.startValue),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // 🎯 중간에 총 시간 표시 (두껍게)
                Text(
                  _formatDurationMMSS(
                    widget.trimmer.endValue - widget.trimmer.startValue,
                  ),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700, // 🎯 두껍게
                  ),
                ),
                Text(
                  _formatDurationMMSS(widget.trimmer.endValue),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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

  const VideoTrimScreen({
    super.key,
    required this.videoFile,
    required this.videoDuration,
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
      await _trimmer.loadVideo(
        videoFile: widget.videoFile,
        videoDuration: widget.videoDuration,
      );

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
      final result = VideoTrimResult(trim: _trimmer.buildTrimSpec());
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
        message: '영상 자르기에 실패했습니다. 다시 시도해주세요.',
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            AppLocalizations.of(context).t('cancel'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
        middle: Text(
          AppLocalizations.of(context).t('video_trim'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isTrimming ? null : _trimVideo,
          child:
              _isTrimming
                  ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.onSurface.withOpacity(0.7),
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
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: VideoViewer(trimmer: _trimmer)),
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
    );
  }
}
