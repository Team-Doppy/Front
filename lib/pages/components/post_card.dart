import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final VideoMuteService _muteService = VideoMuteService();
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
    _muteService.addListener(_onMuteServiceChanged);

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
    _muteService.removeListener(_onMuteServiceChanged);

    // 현재 카드가 재생 중이면 일시정지
    if (_videoController != null && widget.isVisible) {
      _videoController?.pause();
    }

    // 캐시된 서버 비디오는 참조 해제
    if (_cachedVideoUrl != null) {
      VideoCacheService().releaseController(
        _cachedVideoUrl!,
        namespace: 'home',
      );
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

  // 볼륨 적용을 안정화하기 위한 보정: 즉시/마이크로태스크/지연 재적용
  void _applyVolumeKick() {
    if (_videoController == null) return;
    final double vol = _muteService.isFeedMuted ? 0.0 : 1.0;
    _videoController!.setVolume(vol);
    Future.microtask(() => _videoController?.setVolume(vol));
    Future.delayed(const Duration(milliseconds: 20), () {
      _videoController?.setVolume(vol);
    });
  }

  void _onMuteServiceChanged() {
    // 피드 음소거 상태가 변경되면 비디오 볼륨 조정
    if (_videoController != null &&
        _isVideo &&
        _videoController!.value.isInitialized) {
      final newVolume = _muteService.isFeedMuted ? 0.0 : 1.0;
      _videoController!.setVolume(newVolume);
      debugPrint(
        '[PostCard] 음소거 상태 변경: ${_muteService.isFeedMuted ? "음소거" : "소리 켜짐"} (isVisible: ${widget.isVisible}, isPlaying: ${_videoController!.value.isPlaying})',
      );
      // 아이콘 업데이트를 위해 필요
      if (mounted) setState(() {});
    }
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

      // 캐시 서비스에서 컨트롤러 가져오기
      _videoController = VideoCacheService().getOrCreateController(
        _cachedVideoUrl!,
        namespace: 'home',
      );

      // 컨트롤러를 받았으므로 UI 갱신 시도 (Shimmer → 콘텐츠 전환)

      // 이미 초기화된 경우 바로 setState, 아니면 리스너 등록
      if (_videoController!.value.isInitialized) {
        debugPrint('[PostCard] 캐시된 비디오 즉시 표시: $_cachedVideoUrl');
        // 캐시된 컨트롤러의 볼륨 설정 (피드 음소거 상태 사용)
        final newVolume = _muteService.isFeedMuted ? 0.0 : 1.0;
        debugPrint(
          '[PostCard] 볼륨 설정: $newVolume (isFeedMuted: ${_muteService.isFeedMuted}, isVisible: ${widget.isVisible})',
        );
        _videoController!.setVolume(newVolume);
        // 현재 보이는 카드만 재생
        if (widget.isVisible) {
          _videoController!.play();
          // 재생 직후에도 한 번 더 볼륨 적용 (라우팅 복귀 타이밍 보정)
          _applyVolumeKick();
          debugPrint('[PostCard] 비디오 재생 시작');
        } else {
          _videoController!.pause();
          debugPrint('[PostCard] 비디오 일시정지');
        }
        // 캐시된 경우에는 setState 호출하여 즉시 UI 업데이트
        if (mounted) setState(() {});
      } else {
        debugPrint('[PostCard] 비디오 초기화 대기 중: $_cachedVideoUrl');
        _videoController!.addListener(_onVideoInitialized);
        // 초기화 중이어도 쉬머는 표시하지 않음 (검은 화면 + 로딩)
        if (mounted) setState(() {});
      }
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
          final newVolume = _muteService.isFeedMuted ? 0.0 : 1.0;
          _videoController!.setVolume(newVolume);
          debugPrint('[PostCard] 볼륨 재설정: $newVolume');
        }
        // 이후 로직 계속 진행 (isVisible 체크)
      } else {
        // URL이 다르면 기존 컨트롤러 해제하고 재생성
        if (_cachedVideoUrl != null) {
          VideoCacheService().releaseController(
            _cachedVideoUrl!,
            namespace: 'home',
          );
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
      final currentVolume = _muteService.isFeedMuted ? 0.0 : 1.0;
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
      final newVolume = _muteService.isFeedMuted ? 0.0 : 1.0;
      debugPrint(
        '[PostCard] 초기화 완료 - 볼륨 설정: $newVolume (isFeedMuted: ${_muteService.isFeedMuted}, isVisible: ${widget.isVisible})',
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
    _muteService.toggleFeedMute();
  }

  Widget _buildImage() {
    // 🎯 네트워크 URL인지 먼저 판단 (대부분의 경우)
    final isNetworkUrl =
        widget.thumbnailImageUrl.isNotEmpty &&
        (widget.thumbnailImageUrl.startsWith('http://') ||
            widget.thumbnailImageUrl.startsWith('https://'));

    if (isNetworkUrl) {
      // 네트워크 이미지/영상
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12), // 보더 두께만큼 작게
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                  )
                  : SizedBox.expand(
                    child: CachedNetworkImage(
                      imageUrl: widget.thumbnailImageUrl,
                      fit: BoxFit.cover,
                      key: ValueKey('bg-${widget.thumbnailImageUrl}'),
                      fadeInDuration: const Duration(milliseconds: 180),
                      fadeOutDuration: const Duration(milliseconds: 80),
                      placeholder:
                          (context, url) => ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: BorderRadius.circular(12),
                          ),
                      errorWidget:
                          (context, error, stackTrace) => Container(
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
                          ),
                      memCacheWidth: 800, // 메모리 캐시 크기 지정
                      maxWidthDiskCache: 800, // 디스크 캐시 크기
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
                        _muteService.isFeedMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
    // 🎯 로컬 에셋 기반 포스트인지 확인 (온보딩 플레이스홀더)
    final isOnboardingPost = widget.postId.startsWith('onboarding_placeholder');

    // 🎯 LikeService에서 좋아요 상태 가져오기 (항상 최신 상태 반영)
    // initState에서 이미 setInitialLikeData를 호출했으므로 LikeService에 값이 있어야 함
    // 사용자가 좋아요를 클릭하면 LikeService 값이 즉시 업데이트되므로 항상 LikeService 값을 우선 사용
    // LikeService에 값이 없을 때만 fallback으로 widget.isLiked 사용
    final hasLikeData = _likeService.hasPost(widget.postId);
    final currentIsLiked =
        hasLikeData ? _likeService.isPostLiked(widget.postId) : widget.isLiked;

    // 디버그 로그 제거 (불필요한 리빌드 방지)

    return Stack(
      children: [
        _buildImage(),
        // 🎯 작성자 정보 (이미지 위 상단 오버레이) - 로컬 에셋이 아닐 때만 표시
        if (!isOnboardingPost)
          Positioned(
            left: 10,
            bottom: 8,
            child: GestureDetector(
              onTap: () {
                final currentUser = context.read<UserProvider>().currentUser;
                final isMyPost = widget.author == currentUser?.username;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => UserProfileScreen(
                          otherUser:
                              isMyPost
                                  ? null // 내 프로필일 때는 null로 내 프로필 표시
                                  : User(
                                    username: widget.author,
                                    alias: widget.author,
                                    profileImageUrl:
                                        widget.authorProfileImageUrl,
                                  ),
                        ),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CommonProfileAvatar(
                    imageUrl: widget.authorProfileImageUrl ?? "",
                    username: widget.author,
                    size: 28,
                    borderWidth: 0,
                    borderColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.author,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
