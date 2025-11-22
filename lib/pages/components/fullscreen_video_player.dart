import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 풀스크린 이미지 뷰어에서 사용하는 비디오 플레이어 위젯
class FullscreenVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final VideoPlayerController? preloadedController;
  final bool hideScrubber; // 댓글 올라왔을 때 시크바 숨김
  final TransformationController? zoomController; // 확대 제어 전달용
  final bool lockInteraction; // 상위 시트 열림 시 인터랙션 잠금
  final bool hasBottomBar; // 바텀바 유무

  const FullscreenVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = true,
    this.preloadedController,
    this.hideScrubber = false,
    this.zoomController,
    this.lockInteraction = false,
    this.hasBottomBar = false,
  });

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPreloaded = false; // 프리로드된 컨트롤러인지 여부
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isSeeking = false;
  bool _wasPlayingBeforeSeek = false;
  Duration? _targetSeekPosition; // 드래그 중 목표 위치
  double _gestureMinScale = 1.0; // 강한 축소 감지를 위한 최소 스케일

  bool _isVideoZoomed() {
    try {
      final ctrl = widget.zoomController;
      if (ctrl == null) return false;
      final m = ctrl.value;
      final sx = m.storage[0];
      final sy = m.storage[5];
      final s = (sx + sy) / 2.0;
      return s > 1.01;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() async {
    try {
      if (widget.preloadedController != null) {
        // 프리로드된 컨트롤러 사용 (이미 초기화됨)
        _controller = widget.preloadedController!;
        _isPreloaded = true;

        // 이미 초기화되어 있으므로 즉시 사용 가능
        if (_controller.value.isInitialized) {
          _isInitialized = true;

          // 볼륨만 복원 (프리로드 시 무음이었음)
          await _controller.setVolume(1.0);

          _duration = _controller.value.duration;
          _position = _controller.value.position;

          print(
            '[FullscreenVideo] 프리로드 컨트롤러 재사용 - 현재 위치: ${_position.inSeconds}초',
          );
        } else {
          // 혹시 초기화 안 되어 있으면 초기화
          await _controller.initialize();
          _duration = _controller.value.duration;
          _position = _controller.value.position;
        }
      } else {
        // 새 컨트롤러 생성 및 초기화
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        await _controller.initialize();
        _isPreloaded = false;
        _duration = _controller.value.duration;
        _position = _controller.value.position;
      }

      // 컨트롤러 상태 리스너로 진행도/재생 상태 갱신
      _controller.addListener(_onControllerTick);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // autoPlay가 true면 재생 시작
        if (widget.autoPlay && !_controller.value.isPlaying) {
          await _controller.play();
          print('[FullscreenVideo] 자동 재생 시작');
        }
      }
    } catch (e) {
      print('비디오 초기화 오류: $e');
    }
  }

  void _onControllerTick() {
    if (!mounted) return;
    if (_isSeeking) {
      // 드래그 중에는 타겟 포지션 사용
      if (_targetSeekPosition != null) {
        setState(() {
          _position = _targetSeekPosition!;
          _duration = _controller.value.duration;
        });
      }
      return;
    }
    final value = _controller.value;
    setState(() {
      _duration = value.duration;
      _position = value.position;
    });
  }

  @override
  void dispose() {
    // 리스너만 정리 (컨트롤러는 유지)
    try {
      if (_isInitialized) {
        _controller.removeListener(_onControllerTick);

        // 프리로드된 컨트롤러가 아닌 경우만 dispose
        // (직접 생성한 컨트롤러는 정리해야 함)
        if (!_isPreloaded) {
          _controller.pause();
          _controller.dispose();
          print('[FullscreenVideo] 새로 생성한 컨트롤러 dispose');
        } else {
          // 프리로드 컨트롤러는 아무것도 하지 않음
          // (재생 유지, PostReaderScreen에서만 dispose)
          print('[FullscreenVideo] 프리로드 컨트롤러 유지 (재생 계속)');
        }
      }
    } catch (e) {
      print('비디오 플레이어 정리 중 오류: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool isPlaying = _controller.value.isPlaying;
    final double maxMs =
        _duration.inMilliseconds > 0
            ? _duration.inMilliseconds.toDouble()
            : 1.0;
    final double posMs = _position.inMilliseconds.clamp(0, maxMs).toDouble();

    // 비디오 비율 계산 (16:9 이상이면 가로로 긴 영상)
    final double aspectRatio =
        _controller.value.size.width / _controller.value.size.height;
    final BoxFit videoFit =
        aspectRatio >= 16.0 / 9.0 ? BoxFit.contain : BoxFit.cover;

    return Stack(
      children: [
        // 영상
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_controller.value.isPlaying) {
                _controller.pause();
              } else {
                _controller.play();
              }
              setState(() {});
            },
            child: Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: widget.lockInteraction ? 1.0 : 4.0,
                panEnabled: !widget.lockInteraction && _isVideoZoomed(),
                scaleEnabled: !widget.lockInteraction,
                boundaryMargin:
                    widget.lockInteraction || !_isVideoZoomed()
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(200),
                clipBehavior: Clip.none,
                onInteractionStart: (_) {
                  _gestureMinScale = 1.0;
                },
                onInteractionUpdate: (details) {
                  _gestureMinScale =
                      _gestureMinScale < details.scale
                          ? _gestureMinScale
                          : details.scale;
                  setState(() {});
                },
                onInteractionEnd: (_) {
                  if (_gestureMinScale < 0.98) {
                    // 조금이라도 축소하면 정확히 원래 위치/크기로 리셋
                    final ctrl =
                        widget.zoomController ?? TransformationController();
                    ctrl.value = Matrix4.identity();
                  }
                  _gestureMinScale = 1.0;
                  setState(() {});
                },
                transformationController: widget.zoomController,
                child: FittedBox(
                  fit: videoFit,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 중앙 재생 아이콘 (일시정지 상태일 때만)
        if (!isPlaying)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        // 댓글이 열려있지 않을 때만 시크바 표시
        if (!widget.hideScrubber)
          Positioned(
            bottom: widget.hasBottomBar ? 65 : 30, // 바텀바 있으면 65, 없으면 30
            left: 20,
            right: 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _isSeeking = true;
                _wasPlayingBeforeSeek = _controller.value.isPlaying;
                // 첫 프레임 끊김 방지를 위해 첫 업데이트에서는 seek 건너뜀
                // 또한 드래그 시작 시 즉시 pause하지 않음(초기 끊김 완화)
              },
              onHorizontalDragUpdate: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final localPosition = details.localPosition.dx - 15; // 패딩 보정
                final width = box.size.width - 30; // 좌우 패딩 제외

                // 0.0 ~ 1.0 비율 계산
                final ratio = (localPosition / width).clamp(0.0, 1.0);
                final newMs = (maxMs * ratio).floor();
                final newPosition = Duration(milliseconds: newMs);

                _targetSeekPosition = newPosition;
                // 첫 업데이트에서는 seek 생략 → 첫 끊김 완화
                if (_isSeeking &&
                    _position == Duration.zero &&
                    _controller.value.position == Duration.zero) {
                  // UI만 먼저 갱신하고 다음 업데이트부터 seek 수행
                } else {
                  _controller.seekTo(newPosition);
                }

                setState(() {
                  _position = newPosition;
                });
              },
              onHorizontalDragEnd: (details) async {
                if (_targetSeekPosition != null) {
                  try {
                    // 최종 위치로 정확하게 seek
                    await _controller.seekTo(_targetSeekPosition!);
                  } catch (e) {
                    print('Seek 오류: $e');
                  }

                  setState(() {
                    _position = _targetSeekPosition!;
                  });
                }

                // seek 완료 후 재생 재개
                if (_wasPlayingBeforeSeek) {
                  _controller.play();
                }

                _isSeeking = false;
                _targetSeekPosition = null;
              },
              child: Container(
                height: 80, // 터치 영역 확대
                color: Colors.transparent,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 배경 트랙 (전체)
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // 진행 트랙 (현재 위치까지)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor:
                            maxMs > 0 ? (posMs / maxMs).clamp(0.0, 1.0) : 0.0,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
