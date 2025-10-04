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
  final Function(int)? onPageChanged;

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.onRefresh,
    this.onPageChanged,
  });

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  late PageController _pageController;
  int _currentIndex = 0;
  late List<PostData> _items;
  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();

  @override
  void initState() {
    super.initState();
    // 전체 화면 사용 (인스타그램 릴스 스타일)
    _pageController = PageController(viewportFraction: 0.85);
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
    _pageController.dispose();
    super.dispose();
  }

  // debug helpers 제거 (미사용)

  @override
  Widget build(BuildContext context) {
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 120, top: 20),
      child: Stack(
        children: [
          contentWithRefresh,
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: _buildStickyAuthor(context),
          ),
        ],
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
          ],
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

    // 디버그 로그 추가
    print(
      '_buildStickyAuthor: _currentIndex=$_currentIndex, safeIndex=$safeIndex, post.title=${post.title}',
    );

    return Padding(
      padding: const EdgeInsets.only(right: 20, left: 5),
      child: Column(
        key: ValueKey('author-${post.id}-$safeIndex'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            post.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

          Text(
            post.parsedContent,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w300,
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
