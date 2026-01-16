import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/search_top_bar.dart';
import 'package:doppy/pages/components/search_result.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

/// 🎯 검색(기록 + 실시간 계정 검색) 화면 (별도 화면으로 분리)
class SearchExploreScreen extends StatefulWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onClose;

  const SearchExploreScreen({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchSubmitted,
    required this.onClose,
  });

  @override
  State<SearchExploreScreen> createState() => _SearchExploreScreenState();
}

class _SearchExploreScreenState extends State<SearchExploreScreen> {
  bool _isNavigating = false;
  bool _isBlogSearching = false;

  PageRouteBuilder<T> _noAnimRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final searchService = context.read<SearchService>();
      widget.searchFocusNode.requestFocus();
      searchService.onSearchChanged(widget.searchController.text);
    });
  }

  void _clearSearch() {
    widget.searchController.clear();
    context.read<SearchService>().onSearchChanged('');
  }

  Future<void> _submitBlogSearch(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return;

    setState(() {
      _isBlogSearching = true;
    });

    try {
      final searchService = context.read<SearchService>();
      await searchService.startBlogsSearch(q, size: 20);

      final blogResults = searchService.blogResults;
      final posts =
          blogResults.map((item) {
            final originalData = searchService.getPostData(item.id);
            if (originalData != null) {
              return PostData.fromServer(originalData);
            }
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
          }).toList();

      if (!mounted) return;
      setState(() {
        _isBlogSearching = false;
      });

      await Navigator.of(context).push(
        _noAnimRoute(
          SearchBlogResultsScreen(
            keyword: q,
            initialPosts: posts,
            initialHasMore: searchService.blogsHasMore,
          ),
        ),
      );

      // ✅ 결과 화면에서 돌아오면, 검색 중 플래그를 강제로 해제
      if (mounted) {
        searchService.clearSearchingFlag();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isBlogSearching = false;
      });
    }
  }

  void _popAndReset() {
    final searchService = context.read<SearchService>();
    searchService.onSearchChanged('');
    // ✅ 뒤로가기 시 검색 중 플래그 강제 해제
    searchService.clearSearchingFlag();
    widget.searchController.clear();
    widget.searchFocusNode.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final searchService = context.watch<SearchService>();
    final q = searchService.query.trim();
    final isLiveSearch = q.isNotEmpty;
    final historyItems = searchService.searchHistory;
    final accounts = searchService.searchingAccounts;
    final isRealtimeSearching = searchService.isSearching;
    final isSearching = _isBlogSearching;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 검색창
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
              child: SearchTopBar(
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
                query: searchService.query,
                onClear: _clearSearch,
                onBack: () {
                  _popAndReset();
                },
                onClose: widget.onClose,
                onSubmitted: () {
                  _submitBlogSearch(widget.searchController.text);
                },
                onCancel: () {
                  _popAndReset();
                },
                isSearching: isSearching,
              ),
            ),
            // 검색 기록 / 실시간 검색 결과
            Expanded(
              child:
                  isLiveSearch
                      ? (_isBlogSearching
                          ? const SizedBox.shrink()
                          : (accounts.isEmpty && isRealtimeSearching
                              ? const SizedBox.shrink()
                              : (accounts.isEmpty
                                  ? Center(
                                    child: Text(
                                      '검색 결과가 없습니다',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.5),
                                        fontSize: 14,
                                      ),
                                    ),
                                  )
                                  : ListView.builder(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 8,
                                    ),
                                    itemCount: accounts.length + 1,
                                    itemBuilder: (context, index) {
                                      // 첫 번째 아이템: 글 검색 실행 타일
                                      if (index == 0) {
                                        return AccountListItem(
                                          account:
                                              SearchContentItem.blogKeyword(
                                                id: 'current_search',
                                                keyword: q,
                                              ),
                                          onTap: () {
                                            widget.searchController.text = q;
                                            searchService.onSearchChanged(q);
                                            _submitBlogSearch(q);
                                          },
                                          onTapDown: () {},
                                          showRemoveButton: false,
                                        );
                                      }

                                      final item = accounts[index - 1];
                                      return AccountListItem(
                                        account: item,
                                        onTapDown: () {},
                                        onTap: () {
                                          if (_isNavigating) return;
                                          setState(() {
                                            _isNavigating = true;
                                          });

                                          Navigator.push(
                                                context,
                                                _noAnimRoute(
                                                  UserProfileScreen(
                                                    otherUser: User(
                                                      username:
                                                          item.username ?? '',
                                                      alias: item.alias,
                                                      profileImageUrl:
                                                          item.profileImageUrl,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .then((_) {
                                                if (mounted) {
                                                  setState(() {
                                                    _isNavigating = false;
                                                  });
                                                  widget.searchFocusNode
                                                      .requestFocus();
                                                }
                                              })
                                              .catchError((error) {
                                                debugPrint(
                                                  '[SearchExploreScreen] 네비게이션 에러: $error',
                                                );
                                                if (mounted) {
                                                  setState(() {
                                                    _isNavigating = false;
                                                  });
                                                }
                                              });
                                        },
                                        onRemove: null,
                                        showRemoveButton: false,
                                      );
                                    },
                                  ))))
                      : (historyItems.isEmpty
                          ? Center(
                            child: Text(
                              '검색 기록이 없습니다',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                                fontSize: 14,
                              ),
                            ),
                          )
                          : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            itemCount: historyItems.length,
                            itemBuilder: (context, index) {
                              final item = historyItems[index];
                              return AccountListItem(
                                account: item,
                                onTapDown: () {},
                                onTap: () {
                                  if (_isNavigating) return;

                                  // 🎯 글 검색 기록이면 검색 실행 후 pop
                                  if (item.isBlog) {
                                    widget.searchController.text =
                                        item.title ?? '';
                                    searchService.onSearchChanged(
                                      item.title ?? '',
                                    );
                                    _submitBlogSearch(item.title ?? '');
                                    return;
                                  }

                                  setState(() {
                                    _isNavigating = true;
                                  });

                                  Navigator.push(
                                        context,
                                        _noAnimRoute(
                                          UserProfileScreen(
                                            otherUser: User(
                                              username: item.username ?? '',
                                              alias: item.alias,
                                              profileImageUrl:
                                                  item.profileImageUrl,
                                            ),
                                          ),
                                        ),
                                      )
                                      .then((_) {
                                        if (mounted) {
                                          setState(() {
                                            _isNavigating = false;
                                          });
                                          widget.searchFocusNode.requestFocus();
                                        }
                                      })
                                      .catchError((error) {
                                        debugPrint(
                                          '[SearchExploreScreen] 네비게이션 에러: $error',
                                        );
                                        if (mounted) {
                                          setState(() {
                                            _isNavigating = false;
                                          });
                                        }
                                      });
                                },
                                onRemove: () {
                                  if (item.isBlog) {
                                    context
                                        .read<SearchService>()
                                        .removeBlogSearchKeyword(
                                          item.title ?? '',
                                        );
                                  } else {
                                    context
                                        .read<SearchService>()
                                        .removeFromSearchHistory(
                                          item.username ?? '',
                                        );
                                  }
                                },
                                showRemoveButton: true,
                              );
                            },
                          )),
            ),
          ],
        ),
      ),
    );
  }
}
