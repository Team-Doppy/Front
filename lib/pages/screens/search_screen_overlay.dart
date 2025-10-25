import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:flutter/material.dart';
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
        }
        _searchFocusNode.requestFocus();
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
                  onSubmitted: () async {
                    print(
                      '[SearchOverlay] onSubmitted: ${searchService.query}',
                    );

                    try {
                      setState(() {
                        _hasNetworkError = false;
                      });

                      await searchService.searchBlogsByTitleOnce(
                        keyword: searchService.query,
                      );

                      // 검색 완료 후 결과를 PostData로 변환
                      final blogResults = searchService.blogResults;
                      final posts =
                          blogResults.map((item) {
                            return PostData(
                              id: item.id,
                              thumbnailImageUrl: item.imageUrl ?? '',
                              title: item.title ?? '',
                              summary: '',
                              author: item.author ?? item.username ?? '',
                              authorProfileImageUrl: item.profileImageUrl ?? '',
                              content: item.content ?? '',
                              accessLevel: AccessLevel.public,
                              viewCount: 0,
                              likeCount: item.likes ?? 0,
                              isLiked: false,
                              createdAt:
                                  item.createdAt ??
                                  DateTime.now().toIso8601String(),
                              updatedAt:
                                  item.createdAt ??
                                  DateTime.now().toIso8601String(),
                            );
                          }).toList();

                      // 콜백으로 검색 결과와 검색어 전달 (콜백에서 Navigator.pop 처리)
                      widget.onSearchComplete?.call(posts, searchService.query);
                    } catch (e) {
                      // 네트워크 에러 발생 시 처리
                      print('[SearchOverlay] 검색 실패: $e');
                      setState(() {
                        _hasNetworkError = true;
                      });
                      // 에러가 발생해도 빈 결과로 처리하여 "오프라인 상태입니다" 메시지 표시
                      widget.onSearchComplete?.call([], searchService.query);
                    }
                  },
                ),
                Expanded(
                  child: AnimatedBuilder(
                    animation: searchService,
                    builder: (_, __) {
                      final bool disableAnim =
                          _freezeDuringPush || searchService.query.isNotEmpty;
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
              searchService.onTapContentItem(
                item,
                onNavigateToProfile: (username) {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder:
                          (context, animation, secondaryAnimation) =>
                              UserProfileScreen(
                                otherUser: User(
                                  id: 0,
                                  username: username,
                                  alias: item.alias,
                                  profileImageUrl: item.profileImageUrl,
                                ),
                              ),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      transitionDuration: const Duration(milliseconds: 100),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 100,
                      ),
                    ),
                  ).whenComplete(() {
                    if (mounted) setState(() => _freezeDuringPush = false);
                  });
                },
              );
            },
            onTapHistory: (_) {},
            onRemoveHistory: (_) {},
            enableHero: true,
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
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder:
                      (context, animation, secondaryAnimation) =>
                          UserProfileScreen(
                            otherUser: User(
                              id: 0,
                              username: item.username ?? '',
                              alias: item.alias,
                              profileImageUrl: item.profileImageUrl,
                            ),
                          ),
                  transitionsBuilder: (
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 100),
                  reverseTransitionDuration: const Duration(milliseconds: 100),
                ),
              ).whenComplete(() {
                if (mounted) setState(() => _freezeDuringPush = false);
              });
            },
            onTapHistory: (_) {},
            onRemoveHistory: (username) {
              context.read<SearchService>().removeFromSearchHistory(username);
            },
            enableHero: false,
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
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];
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
    } else if (query.isNotEmpty) {
      // 네트워크 에러 상태에 따라 다른 메시지 표시
      final message = hasNetworkError ? '오프라인 상태입니다' : '검색 결과가 없습니다';

      children.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ),
      );
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
                size: 70.0,
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
                )
              else
                Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
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
          // 닫기 버튼
          if (onClose != null)
            SizedBox(
              width: 28,
              child: GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color:
                      isDark
                          ? Colors.white.withOpacity(0.9)
                          : Colors.black.withOpacity(0.9),
                  size: 20,
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
                      color:
                          isDark
                              ? Colors.white.withOpacity(0.9)
                              : Colors.black.withOpacity(0.9),
                      size: 20,
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
                  hintText: '무엇이든 검색해보세요',
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
                            tooltip: '검색',
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
