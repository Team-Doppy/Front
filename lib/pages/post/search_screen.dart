// lib/pages/post/search_screen.dart
import 'package:doppy/pages/post/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_text_styles.dart';
import '../../../theme/app_colors.dart';
import '../../../pages/components/custom_bottom_navigation_bar.dart';
import '../../../data/services/search_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// -------------------- 메인 화면 --------------------
class _SearchScreenState extends State<SearchScreen> {
  // 하단 네비
  int _bottomIndex = 1;

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

    // 포커스 리스너 추가
    _searchFocusNode.addListener(() {
      context.read<SearchService>().onFocusChanged(_searchFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // -------------------- UI 이벤트 핸들러 --------------------
  void _onSearchChanged(String q) {
    _searchController.text = q;
    context.read<SearchService>().onSearchChanged(q);
  }

  void _onSearchSubmitted(String q) {
    _searchController.text = q;
    context.read<SearchService>().onSearchSubmitted(q);
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

  // -------------------- UI 이벤트 핸들러 --------------------

  void _onTapContentItem(SearchContentItem item) {
    if (item.isAccount) {
      _showSnack('계정 선택: ${item.displayName} (@${item.username})');
    } else {
      _showSnack('게시글 선택: "${item.title}" - ${item.author} (♥${item.likes})');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchService>(
      builder: (context, searchService, child) {
        return Scaffold(
          backgroundColor: AppColors.darkSurface,
          body: SafeArea(
            child: Column(
              children: [
                _SearchTopBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  query: searchService.query,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchSubmitted,
                  onClear: _clearSearch,
                  onBack: _resetToInitial,
                ),
                // 검색 완료 후에만 카테고리바 표시
                if (searchService.hasSearched)
                  _CategoryBar(
                    selectedCategory: searchService.selectedCategory,
                    onCategoryChanged: searchService.changeCategory,
                  ),
                Expanded(
                  child:
                      searchService.isFocused
                          ? _SearchResults(
                            accounts:
                                searchService.isSearching
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
                                            username: username,
                                          ),
                                    ),
                                  );
                                },
                              );
                              _onTapContentItem(item);
                            },
                            onTapHistory: (query) {
                              _searchController.text = query;
                              searchService.onSearchChanged(query);
                              // 검색 기록에서 클릭한 경우에도 기록에 추가
                              searchService.addToSearchHistory(query);
                            },
                            onRemoveHistory: (query) {
                              searchService.removeFromSearchHistory(query);
                            },
                          )
                          : _ContentGrid(
                            items: searchService.contentItems,
                            isLoading: searchService.isLoading,
                            error: searchService.error,
                            onTapItem: (item) {
                              searchService.onTapContentItem(
                                item,
                                onNavigateToProfile: (username) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => UserProfileScreen(
                                            username: username,
                                          ),
                                    ),
                                  );
                                },
                              );
                              _onTapContentItem(item);
                            },
                          ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: CustomBottomNavigationBar(
            currentIndex: _bottomIndex,
            onTap: (i) {
              setState(() => _bottomIndex = i);
              debugPrint('BottomNav 탭 변경: index=$i');
            },
          ),
        );
      },
    );
  }
}

/// -------------------- 카테고리바 --------------------
class _CategoryBar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;

  const _CategoryBar({
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0),
      child: Container(
        height: 50,
        decoration: BoxDecoration(color: AppColors.darkSurface),
        child: Row(
          children: [
            Expanded(
              child: _CategoryButton(
                title: '계정',
                isSelected: selectedCategory == '계정',
                onTap: () => onCategoryChanged('계정'),
              ),
            ),
            Expanded(
              child: _CategoryButton(
                title: '추천',
                isSelected: selectedCategory == '추천',
                onTap: () => onCategoryChanged('추천'),
              ),
            ),
            Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  isSelected ? AppColors.darkTextPrimary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: AppTextStyles.bodyLarge.copyWith(
              color:
                  isSelected
                      ? AppColors.darkTextPrimary
                      : AppColors.darkTextSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
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
        // 검색 기록 (검색어가 비어있을 때만 표시)
        if (query.isEmpty && searchHistory.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '최근 검색',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkTextPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    context.read<SearchService>().clearSearchHistory();
                  },
                  child: Text(
                    '전체 삭제',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],

        // 검색 기록 또는 검색된 계정들
        if (query.isEmpty && searchHistory.isNotEmpty) ...[
          // 검색 기록을 계정 형태로 표시
          ...searchHistory.map(
            (query) => _AccountListItem(
              account: SearchContentItem.account(
                id: 'history_$query',
                username: query,
                displayName: query,
                profileImageUrl:
                    'https://picsum.photos/200/200?random=${query.hashCode}',
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
            // 프로필 이미지
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: ClipOval(
                child: Image.network(
                  account.profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.person,
                        color: Colors.grey,
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 계정 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName!,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${account.username}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                  if (account.followers != null && account.followers! > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${account.followers}명',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.darkTextSecondary,
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
                icon: const Icon(
                  Icons.close,
                  color: AppColors.darkTextSecondary,
                  size: 18,
                ),
              )
            else
              Icon(
                Icons.more_vert,
                color: AppColors.darkTextSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

/// -------------------- 컨텐츠 그리드 --------------------
class _ContentGrid extends StatelessWidget {
  final List<SearchContentItem> items;
  final bool isLoading;
  final String? error;
  final Function(SearchContentItem) onTapItem;

  const _ContentGrid({
    required this.items,
    required this.isLoading,
    required this.error,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[ContentGrid] items count: ${items.length}');
    debugPrint(
      '[ContentGrid] items: ${items.map((e) => e.isAccount ? 'Account: ${e.username}' : 'Post: ${e.title}').toList()}',
    );

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              error!,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
        childAspectRatio: 0.8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ContentGridItem(item: item, onTap: () => onTapItem(item));
      },
    );
  }
}

/// -------------------- 그리드 아이템 --------------------
class _ContentGridItem extends StatelessWidget {
  final SearchContentItem item;
  final VoidCallback onTap;

  const _ContentGridItem({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[200]),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 이미지
            Image.network(
              item.isAccount ? item.profileImageUrl! : item.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[300],
                  child: Icon(
                    item.isAccount ? Icons.person : Icons.image,
                    color: Colors.grey[600],
                    size: 32,
                  ),
                );
              },
            ),

            // 오버레이 (계정인 경우)
            if (item.isAccount)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.displayName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${item.followers}명',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 게시글인 경우 하트 아이콘
            if (!item.isAccount)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite, color: Colors.white, size: 12),
                      const SizedBox(width: 2),
                      Text(
                        '${item.likes}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
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

/// -------------------- 상단 바(로고+검색창) --------------------
class _SearchTopBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onBack;

  const _SearchTopBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onSubmitted,
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
                  color: AppColors.darkTextSecondary,
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
                  color: AppColors.darkTextPrimary,
                ),
                cursorColor: AppColors.darkTextSecondary,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color.fromARGB(255, 51, 51, 51),
                  hintText: '검색',
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
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  disabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                ),
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
