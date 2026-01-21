import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

// 공개범위 필터 관리
class CategoryFilterManager extends ValueNotifier<String?> {
  static final CategoryFilterManager _instance =
      CategoryFilterManager._internal();
  factory CategoryFilterManager() => _instance;
  CategoryFilterManager._internal() : super(null);

  void setCategory(String? category) {
    value = category;
  }

  void clearFilter() {
    value = null;
  }

  bool get isFiltered => value != null;
}

class CategoryDropDown {
  VoidCallback? _onCategoryChanged;

  /// 공개범위 변경 콜백 설정
  void setOnCategoryChanged(VoidCallback? callback) {
    _onCategoryChanged = callback;
  }

  /// 리소스 정리
  void dispose() {
    // 리소스 정리 (현재 사용하지 않음)
  }

  /// 공개범위 필터 드롭다운 표시 (BottomSheet)
  void showCategoryDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    BaseFeedProvider feedProvider,
  ) async {
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      builder: (BuildContext context) {
        return Material(
          borderRadius: BorderRadius.circular(30),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 핸들 바
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                // 공개범위 필터 리스트
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      _buildFilterItem(
                        context: context,
                        title: context.tr('all'),
                        filter: BaseFilter.all,
                        feedProvider: feedProvider,
                        onTap: () {
                          feedProvider.selectBase(BaseFilter.all);
                          Navigator.of(context).pop();
                          _onCategoryChanged?.call();
                        },
                      ),
                      _buildFilterItem(
                        context: context,
                        title: context.tr('private'),
                        filter: BaseFilter.private,
                        feedProvider: feedProvider,
                        onTap: () {
                          feedProvider.selectBase(BaseFilter.private);
                          Navigator.of(context).pop();
                          _onCategoryChanged?.call();
                        },
                      ),
                      _buildFilterItem(
                        context: context,
                        title: context.tr('friends'),
                        filter: BaseFilter.friends,
                        feedProvider: feedProvider,
                        onTap: () {
                          feedProvider.selectBase(BaseFilter.friends);
                          Navigator.of(context).pop();
                          _onCategoryChanged?.call();
                        },
                      ),
                      _buildFilterItem(
                        context: context,
                        title: context.tr('public'),
                        filter: BaseFilter.public,
                        feedProvider: feedProvider,
                        onTap: () {
                          feedProvider.selectBase(BaseFilter.public);
                          Navigator.of(context).pop();
                          _onCategoryChanged?.call();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 공개범위 필터 아이템 빌드
  Widget _buildFilterItem({
    required BuildContext context,
    required String title,
    required BaseFilter filter,
    required BaseFeedProvider feedProvider,
    required VoidCallback onTap,
  }) {
    final isSelected = feedProvider.selectedBase == filter;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color:
            isSelected
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.9)
                : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 16,
                      color:
                          isSelected && isDarkMode
                              ? AppColors.darkSurface
                              : isSelected && !isDarkMode
                              ? Colors.white
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
