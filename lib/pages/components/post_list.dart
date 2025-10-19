import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

class PostList extends StatefulWidget {
  final double containerWidth;
  final List<PostData> posts;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  final Future<void> Function()? onRefresh;
  final Function(int)? onPageChanged;
  final bool showCardShimmer;

  // 홈화면 앱바 관련 파라미터들
  final bool isShowingSearchResults;
  final String searchQuery;
  final VoidCallback? onSearchChipTap;
  final VoidCallback? onClearSearch;
  final bool isShowingFriendsOnly;
  final VoidCallback? onFilterTap;

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.onRefresh,
    this.onPageChanged,
    this.showCardShimmer = false,
    this.isShowingSearchResults = false,
    this.searchQuery = '',
    this.onSearchChipTap,
    this.onClearSearch,
    this.isShowingFriendsOnly = false,
    this.onFilterTap,
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
  static const double _deadZonePx = 80.0; // 80px 이전에는 게이지 표시/증가 억제

  double _gestureAccumY = 0.0;
  double _gestureStartX = 0.0; // 탭 시작 X 위치
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

    // 새로고침 당김 정도에 따른 투명도 계산 (가파른 속도)
    final double pullOpacity =
        (_pullExtentPx - _deadZonePx) > 0.0
            ? (1.0 -
                math
                    .pow(
                      (_pullExtentPx - _deadZonePx) /
                          (_refreshTrigger - _deadZonePx),
                      0.5,
                    )
                    .clamp(0.0, 1.0))
            : 1.0;

    slivers.add(
      SliverAppBar(
        toolbarHeight: 40,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        pinned: false,
        floating: true,
        snap: false,
        title: AnimatedOpacity(
          opacity: pullOpacity,
          duration: const Duration(milliseconds: 100),
          child: Text(
            ' Doppy',
            style: GoogleFonts.notoSansKr(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          // 검색 중이면 검색어 칩 + 아이콘, 아니면 검색 아이콘만
          if (widget.isShowingSearchResults && widget.searchQuery.isNotEmpty)
            AnimatedOpacity(
              opacity: pullOpacity,
              duration: const Duration(milliseconds: 100),
              child: GestureDetector(
                onTap: widget.onSearchChipTap,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.searchQuery,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: widget.onClearSearch,
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else ...[
            // 피드 필터 드롭다운
            AnimatedOpacity(
              opacity: pullOpacity,
              duration: const Duration(milliseconds: 100),
              child: IconButton(
                onPressed: widget.onFilterTap,
                icon: Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ],
      ),
    );
    SliverToBoxAdapter(child: SizedBox(height: 30));

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
        onPointerDown: (details) {
          print('onPointerDown');
          print(details.position.dy);
          // 앱바 영역(상단 80px)에서는 포인터 이벤트 무시
          if (details.position.dy < 250) {
            print('onPointerDown - 앱바 영역 무시');
            return;
          }

          print('onPointerDown');
          _isPointerDown = true;
          _accumDx = 0.0;
          _accumDy = 0.0;
          _isVerticalDrag = null;
          _gestureStartX = details.position.dx; // 탭 시작 위치 저장
        },
        onPointerMove: (e) {
          print('onPointerMove');
          // 앱바 영역(상단 80px)에서는 포인터 이벤트 무시
          if (e.position.dy < 250) {
            return;
          }

          // 연속 스크롤 중이면 방향 변경 무시
          if (_isContinuousScroll) {
            return;
          }

          // 방향 판정: 누적 방식으로 안정적인 감지
          _accumDx += e.delta.dx.abs();
          _accumDy += e.delta.dy.abs();

          // 방향이 아직 결정되지 않았을 때만 방향 판정
          if (_isVerticalDrag == null) {
            if (_accumDy > _accumDx * 2.0 && _accumDy > 10.0) {
              _isVerticalDrag = true; // 세로 드래그로 결정
            } else if (_accumDx > _accumDy * 1.2 && _accumDx > 15.0) {
              _isVerticalDrag = false; // 가로 드래그로 결정
            }
          }

          // 세로 드래그가 결정된 경우 가로 스크롤 완전 차단
          if (_isVerticalDrag == true) {
            // 세로 스크롤 감지 (새로고침)
            if (widget.onRefresh == null) return;
            if (!_scrollController.hasClients) return;
            final atTop =
                _scrollController.position.pixels <=
                _scrollController.position.minScrollExtent + 0.5;
            if (!atTop) return;

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
            return; // 세로 드래그 중에는 가로 스크롤 완전 차단
          }

          // 가로 드래그가 결정된 경우에만 페이지 이동 처리
          if (_isVerticalDrag == false) {
            if (e.delta.dx > 0 && _currentIndex > 0) {
              // 오른쪽으로 스크롤 - 이전 페이지
              _pageController.previousPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            } else if (e.delta.dx < 0 &&
                _currentIndex < widget.posts.length - 1) {
              // 왼쪽으로 스크롤 - 다음 페이지
              _pageController.nextPage(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
            return; // 가로 스크롤 감지 시 세로 스크롤 처리 완전 중단
          }
        },
        onPointerUp: (details) async {
          // 앱바 영역(상단 80px)에서는 포인터 이벤트 무시
          if (details.position.dy < 80) {
            print('onPointerUp - 앱바 영역 무시');
            _isPointerDown = false;
            _isVerticalDrag = null;
            _accumDx = 0.0;
            _accumDy = 0.0;
            return;
          }

          // 탭인지 스와이프인지 판단
          // 1. 움직임이 5px 미만이어야 함 (거의 안 움직임)
          // 2. 방향이 결정되지 않았어야 함 (스와이프로 인식되지 않음)
          final isTap =
              _accumDx < 5.0 && _accumDy < 5.0 && _isVerticalDrag == null;

          // 상태 리셋
          _isPointerDown = false;
          final wasVerticalDrag = _isVerticalDrag;
          _isVerticalDrag = null;
          _accumDx = 0.0;
          _accumDy = 0.0;

          if (isTap) {
            // 탭으로 판단 - 화면 좌우에 따라 페이지 이동
            final screenWidth = MediaQuery.of(context).size.width;
            final tapX = _gestureStartX;

            if (tapX < screenWidth * 0.3) {
              // 왼쪽 30% - 이전 페이지
              if (_currentIndex > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                );
              }
            } else if (tapX > screenWidth * 0.7) {
              // 오른쪽 30% - 다음 페이지
              if (_currentIndex < widget.posts.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                );
              }
            } else {
              // 중앙 40% - 포스트 상세보기
              final safeIndex = _currentIndex.clamp(0, widget.posts.length - 1);
              final post = _items[safeIndex];
              Navigator.of(context).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 340),
                  reverseTransitionDuration: const Duration(milliseconds: 100),
                  opaque: false,
                  pageBuilder:
                      (_, __, ___) => PostReaderScreen(
                        exported: post.toExportedData(),
                        heroTag: 'post-hero-${post.id}-$safeIndex',
                      ),
                  transitionsBuilder: (
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ) {
                    const begin = Offset(0.0, 0.1);
                    const end = Offset.zero;
                    const curve = Curves.easeOutCubic;
                    var tween = Tween(
                      begin: begin,
                      end: end,
                    ).chain(CurveTween(curve: curve));
                    var offsetAnimation = animation.drive(tween);
                    var fadeAnimation = Tween<double>(
                      begin: 0.0,
                      end: 1.0,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    );
                    return FadeTransition(
                      opacity: fadeAnimation,
                      child: SlideTransition(
                        position: offsetAnimation,
                        child: child,
                      ),
                    );
                  },
                ),
              );
            }
            return;
          }

          // 스와이프인 경우 - 새로고침 처리 (세로 드래그가 확정된 경우에만)
          if (wasVerticalDrag == true &&
              widget.onRefresh != null &&
              _passedTrigger) {
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
                top: 30,
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
    // 탭 처리는 Listener의 onPointerUp에서 처리

    final content = GestureDetector(
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

class _RefreshGauge extends StatefulWidget {
  final double progress; // 0.0 ~ 1.0
  const _RefreshGauge({required this.progress});

  @override
  State<_RefreshGauge> createState() => _RefreshGaugeState();
}

class _RefreshGaugeState extends State<_RefreshGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController);

    // 새로고침이 진행 중일 때만 회전
    if (widget.progress > 0) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(_RefreshGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress > 0 && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (widget.progress == 0 && _animationController.isAnimating) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = 40;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _rotationAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: _SpinnerPainter(
              progress: widget.progress,
              rotation: _rotationAnimation.value,
            ),
          );
        },
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double progress;
  final double rotation;

  _SpinnerPainter({required this.progress, required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // 회전 변환 적용
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 2 * math.pi); // 전체 회전
    canvas.translate(-center.dx, -center.dy);

    // 12개의 막대를 그리기
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30.0) * (math.pi / 180.0); // 각 막대의 각도
      final opacity = _calculateOpacity(i, progress);

      final paint =
          Paint()
            ..color = Colors.white.withOpacity(opacity)
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round;

      // 막대의 시작점과 끝점 계산
      final startRadius = radius * 0.6;
      final endRadius = radius * 0.9;

      final startX = center.dx + startRadius * math.cos(angle);
      final startY = center.dy + startRadius * math.sin(angle);
      final endX = center.dx + endRadius * math.cos(angle);
      final endY = center.dy + endRadius * math.sin(angle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    canvas.restore();
  }

  double _calculateOpacity(int barIndex, double progress) {
    // 진행률에 따라 막대들의 투명도 계산
    // 12시 방향부터 시계방향으로 점진적으로 밝아지다가 어두워짐
    final normalizedProgress = progress * 12; // 0~12 범위로 변환
    final distance = (barIndex - normalizedProgress).abs();

    // 최소 거리 계산 (원형이므로 12를 넘어가면 반대편으로)
    final minDistance = math.min(distance, 12 - distance);

    // 거리가 가까울수록 밝게, 멀수록 어둡게
    if (minDistance <= 2) {
      return 0.9 - (minDistance * 0.3); // 0.9 ~ 0.3
    } else if (minDistance <= 4) {
      return 0.3 - ((minDistance - 2) * 0.15); // 0.3 ~ 0.0
    } else {
      return 0.05; // 매우 어둡게
    }
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
