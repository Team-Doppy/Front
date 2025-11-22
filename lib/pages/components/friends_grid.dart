import 'dart:ui' as ui;
import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/friend_request_bottom_sheet.dart';
import 'package:doppy/pages/components/member_action_menu_overlay.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/group_model.dart';
import '../../providers/friend_provider.dart';
import '../../providers/group_provider.dart';
import '../screens/user_profile_screen.dart';

// 친구 상태 enum
enum FriendState { requestReceived, accepted }

// 친구 타일 데이터
class FriendTileData {
  final String username;
  final String? url;
  final String? alias;
  final FriendState state;
  FriendTileData({
    required this.username,
    required this.url,
    this.alias,
    required this.state,
  });
}

// --- 하단 친구 그리드 (요청/대기/확정 순으로 정렬, 대기는 블러 처리) ---
class FriendsGrid extends StatefulWidget {
  final FriendProvider friendProv;
  final Group? selectedGroup;
  final GroupProvider groupProv;
  final String searchQuery;
  final bool isMultiSelectMode; // 🎯 다중 선택 모드
  final Set<String> selectedMembers; // 🎯 선택된 멤버
  final ScrollController scrollController; // 🎯 스크롤 컨트롤러
  final Function(String) onMemberToggle; // 🎯 멤버 선택/해제 콜백

  const FriendsGrid({
    Key? key,
    required this.friendProv,
    required this.selectedGroup,
    required this.groupProv,
    required this.searchQuery,
    required this.isMultiSelectMode,
    required this.selectedMembers,
    required this.scrollController,
    required this.onMemberToggle,
  }) : super(key: key);

  @override
  State<FriendsGrid> createState() => _FriendsGridState();
}

class _FriendsGridState extends State<FriendsGrid> {
  bool _showLoading = false;
  DateTime? _loadingStartTime;

  @override
  void didUpdateWidget(FriendsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 로딩 상태가 변경되었을 때
    if (widget.friendProv.isLoading != oldWidget.friendProv.isLoading) {
      if (widget.friendProv.isLoading) {
        // 로딩 시작: 타이머 설정
        _loadingStartTime = DateTime.now();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted &&
              widget.friendProv.isLoading &&
              _loadingStartTime != null &&
              DateTime.now().difference(_loadingStartTime!) >=
                  const Duration(milliseconds: 500)) {
            setState(() {
              _showLoading = true;
            });
          }
        });
      } else {
        // 로딩 종료: 초기화
        _loadingStartTime = null;
        if (_showLoading) {
          setState(() {
            _showLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 친구 로딩 중: Shimmer로 그리드 UI 유지
    if (widget.friendProv.isLoading && _showLoading) {
      return _buildFriendsShimmer();
    } else {
      List<Friend> accepted = widget.friendProv.acceptedFriends;
      List<Friend> received =
          widget.friendProv.receivedRequests; // 받은 요청(상단 우선)
      // List<Friend> sent = widget.friendProv.sentRequests; // 내가 보낸 요청은 제외

      // 🎯 전체 친구 그룹인지 확인 (isSystem == true)
      final isAllFriendsGroup =
          widget.selectedGroup != null &&
          widget.selectedGroup!.isSystem == true;

      // 그룹이 선택된 경우 해당 그룹의 멤버만 필터링
      if (widget.selectedGroup != null) {
        // 전체 친구 그룹이 아닌 경우에만 그룹 멤버로 필터링
        if (!isAllFriendsGroup) {
          final groupMembers = widget.groupProv.membersOf(
            widget.selectedGroup!.id,
          );
          final memberUsernames = groupMembers.map((m) => m.userId).toSet();

          accepted =
              accepted
                  .where((f) => memberUsernames.contains(f.username))
                  .toList();
          received =
              received
                  .where((f) => memberUsernames.contains(f.username))
                  .toList();
          // sent 상태는 제외
        }
        // 🎯 전체 친구 그룹에서는 받은 요청 제외 (수락된 친구만 표시)
        else {
          received = []; // 전체 친구에서는 받은 요청 표시 안 함
        }
      }

      // 🎯 검색어가 있으면 친구 이름 또는 별명으로 필터링
      if (widget.searchQuery.isNotEmpty) {
        final query = widget.searchQuery.toLowerCase();
        accepted =
            accepted
                .where(
                  (f) =>
                      f.username.toLowerCase().contains(query) ||
                      f.alias.toLowerCase().contains(query),
                )
                .toList();
        received =
            received
                .where(
                  (f) =>
                      f.username.toLowerCase().contains(query) ||
                      f.alias.toLowerCase().contains(query),
                )
                .toList();
        // sent 상태는 제외
      }

      final List<FriendTileData> tiles = [];
      // 🎯 전체 친구 그룹이 아닌 경우에만 받은 요청 추가
      if (widget.selectedGroup == null || !isAllFriendsGroup) {
        for (final f in received) {
          tiles.add(
            FriendTileData(
              username: f.username,
              url: f.profileImageUrl,
              alias: f.alias,
              state: FriendState.requestReceived,
            ),
          );
        }
      }
      // sent 상태는 제외
      for (final f in accepted) {
        tiles.add(
          FriendTileData(
            username: f.username,
            url: f.profileImageUrl,
            alias: f.alias,
            state: FriendState.accepted,
          ),
        );
      }

      // 🎯 로딩 완료 후에만 "친구 없음" 메시지 표시
      if (tiles.isEmpty) {
        // 🎯 빈 상태: 포스트 빈 상태와 동일한 구조로 통일
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.4, // 화면 높이의 40%
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Container()), // 위쪽 간격
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  widget.selectedGroup != null
                      ? widget.selectedGroup!.isSystem == true
                          ? context.tr('no_friends_to_display')
                          : context.tr('no_friends_in_group')
                      : context.tr('no_friends_to_display'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(child: Container()), // 아래쪽 간격
            ],
          ),
        );
      }

      // 🎯 전체 친구 그룹인 경우 accepted friends만 무한 스크롤
      final bool shouldLoadMore =
          isAllFriendsGroup &&
          widget.friendProv.hasMoreAcceptedFriends &&
          !widget.friendProv.isLoadingMoreAcceptedFriends;

      final bool showLoadingIndicator =
          isAllFriendsGroup &&
          (widget.friendProv.isLoadingMoreAcceptedFriends ||
              widget.friendProv.hasMoreAcceptedFriends);

      return RawScrollbar(
        controller: widget.scrollController,
        thumbColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
        radius: const Radius.circular(8),
        thickness: 4,
        thumbVisibility: true,
        child: GridView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 6,
            childAspectRatio: 0.75, // 🎯 텍스트 공간 확보를 위해 높이 증가 (0.82 -> 0.75)
          ),
          itemCount: tiles.length + (showLoadingIndicator ? 3 : 0),
          itemBuilder: (context, i) {
            // 🎯 마지막에서 3번째 아이템에 도달하면 더 불러오기
            if (isAllFriendsGroup && i == tiles.length - 3 && shouldLoadMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.friendProv.loadMoreAcceptedFriends();
              });
            }

            // 🎯 로딩 인디케이터
            if (i >= tiles.length) {
              return Center(
                child:
                    widget.friendProv.isLoadingMoreAcceptedFriends
                        ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        )
                        : const SizedBox.shrink(),
              );
            }

            final t = tiles[i];
            return FriendTile(
              data: t,
              isMultiSelectMode: widget.isMultiSelectMode, // 🎯 다중 선택 모드 전달
              isSelected: widget.selectedMembers.contains(
                t.username,
              ), // 🎯 선택 여부 전달
              onToggle: () => widget.onMemberToggle(t.username), // 🎯 선택 토글 콜백
            );
          },
        ),
      );
    }
  }

  // 🎯 친구 그리드 Shimmer 빌드
  Widget _buildFriendsShimmer() {
    return RawScrollbar(
      controller: widget.scrollController,
      thumbColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
      radius: const Radius.circular(8),
      thickness: 4,
      thumbVisibility: true,
      child: GridView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 6,
          childAspectRatio: 0.75,
        ),
        itemCount: 9, // 9개의 shimmer 아이템 표시
        itemBuilder: (context, index) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 프로필 원형 Shimmer
              ShimmerBox(width: 130, height: 130, shape: const CircleBorder()),
              const SizedBox(height: 8),
              // 이름 Shimmer
              ShimmerBox(
                width: 80,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 4),
              // 별명 Shimmer (선택적)
              ShimmerBox(
                width: 60,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FriendTile extends StatelessWidget {
  final FriendTileData data;
  final bool isMultiSelectMode; // 🎯 다중 선택 모드
  final bool isSelected; // 🎯 선택 여부
  final VoidCallback onToggle; // 🎯 선택 토글 콜백

  const FriendTile({
    Key? key,
    required this.data,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onToggle,
  }) : super(key: key);

  static void showFriendRequestBottomSheet(
    BuildContext context,
    String username,
  ) {
    // 받은 요청에서 해당 사용자의 프로필 이미지 URL 찾기
    final friendProvider = context.read<FriendProvider>();
    final receivedRequest =
        friendProvider.receivedRequests
            .where((friend) => friend.username == username)
            .firstOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
              child: FriendRequestBottomSheet(
                username: username,
                profileImageUrl: receivedRequest?.profileImageUrl,
              ),
            ),
          ),
    );
  }

  // 🎯 고급스러운 멤버 액션 메뉴 (롱프레스)
  static void showMemberActionMenu(
    BuildContext context,
    String username,
    String? profileImageUrl,
    Group? selectedGroup,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return MemberActionMenuOverlay(
          username: username,
          profileImageUrl: profileImageUrl,
          selectedGroup: selectedGroup,
          animation: animation,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final bool blur = data.state != FriendState.accepted;
    final groupProv = context.watch<GroupProvider>();
    // 🎯 시스템 그룹이 아닌 첫 번째 그룹 선택
    final selectedGroup =
        groupProv.myGroups.where((g) => g.isSystem != true).firstOrNull;

    Widget avatar = GestureDetector(
      onTap: () {
        // 🎯 다중 선택 모드일 때는 선택/해제만
        if (isMultiSelectMode) {
          onToggle();
          return;
        }

        if (data.state == FriendState.requestReceived) {
          // 받은 요청인 경우 수락/거절 바텀시트 표시
          showFriendRequestBottomSheet(context, data.username);
        } else {
          // 수락된 친구인 경우 프로필 화면으로 이동
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => UserProfileScreen(
                    otherUser: User(username: data.username),
                  ),
            ),
          );
        }
      },
      onLongPress:
          data.state == FriendState.accepted
              ? () {
                // 🎯 롱프레스 시 고급스러운 액션 메뉴
                showMemberActionMenu(
                  context,
                  data.username,
                  data.url,
                  selectedGroup,
                );
              }
              : null,
      child: Stack(
        children: [
          CommonProfileAvatar(
            imageUrl: data.url,
            username: data.username,
            size: 110,
            borderColor: Theme.of(
              context,
            ).colorScheme.onSurface.withOpacity(0.1),
            borderWidth: 0.5,
          ),
          // 🎯 다중 선택 모드일 때 체크 표시
          if (isMultiSelectMode)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected
                          ? Colors.white.withOpacity(0.7)
                          : Colors.transparent,
                ),
                child:
                    isSelected
                        ? Center(
                          child: Container(
                            width: 36,
                            height: 36,

                            child: Icon(
                              Icons.check,
                              color: Colors.black,
                              size: 40,
                            ),
                          ),
                        )
                        : null,
              ),
            ),
        ],
      ),
    );

    if (blur) {
      avatar = Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                data.state == FriendState.requestReceived
                    ? Theme.of(context).colorScheme.primary
                    : Colors.pink.withOpacity(0.8),
            width: data.state == FriendState.requestReceived ? 3.5 : 2,
          ),
        ),
        child: ClipOval(
          child: Stack(alignment: Alignment.center, children: [avatar]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatar,
        const SizedBox(height: 6),
        // 🎯 텍스트가 잘리지 않도록 SizedBox로 최소 높이 보장
        SizedBox(
          width: double.infinity,
          height: 18, // 최소 높이 보장
          child: Center(
            child: Text(
              "@" + data.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (data.alias != null && data.alias!.isNotEmpty) ...[
          const SizedBox(height: 2),
          // 🎯 텍스트가 잘리지 않도록 SizedBox로 최소 높이 보장
          SizedBox(
            width: double.infinity,
            height: 16, // 최소 높이 보장
            child: Center(
              child: Text(
                data.alias!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
