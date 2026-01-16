import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/search_result.dart';
import 'package:doppy/pages/components/search_top_section.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/pages/screens/search_history_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/pages/components/search_trending_section.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../data/services/search_service.dart';

class SearchScreenOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final String? initialQuery; // 초기 검색어 (검색어 칩에서 올 때)
  // ✅ RootShell에서 "명령"으로 전달 (위젯 파라미터 변경 없이 검색어만 갱신)
  final ValueListenable<String?>? initialQueryListenable;

  // ✅ IndexedStack에서 비활성 탭이면 즉시 return하여 무거운 subtree 빌드 방지
  final ValueListenable<int>? activeIndexListenable;
  final int tabIndex;
  final Function(int)? onTabChange; // 🎯 바텀 바 탭 변경

  const SearchScreenOverlay({
    super.key,
    this.onClose,
    this.initialQuery,
    this.initialQueryListenable,
    this.activeIndexListenable,
    this.tabIndex = 1,
    this.onTabChange,
  });

  @override
  State<SearchScreenOverlay> createState() => _SearchScreenOverlayState();
}

class _SearchScreenOverlayState extends State<SearchScreenOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearching = false; // 🎯 중복 검색 방지

  bool _shouldIgnoreControllerChanges = false; // 🎯 검색 칩 탭 시 리스너 무시 플래그
  VoidCallback? _initialQueryListener;

  // 🎯 검색 결과 상태 (독립적으로 관리)
  List<PostData> _searchResults = [];
  String _searchQuery = '';
  bool _isShowingSearchResults = false;
  bool _searchHasMore = true;
  bool _isLoadingMore = false;
  int _searchRefreshCount = 0;

  // 🎯 배경 이미지 관리
  int _currentSearchPostIndex = 0; // 검색 결과 포스트 인덱스
  int _currentTrendingPostIndex = 0; // 트렌딩 포스트 인덱스

  @override
  void initState() {
    super.initState();

    // 🎯 초기 검색어가 있으면 바로 포커스 상태로 시작 (trending 렌더링 방지)
    final externalQuery = widget.initialQueryListenable?.value;
    final hasExternalQuery = externalQuery != null && externalQuery.isNotEmpty;
    final hasInitialQuery =
        hasExternalQuery ||
        (widget.initialQuery != null && widget.initialQuery!.isNotEmpty);

    if (hasInitialQuery) {
      final q = hasExternalQuery ? externalQuery : (widget.initialQuery ?? '');
      _searchController.text = q;
    }

    _searchController.addListener(() {
      // 🎯 검색어 변경 시 SearchService 업데이트
      // 단, 검색 칩 탭으로 인한 변경은 무시
      if (!_shouldIgnoreControllerChanges) {
        context.read<SearchService>().onSearchChanged(_searchController.text);
      }
    });

    // ✅ RootShell에서 initialQuery를 notifier로 전달하는 경우, 변경을 직접 반영
    if (widget.initialQueryListenable != null) {
      _initialQueryListener = () {
        if (!mounted) return;
        _applyIncomingInitialQuery(widget.initialQueryListenable!.value);
      };
      widget.initialQueryListenable!.addListener(_initialQueryListener!);
    }

    // 🎯 초기화 및 초기 검색어 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 🎯 UI 렌더링 완료 후 즉시 실행 (지연 제거하여 빠른 로딩)
      Future.microtask(() async {
        if (!mounted) return;

        final searchService = context.read<SearchService>();

        // 🎯 초기 검색어가 있으면 포커스 설정
        if (hasInitialQuery) {
          final q =
              hasExternalQuery ? externalQuery : (widget.initialQuery ?? '');
          searchService.onSearchChanged(q);
          debugPrint('[SearchScreen] 초기 검색어 설정: $q');
        }

        // initialize는 검색 기록만 로드 (이미 splash에서 로드했을 수 있지만 안전하게 다시 로드)
        await searchService.initialize(forceRefresh: false);

        // 🎯 추천 포스트는 스플래시에서 이미 로드했으므로 재로드하지 않음
        debugPrint(
          '[SearchScreen] 초기화 완료 (검색 기록만 로드, 추천 포스트는 스플래시에서 로드한 것 사용)',
        );
      });
    });
  }

  void _openSearchExplore() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (_, __, ___) => SearchExploreScreen(
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              onSearchSubmitted: _runSearch,
              onClose: widget.onClose ?? () {},
            ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _applyIncomingInitialQuery(String? q) {
    final normalized = (q ?? '').trim();
    final searchService = context.read<SearchService>();

    if (normalized.isNotEmpty) {
      // 초기 검색어로 진입 시 추천 포스트 즉시 지우기 (기존 정책 유지)
      searchService.clearRecommendedPosts();

      _shouldIgnoreControllerChanges = true;
      _searchController.text = normalized;
      _shouldIgnoreControllerChanges = false;

      searchService.onSearchChanged(normalized);
      _searchFocusNode.requestFocus();
    } else {
      _shouldIgnoreControllerChanges = true;
      _searchController.clear();
      _shouldIgnoreControllerChanges = false;

      searchService.clearSearch();
      _searchFocusNode.unfocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 🎯 초기 검색어가 있으면 화면 빌드 전에 추천 포스트 즉시 지우기
    final hasInitialQuery =
        widget.initialQuery != null && widget.initialQuery!.isNotEmpty;

    if (hasInitialQuery) {
      final searchService = context.read<SearchService>();
      searchService.clearRecommendedPosts();
      debugPrint('[SearchScreen] didChangeDependencies - 초기 검색어로 인해 추천 포스트 지움');
    }
  }

  @override
  void didUpdateWidget(SearchScreenOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 위젯이 업데이트될 때도 초기 검색어가 있으면 처리
    final hasInitialQuery =
        widget.initialQuery != null && widget.initialQuery!.isNotEmpty;
    final hadInitialQuery =
        oldWidget.initialQuery != null && oldWidget.initialQuery!.isNotEmpty;

    // 초기 검색어가 변경되었을 때
    if (hasInitialQuery && widget.initialQuery != oldWidget.initialQuery) {
      final searchService = context.read<SearchService>();
      searchService.clearRecommendedPosts();

      // 검색어 설정
      _searchController.text = widget.initialQuery!;
      searchService.onSearchChanged(widget.initialQuery!);
      _searchFocusNode.requestFocus();

      debugPrint(
        '[SearchScreen] didUpdateWidget - 초기 검색어로 인해 추천 포스트 지움 및 검색어 설정: ${widget.initialQuery}',
      );
    } else if (!hasInitialQuery && hadInitialQuery) {
      // 초기 검색어가 제거되었을 때 (검색어 클리어)
      _searchController.clear();
      final searchService = context.read<SearchService>();
      searchService.clearSearch();
      _searchFocusNode.unfocus();
      debugPrint('[SearchScreen] didUpdateWidget - 초기 검색어 제거됨');
    }
  }

  @override
  void dispose() {
    if (widget.initialQueryListenable != null &&
        _initialQueryListener != null) {
      widget.initialQueryListenable!.removeListener(_initialQueryListener!);
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 현재 배경 이미지 URL 가져오기
  String? _getCurrentBackgroundImageUrl(SearchService searchService) {
    // 검색 결과 화면일 때
    if (_isShowingSearchResults && _searchResults.isNotEmpty) {
      final safeIndex = _currentSearchPostIndex.clamp(
        0,
        _searchResults.length - 1,
      );
      final currentPost = _searchResults[safeIndex];
      final imageUrl = currentPost.thumbnailImageUrl.trim();

      // 🎯 네트워크 이미지이면 비디오도 포함하여 전달 (비디오는 VideoCacheService로 프리로드)
      if (imageUrl.startsWith('http')) {
        return imageUrl;
      }
    }

    // 트렌딩 화면일 때 (추천 포스트)
    if (!_isShowingSearchResults && searchService.recommendedPosts.isNotEmpty) {
      final safeIndex = _currentTrendingPostIndex.clamp(
        0,
        searchService.recommendedPosts.length - 1,
      );
      final currentPost = searchService.recommendedPosts[safeIndex];
      final imageUrl = currentPost.imageUrl?.trim() ?? '';

      // 🎯 네트워크 이미지이면 비디오도 포함하여 전달 (비디오는 VideoCacheService로 프리로드)
      if (imageUrl.startsWith('http')) {
        return imageUrl;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ IndexedStack에서 Search 탭이 비활성이면
    // 키보드(MediaQuery) 변화가 와도 여기서 끝내서 무거운 subtree 빌드를 차단한다.
    if (widget.activeIndexListenable != null) {
      return ValueListenableBuilder<int>(
        valueListenable: widget.activeIndexListenable!,
        builder: (context, idx, _) {
          if (idx != widget.tabIndex) {
            return const SizedBox.shrink();
          }
          return _buildActive(context);
        },
      );
    }

    return _buildActive(context);
  }

  Widget _buildActive(BuildContext context) {
    return Consumer<SearchService>(
      builder: (context, searchService, child) {
        // 🎯 현재 배경 이미지 URL 가져오기
        final backgroundImageUrl = _getCurrentBackgroundImageUrl(searchService);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).colorScheme.background,
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(
                    milliseconds: 400,
                  ), // 🎯 부드러운 전환 (섹션 전환과 동일한 duration)
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child:
                      backgroundImageUrl != null
                          ? Builder(
                            builder: (context) {
                              // 비디오 URL 체크
                              final isVideoUrl =
                                  backgroundImageUrl.toLowerCase().endsWith(
                                    '.mp4',
                                  ) ||
                                  backgroundImageUrl.toLowerCase().endsWith(
                                    '.mov',
                                  ) ||
                                  backgroundImageUrl.toLowerCase().endsWith(
                                    '.avi',
                                  ) ||
                                  backgroundImageUrl.toLowerCase().endsWith(
                                    '.webm',
                                  ) ||
                                  backgroundImageUrl.contains('/videos/');

                              // 비디오인 경우 VideoPlayer 사용
                              if (isVideoUrl) {
                                return SearchBackgroundVideoWidget(
                                  videoUrl: backgroundImageUrl,
                                  key: ValueKey('bg-video-$backgroundImageUrl'),
                                );
                              } else {
                                return CachedNetworkImage(
                                  imageUrl: backgroundImageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  key: ValueKey('bg-$backgroundImageUrl'),
                                  fadeInDuration: const Duration(
                                    milliseconds: 200,
                                  ), // 🎯 배경 이미지 변경 시 페이드 인 효과
                                  fadeOutDuration: const Duration(
                                    milliseconds: 300,
                                  ), // 🎯 이전 이미지 페이드 아웃
                                  placeholder:
                                      (context, url) => ShimmerBox(
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                                  errorWidget:
                                      (context, url, error) =>
                                          const SizedBox.shrink(),
                                );
                              }
                            },
                          )
                          : const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).colorScheme.background,
                ),
              ),
              // 🎯 통짜 스크롤 구조 (Sliver 사용)
              _isShowingSearchResults
                  ? _buildSearchResultsView(context)
                  : _buildDefaultSearchBodyWithSliver(context, searchService),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runSearch() async {
    // 🎯 중복 검색 방지
    if (_isSearching) {
      debugPrint('[SearchOverlay] 이미 검색 중입니다. 무시.');
      return;
    }

    final searchService = context.read<SearchService>();
    debugPrint('[SearchOverlay] runSearch: ${searchService.query}');

    try {
      // 빈 검색어면 수행하지 않음
      if (searchService.query.trim().isEmpty) {
        return;
      }

      setState(() {
        _isSearching = true;
      });

      // 페이지네이션 초기화: 20개씩
      await searchService.startBlogsSearch(searchService.query, size: 20);

      // 🎯 글 검색 키워드를 검색 기록에 추가
      searchService.addBlogSearchKeyword(searchService.query);

      final blogResults = searchService.blogResults;
      final posts =
          blogResults.map((item) {
            // 🎯 SearchService에 저장된 원본 서버 데이터 활용
            final originalData = searchService.getPostData(item.id);
            if (originalData != null) {
              // 원본 서버 데이터가 있으면 PostData.fromServer로 변환 (정확한 데이터 사용)
              return PostData.fromServer(originalData);
            } else {
              // fallback: SearchContentItem에서 수동 변환
              return PostData(
                id: item.id,
                thumbnailImageUrl: item.imageUrl ?? '',
                title: item.title ?? '',
                summary: item.summary ?? item.parsedContent ?? '',
                author: item.author ?? item.username ?? '',
                authorProfileImageUrl: item.profileImageUrl ?? '',
                content: item.content ?? '',
                accessLevel: AccessLevel.public,
                viewCount: 0,
                likeCount: item.likes ?? 0,
                commentCount: item.comments ?? 0,
                isLiked: false,
                createdAt:
                    item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
                updatedAt:
                    item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
              );
            }
          }).toList();

      // 🎯 검색 결과를 내부 상태로 저장 (홈으로 이동하지 않음)
      if (mounted) {
        setState(() {
          _searchResults = posts;
          _searchQuery = searchService.query;
          _isShowingSearchResults = true;
          _searchHasMore = searchService.blogsHasMore;
          _searchRefreshCount++;
          _currentSearchPostIndex = 0; // 🎯 검색 결과 변경 시 인덱스 리셋
        });
        debugPrint('[SearchOverlay] 검색 완료: ${posts.length}개 결과 (검색 탭에 표시)');
      }
    } catch (e) {
      debugPrint('[SearchOverlay] 검색 실패: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isShowingSearchResults = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  // 🎯 기본 검색 화면 (trending/history/live) - Sliver 구조
  Widget _buildDefaultSearchBodyWithSliver(
    BuildContext context,
    SearchService searchService,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final heroHeight = screenHeight * 0.55; // 🎯 화면 높이의 40%

    return CustomScrollView(
      key: const ValueKey('search-default-scroll'),
      slivers: [
        // 🎯 Hero 섹션이 있는 SliverAppBar (검색 중이면 숨김)
        if (!_isSearching)
          SliverAppBar(
            key: const ValueKey('search-hero-appbar'),
            expandedHeight: heroHeight,
            toolbarHeight: 56, // 🎯 최소 높이 100px 유지
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            floating: false,
            snap: false,
            automaticallyImplyLeading: false,
            pinned: true, // 🎯 pinned을 true로 설정하여 최소 높이 유지
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                // 🎯 스크롤 위치에 따라 텍스트 투명도 계산
                final currentHeight = constraints.maxHeight;
                final expandedHeight = heroHeight;
                final collapsedHeight = 20.0; // toolbarHeight와 동일

                // 접힌 정도 계산 (0.0 = 완전히 펼쳐짐, 1.0 = 완전히 접힘)
                final collapseProgress = ((expandedHeight - currentHeight) /
                        (expandedHeight - collapsedHeight))
                    .clamp(0.0, 1.0);

                // 텍스트 투명도: 50px 스크롤 시 투명해짐
                final scrollDistance = expandedHeight - currentHeight;
                final textOpacity = (1.0 - (scrollDistance / 50.0)).clamp(
                  0.0,
                  1.0,
                );

                // 이미지 투명도: 접힐수록 투명해짐 (겹침 방지)
                final imageOpacity = (1.0 - collapseProgress * 1.5).clamp(
                  0.0,
                  1.0,
                );

                // 🎯 이미지가 거의 투명해졌을 때 AppBar 배경 표시 (더 늦게 나타나도록)
                final showAppBarBackground = imageOpacity < 0.1;
                // 🎯 배경도 점진적으로 나타나도록 opacity 적용
                final backgroundOpacity = (1.0 - imageOpacity / 0.1).clamp(
                  0.0,
                  1.0,
                );

                // 🎯 로고와 검색 아이콘 색상: 접힐수록 primary 색상으로 변경
                final primaryColor = Theme.of(context).colorScheme.primary;
                final iconColor =
                    Color.lerp(Colors.white, primaryColor, collapseProgress)!;

                return Stack(
                  children: [
                    // 🎯 AppBar 배경 (이미지가 투명해졌을 때 점진적으로 표시)
                    if (showAppBarBackground)
                      Positioned.fill(
                        child: Opacity(
                          opacity: backgroundOpacity,
                          child: Container(
                            color: Theme.of(context).colorScheme.background,
                          ),
                        ),
                      ),
                    // 🎯 Hero 섹션 (배경) - 접힐 때 투명해짐
                    Positioned.fill(
                      child: Opacity(
                        opacity: imageOpacity,
                        child: _buildHeroSection(
                          context,
                          searchService,
                          textOpacity: textOpacity, // 위로 스크롤할수록 텍스트가 투명해짐
                        ),
                      ),
                    ),
                    // 로고와 검색 아이콘 오버레이 (상단) - 접힐 때 색상이 primary로 변경
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Doppy 로고
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'Doppy',
                                  style: TextStyle(
                                    color: iconColor,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              // 검색 아이콘
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  right: 12,
                                  left: 12,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    _openSearchExplore();
                                  },
                                  child: SvgPicture.asset(
                                    'assets/icons/ic_search.svg',
                                    width: 28,
                                    height: 28,
                                    // ignore: deprecated_member_use
                                    color: iconColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // 🎯 트렌딩/검색 기록/실시간 검색 결과를 Sliver로 변환
        // 🎯 검색 중일 때는 추천 화면 표시하지 않음
        if (!_isSearching)
          // 🎯 Hero 섹션이 접혔을 때 SafeArea 적용 (콘텐츠가 SafeArea 영역까지 올라가지 않도록)
          SliverSafeArea(
            top: true,
            bottom: false,
            sliver: _buildDefaultSearchBodySliver(context, searchService),
          )
        else
          // 🎯 검색 중일 때는 빈 화면 (로딩은 suffix_icon에 표시)
          SliverFillRemaining(hasScrollBody: false, child: Container()),
      ],
    );
  }

  // 🎯 Hero 섹션 빌드
  Widget _buildHeroSection(
    BuildContext context,
    SearchService searchService, {
    double textOpacity = 1.0,
  }) {
    if (searchService.recommendedPosts.isEmpty) {
      return Container(color: Theme.of(context).colorScheme.background);
    }

    return SearchHeroSection(
      posts: searchService.recommendedPosts,
      textOpacity: textOpacity,
      onPostIndexChanged: (index) {
        setState(() {
          _currentTrendingPostIndex = index;
        });
      },
      onTapPost: (post) {
        final postData = PostData(
          id: post.id,
          thumbnailImageUrl: post.imageUrl ?? '',
          title: post.title ?? '',
          summary: post.summary ?? post.parsedContent ?? '',
          author: post.author ?? post.username ?? '',
          authorProfileImageUrl: post.profileImageUrl ?? '',
          content: post.content ?? '',
          accessLevel: AccessLevel.public,
          viewCount: 0,
          likeCount: post.likes ?? 0,
          commentCount: post.comments ?? 0,
          isLiked: false,
          createdAt: post.createdAt ?? DateTime.now().toIso8601String(),
          updatedAt: post.createdAt ?? DateTime.now().toIso8601String(),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => PostReaderScreen(
                  exported: postData.toExportedData(),
                  heroTag: 'search-post-${post.id}',
                ),
          ),
        );
      },
    );
  }

  // 🎯 기본 검색 화면을 Sliver로 변환
  Widget _buildDefaultSearchBodySliver(
    BuildContext context,
    SearchService searchService,
  ) {
    return Builder(
      key: ValueKey('trending'),
      builder: (_) {
        // 🎯 검색 중일 때는 아무것도 표시하지 않음 (로딩은 suffix_icon에 표시)
        if (_isSearching) {
          return SliverFillRemaining(hasScrollBody: false, child: Container());
        }

        // ✅ 검색(기록/실시간)은 별도 화면(push)로 분리됨
        // 3) 추천 포스트 표시 (OTT 스타일 - Sliver 구조)
        // 🎯 TrendingKeywordsWithPreload는 이제 Sliver를 반환하므로 직접 사용
        final trendingWidget = TrendingListView(
          recommendedPosts: searchService.recommendedPosts,
          friendsPosts: searchService.friendsPosts,
          isLoading: searchService.isRecommendedLoading,
          shouldShowShimmer: searchService.isRecommendedLoading,
          friendsHasMore: searchService.friendsHasMore,
          recommendedHasMore: searchService.recommendedHasMore,
          onTapKeyword: (keyword) {
            // 키워드 기능 제거
          },
          onPostIndexChanged: (index) {
            // 🎯 추천 포스트 인덱스 업데이트
            setState(() {
              _currentTrendingPostIndex = index;
            });
          },
          onLoadMoreFriends: () {
            searchService.loadMoreFriendsPosts();
          },
          onLoadMoreRecommended: () {
            searchService.loadMoreRecommendedPosts();
          },
          onTapPost: (post) {
            // 🎯 포스트 상세 화면으로 이동
            final postData = PostData(
              id: post.id,
              thumbnailImageUrl: post.imageUrl ?? '',
              title: post.title ?? '',
              summary: post.summary ?? post.parsedContent ?? '',
              author: post.author ?? post.username ?? '',
              authorProfileImageUrl: post.profileImageUrl ?? '',
              content: post.content ?? '',
              accessLevel: AccessLevel.public,
              viewCount: 0,
              likeCount: post.likes ?? 0,
              commentCount: post.comments ?? 0,
              isLiked: false,
              createdAt: post.createdAt ?? DateTime.now().toIso8601String(),
              updatedAt: post.createdAt ?? DateTime.now().toIso8601String(),
            );

            Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (_) => PostReaderScreen(
                      exported: postData.toExportedData(),
                      heroTag: 'search-post-${post.id}',
                    ),
              ),
            );
          },
          onRefresh: () async {
            // 🎯 추천 포스트는 스플래시에서 로드한 것을 사용하므로 새로고침하지 않음
            debugPrint('[SearchScreen] 추천 포스트 새로고침 스킵 (스플래시에서 로드한 것 사용)');
          },
        );

        // 🎯 TrendingKeywordsWithPreload가 Sliver를 반환하므로 SliverPadding으로 감싸서 상단 여백 추가
        return SliverPadding(
          padding: const EdgeInsets.only(top: 0, bottom: 0, left: 0, right: 0),
          sliver: trendingWidget,
        );
      },
    );
  }

  // 🎯 검색 결과 뷰 (독립적인 UI, 홈 화면 의존성 제거)
  Widget _buildSearchResultsView(BuildContext context) {
    return SearchResultsView(
      key: ValueKey('search-${_searchRefreshCount}'),
      posts: _searchResults,
      searchQuery: _searchQuery,
      isLoading: _isSearching && _searchResults.isEmpty,
      isLoadingMore: _isLoadingMore,
      hasMore: _searchHasMore,
      onRefresh: _refreshSearchResults,
      onLoadMore: _searchHasMore ? _loadMoreSearchResults : null,
      onPageChanged: (index) {
        setState(() {
          _currentSearchPostIndex = index;
        });
      },
      onSearchChipTap: () {
        // 🎯 검색 결과 칩 탭: 기본 검색 화면으로 돌아가되 검색어만 서치 필드에 입력
        final searchService = context.read<SearchService>();

        // 🎯 리스너 무시 플래그 먼저 설정 (상태 변경 중 리스너 트리거 방지)
        _shouldIgnoreControllerChanges = true;

        // 🎯 검색 결과 화면 숨기기
        _isShowingSearchResults = false;
        _searchResults = [];
        _searchRefreshCount++;

        // 🎯 필드에 검색어 설정 (리스너가 무시되므로 SearchService는 변경되지 않음)
        _searchController.text = _searchQuery;

        // 🎯 SearchService 상태 설정 (clearSearch() 호출하지 않음 - 플로우 끊김 방지)
        // 검색어를 비워서 검색 기록 화면이 표시되도록
        // 단, 리스너가 무시되므로 필드의 검색어는 유지됨
        searchService.onSearchChanged('');

        // 🎯 한 번에 setState로 처리하여 플로우 끊김 최소화
        setState(() {});

        // 🎯 리스너 무시 플래그 해제 및 포커스 설정 (화면이 그려진 후)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _shouldIgnoreControllerChanges = false;
            _searchFocusNode.requestFocus();
          }
        });
      },
      onClearSearch: () {
        // 🎯 검색 필드 비우기
        _searchController.clear();
        final searchService = context.read<SearchService>();
        searchService.clearSearch();

        setState(() {
          _isShowingSearchResults = false;
          _searchResults = [];
          _searchQuery = '';
          _searchRefreshCount++;
        });
      },
    );
  }

  // 🎯 검색 결과 새로고침
  Future<void> _refreshSearchResults() async {
    if (_searchQuery.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final searchService = context.read<SearchService>();
      await searchService.startBlogsSearch(_searchQuery, size: 20);

      final blogResults = searchService.blogResults;
      final posts =
          blogResults.map((item) {
            // 🎯 SearchService에 저장된 원본 서버 데이터 활용
            final originalData = searchService.getPostData(item.id);
            if (originalData != null) {
              // 원본 서버 데이터가 있으면 PostData.fromServer로 변환 (정확한 데이터 사용)
              return PostData.fromServer(originalData);
            } else {
              // fallback: SearchContentItem에서 수동 변환
              return PostData(
                id: item.id,
                thumbnailImageUrl: item.imageUrl ?? '',
                title: item.title ?? '',
                summary: item.summary ?? item.parsedContent ?? '',
                author: item.author ?? item.username ?? '',
                authorProfileImageUrl: item.profileImageUrl ?? '',
                content: item.content ?? '',
                accessLevel: AccessLevel.public,
                viewCount: 0,
                likeCount: item.likes ?? 0,
                commentCount: item.comments ?? 0,
                isLiked: false,
                createdAt:
                    item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
                updatedAt:
                    item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
              );
            }
          }).toList();

      if (mounted) {
        setState(() {
          _searchResults = posts;
          _searchHasMore = searchService.blogsHasMore;
          _searchRefreshCount++;
          _currentSearchPostIndex = 0; // 🎯 검색 결과 새로고침 시 인덱스 리셋
        });
      }
    } catch (e) {
      debugPrint('[SearchOverlay] 검색 새로고침 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  // 🎯 검색 결과 더 불러오기
  Future<void> _loadMoreSearchResults() async {
    if (_isLoadingMore || !_searchHasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final searchService = context.read<SearchService>();
      final items = await searchService.loadMoreBlogs(size: 20);

      final append =
          items.map((item) {
            // 🎯 SearchService에 저장된 원본 서버 데이터 활용
            final originalData = searchService.getPostData(item.id);
            if (originalData != null) {
              // 원본 서버 데이터가 있으면 PostData.fromServer로 변환 (정확한 데이터 사용)
              return PostData.fromServer(originalData);
            } else {
              // fallback: SearchContentItem에서 수동 변환
              return PostData(
                id: item.id,
                thumbnailImageUrl: item.imageUrl ?? '',
                title: item.title ?? '',
                summary: item.summary ?? item.parsedContent ?? '',
                author: item.author ?? item.username ?? '',
                authorProfileImageUrl: item.profileImageUrl ?? '',
                content: item.content ?? '',
                accessLevel: AccessLevel.public,
                viewCount: 0,
                likeCount: item.likes ?? 0,
                commentCount: item.comments ?? 0,
                isLiked: false,
                createdAt:
                    item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
                updatedAt:
                    item.createdAt ?? DateTime.now().toUtc().toIso8601String(),
              );
            }
          }).toList();

      if (mounted) {
        setState(() {
          _searchResults.addAll(append);
          _searchHasMore = searchService.blogsHasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[SearchOverlay] 검색 결과 더 불러오기 실패: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
}
