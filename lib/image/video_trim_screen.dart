import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 비디오 트림 결과
class TrimmedVideoResult {
  final File videoFile;
  final String? thumbnailPath;

  TrimmedVideoResult({required this.videoFile, this.thumbnailPath});
}

/// Trimmer 클래스 - video_trimmer 패키지 구조와 동일
/// 비디오 상태를 관리하는 ChangeNotifier
class Trimmer extends ChangeNotifier {
  VideoPlayerController? _videoPlayerController;
  File? _videoFile;
  Duration? _videoDuration;

  double _startValue = 0.0;
  double _endValue = 60.0;
  double _currentPosition = 0.0;
  bool _isPlaying = false;
  bool _isInitialized = false;

  // 썸네일
  List<Uint8List?> _thumbnails = [];
  bool _isLoadingThumbnails = false;

  Timer? _playbackTimer;

  // 🎯 핸들 드래그 상태 (타이머 보정 충돌 방지용)
  bool _isHandleDragging = false;

  VideoPlayerController? get videoPlayerController => _videoPlayerController;
  File? get videoFile => _videoFile;
  Duration? get videoDuration => _videoDuration;
  double get startValue => _startValue;
  double get endValue => _endValue;
  double get currentPosition => _currentPosition;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;
  List<Uint8List?> get thumbnails => _thumbnails;
  bool get isLoadingThumbnails => _isLoadingThumbnails;

  /// 비디오 로드
  Future<void> loadVideo({
    required File videoFile,
    required Duration videoDuration,
  }) async {
    _videoFile = videoFile;
    _videoDuration = videoDuration;

    final maxSeconds = videoDuration.inSeconds.toDouble();
    _startValue = 0.0;
    _endValue = maxSeconds < 60.0 ? maxSeconds : 60.0;
    _currentPosition = _startValue;

    try {
      _videoPlayerController = VideoPlayerController.file(videoFile);
      await _videoPlayerController!.initialize();

      _isInitialized = true;
      _videoPlayerController!.seekTo(
        Duration(milliseconds: (_startValue * 1000).toInt()),
      );
      _videoPlayerController!.addListener(_onPlaybackUpdate);

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

      // 🎯 핸들 드래그 중에는 타이머 보정 개입 금지 (타이밍 충돌 방지)
      if (_isHandleDragging) {
        return;
      }

      final position =
          _videoPlayerController!.value.position.inMilliseconds / 1000.0;
      final isPlaying = _videoPlayerController!.value.isPlaying;

      bool needsUpdate = false;

      // 🎯 재생 범위 체크 (재생 중일 때만)
      if (isPlaying) {
        if (position >= _endValue) {
          // 끝 도달: 일시정지하고 시작으로 이동
          _videoPlayerController!.pause();
          final startMs =
              ((_startValue.clamp(0.0, double.infinity)) * 1000).toInt();
          if (startMs < 0) return; // 음수 방지
          _videoPlayerController!.seekTo(Duration(milliseconds: startMs));
          _isPlaying = false;
          _currentPosition = _startValue.clamp(0.0, double.infinity);
          needsUpdate = true;
        } else if (position < _startValue) {
          // 시작 이전: 시작으로 이동
          final startMs =
              ((_startValue.clamp(0.0, double.infinity)) * 1000).toInt();
          if (startMs < 0) return; // 음수 방지
          _videoPlayerController!.seekTo(Duration(milliseconds: startMs));
          _currentPosition = _startValue.clamp(0.0, double.infinity);
          needsUpdate = true;
        } else {
          // 정상 범위 내
          if (_currentPosition != position) {
            _currentPosition = position.clamp(0.0, double.infinity);
            needsUpdate = true;
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

  void _onPlaybackUpdate() {
    // 타이머에서 처리
  }

  /// 재생/일시정지 토글
  void videoPlaybackControl() {
    if (_videoPlayerController == null || !_isInitialized) {
      return;
    }

    if (_isPlaying) {
      _videoPlayerController!.pause();
      _isPlaying = false;
    } else {
      // 현재 위치가 범위를 벗어나면 시작 지점으로
      if (_currentPosition >= _endValue || _currentPosition < _startValue) {
        seekTo(_startValue);
      }
      _videoPlayerController!.play();
      _isPlaying = true;
    }
    notifyListeners();
  }

  /// 재생 위치 이동 (명시적 사용자 액션에서만 사용)
  void seekTo(double position) {
    if (_videoPlayerController == null || !_isInitialized) {
      return;
    }

    // 범위 내로 클램프 (음수 방지)
    final clampedPosition = position
        .clamp(
          _startValue.clamp(0.0, double.infinity),
          _endValue.clamp(0.0, double.infinity),
        )
        .clamp(0.0, double.infinity);

    // 🎯 Duration 생성 시 음수 방지
    final milliseconds = (clampedPosition * 1000).toInt();
    if (milliseconds < 0) return; // 음수 방지
    _videoPlayerController!.seekTo(Duration(milliseconds: milliseconds));
    _currentPosition = clampedPosition;
    notifyListeners();
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
    _currentPosition = _currentPosition.clamp(_startValue, _endValue);
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
    _currentPosition = _currentPosition.clamp(_startValue, _endValue);
    notifyListeners();
  }

  /// 핸들 드래그 상태 설정 (타이머 보정 충돌 방지용)
  void setHandleDragging(bool isDragging) {
    _isHandleDragging = isDragging;
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
  /// 🎯 압축은 하지 않고 트림만 수행 (copy 코덱)
  /// 압축은 플레이스홀더 상태에서 업로드 시 진행
  Future<TrimmedVideoResult> saveTrimmedVideo({
    required double startValue,
    required double endValue,
  }) async {
    if (_videoFile == null) {
      throw Exception('비디오 파일이 없습니다.');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/trimmed_$timestamp.mp4';

    final duration = endValue - startValue;

    // 🎯 비디오 트림만 수행 (압축 없음 - copy 코덱)
    // -c copy: 비디오/오디오 재인코딩 없이 복사 (매우 빠름, 무손실)
    // -avoid_negative_ts make_zero: 타임스탬프 보정
    // -movflags +faststart: 메타데이터를 파일 앞에 배치
    // 압축은 업로드 시 플레이스홀더 상태에서 진행됨
    final command =
        '-ss ${startValue.toStringAsFixed(2)} '
        '-i "${_videoFile!.path}" '
        '-t ${duration.toStringAsFixed(2)} '
        '-c copy '
        '-movflags +faststart '
        '-avoid_negative_ts make_zero '
        '-y '
        '"$outputPath"';

    debugPrint('[Trimmer] ffmpeg 명령 (트림만, 압축 없음): $command');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        // 🎯 썸네일 생성 (패키지 이용) - 첫 프레임
        String? thumbnailPath;
        try {
          // 🎯 VideoThumbnail 패키지로 썸네일 생성
          final bytes = await VideoThumbnail.thumbnailData(
            video: outputPath,
            imageFormat: ImageFormat.JPEG,
            timeMs: 0, // 첫 프레임
            quality: 100,
          );

          if (bytes != null) {
            // 🎯 메모리에서 파일로 저장
            final thumbnailFilePath = '${tempDir.path}/thumb_$timestamp.jpg';
            final thumbnailFile = File(thumbnailFilePath);
            await thumbnailFile.writeAsBytes(bytes);

            if (await thumbnailFile.exists()) {
              thumbnailPath = thumbnailFilePath;
              debugPrint(
                '[Trimmer] ✅ 썸네일 생성 완료: $thumbnailPath (${bytes.length} bytes)',
              );
            } else {
              debugPrint('[Trimmer] ⚠️ 썸네일 파일 쓰기 실패');
            }
          } else {
            debugPrint('[Trimmer] ⚠️ 썸네일 데이터 생성 실패 (bytes가 null)');
          }
        } catch (e) {
          debugPrint('[Trimmer] ⚠️ 썸네일 생성 실패 (계속 진행): $e');
        }

        debugPrint('[Trimmer] ✅ 트림 완료 (압축은 업로드 시 진행)');
        return TrimmedVideoResult(
          videoFile: outputFile,
          thumbnailPath: thumbnailPath,
        );
      } else {
        throw Exception('출력 파일이 생성되지 않았습니다.');
      }
    } else {
      final output = await session.getOutput();
      debugPrint('[Trimmer] ❌ ffmpeg 실패: $output');
      throw Exception('영상 자르기에 실패했습니다.');
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _videoPlayerController?.removeListener(_onPlaybackUpdate);
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
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

  // 🎯 드래그 시작 기준값 (누적 계산용)
  double? _dragStartValue;
  double? _dragStartTimelineX; // timeline absolute px (= localX + scrollOffset)
  double? _dragStartOppositeValue; // 🎯 반대쪽 핸들 값 (역전 방지용)

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
    final duration = Duration(seconds: seconds.toInt());
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${secs}s';
    }
  }

  String _formatDurationMMSS(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
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

        const maxTrimLength = 60.0;
        final selectionMinGap = 1.0;

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

        // 🎯 경계선 화면 좌표 (스크롤 오프셋만 한 번 적용)
        final startBoundaryX = startPixel - scrollOffset; // 왼쪽 경계선
        final endBoundaryX = endPixel - scrollOffset; // 오른쪽 경계선

        // 🎯 검정 오버레이 계산 (경계선 기준)
        final leftOverlayWidth = startBoundaryX.clamp(0.0, totalWidth);
        final rightOverlayStart = endBoundaryX.clamp(0.0, totalWidth);
        final rightOverlayWidth = totalWidth - rightOverlayStart;

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
                  // 🎯 핸들/재생바 드래그 중 스크롤 잠금: 좌표계 흔들림(점프/걸림) 방지
                  physics:
                      (_isHandleDragging || _isPlaybackBarDragging)
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

              // 🎯 왼쪽 경계선 핸들 (경계선 왼쪽 끝에 붙게)
              Positioned(
                left: startBoundaryX.clamp(
                  0.0,
                  totalWidth - 20,
                ), // 왼쪽에 붙게, 오버플로우 방지
                top: 0,
                bottom: 0,
                width: 20,
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

              // 🎯 오른쪽 경계선 핸들 (경계선 오른쪽 끝에 붙게)
              Positioned(
                left: (endBoundaryX - 20).clamp(
                  0.0,
                  totalWidth - 20,
                ), // 오른쪽 끝에 붙게, 오버플로우 방지
                top: 0,
                bottom: 0,
                width: 20,
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

              // 🎯 재생 시간 표시 (선택 구간 표시 박스 위에, 가운데 정렬)
              Positioned(
                top: -60,
                left: startBoundaryX + (endBoundaryX - startBoundaryX) / 2,
                child: Transform.translate(
                  offset: const Offset(-30, 0),
                  child: Builder(
                    builder: (context) {
                      final colorScheme = Theme.of(context).colorScheme;
                      final currentPosition = widget.trimmer.currentPosition
                          .clamp(
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
                          _formatDurationMMSS(currentPosition),
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    // 🎯 오버레이 드래그 중이면 숨기기
    if (_isHandleDragging) {
      return const SizedBox.shrink();
    }

    // 🎯 실제 startValue/endValue 사용 (정확한 동기화)
    final startValue = widget.trimmer.startValue;
    final endValue = widget.trimmer.endValue;
    final currentPos = widget.trimmer.currentPosition;

    // 🎯 선택 범위 내에서의 상대 위치 계산 (0.0 ~ 1.0)
    final rangeLength = endValue - startValue;
    if (rangeLength <= 0) {
      return const SizedBox.shrink();
    }

    // 🎯 현재 위치를 범위 내로 클램프 (재생바가 항상 표시되도록)
    final clampedCurrentPos = currentPos.clamp(startValue, endValue);
    final relativePosition = (clampedCurrentPos - startValue) / rangeLength;

    // 🎯 startX와 endX는 이미 핸들의 중심 위치
    // 재생바도 핸들 중심부터 중심까지 이동
    final visualStartX = startX;
    final visualEndX = endX;
    final visualWidth = visualEndX - visualStartX;

    // 🎯 재생바의 화면상 절대 위치
    final barWidth = _isPlaybackBarDragging ? 6.0 : 3.0;
    final barLeft =
        visualStartX + (visualWidth * relativePosition) - (barWidth / 2);

    // 🎯 재생바 위치를 경계선 사이로 제한
    final minDistanceFromBoundary = 4.0;
    final minBarLeft = startX + minDistanceFromBoundary;
    final maxBarLeft = endX - minDistanceFromBoundary - barWidth;

    final clampedBarLeft = barLeft.clamp(minBarLeft, maxBarLeft);

    return Positioned(
      left: clampedBarLeft,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          if (_isHandleDragging) {
            return;
          }

          debugPrint('[PlaybackBar] 드래그 시작');
          setState(() {
            _isPlaybackBarDragging = true;
          });
          // 재생 중이면 일시정지
          if (widget.trimmer.isPlaying) {
            widget.trimmer.videoPlaybackControl();
          }
        },
        onPanUpdate: (details) {
          if (!_isPlaybackBarDragging || _isHandleDragging) return;

          // 🎯 드래그 delta를 상대 위치 변화로 변환 (시각적 너비 기준)
          final deltaPixels = details.delta.dx;
          final deltaRelative = deltaPixels / visualWidth;
          final deltaTime = deltaRelative * rangeLength;

          // 새로운 위치 계산 (startValue/endValue 기준)
          var newPosition = clampedCurrentPos + deltaTime;

          // 범위 제한 (startValue/endValue 사용)
          newPosition = newPosition.clamp(startValue, endValue);

          debugPrint(
            '[PlaybackBar] 드래그: $newPosition초 (범위: $startValue ~ $endValue)',
          );
          widget.trimmer.seekTo(newPosition);
        },
        onPanEnd: (details) {
          debugPrint('[PlaybackBar] 드래그 종료');
          setState(() {
            _isPlaybackBarDragging = false;
          });
        },
        child: Container(
          width: barWidth + 20, // 터치 영역 확장
          alignment: Alignment.center,
          child: Builder(
            builder: (context) {
              final colorScheme = Theme.of(context).colorScheme;
              return Container(
                width: barWidth,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.3),
                      blurRadius: _isPlaybackBarDragging ? 8 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 드래그 가능한 오버레이 (핸들 대신 사용)
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
        const minLength = 1.0;

        if (isStart) {
          var newStart = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 드래그 시작 시 저장된 반대쪽 값과 비교
          if (newStart >= _dragStartOppositeValue!) return;

          newStart = newStart.clamp(
            0.0,
            (_dragStartOppositeValue! - minLength).clamp(0.0, totalSeconds),
          );

          // 🎯 유효하지 않은 값 방지
          if (newStart.isNaN || newStart.isInfinite || newStart < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newStart >= _dragStartOppositeValue!) return;

          final proposedLength = _dragStartOppositeValue! - newStart;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;
          newStart = newStart.clamp(0.0, totalSeconds);

          widget.trimmer.onChangeStart(newStart);
          widget.onChangeStart?.call(newStart);
          // 🎯 드래그 중 즉시 UI 업데이트 (오버레이가 따라오도록)
          setState(() {});
        } else {
          var newEnd = _dragStartValue! + deltaSeconds;

          // 🎯 핸들 위치 역전 방지: 드래그 시작 시 저장된 반대쪽 값과 비교
          if (newEnd <= _dragStartOppositeValue!) return;

          newEnd = newEnd.clamp(
            (_dragStartOppositeValue! + minLength).clamp(0.0, totalSeconds),
            totalSeconds,
          );

          // 🎯 유효하지 않은 값 방지
          if (newEnd.isNaN || newEnd.isInfinite || newEnd < 0) return;

          // 🎯 최종 역전 체크 (clamp 후에도)
          if (newEnd <= _dragStartOppositeValue!) return;

          final proposedLength = newEnd - _dragStartOppositeValue!;
          if (proposedLength < minLength) return;
          if (proposedLength > maxTrimLength) return;
          newEnd = newEnd.clamp(0.0, totalSeconds);

          widget.trimmer.onChangeEnd(newEnd);
          widget.onChangeEnd?.call(newEnd);
          // 🎯 드래그 중 즉시 UI 업데이트 (오버레이가 따라오도록)
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
        if (isStart) {
          widget.trimmer.seekTo(widget.trimmer.startValue);
        } else {
          widget.trimmer.seekTo(widget.trimmer.endValue);
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
        const minLength = 1.0;

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
      child: Center(
        child: Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            return Container(
              width: 20,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.6),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.4),
                    blurRadius: _isHandleDragging ? 8 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // 🎯 그립 라인들
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 2.0,
                          height: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 1.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(1.25),
                          ),
                        ),
                        Container(
                          width: 2.0,
                          height: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 1.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(1.25),
                          ),
                        ),
                        Container(
                          width: 2.0,
                          height: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 1.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(1.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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
      final result = await _trimmer.saveTrimmedVideo(
        startValue: _trimmer.startValue,
        endValue: _trimmer.endValue,
      );

      if (!mounted) return;

      // 🎯 플레이스홀더 안정화 대기 (UX 개선)
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      debugPrint('[VideoTrimScreen] 트리밍 오류: $e');
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
