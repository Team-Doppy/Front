// lib/pages/post/search_screen.dart
import 'package:doppy/data/models/user_model.dart';
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
          backgroundColor: Theme.of(context).colorScheme.surface,
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
                  child: _SearchResults(
                    accounts:
                        searchService.query.isNotEmpty
                            ? searchService.searchingAccounts
                            : [],
                    searchHistory: searchService.searchHistory,
                    query: searchService.query,
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
                          );
                        },
                      );
                    },
                    onTapHistory: (query) {
                      _searchController.text = query;
                      // 검색 기록에서 클릭한 경우에도 기록에 추가
                      searchService.addToSearchHistory(query);
                    },
                    onRemoveHistory: (query) {
                      searchService.removeFromSearchHistory(query);
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
}

/// -------------------- 검색 결과 (계정 + 검색 기록) --------------------
class _SearchResults extends StatelessWidget {
  final List<SearchContentItem> accounts;
  final List<String> searchHistory;
  final String query;
  final Function(SearchContentItem) onTapAccount;
  final Function(String) onTapHistory;
  final Function(String) onRemoveHistory;

  const _SearchResults({
    required this.accounts,
    required this.searchHistory,
    required this.query,
    required this.onTapAccount,
    required this.onTapHistory,
    required this.onRemoveHistory,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 검색 기록 또는 검색된 계정들
        if (query.isEmpty && searchHistory.isNotEmpty) ...[
          // 검색 기록을 계정 형태로 표시
          ...searchHistory.map(
            (query) => _AccountListItem(
              account: SearchContentItem.account(
                id: 'history_$query',
                username: query,
                alias: query,
                profileImageUrl: '',
                followers: 0,
              ),
              onTap: () => onTapHistory(query),
              onRemove: () => onRemoveHistory(query),
              showRemoveButton: true,
            ),
          ),
        ] else if (accounts.isNotEmpty) ...[
          // 검색된 계정들
          ...accounts.map(
            (account) => _AccountListItem(
              account: account,
              onTap: () => onTapAccount(account),
            ),
          ),
        ] else if (query.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                '검색 결과가 없습니다',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AccountListItem extends StatelessWidget {
  final SearchContentItem account;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  const _AccountListItem({
    required this.account,
    required this.onTap,
    this.onRemove,
    this.showRemoveButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 프로필 이미지 (네트워크+쉬머)
            _ProfileAvatar(url: account.profileImageUrl),
            const SizedBox(width: 12),

            // 계정 정보 (alias + @username)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AliasAndUsername(
                    alias: account.alias,
                    username: account.username,
                  ),
                  if (account.followers != null && account.followers! > 0) ...[
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
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? url;
  const _ProfileAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final shimmerBase = Theme.of(context).colorScheme.surfaceVariant;
    final shimmerHighlight = Theme.of(context).colorScheme.surface;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ClipOval(
        child:
            (url != null && url!.isNotEmpty)
                ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _ShimmerCircle(
                      base: shimmerBase,
                      highlight: shimmerHighlight,
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: shimmerBase,
                      child: Icon(
                        Icons.person,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                    );
                  },
                )
                : Container(
                  color: shimmerBase,
                  child: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
      ),
    );
  }
}

class _ShimmerCircle extends StatefulWidget {
  final Color base;
  final Color highlight;
  const _ShimmerCircle({required this.base, required this.highlight});

  @override
  State<_ShimmerCircle> createState() => _ShimmerCircleState();
}

class _ShimmerCircleState extends State<_ShimmerCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final dx = -1.0 + 2.0 * _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment(dx, 0),
              end: Alignment(dx + 1.2, 0),
              colors: [widget.base, widget.highlight, widget.base],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

class _AliasAndUsername extends StatelessWidget {
  final String? alias;
  final String? username;
  const _AliasAndUsername({this.alias, this.username});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (alias?.isNotEmpty == true ? alias! : (username ?? '')),
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '@${username ?? ''}',
          style: AppTextStyles.bodyMedium.copyWith(color: secondary),
        ),
      ],
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
          searchService.hasSearched || searchService.isFocused
              ? GestureDetector(
                onTap: onBack,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              )
              : const SizedBox.shrink(),

          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                cursorColor: Theme.of(context).colorScheme.onSurface,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  hintText: '사용자 검색',
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
