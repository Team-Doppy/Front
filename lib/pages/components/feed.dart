import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/vertical_category_section.dart';
import 'package:doppy/pages/components/grid_category_section.dart';
import 'package:doppy/pages/components/feed_loading_shimmer_sliver.dart';
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
          return const FeedLoadingShimmerSliver();
        }

        // userInfo에서 isOwnProfile 확인
        final isOwnProfile = data.userInfo?['isOwnProfile'] as bool? ?? true;

        // 공개범위 필터링 - systemCategoryMappings에 있는 실제 데이터만 표시
        List<PostData> filteredPosts = [];
        final feedProvider = context.read<BaseFeedProvider>();
        final allPosts = _mapRawToPosts(data.posts, feedProvider);
        final systemMappings = data.systemCategoryMappings;

        // ✅ API 명세: 서버에서 phase와 accessLevel 모두 필터링
        // 서버에서 이미 필터링된 데이터를 그대로 사용
        final selectedAccessLevel = feedProvider.serverAccessLevel;
        final selectedPhase = feedProvider.serverPhase;
        final selectedLifePhase = feedProvider.serverLifePhase;

        if (selectedPhase != null ||
            selectedLifePhase != null ||
            selectedAccessLevel != null) {
          // 서버에서 필터링된 데이터를 그대로 사용
          filteredPosts = allPosts;
          debugPrint(
            '[Feed] 서버 필터 적용: phase=$selectedPhase, '
            'lifePhase=$selectedLifePhase, accessLevel=$selectedAccessLevel, '
            'filteredPosts=${filteredPosts.length}개',
          );
        }
        // 필터가 없으면 systemCategoryMappings로 클라이언트 필터링 (전체 탭)
        else if (systemMappings == null || systemMappings.isEmpty) {
          filteredPosts = [];
        } else {
          // 탭에서 선택한 공개범위 사용
          String? targetAccessLevelKey;
          if (data.selectedBase != BaseFilter.all) {
            targetAccessLevelKey = SystemCategoryKeys.fromBaseFilter(
              data.selectedBase,
            );
          }

          // systemCategoryMappings에서 필터링할 키 목록
          final targetKeys = <String>[];
          if (targetAccessLevelKey != null &&
              systemMappings.containsKey(targetAccessLevelKey)) {
            // 특정 공개범위만 필터링
            targetKeys.add(targetAccessLevelKey);
          } else {
            // 전체 공개범위 (모든 키)
            targetKeys.addAll(systemMappings.keys);
          }

          // 선택된 키들에서 postId 수집 및 정렬
          final allOrderedPosts = <Map<String, dynamic>>[];
          for (final key in targetKeys) {
            final postIdList = systemMappings[key] as List?;
            if (postIdList != null && postIdList.isNotEmpty) {
              for (final item in postIdList) {
                if (item is Map<String, dynamic>) {
                  allOrderedPosts.add(item);
                } else if (item is int) {
                  allOrderedPosts.add({
                    'postId': item,
                    'order': allOrderedPosts.length,
                  });
                }
              }
            }
          }

          // order 순서대로 정렬
          allOrderedPosts.sort((a, b) {
            final orderA = (a['order'] as num?)?.toInt() ?? 0;
            final orderB = (b['order'] as num?)?.toInt() ?? 0;
            return orderA.compareTo(orderB);
          });

          // postId 추출
          final orderedPostIds =
              allOrderedPosts
                  .map((m) => m['postId']?.toString())
                  .whereType<String>()
                  .toList();

          // 실제 존재하는 포스트만 필터링 (플레이스홀더 제거)
          final postMap = {for (var post in allPosts) post.id: post};
          filteredPosts =
              orderedPostIds
                  .map((id) => postMap[id])
                  .where((post) => post != null)
                  .cast<PostData>()
                  .toList();
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // (리뉴얼 명세) 탭/타이틀은 UserProfileScreen에서 관리
                      _buildPostSection(
                        filteredPosts,
                        displayMode,
                        isOwnProfile,
                      ),
                    ],
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
    Widget postSection;

    if (displayMode == FeedDisplayMode.card) {
      postSection = VerticalCategorySection(
        posts: posts,
        displayMode: displayMode,
        isLastSection: true,
        mainScrollController: _mainScrollController,
        isOwnProfile: isOwnProfile,
      );
    } else {
      postSection = GridCategorySection(
        posts: posts,
        displayMode: displayMode,
        isLastSection: true,
        mainScrollController: _mainScrollController,
        isOwnProfile: isOwnProfile,
      );
    }

    return postSection;
  }

  // (리뉴얼 명세) phase/lifePhase 필터링은 서버에서 처리한다.
}
