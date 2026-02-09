import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/data/models/user_model.dart';
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
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

/// 곰신 홈 화면 콘텐츠
class GirlfriendHomeContent extends StatelessWidget {
  final Function(Phase, Cell) onCellTap;
  final Function(Phase, Cell, Offset?, Offset?) onCellLongPress;
  final Cell? selectedCell;

  const GirlfriendHomeContent({
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
        final connectedMilitaryUser = currentUser?.connectedMilitaryUser;

        // ✅ 선택된 phase만 필터링하여 표시
        MilitaryGridResponse? displayResponse;
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
            final currentUser = context.read<UserProvider>().currentUser;
            // ✅ 곰신의 경우 연결된 남친의 militaryInfo 사용
            final militaryInfo =
                currentUser?.connectedMilitaryUser?.militaryInfo ??
                currentUser?.militaryInfo;
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

        // ✅ 섹션 리스트 구성 (입대 후 홈과 동일한 방식)
        final homeItems = <HomeSectionItem>[
          // ✅ 그리드 바로 밑에 CTA 버튼 (여친일 때는 항상 표시)
          // connectedMilitaryUser가 null이어도 placeholder로 표시
          HomeSectionItem(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: HomeSectionSpacing.sectionMedium,
            ),
            child:
                connectedMilitaryUser != null
                    ? GirlfriendWriteCTASection(
                      girlfriendUser: connectedMilitaryUser,
                      militaryInfo: connectedMilitaryUser.militaryInfo,
                    )
                    : PlaceholderGirlfriendWriteCTASection(
                      // ✅ 현재 사용자의 militaryInfo 또는 connectedMilitaryUser의 militaryInfo 사용
                      militaryInfo:
                          currentUser?.connectedMilitaryUser?.militaryInfo ??
                          currentUser?.militaryInfo,
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
          // ✅ "나에게 온 편지" 섹션
          const HomeSectionItem(child: SupportPostsSection(bottomSpacing: 0)),
          // ✅ 곰신 포스트 섹션 (본인이 작성한 포스트만 필터링)
          if (_getGirlfriendPosts(
            myFeedProvider.posts,
            currentUser?.username,
          ).isNotEmpty)
            HomeSectionItem(
              child: PostCardSection(
                mode: PostCardSectionMode.unlocked,
                posts:
                    _getGirlfriendPosts(
                      myFeedProvider.posts,
                      currentUser?.username,
                    ).take(5).toList(),
                title: '곰신 포스트',
                titleBoldSubstrings: const ['곰신'],
                showAuthorInfo: false,
                bottomSpacing: 0,
              ),
            ),
          // ✅ 친구 포스트 섹션
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
          // ✅ "아는 곰신인가요" 섹션 (친구 추천 섹션)
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
            // ✅ Military Grid (연결된 군인의 그리드)
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

            const SizedBox(height: HomeSectionSpacing.sectionMedium),

            // ✅ 섹션들 표시 (입대 후 홈과 동일한 방식)
            HomeSectionList(items: homeItems),
          ],
        );
      },
    );
  }

  /// 여친 포스트만 필터링 (본인이 작성한 포스트만)
  List<Map<String, dynamic>> _getGirlfriendPosts(
    List<Map<String, dynamic>> allPosts,
    String? currentUsername,
  ) {
    if (currentUsername == null) return [];

    // ✅ 본인이 작성한 포스트만 필터링 (author가 현재 사용자와 일치)
    return allPosts.where((post) {
      final author =
          post['author']?.toString() ??
          post['username']?.toString() ??
          post['authorUsername']?.toString();
      return author == currentUsername;
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
}
