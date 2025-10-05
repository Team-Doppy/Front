// import 'dart:math';
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:flutter/rendering.dart';

class PostList extends StatefulWidget {
  final double containerWidth;
  final List<PostData> posts;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  final Future<void> Function()? onRefresh;
  final Function(int)? onPageChanged;
  final bool showCardShimmer;

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.onRefresh,
    this.onPageChanged,
    this.showCardShimmer = false,
  });

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = 0;
  late List<PostData> _items;
  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();
  bool _isPointerDown = false; // 당김 중 손가락 눌림 상태 추적
  double _pullExtentPx = 0.0; // 커스텀 게이지 표현용 당김 픽셀
  static const double _refreshTrigger = 140.0; // 트리거 거리(둔감)
  bool _passedTrigger = false; // 임계치 통과 여부 (릴리즈 시점 확인용)

  @override
  void initState() {
    super.initState();
    // 전체 화면 사용 (인스타그램 릴스 스타일)
    _pageController = PageController(viewportFraction: 0.65);
    _items = List<PostData>.from(widget.posts);

    // LikeService 변경사항 감지
    _likeService.addListener(_onLikeServiceChanged);

    // 각 게시물의 좋아요 상태 확인
    _loadLikeStatusForAllPosts();
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadLikeStatusForAllPosts() {
    // PostData에서 직접 좋아요 상태와 수 설정
    for (final post in _items) {
      final postId = post.id.toString();
      if (postId.isNotEmpty) {
        _likeService.setInitialLikeData(postId, post.isLiked, post.likeCount);
      }
    }
  }

  void _loadLikeStatusForNewPosts(List<PostData> newPosts) {
    // 새로운 게시물들의 좋아요 상태와 수 설정
    for (final post in newPosts) {
      final postId = post.id.toString();
      if (postId.isNotEmpty) {
        _likeService.setInitialLikeData(postId, post.isLiked, post.likeCount);
      }
    }
  }

  @override
  void didUpdateWidget(PostList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 게시물 목록이 변경되었을 때
    if (widget.posts != oldWidget.posts) {
      // 새로운 포스트가 추가된 경우 (기존보다 길이가 길어짐)
      if (widget.posts.length > _items.length) {
        // 기존 _items에 새로운 포스트들만 추가
        final newPosts = widget.posts.skip(_items.length).toList();
        _items.addAll(newPosts);
        _loadLikeStatusForNewPosts(newPosts);
      } else {
        // 완전히 새로운 목록인 경우 (길이가 같거나 짧아짐)
        _items = List<PostData>.from(widget.posts);
        _loadLikeStatusForAllPosts();
      }
    }
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // debug helpers 제거 (미사용)

  @override
  Widget build(BuildContext context) {
    // 커스텀 게이지 위젯 내부 정의

    Widget pageView = PageView.builder(
      scrollDirection: Axis.horizontal,
      controller: _pageController,
      pageSnapping: true,
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.none,
      padEnds: true,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });

        // 페이지 변경 콜백 호출
        if (widget.onPageChanged != null) {
          widget.onPageChanged!(index);
        }

        // 무한 스크롤: 마지막 페이지 근처에서 더 로드
        if (widget.onLoadMore != null &&
            index >= widget.posts.length - 2 &&
            !widget.isLoadingMore) {
          widget.onLoadMore!();
        }
      },
      itemCount: _items.length + (widget.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          // 로딩 인디케이터
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  '더 많은 포스트를 불러오는 중...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        // 안전한 범위 체크
        if (index >= _items.length) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Text('로딩 중...', style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        final post = _items[index];
        return _buildPostItem(context, post, index);
      },
    );

    // 전체 화면 어디서든 아래로 당겨 새로고침 가능하도록 (커스텀 게이지 + 취소 지원)
    final List<Widget> slivers = [];
    // CupertinoSliverRefreshControl 제거: 바운싱 없이도 새로고침을 지원하기 위해 Material RefreshIndicator 사용

    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.48,
          child: pageView,
        ),
      ),
    );

    slivers.add(
      SliverFillRemaining(
        hasScrollBody: false,
        child: _buildStickyAuthor(context),
      ),
    );

    final scrollable = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );

    Widget content =
        (widget.onRefresh != null)
            ? NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is OverscrollNotification &&
                    n.metrics.pixels <= n.metrics.minScrollExtent) {
                  // 방향 혼동 방지: 절대값으로 누적하되, 포인터 이동에서 방향 필터링
                  final double delta = n.overscroll.abs() * 0.4; // 더 둔감
                  _pullExtentPx = (_pullExtentPx + delta).clamp(0.0, 160.0);
                  _passedTrigger = _pullExtentPx >= _refreshTrigger;
                  setState(() {});
                } else if (n is ScrollEndNotification ||
                    n is UserScrollNotification &&
                        (n).direction == ScrollDirection.idle) {
                  if (_pullExtentPx < _refreshTrigger && !_isPointerDown) {
                    _pullExtentPx = 0.0;
                    _passedTrigger = false;
                    setState(() {});
                  }
                }
                return false;
              },
              child: scrollable,
            )
            : scrollable;

    return SafeArea(
      child: Listener(
        onPointerDown: (_) => _isPointerDown = true,
        onPointerMove: (e) {
          if (widget.onRefresh == null) return;
          if (!_scrollController.hasClients) return;
          final atTop =
              _scrollController.position.pixels <=
              _scrollController.position.minScrollExtent + 0.5;
          if (!atTop) return;
          // 손가락을 아래로 움직일 때만 누적 (dy > 0)
          if (e.delta.dy > 0) {
            final double delta = e.delta.dy * 0.1; // 민감도
            _pullExtentPx = (_pullExtentPx + delta).clamp(0.0, 160.0);
            _passedTrigger = _pullExtentPx >= _refreshTrigger;
            setState(() {});
          }

          if (e.delta.dy < 0) {
            // 위로 올리면 게이지가 감소하도록 음수 값을 더해 감소 처리
            _pullExtentPx = (_pullExtentPx + e.delta.dy * 0.9).clamp(
              0.0,
              160.0,
            );
            _passedTrigger = _pullExtentPx >= _refreshTrigger;
            setState(() {});
          }
        },
        onPointerUp: (_) async {
          _isPointerDown = false;
          if (widget.onRefresh != null && _passedTrigger) {
            setState(() {});
            try {
              await widget.onRefresh!();
            } finally {
              _pullExtentPx = 0.0;
              _passedTrigger = false;
              if (mounted) setState(() {});
            }
          } else {
            if (_pullExtentPx > 0.0) {
              _pullExtentPx = 0.0;
              _passedTrigger = false;
              if (mounted) setState(() {});
              // 제자리로 스크롤 복귀 애니메이션
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.minScrollExtent,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              }
            }
          }
        },
        onPointerCancel: (_) => _isPointerDown = false,
        child: Stack(
          children: [
            content,
            if (widget.onRefresh != null && _pullExtentPx > 0.0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 72,
                child: IgnorePointer(
                  child: Center(
                    child: _RefreshGauge(
                      progress: (_pullExtentPx / _refreshTrigger).clamp(
                        0.0,
                        1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    // 스케일은 AnimatedBuilder 안에서 PageController.page 기반으로 계산합니다

    final content = GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 340),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            opaque: false,
            pageBuilder:
                (_, __, ___) => PostReaderScreen(
                  exported: post.toExportedData(),
                  heroTag: 'post-hero-${post.id}-$index',
                ),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              // 부드러운 페이드 인/아웃과 스케일 효과
              const begin = Offset(0.0, 0.1);
              const end = Offset.zero;
              const curve = Curves.easeOutCubic;

              var tween = Tween(
                begin: begin,
                end: end,
              ).chain(CurveTween(curve: curve));

              var offsetAnimation = animation.drive(tween);
              var fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              );

              return FadeTransition(
                opacity: fadeAnimation,
                child: SlideTransition(position: offsetAnimation, child: child),
              );
            },
          ),
        );
      },

      onDoubleTap: () async {
        final id = post.id.toString();
        if (id.isEmpty) {
          print('[PostList] 유효하지 않은 포스트 ID: $id');
          return;
        }

        if (_likingInFlight.contains(id)) return;
        setState(() => _likingInFlight.add(id));

        try {
          await _likeService.togglePostLike(id);
          // setState() 제거 - LikeService의 notifyListeners()가 자동으로 UI 업데이트
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('좋아요 처리 중 오류가 발생했습니다 $e'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(milliseconds: 900),
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _likingInFlight.remove(id));
          }
        }
      },
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, child) {
          final double pageNow =
              _pageController.hasClients
                  ? (_pageController.page ?? _currentIndex.toDouble())
                  : _currentIndex.toDouble();
          final double ad = (pageNow - index).abs().clamp(0.0, 1.0);
          final double t = 1.0 - ad;
          // 커브로 더 부드럽게, 변화폭 크게 (0.85 ~ 1.0)
          final double eased = Curves.easeOutCubic.transform(t);
          final double scale = 0.85 + 0.15 * eased;
          return Transform.scale(scale: scale, child: child);
        },
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child:
                    widget.showCardShimmer
                        ? _buildImageAreaShimmer()
                        : PostCard(
                          containerWidth: widget.containerWidth,
                          thumbnailImageUrl: post.thumbnailImageUrl,
                          heroTag: 'post-hero-${post.id}-$index',
                          title: post.title,
                          author: post.author,
                          authorProfileImageUrl: post.authorProfileImageUrl,
                          content: post.parsedContent,
                          isVisible: _currentIndex == index,
                          postId: post.id.toString(),
                          isLiked: _likeService.isPostLiked(post.id.toString()),
                          likeCount: _likeService.getPostLikeCount(
                            post.id.toString(),
                          ),
                          onLikePressed: () async {
                            final id = post.id.toString();
                            if (id.isEmpty) {
                              print('[PostList] 유효하지 않은 포스트 ID: $id');
                              return;
                            }

                            if (_likingInFlight.contains(id)) return;
                            setState(() => _likingInFlight.add(id));

                            try {
                              await _likeService.togglePostLike(id);
                              // setState() 제거 - LikeService의 notifyListeners()가 자동으로 UI 업데이트
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('좋아요 처리 중 오류가 발생했습니다'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(milliseconds: 900),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _likingInFlight.remove(id));
                              }
                            }
                          },
                        ),
              ),
            ),
          ],
        ),
      ),
    );
    return content;
  }

  Widget _buildImageAreaShimmer() {
    // PostCard의 이미지 영역과 동일 크기로 보이도록, 이미지 자체만 쉬머 느낌으로
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceVariant,
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ShimmerBox(
          width: double.infinity,
          height: double.infinity,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildStickyAuthor(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const SizedBox.shrink();
    }
    final safeIndex = _currentIndex.clamp(0, widget.posts.length - 1);
    final post = widget.posts[safeIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 제목
          Text(
            post.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 38,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // 내용 (남은 공간 모두 사용)
          Expanded(
            child: Text(
              post.parsedContent,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.w300,
                height: 1.8,
                letterSpacing: -0.1,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshGauge extends StatelessWidget {
  final double progress; // 0.0 ~ 1.0
  const _RefreshGauge({required this.progress});

  @override
  Widget build(BuildContext context) {
    final double size = 26;
    final Color track = Colors.white.withOpacity(0.18);
    final Color fill = Colors.white.withOpacity(0.9);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(progress: progress, track: track, fill: fill),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color fill;

  _GaugePainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..color = track;

    // 배경 트랙
    canvas.drawCircle(center, radius, stroke);

    // 진행 아크
    final progressPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..color = fill;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -3.1415926 / 2; // 12시 방향
    final sweep = 2 * 3.1415926 * progress;
    canvas.drawArc(rect, startAngle, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.track != track ||
        oldDelegate.fill != fill;
  }
}
