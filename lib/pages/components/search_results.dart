import 'package:flutter/material.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import '../../../theme/app_text_styles.dart';

/// 검색 결과 리스트 (계정 + 검색 기록)
class SearchResults extends StatefulWidget {
  final List<SearchContentItem> accounts;
  final List<String> searchHistory;
  final String query;
  final bool hasNetworkError;
  final VoidCallback onAnyTapDown;
  final Function(SearchContentItem) onTapAccount;
  final Function(String) onTapHistory;
  final Function(SearchContentItem) onRemoveHistory;
  final bool enableHero;
  final VoidCallback onTapSearch;

  const SearchResults({
    super.key,
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
  State<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<SearchResults> {
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
        AccountListItem(
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
          AccountListItem(
            account: account,
            onTapDown: widget.onAnyTapDown,
            onTap: () => widget.onTapAccount(account),
            onRemove: () => widget.onRemoveHistory(account),
            showRemoveButton: widget.query.isEmpty,
          ),
        );
      }
    }

    return RawScrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(2),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children,
      ),
    );
  }
}

/// 계정/검색어 리스트 아이템
class AccountListItem extends StatelessWidget {
  final SearchContentItem account;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  const AccountListItem({
    super.key,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              CommonProfileAvatar(
                imageUrl: null,
                username: 'search',
                size: 50,
                borderColor: Theme.of(context).colorScheme.background,
                borderWidth: 0,
                backgroundColor:
                    Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[200]
                        : Colors.black,
                centerWidget: Icon(
                  Icons.search,
                  size: 20,
                  color:
                      Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  account.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onBackground,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CommonProfileAvatar(
                imageUrl: account.profileImageUrl,
                username: account.username ?? '',
                size: 50.0,
                backgroundColor: Colors.black,
                borderColor: Theme.of(context).colorScheme.surface,
                // 🎯 프로필 이미지가 있을 때는 보더 제거
                borderWidth: 0,
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
