import 'dart:ui' as ui;
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/utils/network_utils.dart';
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
  final bool showAppBar; // 앱바 표시 여부
  final String? sectionLabel; // 섹션 레이블 (친구글/전체글)
  final double appBarOpacity; // 앱바 추가 투명도 (섹션 전환 시 페이드 효과)
  final NetworkError? networkError; // 네트워크 에러 상태
  final VoidCallback? onRetryError; // 에러 재시도 콜백

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
    this.showAppBar = true, // 기본값은 true (기존 동작 유지)
    this.sectionLabel,
    this.appBarOpacity = 1.0, // 기본값은 1.0 (완전 불투명)
    this.networkError, // 네트워크 에러 상태
    this.onRetryError, // 에러 재시도 콜백
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

  double _gestureAccumY = 0.0;
  double _gestureAccumX = 0.0;
  bool _isGestureActive = false;
  bool _isHorizontalGesture = false; // 가로 제스처 감지 여부
  double _pullProgress = 0.0; // 당기는 진행률 (0.0 ~ 1.0)
  double _verticalSwipeThreshold = 500.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
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
      print(
        '📝 PostList 업데이트: 기존 ${_items.length}개 → 새로운 ${widget.posts.length}개',
      );

      // 새로운 포스트가 추가된 경우 (기존보다 길이가 길어짐)
      if (widget.posts.length > _items.length) {
        // 기존 _items에 새로운 포스트들만 추가
        final newPosts = widget.posts.skip(_items.length).toList();
        _items.addAll(newPosts);
        _loadLikeStatusForNewPosts(newPosts);
        print('➕ 새로운 포스트 ${newPosts.length}개 추가됨');
      } else {
        // 완전히 새로운 목록인 경우 (길이가 같거나 짧아짐)
        _items = List<PostData>.from(widget.posts);
        _loadLikeStatusForAllPosts();
        print('🔄 완전히 새로운 포스트 목록으로 교체');
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

  Widget _buildScrollView(BuildContext context) {
    return CustomScrollView(
      controller: _scrollController,
      physics:
          _isHorizontalGesture
              ? const NeverScrollableScrollPhysics() // 가로 제스처 시 스크롤 차단
              : const AlwaysScrollableScrollPhysics(),
      slivers: [
        // AppBar (조건부 표시)
        if (widget.showAppBar)
          SliverAppBar(
            toolbarHeight: 35,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            pinned: false,
            floating: true,
            snap: false,
            title: AnimatedOpacity(
              opacity: (1.0 - _pullProgress) * widget.appBarOpacity,
              duration:
                  _pullProgress != 0.0
                      ? Duration(milliseconds: 0)
                      : Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              child: Text(
                ' Doppy',
                style: GoogleFonts.notoSansKr(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              // 검색 중이면 검색어 칩, 아니면 필터 아이콘
              AnimatedOpacity(
                opacity: (1.0 - _pullProgress) * widget.appBarOpacity,
                duration: Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child:
                    widget.isShowingSearchResults &&
                            widget.searchQuery.isNotEmpty
                        ? GestureDetector(
                          onTap: widget.onSearchChipTap,
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
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
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        widget.searchQuery,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        : Padding(
                          padding: const EdgeInsets.only(right: 12, top: 10),
                          child: GestureDetector(
                            onTap: widget.onFilterTap,
                            child: Row(
                              children: [
                                if (widget.sectionLabel != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      widget.sectionLabel!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.8),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                                SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.8),
                                ),
                              ],
                            ),
                          ),
                        ),
              ),
            ],
          ),
        SliverToBoxAdapter(
          child: Container(
            height: 30,
            decoration: BoxDecoration(color: Colors.transparent),
          ),
        ),

        // PageView 또는 빈 상태
        SliverToBoxAdapter(
          child: Container(
            height: 400,
            decoration: BoxDecoration(color: Colors.transparent),
            child:
                _items.isEmpty && !widget.showCardShimmer
                    ? _buildEmptyState(context)
                    : PageView.builder(
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
                            index >= _items.length - 2 &&
                            !widget.isLoadingMore) {
                          print(
                            '🔄 로드 모어 실행! 현재 인덱스: $index, 전체 아이템: ${_items.length}',
                          );
                          widget.onLoadMore!();
                        }
                      },
                      itemCount: _items.length + (widget.isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          // 로딩 인디케이터
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 16),
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
          ),
        ),

        // Author Section
        SliverFillRemaining(
          hasScrollBody: false,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (details) {
              _gestureAccumY = 0.0;
              _gestureAccumX = 0.0;
              _isGestureActive = true;
              _isHorizontalGesture = false;
            },
            onPointerMove: (details) {
              if (!_isGestureActive) return;

              // 제스처 방향 결정 (더 빠르게, 더 민감하게)
              if (!_isHorizontalGesture) {
                _gestureAccumY += details.delta.dy;
                _gestureAccumX += details.delta.dx;

                // 제스처 방향 빠르게 결정 (3px 이상 움직임 시)
                if (_gestureAccumX.abs() > 3 || _gestureAccumY.abs() > 3) {
                  // 가로 움직임이 세로보다 크면 가로 제스처로 고정
                  if (_gestureAccumX.abs() > _gestureAccumY.abs()) {
                    setState(() {
                      _isHorizontalGesture = true;
                    });
                    print('🔄 가로 제스처 감지! 세로 완전 차단');
                  }
                }
              }

              // 가로 제스처가 활성화되면 세로 누적값 무시
              if (_isHorizontalGesture) {
                _gestureAccumX += details.delta.dx;
                // 세로 움직임은 완전히 무시 (누적하지 않음)

                // 수평 스크롤만 처리
                if (_gestureAccumX.abs() > 30) {
                  if (_gestureAccumX > 0 && _currentIndex > 0) {
                    // 오른쪽으로 스크롤 - 이전 페이지
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                    );
                    _isGestureActive = false;
                  } else if (_gestureAccumX < 0 &&
                      _currentIndex < _items.length - 1) {
                    // 왼쪽으로 스크롤 - 다음 페이지
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                    );
                    _isGestureActive = false;
                  }
                }
                return; // 세로 동작 완전 차단
              }

              // 세로 제스처 처리 (가로가 아닐 때만)
              _gestureAccumY += details.delta.dy;

              // 위로 스와이프 감지 (섹션 전환용)
              if (_gestureAccumY < -_verticalSwipeThreshold &&
                  widget.onFilterTap != null) {
                print(
                  '⬆️ Listener로 위로 스와이프 감지! 섹션 전환 (임계값: $_verticalSwipeThreshold)',
                );
                widget.onFilterTap!();
                _isGestureActive = false;
                return;
              }
            },
            onPointerUp: (details) {
              setState(() {
                _isGestureActive = false;
                _isHorizontalGesture = false;
              });
              _gestureAccumY = 0.0;
              _gestureAccumX = 0.0;
            },
            child: GestureDetector(
              onTapUp: (details) {
                // 텍스트 영역에서도 탭 위치에 따라 다른 동작
                final screenWidth = MediaQuery.of(context).size.width;
                final tapX = details.globalPosition.dx;

                if (tapX < screenWidth * 0.3) {
                  // 왼쪽 30% - 이전 페이지
                  if (_currentIndex > 0) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else if (tapX > screenWidth * 0.7) {
                  // 오른쪽 30% - 다음 페이지
                  if (_currentIndex < _items.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else {
                  // 중앙 40% - 포스트 상세보기
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 340),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 100,
                      ),
                      opaque: false,
                      pageBuilder:
                          (_, __, ___) => PostReaderScreen(
                            exported: _items[_currentIndex].toExportedData(),
                            heroTag:
                                'post-hero-${_items[_currentIndex].id}-$_currentIndex',
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
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
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
              },
              child: Container(
                decoration: BoxDecoration(color: Colors.transparent),
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  opacity: widget.appBarOpacity,
                  child: _textArea(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomRefreshIndicator(
        top: 50,
        onRefresh: widget.onRefresh,
        onPullProgress: (progress) {
          setState(() {
            _pullProgress = progress;
          });
        },
        child: _buildScrollView(context),
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    return GestureDetector(
      onTapUp: (details) {
        // 탭 위치에 따라 다른 동작
        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = details.globalPosition.dx;

        if (tapX < screenWidth * 0.3) {
          // 왼쪽 30% - 이전 페이지
          if (_currentIndex > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        } else if (tapX > screenWidth * 0.7) {
          // 오른쪽 30% - 다음 페이지
          if (_currentIndex < _items.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        } else {
          // 중앙 40% - 포스트 상세보기
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
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
            ),
          );
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
          final double eased = Curves.easeOutCubic.transform(t);
          final double scale = 0.85 + 0.15 * eased;
          return Transform.scale(scale: scale, child: child);
        },
        child: Center(
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
                        if (id.isEmpty) return;

                        if (_likingInFlight.contains(id)) return;
                        setState(() => _likingInFlight.add(id));

                        try {
                          await _likeService.togglePostLike(id);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('좋아요 처리 중 오류가 발생했습니다'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(milliseconds: 900),
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

  Widget _buildEmptyState(BuildContext context) {
    // 현재 탭에 따른 메시지 결정
    String message;
    String subtitle;
    IconData icon;
    bool showRecommendButton = false;

    if (widget.isShowingFriendsOnly) {
      message = "친구들의 글이 아직 없어요";
      subtitle = "친구들이 첫 번째 글을 올릴 때까지 기다려보세요!";
      icon = Icons.people_outline;
      showRecommendButton = true; // 친구글 탭에서만 추천글 버튼 표시
    } else {
      message = "아직 글이 없어요";
      subtitle = "새로운 글들이 곧 올라올 거예요!";
      icon = Icons.article_outlined;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),

          // 추천글 보러가기 버튼 (친구글 탭에서만 표시)
          if (showRecommendButton) ...[
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () {
                // 전체글 탭으로 전환 (위로 스와이프와 동일한 동작)
                if (widget.onFilterTap != null) {
                  widget.onFilterTap!();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '추천글 보러가기',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textArea(BuildContext context) {
    if (_items.isEmpty) {
      // 빈 상태일 때는 빈 공간 표시
      return const SizedBox.shrink();
    }
    final safeIndex = _currentIndex.clamp(0, _items.length - 1);
    final post = _items[safeIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: 10),
          // 제목
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
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
