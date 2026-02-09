import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/girlfriend_request_model.dart';
import 'package:doppy/pages/home/home_widgets.dart';
import 'package:doppy/pages/components/military_grid_widget.dart';
import 'package:doppy/pages/screens/my_friends_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/military_grid_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

/// 입대 예정자 홈 화면 콘텐츠
class PreEnlistmentHomeContent extends StatelessWidget {
  final Function(Phase, Cell) onCellTap;
  final Function(Phase, Cell, Offset?, Offset?) onCellLongPress;
  final Cell? selectedCell;

  const PreEnlistmentHomeContent({
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
            final militaryInfo = currentUser?.militaryInfo;
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

        // ✅ 곰신과 연결된 경우 확인 (요청이 아닌 이미 연결된 경우)
        final isConnected =
            connectedGirlfriend != null && !hasGirlfriendRequest;

        final homeItems = <HomeSectionItem>[
          // ✅ 1. 가장 위: "사회에서 추억 남기기" CTA 버튼
          HomeSectionItem(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const SocialMemoryWriteButton(),
          ),
          // ✅ 2. 그 밑: "내 짝궁과 한마디" (연결된 경우만)
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
          // ✅ 3. 그 밑: "입대 전에 꼭 답해보세요" CTA
          const HomeSectionItem(
            padding: EdgeInsets.zero, // FillSection은 padding 없음
            child: PreEnlistmentCTASection(),
          ),
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

            // ✅ 테스트용: 본인 상태 변경 버튼
            HomeSectionList(items: homeItems),
          ],
        );
      },
    );
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
}

// 테스트 버튼 제거됨 - military_info_setting_screen.dart에서만 수정 가능
