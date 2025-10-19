import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/empty_post_list.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/pages/components/feed_filter_dropdown.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/search_screen_overlay.dart';
import 'package:doppy/providers/search_result_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;

class HomeScreen extends StatefulWidget {
  final List<PostData>? preloadedPosts;

  const HomeScreen({super.key, this.preloadedPosts});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final BlogService _blogService = BlogService();
  List<PostData> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 0;
  bool _hasMoreData = true;
  int _currentPostIndex = 0; // 현재 보이는 포스트 인덱스
  bool _isCardShimmering = false; // 새로고침 시 카드 영역만 쉬머 표시
  int _loadTick = 0; // 응답 정합성 보장용 토큰

  // 검색 오버레이 상태
  bool _isSearchOverlayVisible = false;
  bool _isShowingSearchResults = false; // 검색 결과 표시 중인지
  String _searchQuery = ''; // 현재 검색어

  // 피드 필터 상태
  bool _isShowingFriendsOnly = true; // 친구만 보기 여부 (기본: 친구글)

  // 새로고침 시 배경 이미지 유지용
  String? _previousBackgroundImageUrl;

  @override
  void initState() {
    super.initState();
    // 스플래시에서 전달된 선로딩 데이터를 즉시 반영
    if (widget.preloadedPosts != null) {
      _posts = List<PostData>.from(widget.preloadedPosts!);
      _isLoading = false;
      _hasMoreData = _posts.length == 10;
      _currentPage = _posts.isNotEmpty ? 1 : 0; // 데이터가 있으면 다음 페이지부터 로드
      print('[HomeScreen] Preloaded ${_posts.length} posts from splash');
    }

    print('[HomeScreen] initState: ${widget.preloadedPosts?.length}');

    // 다음 프레임에서 검색 결과 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final searchResultProvider = context.read<SearchResultProvider>();
      if (searchResultProvider.hasSearchResults) {
        setState(() {
          _posts = searchResultProvider.searchResults;
          _searchQuery = searchResultProvider.searchQuery;
          _isShowingSearchResults = true;
          _isLoading = false;
          _hasMoreData = false;
        });
      }

      // Provider의 오버레이 상태 변화를 감지
      searchResultProvider.addListener(() {
        if (!searchResultProvider.isSearchOverlayVisible &&
            _isSearchOverlayVisible) {
          // 다른 탭으로 이동 시 오버레이 닫기
          setState(() {
            _isSearchOverlayVisible = false;
          });
        }
      });
    });
  }

  // 검색 결과 설정 (외부에서 호출)
  void setSearchResults(List<PostData> results, String query) {
    if (mounted) {
      setState(() {
        _posts = results;
        _isShowingSearchResults = true;
        _searchQuery = query;
        _currentPostIndex = 0;
      });
    }
  }

  // 검색 오버레이 열기 (독립 화면으로)
  void openSearchOverlay({String? initialQuery}) {
    print('[HomeScreen.openSearchOverlay] 호출됨 - initialQuery: $initialQuery');
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: SearchScreenOverlay(
              initialQuery: initialQuery, // 초기 검색어 전달
              onSearchComplete: (results, query) {
                // 검색 결과를 받아서 홈화면으로 돌아가며 표시
                Navigator.of(context).pop(); // 검색 화면 닫기
                setSearchResults(results, query); // 검색 결과 설정
              },
              onClose: () {
                Navigator.of(context).pop();
              },
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return child;
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  void _resetFeed({bool showLoading = true}) {
    // 새로고침 시 현재 배경 이미지를 이전 이미지로 저장
    if (_posts.isNotEmpty) {
      final safeIndex = _currentPostIndex.clamp(0, _posts.length - 1);
      final currentPost = _posts[safeIndex];
      final String imageUrl = currentPost.thumbnailImageUrl.trim();
      if (imageUrl.startsWith('http')) {
        _previousBackgroundImageUrl = imageUrl;
      }
    }

    setState(() {
      _posts = [];
      _currentPage = 0;
      _hasMoreData = true;
      _isLoading = showLoading;
      _isLoadingMore = false;
      _error = null;
      _currentPostIndex = 0;
      _isCardShimmering = false;
      _isShowingSearchResults = false;
    });
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    // 검색 결과 표시 중에는 로드하지 않음
    if (_isShowingSearchResults && !refresh) return;

    try {
      if (refresh) {
        _resetFeed(showLoading: true); // 완전 청소 후 로딩 표시
      } else {
        setState(() {
          _isLoading = _posts.isEmpty; // 처음 진입 시 전체 로딩
          _error = null;
        });
      }

      final int token = ++_loadTick; // 응답 토큰 발급

      // 필터에 따라 다른 엔드포인트 호출
      final serverData =
          _isShowingFriendsOnly
              ? await _blogService.getFriendsPosts(page: _currentPage, size: 10)
              : await _blogService.getRecommendedPosts(
                page: _currentPage,
                size: 10,
              );
      final posts =
          serverData.map((data) => PostData.fromServer(data)).toList();

      // 전환 전에 썸네일 이미지 프리캐싱 (상위 몇 개)
      await _precacheImages(posts.take(3).toList());

      if (token != _loadTick) return; // 최신 요청이 아니면 무시

      setState(() {
        if (refresh) {
          _posts = posts;
          // 새로고침 완료 후 이전 배경 이미지 정리
          _previousBackgroundImageUrl = null;
        } else {
          _posts.addAll(posts);
        }
        _isLoading = false;
        _isLoadingMore = false;
        _hasMoreData = posts.length == 10; // 10개 미만이면 더 이상 데이터 없음
        _currentPage++;
        _isCardShimmering = false; // 로드 완료 후 카드 쉬머 해제
      });
    } catch (e) {
      print('[HomeScreen] Error loading posts: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
        // 서버 오류 시 빈 리스트 유지
      });
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMoreData || _isShowingSearchResults) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _loadPosts();
  }

  Widget _buildDynamicBackground() {
    // 새로고침 중이고 이전 배경 이미지가 있으면 그것을 사용
    if (_posts.isEmpty && _previousBackgroundImageUrl != null) {
      return Positioned.fill(
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: _previousBackgroundImageUrl!,
                fit: BoxFit.cover,
                key: ValueKey('bg-previous-$_previousBackgroundImageUrl'),
                placeholder:
                    (context, url) => ShimmerBox(
                      width: double.infinity,
                      height: double.infinity,
                    ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.8),
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.8),
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.8),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) return const SizedBox.shrink();

    // 안전한 인덱스 범위 체크
    final safeIndex = _currentPostIndex.clamp(0, _posts.length - 1);
    final currentPost = _posts[safeIndex];
    final String imageUrl = currentPost.thumbnailImageUrl.trim();

    final bool isNetwork = imageUrl.startsWith('http');

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child:
                isNetwork
                    ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      key: ValueKey('bg-$imageUrl'),
                      placeholder:
                          (context, url) => ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                          ),
                      errorWidget:
                          (context, url, error) => const Icon(Icons.error),
                    )
                    : SizedBox.shrink(),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(0.75),
                      Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(0.75),
                      Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(0.75),
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [_buildDynamicBackground(), _buildContent(screenWidth)],
    );
  }

  Widget _buildContent(double screenWidth) {
    // 데이터가 준비되어 있다면 애니메이션 없이 즉시 렌더링
    if (!_isLoading && _error == null && _posts.isNotEmpty) {
      return PostList(
        containerWidth: screenWidth,
        posts: _posts,
        onLoadMore:
            (_hasMoreData && !_isShowingSearchResults) ? _loadMorePosts : null,
        isLoadingMore: _isLoadingMore,
        onRefresh: () => _loadPosts(refresh: true),
        showCardShimmer: _isCardShimmering,
        onPageChanged: (index) {
          setState(() {
            _currentPostIndex = index;
          });
        },
        isShowingSearchResults: _isShowingSearchResults,
        searchQuery: _searchQuery,
        onSearchChipTap: () => openSearchOverlay(initialQuery: _searchQuery),
        onClearSearch: () {
          // Provider 클리어
          context.read<SearchResultProvider>().clearSearchResults();

          setState(() {
            _isShowingSearchResults = false;
            _searchQuery = '';
            _currentPostIndex = 0;
          });
          // 홈 포스트 다시 로드
          _loadPosts(refresh: true);
        },
        isShowingFriendsOnly: _isShowingFriendsOnly,
        onFilterTap: () {
          FeedFilterDropdown.show(
            context,
            isShowingFriendsOnly: _isShowingFriendsOnly,
            onFilterChanged: (showFriendsOnly) {
              _resetFeed(showLoading: true);
              _isShowingFriendsOnly = showFriendsOnly;
              _loadPosts(refresh: true); // 완전 새로고침
            },
          );
        },
      );
    }

    final Widget child =
        (_error != null)
            ? _buildError()
            : (_isLoading)
            ? PostList(
              containerWidth: screenWidth,
              posts: _posts,
              onLoadMore: null,
              isLoadingMore: false,
              onRefresh: () => _loadPosts(refresh: true),
              showCardShimmer: true,
              onPageChanged: (index) {
                setState(() {
                  _currentPostIndex = index;
                });
              },
              isShowingSearchResults: _isShowingSearchResults,
              searchQuery: _searchQuery,
              onSearchChipTap:
                  () => openSearchOverlay(initialQuery: _searchQuery),
              onClearSearch: () {
                // Provider 클리어
                context.read<SearchResultProvider>().clearSearchResults();

                setState(() {
                  _isShowingSearchResults = false;
                  _searchQuery = '';
                  _currentPostIndex = 0;
                });
                // 홈 포스트 다시 로드
                _loadPosts(refresh: true);
              },
              isShowingFriendsOnly: _isShowingFriendsOnly,
              onFilterTap: () {
                FeedFilterDropdown.show(
                  context,
                  isShowingFriendsOnly: _isShowingFriendsOnly,
                  onFilterChanged: (showFriendsOnly) {
                    _resetFeed(showLoading: true);
                    _isShowingFriendsOnly = showFriendsOnly;
                    _loadPosts(refresh: true); // 완전 새로고침
                  },
                );
              },
            )
            : (_posts.isEmpty)
            ? (() {
              print('[HomeScreen._buildContent] 포스트 비어있음 → EmptyPostList 표시');
              return _buildEmptyResult();
            })()
            : PostList(
              containerWidth: screenWidth,
              posts: _posts,
              onLoadMore:
                  (_hasMoreData && !_isShowingSearchResults)
                      ? _loadMorePosts
                      : null,
              isLoadingMore: _isLoadingMore,
              onRefresh: () => _loadPosts(refresh: true),
              showCardShimmer: _isCardShimmering,
              onPageChanged: (index) {
                setState(() {
                  _currentPostIndex = index;
                });
              },
            );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        final scale = Tween<double>(begin: 0.98, end: 1.0).animate(curved);
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('${_isLoading}_${_error != null}_${_posts.length}'),
        child: child,
      ),
    );
  }

  Future<void> _precacheImages(List<PostData> posts) async {
    final List<Future<void>> futures = [];
    for (final p in posts) {
      final url = p.thumbnailImageUrl.trim();
      if (url.isEmpty) continue;
      futures.add(precacheImage(NetworkImage(url), context).catchError((_) {}));
    }
    if (futures.isNotEmpty) {
      try {
        await Future.wait(futures);
      } catch (_) {}
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 커스텀 에러 아이콘 (원형 배경)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.1),
              ),
              child: const Center(
                child: Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '연결 상태를 확인해주세요',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '네트워크 연결이 불안정하거나\n서버에 접속할 수 없습니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
                height: 1.4,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 32),
            // 세련된 재시도 버튼
            SizedBox(
              width: 160,
              height: 48,
              child: ElevatedButton(
                onPressed: _loadPosts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.refresh_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '다시 시도',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResult() {
    return EmptyPostList();
  }
}
