import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../../theme/app_text_styles.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchService>(
      builder: (context, searchService, child) {
        return Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).colorScheme.background,
              body: SafeArea(
                child: Column(
                  children: [
                    // 🎯 검색 결과가 표시될 때는 검색창 숨김
                    if (!_isShowingSearchResults) ...[
                      _SearchTopBar(
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
            ),
            // 🎯 바텀 네비게이션 바
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomBottomNavigationBar(
                currentIndex: 1, // 검색 탭 활성화
                actualIndex: 1,
                onTap: (index) {
                  debugPrint('[SearchScreen] 바텀 바 탭: $index');

                  if (index == 1) {
                    debugPrint('[SearchScreen] 검색 탭 클릭 무시');
                    return; // 검색 탭은 무시
                  }

                  // 🎯 onTabChange에 위임 (main.dart에서 인덱스 기반으로 처리)
                  debugPrint('[SearchScreen] 탭 전환 위임: $index');
                  widget.onTabChange?.call(index);
                },
                isSearching: true,
                forceOpaqueBackground: true, // 🎯 투명도 없이 배경 색상 표시
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runSearch() async {
    // 🎯 중복 검색 방지
    if (_isSearching) {
      print('[SearchOverlay] 이미 검색 중입니다. 무시.');
      return;
    }

    final searchService = context.read<SearchService>();
    print('[SearchOverlay] runSearch: ${searchService.query}');

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
        });
        print('[SearchOverlay] 검색 완료: ${posts.length}개 결과 (검색 탭에 표시)');
      }
    } catch (e) {
      print('[SearchOverlay] 검색 실패: $e');
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
          return _SearchResults(
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
          return _SearchResults(
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
        return _TrendingKeywordsWithPreload(
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
              PageRouteBuilder(
                pageBuilder:
                    (context, animation, secondaryAnimation) =>
                        PostReaderScreen(
                          exported: postData.toExportedData(),
                          heroTag: 'search-post-${post.id}',
                        ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
                transitionDuration: const Duration(milliseconds: 200),
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

  // 🎯 검색 결과 뷰 (홈 화면과 동일한 구조)
  Widget _buildSearchResultsView(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double _appBarOpacity = 1.0; // 앱바 투명도 (홈스크린과 동일)

    return PostList(
      key: ValueKey('search-${_searchRefreshCount}'),
      containerWidth: screenWidth,
      posts: _searchResults,
      onLoadMore: _searchHasMore ? _loadMoreSearchResults : null,
      isLoadingMore: _isLoadingMore,
      isLoading: _isSearching && _searchResults.isEmpty,
      onRefresh: _refreshSearchResults,
      showCardShimmer: _isSearching && _searchResults.isEmpty,
      onPageChanged: (index) {
        // 페이지 변경 처리 (필요시)
      },
      isShowingSearchResults: true,
      searchQuery: _searchQuery,
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
        setState(() {
          _isShowingSearchResults = false;
          _searchResults = [];
          _searchQuery = '';
          _searchRefreshCount++;
        });
      },
      isShowingFriendsOnly: false,
      showAppBar: true, // 🎯 AppBar는 표시하되 검색 결과 칩만 보이도록
      sectionLabel: _searchQuery.isNotEmpty ? _searchQuery : '검색 결과',
      appBarOpacity: _appBarOpacity,
      isTabActive: true,
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
        });
      }
    } catch (e) {
      print('[SearchOverlay] 검색 새로고침 실패: $e');
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
      print('[SearchOverlay] 검색 결과 더 불러오기 실패: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
}

/// -------------------- 검색 결과 (계정 + 검색 기록) --------------------
class _SearchResults extends StatefulWidget {
  final List<SearchContentItem> accounts;
  final List<String> searchHistory;
  final String query;
  final bool hasNetworkError;
  final VoidCallback onAnyTapDown;
  final Function(SearchContentItem) onTapAccount;
  final Function(String) onTapHistory;
  final Function(SearchContentItem)
  onRemoveHistory; // 🎯 SearchContentItem으로 변경
  final bool enableHero;
  final VoidCallback onTapSearch;

  const _SearchResults({
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
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
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
        _AccountListItem(
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
          _AccountListItem(
            account: account,
            onTapDown: widget.onAnyTapDown,
            onTap: () => widget.onTapAccount(account),
            onRemove: () => widget.onRemoveHistory(account), // 🎯 item 전체 전달
            showRemoveButton: widget.query.isEmpty,
          ),
        );
      }
    }

    return RawScrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 4,
      radius: Radius.circular(2),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children,
      ),
    );
  }
}

class _AccountListItem extends StatelessWidget {
  final SearchContentItem account;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onRemove;
  final bool showRemoveButton;
  const _AccountListItem({
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // 🎯 CommonProfileAvatar로 통일
              CommonProfileAvatar(
                imageUrl: null,
                username: 'search',
                size: 50,
                borderColor: Theme.of(context).colorScheme.background,
                borderWidth: 2,
                centerWidget: Icon(
                  Icons.search,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  account.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              CommonProfileAvatar(
                imageUrl: account.profileImageUrl,
                username: account.username ?? '',
                size: 50.0,
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

class _SearchTopBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final VoidCallback onSubmitted;
  final VoidCallback? onCancel; // 🎯 취소 버튼 콜백
  final bool isSearching; // 🎯 검색 중 여부

  const _SearchTopBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onClear,
    required this.onBack,
    this.onClose,
    required this.onSubmitted,
    this.onCancel,
    this.isSearching = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchService = context.watch<SearchService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          if (searchService.isFocused) ...[
            SizedBox(
              width: 28,
              child: IgnorePointer(
                ignoring:
                    !(searchService.hasSearched || searchService.isFocused),
                child: Opacity(
                  opacity:
                      (!(searchService.hasSearched || searchService.isFocused))
                          ? 0
                          : 1,
                  child: GestureDetector(
                    onTap: onBack,
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 24,
                      color:
                          isDark
                              ? Colors.white.withOpacity(0.75)
                              : Colors.black.withOpacity(0.75),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  FocusScope.of(context).unfocus();
                  onSubmitted();
                },
                onTap: () => context.read<SearchService>().setFocused(true),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
                cursorColor: isDark ? Colors.white : Colors.black,
                decoration: InputDecoration(
                  filled: true,
                  fillColor:
                      isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1),
                  hintText: context.tr('search_placeholder'),
                  hintStyle: TextStyle(
                    color:
                        isDark
                            ? Colors.white.withOpacity(0.6)
                            : Colors.black.withOpacity(0.6),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  suffixIcon:
                      isSearching
                          ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color:
                                    isDark
                                        ? Colors.white.withOpacity(0.8)
                                        : Colors.black.withOpacity(0.8),
                              ),
                            ),
                          )
                          : query.isNotEmpty
                          ? IconButton(
                            tooltip: context.tr('search_hint'),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              onSubmitted();
                            },
                            icon: Icon(
                              Icons.search,
                              color:
                                  isDark
                                      ? Colors.white.withOpacity(0.8)
                                      : Colors.black.withOpacity(0.8),
                              size: 22,
                            ),
                          )
                          : Icon(
                            Icons.search,
                            color:
                                isDark
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black.withOpacity(0.6),
                            size: 22,
                          ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// -------------------- 실시간 검색어 (이미지 프리로드 포함) --------------------
class _TrendingKeywordsWithPreload extends StatefulWidget {
  final List<String> keywords;
  final List<SearchContentItem> recommendedPosts;
  final bool isLoading;
  final bool shouldShowShimmer;
  final Function(String) onTapKeyword;
  final Function(SearchContentItem) onTapPost;
  final Future<void> Function()? onRefresh;

  const _TrendingKeywordsWithPreload({
    required this.keywords,
    required this.recommendedPosts,
    required this.isLoading,
    required this.shouldShowShimmer,
    required this.onTapKeyword,
    required this.onTapPost,
    this.onRefresh,
  });

  @override
  State<_TrendingKeywordsWithPreload> createState() =>
      _TrendingKeywordsWithPreloadState();
}

class _TrendingKeywordsWithPreloadState
    extends State<_TrendingKeywordsWithPreload> {
  bool _imagesPreloaded = false;
  bool _isPreloading = false;
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    // initState에서는 context를 사용할 수 없으므로 didChangeDependencies에서 처리
  }

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
  void didUpdateWidget(_TrendingKeywordsWithPreload oldWidget) {
    super.didUpdateWidget(oldWidget);
    // recommendedPosts가 변경되거나 shimmer 상태가 변경되면 다시 프리로드
    if (widget.recommendedPosts != oldWidget.recommendedPosts ||
        widget.shouldShowShimmer != oldWidget.shouldShowShimmer) {
      _imagesPreloaded = false;
      _isPreloading = false;
      _preloadImagesIfNeeded();
    }
  }

  Future<void> _preloadImagesIfNeeded() async {
    // 이미 프리로드 중이거나 완료했으면 스킵
    if (_isPreloading || _imagesPreloaded) {
      return;
    }

    // recommendedPosts가 없으면 스킵
    if (widget.recommendedPosts.isEmpty) {
      _imagesPreloaded = true;
      return;
    }

    // recommendedPosts가 5개 미만이면 모두, 5개 이상이면 5개만 프리로드
    final postsToPreload = widget.recommendedPosts.take(5).toList();

    // 이미지 URL 추출
    final imageUrls =
        postsToPreload
            .where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty)
            .map((post) => post.imageUrl!)
            .toList();

    if (imageUrls.isEmpty) {
      _imagesPreloaded = true;
      return;
    }

    _isPreloading = true;
    debugPrint('[TrendingKeywords] 이미지 프리로드 시작: ${imageUrls.length}개');

    try {
      // 동기적으로 모든 이미지 프리로드
      await Future.wait(
        imageUrls.map((url) {
          return precacheImage(
            NetworkImage(url),
            context,
            onError: (e, stack) {
              debugPrint('[TrendingKeywords] 이미지 프리로드 실패: $url - $e');
            },
          );
        }),
      );

      debugPrint('[TrendingKeywords] 이미지 프리로드 완료');
      if (mounted) {
        setState(() {
          _imagesPreloaded = true;
          _isPreloading = false;
        });
      }
    } catch (e) {
      debugPrint('[TrendingKeywords] 이미지 프리로드 중 오류: $e');
      if (mounted) {
        setState(() {
          _imagesPreloaded = true; // 에러가 나도 계속 진행
          _isPreloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[TrendingKeywords] build - keywords: ${widget.keywords.length}, posts: ${widget.recommendedPosts.length}, isLoading: ${widget.isLoading}, shouldShowShimmer: ${widget.shouldShowShimmer}, _imagesPreloaded: $_imagesPreloaded',
    );

    // 🎯 shimmer를 표시해야 하는 경우 (새로고침 중이거나 로딩 중일 때만)
    // 캐시 사용 시에는 이미지 프리로드가 완료되지 않아도 shimmer 표시하지 않음
    if (widget.shouldShowShimmer) {
      return const _TrendingKeywordsShimmer();
    }

    // 이미지 프리로드가 완료되지 않았어도 캐시 사용 시에는 기존 데이터 표시
    // (이미지가 로드되는 동안 기존 데이터를 보여줌)

    // 🎯 키워드와 추천 포스트 모두 없는 경우
    if (widget.keywords.isEmpty && widget.recommendedPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [],
        ),
      );
    }

    return CustomRefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 🎯 실시간 검색어 리스트
          if (widget.keywords.isNotEmpty) ...[
            ...widget.keywords.map((keyword) {
              return _AccountListItem(
                account: SearchContentItem.blogKeyword(
                  id: 'trending_$keyword',
                  keyword: keyword,
                ),
                onTap: () => widget.onTapKeyword(keyword),
                showRemoveButton: false,
              );
            }).toList(),
            const SizedBox(height: 30),
          ],

          // 🎯 추천 콘텐츠 섹션 (실제 데이터)
          if (widget.recommendedPosts.isNotEmpty) ...[
            Builder(
              builder: (context) {
                debugPrint(
                  '[TrendingKeywords] Rendering posts: ${widget.recommendedPosts.length}',
                );
                return _RecommendedContentSection(
                  title: '추천 포스트',
                  posts: widget.recommendedPosts,
                  onTapItem: (post) => widget.onTapPost(post),
                );
              },
            ),
          ] else ...[
            Builder(
              builder: (context) {
                debugPrint('[TrendingKeywords] No posts to display');
                return const SizedBox.shrink();
              },
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

/// -------------------- 실시간 검색어 Shimmer --------------------
class _TrendingKeywordsShimmer extends StatelessWidget {
  const _TrendingKeywordsShimmer();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 32) / 1.5;
    final cardImageHeight = cardWidth * 5 / 4;
    final cardTotalHeight = cardImageHeight + 40;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 🎯 실시간 검색어 Shimmer
        ...List.generate(5, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                // 원형 아이콘
                ShimmerBox(
                  width: 50,
                  height: 50,
                  borderRadius: BorderRadius.circular(25),
                ),
                const SizedBox(width: 16),
                // 텍스트
                Expanded(
                  child: ShimmerBox(
                    width: 120,
                    height: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 30),

        // 🎯 추천 콘텐츠 섹션 Shimmer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ShimmerBox(
            width: 100,
            height: 18,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardTotalHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            itemBuilder: (context, index) {
              return Container(
                width: cardWidth,
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 썸네일 Shimmer
                    ShimmerBox(
                      width: cardWidth,
                      height: cardImageHeight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    const SizedBox(height: 8),
                    // 타이틀 Shimmer
                    ShimmerBox(
                      width: cardWidth,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 4),
                    ShimmerBox(
                      width: cardWidth * 0.7,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// -------------------- 추천 콘텐츠 섹션 --------------------
class _RecommendedContentSection extends StatefulWidget {
  final String title;
  final List<SearchContentItem> posts;
  final Function(SearchContentItem) onTapItem;

  const _RecommendedContentSection({
    required this.title,
    required this.posts,
    required this.onTapItem,
  });

  @override
  State<_RecommendedContentSection> createState() =>
      _RecommendedContentSectionState();
}

class _RecommendedContentSectionState
    extends State<_RecommendedContentSection> {
  @override
  Widget build(BuildContext context) {
    // 🎯 안전 장치: posts가 비어있으면 빈 위젯 반환
    if (widget.posts.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 16) / 1.5; // 좌우 패딩 16씩 제외 후 1.5개 표시
    final cardImageHeight = cardWidth * 5 / 4; // 4:5 비율
    final cardTotalHeight = cardImageHeight + 80; // 이미지 + 타이틀 영역

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardTotalHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // 가로 스크롤일 때는 리프레시를 막기 위해 true 반환 (이벤트 소비)
              if (notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) {
                if (notification.metrics.axis == Axis.horizontal) {
                  return true; // 이벤트 소비하여 리프레시 방지
                }
              }
              return false;
            },
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16, right: 16),
              itemCount: widget.posts.length,
              itemBuilder: (context, index) {
                // 🎯 안전 장치: 인덱스 범위 체크
                if (index < 0 || index >= widget.posts.length) {
                  debugPrint('[RecommendedContent] ⚠️ 인덱스 범위 초과: $index');
                  return const SizedBox.shrink();
                }

                final post = widget.posts[index];
                return Padding(
                  padding: EdgeInsets.only(
                    right: index < widget.posts.length - 1 ? 10 : 0,
                  ),
                  child: _PostCard(
                    post: post,
                    cardWidth: cardWidth,
                    cardImageHeight: cardImageHeight,
                    onTap: () => widget.onTapItem(post),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// -------------------- 포스트 카드 --------------------
class _PostCard extends StatefulWidget {
  final SearchContentItem post;
  final double cardWidth;
  final double cardImageHeight;
  final VoidCallback onTap;

  const _PostCard({
    required this.post,
    required this.cardWidth,
    required this.cardImageHeight,
    required this.onTap,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[PostCard] initState - ${widget.post.id}: ${widget.post.title}',
    );
  }

  @override
  void dispose() {
    debugPrint('[PostCard] dispose - ${widget.post.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🎯 AutomaticKeepAliveClientMixin 필수

    // 🎯 비디오 파일 URL 체크
    final isVideoUrl =
        widget.post.imageUrl != null &&
        (widget.post.imageUrl!.toLowerCase().endsWith('.mp4') ||
            widget.post.imageUrl!.toLowerCase().endsWith('.mov') ||
            widget.post.imageUrl!.toLowerCase().endsWith('.avi') ||
            widget.post.imageUrl!.toLowerCase().endsWith('.webm'));

    final shouldShowImage =
        widget.post.imageUrl != null &&
        widget.post.imageUrl!.isNotEmpty &&
        !isVideoUrl;

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🎯 썸네일 이미지 (4:5 비율)
          Container(
            width: widget.cardWidth,
            height: widget.cardImageHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child:
                isVideoUrl
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _ThumbnailVideoPlayer(
                        videoUrl: widget.post.imageUrl!,
                        width: widget.cardWidth,
                        height: widget.cardImageHeight,
                      ),
                    )
                    : shouldShowImage
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        widget.post.imageUrl!,
                        width: widget.cardWidth,
                        height: widget.cardImageHeight,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.image,
                              size: 40,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                            ),
                          );
                        },
                      ),
                    )
                    : Center(
                      child: Icon(
                        Icons.image,
                        size: 40,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                      ),
                    ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CommonProfileAvatar(
                imageUrl: widget.post.profileImageUrl,
                username: widget.post.author ?? '',
                size: 28,
                borderColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.6),
                borderWidth: 0.4,
              ),
              const SizedBox(width: 6),
              Text(
                widget.post.title ?? '제목 없음',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// -------------------- 썸네일 비디오 플레이어 --------------------
class _ThumbnailVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double width;
  final double height;

  const _ThumbnailVideoPlayer({
    required this.videoUrl,
    required this.width,
    required this.height,
  });

  @override
  State<_ThumbnailVideoPlayer> createState() => _ThumbnailVideoPlayerState();
}

class _ThumbnailVideoPlayerState extends State<_ThumbnailVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint('[ThumbnailVideoPlayer] 초기화 시작: ${widget.videoUrl}');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();

      debugPrint('[ThumbnailVideoPlayer] 초기화 완료');

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // 🎯 음소거 및 자동 재생
        await _controller!.setVolume(0.0);
        await _controller!.setLooping(true);
        await _controller!.play();

        debugPrint('[ThumbnailVideoPlayer] 재생 시작');
      }
    } catch (e) {
      debugPrint('[ThumbnailVideoPlayer] error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[ThumbnailVideoPlayer] dispose - ${widget.videoUrl}');
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🎯 AutomaticKeepAliveClientMixin 필수

    if (_hasError) {
      return Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 40,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withOpacity(0.3),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(color: Theme.of(context).colorScheme.surfaceVariant);
    }

    // 🎯 안전 장치: 비디오 사이즈 체크
    final videoSize = _controller!.value.size;
    if (videoSize.width <= 0 || videoSize.height <= 0) {
      debugPrint('[ThumbnailVideoPlayer] ⚠️ 유효하지 않은 비디오 사이즈');
      return Container(color: Theme.of(context).colorScheme.surfaceVariant);
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: videoSize.width,
          height: videoSize.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}
