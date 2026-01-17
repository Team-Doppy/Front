import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart'
    show CustomRefreshIndicator;
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_text_styles.dart';

// ============================================================================
// 검색 결과 뷰 (블로그 포스트 PageView)
// ============================================================================

/// 검색 결과 뷰 (독립적인 UI)
class SearchResultsView extends StatefulWidget {
  final List<PostData> posts;
  final String searchQuery;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final Function(int)? onPageChanged;
  final VoidCallback onSearchChipTap;
  final VoidCallback onClearSearch;

  const SearchResultsView({
    super.key,
    required this.posts,
    required this.searchQuery,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    this.onRefresh,
    this.onLoadMore,
    this.onPageChanged,
    required this.onSearchChipTap,
    required this.onClearSearch,
  });

  @override
  State<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<SearchResultsView> {
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = 0;
  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();
  bool _suppressVisibility = false;
  double _pullProgress = 0.0;

  // 🎯 가로/세로 제스처 감지 (PostList와 동일)
  double _gestureAccumY = 0.0;
  double _gestureAccumX = 0.0;
  bool _isGestureActive = false;
  bool _isHorizontalGesture = false; // 가로 제스처 감지 여부

  static const Duration _swipeDuration = Duration(milliseconds: 400);
  static const Curve _swipeCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.75,
    ); // 🎯 PostList와 동일한 viewport
    _likeService.addListener(_onLikeServiceChanged);
    _loadLikeStatusForAllPosts();
  }

  @override
  void didUpdateWidget(SearchResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.posts != oldWidget.posts) {
      _loadLikeStatusForAllPosts();
    }
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadLikeStatusForAllPosts() {
    // 🎯 LikeService에 값이 없을 때만 설정 (다른 화면에서 좋아요를 누른 경우 덮어쓰지 않음)
    for (final post in widget.posts) {
      final postId = post.id.toString();
      if (postId.isNotEmpty && !_likeService.hasPost(postId)) {
        _likeService.setInitialLikeData(postId, post.isLiked, post.likeCount);
      }
    }
  }

  Widget _buildScrollView(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Listener(
      behavior: HitTestBehavior.opaque, // 🎯 PostList와 동일
      // 🎯 가로/세로 제스처 감지 (PostList와 동일)
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
              assert(() {
                debugPrint('🔄 가로 제스처 감지! 세로 완전 차단');
                return true;
              }());
            }
          }
        }

        // 가로 제스처가 활성화되면 세로 누적값 무시
        if (_isHorizontalGesture) {
          _gestureAccumX += details.delta.dx;
          // 세로 움직임은 완전히 무시 (누적하지 않음)

          // 수평 스크롤만 처리 (텍스트 영역 스와이프는 더 부드럽게)
          if (_gestureAccumX.abs() > 30) {
            if (_gestureAccumX > 0 && _currentIndex > 0) {
              // 오른쪽으로 스크롤 - 이전 페이지 (텍스트 영역이므로 더 부드럽게)
              _pageController.previousPage(
                duration: _swipeDuration,
                curve: _swipeCurve,
              );
              _isGestureActive = false;
            } else if (_gestureAccumX < 0 &&
                _currentIndex < widget.posts.length - 1) {
              // 왼쪽으로 스크롤 - 다음 페이지 (텍스트 영역이므로 더 부드럽게)
              _pageController.nextPage(
                duration: _swipeDuration,
                curve: _swipeCurve,
              );
              _isGestureActive = false;
            }
          }
          return; // 세로 동작 완전 차단
        }

        // 세로 제스처 처리 (가로가 아닐 때만)
      },
      onPointerUp: (details) {
        if (_isGestureActive || _isHorizontalGesture) {
          setState(() {
            _isGestureActive = false;
            _isHorizontalGesture = false;
          });
        } else {
          _isGestureActive = false;
          _isHorizontalGesture = false;
        }
        _gestureAccumY = 0.0;
        _gestureAccumX = 0.0;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics:
            _isHorizontalGesture
                ? const NeverScrollableScrollPhysics() // 🎯 가로 제스처 감지 시 세로 스크롤 차단
                : const AlwaysScrollableScrollPhysics(),
        slivers: [
          // AppBar with 검색 칩
          SliverAppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 48,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            pinned: false,
            floating: true,
            snap: false,
            title: AnimatedOpacity(
              opacity: (1.0 - _pullProgress),
              duration:
                  _pullProgress != 0.0
                      ? Duration(milliseconds: 0)
                      : Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              child: Container(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              AnimatedOpacity(
                opacity: (1.0 - _pullProgress),
                duration: Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child:
                    widget.searchQuery.isNotEmpty
                        ? GestureDetector(
                          onTap: widget.onSearchChipTap,
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withOpacity(0.7),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      widget.searchQuery,
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: widget.onClearSearch,
                                    child: Icon(
                                      Icons.close,
                                      size: 22,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              height: 50,
              decoration: BoxDecoration(color: Colors.transparent),
            ),
          ),

          // PageView 또는 빈 상태
          if (widget.posts.isEmpty && !widget.isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [],
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Container(
                height: 400,
                decoration: BoxDecoration(color: Colors.transparent),
                child: PageView.builder(
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

                    if (widget.onPageChanged != null) {
                      widget.onPageChanged!(index);
                    }

                    // 무한 스크롤
                    if (widget.onLoadMore != null &&
                        index >= widget.posts.length - 5 &&
                        !widget.isLoadingMore) {
                      widget.onLoadMore!();
                    }
                  },
                  itemCount:
                      widget.posts.length + (widget.isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= widget.posts.length) {
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

                    final post = widget.posts[index];
                    return _buildPostItem(context, post, index, screenWidth);
                  },
                ),
              ),
            ),

          // Author Section
          SliverFillRemaining(
            hasScrollBody: false,
            child: GestureDetector(
              onTapUp: (details) async {
                final screenWidth = MediaQuery.of(context).size.width;
                final tapX = details.globalPosition.dx;

                if (tapX < screenWidth * 0.3) {
                  if (_currentIndex > 0) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else if (tapX > screenWidth * 0.7) {
                  if (_currentIndex < widget.posts.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else {
                  setState(() => _suppressVisibility = true);
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => PostReaderScreen(
                            exported:
                                widget.posts[_currentIndex].toExportedData(),
                            heroTag:
                                'search-post-${widget.posts[_currentIndex].id}-$_currentIndex',
                          ),
                    ),
                  );
                  if (mounted) {
                    setState(() => _suppressVisibility = false);
                  }
                }
              },
              child: Container(
                decoration: BoxDecoration(color: Colors.transparent),
                child: _textArea(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostItem(
    BuildContext context,
    PostData post,
    int index,
    double screenWidth,
  ) {
    // viewportFraction이 0.75이므로 실제 카드 너비는 screenWidth * 0.75
    final cardWidth = screenWidth * 0.75;

    return GestureDetector(
      onTapUp: (details) {
        final tapX = details.globalPosition.dx;

        if (tapX < screenWidth * 0.3) {
          if (_currentIndex > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        } else if (tapX > screenWidth * 0.7) {
          if (_currentIndex < widget.posts.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        } else {
          setState(() => _suppressVisibility = true);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (_) => PostReaderScreen(
                      exported: post.toExportedData(),
                      heroTag: 'search-post-${post.id}-$index',
                    ),
              ),
            );
            if (mounted) {
              setState(() => _suppressVisibility = false);
            }
          });
        }
      },
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, _) {
          final double pageNow =
              _pageController.hasClients
                  ? (_pageController.page ?? _currentIndex.toDouble())
                  : _currentIndex.toDouble();
          final double ad = (pageNow - index).abs().clamp(0.0, 1.0);
          final double t = 1.0 - ad;
          final double eased = Curves.easeOutCubic.transform(t);
          final double scale = 0.85 + 0.15 * eased;
          final bool isMainVisible = !_suppressVisibility && t >= 0.7;

          return Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: PostCard(
                  containerWidth: cardWidth,
                  thumbnailImageUrl: post.thumbnailImageUrl,
                  heroTag: 'search-post-${post.id}-$index',
                  title: post.title,
                  author: post.author,
                  authorProfileImageUrl: post.authorProfileImageUrl,
                  content: post.parsedContent,
                  isVisible: isMainVisible,
                  postId: post.id.toString(),
                  isLiked: _likeService.isPostLiked(post.id.toString()),
                  likeCount: _likeService.getPostLikeCount(post.id.toString()),
                  onLikePressed: () async {
                    final id = post.id.toString();
                    if (id.isEmpty || _likingInFlight.contains(id)) return;
                    _likingInFlight.add(id);
                    setState(() {});
                    try {
                      await _likeService.togglePostLike(id);
                    } catch (e) {
                      if (mounted) {
                        setState(() {});
                      }
                    } finally {
                      _likingInFlight.remove(id);
                    }
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _textArea(BuildContext context) {
    if (widget.posts.isEmpty) {
      return const SizedBox.shrink();
    }
    final safeIndex = _currentIndex.clamp(0, widget.posts.length - 1);
    final post = widget.posts[safeIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: 10),
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
        child:
            widget.isLoading
                ? _buildRefreshingShimmer()
                : _buildScrollView(context),
      ),
    );
  }

  Widget _buildRefreshingShimmer() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          toolbarHeight: 35,
          backgroundColor: Colors.transparent,
          elevation: 0,
          pinned: false,
          floating: true,
          title: Text(
            ' Doppy',
            style: GoogleFonts.notoSansKr(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            height: 50,
            decoration: BoxDecoration(color: Colors.transparent),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            height: 400,
            decoration: BoxDecoration(color: Colors.transparent),
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ShimmerBox(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverFillRemaining(hasScrollBody: false, child: Container()),
      ],
    );
  }
}

// ============================================================================
// 검색 결과 리스트 (계정 + 검색 기록)
// ============================================================================

/// 검색 결과 리스트 (계정 + 검색 기록)
class SearchResults extends StatefulWidget {
  final List<SearchContentItem> accounts;
  final List<String> searchHistory;
  final String query;
  final bool hasNetworkError;
  final VoidCallback onAnyTapDown;
  final Function(SearchContentItem) onTapAccount;
  final Function(String) onTapHistory;
  final Function(SearchContentItem) onRemoveHistory;
  final bool enableHero;
  final VoidCallback onTapSearch;

  const SearchResults({
    super.key,
    required this.accounts,
    required this.searchHistory,
    required this.query,
    required this.hasNetworkError,
    required this.onAnyTapDown,
    required this.onTapAccount,
    required this.onTapHistory,
    required this.onRemoveHistory,
    required this.enableHero,
    required this.onTapSearch,
  });

  @override
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];
    if (widget.query.isNotEmpty) {
      // 검색어 실행 타일 (항상 맨 위)
      children.add(
        AccountListItem(
          account: SearchContentItem.blogKeyword(
            id: 'current_search',
            keyword: widget.query,
          ),
          onTap: widget.onTapSearch,
          onTapDown: widget.onAnyTapDown,
          showRemoveButton: false,
        ),
      );
    }

    if (widget.accounts.isNotEmpty) {
      final seen = <String>{};
      for (final account in widget.accounts) {
        final uname = account.username ?? '';
        if (uname.isNotEmpty) seen.add(uname);
        children.add(
          AccountListItem(
            account: account,
            onTapDown: widget.onAnyTapDown,
            onTap: () => widget.onTapAccount(account),
            onRemove: () => widget.onRemoveHistory(account),
            showRemoveButton: widget.query.isEmpty,
          ),
        );
      }
    }

    return RawScrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(2),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children,
      ),
    );
  }
}

/// 계정/검색어 리스트 아이템
class AccountListItem extends StatelessWidget {
  final SearchContentItem account;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  const AccountListItem({
    super.key,
    required this.account,
    required this.onTap,
    this.onTapDown,
    this.onRemove,
    this.showRemoveButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // 🎯 글 검색 기록인 경우 (인물과 동일한 디자인)
    if (account.isBlog) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTapDown?.call(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              CommonProfileAvatar(
                imageUrl: null,
                username: 'search',
                size: 50,
                borderColor: Theme.of(context).colorScheme.background,
                borderWidth: 0,
                backgroundColor:
                    Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[200]
                        : Colors.black,
                centerWidget: Icon(
                  Icons.search,
                  size: 20,
                  color:
                      Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  account.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onBackground,
                  ),
                ),
              ),
              if (showRemoveButton && onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 계정 검색 기록인 경우
    return HeroMode(
      enabled: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTapDown?.call(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CommonProfileAvatar(
                imageUrl: account.profileImageUrl,
                username: account.username ?? '',
                size: 50.0,
                // 🎯 프로필 이미지가 없을 때만 배경색 설정 (grey[100] / black)
                backgroundColor:
                    account.profileImageUrl == null ||
                            account.profileImageUrl!.isEmpty
                        ? (Theme.of(context).brightness == Brightness.light
                            ? Colors.grey[100]
                            : Colors.black)
                        : null,
                borderColor: Theme.of(context).colorScheme.surface,
                // 🎯 프로필 이미지가 있을 때는 보더 제거
                borderWidth: 0,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (account.alias?.isNotEmpty == true)
                          ? account.alias!
                          : (account.username ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${account.username ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (account.followers != null &&
                        account.followers! > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${account.followers}명',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showRemoveButton && onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 블로그 검색 결과 화면
// ============================================================================

/// 블로그 검색 결과 화면
class SearchBlogResultsScreen extends StatefulWidget {
  final String keyword;
  final List<PostData> initialPosts;
  final bool initialHasMore;

  const SearchBlogResultsScreen({
    super.key,
    required this.keyword,
    required this.initialPosts,
    required this.initialHasMore,
  });

  @override
  State<SearchBlogResultsScreen> createState() =>
      _SearchBlogResultsScreenState();
}

class _SearchBlogResultsScreenState extends State<SearchBlogResultsScreen> {
  late List<PostData> _posts = List<PostData>.from(widget.initialPosts);
  late bool _hasMore = widget.initialHasMore;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;

  PostData _toPostData(SearchContentItem item, SearchService searchService) {
    final originalData = searchService.getPostData(item.id);
    if (originalData != null) {
      return PostData.fromServer(originalData);
    }
    return PostData(
      id: item.id,
      thumbnailImageUrl: item.imageUrl ?? '',
      title: item.title ?? '',
      author: item.author ?? item.username ?? '',
      authorProfileImageUrl: item.profileImageUrl ?? '',
      content: item.content ?? '',
      accessLevel: AccessLevel.public,
      viewCount: 0,
      likeCount: item.likes ?? 0,
      commentCount: item.comments ?? 0,
      isLiked: false,
      createdAt: item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      updatedAt: item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });

    try {
      final searchService = context.read<SearchService>();
      await searchService.startBlogsSearch(widget.keyword, size: 20);
      final blogResults = searchService.blogResults;
      final next =
          blogResults.map((i) => _toPostData(i, searchService)).toList();

      if (!mounted) return;
      setState(() {
        _posts = next;
        _hasMore = searchService.blogsHasMore;
        _isRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final searchService = context.read<SearchService>();
      final items = await searchService.loadMoreBlogs(size: 20);
      final append = items.map((i) => _toPostData(i, searchService)).toList();

      if (!mounted) return;
      setState(() {
        _posts.addAll(append);
        _hasMore = searchService.blogsHasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        bottom: false,
        child: SearchResultsView(
          posts: _posts,
          searchQuery: widget.keyword,
          isLoading: _isRefreshing && _posts.isEmpty,
          isLoadingMore: _isLoadingMore,
          hasMore: _hasMore,
          onRefresh: _refresh,
          onLoadMore: _hasMore ? () => _loadMore() : null,
          onSearchChipTap: () {
            // ✅ 검색 칩 탭 시: 텍스트 필드 유지하고 뒤로가기
            context.read<SearchService>().clearSearchingFlag();
            Navigator.of(context).pop();
          },
          onClearSearch: () {
            // ✅ X 버튼 클릭 시: 텍스트 필드 비우고 뒤로가기
            final searchService = context.read<SearchService>();
            searchService.onSearchChanged(''); // 텍스트 필드 비우기
            searchService.clearSearchingFlag();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
