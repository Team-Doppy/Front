import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/category_provider.dart';
import 'package:doppy/pages/components/comps_for_profile/category_create_dialog.dart';
import 'package:doppy/data/services/feed_service.dart';

// 카테고리 필터 관리
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

  /// 카테고리 변경 콜백 설정
  void setOnCategoryChanged(VoidCallback? callback) {
    _onCategoryChanged = callback;
  }

  /// 카테고리 드롭다운 표시
  void showCategoryDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    CategoryProvider? categoryProvider,
  ) async {
    // 버튼 위치 계산
    final RenderBox? renderBox =
        buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonPosition = renderBox?.localToGlobal(Offset.zero);
    // final buttonSize = renderBox?.size; // 현재는 사용하지 않음

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            // 배경 터치로 닫기
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // 드롭다운 컨텐츠 - 버튼 아래에 정확히 위치
            Positioned(
              top: (buttonPosition?.dy ?? 100) - 110,
              left: buttonPosition?.dx ?? 20 - 15,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 280,
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.6),
                          width: 0.5,
                        ),
                      ),
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thumbVisibility: WidgetStateProperty.all(true),
                          trackVisibility: WidgetStateProperty.all(false),
                          thumbColor: WidgetStateProperty.all(
                            Colors.white.withOpacity(0.4),
                          ),
                          trackColor: WidgetStateProperty.all(
                            Colors.white.withOpacity(0.1),
                          ),
                          thickness: WidgetStateProperty.all(3.0),
                          radius: const Radius.circular(1.5),
                          crossAxisMargin: 3,
                          mainAxisMargin: 20,
                        ),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: _buildCategoryContent(
                              context,
                              categoryProvider,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 카테고리 드롭다운 내용 빌드
  Widget _buildCategoryContent(
    BuildContext context,
    CategoryProvider? categoryProvider,
  ) {
    final feedProvider = context.read<ProfileFeedProvider>();
    final posts = feedProvider.posts;
    final cat = context.read<CategoryProvider>();

    print(
      '[CategoryDropDown] _buildCategoryContent - cat instance: ${cat.hashCode}, selectedBase: ${cat.selectedBase}',
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCreateCategoryButton(context, categoryProvider),

        // 기본 탭 4개
        _buildCategoryItem(
          title: '전체',
          count: posts.length,
          isSelected:
              cat.selectedCategoryId == null &&
              (cat.selectedBase == BaseFilter.all),
          context: context,
          onTap: () {
            cat.selectBase(BaseFilter.all);
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),
        _buildCategoryItem(
          title: '나만보기',
          count: posts.length, // 실제 카운트는 서버 필터링 후 반영 가능
          isSelected:
              cat.selectedCategoryId == null &&
              (cat.selectedBase == BaseFilter.private),
          context: context,
          onTap: () {
            print('[CategoryDropDown] 나만보기 탭 선택됨 (instance: ${cat.hashCode})');
            cat.selectBase(BaseFilter.private);
            print(
              '[CategoryDropDown] selectBase 호출 완료, 현재: ${cat.selectedBase}',
            );
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),
        _buildCategoryItem(
          title: '그룹공유',
          count: posts.length,
          isSelected:
              cat.selectedCategoryId == null &&
              (cat.selectedBase == BaseFilter.groups),
          context: context,
          onTap: () {
            print('[CategoryDropDown] 그룹공유 탭 선택됨');
            cat.selectBase(BaseFilter.groups);
            print(
              '[CategoryDropDown] selectBase 호출 완료, 현재: ${cat.selectedBase}',
            );
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),
        _buildCategoryItem(
          title: '전체공개',
          count: posts.length,
          isSelected:
              cat.selectedCategoryId == null &&
              (cat.selectedBase == BaseFilter.public),
          context: context,
          onTap: () {
            cat.selectBase(BaseFilter.public);
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),

        Container(
          height: 1,
          margin: EdgeInsets.symmetric(horizontal: 16),
          color: Colors.white.withOpacity(0.1),
        ),

        // 사용자가 만든 카테고리
        ...(cat.categories).map(
          (c) => Dismissible(
            key: ValueKey('cat-${c.id}'),
            direction:
                (cat.isReadOnly)
                    ? DismissDirection.none
                    : DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red.withOpacity(0.6),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async => !(cat.isReadOnly),
            onDismissed: (_) {
              cat.removeCategory(c.id);
              _onCategoryChanged?.call();
            },
            child: _buildCategoryItem(
              title: c.name,
              count: 0,
              isSelected: cat.selectedCategoryId == c.id,
              context: context,
              onTap: () {
                cat.selectCategory(c.id);
                Navigator.of(context).pop();
                _onCategoryChanged?.call();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateCategoryButton(
    BuildContext context,
    CategoryProvider? categoryProvider,
  ) {
    final cat = context.read<CategoryProvider>();
    final isReadOnly = cat.isReadOnly;
    final feedModeManager = FeedDisplayModeManager();
    final isImageOnlyMode = feedModeManager.isImageOnly;

    // 읽기 전용이거나 카드 모드면 숨김
    if (isReadOnly || !isImageOnlyMode) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
          final name = await showDialog<String?>(
            context: context,
            builder: (_) => const CategoryCreateDialog(),
          );
          print('[CategoryDropDown] 다이얼로그 결과: $name');
          if (name != null && name.trim().isNotEmpty) {
            print(
              '[CategoryDropDown] Provider 찾음: ${cat.categories.length}개 카테고리 (instance: ${cat.hashCode})',
            );
            cat.createCategory(name.trim());
            print('[CategoryDropDown] 카테고리 생성 완료: ${cat.categories.length}개');
            _onCategoryChanged?.call();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '새 카테고리 만들기',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add,
                  color: Colors.white.withOpacity(0.9),
                  size: 20,
                ),
              ),
              SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// 카테고리 아이템 빌드
  Widget _buildCategoryItem({
    required String title,
    required int count,
    required bool isSelected,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
