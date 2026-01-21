import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/post_action_bottom_sheet.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/pages/components/share_post_overlay.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 인스타그램 스타일: 그리드 아이템을 꾹 눌렀을 때
/// - 배경 블러/딤
/// - 카드 프리뷰(이미지/영상)
/// - 하단 액션 리스트
class PostLongPressPreviewOverlayController {
  PostLongPressPreviewOverlayController._(this._entry);
  final OverlayEntry _entry;
  bool _isDismissed = false;

  void dismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    try {
      _entry.remove();
    } catch (e) {
      // 이미 제거된 overlay entry를 다시 제거하려고 할 때 발생하는 오류 무시
      debugPrint('[PostLongPressPreviewOverlay] dismiss 오류 (무시): $e');
    }
  }

  static PostLongPressPreviewOverlayController show({
    required BuildContext context,
    required SearchContentItem post,
    required Rect originRect,
    required VoidCallback onTapOpenPost,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return _PostLongPressPreviewOverlay(
          post: post,
          originRect: originRect,
          onTapOpenPost: onTapOpenPost,
          onDismiss: () {
            try {
              entry.remove();
            } catch (_) {}
          },
        );
      },
    );
    overlay.insert(entry);
    return PostLongPressPreviewOverlayController._(entry);
  }
}

class _PostLongPressPreviewOverlay extends StatefulWidget {
  const _PostLongPressPreviewOverlay({
    required this.post,
    required this.originRect,
    required this.onTapOpenPost,
    required this.onDismiss,
  });

  final SearchContentItem post;
  final Rect originRect;
  final VoidCallback onTapOpenPost;
  final VoidCallback onDismiss;

  @override
  State<_PostLongPressPreviewOverlay> createState() =>
      _PostLongPressPreviewOverlayState();
}

class _PostLongPressPreviewOverlayState
    extends State<_PostLongPressPreviewOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  bool _isDismissing = false;
  Offset _dragOffset = Offset.zero; // ✅ 드래그 오프셋 추적
  bool _isLiked = false; // ✅ 좋아요 상태 (메타데이터에서 초기화)
  final _likeService = LikeService();
  final _searchService = SearchService();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 120,
      ), // ✅ 인 애니메이션: 더 빠르게 (180ms → 120ms)
      reverseDuration: const Duration(
        milliseconds: 250,
      ), // ✅ 아웃 애니메이션: 더 느리게 (180ms → 250ms)
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    HapticFeedback.mediumImpact();

    // LikeService 변경사항 구독
    _likeService.addListener(_onLikeServiceChanged);

    // ✅ 좋아요 상태 초기화 (메타데이터에서 가져오기)
    _initializeLikeStatus();

    _ctrl.forward();
  }

  void _initializeLikeStatus() {
    // ✅ SearchService의 _postData에서 원본 서버 응답 가져오기
    final postData = _searchService.getPostData(widget.post.id);

    if (postData != null) {
      // ✅ 서버 응답에 isLiked가 있으면 사용
      final isLikedFromServer = postData['isLiked'] == true;
      final likeCountFromServer =
          (postData['likeCount'] as num?)?.toInt() ?? widget.post.likes ?? 0;

      // ✅ LikeService에 초기 데이터 설정
      _likeService.setInitialLikeData(
        widget.post.id,
        isLikedFromServer,
        likeCountFromServer,
      );

      if (mounted) {
        setState(() {
          _isLiked = isLikedFromServer;
        });
      }
    } else {
      // ✅ 메타데이터가 없으면 LikeService에서 확인 (캐시에 있을 수 있음)
      _isLiked = _likeService.isPostLiked(widget.post.id);
      debugPrint('[PostLongPressPreviewOverlay] 좋아요 상태 서버 동기화 후 : $_isLiked');

      // ✅ 캐시에도 없으면 서버에서 가져오기
      if (!_likeService.hasPost(widget.post.id)) {
        _likeService.ensureLoaded(widget.post.id).then((_) {
          if (mounted) {
            setState(() {
              _isLiked = _likeService.isPostLiked(widget.post.id);
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {
        _isLiked = _likeService.isPostLiked(widget.post.id);
      });
    }
  }

  Future<void> _handleDismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;

    // ✅ 역애니메이션 실행 (endRect → originRect)
    await _ctrl.reverse();

    // 애니메이션 완료 후 실제 dismiss
    if (mounted) {
      widget.onDismiss();
    }
  }

  Rect _targetRect(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final pad = mq.padding;

    // ✅ 인스타처럼 더 작고 미니멀하게
    final maxW = (size.width * 0.75).clamp(0.0, 320.0);
    final cardW = maxW;
    final cardH = cardW * 1.2; // 인스타 느낌(세로 카드, 약간 더 작게)

    // 상단 SafeArea 아래, 중앙보다 살짝 위에 배치
    final topMin = pad.top + 12;
    final topPreferred = size.height * 0.15;
    final top = topPreferred < topMin ? topMin : topPreferred;

    final left = (size.width - cardW) / 2;
    return Rect.fromLTWH(left, top, cardW, cardH);
  }

  bool _isVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.endsWith('.mov') ||
        u.endsWith('.m4v') ||
        u.contains('/videos/') ||
        u.contains('video');
  }

  Future<void> _handleLike() async {
    final postId = widget.post.id;
    try {
      // ✅ 오버레이 닫기 전에 좋아요 토글
      await _likeService.togglePostLike(postId);
      // 상태는 _onLikeServiceChanged에서 자동 업데이트됨
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(context, e.toString());
    }
  }

  Future<void> _handleShare() async {
    // ✅ 오버레이 먼저 닫기
    await _handleDismiss();

    if (!mounted) return;

    final p = widget.post;
    final author = p.author ?? '';
    SharePostOverlay.show(
      context,
      postId: p.id,
      title: p.title ?? '',
      summary: p.summary ?? '',
      authorUsername: author,
      authorProfileImageUrl: p.profileImageUrl,
      thumbnailUrl: p.imageUrl,
      readTime: 1,
    );
  }

  Future<void> _handleProfile() async {
    final username = widget.post.author ?? '';
    if (username.isEmpty) return;

    // ✅ 오버레이 먼저 닫기
    await _handleDismiss();

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(otherUser: User(username: username)),
      ),
    );
  }

  Future<void> _handleReport() async {
    // ✅ 오버레이 먼저 닫기
    await _handleDismiss();

    if (!mounted) return;

    final p = widget.post;
    final author = p.author ?? '';
    PostActionBottomSheet.show(
      context,
      postId: p.id,
      postTitle: p.title ?? '',
      authorUsername: author,
      authorAlias: null,
      authorProfileImageUrl: p.profileImageUrl,
      thumbnailImageUrl: p.imageUrl,
      likeCount: p.likes ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final img = p.imageUrl ?? '';
    final isVideo = img.isNotEmpty && _isVideoUrl(img);

    final endRect = _targetRect(context);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 배경 딤 + 블러 (탭하면 닫기)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleDismiss,
              child: AnimatedBuilder(
                animation: _t,
                builder: (context, _) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 18 * _t.value,
                      sigmaY: 18 * _t.value,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(0.35 * _t.value),
                    ),
                  );
                },
              ),
            ),
          ),

          // 카드 프리뷰 (originRect → endRect)
          AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final rect = Rect.lerp(widget.originRect, endRect, _t.value)!;
              // ✅ 드래그 오프셋 적용
              final currentTop = rect.top + _dragOffset.dy;
              final currentLeft = rect.left + _dragOffset.dx;

              // ✅ 드래그 거리에 따른 opacity 계산 (아래로 드래그할 때만)
              final dragProgress =
                  _dragOffset.dy > 0
                      ? (_dragOffset.dy /
                              (MediaQuery.of(context).size.height * 0.3))
                          .clamp(0.0, 1.0)
                      : 0.0;
              final cardOpacity = 1.0 - (dragProgress * 0.8); // 최대 80%까지 투명해짐

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                left: currentLeft,
                top: currentTop,
                width: rect.width,
                height: rect.height,
                child: Opacity(
                  opacity: cardOpacity,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      // ✅ 아래로만 드래그 허용 (위로는 제한)
                      if (details.delta.dy > 0 || _dragOffset.dy > 0) {
                        setState(() {
                          _dragOffset += details.delta;
                        });
                      }
                    },
                    onPanEnd: (details) {
                      final screenHeight = MediaQuery.of(context).size.height;
                      final dragThreshold =
                          screenHeight * 0.15; // 화면 높이의 15% 이상 드래그하면 닫기
                      final velocity = details.velocity.pixelsPerSecond.dy;

                      // ✅ 빠르게 아래로 스와이프하거나 일정 거리 이상 드래그하면 닫기
                      if (_dragOffset.dy > dragThreshold || velocity > 500) {
                        _handleDismiss();
                      } else {
                        // ✅ 그렇지 않으면 원래 위치로 부드럽게 스프링백 (AnimatedPositioned가 자동 처리)
                        setState(() {
                          _dragOffset = Offset.zero;
                        });
                      }
                    },
                    child: Transform.scale(
                      scale: 0.8 + (0.02 * _t.value),
                      child: Material(
                        color: Colors.transparent,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (isVideo)
                                ThumbnailVideoPlayer(
                                  videoUrl: img,
                                  width: rect.width,
                                  height: rect.height,
                                  autoPlay: true,
                                )
                              else
                                Image(
                                  image: CachedNetworkImageProvider(img),
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) => Container(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surfaceVariant,
                                      ),
                                ),
                              // 상단 텍스트 바(간단)
                              Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  color: Colors.black.withOpacity(0.25),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.author ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
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
                    ),
                  ),
                ),
              );
            },
          ),

          // 하단 액션 리스트 (카드 바로 아래에 붙음)
          AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final rect = Rect.lerp(widget.originRect, endRect, _t.value)!;
              // 카드 바로 아래에 배치 (간격 12px)
              final actionListTop = rect.bottom - 10.0;

              // ✅ 드래그 오프셋 적용
              final currentActionListTop = actionListTop + _dragOffset.dy;
              final currentActionListLeft = rect.left + _dragOffset.dx;

              // ✅ 드래그 거리에 따른 opacity 계산
              final dragProgress =
                  _dragOffset.dy > 0
                      ? (_dragOffset.dy /
                              (MediaQuery.of(context).size.height * 0.3))
                          .clamp(0.0, 1.0)
                      : 0.0;
              final actionListOpacity = _t.value * (1.0 - (dragProgress * 0.8));

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                left: currentActionListLeft,
                top: currentActionListTop,
                width: rect.width,
                child: Opacity(
                  opacity: actionListOpacity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: rect.width,
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.88),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionRow(
                            label: '좋아요',
                            icon:
                                _isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                            isLiked: _isLiked,
                            onTap: _handleLike,
                          ),
                          _ActionRow(
                            label: '공유하기',
                            icon: Icons.send_outlined,
                            onTap: _handleShare,
                          ),
                          _ActionRow(
                            label: '프로필 보기',
                            icon: Icons.account_circle_outlined,
                            onTap: _handleProfile,
                          ),
                          _ActionRow(
                            label: '신고',
                            icon: Icons.report_outlined,
                            isDestructive: true,
                            onTap: _handleReport,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.isLiked = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isLiked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    if (isDestructive) {
      color = theme.colorScheme.error;
    } else if (isLiked) {
      // ✅ 좋아요 상태일 때 빨간색
      color = Colors.red;
    } else {
      color = theme.colorScheme.onSurface;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // ✅ 인스타처럼 더 컴팩트하게
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withOpacity(0.15),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              Icon(icon, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
