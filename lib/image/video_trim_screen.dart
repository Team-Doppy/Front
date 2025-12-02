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

  bool _isSeeking = false;

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_videoPlayerController == null || !_isInitialized) {
        timer.cancel();
        return;
      }

      // seekTo 중에는 체크하지 않음
      if (_isSeeking) {
        return;
      }

      final position =
          _videoPlayerController!.value.position.inMilliseconds / 1000.0;
      final isPlaying = _videoPlayerController!.value.isPlaying;

      // 상태 업데이트
      bool needsUpdate = false;

      // 재생 범위 체크
      if (position >= _endValue && position > _startValue) {
        if (isPlaying) {
          debugPrint('[Trimmer] 끝 도달: $position >= $_endValue, 시작으로 이동');
          _isSeeking = true;
          _videoPlayerController!.pause();
          _videoPlayerController!
              .seekTo(Duration(milliseconds: (_startValue * 1000).toInt()))
              .then((_) {
                _isSeeking = false;
              });
          _isPlaying = false;
          _currentPosition = _startValue;
          needsUpdate = true;
        }
      } else if (position < _startValue - 0.2) {
        // 0.2초 이상 차이날 때만 보정 (무한 루프 방지)
        debugPrint('[Trimmer] 시작 이전: $position < $_startValue, 시작으로 이동');
        _isSeeking = true;
        _videoPlayerController!
            .seekTo(Duration(milliseconds: (_startValue * 1000).toInt()))
            .then((_) {
              _isSeeking = false;
            });
        _currentPosition = _startValue;
        needsUpdate = true;
      } else {
        // 정상 범위 내
        if (_currentPosition != position || _isPlaying != isPlaying) {
          _currentPosition = position;
          _isPlaying = isPlaying;
          needsUpdate = true;
        }
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
      debugPrint(
        '[Trimmer] ❌ videoPlaybackControl 실패: controller=$_videoPlayerController, initialized=$_isInitialized',
      );
      return;
    }

    debugPrint(
      '[Trimmer] videoPlaybackControl 호출: isPlaying=$_isPlaying, currentPosition=$_currentPosition, start=$_startValue, end=$_endValue',
    );
    debugPrint(
      '[Trimmer] 비디오 컨트롤러 상태: position=${_videoPlayerController!.value.position.inSeconds}초, isPlaying=${_videoPlayerController!.value.isPlaying}, isInitialized=${_videoPlayerController!.value.isInitialized}',
    );

    try {
      if (_isPlaying) {
        _videoPlayerController!.pause();
        _isPlaying = false;
        debugPrint('[Trimmer] ✅ 일시정지');
      } else {
        // 🎯 재생 시작 시 _isSeeking 무시 (강제 재생)
        _isSeeking = false;

        // 현재 위치가 범위를 벗어나면 시작 지점으로
        if (_currentPosition >= _endValue || _currentPosition < _startValue) {
          debugPrint(
            '[Trimmer] 범위 밖: $_currentPosition, 시작 지점으로 이동: $_startValue',
          );
          _isSeeking = true;
          _videoPlayerController!
              .seekTo(Duration(milliseconds: (_startValue * 1000).toInt()))
              .then((_) {
                _isSeeking = false;
              });
          _currentPosition = _startValue;
        }

        debugPrint('[Trimmer] play() 호출 시도...');
        _videoPlayerController!.play();
        _isPlaying = true;
        debugPrint('[Trimmer] ✅ 재생 시작: position=$_currentPosition');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Trimmer] ❌ 재생 제어 오류: $e');
    }
  }

  /// 재생 위치 이동
  void seekTo(double position) {
    if (_videoPlayerController == null || !_isInitialized) {
      debugPrint(
        '[Trimmer] ❌ seekTo 실패: controller=$_videoPlayerController, initialized=$_isInitialized',
      );
      return;
    }

    debugPrint('[Trimmer] 🎯 seekTo: $position초');
    _isSeeking = true;

    // 타임아웃 추가 (500ms 후 강제로 플래그 해제)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_isSeeking) {
        debugPrint('[Trimmer] ⚠️ seekTo 타임아웃, 플래그 강제 해제');
        _isSeeking = false;
      }
    });

    _videoPlayerController!
        .seekTo(Duration(milliseconds: (position * 1000).toInt()))
        .then((_) {
          _isSeeking = false;
          debugPrint('[Trimmer] ✅ seekTo 완료: $position초');
        })
        .catchError((e) {
          _isSeeking = false;
          debugPrint('[Trimmer] ❌ seekTo 오류: $e');
        });
    _currentPosition = position;
    notifyListeners();
  }

  /// 시작 값 변경
  void onChangeStart(double value) {
    _startValue = value;
    notifyListeners();
  }

  /// 끝 값 변경
  void onChangeEnd(double value) {
    _endValue = value;
    notifyListeners();
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

      const int maxFrames = 40;
      const int minFrames = 10;

      int frameCount = totalSeconds.floor();
      frameCount = frameCount.clamp(minFrames, maxFrames);

      final intervalSeconds = totalSeconds / frameCount;

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
  bool _isDragging = false;
  double? _selectionAreaDragStartStartValue;
  double? _selectionAreaDragStartEndValue;
  double _thumbnailScrollOffset = 0.0;

  // 🎯 핸들의 화면상 고정 위치 (초기화는 첫 빌드에서)
  double? _fixedStartX;
  double? _fixedEndX;

  // 🎯 재생바 드래그 상태
  bool _isPlaybackBarDragging = false;

  // 🎯 스크롤 중 상태
  bool _isScrolling = false;
  Timer? _scrollEndTimer;

  @override
  void initState() {
    super.initState();
    widget.trimmer.addListener(_onTrimmerUpdate);
  }

  @override
  void dispose() {
    widget.trimmer.removeListener(_onTrimmerUpdate);
    _scrollEndTimer?.cancel();
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

  // 🎯 계산된 시간 값을 State에 저장
  double _displayStartTime = 0.0;
  double _displayEndTime = 0.0;

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
        final handleWidth = 14.0;
        final selectionMinGap = 1.0;
        final maxDuration = totalSeconds;

        // 🎯 썸네일 스트립 너비 계산
        final thumbnailStripWidth =
            totalSeconds <= maxTrimLength
                ? totalWidth // 1분 미만: 화면 너비에 맞춤
                : (totalSeconds / maxTrimLength) *
                    (totalWidth * 2 / 3); // 1분 이상: 기존 방식

        final pxPerSecond = thumbnailStripWidth / totalSeconds;

        // 🎯 핸들의 실제 썸네일 스트립 상 픽셀 위치
        final selectionPixelStart = widget.trimmer.startValue * pxPerSecond;
        final selectionPixelEnd = widget.trimmer.endValue * pxPerSecond;

        // 🎯 화면에 표시될 핸들 위치와 썸네일 오프셋 계산
        final handleMargin = 10.0; // 핸들이 화면 끝에서 유지할 최소 여백
        final maxVisibleWidth = totalWidth;

        // 🎯 간단한 구조:
        // 1. 핸들 드래그 → 핸들만 움직임, 썸네일 고정
        // 2. 나머지 영역 드래그 → 핸들 화면상 고정, 썸네일 스크롤

        // 🎯 첫 빌드 시 화면상 고정 위치 초기화
        if (_fixedStartX == null || _fixedEndX == null) {
          if (totalSeconds <= maxTrimLength) {
            // 1분 미만: 핸들을 양 끝에 배치
            _fixedStartX = 0.0;
            _fixedEndX = thumbnailStripWidth;
          } else {
            // 1분 이상: 기존 방식
            _fixedStartX = selectionPixelStart;
            _fixedEndX = selectionPixelEnd;
          }
        }

        // 썸네일 오프셋 적용
        final thumbnailOffset = -_thumbnailScrollOffset;

        // 🎯 핸들은 화면상 고정 위치 사용
        final startX = _fixedStartX!;
        final endX = _fixedEndX!;

        // 🎯 핸들의 화면상 위치로부터 실제 시간 역계산
        // 화면상 핸들 위치에서 썸네일 오프셋을 빼면 절대 픽셀 위치
        // 절대 픽셀 위치를 pxPerSecond로 나누면 시간(초)
        _displayStartTime = (startX - thumbnailOffset) / pxPerSecond;
        _displayEndTime = (endX - thumbnailOffset) / pxPerSecond;

        // 🎯 Trimmer의 startValue/endValue도 동기화 (재생에 사용됨)
        if ((widget.trimmer.startValue - _displayStartTime).abs() > 0.1 ||
            (widget.trimmer.endValue - _displayEndTime).abs() > 0.1) {
          // 차이가 0.1초 이상일 때만 업데이트 (불필요한 notifyListeners 방지)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.trimmer.onChangeStart(_displayStartTime);
            widget.trimmer.onChangeEnd(_displayEndTime);
          });
        }

        return Stack(
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

            // 썸네일 스트립
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: OverflowBox(
                maxWidth: thumbnailStripWidth,
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(thumbnailOffset, 0),
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
                                    (thumb) => Expanded(
                                      child:
                                          thumb != null
                                              ? Image.memory(
                                                thumb,
                                                fit: BoxFit.fill,
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
                                                  return Container();
                                                },
                                              ),
                                    ),
                                  )
                                  .toList(),
                    ),
                  ),
                ),
              ),
            ),

            // 🎯 재생 시간 표시 (선택 구간 표시 박스 위에, 가운데 정렬)
            Positioned(
              top: -60,
              left: startX + (endX - startX) / 2,
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

            // 🎯 선택 구간 표시 박스 (핸들 사이 위에) - 항상 표시
            Positioned(
              top: -30,
              left: startX + (endX - startX) / 2,
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

            // 🎯 전체 영역 드래그 (핸들 제외, 썸네일 스크롤)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  // 핸들 영역인지 체크 (좌우로 20px씩 확장)
                  final localX = event.localPosition.dx;
                  final handleTouchPadding = 20.0;

                  final startHandleLeft = (startX - handleWidth / 2).clamp(
                    handleMargin,
                    maxVisibleWidth - handleWidth - handleMargin,
                  );
                  final endHandleLeft = (endX - handleWidth / 2).clamp(
                    handleMargin,
                    maxVisibleWidth - handleWidth - handleMargin,
                  );

                  final touchingStartHandle =
                      localX >= startHandleLeft - handleTouchPadding &&
                      localX <=
                          startHandleLeft + handleWidth + handleTouchPadding;
                  final touchingEndHandle =
                      localX >= endHandleLeft - handleTouchPadding &&
                      localX <=
                          endHandleLeft + handleWidth + handleTouchPadding;

                  if (touchingStartHandle || touchingEndHandle) {
                    // 핸들 영역이면 무시
                    return;
                  }

                  _selectionAreaDragStartStartValue = widget.trimmer.startValue;
                  _selectionAreaDragStartEndValue = widget.trimmer.endValue;

                  if (mounted) {
                    setState(() {
                      _isDragging = true;
                      _isScrolling = true;
                    });
                  }
                },
                onPointerMove: (event) {
                  if (_selectionAreaDragStartStartValue == null ||
                      _selectionAreaDragStartEndValue == null) {
                    return;
                  }

                  // 🎯 썸네일 스크롤 + 시간 값도 함께 변경 (2배 빠르게)
                  final deltaPixels = event.delta.dx * 2.0;
                  final deltaSeconds = (deltaPixels / pxPerSecond);

                  final currentLength =
                      _selectionAreaDragStartEndValue! -
                      _selectionAreaDragStartStartValue!;

                  var newStart = widget.trimmer.startValue + deltaSeconds;
                  var newEnd = widget.trimmer.endValue + deltaSeconds;

                  // 🎯 범위 체크: 비디오 시작/끝을 벗어나지 않도록
                  if (newStart < 0) {
                    newStart = 0;
                    newEnd = currentLength;
                  }
                  if (newEnd > maxDuration) {
                    newEnd = maxDuration;
                    newStart = maxDuration - currentLength;
                    if (newStart < 0) newStart = 0;
                  }

                  // 썸네일 스크롤 오프셋도 함께 변경
                  final newScrollOffset = _thumbnailScrollOffset - deltaPixels;
                  final maxScroll = (thumbnailStripWidth - maxVisibleWidth)
                      .clamp(0.0, double.infinity);
                  final clampedScrollOffset = newScrollOffset.clamp(
                    0.0,
                    maxScroll,
                  );

                  if (mounted) {
                    setState(() {
                      _thumbnailScrollOffset = clampedScrollOffset;
                    });
                  }

                  widget.trimmer.onChangeStart(newStart);
                  widget.trimmer.onChangeEnd(newEnd);
                  widget.trimmer.seekTo(newStart);
                  widget.onChangeStart?.call(newStart);
                  widget.onChangeEnd?.call(newEnd);
                },
                onPointerUp: (event) {
                  _selectionAreaDragStartStartValue = null;
                  _selectionAreaDragStartEndValue = null;
                  if (mounted) {
                    setState(() {
                      _isDragging = false;
                    });

                    // 🎯 0.5초 후에 재생바 표시
                    _scrollEndTimer?.cancel();
                    _scrollEndTimer = Timer(
                      const Duration(milliseconds: 500),
                      () {
                        if (mounted) {
                          setState(() {
                            _isScrolling = false;
                          });
                        }
                      },
                    );
                  }
                },
                child: Container(color: Colors.transparent),
              ),
            ),

            // 시작 핸들 (전체 드래그보다 위에 배치)
            Positioned(
              left: (startX - handleWidth / 2).clamp(
                0.0, // 마진 없음
                maxVisibleWidth - handleWidth,
              ),
              top: 0,
              bottom: 0,
              child: _buildHandle(
                pxPerSecond: pxPerSecond,
                isStart: true,
                handleWidth: handleWidth,
                maxDuration: maxDuration,
                minGap: selectionMinGap,
                startX: startX,
                endX: endX,
                totalWidth: totalWidth,
                thumbnailStripWidth: thumbnailStripWidth,
              ),
            ),

            // 끝 핸들 (전체 드래그보다 위에 배치)
            Positioned(
              left: (endX - handleWidth / 2).clamp(
                0.0, // 마진 없음
                maxVisibleWidth - handleWidth,
              ),
              top: 0,
              bottom: 0,
              child: _buildHandle(
                pxPerSecond: pxPerSecond,
                isStart: false,
                handleWidth: handleWidth,
                maxDuration: maxDuration,
                minGap: selectionMinGap,
                startX: startX,
                endX: endX,
                totalWidth: totalWidth,
                thumbnailStripWidth: thumbnailStripWidth,
              ),
            ),

            // 🎯 재생 위치 바 (핸들 사이)
            _buildPlaybackBar(
              startX: startX,
              endX: endX,
              handleWidth: handleWidth,
              pxPerSecond: pxPerSecond,
              thumbnailOffset: thumbnailOffset,
              maxVisibleWidth: maxVisibleWidth,
              handleMargin: handleMargin,
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
    required double handleWidth,
    required double pxPerSecond,
    required double thumbnailOffset,
    required double maxVisibleWidth,
    required double handleMargin,
  }) {
    // 🎯 스크롤 중이거나 핸들 드래그 중이면 숨기기
    if (_isScrolling || _isDragging) {
      return const SizedBox.shrink();
    }

    // 🎯 새로운 접근: displayStartTime/displayEndTime 기준으로 계산
    final currentPos = widget.trimmer.currentPosition;

    // 현재 위치가 선택 범위 내에 있는지 확인
    if (currentPos < _displayStartTime || currentPos > _displayEndTime) {
      return const SizedBox.shrink();
    }

    // 🎯 선택 범위 내에서의 상대 위치 계산 (0.0 ~ 1.0)
    final rangeLength = _displayEndTime - _displayStartTime;
    if (rangeLength <= 0) {
      return const SizedBox.shrink();
    }

    final relativePosition = (currentPos - _displayStartTime) / rangeLength;

    // 🎯 startX와 endX는 이미 핸들의 중심 위치
    // 재생바도 핸들 중심부터 중심까지 이동
    final visualStartX = startX;
    final visualEndX = endX;
    final visualWidth = visualEndX - visualStartX;

    // 🎯 재생바의 화면상 절대 위치
    final barWidth = _isPlaybackBarDragging ? 6.0 : 3.0;
    final barLeft =
        visualStartX + (visualWidth * relativePosition) - (barWidth / 2);

    return Positioned(
      left: barLeft.clamp(
        visualStartX - barWidth / 2,
        visualEndX - barWidth / 2 - 10,
      ),
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
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
          // 🎯 드래그 delta를 상대 위치 변화로 변환 (시각적 너비 기준)
          final deltaPixels = details.delta.dx;
          final deltaRelative = deltaPixels / visualWidth;
          final deltaTime = deltaRelative * rangeLength;

          // 새로운 위치 계산
          var newPosition = currentPos + deltaTime;

          // 범위 제한
          newPosition = newPosition.clamp(_displayStartTime, _displayEndTime);

          debugPrint('[PlaybackBar] 드래그: $newPosition초');
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

  Widget _buildHandle({
    required double pxPerSecond,
    required bool isStart,
    required double handleWidth,
    required double maxDuration,
    required double minGap,
    required double startX,
    required double endX,
    required double totalWidth,
    required double thumbnailStripWidth,
  }) {
    return GestureDetector(
      // 🎯 핸들 영역만 정확히 감지하도록 제한, 터치 이벤트 우선순위 확보
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onPanStart: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onPanUpdate: (details) {
        // 🎯 정확한 방식: delta.dx를 초 단위로 변환하여 직접 값 업데이트
        final totalSeconds =
            widget.trimmer.videoDuration?.inSeconds.toDouble() ?? 0.0;

        // delta를 초 단위로 변환
        final deltaSeconds = details.delta.dx / pxPerSecond;
        const maxTrimLength = 60.0;

        if (isStart) {
          // 시작 값 업데이트
          var newStart = widget.trimmer.startValue + deltaSeconds;

          // 🎯 범위 체크: 0 ~ endValue
          newStart = newStart.clamp(0.0, widget.trimmer.endValue);

          // 🎯 1초 미만 체크 (최소 길이 1초) - 우선 적용
          const minLength = 1.0;
          final proposedLength = widget.trimmer.endValue - newStart;

          if (proposedLength < minLength) {
            // 1초 미만이면 업데이트 중단
            debugPrint('[TrimEditor] ❌ 시작 핸들 차단: 길이=$proposedLength초 < 1초');
            return;
          }

          // 최대 길이 체크
          if (proposedLength > maxTrimLength) {
            newStart = widget.trimmer.endValue - maxTrimLength;
          }

          // 최종 범위 체크 (0보다 작아지지 않도록)
          newStart = newStart.clamp(0.0, totalSeconds);

          debugPrint(
            '[TrimEditor] 시작 핸들 드래그: $newStart, 길이=${widget.trimmer.endValue - newStart}초',
          );

          // 🎯 화면상 고정 위치 업데이트
          setState(() {
            _fixedStartX = (_fixedStartX ?? startX) + details.delta.dx;
          });

          widget.trimmer.onChangeStart(newStart);
          widget.trimmer.seekTo(newStart);
          widget.onChangeStart?.call(newStart);
        } else {
          // 끝 값 업데이트
          var newEnd = widget.trimmer.endValue + deltaSeconds;

          // 🎯 범위 체크: startValue ~ totalSeconds
          newEnd = newEnd.clamp(widget.trimmer.startValue, totalSeconds);

          // 🎯 1초 미만 체크 (최소 길이 1초) - 우선 적용
          const minLength = 1.0;
          final proposedLength = newEnd - widget.trimmer.startValue;

          if (proposedLength < minLength) {
            // 1초 미만이면 업데이트 중단
            debugPrint('[TrimEditor] ❌ 끝 핸들 차단: 길이=${proposedLength}초 < 1초');
            return;
          }

          // 최대 길이 체크
          if (proposedLength > maxTrimLength) {
            newEnd = widget.trimmer.startValue + maxTrimLength;
          }

          // 최종 범위 체크 (totalSeconds를 넘지 않도록)
          newEnd = newEnd.clamp(0.0, totalSeconds);

          debugPrint(
            '[TrimEditor] 끝 핸들 드래그: $newEnd, 길이=${newEnd - widget.trimmer.startValue}초',
          );

          // 🎯 화면상 고정 위치 업데이트
          setState(() {
            _fixedEndX = (_fixedEndX ?? endX) + details.delta.dx;
          });

          widget.trimmer.onChangeEnd(newEnd);
          widget.trimmer.seekTo(newEnd);
          widget.onChangeEnd?.call(newEnd);
        }
      },
      onPanEnd: (_) {
        setState(() {
          _isDragging = false;
        });
      },
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return Stack(
            children: [
              Container(
                width: handleWidth,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              // 🎯 시간 구간 표시 박스 (핸들 위에)
              if (_isDragging)
                Positioned(
                  bottom: 50,
                  left: handleWidth / 2,
                  child: Transform.translate(
                    offset: const Offset(-50, 0),
                    child: Container(
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
                        isStart
                            ? _formatDuration(widget.trimmer.startValue)
                            : _formatDuration(widget.trimmer.endValue),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
          Container(
            height: 120,
            color: colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _buildTimeline(),
          ),
          // 시간 표시
          Container(
            color: colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDurationMMSS(_displayStartTime),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatDurationMMSS(_displayEndTime),
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
