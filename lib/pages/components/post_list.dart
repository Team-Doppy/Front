// import 'dart:math';
import 'dart:async';
import 'package:doppy/pages/components/common_profile_avatar.dart';
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
  static const double _refreshTrigger = 200.0; // 트리거 거리(더 둔감하게)
  bool _passedTrigger = false; // 임계치 통과 여부 (릴리즈 시점 확인용)
  // 스와이프 방향 판정 및 데드존 처리용
  double _accumDx = 0.0;
  double _accumDy = 0.0;
  bool? _isVerticalDrag; // null: 미정, true: 수직, false: 수평
  static const double _deadZonePx = 150.0; // 150px 이전에는 게이지 표시/증가 억제

  // 제스처 감지용 변수들
  double _gestureStartY = 0.0;
  double _gestureAccumY = 0.0;
  bool _isGestureActive = false;

  // 연속 스크롤용 변수들
  bool _isContinuousScroll = false;
  Timer? _continuousScrollTimer;
  Timer? _continuousScrollDelayTimer;
  double _pointerX = 0.0; // 손의 X 위치 추적
  double _screenCenter = 0.0; // 화면 중앙 위치

  @override
  void initState() {
    super.initState();
    // 전체 화면 사용 (인스타그램 릴스 스타일)
    _pageController = PageController(viewportFraction: 0.65);
    _items = List<PostData>.from(widget.posts);

    // 화면 중앙 위치 설정 (didChangeDependencies에서 업데이트됨)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _screenCenter = MediaQuery.of(context).size.width / 2;
      }
    });

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
    _continuousScrollTimer?.cancel();
    _continuousScrollDelayTimer?.cancel();
    super.dispose();
  }

  // 연속 스크롤 메서드
  void _startContinuousScroll(bool isNext) {
    // 이미 연속 스크롤이 진행 중이면 중단
    if (_isContinuousScroll) return;

    // 지연 타이머 취소
    _continuousScrollDelayTimer?.cancel();

    // 300ms 후에 연속 스크롤 시작 사용자가 손을 300ms 동안 유지했을 때 연속 스크롤을 시작
    _continuousScrollDelayTimer = Timer(const Duration(milliseconds: 100), () {
      _continuousScrollTimer?.cancel();
      _isContinuousScroll = true;

      //200ms마다 페이지를 이동 (100ms 애니메이션으로)
      _continuousScrollTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (timer) {
          if (!_isContinuousScroll) {
            timer.cancel();
            return;
          }

          // 현재 페이지 인덱스를 PageController에서 직접 가져옴
          final currentPage = _pageController.page?.round() ?? _currentIndex;

          if (isNext && currentPage < widget.posts.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
            );
          } else if (!isNext && currentPage > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
            );
          } else {
            timer.cancel();
            _isContinuousScroll = false;
          }
        },
      );
    });
  }

  void _stopContinuousScroll() {
    _continuousScrollTimer?.cancel();
    _continuousScrollDelayTimer?.cancel();
    _isContinuousScroll = false;
  }

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
          height: MediaQuery.of(context).size.height * 0.5,
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
                // 스크롤 종료/유휴 시 임계 미만이면 리셋
                if (n is ScrollEndNotification ||
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
        onPointerDown: (_) {
          _isPointerDown = true;
          _accumDx = 0.0;
          _accumDy = 0.0;
          _isVerticalDrag = null;
        },
        onPointerMove: (e) {
          // 연속 스크롤 중이면 방향 변경 무시
          if (_isContinuousScroll) {
            return;
          }

          // 방향 판정: 누적 방식으로 안정적인 감지
          _accumDx += e.delta.dx.abs();
          _accumDy += e.delta.dy.abs();

          // 가로 스크롤 우선 감지 (페이지 이동)
          if (_accumDx > _accumDy * 1.2 && _accumDx > 15.0) {
            if (e.delta.dx > 0 && _currentIndex > 0) {
              // 오른쪽으로 스크롤 - 이전 페이지
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              // 연속 스크롤 시작 (이전 페이지)
              _startContinuousScroll(false);
            } else if (e.delta.dx < 0 &&
                _currentIndex < widget.posts.length - 1) {
              // 왼쪽으로 스크롤 - 다음 페이지
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              // 연속 스크롤 시작 (다음 페이지)
              _startContinuousScroll(true);
            }
            return; // 가로 스크롤 감지 시 세로 스크롤 처리 완전 중단
          } else {
            // 가로 스크롤이 아닐 때 연속 스크롤 중단
            _stopContinuousScroll();
          }

          // 세로 스크롤 감지 (새로고침) - 가로 스크롤이 아닐 때만
          if (widget.onRefresh == null) return;
          if (!_scrollController.hasClients) return;
          final atTop =
              _scrollController.position.pixels <=
              _scrollController.position.minScrollExtent + 0.5;
          if (!atTop) return;

          if (_isVerticalDrag == null) {
            if (_accumDy > _accumDx * 2.0 && _accumDy > 10.0) {
              _isVerticalDrag = true;
            } else if (_accumDx > _accumDy * 1.2 && _accumDx > 15.0) {
              _isVerticalDrag = false;
            }
          }
          if (_isVerticalDrag == true) {
            double delta = 0.0;
            if (e.delta.dy > 0) {
              delta = e.delta.dy * 0.4; // 둔감한 증가
            } else if (e.delta.dy < 0) {
              delta = e.delta.dy * 0.6; // 감소는 빠르게
            }
            if (delta != 0.0) {
              _pullExtentPx = (_pullExtentPx + delta).clamp(0.0, 200.0);
              _passedTrigger = _pullExtentPx >= _refreshTrigger;
              setState(() {});
            }
          }
        },
        onPointerUp: (_) async {
          _isPointerDown = false;
          _stopContinuousScroll(); // 연속 스크롤 중단
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
            if (widget.onRefresh != null && (_pullExtentPx - _deadZonePx) > 0.0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 72,
                child: IgnorePointer(
                  child: Center(
                    child: _RefreshGauge(
                      progress: (((_pullExtentPx - _deadZonePx) /
                              (_refreshTrigger - _deadZonePx))
                          .clamp(0.0, 1.0)),
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
        /*
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
        }*/
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        _gestureStartY = details.globalPosition.dy;
        _gestureAccumY = 0.0;
        _isGestureActive = true;
      },
      onPanUpdate: (details) {
        if (!_isGestureActive) return;

        _gestureAccumY += details.delta.dy;

        // 누적된 수직 움직임이 50px 이상일 때 페이지 이동
        if (_gestureAccumY.abs() > 50) {
          if (_gestureAccumY > 0 && _currentIndex > 0) {
            // 아래로 스크롤 - 이전 페이지
            _pageController.previousPage(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            _isGestureActive = false; // 제스처 비활성화
          } else if (_gestureAccumY < 0 &&
              _currentIndex < widget.posts.length - 1) {
            // 위로 스크롤 - 다음 페이지
            _pageController.nextPage(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
            _isGestureActive = false; // 제스처 비활성화
          }
        }
      },
      onPanEnd: (details) {
        _isGestureActive = false;
        _gestureAccumY = 0.0;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // 제목
            IgnorePointer(
              child: Text(
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
            ),

            // 내용 (남은 공간 모두 사용)
            Expanded(
              child: IgnorePointer(
                child: Text(
                  post.parsedContent,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    height: 1.8,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
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
