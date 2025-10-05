import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:provider/provider.dart';

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
  void showCategoryDropdown(BuildContext context, GlobalKey buttonKey) async {
    // 버튼 위치 계산
    final RenderBox? renderBox =
        buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonPosition = renderBox?.localToGlobal(Offset.zero);
    final buttonSize = renderBox?.size;

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
              top: (buttonPosition?.dy ?? 100),
              left: buttonPosition?.dx ?? 20,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _buildCategoryContent(context),
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
  Widget _buildCategoryContent(BuildContext context) {
    final feedProvider = context.read<ProfileFeedProvider>();
    final posts = feedProvider.posts;

    // 카테고리별 포스트 개수 계산
    final categoryCounts = <String, int>{};
    for (final rawPost in posts) {
      try {
        final post = PostData.fromServer(rawPost);
        String categoryName;
        switch (post.accessLevel) {
          case AccessLevel.private:
            categoryName = '나만 보기';
            break;
          case AccessLevel.groups:
            categoryName = '그룹';
            break;
          case AccessLevel.public:
            categoryName = '전체 공개';
            break;
        }
        categoryCounts[categoryName] = (categoryCounts[categoryName] ?? 0) + 1;
      } catch (_) {}
    }

    // 카테고리 목록 생성 (포스트가 있는 카테고리만)
    final categories =
        categoryCounts.entries
            .where((entry) => entry.value > 0)
            .map((entry) => MapEntry(entry.key, entry.value))
            .toList();

    // 포스트가 없는 경우
    if (categories.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 12),
                Text(
                  '카테고리가 없어요',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 전체 보기 옵션
        _buildCategoryItem(
          icon: Icon(Icons.grid_view, color: Colors.white.withOpacity(0.8)),
          title: '전체 보기',
          count: posts.length,
          isSelected: !CategoryFilterManager().isFiltered,
          context: context,
          onTap: () {
            CategoryFilterManager().clearFilter();
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),

        // 구분선
        Container(
          height: 1,
          margin: EdgeInsets.symmetric(horizontal: 16),
          color: Colors.white.withOpacity(0.1),
        ),

        // 카테고리별 옵션들
        ...categories.map(
          (entry) => _buildCategoryItem(
            icon: Icon(Icons.folder, color: Colors.white.withOpacity(0.8)),
            title: entry.key,
            count: entry.value,
            isSelected: CategoryFilterManager().value == entry.key,
            context: context,
            onTap: () {
              CategoryFilterManager().setCategory(entry.key);
              Navigator.of(context).pop();
              _onCategoryChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  /// 카테고리 아이템 빌드
  Widget _buildCategoryItem({
    required Widget icon,
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
              icon,
              const SizedBox(width: 12),
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
