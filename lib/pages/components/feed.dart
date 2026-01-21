import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/vertical_category_section.dart';
import 'package:doppy/pages/components/grid_category_section.dart';
import 'package:doppy/pages/components/card_view_shimmer.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/pages/components/profile_empty_state_mission_cards.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Feed {
  ScrollController? _mainScrollController;

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
                author: postData.author,
                authorId: postData.authorId,
                authorProfileImageUrl: profileImageFromUser,
                content: postData.content,
                accessLevel: postData.accessLevel,
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

  /// 메인 빌드: 포스트 리스트 렌더링
  Widget buildFeedContent({ScrollController? scrollController}) {
    _mainScrollController = scrollController;

    return Selector<
      BaseFeedProvider,
      ({
        BaseFilter selectedBase,
        bool isLoading,
        List<dynamic> posts,
        Map<String, dynamic>? systemCategoryMappings,
        Map<String, dynamic>? userInfo,
        bool isReadOnly,
        NetworkError? networkError,
      })
    >(
      selector:
          (context, feedProvider) => (
            selectedBase: feedProvider.selectedBase,
            isLoading: feedProvider.isLoading,
            posts: feedProvider.posts,
            systemCategoryMappings: feedProvider.systemCategoryMappings,
            userInfo: feedProvider.userInfo,
            isReadOnly: feedProvider.isReadOnly,
            networkError: feedProvider.networkError,
          ),
      builder: (context, data, _) {
        // 로딩 중이면 shimmer 표시
        if (data.isLoading) {
          return _buildLoadingShimmer(context);
        }

        // userInfo에서 isOwnProfile 확인
        final isOwnProfile = data.userInfo?['isOwnProfile'] as bool? ?? true;

        // 공개범위 필터링
        List<PostData> filteredPosts = [];
        final feedProvider = context.read<BaseFeedProvider>();
        final allPosts = _mapRawToPosts(data.posts, feedProvider);

        // 다른 유저 프로필일 때는 공개범위 필터링 제거 (서버에서 이미 필터링됨)
        if (isOwnProfile && data.selectedBase != BaseFilter.all) {
          // systemCategoryMappings를 사용하여 포스트 필터링
          final systemKey = SystemCategoryKeys.fromBaseFilter(
            data.selectedBase,
          );
          final systemMappings = data.systemCategoryMappings;

          if (systemMappings != null &&
              systemKey != null &&
              systemKey.isNotEmpty) {
            final postIdList = systemMappings[systemKey] as List?;
            if (postIdList != null && postIdList.isNotEmpty) {
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

              filteredPosts =
                  allPosts
                      .where((post) => targetPostIds.contains(post.id))
                      .toList();
            }
          }
        } else {
          // 전체 탭: 모든 포스트 표시
          filteredPosts = allPosts;
        }

        // 아무런 글도 없을 때
        if (filteredPosts.isEmpty) {
          final err = data.networkError;
          final isOfflineLikeError =
              err != null &&
              (err.type == NetworkErrorType.noConnection ||
                  err.type == NetworkErrorType.timeout);

          // ✅ "진짜 오프라인"인 경우에만 오프라인 에러 UI를 노출
          if (isOfflineLikeError || !NetworkManager.isOnline) {
            final l10n = AppLocalizations.of(context);
            return ErrorStateSliver(
              error:
                  data.networkError ??
                  NetworkError(
                    type: NetworkErrorType.noConnection,
                    message: 'No internet connection',
                    userMessage: l10n.t('offline_status_message'),
                    isRetryable: true,
                  ),
            );
          }
          return ProfileEmptyStateMissionCards(feedProvider: feedProvider);
        }

        // 글이 있을 때
        final displayModeManager = FeedDisplayModeManager();

        return ValueListenableBuilder<FeedDisplayMode>(
          valueListenable: displayModeManager,
          builder:
              (context, displayMode, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 80),
                  child: _buildPostSection(
                    filteredPosts,
                    displayMode,
                    isOwnProfile,
                  ),
                ),
              ),
        );
      },
    );
  }

  Widget _buildPostSection(
    List<PostData> posts,
    FeedDisplayMode displayMode,
    bool isOwnProfile,
  ) {
    if (displayMode == FeedDisplayMode.card) {
      return VerticalCategorySection(
        posts: posts,
        displayMode: displayMode,
        isLastSection: true,
        mainScrollController: _mainScrollController,
        isOwnProfile: isOwnProfile,
      );
    }

    return GridCategorySection(
      posts: posts,
      displayMode: displayMode,
      isLastSection: true,
      mainScrollController: _mainScrollController,
      isOwnProfile: isOwnProfile,
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: CardViewShimmer(),
              );
            },
            childCount: 5, // 카드 5개
          ),
        ),
      );
    } else {
      // ImageView (그리드) 모드 shimmer
      return SliverPadding(
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
              return ImageViewShimmer(isFirst: index == 0, isLast: index == 8);
            },
            childCount: 9, // 9개의 shimmer 이미지 표시
          ),
        ),
      );
    }
  }
}
