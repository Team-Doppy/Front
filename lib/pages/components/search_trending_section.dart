import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';

class TrendingListView extends StatefulWidget {
  final List<SearchContentItem> recommendedPosts;
  final List<SearchContentItem> friendsPosts;
  final bool isLoading;
  final bool shouldShowShimmer;
  final bool friendsHasMore;
  final bool recommendedHasMore;
  final Function(String) onTapKeyword;
  final Function(SearchContentItem) onTapPost;
  final Function(int)? onPostIndexChanged;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMoreFriends;
  final VoidCallback? onLoadMoreRecommended;

  const TrendingListView({
    super.key,
    required this.recommendedPosts,
    required this.friendsPosts,
    required this.isLoading,
    required this.shouldShowShimmer,
    required this.friendsHasMore,
    required this.recommendedHasMore,
    required this.onTapKeyword,
    required this.onTapPost,
    this.onPostIndexChanged,
    this.onRefresh,
    this.onLoadMoreFriends,
    this.onLoadMoreRecommended,
  });

  @override
  State<TrendingListView> createState() => _TrendingListViewState();
}

class _TrendingListViewState extends State<TrendingListView> {
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context가 준비된 후에 이미지 프리로드 시작 (한 번만)
    if (!_hasInitialized) {
      _hasInitialized = true;
      _preloadImagesIfNeeded();
    }
  }

  @override
  void didUpdateWidget(TrendingListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // recommendedPosts가 변경되거나 shimmer 상태가 변경되면 다시 프리로드
    if (widget.recommendedPosts != oldWidget.recommendedPosts ||
        widget.shouldShowShimmer != oldWidget.shouldShowShimmer) {
      _preloadImagesIfNeeded();
    }
  }

  Future<void> _preloadImagesIfNeeded() async {
    // 이미 프리로드 중이거나 완료했으면 스킵
    // recommendedPosts가 없으면 스킵
    if (widget.recommendedPosts.isEmpty) {
      return;
    }

    // recommendedPosts가 5개 미만이면 모두, 5개 이상이면 5개만 프리로드
    final postsToPreload = widget.recommendedPosts.take(5).toList();

    // 이미지 URL 추출 (비디오 URL 제외)
    final imageUrls =
        postsToPreload
            .where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty)
            .where((post) {
              // 🎯 비디오 파일(.mp4, .mov 등) 제외 - 이미지만 프리로드
              final url = post.imageUrl!.toLowerCase();
              return !url.endsWith('.mp4') &&
                  !url.endsWith('.mov') &&
                  !url.endsWith('.avi') &&
                  !url.endsWith('.webm') &&
                  !url.contains('/videos/');
            })
            .map((post) => post.imageUrl!)
            .toList();

    if (imageUrls.isEmpty) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이미지 프리로드가 완료되지 않았어도 캐시 사용 시에는 기존 데이터 표시
    // (이미지가 로드되는 동안 기존 데이터를 보여줌)

    // 🎯 키워드와 추천 포스트 모두 없는 경우 - Sliver로 반환
    if (widget.recommendedPosts.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [],
          ),
        ),
      );
    }

    // 🎯 OTT 스타일 레이아웃 (Sliver 구조)
    final screenHeight = MediaQuery.of(context).size.height;
    final heroHeight = screenHeight * 0.5; // 화면 높이의 50%를 히어로 섹션에 할당

    // 🎯 Hero 섹션용: recommendedPosts에서 5개만 추출
    final heroPosts = widget.recommendedPosts.take(5).toList();
    // 🎯 추천글 섹션용: 나머지 15개 (5개 이후부터)
    final recommendedSectionPosts = widget.recommendedPosts.skip(5).toList();

    // 🎯 Sliver 리스트를 직접 반환 (CustomScrollView는 상위에서 처리)
    // CustomRefreshIndicator는 상위에서 처리하므로 여기서는 Sliver만 반환
    return _TrendingSliverContent(
      heroHeight: heroHeight,
      heroPosts: heroPosts,
      recommendedPosts: recommendedSectionPosts,
      friendsPosts: widget.friendsPosts,
      friendsHasMore: widget.friendsHasMore,
      recommendedHasMore: widget.recommendedHasMore,
      onPostIndexChanged: widget.onPostIndexChanged,
      onTapPost: widget.onTapPost,
      onTapKeyword: widget.onTapKeyword,
      onLoadMoreFriends: widget.onLoadMoreFriends,
      onLoadMoreRecommended: widget.onLoadMoreRecommended,
      excludeHero: true, // 🎯 Hero 섹션은 상위 SliverAppBar에서 처리하므로 제외
    );
  }
}

/// 🎯 Sliver 리스트를 반환하는 위젯 (CustomScrollView 없이 Sliver만)
class _TrendingSliverContent extends StatefulWidget {
  final double heroHeight;
  final List<SearchContentItem> heroPosts;
  final List<SearchContentItem> recommendedPosts;
  final List<SearchContentItem> friendsPosts;
  final bool friendsHasMore;
  final bool recommendedHasMore;
  final Function(int)? onPostIndexChanged;
  final Function(SearchContentItem) onTapPost;
  final Function(String) onTapKeyword;
  final VoidCallback? onLoadMoreFriends;
  final VoidCallback? onLoadMoreRecommended;
  final bool excludeHero; // 🎯 Hero 섹션 제외 여부

  const _TrendingSliverContent({
    required this.heroHeight,
    required this.heroPosts,
    required this.recommendedPosts,
    required this.friendsPosts,
    required this.friendsHasMore,
    required this.recommendedHasMore,
    this.onPostIndexChanged,
    required this.onTapPost,
    required this.onTapKeyword,
    this.onLoadMoreFriends,
    this.onLoadMoreRecommended,
    this.excludeHero = false,
  });

  @override
  State<_TrendingSliverContent> createState() => _TrendingSliverContentState();
}

class _TrendingSliverContentState extends State<_TrendingSliverContent> {
  bool _isLoadingMore = false;

  @override
  Widget build(BuildContext context) {
    // 🎯 Sliver 리스트를 반환 (CustomScrollView는 상위에서 처리)
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 스크롤이 끝에 가까우면 로드모어 실행
        if (notification is ScrollUpdateNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 500 &&
              widget.recommendedHasMore &&
              widget.onLoadMoreRecommended != null &&
              !_isLoadingMore) {
            // 스크롤이 끝에서 500px 이내에 도달하면 로드모어 실행
            setState(() {
              _isLoadingMore = true;
            });
            widget.onLoadMoreRecommended!();
            // 1초 후 플래그 리셋 (로딩 완료를 기다리지 않음)
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                setState(() {
                  _isLoadingMore = false;
                });
              }
            });
          }
        }
        return false;
      },
      child: SliverList(
        delegate: SliverChildListDelegate([
          // 🎯 위쪽: 히어로 섹션 (배경을 덮는 추천 컨텐츠) - excludeHero가 false일 때만
          if (!widget.excludeHero) ...[
            SizedBox(
              height: widget.heroHeight,
              child:
                  widget.heroPosts.isNotEmpty
                      ? _HeroSection(
                        posts: widget.heroPosts,
                        onPostIndexChanged: widget.onPostIndexChanged,
                        onTapPost: widget.onTapPost,
                      )
                      : Container(
                        color: Theme.of(context).colorScheme.background,
                      ),
            ),
          ],

          // 🎯 아래쪽: 그리드 레이아웃 (실험용)
          _GridLayoutWidget(
            friendsPosts: widget.friendsPosts,
            recommendedPosts: widget.recommendedPosts,
            friendsHasMore: widget.friendsHasMore,
            recommendedHasMore: widget.recommendedHasMore,
            onTapKeyword: widget.onTapKeyword,
            onTapPost: widget.onTapPost,
            onLoadMoreFriends: widget.onLoadMoreFriends,
            onLoadMoreRecommended: widget.onLoadMoreRecommended,
          ),
        ]),
      ),
    );
  }
}

/// 🎯 그리드 레이아웃 (실험용 - 친구글 + 추천글 합쳐서 표시)
class _GridLayoutWidget extends StatelessWidget {
  final List<SearchContentItem> friendsPosts;
  final List<SearchContentItem> recommendedPosts;
  final bool friendsHasMore;
  final bool recommendedHasMore;
  final Function(String) onTapKeyword;
  final Function(SearchContentItem) onTapPost;
  final VoidCallback? onLoadMoreFriends;
  final VoidCallback? onLoadMoreRecommended;

  const _GridLayoutWidget({
    required this.friendsPosts,
    required this.recommendedPosts,
    required this.friendsHasMore,
    required this.recommendedHasMore,
    required this.onTapKeyword,
    required this.onTapPost,
    this.onLoadMoreFriends,
    this.onLoadMoreRecommended,
  });

  @override
  Widget build(BuildContext context) {
    // 🎯 사용자 alias 가져오기
    final userProvider = context.watch<UserProvider>();
    final alias =
        userProvider.currentUser?.alias ??
        userProvider.currentUser?.username ??
        '';

    // 🎯 추천글만 사용 (friends 포스트 제외)
    final allPosts = recommendedPosts;

    if (allPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = 3; // 3열 그리드
    final spacing = 1.0;
    final padding = 0.0;
    final availableWidth =
        screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1));
    final cardWidth = availableWidth / crossAxisCount;
    final cardImageHeight = cardWidth * 1.2; // 약 4:5 비율

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 16),
            child: Text(
              '$alias님을 위한 추천',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // 그리드 레이아웃
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: 0.7, // 이미지 + 제목 영역 비율 (대략적 계산)
            ),
            itemCount:
                allPosts.length + (recommendedHasMore ? 1 : 0), // 로딩 인디케이터
            itemBuilder: (context, index) {
              if (index >= allPosts.length) {
                // 로딩 인디케이터
                return ShimmerBox(width: cardWidth, height: cardImageHeight);
              }
              final post = allPosts[index];
              return _GridCard(
                post: post,
                cardWidth: cardWidth,
                cardImageHeight: cardImageHeight,
                onTap: () => onTapPost(post),
                index: index,
                totalItems: allPosts.length + (recommendedHasMore ? 1 : 0),
                crossAxisCount: crossAxisCount,
              );
            },
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}

/// 🎯 히어로 섹션 (위쪽 큰 배경 이미지)
class _HeroSection extends StatefulWidget {
  final List<SearchContentItem> posts;
  final Function(int)? onPostIndexChanged;
  final Function(SearchContentItem) onTapPost;

  const _HeroSection({
    required this.posts,
    this.onPostIndexChanged,
    required this.onTapPost,
  });

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onPageChanged);
    // 🎯 build 중 setState 방지: 다음 프레임에 콜백 실행
    if (widget.posts.isNotEmpty && widget.onPostIndexChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onPostIndexChanged!(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final newIndex = _pageController.page?.round() ?? 0;
    if (newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
      widget.onPostIndexChanged?.call(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Container(color: Theme.of(context).colorScheme.background);
    }

    return Stack(
      children: [
        // 배경 이미지/비디오
        PageView.builder(
          controller: _pageController,
          itemCount: widget.posts.length,
          // 🎯 onPageChanged는 제거하고 PageController 리스너만 사용
          itemBuilder: (context, index) {
            final post = widget.posts[index];
            final imageUrl = post.imageUrl ?? '';

            // 비디오 URL 체크
            final isVideoUrl =
                imageUrl.toLowerCase().endsWith('.mp4') ||
                imageUrl.toLowerCase().endsWith('.mov') ||
                imageUrl.toLowerCase().endsWith('.avi') ||
                imageUrl.toLowerCase().endsWith('.webm') ||
                imageUrl.contains('/videos/');

            return GestureDetector(
              onTap: () => widget.onTapPost(post),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isVideoUrl)
                    SearchBackgroundVideoWidget(
                      videoUrl: imageUrl,
                      key: ValueKey('hero-video-$imageUrl'),
                    )
                  else if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget:
                          (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                    )
                  else
                    Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                    ),
                  // 그라데이션 오버레이
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // 페이지 인디케이터 (하단)
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.posts.length.clamp(0, 5), // 최대 5개만 표시
              (index) => Container(
                width: index == _currentIndex ? 8 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape:
                      index == _currentIndex
                          ? BoxShape.rectangle
                          : BoxShape.circle,
                  borderRadius:
                      index == _currentIndex ? BorderRadius.circular(3) : null,
                  color:
                      index == _currentIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 🎯 그리드 카드
class _GridCard extends StatelessWidget {
  final SearchContentItem post;
  final double cardWidth;
  final double cardImageHeight;
  final VoidCallback onTap;
  final int index;
  final int totalItems;
  final int crossAxisCount;

  const _GridCard({
    required this.post,
    required this.cardWidth,
    required this.cardImageHeight,
    required this.onTap,
    required this.index,
    required this.totalItems,
    required this.crossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = post.imageUrl ?? '';
    final isVideoUrl =
        imageUrl.toLowerCase().endsWith('.mp4') ||
        imageUrl.toLowerCase().endsWith('.mov') ||
        imageUrl.toLowerCase().endsWith('.avi') ||
        imageUrl.toLowerCase().endsWith('.webm') ||
        imageUrl.contains('/videos/');

    // 🎯 그리드 위치 계산
    final row = index ~/ crossAxisCount;
    final col = index % crossAxisCount;
    final totalRows = (totalItems + crossAxisCount - 1) ~/ crossAxisCount;

    // 🎯 첫 번째 행과 마지막 행의 좌우 끝부분에만 border radius 적용
    final isFirstRow = row == 0;
    final isLastRow = row == totalRows - 1;
    final isFirstCol = col == 0;
    final isLastCol = col == crossAxisCount - 1;

    final borderRadius = BorderRadius.only(
      topLeft:
          (isFirstRow && isFirstCol) ? const Radius.circular(20) : Radius.zero,
      topRight:
          (isFirstRow && isLastCol) ? const Radius.circular(20) : Radius.zero,
      bottomLeft:
          (isLastRow && isFirstCol) ? const Radius.circular(20) : Radius.zero,
      bottomRight:
          (isLastRow && isLastCol) ? const Radius.circular(20) : Radius.zero,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(borderRadius: borderRadius),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 이미지/비디오
              if (isVideoUrl)
                ThumbnailVideoPlayer(
                  videoUrl: imageUrl,
                  width: cardWidth,
                  height: cardImageHeight,
                )
              else if (imageUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: cardWidth,
                  height: cardImageHeight,
                  fit: BoxFit.cover,
                  errorWidget:
                      (context, url, error) => Container(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                )
              else
                Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Icon(
                    Icons.image,
                    size: 40,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                  ),
                ),
              // 하단 그라데이션 오버레이
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    post.title ?? '제목 없음',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      letterSpacing: -1,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🎯 OTT 스타일 카드 (가로 스크롤용 - 나중에 필요하면 사용)
class _OTTCard extends StatelessWidget {
  final SearchContentItem post;
  final double cardWidth;
  final double cardImageHeight;
  final VoidCallback onTap;

  const _OTTCard({
    required this.post,
    required this.cardWidth,
    required this.cardImageHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = post.imageUrl ?? '';
    final isVideoUrl =
        imageUrl.toLowerCase().endsWith('.mp4') ||
        imageUrl.toLowerCase().endsWith('.mov') ||
        imageUrl.toLowerCase().endsWith('.avi') ||
        imageUrl.toLowerCase().endsWith('.webm') ||
        imageUrl.contains('/videos/');

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 썸네일
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                width: 0.8,
              ),
            ),
            width: cardWidth,
            height: cardImageHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  if (isVideoUrl)
                    ThumbnailVideoPlayer(
                      videoUrl: imageUrl,
                      width: cardWidth,
                      height: cardImageHeight,
                    )
                  else if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: cardWidth,
                      height: cardImageHeight,
                      fit: BoxFit.cover,
                      errorWidget:
                          (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            child: Icon(
                              Icons.image,
                              size: 40,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                            ),
                          ),
                    )
                  else
                    Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Icon(
                        Icons.image,
                        size: 40,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 제목
          SizedBox(
            width: cardWidth,
            child: Text(
              textAlign: TextAlign.center,
              post.title ?? '제목 없음',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
