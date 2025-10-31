import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/vertical_category_section.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/grid_category_section.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/category_model.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
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

        // 디버그 로그 (오프라인이어도 데이터가 있으면 기존 컨텐츠 유지)
        print('[Feed] networkError: ${feedProvider.networkError}');
        print('[Feed] NetworkManager.isOnline: ${NetworkManager.isOnline}');
        print('[Feed] categories.length: ${feedProvider.categories.length}');
        print('[Feed] isLoading: ${feedProvider.isLoading}');
        print('[Feed] posts.length: ${feedProvider.posts.length}');

        // 로딩 중이면 이전 컨텐츠 유지 (깜빡임 방지)
        // 단, 초기 로딩이고 데이터가 없을 때만 비워두기
        if (feedProvider.isLoading && feedProvider.categories.isEmpty) {
          print('[Feed] ✅ 로딩 중 - 빈 위젯 반환');
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // 카테고리 → 섹션 메타 구성
        final List<CategoryMetaData> categoryMetaDataList = [];

        // 시스템 카테고리 처리 (나만보기, 그룹공개, 전체공개)
        // BaseFilter를 직접 사용하여 필터링
        // 단, filteredCategoryId가 있으면 커스텀 카테고리 상세보기이므로 시스템 필터를 무시
        if (filteredBase != BaseFilter.all && filteredCategoryId == null) {
          // systemCategoryMappings를 사용하여 포스트 필터링
          String systemTitle;
          String systemKey;
          switch (filteredBase) {
            case BaseFilter.private:
              systemTitle = '나만보기';
              systemKey = '나만보기';
              break;
            case BaseFilter.groups:
              systemTitle = '그룹공유';
              systemKey = '그룹공유';
              break;
            case BaseFilter.public:
              systemTitle = '전체공개';
              systemKey = '전체공개';
              break;
            case BaseFilter.all:
              systemTitle = '전체';
              systemKey = '';
              break;
          }

          // systemCategoryMappings에서 포스트 ID 목록 가져오기
          final systemMappings = feedProvider.systemCategoryMappings;
          List<PostData> filteredPosts = [];

          if (systemMappings != null && systemKey.isNotEmpty) {
            final postIdList = systemMappings[systemKey] as List?;
            if (postIdList != null && postIdList.isNotEmpty) {
              // 포스트 ID를 Set으로 변환 (빠른 조회를 위해)
              final Set<String> targetPostIds =
                  postIdList
                      .map((item) {
                        if (item is Map) {
                          return item['postId']?.toString();
                        } else if (item is int) {
                          return item.toString();
                        }
                        return item?.toString();
                      })
                      .whereType<String>()
                      .toSet();

              // 모든 포스트에서 해당 ID에 맞는 포스트만 필터링
              final allPosts = _mapRawToPosts(feedProvider.posts);
              filteredPosts =
                  allPosts
                      .where((post) => targetPostIds.contains(post.id))
                      .toList();

              print('[Feed] 시스템 카테고리 필터링: $systemKey');
              print(
                '[Feed] systemCategoryMappings 포스트 ID 수: ${targetPostIds.length}',
              );
              print('[Feed] 필터링된 포스트 수: ${filteredPosts.length}');
            }
          }

          if (filteredPosts.isNotEmpty) {
            categoryMetaDataList.add(
              CategoryMetaData(
                title: systemTitle,
                posts: filteredPosts,
                categoryId: 'system_${filteredBase.name}',
                isReadOnly: true,
              ),
            );
          }
        } else {
          // 카테고리 배열 순서대로 순회 (리오더 반영)
          for (final cat in feedProvider.categories) {
            final categoryKey = (cat['id'] ?? '').toString();
            final rawPosts =
                feedProvider.postsByCategory[categoryKey] ??
                const <Map<String, dynamic>>[];

            final title = (cat['name'] ?? '').toString();

            print('[Feed] 카테고리 체크 - key: $categoryKey, title: $title');

            // 특정 카테고리가 선택되었으면 해당 카테고리만 표시
            if (filteredCategoryId != null &&
                categoryKey != filteredCategoryId) {
              continue;
            }

            print('[Feed] 선택됨 - $title (key: $categoryKey)');

            // 원본 포스트 목록을 PostData로 변환 (전체 탭이므로 필터 없음)
            final posts = _mapRawToPosts(rawPosts);

            print('[Feed] 포스트 개수: ${posts.length}');

            // 타인 프로필이면 빈 카테고리 숨김
            if (posts.isEmpty && feedProvider.isReadOnly) continue;

            // 전체 탭에서 시스템 카테고리 필터링 (미분류는 예외)
            if (filteredBase == BaseFilter.all) {
              if (!_includeCategoryInAll(cat, posts)) continue;
            }

            print('[Feed] 카테고리 추가: $title');
            categoryMetaDataList.add(
              CategoryMetaData(
                title: title,
                posts: posts,
                categoryId: categoryKey,
              ),
            );
          }
        }

        // 아무런 글도 없을 때,
        if (feedProvider.posts.isEmpty ||
            categoryMetaDataList.length == 1 &&
                categoryMetaDataList[0].title == 'system_doppy_uncategorized' &&
                categoryMetaDataList[0].posts.isEmpty) {
          // 오프라인일 때만 오프라인 안내 노출 (데이터가 있으면 위에서 이미 컨텐츠 렌더)
          if (feedProvider.networkError != null || !NetworkManager.isOnline) {
            print('[Feed] 오프라인 + 컨텐츠 없음 → 피드 영역 오프라인 메시지 표시');
            return ErrorStateSliver(
              error:
                  feedProvider.networkError ??
                  NetworkError(
                    type: NetworkErrorType.noConnection,
                    message: 'No internet connection',
                    userMessage: '오프라인 상태입니다',
                    isRetryable: true,
                  ),
            );
          }
          return SliverToBoxAdapter(
            child: Column(
              children: [
                SizedBox(height: 100),
                Icon(
                  Icons.search,
                  size: 100,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                ),
                SizedBox(height: 10),
                Text(
                  '아직은 포스트가 없어요!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                SizedBox(height: 300),
              ],
            ),
          );
        }

        // 글이 있을 때
        final displayModeManager = FeedDisplayModeManager();

        return ValueListenableBuilder<FeedDisplayMode>(
          valueListenable: displayModeManager,
          builder:
              (context, displayMode, _) => SliverToBoxAdapter(
                child: Column(
                  children: [
                    for (int i = 0; i < categoryMetaDataList.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 0 : 10,
                          bottom: i == categoryMetaDataList.length - 1 ? 50 : 0,
                        ),
                        child: _buildCategorySection(
                          categoryMetaDataList[i],
                          i,
                          categoryMetaDataList.length,
                          displayMode,
                          filteredCategoryId,
                        ),
                      ),
                    SizedBox(height: 100),
                  ],
                ),
              ),
        );
      },
    );
  }

  Widget _buildCategorySection(
    CategoryMetaData categoryMetaData,
    int sectionIndex,
    int totalSections,
    FeedDisplayMode displayMode,
    String? filteredCategoryId,
  ) {
    if (displayMode == FeedDisplayMode.card) {
      return VerticalCategorySection(
        showHeader: filteredCategoryId == null && !categoryMetaData.isReadOnly,
        title: categoryMetaData.title,
        categoryId: categoryMetaData.categoryId,
        posts: categoryMetaData.posts,
        sectionIndex: sectionIndex,
        displayMode: displayMode,
        isLastSection: sectionIndex == totalSections - 1,
        categoryDropTargetIndex: _categoryDropTargetIndex,
        draggingSectionIndex: _draggingSectionIndex,
        isDraggingCategory: _isDraggingCategory,
        mainScrollController: _mainScrollController,
        onDragStateChanged: onDragStateChanged,
      );
    }

    return GridCategorySection(
      showHeader: filteredCategoryId == null && !categoryMetaData.isReadOnly,
      title: categoryMetaData.title,
      categoryId: categoryMetaData.categoryId,
      posts: categoryMetaData.posts,
      sectionIndex: sectionIndex,
      displayMode: displayMode,
      isLastSection: sectionIndex == totalSections - 1,
      categoryDropTargetIndex: _categoryDropTargetIndex,
      draggingSectionIndex: _draggingSectionIndex,
      isDraggingCategory: _isDraggingCategory,
      mainScrollController: _mainScrollController,
      onDragStateChanged: onDragStateChanged,
    );
  }
}
