import 'package:doppy/data/models/post_data.dart';

import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/horizontal_category_section.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/category_model.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Feed {
  // 카테고리 드래그 상태 관리
  final ValueNotifier<bool> _isDraggingCategory = ValueNotifier(false);
  final ValueNotifier<int?> _categoryDropTargetIndex = ValueNotifier(null);
  final ValueNotifier<int?> _draggingSectionIndex = ValueNotifier(null);
  ScrollController? _mainScrollController;

  // 외부에서 드래그 상태 접근 가능하도록 getter 추가
  ValueNotifier<bool> get isDraggingCategory => _isDraggingCategory;

  // 드래그 상태 변경 콜백
  VoidCallback? onDragStateChanged;

  // ========= Helper functions (visibility & filtering rules) =========

  /// Raw 데이터를 PostData 리스트로 변환
  List<PostData> _mapRawToPosts(List<dynamic> rawList) {
    return rawList
        .map((raw) {
          try {
            return PostData.fromServer(raw);
          } catch (_) {
            return null;
          }
        })
        .whereType<PostData>()
        .toList();
  }

  /// BaseFilter에 따라 포스트 필터링
  List<PostData> _applyBaseFilter(List<PostData> posts, BaseFilter base) {
    if (base == BaseFilter.all) return posts;
    return posts.where((post) {
      switch (base) {
        case BaseFilter.private:
          return post.accessLevel == AccessLevel.private;
        case BaseFilter.groups:
          return post.accessLevel == AccessLevel.groups;
        case BaseFilter.public:
          return post.accessLevel == AccessLevel.public;
        case BaseFilter.all:
          return true;
      }
    }).toList();
  }

  /// 시스템 카테고리 여부 판단
  bool _isSystemCategory(Map<String, dynamic> cat) {
    return (cat['isSystem'] == true);
  }

  /// 미분류 카테고리 여부 판단 (system_doppy_uncategorized 또는 id=0)
  bool _isUncategorized(Map<String, dynamic> cat) {
    final name = (cat['name']?.toString() ?? '');
    final idVal = (cat['id'] as int?) ?? -1;
    return name == 'system_doppy_uncategorized' || idVal == 0;
  }

  /// 전체 탭에서 카테고리 포함 여부 판단
  /// - 시스템 카테고리는 숨김 (단, 미분류는 예외)
  /// - 미분류도 포스트가 없으면 숨김
  bool _includeCategoryInAll(Map<String, dynamic> cat, List<PostData> posts) {
    final isSystem = _isSystemCategory(cat);
    final isUncategorized = _isUncategorized(cat);

    // 시스템 카테고리는 숨기되, 미분류는 예외
    if (isSystem && !isUncategorized) return false;

    // 미분류도 포스트가 없으면 숨김
    if (isUncategorized && posts.isEmpty) return false;

    return true;
  }

  /// 메인 빌드: 카테고리별 수평 섹션 렌더링 (전체 탭 기준)
  Widget buildFeedContent({ScrollController? scrollController}) {
    _mainScrollController = scrollController;

    return Consumer<BaseFeedProvider>(
      builder: (context, feedProvider, _) {
        // 필터링 조건 가져오기
        final filteredBase = feedProvider.selectedBase;
        final filteredCategoryId = feedProvider.selectedCategoryId;

        // 로딩 중이면 이전 컨텐츠 유지 (깜빡임 방지)
        // 단, 초기 로딩이고 데이터가 없을 때만 비워두기
        if (feedProvider.isLoading && feedProvider.categories.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // 카테고리 → 섹션 메타 구성 (시스템 카테고리 포함)
        final List<CategoryMetaData> categoryMetaDataList = [];

        // 사용자 정의 카테고리만 표시 (시스템 카테고리는 숨김)
        for (final cat in feedProvider.categories) {
          final idStr = (cat['id'] ?? '').toString();
          final title = (cat['name'] ?? '').toString();

          print('[Feed] 카테고리 체크 - idStr: $idStr, title: $title');

          // 특정 카테고리가 선택되었으면 해당 카테고리만 표시
          if (filteredCategoryId != null && idStr != filteredCategoryId) {
            continue;
          }

          print('[Feed] 선택됨 - $title (id: $idStr)');

          // 원본 포스트 목록을 PostData로 변환 후 필터링
          final rawPosts = feedProvider.postsByCategory[idStr] ?? const [];
          List<PostData> posts = _applyBaseFilter(
            _mapRawToPosts(rawPosts),
            filteredBase,
          );

          // 타인 프로필이면 빈 카테고리 숨김
          if (posts.isEmpty && feedProvider.isReadOnly) continue;

          // 전체 탭에서 시스템 카테고리 필터링 (미분류는 예외)
          if (filteredBase == BaseFilter.all) {
            if (!_includeCategoryInAll(cat, posts)) continue;
          }

          categoryMetaDataList.add(
            CategoryMetaData(title: title, posts: posts, categoryId: idStr),
          );
        }
        // 아무런 글도 없을 때,
        if (feedProvider.posts.isEmpty ||
            categoryMetaDataList.length == 1 &&
                categoryMetaDataList[0].title == 'system_doppy_uncategorized' &&
                categoryMetaDataList[0].posts.isEmpty) {
          return SliverToBoxAdapter(
            child: Column(
              children: [
                SizedBox(height: 100),
                Text('아직은 포스트가 없어요!'),
                SizedBox(height: 300),
              ],
            ),
          );
        }

        //글이 있을 때,
        return SliverToBoxAdapter(
          child: Column(
            children: [
              for (int i = 0; i < categoryMetaDataList.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    top: i == 0 ? 0 : 10,
                    bottom: i == categoryMetaDataList.length - 1 ? 50 : 0,
                  ),
                  child: HorizontalCategorySection(
                    // 전체에서,
                    showHeader: filteredCategoryId == null,
                    title: categoryMetaDataList[i].title,
                    categoryId: categoryMetaDataList[i].categoryId,
                    posts: categoryMetaDataList[i].posts,
                    sectionIndex: i,
                    displayMode: FeedDisplayMode.imageOnly,
                    isLastSection: i == categoryMetaDataList.length - 1,
                    categoryDropTargetIndex: _categoryDropTargetIndex,
                    draggingSectionIndex: _draggingSectionIndex,
                    isDraggingCategory: _isDraggingCategory,
                    mainScrollController: _mainScrollController,
                    onDragStateChanged: onDragStateChanged,
                  ),
                ),
              SizedBox(height: 200),
            ],
          ),
        );
      },
    );
  }
}
