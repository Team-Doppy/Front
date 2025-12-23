import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/vertical_category_section.dart';
import 'package:doppy/pages/components/grid_category_section.dart';
import 'package:doppy/data/models/category_model.dart';
import 'package:doppy/pages/components/card_view_shimmer.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/pages/components/profile_empty_state_mission_cards.dart';
import 'package:doppy/l10n/app_localizations.dart';
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
  List<PostData> _mapRawToPosts(
    List<dynamic> rawList,
    BaseFeedProvider feedProvider,
  ) {
    // 🎯 userInfo에서 프로필 이미지 추출 (프로필 피드용)
    final String? profileImageFromUser =
        feedProvider.userInfo?['profileImageUrl'] as String?;

    return rawList
        .map((raw) {
          try {
            final postData = PostData.fromServer(raw);

            // 🎯 authorProfileImageUrl이 없거나 비어있으면 userInfo에서 추가
            if ((postData.authorProfileImageUrl.isEmpty) &&
                profileImageFromUser != null &&
                profileImageFromUser.isNotEmpty) {
              return PostData(
                id: postData.id,
                thumbnailImageUrl: postData.thumbnailImageUrl,
                title: postData.title,
                summary: postData.summary,
                author: postData.author,
                authorId: postData.authorId,
                authorProfileImageUrl: profileImageFromUser,
                content: postData.content,
                accessLevel: postData.accessLevel,
                sharedGroupIds: postData.sharedGroupIds,
                sharedGroupNames: postData.sharedGroupNames,
                createdAt: postData.createdAt,
                updatedAt: postData.updatedAt,
                viewCount: postData.viewCount,
                likeCount: postData.likeCount,
                commentCount: postData.commentCount,
                isLiked: postData.isLiked,
              );
            }

            return postData;
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

    // 🚀 Selector를 사용하여 필요한 값만 구독하여 불필요한 rebuild 방지
    return Selector<
      BaseFeedProvider,
      ({
        BaseFilter selectedBase,
        String? selectedCategoryId,
        bool isLoading,
        List<Map<String, dynamic>> categories,
        List<dynamic> posts,
        Map<String, dynamic>? systemCategoryMappings,
        bool isReadOnly,
        NetworkError? networkError,
      })
    >(
      selector:
          (context, feedProvider) => (
            selectedBase: feedProvider.selectedBase,
            selectedCategoryId: feedProvider.selectedCategoryId,
            isLoading: feedProvider.isLoading,
            categories: feedProvider.categories,
            posts: feedProvider.posts,
            systemCategoryMappings: feedProvider.systemCategoryMappings,
            isReadOnly: feedProvider.isReadOnly,
            networkError: feedProvider.networkError,
          ),
      builder: (context, data, _) {
        // 필터링 조건 가져오기
        final filteredBase = data.selectedBase;
        final filteredCategoryId = data.selectedCategoryId;

        // 로딩 중이면 shimmer 표시
        if (data.isLoading && data.categories.isEmpty) {
          return _buildLoadingShimmer(context);
        }

        // 카테고리 → 섹션 메타 구성
        final List<CategoryMetaData> categoryMetaDataList = [];

        // 시스템 카테고리 처리 (나만보기, 친구공유, 그룹공개, 전체공개)
        // BaseFilter를 직접 사용하여 필터링
        // 단, filteredCategoryId가 있으면 커스텀 카테고리 상세보기이므로 시스템 필터를 무시
        if (filteredBase != BaseFilter.all && filteredCategoryId == null) {
          // systemCategoryMappings를 사용하여 포스트 필터링
          final systemKey = SystemCategoryKeys.fromBaseFilter(filteredBase);
          final systemTitle =
              systemKey != null
                  ? SystemCategoryKeys.getDisplayText(context, systemKey)
                  : context.tr('all');

          // systemCategoryMappings에서 포스트 ID 목록 가져오기
          final systemMappings = data.systemCategoryMappings;
          List<PostData> filteredPosts = [];

          if (systemMappings != null &&
              systemKey != null &&
              systemKey.isNotEmpty) {
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
              final feedProvider = context.read<BaseFeedProvider>();
              final allPosts = _mapRawToPosts(data.posts, feedProvider);
              filteredPosts =
                  allPosts
                      .where((post) => targetPostIds.contains(post.id))
                      .toList();
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
          // 프로필: 내 프로필(읽기 가능 상태)에서는 사용자가 정한 순서를 그대로 사용
          // 단, 사용자가 아직 한 번도 재정렬하지 않은 경우에는 "막 생성된 카테고리"를 한시적으로 맨 앞에 배치 (예외 규칙)
          // 타인 프로필/읽기 전용에서는 기존 정렬 정책 유지 (신규 상단, 시스템/미분류 규칙)

          // 🎯 Feed가 실제로 표시되는 화면에서만 정렬 로직 실행
          // _mainScrollController가 설정되어 있으면 Feed 화면에서 호출된 것
          // (에디터 화면 등에서는 buildFeedContent가 호출되지 않으므로 _mainScrollController가 null)
          final isFeedScreen = _mainScrollController != null;

          final sortedCategories = List<Map<String, dynamic>>.from(
            data.categories,
          );
          if (data.isReadOnly) {
            sortedCategories.sort((a, b) {
              final bool aUncat = _isUncategorized(a);
              final bool bUncat = _isUncategorized(b);
              if (aUncat != bUncat) return aUncat ? 1 : -1; // 미분류 뒤로

              final bool aSys = _isSystemCategory(a);
              final bool bSys = _isSystemCategory(b);
              if (aSys != bSys) return aSys ? 1 : -1; // 시스템 뒤로

              final int aId = (a['id'] as int?) ?? -1;
              final int bId = (b['id'] as int?) ?? -1;
              return bId.compareTo(aId); // 내림차순
            });
          } else {
            // 내 프로필: 아직 사용자 재정렬 이력이 없고 드래그 중이 아닐 때만 신규(최대 id) 카테고리를 맨 앞 예외 배치
            // 🎯 Feed 화면에서만 실행 (에디터 화면 등에서 불필요한 실행 방지)
            if (isFeedScreen) {
              final providerType = context.read<BaseFeedProvider>();
              try {
                final dynamic dyn = providerType;
                final bool hasUserReordered =
                    (dyn is MyProfileFeedProvider)
                        ? dyn.hasUserReordered
                        : false;
                final bool dragging = _isDraggingCategory.value == true;

                if (!hasUserReordered && !dragging) {
                  // 🚀 최적화: 사용자 카테고리만 필터링 (시스템/미분류 제외)
                  final userCats =
                      sortedCategories.where((c) {
                        final id = (c['id'] as int?) ?? -1;
                        return !_isSystemCategory(c) && id != 0;
                      }).toList();

                  if (userCats.isNotEmpty) {
                    // 최대 id(최근 생성) 찾기
                    final int maxId = userCats
                        .map((c) => (c['id'] as int?) ?? -1)
                        .fold(-1, (a, b) => a > b ? a : b);
                    final int currentIndex = sortedCategories.indexWhere(
                      (c) => ((c['id'] as int?) ?? -1) == maxId,
                    );

                    if (currentIndex > 0) {
                      // UI 정렬 (렌더링용)
                      final moved = sortedCategories.removeAt(currentIndex);
                      sortedCategories.insert(0, moved);

                      // 🎯 Provider의 실제 데이터도 변경 (UI와 데이터 일치)
                      if (dyn is MyProfileFeedProvider) {
                        final newOrder =
                            sortedCategories
                                .map((c) => (c['id'] as int?) ?? -1)
                                .where((id) => id >= 0)
                                .toList();

                        // 🚀 최적화: notifyListeners 없이 조용히 재정렬
                        dyn.reorderCategoriesLocallySilently(newOrder);
                      }
                    }
                  }
                }
              } catch (e) {
                debugPrint('[Feed] ❌ 정렬 로직 에러: $e');
              }
            }
          }

          // 정렬된 순서대로 순회 (리오더 반영 + 신규 상단)
          final feedProvider = context.read<BaseFeedProvider>();
          for (final cat in sortedCategories) {
            final categoryKey = (cat['id'] ?? '').toString();
            final rawPosts =
                feedProvider.postsByCategory[categoryKey] ??
                const <Map<String, dynamic>>[];

            final title = (cat['name'] ?? '').toString();

            // 특정 카테고리가 선택되었으면 해당 카테고리만 표시
            if (filteredCategoryId != null &&
                categoryKey != filteredCategoryId) {
              continue;
            }

            // 원본 포스트 목록을 PostData로 변환 (전체 탭이므로 필터 없음)
            final posts = _mapRawToPosts(rawPosts, feedProvider);

            // 타인 프로필이면 빈 카테고리 숨김
            if (posts.isEmpty && data.isReadOnly) continue;

            // 전체 탭에서 시스템 카테고리 필터링 (미분류는 예외)
            if (filteredBase == BaseFilter.all) {
              if (!_includeCategoryInAll(cat, posts)) continue;
            }
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
        if (data.posts.isEmpty ||
            categoryMetaDataList.length == 1 &&
                categoryMetaDataList[0].title == 'system_doppy_uncategorized' &&
                categoryMetaDataList[0].posts.isEmpty) {
          // 오프라인일 때만 오프라인 안내 노출 (데이터가 있으면 위에서 이미 컨텐츠 렌더)
          if (data.networkError != null || !NetworkManager.isOnline) {
            return ErrorStateSliver(
              error:
                  data.networkError ??
                  NetworkError(
                    type: NetworkErrorType.noConnection,
                    message: 'No internet connection',
                    userMessage: '오프라인 상태입니다',
                    isRetryable: true,
                  ),
            );
          }
          // 내 프로필일 때는 미션 카드 표시, 타인 프로필일 때는 빈 메시지 표시
          final feedProvider = context.read<BaseFeedProvider>();
          return ProfileEmptyStateMissionCards(feedProvider: feedProvider);
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

  /// 로딩 중 shimmer 표시
  Widget _buildLoadingShimmer(BuildContext context) {
    final displayMode = FeedDisplayModeManager().value;
    final isCardView = displayMode == FeedDisplayMode.card;

    if (isCardView) {
      // CardView 모드 shimmer
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 1.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == 0) {
                // 카테고리 타이틀 shimmer
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: 12.0,
                    top: 14.0,
                    left: 8.0,
                    right: 200.0,
                  ),
                  child: ShimmerBox(
                    width: 200,
                    height: 24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }
              // 카드 shimmer (실제 간격과 동일하게 2.0)
              return Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: CardViewShimmer(),
              );
            },
            childCount: 6, // 타이틀 1개 + 카드 5개
          ),
        ),
      );
    } else {
      // ImageView (그리드) 모드 shimmer
      return SliverMainAxisGroup(
        slivers: [
          // 카테고리 타이틀 shimmer
          SliverPadding(
            padding: const EdgeInsets.only(
              left: 12.0,
              right: 200.0,
              top: 16.0,
              bottom: 8.0,
            ),
            sliver: SliverToBoxAdapter(
              child: ShimmerBox(
                width: 200,
                height: 24,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // 그리드 shimmer (실제 간격과 동일하게 2.5, 2)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2.5,
                childAspectRatio: 4 / 5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return ImageViewShimmer(
                    isFirst: index == 0,
                    isLast: index == 8,
                  );
                },
                childCount: 9, // 9개의 shimmer 이미지 표시
              ),
            ),
          ),
        ],
      );
    }
  }
}
