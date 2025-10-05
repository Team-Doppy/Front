import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/past_card2.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_text_styles.dart';
// import '../../../theme/app_colors.dart';
import '../../../data/services/search_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// -------------------- 메인 화면 --------------------
class _SearchScreenState extends State<SearchScreen> {
  // 하단 네비
  // RootShell에서 하단 네비를 고정 제공하므로 로컬 인덱스 불필요

  // 검색 컨트롤러
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _freezeDuringPush = false; // 네비게이션 중 화면 전환 방지
  List<SearchContentItem> _frozenAccounts = const [];
  String _freezeKind = ''; // 'live' | 'history'

  @override
  void initState() {
    super.initState();
    // SearchService 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SearchService>().initialize();
    });

    // 텍스트 변경 리스너에서만 검색 트리거
    _searchController.addListener(() {
      context.read<SearchService>().onSearchChanged(_searchController.text);
    });

    // 포커스 변경: 한 번만 등록해 상태 반영 (잠금 중엔 무시)
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

  // -------------------- UI 이벤트 핸들러 --------------------
  void _clearSearch() {
    _searchController.clear();
    context.read<SearchService>().clearSearch();
  }

  void _resetToInitial() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    context.read<SearchService>().resetToInitial();
  }

  // -------------------- UI 이벤트 핸들러 --------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchService>(
      builder: (context, searchService, child) {
        return Scaffold(
          body: Stack(
            children: [
              /*
              // 배경 이미지 (블러 처리)
              Positioned.fill(
                child: Image.asset(
                  'assets/images/feed3.png', // 배경용 asset 이미지
                  fit: BoxFit.cover,
                ),
              ),

              // 블러 오버레이
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.background.withOpacity(0.8),
                  ),
                ),
              ),
              */

              // 메인 콘텐츠
              SafeArea(
                child: Column(
                  children: [
                    SizedBox(height: 5),
                    _SearchTopBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      query: searchService.query,
                      onClear: _clearSearch,
                      onBack: _resetToInitial,
                      onSubmitted: () {
                        print('onSubmitted: ${searchService.query}');
                        searchService.searchBlogsByTitleOnce(
                          keyword: searchService.query,
                        );
                      },
                    ),
                    // 검색 입력 종료 후 작은 탭 (계정/블로그)
                    if (!searchService.isFocused &&
                        searchService.query.isNotEmpty)
                      const _ResultTabs(),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: searchService,
                        builder: (_, __) {
                          final bool disableAnim =
                              _freezeDuringPush ||
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
            ],
          ),
          // 하단 네비게이션은 RootShell에서 고정 제공
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
        // 1.5) 입력 종료 후: 탭 기반 결과 (블로그/계정)
        if (searchService.query.isNotEmpty && !searchService.isFocused) {
          if (searchService.selectedCategory == '추천') {
            // 블로그 그리드
            final posts = context.watch<SearchService>().blogResults;
            return _StaggeredGrid(items: posts, controller: ScrollController());
          } else {
            // 계정 리스트
            return _SearchResults(
              accounts: searchService.searchingAccounts,
              searchHistory: const [],
              query: searchService.query,
              onAnyTapDown: () {},
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
                    reverseTransitionDuration: const Duration(
                      milliseconds: 100,
                    ),
                  ),
                );
              },
              onTapHistory: (_) {},
              onRemoveHistory: (_) {},
              enableHero: false,
            );
          }
        }
        // 2) 포커스 O & 쿼리 없음: 검색 기록 펼침
        if (searchService.isFocused) {
          return _SearchResults(
            accounts: searchService.searchHistory,
            searchHistory: const [],
            query: '',
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
              // SearchService를 통해 검색 기록에서 제거
              context.read<SearchService>().removeFromSearchHistory(username);
            },
            enableHero: false,
          );
        }
        // 3) 기본: 추천 컨텐츠(OTT 느낌)
        final items = searchService.contentItems;
        return _RecommendHome(items: items);
      },
    );
  }
}

/// -------------------- 검색 결과 (계정 + 검색 기록) --------------------
class _SearchResults extends StatelessWidget {
  final List<SearchContentItem> accounts;
  final List<String> searchHistory;
  final String query;
  final VoidCallback onAnyTapDown;
  final Function(SearchContentItem) onTapAccount;
  final Function(String) onTapHistory;
  final Function(String) onRemoveHistory;
  final bool enableHero;

  const _SearchResults({
    required this.accounts,
    required this.searchHistory,
    required this.query,
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
      children.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              '검색 결과가 없습니다',
              style: TextStyle(color: Colors.grey, fontSize: 16),
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
              // 프로필 이미지 (70x70)
              CommonProfileAvatar(
                imageUrl: account.profileImageUrl,
                username: account.username ?? '',
                size: 70.0,
              ),
              const SizedBox(width: 22),

              // 계정 정보 (alias + @username)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이름 텍스트
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

              // 버튼 (삭제 또는 더보기)
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

/// -------------------- 컨텐츠 그리드 --------------------
// (그리드 UI 및 게시글 카드 UI는 제거되어, 현재는 유저 검색만 지원합니다.)

/// -------------------- 상단 바(로고+검색창) --------------------
class _SearchTopBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback onSubmitted;

  const _SearchTopBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onClear,
    required this.onBack,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final searchService = context.watch<SearchService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              height: 40,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  FocusScope.of(context).unfocus();
                  context.read<SearchService>().searchBlogsByTitleOnce(
                    keyword: v,
                  );
                },
                onTap: () => context.read<SearchService>().setFocused(true),
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                cursorColor: Theme.of(context).colorScheme.onSurface,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  hintText: '무엇이든 검색해보세요',
                  hintStyle: AppTextStyles.withWeight(
                    AppTextStyles.bodyLarge,
                    FontWeight.w500,
                  ).copyWith(color: const Color(0xFF989898)),

                  suffixIcon:
                      query.isNotEmpty
                          ? IconButton(
                            tooltip: '검색',
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              onSubmitted();
                            },
                            icon: const Icon(
                              Icons.search,
                              color: Color(0xFF989898),
                              size: 22,
                            ),
                          )
                          : Icon(
                            Icons.search,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                            size: 22,
                          ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),

                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
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

class _ResultTabs extends StatelessWidget {
  const _ResultTabs();

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SearchService>();
    final theme = Theme.of(context);

    return Container(
      height: 40,
      margin: const EdgeInsets.only(top: 0, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: svc.selectedCategory,
                isDense: true,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '추천',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '블로그',
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownMenuItem<String>(
                    value: '계정',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '계정',
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    svc.changeCategory(newValue);
                  }
                },
                icon: Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendHome extends StatefulWidget {
  final List<SearchContentItem> items;
  const _RecommendHome({required this.items});

  @override
  State<_RecommendHome> createState() => _RecommendHomeState();
}

class _RecommendHomeState extends State<_RecommendHome> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      final searchService = context.read<SearchService>();
      searchService.loadRecommendations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = widget.items.isNotEmpty;

    return Consumer<SearchService>(
      builder: (context, searchService, _) {
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(0),
              child:
                  hasData
                      ? _StaggeredGrid(
                        items: widget.items,
                        controller: _scrollController,
                      )
                      : _LoadingGrid(theme: theme),
            ),
            if (searchService.isLoadingMore)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '추천 컨텐츠 불러오는 중...',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 14,
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
    );
  }
}

class _StaggeredGrid extends StatelessWidget {
  final List<SearchContentItem> items;
  final ScrollController controller;
  const _StaggeredGrid({required this.items, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchService>(
      builder: (context, searchService, _) {
        return RefreshIndicator(
          onRefresh: () => searchService.refreshRecommendations(),
          displacement: 50, // 새로고침 인디케이터 위치를 더 아래로
          edgeOffset: 10, // 가장자리에서의 오프셋 증가
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.9), // 새로고침 아이콘 색상
          child: ListView.builder(
            controller: controller,
            itemCount: items.length,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemBuilder: (context, index) {
              return BlogCard(item: items[index], index: index);
            },
          ),
        );
      },
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  final ThemeData theme;
  const _LoadingGrid({required this.theme});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6, // 초기 로딩 시 6개 placeholder
      itemBuilder: (context, index) {
        return const _GridCardPlaceholder();
      },
    );
  }
}

class _GridCardPlaceholder extends StatelessWidget {
  const _GridCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: SizedBox(
        height: 200, // 고정 높이 설정
        child: Stack(
          children: [
            // 배경 shimmer
            Positioned.fill(
              child: ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
            ),
            // 텍스트 shimmer들
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerBox(
                    width: 120,
                    height: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  ShimmerBox(
                    width: 80,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
