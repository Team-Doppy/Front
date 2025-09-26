// import 'dart:math';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';

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

  @override
  void initState() {
    super.initState();
    // 전체 화면 사용 (인스타그램 릴스 스타일)
    _pageController = PageController(viewportFraction: 0.88);
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
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _printLarge(String text, {int chunkSize = 800}) {
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      debugPrint(text.substring(i, end));
    }
  }

  void _printJsonFull(dynamic data) {
    try {
      final json = const JsonEncoder.withIndent('  ').convert(data);
      _printLarge(json);
    } catch (_) {
      _printLarge(data.toString());
    }
  }

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

          final post = widget.posts[index];
          return _buildPostItem(context, post, index);
        },
      ),
    );

    // 헤더(작가 프로필/이름) + 본문(PageView)를 컬럼으로 분리하여 겹침 제거
    final double topInset = MediaQuery.of(context).padding.top;

    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(24, topInset + 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildTopRightAvatar(context), _buildStickyAuthor(context)],
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
      children: [header, Expanded(child: contentWithRefresh)],
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
    // 이웃 카드가 완전히 사라지지 않도록 최소 0.35 유지
    double opacity = 0.35 + 0.65 * proximity;
    // 멀수록 블러(최대 6) – 카드 존재감만 암시
    double blur = (1.0 - proximity) * 2.0;

    return GestureDetector(
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

      onDoubleTap: () {
        debugPrint('double tap');
        _printJsonFull(post.toServerLikeMap());
      },
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Center(
            child: AspectRatio(
              aspectRatio: 9 / 14,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: PostCard(
                  containerWidth: widget.containerWidth,
                  thumbnailImageUrl: post.thumbnailImageUrl,
                  heroTag: 'post-hero-${post.id}-$index',
                  title: post.title,
                  author: post.author,
                  authorProfileImageUrl: post.authorProfileImageUrl,
                  content: post.parsedContent,
                  isVisible: _currentIndex == index,
                ),
              ),
            ),
          ),
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
    final alias = '@${post.author.toLowerCase()}';

    return Column(
      key: ValueKey('author-${post.id}-$safeIndex'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          post.author,
          textAlign: TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          alias,
          textAlign: TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildTopRightAvatar(BuildContext context) {
    if (widget.posts.isEmpty) return const SizedBox.shrink();
    final safeIndex = _currentIndex.clamp(0, widget.posts.length - 1);
    final post = widget.posts[safeIndex];
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(60),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(60),
        child:
            (post.authorProfileImageUrl.isNotEmpty)
                ? Image.network(
                  post.authorProfileImageUrl,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                )
                : Container(
                  color: Colors.white,
                  child: const Icon(Icons.person, color: Colors.black54),
                ),
      ),
    );
  }
}
