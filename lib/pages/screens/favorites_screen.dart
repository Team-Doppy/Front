import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/card_view.dart';
import 'package:doppy/pages/components/image_view.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<PostData> _posts = [];
  final List<PostData> _filteredPosts = [];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  bool _isRefreshing = false; // 새로고침 중
  double _pullProgress = 0.0; // 당기는 진행률

  bool _isGridMode = false; // false = CardView (list), true = ImageView (grid)

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialPosts();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMorePosts();
      }
    }
  }

  Future<void> _loadInitialPosts() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _posts.clear();
      _hasMore = true;
    });

    try {
      final newPosts = await _fetchLikedPosts(0);

      if (mounted) {
        setState(() {
          _posts.addAll(newPosts);
          _hasMore = newPosts.length >= _pageSize;
          _isLoading = false;
          _applySearchFilter();
        });
      }
    } catch (e) {
      debugPrint('[FavoritesScreen] 초기 로딩 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final newPosts = await _fetchLikedPosts(nextPage);

      if (mounted) {
        setState(() {
          _posts.addAll(newPosts);
          _currentPage = nextPage;
          _hasMore = newPosts.length >= _pageSize;
          _isLoadingMore = false;
          _applySearchFilter();
        });
      }
    } catch (e) {
      debugPrint('[FavoritesScreen] 추가 로딩 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<List<PostData>> _fetchLikedPosts(int page) async {
    try {
      final blogService = BlogService();
      final postsJson = await blogService.getMyLikedPosts(
        page: page,
        size: _pageSize,
      );

      return postsJson
          .map((json) {
            try {
              // 🎯 "내가 좋아한" 화면에서는 모든 포스트가 좋아요한 포스트이므로 isLiked를 true로 설정
              final jsonWithLiked = Map<String, dynamic>.from(json);
              jsonWithLiked['isLiked'] = true;
              return PostData.fromServer(jsonWithLiked);
            } catch (e) {
              debugPrint('[FavoritesScreen] 포스트 파싱 실패: $e');
              return null;
            }
          })
          .whereType<PostData>()
          .toList();
    } catch (e) {
      debugPrint('[FavoritesScreen] 좋아요 포스트 가져오기 실패: $e');
      return [];
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      _isRefreshing = true;
    });

    await _loadInitialPosts();

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  void _toggleDisplayMode(bool isGrid) {
    setState(() {
      _isGridMode = isGrid;
    });
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredPosts.clear();
      _filteredPosts.addAll(_posts);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredPosts.clear();
      _filteredPosts.addAll(
        _posts.where((post) {
          final title = post.title.toLowerCase();
          return title.contains(query);
        }).toList(),
      );
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _applySearchFilter();
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _applySearchFilter();
    });
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            CustomRefreshIndicator(
              onRefresh: _onRefresh,
              top: 60,
              onPullProgress: (progress) {
                setState(() {
                  _pullProgress = progress;
                });
              },
              child: RawScrollbar(
                controller: _scrollController,
                thumbColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.3),
                thickness: 4,
                radius: const Radius.circular(8),
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // SliverAppBar
                    SliverAppBar(
                      expandedHeight: 0,
                      toolbarHeight: kToolbarHeight,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      pinned: false,
                      floating: true,
                      snap: false,
                      leading: Opacity(
                        opacity: 1.0 - _pullProgress,
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.75),
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      title: Opacity(
                        opacity: 1.0 - _pullProgress,
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            cursorColor:
                                Theme.of(context).colorScheme.onSurface,
                            onChanged: _onSearchChanged,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor:
                                  isDark
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.black.withOpacity(0.05),
                              hintText: context.tr('search_favorites'),
                              hintStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                                fontSize: 16,
                              ),
                              suffixIcon:
                                  _searchQuery.isNotEmpty
                                      ? IconButton(
                                        icon: Icon(
                                          Icons.cancel_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.5),
                                          size: 20,
                                        ),
                                        onPressed: _clearSearch,
                                      )
                                      : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 20,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      actions: [
                        Opacity(
                          opacity: 1.0 - _pullProgress,
                          child: Row(
                            children: [
                              if (!_isGridMode)
                                GestureDetector(
                                  onTap: () => _toggleDisplayMode(true),
                                  child: Icon(
                                    Icons.grid_view_rounded,
                                    size: 24,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.25),
                                  ),
                                ),
                              SizedBox(width: 8),
                              if (_isGridMode)
                                GestureDetector(
                                  onTap: () => _toggleDisplayMode(false),
                                  child: Icon(
                                    Icons.view_list_rounded,
                                    size: 24,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.25),
                                  ),
                                ),
                              SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // 콘텐츠
                    if (_isRefreshing)
                      ..._buildShimmer()
                    else if (_isLoading)
                      ..._buildShimmer()
                    else if (_posts.isEmpty)
                      SliverFillRemaining(child: _buildEmptyState())
                    else if (_filteredPosts.isEmpty && _searchQuery.isNotEmpty)
                      SliverFillRemaining(child: _buildNoSearchResults())
                    else ...[
                      if (!_isGridMode)
                        // 리스트 모드 - CardView
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final post = _filteredPosts[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => PostReaderScreen(
                                              exported: post.toExportedData(),
                                            ),
                                      ),
                                    );
                                  },
                                  child: CardView(
                                    post: post,
                                    isLast: index == _filteredPosts.length - 1,
                                  ),
                                ),
                              );
                            }, childCount: _filteredPosts.length),
                          ),
                        )
                      else
                        // 그리드 모드 - ImageView
                        SliverPadding(
                          padding: const EdgeInsets.all(4.0),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                  childAspectRatio: 0.8,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final post = _filteredPosts[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => PostReaderScreen(
                                            exported: post.toExportedData(),
                                          ),
                                    ),
                                  );
                                },
                                child: ImageView(
                                  post: post,
                                  isLast: index == _filteredPosts.length - 1,
                                ),
                              );
                            }, childCount: _filteredPosts.length),
                          ),
                        ),

                      // 하단 여백
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 40,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('no_favorite_posts'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('no_search_results_short'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"$_searchQuery"${context.tr('no_results_for_query')}',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildShimmer() {
    final isGrid = _isGridMode;
    if (isGrid) {
      return _buildShimmerGrid();
    } else {
      return _buildShimmerCardList();
    }
  }

  List<Widget> _buildShimmerGrid() {
    return [
      SliverPadding(
        padding: const EdgeInsets.all(4.0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 0.8,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.1),
                  width: 0.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            );
          }, childCount: 9), // 고정 9개 shimmer
        ),
      ),
    ];
  }

  List<Widget> _buildShimmerCardList() {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
                height: 125,
                child: Row(
                  children: [
                    // 썸네일 Shimmer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: ShimmerBox(
                        width: 125,
                        height: 120,
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 텍스트 영역 Shimmer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 제목 Shimmer (2줄)
                          ShimmerBox(
                            width: double.infinity,
                            height: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 6),
                          ShimmerBox(
                            width: MediaQuery.of(context).size.width * 0.4,
                            height: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 8),
                          // 날짜 Shimmer
                          ShimmerBox(
                            width: 80,
                            height: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 8),
                          // 요약 Shimmer (2줄)
                          ShimmerBox(
                            width: double.infinity,
                            height: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 4),
                          ShimmerBox(
                            width: MediaQuery.of(context).size.width * 0.3,
                            height: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }, childCount: 5),
        ),
      ),
    ];
  }
}
