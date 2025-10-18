import 'package:doppy/data/models/post_data.dart';

import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/horizontal_category_section.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/category_model.dart';

import 'package:doppy/providers/profile_feed_provider.dart';

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

  /// 메인 빌드: 카테고리별 수평 섹션 렌더링 (전체 탭 기준)
  Widget buildFeedContent({ScrollController? scrollController}) {
    _mainScrollController = scrollController;

    return Consumer<ProfileFeedProvider>(
      builder: (context, feedProvider, _) {
        // 필터링 조건 가져오기
        final filteredBase = feedProvider.selectedBase;
        final filteredCategoryId = feedProvider.selectedCategoryId;

        // 로딩 중이면 비워두기
        if (feedProvider.isLoading) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // 카테고리 → 섹션 메타 구성 (시스템 카테고리 포함)
        final List<CategoryMetaData> categoryMetaDataList = [];

        // 사용자 정의 카테고리
        for (final cat in feedProvider.categories) {
          final idStr = (cat['id'] ?? '').toString();
          final title = (cat['name'] ?? '').toString();

          print('[Feed] 카테고리 체크 - idStr: $idStr, title: $title');

          // 특정 카테고리가 선택되었으면 해당 카테고리만 표시
          if (filteredCategoryId != null && idStr != filteredCategoryId) {
            continue;
          }

          print('[Feed] 선택됨 - $title (id: $idStr)');

          // 원본 포스트 목록
          final rawPosts = feedProvider.postsByCategory[idStr] ?? const [];
          List<PostData> posts =
              rawPosts
                  .map((raw) {
                    try {
                      return PostData.fromServer(raw);
                    } catch (_) {
                      return null;
                    }
                  })
                  .whereType<PostData>()
                  .toList();

          // BaseFilter에 따라 필터링
          if (filteredBase != BaseFilter.all) {
            posts =
                posts.where((post) {
                  switch (filteredBase) {
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

          // 타인 프로필이면 빈 카테고리 숨김
          if (posts.isEmpty && feedProvider.isReadOnly) continue;

          categoryMetaDataList.add(
            CategoryMetaData(title: title, posts: posts, categoryId: idStr),
          );
        }

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
