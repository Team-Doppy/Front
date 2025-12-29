import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/search_top_bar.dart';
import 'package:doppy/pages/components/search_results.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/pages/components/search_trending_section.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/search_service.dart';

class SearchScreenOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final String? initialQuery; // 초기 검색어 (검색어 칩에서 올 때)
  final Function(int)? onTabChange; // 🎯 바텀 바 탭 변경

  const SearchScreenOverlay({
    super.key,
    this.onClose,
    this.initialQuery,
    this.onTabChange,
  });

  @override
  State<SearchScreenOverlay> createState() => _SearchScreenOverlayState();
}

class _SearchScreenOverlayState extends State<SearchScreenOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _hasNetworkError = false;
  bool _isSearching = false; // 🎯 중복 검색 방지
  bool _isNavigating = false; // 🎯 네비게이션 중 중복 탭 방지
  bool _shouldIgnoreControllerChanges = false; // 🎯 검색 칩 탭 시 리스너 무시 플래그

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
    final hasInitialQuery =
        widget.initialQuery != null && widget.initialQuery!.isNotEmpty;

    if (hasInitialQuery) {
      _searchController.text = widget.initialQuery!;
    }

    _searchController.addListener(() {
      // 🎯 검색어 변경 시 SearchService 업데이트
      // 단, 검색 칩 탭으로 인한 변경은 무시
      if (!_shouldIgnoreControllerChanges) {
        context.read<SearchService>().onSearchChanged(_searchController.text);
      }
    });

    _searchFocusNode.addListener(() {
      context.read<SearchService>().setFocused(_searchFocusNode.hasFocus);
    });

    // 🎯 초기화 및 초기 검색어 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 🎯 UI 렌더링 완료 후 지연 실행하여 블로킹 방지
      Future.delayed(const Duration(milliseconds: 300), () async {
        if (!mounted) return;

        final searchService = context.read<SearchService>();

        // 🎯 초기 검색어가 있으면 포커스 설정
        if (hasInitialQuery) {
          searchService.onSearchChanged(widget.initialQuery!);
          searchService.setFocused(true);
          debugPrint('[SearchScreen] 초기 검색어로 포커스 설정: ${widget.initialQuery}');
        }

        // initialize는 백그라운드에서 실행 (캐시 사용)
        await searchService.initialize(forceRefresh: false);

        debugPrint('[SearchScreen] 초기화 완료');
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 🎯 초기 검색어가 있으면 화면 빌드 전에 트렌딩 데이터 즉시 지우기
    final hasInitialQuery =
        widget.initialQuery != null && widget.initialQuery!.isNotEmpty;

    if (hasInitialQuery) {
      final searchService = context.read<SearchService>();
      searchService.clearTrendingData();
      debugPrint(
        '[SearchScreen] didChangeDependencies - 초기 검색어로 인해 트렌딩 데이터 지움',
      );
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
      searchService.clearTrendingData();

      // 검색어 설정 및 포커스
      _searchController.text = widget.initialQuery!;
      searchService.onSearchChanged(widget.initialQuery!);
      searchService.setFocused(true);
      _searchFocusNode.requestFocus();

      debugPrint(
        '[SearchScreen] didUpdateWidget - 초기 검색어로 인해 트렌딩 데이터 지움 및 검색어 설정: ${widget.initialQuery}',
      );
    } else if (!hasInitialQuery && hadInitialQuery) {
      // 초기 검색어가 제거되었을 때 (검색어 클리어)
      _searchController.clear();
      final searchService = context.read<SearchService>();
      searchService.clearSearch();
      searchService.setFocused(false);
      _searchFocusNode.unfocus();
      debugPrint('[SearchScreen] didUpdateWidget - 초기 검색어 제거됨');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<SearchService>().clearSearch();
  }

  void _resetToInitial() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    context.read<SearchService>().resetToInitial();
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
    return Consumer<SearchService>(
      builder: (context, searchService, child) {
        // 🎯 현재 배경 이미지 URL 가져오기
        final backgroundImageUrl = _getCurrentBackgroundImageUrl(searchService);

        return Scaffold(
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
              SafeArea(
                child: Column(
                  children: [
                    // 🎯 검색 결과가 표시될 때는 검색창 숨김
                    if (!_isShowingSearchResults) ...[
                      SearchTopBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        query: searchService.query,
                        onClear: _clearSearch,
                        onBack: _resetToInitial,
                        onClose: widget.onClose,
                        onSubmitted: _runSearch,
                        onCancel: () {
                          _searchFocusNode.unfocus();
                          context.read<SearchService>().setFocused(false);
                        },
                        isSearching: _isSearching, // 🎯 검색 중 여부 전달
                      ),
                    ],
                    Expanded(
                      child:
                          _isShowingSearchResults
                              ? _buildSearchResultsView(context)
                              : _buildDefaultSearchBody(context, searchService),
                    ),
                  ],
                ),
              ),
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
        _hasNetworkError = false;
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
                createdAt: item.createdAt ?? DateTime.now().toIso8601String(),
                updatedAt: item.createdAt ?? DateTime.now().toIso8601String(),
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
          _hasNetworkError = true;
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

  // 🎯 기본 검색 화면 (trending/history/live)
  Widget _buildDefaultSearchBody(
    BuildContext context,
    SearchService searchService,
  ) {
    return Builder(
      key: ValueKey(
        searchService.query.isNotEmpty
            ? 'live'
            : (searchService.isFocused ? 'history' : 'trending'),
      ),
      builder: (_) {
        // 1) 입력 중: 실시간 계정 검색 결과
        if (searchService.query.isNotEmpty && searchService.isFocused) {
          return SearchResults(
            accounts: searchService.searchingAccounts,
            searchHistory: const [],
            query: searchService.query,
            hasNetworkError: _hasNetworkError,
            onAnyTapDown: () {},
            onTapAccount: (item) {
              // 🎯 중복 탭 방지
              if (_isNavigating) return;

              setState(() {
                _isNavigating = true;
              });

              searchService.onTapContentItem(
                item,
                onNavigateToProfile: (username) {
                  Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => UserProfileScreen(
                                otherUser: User(
                                  username: username,
                                  alias: item.alias,
                                  profileImageUrl: item.profileImageUrl,
                                ),
                              ),
                        ),
                      )
                      .then((_) {
                        if (mounted) {
                          setState(() {
                            _isNavigating = false;
                          });
                          _searchFocusNode.requestFocus();
                        }
                      })
                      .catchError((error) {
                        debugPrint('[SearchScreen] 네비게이션 에러: $error');
                        if (mounted) {
                          setState(() {
                            _isNavigating = false;
                          });
                        }
                      });
                },
              );
            },
            onTapHistory: (_) {},
            onRemoveHistory: (item) {},
            enableHero: true,
            onTapSearch: _runSearch,
          );
        }

        // 2) 포커스 O & 쿼리 없음: 검색 기록 펼침
        if (searchService.isFocused) {
          return SearchResults(
            accounts: searchService.searchHistory,
            searchHistory: const [],
            query: '',
            hasNetworkError: false,
            onAnyTapDown: () {},
            onTapAccount: (item) {
              // 🎯 중복 탭 방지
              if (_isNavigating) return;

              // 🎯 글 검색 기록이면 검색 실행
              if (item.isBlog) {
                _searchController.text = item.title ?? '';
                searchService.onSearchChanged(item.title ?? '');
                _runSearch();
                return;
              }

              setState(() {
                _isNavigating = true;
              });

              Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => UserProfileScreen(
                            otherUser: User(
                              username: item.username ?? '',
                              alias: item.alias,
                              profileImageUrl: item.profileImageUrl,
                            ),
                          ),
                    ),
                  )
                  .then((_) {
                    if (mounted) {
                      setState(() {
                        _isNavigating = false;
                      });
                      _searchFocusNode.requestFocus();
                    }
                  })
                  .catchError((error) {
                    debugPrint('[SearchScreen] 네비게이션 에러: $error');
                    if (mounted) {
                      setState(() {
                        _isNavigating = false;
                      });
                    }
                  });
            },
            onTapHistory: (_) {},
            onRemoveHistory: (item) {
              // 🎯 글 검색 기록이면 글 검색 기록에서 제거
              if (item.isBlog) {
                context.read<SearchService>().removeBlogSearchKeyword(
                  item.title ?? '',
                );
              } else {
                context.read<SearchService>().removeFromSearchHistory(
                  item.username ?? '',
                );
              }
            },
            enableHero: false,
            onTapSearch: _runSearch,
          );
        }

        // 3) 포커스 X: 실시간 검색어 표시
        return TrendingKeywordsWithPreload(
          keywords: searchService.trendingKeywords,
          recommendedPosts: searchService.recommendedPosts,
          isLoading: searchService.isTrendingLoading,
          shouldShowShimmer:
              searchService.shouldShowShimmer, // 🎯 shimmer 표시 여부
          onTapKeyword: (keyword) {
            _searchController.text = keyword;
            context.read<SearchService>().onSearchChanged(keyword);
            _runSearch();
          },
          onPostIndexChanged: (index) {
            // 🎯 트렌딩 포스트 인덱스 업데이트
            setState(() {
              _currentTrendingPostIndex = index;
            });
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
            // 🎯 트렌딩 데이터 새로고침
            debugPrint('[SearchScreen] 트렌딩 데이터 새로고침 시작');
            await searchService.fetchTrendingKeywords(forceRefresh: true);
            debugPrint('[SearchScreen] 트렌딩 데이터 새로고침 완료');
          },
        );
      },
    );
  }

  // 🎯 검색 결과 뷰 (독립적인 UI, 홈 화면 의존성 제거)
  Widget _buildSearchResultsView(BuildContext context) {
    return _SearchResultsView(
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
        // 1. 포커스 설정 먼저 (검색 기록 화면 표시를 위해)
        searchService.setFocused(true);

        // 2. 검색어를 비워서 검색 기록 화면이 표시되도록
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
                createdAt: item.createdAt ?? DateTime.now().toIso8601String(),
                updatedAt: item.createdAt ?? DateTime.now().toIso8601String(),
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
                createdAt: item.createdAt ?? DateTime.now().toIso8601String(),
                updatedAt: item.createdAt ?? DateTime.now().toIso8601String(),
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

/// -------------------- 검색 결과 뷰 (독립적인 UI) --------------------
class _SearchResultsView extends StatefulWidget {
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

  const _SearchResultsView({
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
  State<_SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<_SearchResultsView> {
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
    _likeService.addListener(_onLikeServiceChanged);
    _loadLikeStatusForAllPosts();
  }

  @override
  void didUpdateWidget(_SearchResultsView oldWidget) {
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
      // 🎯 가로/세로 제스처 감지 (PostList와 동일)
      onPointerMove: (details) {
        if (!_isGestureActive) {
          setState(() {
            _isGestureActive = true;
          });
        }

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
                _currentIndex < widget.posts.length - 1) {
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
      },
      onPointerUp: (details) {
        setState(() {
          _isGestureActive = false;
          _isHorizontalGesture = false;
        });
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
            toolbarHeight: 35,
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
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.8),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.searchQuery,
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: widget.onClearSearch,
                                    child: Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.8),
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
                    children: [
                      Text(
                        AppLocalizations.of(
                          context,
                        ).translate('no_search_results'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).translate('try_different_search'),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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
                  containerWidth: screenWidth,
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
