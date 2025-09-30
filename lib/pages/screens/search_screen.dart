// lib/pages/post/search_screen.dart
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_text_styles.dart';
// import '../../../theme/app_colors.dart';
import '../../../data/services/search_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
                                ? CachedNetworkImage(
                                  imageUrl: account.profileImageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      (context, url) => const ShimmerBox(
                                        width: 60,
                                        height: 60,
                                      ),
                                  errorWidget:
                                      (context, url, error) => Icon(
                                        Icons.person,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                  // 프로필 이미지 캐시 설정
                                  memCacheWidth: 120,
                                  maxWidthDiskCache: 120,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  cacheKey:
                                      'search_profile_${account.profileImageUrl}',
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
                              ? CachedNetworkImage(
                                imageUrl: account.profileImageUrl!,
                                fit: BoxFit.cover,
                                placeholder:
                                    (context, url) =>
                                        const ShimmerBox(width: 60, height: 60),
                                errorWidget:
                                    (context, url, error) => Icon(
                                      Icons.person,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                // 프로필 이미지 캐시 설정
                                memCacheWidth: 120,

                                maxWidthDiskCache: 120,

                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                cacheKey:
                                    'search_profile_${account.profileImageUrl}',
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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

class _RecommendHome extends StatelessWidget {
  final List<SearchContentItem> items;
  const _RecommendHome({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = items.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(0),
      child:
          !hasData ? _StaggeredGrid(items: items) : _LoadingGrid(theme: theme),
    );
  }
}

class _StaggeredGrid extends StatelessWidget {
  final List<SearchContentItem> items;
  const _StaggeredGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 3열 고정
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 3 / 4, // 3:4 비율
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _GridCard(item: item);
      },
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  final ThemeData theme;
  const _LoadingGrid({required this.theme});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 3열 고정
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 3 / 4, // 3:4 비율
      ),
      itemCount: 50, // 로딩 시 6개 placeholder
      itemBuilder: (context, index) {
        return const ShimmerBox(
          width: double.infinity,
          height: double.infinity,
          borderRadius: BorderRadius.zero,
        );
      },
    );
  }
}

class _GridCard extends StatelessWidget {
  final SearchContentItem item;
  const _GridCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 이미지
          item.imageUrl != null && item.imageUrl!.startsWith('http')
              ? CachedNetworkImage(
                imageUrl: item.imageUrl!,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => const ShimmerBox(
                      width: double.infinity,
                      height: double.infinity,
                    ),
                errorWidget:
                    (context, url, error) => Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: const Icon(Icons.image, size: 50),
                    ),
                memCacheWidth: 300,
                maxWidthDiskCache: 300,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                cacheKey: 'grid_${item.imageUrl}',
              )
              : Image.asset(
                item.imageUrl ?? 'assets/images/feed1.jpg',
                fit: BoxFit.cover,
              ),

          // 그라데이션 오버레이
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.7),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // 제목
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              item.title ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
