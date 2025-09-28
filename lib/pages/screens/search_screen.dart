// lib/pages/post/search_screen.dart
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
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
          backgroundColor: Theme.of(context).colorScheme.background,
          body: SafeArea(
            child: Column(
              children: [
                _SearchTopBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  query: searchService.query,
                  onClear: _clearSearch,
                  onBack: _resetToInitial,
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
        if (searchService.query.isNotEmpty) {
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
                    MaterialPageRoute(
                      builder:
                          (context) => UserProfileScreen(
                            otherUser: User(
                              id: 0,
                              username: username,
                              alias: item.alias,
                              profileImageUrl: item.profileImageUrl,
                            ),
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
            onAnyTapDown:
                () => setState(() {
                  _freezeDuringPush = true;
                  _freezeKind = 'history';
                  _frozenAccounts = List.of(searchService.searchHistory);
                }),
            onTapAccount: (item) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => UserProfileScreen(
                        otherUser: User(
                          id: 0,
                          username: item.username ?? '',
                          alias: item.alias,
                          profileImageUrl: item.profileImageUrl,
                        ),
                      ),
                ),
              ).whenComplete(() {
                if (mounted) setState(() => _freezeDuringPush = false);
              });
            },
            onTapHistory: (_) {},
            onRemoveHistory: (_) {},
            enableHero: false, // 기록 화면에서는 Hero 비활성화로 깜빡임/중복 회피
          );
        }
        // 3) 기본: 추천 컨텐츠(OTT 느낌)
        final items = searchService.contentItems;
        return _OttHome(items: items);
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
        final allowHero = uname.isNotEmpty && !seen.contains(uname);
        if (uname.isNotEmpty) seen.add(uname);
        children.add(
          _AccountListItem(
            account: account,
            onTapDown: onAnyTapDown,
            onTap: () => onTapAccount(account),
            onRemove: () => onRemoveHistory(uname),
            showRemoveButton: query.isEmpty,
            useHero: enableHero && allowHero,
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
  final bool useHero;

  const _AccountListItem({
    required this.account,
    required this.onTap,
    this.onTapDown,
    this.onRemove,
    this.showRemoveButton = false,
    this.useHero = true,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 프로필 이미지 (60x60) + 원형 Hero (user-<username>)
              (useHero && (account.username ?? '').isNotEmpty)
                  ? Hero(
                    tag: 'user-${account.username}',
                    child: ClipOval(
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child:
                            (account.profileImageUrl != null &&
                                    account.profileImageUrl!.isNotEmpty)
                                ? Image.network(
                                  account.profileImageUrl!,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.low,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const ShimmerBox(
                                      width: 60,
                                      height: 60,
                                    );
                                  },
                                  errorBuilder:
                                      (context, error, stackTrace) => Icon(
                                        Icons.person,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                )
                                : Icon(
                                  Icons.person,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                      ),
                    ),
                  )
                  : ClipOval(
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child:
                          (account.profileImageUrl != null &&
                                  account.profileImageUrl!.isNotEmpty)
                              ? Image.network(
                                account.profileImageUrl!,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const ShimmerBox(
                                    width: 60,
                                    height: 60,
                                  );
                                },
                              )
                              : Icon(
                                Icons.person,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                    ),
                  ),
              const SizedBox(width: 12),

              // 계정 정보 (alias + @username)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이름 텍스트 Hero (user-name-<username>)
                    (useHero && (account.username ?? '').isNotEmpty)
                        ? Hero(
                          tag: 'user-name-${account.username}',
                          transitionOnUserGestures: true,
                          child: Material(
                            type: MaterialType.transparency,
                            child: Text(
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
                          ),
                        )
                        : Text(
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

  const _SearchTopBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onClear,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final searchService = context.watch<SearchService>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
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
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 22,
                    color: Color(0xFF989898),
                  ),
                  suffixIcon:
                      query.isNotEmpty
                          ? IconButton(
                            tooltip: '지우기',
                            onPressed: onClear,
                            icon: const Icon(
                              Icons.clear,
                              color: Color(0xFF989898),
                            ),
                          )
                          : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),

                  isDense: true,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
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

class _OttHome extends StatelessWidget {
  final List<SearchContentItem> items;
  const _OttHome({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = items.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Hero Banner
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: AspectRatio(
            aspectRatio: 9 / 12,
            child:
                hasData
                    ? _HeroCarousel(items: items)
                    : _BannerPlaceholder(theme: theme),
          ),
        ),

        // 섹션 1: 지금 뜨는 컨텐츠
        _SectionRow(title: '지금 뜨는 컨텐츠', items: hasData ? items : const []),

        // 섹션 2: 에디터의 추천
        _SectionRow(
          title: '에디터의 추천',
          items: hasData ? items.reversed.toList() : const [],
        ),

        // 섹션 3: 최신 업로드
        _SectionRow(
          title: '최신 업로드',
          items:
              hasData ? List<SearchContentItem>.from(items.reversed) : const [],
        ),
      ],
    );
  }
}

class _BannerPlaceholder extends StatelessWidget {
  final ThemeData theme;
  const _BannerPlaceholder({required this.theme});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(color: theme.colorScheme.surfaceVariant),
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  final List<SearchContentItem> items;
  const _HeroCarousel({required this.items});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _pageCtrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) {
              return _HeroBanner(item: items[index]);
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(items.length, (i) {
                final bool active = i == _current;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 8 : 6,
                  height: active ? 8 : 6,
                  decoration: BoxDecoration(
                    color:
                        active ? Colors.white : Colors.white.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final SearchContentItem item;
  const _HeroBanner({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            item.imageUrl != null && item.imageUrl!.startsWith('http')
                ? Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  cacheHeight: 300,
                  filterQuality: FilterQuality.medium,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const ShimmerBox(width: 300, height: 300);
                  },
                )
                : Image.asset(
                  item.imageUrl ?? 'assets/images/feed1.jpg',
                  fit: BoxFit.cover,
                ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '추천',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
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
}

class _SectionRow extends StatelessWidget {
  final String title;
  final List<SearchContentItem> items;
  const _SectionRow({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = items.isNotEmpty;
    const double cardHeight = 260; // 크기 확대
    final double cardWidth = cardHeight * 3 / 4; // 3:4 비율
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: hasData ? items.length : 8,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (!hasData) {
                  return SizedBox(
                    width: cardWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(color: theme.colorScheme.surfaceVariant),
                    ),
                  );
                }
                final it = items[index];
                return SizedBox(
                  width: cardWidth,
                  child: _PosterTileSmall(item: it),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterTileSmall extends StatelessWidget {
  final SearchContentItem item;
  const _PosterTileSmall({required this.item});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            item.imageUrl != null && item.imageUrl!.startsWith('http')
                ? Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  cacheHeight: 300,
                  filterQuality: FilterQuality.medium,
                )
                : Image.asset(
                  item.imageUrl ?? 'assets/images/feed1.jpg',
                  fit: BoxFit.cover,
                ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.all(8),

                child: Text(
                  item.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
