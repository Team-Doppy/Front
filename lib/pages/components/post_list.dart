// import 'dart:math';
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';

class PostList extends StatefulWidget {
  final double containerWidth;
  final List<PostData> posts;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  final Future<void> Function()? onRefresh;

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.onRefresh,
  });

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isScrolling = false;
  double _page = 0.0;
  late List<PostData> _items;
  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();

  @override
  void initState() {
    super.initState();
    // 전체 화면 사용 (인스타그램 릴스 스타일)
    _pageController = PageController(viewportFraction: 0.88);
    _items = List<PostData>.from(widget.posts);
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        final current = _pageController.page ?? _currentIndex.toDouble();
        if ((current - _page).abs() > 0.0001) {
          setState(() {
            _page = current;
          });
        }
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

    // 새로운 게시물이 추가되었을 때 좋아요 상태 확인
    if (widget.posts.length > oldWidget.posts.length) {
      final newPosts = widget.posts.skip(oldWidget.posts.length).toList();
      _loadLikeStatusForNewPosts(newPosts);
    }

    // 게시물 목록이 완전히 바뀌었을 때
    if (widget.posts != oldWidget.posts) {
      _items = List<PostData>.from(widget.posts);
      _loadLikeStatusForAllPosts();
    }
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    _pageController.dispose();
    super.dispose();
  }

  // debug helpers 제거 (미사용)

  @override
  Widget build(BuildContext context) {
    Widget pageView = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // 페이지 정지 직전(정확히 맞물리기 직전)으로 가까워지면 미리 밝기 복원
          final metrics = notification.metrics;
          final viewport = metrics.viewportDimension;
          if (viewport > 0) {
            final page = metrics.pixels / viewport;
            final nearest = page.round();
            final distance = (nearest - page).abs();
            // 임계값: 0.12 페이지 이내로 접근하면 정지 취급
            if (distance < 0.12) {
              if (_isScrolling || _currentIndex != nearest) {
                setState(() {
                  _isScrolling = false;
                  // 범위 보호
                  final maxIndex = widget.posts.length - 1;
                  _currentIndex = nearest.clamp(0, maxIndex);
                });
              }
            } else {
              if (!_isScrolling) {
                setState(() {
                  _isScrolling = true;
                });
              }
            }
          }
        }
        if (notification is ScrollStartNotification) {
          if (!_isScrolling) {
            setState(() {
              _isScrolling = true;
            });
          }
        } else if (notification is ScrollEndNotification) {
          if (_isScrolling) {
            setState(() {
              _isScrolling = false;
            });
          }
        }
        return false;
      },
      child: PageView.builder(
        scrollDirection: Axis.horizontal,
        controller: _pageController,
        pageSnapping: true,

        clipBehavior: Clip.none,
        padEnds: true,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });

          // 무한 스크롤: 마지막 페이지 근처에서 더 로드
          if (widget.onLoadMore != null &&
              index >= widget.posts.length - 2 &&
              !widget.isLoadingMore) {
            widget.onLoadMore!();
          }
        },
        itemCount: widget.posts.length + (widget.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= widget.posts.length) {
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

          final post = _items[index];
          return _buildPostItem(context, post, index);
        },
      ),
    );

    // 헤더(작가 프로필/이름) + 본문(PageView)를 컬럼으로 분리하여 겹침 제거
    final double topInset = MediaQuery.of(context).padding.top;

    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(24, topInset, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildStickyAuthor(context)],
      ),
    );

    // 새로고침 기능이 있으면 RefreshIndicator로 감싸기
    Widget contentWithRefresh =
        widget.onRefresh != null
            ? RefreshIndicator(
              onRefresh: widget.onRefresh!,
              color: Colors.white,
              backgroundColor: Colors.black54,
              child: pageView,
            )
            : pageView;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        Expanded(flex: 4, child: contentWithRefresh),
        Expanded(flex: 1, child: header),
      ],
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    // 스크롤 진행도 기반 전환 효과 설정 (세로 스크롤 유지)
    final bool hasClients = _pageController.hasClients;
    final double pageNow = hasClients ? _page : _currentIndex.toDouble();
    final double delta = pageNow - index; // 현재 페이지로부터의 거리 (0이면 중앙)
    final double ad = delta.abs();

    // 심플 모드: 공존 연출 제거. 오직 축소/페이드/블러만 거리 비례로 적용
    // proximity: 0(멀리) ~ 1(정확히 중앙)
    final double proximity = (1.0 - ad).clamp(0.0, 1.0);
    // 중앙 1.0, 가장자리도 살짝 보이도록 최소 0.9 유지
    double scale = 0.90 + 0.10 * proximity;

    // 블러 제거, 스케일/페이드만 유지

    final content = GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            reverseTransitionDuration: const Duration(milliseconds: 500),
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
      child: Transform.scale(
        scale: scale,
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 12,
            child: PostCard(
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
              likeCount: _likeService.getPostLikeCount(post.id.toString()),
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
      ),
    );
    return content;
  }

  Widget _buildStickyAuthor(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const SizedBox.shrink();
    }
    final safeIndex = _currentIndex.clamp(0, widget.posts.length - 1);
    final post = widget.posts[safeIndex];

    return Padding(
      padding: const EdgeInsets.only(right: 20, left: 5),
      child: Column(
        key: ValueKey('author-${post.id}-$safeIndex'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.title,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            post.parsedContent,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
