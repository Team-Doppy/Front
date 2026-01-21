import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/image/utils/read_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

// ignore: must_be_immutable
class PostCard extends StatefulWidget {
  final double containerWidth;
  final String thumbnailImageUrl;
  final String? heroTag;
  final String title;
  final String author;
  final String? authorProfileImageUrl;
  final String content;
  final bool isVisible;
  final VoidCallback? onLikePressed;
  final String postId; // 포스트 ID 추가

  bool isLiked;
  int likeCount;

  PostCard({
    super.key,
    required this.containerWidth,
    required this.thumbnailImageUrl,
    this.heroTag,
    required this.title,
    required this.author,
    this.authorProfileImageUrl,
    required this.content,
    this.isVisible = false,
    this.onLikePressed,
    required this.postId, // 필수로 변경

    this.isLiked = false,
    this.likeCount = 0,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with AutomaticKeepAliveClientMixin {
  final LikeService _likeService = LikeService();
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  String? _cachedVideoUrl;
  // 비디오 준비 상태는 Shimmer 전환으로 대체되어 별도 플래그 불필요

  @override
  bool get wantKeepAlive => true; // 스크롤해도 위젯 상태 유지

  @override
  void initState() {
    super.initState();
    _likeService.addListener(_onLikeServiceChanged);

    // 🎯 서버에서 받은 초기 좋아요 상태를 LikeService에 설정
    // (LikeService에 값이 없을 때만, post_list에서 이미 설정했을 수도 있음)
    if (!_likeService.hasPost(widget.postId)) {
      _likeService.setInitialLikeData(
        widget.postId,
        widget.isLiked,
        widget.likeCount,
      );
    }

    // 🎯 초기 상태 저장 (변경 감지용)
    _previousIsLiked =
        _likeService.hasPost(widget.postId)
            ? _likeService.isPostLiked(widget.postId)
            : widget.isLiked;
    _previousLikeCount =
        _likeService.hasPost(widget.postId)
            ? _likeService.getPostLikeCount(widget.postId)
            : widget.likeCount;

    _checkIfVideo();
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);

    // ✅ 캐시 컨트롤러는 위젯이 사라져도 살아있을 수 있으므로,
    // isVisible과 무관하게 "재생 중이면" 일시정지하여 소리/리소스 누수를 방지한다.
    if (_videoController != null) {
      try {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        }
      } catch (_) {}
    }

    // 🎯 표준 방식: 컨트롤러 dispose
    if (_videoController != null) {
      try {
        _videoController!.removeListener(_onVideoInitialized);
        if (_videoController!.value.isInitialized) {
          _videoController!.pause();
        }
        _videoController!.dispose();
      } catch (e) {
        debugPrint('[PostCard] 컨트롤러 dispose 오류: $e');
      }
      _videoController = null;
      _cachedVideoUrl = null;
    }

    super.dispose();
  }

  // 🎯 이전 좋아요 상태를 저장하여 실제 변경 시에만 setState 호출
  bool? _previousIsLiked;
  int? _previousLikeCount;

  void _onLikeServiceChanged() {
    if (!mounted) return;

    final currentIsLiked = _likeService.isPostLiked(widget.postId);
    final currentLikeCount = _likeService.getPostLikeCount(widget.postId);

    // 🎯 실제로 값이 변경되었을 때만 setState 호출 (불필요한 리빌드 방지)
    if (_previousIsLiked != currentIsLiked ||
        _previousLikeCount != currentLikeCount) {
      _previousIsLiked = currentIsLiked;
      _previousLikeCount = currentLikeCount;
      setState(() {});
    }
  }

  // 🎯 표준 방식: 볼륨은 항상 1.0 (소리 항상 재생)
  void _applyVolumeKick() {
    if (_videoController == null) return;
    _videoController!.setVolume(1.0);
    Future.microtask(() => _videoController?.setVolume(1.0));
    Future.delayed(const Duration(milliseconds: 20), () {
      _videoController?.setVolume(1.0);
    });
  }

  void _checkIfVideo() {
    final url = widget.thumbnailImageUrl.toLowerCase();
    _isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.contains('/videos/') ||
        url.contains('video');

    if (_isVideo && widget.thumbnailImageUrl.isNotEmpty) {
      _cachedVideoUrl = widget.thumbnailImageUrl;

      // 🎯 표준 방식: 직접 컨트롤러 생성
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(_cachedVideoUrl!),
        httpHeaders: const {'Accept': 'video/*', 'Connection': 'keep-alive'},
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // 리스너 추가
      _videoController!.addListener(_onVideoInitialized);

      // 초기화 시작
      _videoController!
          .initialize()
          .then((_) {
            if (!mounted || _videoController == null) return;

            try {
              // 볼륨 설정 (피드 음소거 상태 사용)
              final newVolume = 1.0; // 🎯 항상 소리 재생
              _videoController!.setVolume(newVolume);

              // 현재 보이는 카드만 재생
              if (widget.isVisible) {
                _videoController!.play();
                _applyVolumeKick();
              } else {
                _videoController!.pause();
              }

              if (mounted) setState(() {});
            } catch (e) {
              debugPrint('[PostCard] 초기화 후 설정 오류: $e');
            }
          })
          .catchError((e) {
            debugPrint('[PostCard] 초기화 실패: $e');
            if (mounted) setState(() {});
          });

      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 서버에서 받은 초기값이 변경되면 LikeService에 반영
    // 단, LikeService에 값이 없을 때만 초기값 설정
    // (사용자가 좋아요를 클릭한 경우 LikeService 값이 우선되어야 함)
    if (!_likeService.hasPost(widget.postId)) {
      _likeService.setInitialLikeData(
        widget.postId,
        widget.isLiked,
        widget.likeCount,
      );
    }

    // 썸네일 URL이 변경된 경우에만 비디오 재설정
    if (oldWidget.thumbnailImageUrl != widget.thumbnailImageUrl) {
      debugPrint(
        '[PostCard] 썸네일 변경 감지: ${oldWidget.thumbnailImageUrl} → ${widget.thumbnailImageUrl}',
      );

      // 이전 URL과 새 URL이 다를 때만 컨트롤러 해제
      final oldUrl = oldWidget.thumbnailImageUrl.toLowerCase();
      final newUrl = widget.thumbnailImageUrl.toLowerCase();
      final oldIsVideo =
          oldUrl.endsWith('.mp4') ||
          oldUrl.endsWith('.mov') ||
          oldUrl.endsWith('.m4v') ||
          oldUrl.contains('/videos/');
      final newIsVideo =
          newUrl.endsWith('.mp4') ||
          newUrl.endsWith('.mov') ||
          newUrl.endsWith('.m4v') ||
          newUrl.contains('/videos/');

      // 둘 다 비디오이고 URL이 같으면 컨트롤러 유지 (볼륨만 재설정)
      if (oldIsVideo &&
          newIsVideo &&
          oldWidget.thumbnailImageUrl == widget.thumbnailImageUrl) {
        debugPrint('[PostCard] 같은 비디오 URL - 컨트롤러 유지');
        // 볼륨만 재설정
        if (_videoController != null && _videoController!.value.isInitialized) {
          final newVolume = 1.0; // 🎯 항상 소리 재생
          _videoController!.setVolume(newVolume);
          debugPrint('[PostCard] 볼륨 재설정: $newVolume');
        }
        // 이후 로직 계속 진행 (isVisible 체크)
      } else {
        // URL이 다르면 기존 컨트롤러 해제하고 재생성
        if (_videoController != null) {
          try {
            _videoController!.removeListener(_onVideoInitialized);
            if (_videoController!.value.isInitialized) {
              _videoController!.pause();
            }
            _videoController!.dispose();
          } catch (e) {
            debugPrint('[PostCard] 컨트롤러 dispose 오류: $e');
          }
          _videoController = null;
          _cachedVideoUrl = null;
        }

        // 비디오 상태 초기화
        _isVideo = false;

        // 새로운 썸네일 확인 및 비디오 설정
        _checkIfVideo();

        if (mounted) setState(() {});
        return; // 이후 로직 건너뛰기
      }
    }

    // 보이는 상태가 변경되면 재생/정지 제어
    if (oldWidget.isVisible != widget.isVisible &&
        _videoController != null &&
        _isVideo) {
      // 볼륨을 다시 설정 (뮤트 상태가 변경되었을 수 있음)
      final currentVolume = 1.0; // 🎯 항상 소리 재생
      _videoController!.setVolume(currentVolume);
      debugPrint('[PostCard] isVisible 변경 - 볼륨 재설정: $currentVolume');

      if (widget.isVisible) {
        _videoController!.play();
        // 가시화 직후 볼륨 재적용
        _applyVolumeKick();
        debugPrint('[PostCard] 비디오 재생: isVisible=true');
      } else {
        _videoController!.pause();
        debugPrint('[PostCard] 비디오 정지: isVisible=false');
      }
    }
  }

  void _onVideoInitialized() {
    if (_videoController?.value.isInitialized ?? false) {
      _videoController?.removeListener(_onVideoInitialized);
      // 초기화 완료 시 피드 음소거 상태 적용
      final newVolume = 1.0; // 🎯 항상 소리 재생
      debugPrint(
        '[PostCard] 초기화 완료 - 볼륨 설정: $newVolume (isVisible: ${widget.isVisible})',
      );
      _videoController?.setVolume(newVolume);
      // 현재 보이는 카드만 재생, 아니면 명시적으로 정지
      if (widget.isVisible) {
        _videoController!.play();
        // 초기화 직후 볼륨 재적용
        _applyVolumeKick();
        debugPrint('[PostCard] 초기화 후 재생 시작');
      } else {
        _videoController!.pause();
        debugPrint('[PostCard] 초기화 후 일시정지');
      }
      if (mounted) setState(() {});
    }
  }

  void _toggleMute() {
    if (_videoController == null || !_isVideo) return;
    // 피드 음소거 상태 토글
    // 🎯 표준 방식: 개별 뮤트 기능 제거 (소리 항상 재생)
  }

  Widget _buildImage() {
    // ✅ 이미지가 없으면 셔머 표시
    if (widget.thumbnailImageUrl.isEmpty) {
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ShimmerBox(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      );
    }

    // 🎯 네트워크 URL인지 먼저 판단 (대부분의 경우)
    final isNetworkUrl =
        widget.thumbnailImageUrl.isNotEmpty &&
        (widget.thumbnailImageUrl.startsWith('http://') ||
            widget.thumbnailImageUrl.startsWith('https://'));

    if (isNetworkUrl) {
      // 네트워크 이미지/영상
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22), // 보더 두께만큼 작게
          child: Stack(
            fit: StackFit.expand,
            children: [
              _isVideo
                  ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child:
                        (_videoController != null &&
                                _videoController!.value.isInitialized)
                            ? SizedBox.expand(
                              key: ValueKey(
                                'video_ready_${widget.thumbnailImageUrl}',
                              ),
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoController!.value.size.width,
                                  height: _videoController!.value.size.height,
                                  child: VideoPlayer(_videoController!),
                                ),
                              ),
                            )
                            : ShimmerBox(
                              key: ValueKey(
                                'video_shimmer_${widget.thumbnailImageUrl}',
                              ),
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: BorderRadius.circular(22),
                            ),
                  )
                  : SizedBox.expand(
                    child: Image(
                      image: ReadImageProvider.build(
                        url: widget.thumbnailImageUrl,
                        decodeWidth: 800,
                      ),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                      key: ValueKey('thumb-${widget.thumbnailImageUrl}'),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return ShimmerBox(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.circular(22),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: Center(
                            child: Icon(
                              Icons.error,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.54),
                              size: 40,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

              // 음소거 버튼 (영상이 초기화되었을 때만)
              if (_isVideo &&
                  _videoController != null &&
                  _videoController!.value.isInitialized)
                Positioned(
                  right: 6,
                  top: 6,
                  child: GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.volume_up_rounded, // 🎯 항상 소리 재생
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      // 로컬 에셋 또는 빈 URL
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            widget.thumbnailImageUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수

    // 디버그 로그 제거 (불필요한 리빌드 방지)

    return Stack(
      children: [
        _buildImage(),

        // 🎯 좋아요 정보 (오른쪽 하단) - 로컬 에셋이 아닐 때만 표시
        /*
        if (!isOnboardingPost)
          Positioned(
            right: 12,
            bottom: 8,
            child: GestureDetector(
              onTap: widget.onLikePressed,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    currentIsLiked ? Icons.favorite : Icons.favorite_border,
                    color:
                        currentIsLiked ? const Color(0xFFFF5959) : Colors.white,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),*/
      ],
    );
  }
}
