import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_text_styles.dart';
import '../../../data/services/search_service.dart';

class SearchScreenOverlay extends StatefulWidget {
  final Function(List<PostData>, String)? onSearchComplete; // 검색 결과와 검색어 함께 전달
  final VoidCallback? onClose;
  final String? initialQuery; // 초기 검색어 (검색어 칩에서 올 때)

  const SearchScreenOverlay({
    super.key,
    this.onSearchComplete,
    this.onClose,
    this.initialQuery,
  });

  @override
  State<SearchScreenOverlay> createState() => _SearchScreenOverlayState();
}

class _SearchScreenOverlayState extends State<SearchScreenOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _freezeDuringPush = false;
  List<SearchContentItem> _frozenAccounts = const [];
  String _freezeKind = '';
  bool _hasNetworkError = false;
  bool _suppressAnimOnce = false;

  @override
  void initState() {
    super.initState();

    // 초기 검색어가 있으면 설정
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SearchService>().initialize();
      if (mounted) {
        // 초기 검색어가 있으면 검색 실행
        if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
          context.read<SearchService>().onSearchChanged(widget.initialQuery!);
        } else {
          // 초기 검색어가 없으면 검색 기록을 표시
          context.read<SearchService>().setFocused(true);
        }
      }
    });

    _searchController.addListener(() {
      context.read<SearchService>().onSearchChanged(_searchController.text);
    });

    _searchFocusNode.addListener(() {
      final svc = context.read<SearchService>();
      if (!svc.isViewLocked) {
        svc.setFocused(_searchFocusNode.hasFocus);
      }
    });
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
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 5),
                _SearchTopBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  query: searchService.query,
                  onClear: _clearSearch,
                  onBack: _resetToInitial,
                  onClose: widget.onClose,
                  onSubmitted: _runSearch,
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: searchService,
                    builder: (_, __) {
                      final bool disableAnim =
                          _freezeDuringPush ||
                          _suppressAnimOnce ||
                          searchService.query.isNotEmpty;
                      return AnimatedSwitcher(
                        duration:
                            disableAnim
                                ? const Duration(milliseconds: 0)
                                : const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) {
                          if (disableAnim) return child;
                          final slide = Tween<Offset>(
                            begin: const Offset(0.0, 0.04),
                            end: Offset.zero,
                          ).animate(anim);
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: _buildSearchBody(context, searchService),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runSearch() async {
    final searchService = context.read<SearchService>();
    print('[SearchOverlay] runSearch: ${searchService.query}');
    try {
      // 빈 검색어면 수행하지 않음
      if (searchService.query.trim().isEmpty) {
        return;
      }
      setState(() => _hasNetworkError = false);
      // 페이지네이션 초기화: 20개씩
      await searchService.startBlogsSearch(searchService.query, size: 20);
      final blogResults = searchService.blogResults;
      final posts =
          blogResults.map((item) {
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
          }).toList();
      widget.onSearchComplete?.call(posts, searchService.query);
    } catch (e) {
      print('[SearchOverlay] 검색 실패: $e');
      setState(() => _hasNetworkError = true);
      widget.onSearchComplete?.call([], searchService.query);
    }
  }

  Widget _buildSearchBody(BuildContext context, SearchService searchService) {
    if (_freezeDuringPush) {
      final enableHero = _freezeKind == 'live';
      return _SearchResults(
        accounts: _frozenAccounts,
        searchHistory: const [],
        query: enableHero ? searchService.query : '',
        hasNetworkError: _hasNetworkError,
        onAnyTapDown: () {},
        onTapAccount: (item) {},
        onTapHistory: (_) {},
        onRemoveHistory: (_) {},
        enableHero: enableHero,
        onTapSearch: _runSearch,
      );
    }
    return Builder(
      key: ValueKey(
        _freezeDuringPush
            ? 'live'
            : (searchService.query.isNotEmpty
                ? 'live'
                : (searchService.isFocused ? 'history' : 'grid')),
      ),
      builder: (_) {
        // 1) 입력 중: 실시간 계정 검색 결과
        if (searchService.query.isNotEmpty && searchService.isFocused) {
          return _SearchResults(
            accounts: searchService.searchingAccounts,
            searchHistory: const [],
            query: searchService.query,
            hasNetworkError: _hasNetworkError,
            onAnyTapDown:
                () => setState(() {
                  _freezeDuringPush = true;
                  _freezeKind = 'live';
                  _frozenAccounts = List.of(searchService.searchingAccounts);
                }),
            onTapAccount: (item) {
              // 뷰 잠금 후 네비게이션 (포커스 변화 억제)
              searchService.lockView();
              searchService.onTapContentItem(
                item,
                onNavigateToProfile: (username) {
                  final route = MaterialPageRoute(
                    builder:
                        (_) => UserProfileScreen(
                          otherUser: User(
                            username: username,
                            alias: item.alias,
                            profileImageUrl: item.profileImageUrl,
                          ),
                        ),
                  );
                  Navigator.push(context, route).whenComplete(() {
                    if (!mounted) return;
                    setState(() {
                      _freezeDuringPush = false;
                      _suppressAnimOnce = true;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _suppressAnimOnce = false);
                    });
                    final svc = context.read<SearchService>();
                    svc.unlockView();
                    svc.setFocused(true);
                    _searchFocusNode.requestFocus();
                  });
                },
              );
            },
            onTapHistory: (_) {},
            onRemoveHistory: (_) {},
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
            onAnyTapDown:
                () => setState(() {
                  _freezeDuringPush = true;
                  _freezeKind = 'history';
                  _frozenAccounts = List.of(searchService.searchHistory);
                }),
            onTapAccount: (item) {
              context.read<SearchService>().lockView();

              final route = MaterialPageRoute(
                builder:
                    (_) => UserProfileScreen(
                      otherUser: User(
                        username: item.username ?? '',
                        alias: item.alias,
                        profileImageUrl: item.profileImageUrl,
                      ),
                    ),
              );
              Navigator.push(context, route).whenComplete(() {
                if (!mounted) return;
                setState(() {
                  _freezeDuringPush = false;
                  _suppressAnimOnce = true;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _suppressAnimOnce = false);
                });
                final svc = context.read<SearchService>();
                svc.unlockView();
                svc.setFocused(true);
                _searchFocusNode.requestFocus();
              });
            },
            onTapHistory: (_) {},
            onRemoveHistory: (username) {
              context.read<SearchService>().removeFromSearchHistory(username);
            },
            enableHero: false,
            onTapSearch: _runSearch,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

/// -------------------- 검색 결과 (계정 + 검색 기록) --------------------
class _SearchResults extends StatelessWidget {
  final List<SearchContentItem> accounts;
  final List<String> searchHistory;
  final String query;
  final bool hasNetworkError;
  final VoidCallback onAnyTapDown;
  final Function(SearchContentItem) onTapAccount;
  final Function(String) onTapHistory;
  final Function(String) onRemoveHistory;
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
  Widget build(BuildContext context) {
    final List<Widget> children = [];
    if (query.isNotEmpty) {
      // 검색어 실행 타일 (항상 맨 위)
      children.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onAnyTapDown.call(),
          onTap: onTapSearch,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Row(
              children: [
                // 검색 아이콘을 CommonProfileAvatar에 넣기
                CommonProfileAvatar(
                  imageUrl: null,
                  username: 'search',
                  size: 70,
                  borderColor: Theme.of(context).colorScheme.background,

                  borderWidth: 2,
                  centerWidget: Icon(
                    Icons.search,
                    size: 30,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (accounts.isNotEmpty) {
      final seen = <String>{};
      for (final account in accounts) {
        final uname = account.username ?? '';
        if (uname.isNotEmpty) seen.add(uname);
        children.add(
          _AccountListItem(
            account: account,
            onTapDown: onAnyTapDown,
            onTap: () => onTapAccount(account),
            onRemove: () => onRemoveHistory(uname),
            showRemoveButton: query.isEmpty,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: children,
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
                size: 60.0,
              ),
              const SizedBox(width: 22),
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

  const _SearchTopBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onClear,
    required this.onBack,
    this.onClose,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchService = context.watch<SearchService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 12),
          // 닫기 버튼
          if (onClose != null)
            Container(
              width: 28,
              padding: const EdgeInsets.only(bottom: 1),
              child: GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 24,
                  color:
                      isDark
                          ? Colors.white.withOpacity(0.75)
                          : Colors.black.withOpacity(0.75),
                ),
              ),
            )
          else if (searchService.isFocused) ...[
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
              height: 44,
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
                      query.isNotEmpty
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
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
