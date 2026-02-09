import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/data/models/girlfriend_request_model.dart';
import 'package:doppy/pages/home/home_widgets.dart';
import 'package:doppy/pages/components/military_grid_widget.dart';
import 'package:doppy/pages/screens/my_friends_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/military_grid_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

/// 입대 후 (군인) 홈 화면 콘텐츠
class MilitaryHomeContent extends StatelessWidget {
  final Function(Phase, Cell) onCellTap;
  final Function(Phase, Cell, Offset?, Offset?) onCellLongPress;
  final Cell? selectedCell;

  const MilitaryHomeContent({
    super.key,
    required this.onCellTap,
    required this.onCellLongPress,
    this.selectedCell,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      MilitaryGridProvider,
      FriendProvider,
      UserProvider,
      MyProfileFeedProvider
    >(
      builder: (
        context,
        gridProvider,
        friendProvider,
        userProvider,
        myFeedProvider,
        _,
      ) {
        final gridResponse = gridProvider.gridResponse;
        final currentUser = userProvider.currentUser;
        // ✅ 곰신 요청 상태 확인: girlfriendRequest가 있으면 우선 사용, 없으면 connectedToMeByUser 체크
        final girlfriendRequest = currentUser?.girlfriendRequest;
        final hasGirlfriendRequest =
            girlfriendRequest != null &&
            girlfriendRequest.status == GirlfriendRequestStatus.pending;
        final connectedGirlfriend =
            girlfriendRequest?.requester ?? currentUser?.connectedToMeByUser;

        // ✅ 선택된 phase만 필터링하여 표시 (항상 non-null placeholder 제공)
        final MilitaryGridResponse displayResponse;
        if (gridResponse != null) {
          final selectedPhaseCode =
              gridProvider.selectedPhase?.phase ??
              gridResponse.currentPhase ??
              (gridResponse.phases.isNotEmpty
                  ? gridResponse.phases.first.phase
                  : null);

          Phase? selectedPhase;
          if (selectedPhaseCode != null) {
            for (final p in gridResponse.phases) {
              if (p.phase == selectedPhaseCode) {
                selectedPhase = p;
                break;
              }
            }
            if (selectedPhase == null && gridProvider.selectedPhase != null) {
              selectedPhase = gridProvider.selectedPhase;
            }
          }
          selectedPhase ??=
              gridResponse.phases.isNotEmpty ? gridResponse.phases.first : null;

          displayResponse =
              selectedPhase != null
                  ? MilitaryGridResponse(
                    phases: [selectedPhase],
                    greetingKey: gridResponse.greetingKey,
                    availablePhases: gridResponse.availablePhases,
                    currentPhase: selectedPhase.phase,
                  )
                  : gridResponse;
        } else {
          // Placeholder 처리
          final selectedPhase = gridProvider.selectedPhase;
          if (selectedPhase != null) {
            displayResponse = gridProvider.buildPlaceholderResponse(
              phase: selectedPhase,
            );
          } else {
            final militaryInfo =
                context.read<UserProvider>().currentUser?.militaryInfo;
            final userStatus = militaryInfo?.status;
            final currentRank = militaryInfo?.currentRank;

            final clientPhases = gridProvider.buildClientPhases();
            final defaultPhase =
                gridProvider.determineDefaultPhase(
                  allPhases: clientPhases,
                  userStatus: userStatus,
                  currentRank: currentRank,
                ) ??
                clientPhases.first;

            displayResponse = gridProvider.buildPlaceholderResponse(
              phase: defaultPhase,
            );
          }
        }

        // 섹션 리스트 구성
        final sections = <Widget>[];

        // ✅ 받은 Support 글 섹션 (임시 하드코딩)
        sections.add(SupportPostsSection());

        // ✅ 진급 리포트 CTA (임시 하드코딩 - 리포트가 있다고 가정)
        sections.add(PromotionReportCTASection());

        // ✅ 친구 포스트 섹션
        if (friendProvider.friendPosts.isNotEmpty) {
          sections.add(
            PostCardSection(
              mode: PostCardSectionMode.unlocked,
              posts: friendProvider.friendPosts.take(5).toList(),
              title: '요새 내 친구들',
              titleBoldSubstrings: const ['요새'],
              showAuthorInfo: true,
            ),
          );
        }

        // ✅ 친구 추천 섹션
        sections.add(
          FriendRecommendationSection(
            onFriendTap: (String username) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => UserProfileScreen(
                        otherUser: User(username: username),
                      ),
                ),
              );
            },
            onAddFriendTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => UserSearchBottomSheet(),
              );
            },
          ),
        );

        // ✅ 곰신과 연결된 경우 확인 (요청이 아닌 이미 연결된 경우)
        final isConnected =
            connectedGirlfriend != null && !hasGirlfriendRequest;

        final homeItems = <HomeSectionItem>[
          HomeSectionItem(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const ThisWeekWriteButton(),
          ),
          if (hasGirlfriendRequest)
            HomeSectionItem(
              padding: EdgeInsets.zero, // FillSection은 padding 없음
              child: GirlfriendRequestAcceptSection(
                girlfriendRequest: girlfriendRequest,
              ),
            ),
          if (isConnected)
            HomeSectionItem(
              padding: const EdgeInsets.symmetric(horizontal: 12), // 일반 CTA 카드
              child: GirlfriendWriteCTASection(
                girlfriendUser: connectedGirlfriend,
                militaryInfo: currentUser?.militaryInfo,
              ),
            ),
          // ✅ 네트워크 오프라인 상태 표시
          HomeSectionItem(
            child: StreamBuilder<bool>(
              stream: NetworkManager.onConnectivityChanged,
              initialData: NetworkManager.isOnline,
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? NetworkManager.isOnline;
                if (!isOnline) {
                  return _buildOfflineBanner(context);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          // ✅ 받은 Support 글 섹션 (임시 하드코딩)
          const HomeSectionItem(child: SupportPostsSection(bottomSpacing: 0)),
          // ✅ 진급 리포트 CTA (임시 하드코딩 - 리포트가 있다고 가정)
          const HomeSectionItem(
            child: PromotionReportCTASection(bottomSpacing: 0),
          ),
          // ✅ "사회에서의 추억" 섹션 (입대전 + 휴가 포스트)
          if (_getSocialMemoryPosts(myFeedProvider.posts).isNotEmpty)
            HomeSectionItem(
              child: PostCardSection(
                mode: PostCardSectionMode.unlocked,
                posts:
                    _getSocialMemoryPosts(
                      myFeedProvider.posts,
                    ).take(5).toList(),
                title: '사회에서의 추억',
                titleBoldSubstrings: const ['사회에서의'],
                showAuthorInfo: false,
                bottomSpacing: 0,
              ),
            ),
          if (friendProvider.friendPosts.isNotEmpty)
            HomeSectionItem(
              child: PostCardSection(
                mode: PostCardSectionMode.unlocked,
                posts: friendProvider.friendPosts.take(5).toList(),
                title: '요새 내 친구들',
                titleBoldSubstrings: const ['요새'],
                showAuthorInfo: true,
                bottomSpacing: 0,
              ),
            ),
          HomeSectionItem(
            child: FriendRecommendationSection(
              onFriendTap: (String username) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => UserProfileScreen(
                          otherUser: User(username: username),
                        ),
                  ),
                );
              },
              onAddFriendTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (context) => UserSearchBottomSheet(),
                );
              },
              bottomSpacing: 0,
              bottomPadding: 0,
            ),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Military Grid (placeholder 포함)
            MilitaryGridWidget(
              key: ValueKey('grid-${displayResponse.currentPhase ?? 'all'}'),
              gridResponse: displayResponse,
              onCellTap: onCellTap,
              onLongPress: onCellLongPress,
              selectedCell: selectedCell,
              isLoading: gridProvider.isLoading,
              onCellKey: (phase, cell, key) {
                gridProvider.registerCellKey(phase, cell, key);
              },
            ),

            const SizedBox(height: HomeSectionSpacing.sectionLarge),

            HomeSectionList(items: homeItems),
          ],
        );
      },
    );
  }

  /// ✅ "사회에서의 추억" 포스트 필터링 (입대전 + 휴가)
  /// lifePhase가 'LEAVE_OR_PRE_ENLISTMENT'인 포스트만 반환
  List<Map<String, dynamic>> _getSocialMemoryPosts(
    List<Map<String, dynamic>> allPosts,
  ) {
    return allPosts.where((post) {
      final lifePhase = post['lifePhase'] as String?;
      // lifePhase가 'LEAVE_OR_PRE_ENLISTMENT'인 포스트만 필터링
      return lifePhase == 'LEAVE_OR_PRE_ENLISTMENT';
    }).toList();
  }

  /// 오프라인 상태 배너
  Widget _buildOfflineBanner(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(
        bottom: HomeSectionSpacing.sectionLarge,
        left: 20,
        right: 20,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '오프라인 상태',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: onSurface,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '네트워크 연결을 확인해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 테스트 버튼 제거됨 - military_info_setting_screen.dart에서만 수정 가능
}
