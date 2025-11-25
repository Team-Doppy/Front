import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/group_sheet.dart';
import 'package:doppy/pages/components/friend_requests_list_bottom_sheet.dart';
import 'package:doppy/pages/components/sent_requests_list_bottom_sheet.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// 그룹 선택 화면 (디스크 형태 가로 스크롤)
class GroupSelectionScreen extends StatefulWidget {
  const GroupSelectionScreen({Key? key}) : super(key: key);

  @override
  State<GroupSelectionScreen> createState() => _GroupSelectionScreenState();
}

class _GroupSelectionScreenState extends State<GroupSelectionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _loadingAnimationController;
  final GroupDropDown _groupDropDown = GroupDropDown();
  late final PageController _pageController;
  int _currentGroupIndex = 0;
  double _headerOpacity = 1.0; // 🎯 헤더 투명도 추적
  double _iconOpacity = 1.0; // 🎯 아이콘 투명도 (스크롤만, 새로고침 시 영향 없음)
  bool _isDragMode = false; // 🎯 드래그 모드 (롱프레스 중)
  bool _isReordering = false; // 🎯 reorder 진행 중인지 여부 (낙관적 업데이트 보호용)
  List<Group> _groups = []; // 🎯 reorder를 위한 그룹 리스트
  Timer? _autoScrollTimer; // 🎯 자동 스크롤 타이머
  Offset? _dragPosition; // 🎯 드래그 중인 위치
  int? _dragTargetIndex; // 🎯 드래그 중 드롭 타겟 인덱스 (시각적 표시용)
  bool _isRefreshing = false; // 🎯 새로고침 중인지 여부
  double _swipeOffset = 0.0; // 🎯 가로 스와이프 오프셋
  double _swipeStartX = 0.0; // 🎯 스와이프 시작 X 위치

  @override
  void initState() {
    super.initState();

    // PageController 초기화
    _pageController = PageController(
      viewportFraction: 0.45, // 앞뒤 그룹이 보이도록 (현재 60%, 앞뒤 각 20%3
    );

    // 로딩 애니메이션 컨트롤러 초기화
    _loadingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // 그룹 데이터는 이미 SplashScreen에서 로드되었으므로 여기서 다시 호출하지 않음

    // 🎯 PageController 리스너 추가 (스크롤 진행률 감지)
    _pageController.addListener(_onPageScroll);

    // 🎯 화면 진입 시 친구 요청 데이터 새로 조회 (캐시 무시)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final friendProvider = context.read<FriendProvider>();
      final groupProvider = context.read<GroupProvider>();

      // 🎯 친구 요청 데이터 새로 조회
      await friendProvider.fetchAllFriendData(forceRefresh: true);

      // 🎯 그룹 데이터 확인 및 보장
      if (!mounted) return;
      final groups = groupProvider.myGroups;

      // 🎯 전체 그룹(allFriends)이 없으면 새로 로드
      final hasAllFriendsGroup = groups.any((g) => g.isSystem == true);

      // 🎯 데이터가 없거나 전체 그룹이 없으면 새로 로드
      if (groups.isEmpty || !hasAllFriendsGroup) {
        await groupProvider.fetchMyGroups(
          forceRefresh: true,
          friendProvider: friendProvider,
        );
      }

      // 🎯 전체 친구 그룹의 memberCount 동기화 (FriendProvider의 최신 친구 수로)
      // 🎯 누락된 친구가 포함된 커스텀 그룹들의 멤버 수도 함께 동기화
      if (hasAllFriendsGroup && !mounted) return;
      if (hasAllFriendsGroup) {
        final actualFriendCount = friendProvider.acceptedFriends.length;

        // 🎯 FriendProvider의 친구 수로 동기화 (커스텀 그룹 동기화 포함)
        groupProvider.syncAllFriendsMemberCount(
          actualFriendCount,
          friendProvider: friendProvider,
        );
      }
    });
  }

  // 🎯 페이지 스크롤 리스너
  void _onPageScroll() {
    if (!_pageController.hasClients) return;

    final page = _pageController.page ?? 0;

    // 🎯 페이드 시작 지점과 범위 (아주 조금만 내려도 바로 페이드 시작)
    const double fadeStart = 0.000; // 2% 스크롤만 해도 페이드 시작
    const double fadeEnd = 0.05; // 완전히 사라지는 지점

    if (page <= fadeStart) {
      if (_headerOpacity != 1.0 || _iconOpacity != 1.0) {
        setState(() {
          _headerOpacity = 1.0;
          _iconOpacity = 1.0;
        });
      }
    } else if (page < fadeEnd) {
      final progress = ((page - fadeStart) / (fadeEnd - fadeStart)).clamp(
        0.0,
        1.0,
      );
      final opacity = 1.0 - progress;
      setState(() {
        _headerOpacity = opacity;
        _iconOpacity = opacity;
      });
    } else if (_headerOpacity > 0.0 || _iconOpacity > 0.0) {
      setState(() {
        _headerOpacity = 0.0;
        _iconOpacity = 0.0;
      });
    }

    // 다시 첫 페이지로 돌아올 때
    if (page >= 0.0 &&
        page < fadeStart &&
        (_headerOpacity < 1.0 || _iconOpacity < 1.0)) {
      setState(() {
        _headerOpacity = 1.0;
        _iconOpacity = 1.0; // 🎯 아이콘도 다시 나타남
      });
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _loadingAnimationController.stop();
    _loadingAnimationController.dispose();
    _groupDropDown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      resizeToAvoidBottomInset: false,

      body: SafeArea(
        child: GestureDetector(
          // 🎯 가로 스와이프로 닫기 기능
          onHorizontalDragStart: (details) {
            _swipeStartX = details.globalPosition.dx;
            _swipeOffset = 0.0;
          },
          onHorizontalDragUpdate: (details) {
            // 오른쪽으로 스와이프만 감지 (닫기)
            if (details.delta.dx > 0) {
              setState(() {
                _swipeOffset = details.globalPosition.dx - _swipeStartX;
              });
            }
          },
          onHorizontalDragEnd: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            final dragDistance = _swipeOffset;
            final velocity = details.primaryVelocity ?? 0;

            // 🎯 스와이프 거리가 화면의 30% 이상이거나 빠른 속도로 스와이프하면 닫기
            if (dragDistance > screenWidth * 0.3 || velocity > 500) {
              Navigator.of(context).pop();
            } else {
              // 원래 위치로 복귀
              setState(() {
                _swipeOffset = 0.0;
                _swipeStartX = 0.0;
              });
            }
          },
          child: Stack(
            children: [
              Consumer<GroupProvider>(
                builder: (context, groupProv, child) {
                  List<Group> groups = groupProv.myGroups;

                  // 🎯 전체 그룹(allFriends) 보장 - 없으면 새로 로드
                  final hasAllFriendsGroup = groups.any(
                    (g) => g.isSystem == true,
                  );
                  if (!groupProv.isLoading &&
                      (groups.isEmpty || !hasAllFriendsGroup)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (!mounted) return;
                      final friendProvider = context.read<FriendProvider>();
                      debugPrint('🔄 [GroupSelectionScreen] 전체 그룹 보장 - 새로 로드');
                      await groupProv.fetchMyGroups(
                        forceRefresh: true,
                        friendProvider: friendProvider,
                      );
                    });
                  }

                  // 🎯 서버에서 받은 순서 유지 (정렬 제거)
                  // displayOrder가 있다면 그 순서로 정렬, 없으면 createdAt 순서 유지
                  // groups는 이미 서버에서 displayOrder 순서로 정렬되어 옴

                  // 🎯 _groups 업데이트 (reorder를 위해) - 드래그 중이거나 reorder 중에는 업데이트 금지
                  if (!_isDragMode && !_isReordering) {
                    // 그룹 수나 ID가 다르면 업데이트
                    final needsUpdate =
                        _groups.length != groups.length ||
                        !_groups.every(
                          (g) => groups.any((g2) => g2.id == g.id),
                        ) ||
                        _groups.asMap().entries.any((entry) {
                          final index = entry.key;
                          final group = entry.value;
                          if (index >= groups.length) return true;
                          final updatedGroup = groups[index];
                          return updatedGroup.id != group.id ||
                              updatedGroup.name != group.name ||
                              updatedGroup.memberCount != group.memberCount ||
                              updatedGroup.postCount != group.postCount ||
                              updatedGroup.profileImageUrl !=
                                  group.profileImageUrl ||
                              updatedGroup.description != group.description;
                        });

                    if (needsUpdate) {
                      // 🎯 빌드 중에는 setState 호출 불가하므로 PostFrameCallback 사용
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_isDragMode && !_isReordering) {
                          setState(() {
                            _groups = List<Group>.from(groups);
                            // ❌ _currentGroupIndex 직접 변경 금지 - PageView가 onPageChanged로 변경하도록 맡김
                          });

                          // PageView index 재동기화 (범위 체크)
                          if (_pageController.hasClients &&
                              _groups.isNotEmpty) {
                            if (_currentGroupIndex >= _groups.length) {
                              // 인덱스가 범위를 벗어났을 때만 이동
                              final targetIndex = (_groups.length - 1).clamp(
                                0,
                                _groups.length - 1,
                              );
                              _pageController.animateToPage(
                                targetIndex,
                                duration: const Duration(milliseconds: 1),
                                curve: Curves.linear,
                              );
                            }
                          }
                        }
                      });
                    }
                  }

                  return _buildGroupSelectionContent(groups);
                },
              ),
              Positioned(top: 6, left: 0, right: 0, child: _buildAppBar()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Consumer<FriendProvider>(
      builder: (context, friendProvider, child) {
        final receivedCount = friendProvider.receivedRequests.length;
        final sentCount = friendProvider.sentRequests.length;

        return Row(
          children: [
            SizedBox(width: 5),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_new_rounded),
            ),
            Spacer(),

            // 받은 친구요청 아이콘 - 스크롤에만 반응 (새로고침 시 영향 없음)
            Opacity(
              opacity: _iconOpacity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () {
                      FriendRequestsListBottomSheet.show(context);
                    },
                    icon: Padding(
                      padding: const EdgeInsets.only(top: 0.0),
                      child: Icon(
                        Icons.person_add_alt_1,
                        size: 26,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    tooltip: context.tr('received_requests'),
                  ),
                  if (receivedCount > 0)
                    Positioned(
                      right: 7,
                      top: 9,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          receivedCount > 99 ? '99+' : '$receivedCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 보낸 친구요청 아이콘 - 스크롤에만 반응 (새로고침 시 영향 없음)
            Opacity(
              opacity: _iconOpacity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () {
                      SentRequestsListBottomSheet.show(context);
                    },
                    icon: Icon(Icons.send_rounded, size: 24.5),
                    tooltip: context.tr('sent_requests'),
                  ),
                  if (sentCount > 0)
                    Positioned(
                      right: 7,
                      top: 9,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          sentCount > 99 ? '99+' : '$sentCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            IconButton(
              onPressed: () {
                _groupDropDown.showGroupDropdown(
                  context,
                  GlobalKey(),
                  [],
                  null,
                  (group) {},
                  _createNewGroup,
                  startWithCreate: true, // 그룹 생성 UI 바로 표시
                );
              },
              icon: Icon(Icons.add, size: 30),
            ),
            SizedBox(width: 15),
          ],
        );
      },
    );
  }

  /// 리프레시 처리
  Future<void> _handleRefresh() async {
    try {
      final groupProvider = context.read<GroupProvider>();
      final friendProvider = context.read<FriendProvider>();

      // 🎯 친구 요청 데이터를 먼저 새로고침 (allFriends 그룹의 친구 수 반영을 위해)
      await friendProvider.fetchAllFriendData(forceRefresh: true);

      // 그룹 데이터 새로고침 (friendProvider 전달)
      await groupProvider.fetchMyGroups(
        forceRefresh: true,
        friendProvider: friendProvider,
      );

      // 🎯 전체 친구 그룹의 memberCount 동기화 (FriendProvider의 최신 친구 수로)
      // 🎯 누락된 친구가 포함된 커스텀 그룹들의 멤버 수도 함께 동기화
      if (!mounted) return;
      final groups = groupProvider.myGroups;
      final hasAllFriendsGroup = groups.any((g) => g.isSystem == true);
      if (hasAllFriendsGroup) {
        final actualFriendCount = friendProvider.acceptedFriends.length;
        groupProvider.syncAllFriendsMemberCount(
          actualFriendCount,
          friendProvider: friendProvider,
        );
      }
    } catch (e) {
      debugPrint('❌ [GroupSelectionScreen] 리프레시 에러: $e');
    } finally {
      // 🎯 새로고침 완료 후 약간의 딜레이 후 텍스트 복원
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          // 🎯 첫 페이지에 있으면 "내 그룹" 텍스트 다시 보이기
          if (_currentGroupIndex == 0) {
            _headerOpacity = 1.0;
          }
        });
      }
    }
  }

  /// 🎯 당기는 진행률 업데이트 (스피너 표시 감지용)
  void _onPullProgress(double progress) {
    // 🎯 텍스트를 먼저 숨기고, 그 다음에 스피너 표시
    final shouldStartHiding = progress >= 0.0; // 텍스트 숨기기 시작 (0부터)
    final shouldShowSpinner = progress >= 0.5; // 스피너 표시

    setState(() {
      if (shouldStartHiding) {
        // 🎯 텍스트를 먼저 부드럽게 숨기기 (progress 0.0 ~ 0.15에서 완전히 사라짐)
        final hideProgress = (progress / 0.15).clamp(0.0, 1.0);
        _headerOpacity = 1.0 - hideProgress;
      } else {
        // 다시 내려갔으면 텍스트 다시 보이기
        if (_currentGroupIndex == 0) {
          _headerOpacity = 1.0;
        }
      }

      if (shouldShowSpinner) {
        // 🎯 텍스트가 거의 사라진 후 스피너 표시
        _isRefreshing = true;
        _headerOpacity = 0.0; // 완전히 숨김
      } else if (progress < 0.5) {
        // 다시 내려갔고 충분히 낮아졌으면 (실제 새로고침하지 않았을 때) 스피너 숨기기
        _isRefreshing = false;
        if (_currentGroupIndex == 0 && progress < 0.0) {
          _headerOpacity = 1.0; // 🎯 첫 페이지에 있고 충분히 낮아졌으면 다시 보이기
        }
      }
    });
  }

  /// 그룹 선택 메인 컨텐츠
  Widget _buildGroupSelectionContent(List<Group> groups) {
    return Stack(
      children: [
        // 세로 스크롤 그룹 디스크 (PageView로 스냅 효과) - CustomRefreshIndicator로 감싸기
        CustomRefreshIndicator(
          top: 120,
          onRefresh: _handleRefresh,
          onPullProgress: _onPullProgress, // 🎯 당기는 진행률 콜백 추가
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const PageScrollPhysics(), // 🎯 스크롤은 항상 활성화
            itemCount:
                _isDragMode
                    ? _groups
                        .length // 🎯 드래그 중에는 itemCount 고정 (생성 버튼 제외)
                    : (_groups.length <= 1
                        ? _groups.length +
                            1 // 🎯 그룹이 1개 이하면 생성 버튼 포함
                        : _groups.length), // 🎯 그룹이 2개 이상이면 생성 버튼 제외
            onPageChanged: (index) {
              // 🎯 PageController의 실제 페이지를 단일 source of truth로 사용
              // 항상 index 업데이트 (dragMode와 무관하게)
              setState(() {
                _currentGroupIndex = index;
              });
            },
            itemBuilder: (context, index) {
              // 🎯 그룹이 1개 이하일 때만 마지막 아이템에 그룹 생성 버튼 표시
              if (_groups.length <= 1 && index == _groups.length) {
                return _buildCreateGroupDisc();
              }

              // 🎯 인덱스 범위 체크
              if (index < 0 || index >= _groups.length) {
                return const SizedBox.shrink();
              }

              final group = _groups[index];

              // 🎯 LongPressDraggable + DragTarget으로 reorder 구현
              return _buildDraggableGroupDisc(group, index);
            },
          ),
        ),

        // 🎯 스크롤 시 사라지는 상단 헤더 텍스트 (새로고침 중에는 숨김)
        if (!_isRefreshing)
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: _headerOpacity,
                child: Column(
                  children: [
                    Text(
                      context.tr('my_groups'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('scroll_to_explore'),
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 🎯 우측 인덱스 (가로 라인) - 독립적으로 터치 인식
        Positioned(
          bottom: 10,
          right: 16,
          child: _buildGroupIndexIndicator(groups),
        ),
      ],
    );
  }

  // 그룹 인덱스 인디케이터 (가로 라인) - 클릭/드래그 가능
  Widget _buildGroupIndexIndicator(List<Group> groups) {
    // 🎯 그룹이 1개 이하면 생성 버튼 포함, 아니면 그룹만
    final totalItems =
        _groups.length <= 1 ? _groups.length + 1 : _groups.length;

    return GestureDetector(
      // 🎯 세로 드래그로 페이지 이동
      onVerticalDragUpdate: (details) {
        // 드래그 위치를 페이지 인덱스로 변환
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);

        // 인디케이터의 높이 계산 (각 라인 높이 6 + 마진 4 = 10)
        final indicatorHeight = totalItems * 10.0;
        final relativeY = localPosition.dy.clamp(0.0, indicatorHeight);
        final targetIndex = (relativeY / 10.0).floor().clamp(0, totalItems - 1);

        if (targetIndex != _currentGroupIndex && _pageController.hasClients) {
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      },
      // 🎯 탭으로 직접 페이지 이동
      onTapDown: (details) {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);

        // 탭 위치를 페이지 인덱스로 변환
        final indicatorHeight = totalItems * 10.0;
        final relativeY = localPosition.dy.clamp(0.0, indicatorHeight);
        final targetIndex = (relativeY / 10.0).floor().clamp(0, totalItems - 1);

        if (_pageController.hasClients) {
          _pageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(totalItems, (index) {
            final isCurrent =
                index == _currentGroupIndex.clamp(0, totalItems - 1);
            return Container(
              width: 12,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isCurrent
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// 자동 스크롤 시작 (위치 업데이트)
  void _startAutoScroll(Offset globalPosition) {
    if (!mounted) return;

    _dragPosition = globalPosition;

    // 🎯 글로벌 좌표 기준으로 화면 높이 계산
    // 글로벌 좌표는 화면 전체를 기준으로 하므로 0부터 시작
    final screenHeight = MediaQuery.of(context).size.height;
    final threshold = screenHeight * 0.15; // 화면 상단/하단 15% 영역

    // 자동 스크롤이 필요한 영역인지 확인 (글로벌 좌표 기준)
    final needsAutoScroll =
        _dragPosition!.dy < threshold ||
        _dragPosition!.dy > screenHeight - threshold;

    // 자동 스크롤이 필요 없으면 Timer 중지
    if (!needsAutoScroll) {
      _stopAutoScroll();
      return;
    }

    // Timer가 없으면 시작
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      if (!_isDragMode ||
          _dragPosition == null ||
          !_pageController.hasClients ||
          !mounted) {
        _stopAutoScroll();
        return;
      }

      // 🎯 글로벌 좌표 기준으로 화면 높이 계산
      final screenHeight = MediaQuery.of(context).size.height;
      final threshold = screenHeight * 0.15; // 화면 상단/하단 15% 영역

      // 현재 위치에 따라 방향 결정 (매번 체크, 글로벌 좌표 기준)
      int? targetIndex;
      final maxIndex = _groups.length - 1; // 마지막 인덱스 (생성 버튼 제외)

      // 화면 상단 근처 (글로벌 좌표 기준, 0부터 시작)
      if (_dragPosition!.dy < threshold && _currentGroupIndex > 0) {
        targetIndex = (_currentGroupIndex - 1).clamp(0, maxIndex);
      }
      // 화면 하단 근처 (글로벌 좌표 기준)
      else if (_dragPosition!.dy > screenHeight - threshold &&
          _currentGroupIndex < maxIndex) {
        targetIndex = (_currentGroupIndex + 1).clamp(0, maxIndex);
      }

      // 타겟 인덱스가 있고 현재와 다르면 스크롤
      if (targetIndex != null && targetIndex != _currentGroupIndex) {
        _pageController.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
        // ❌ _currentGroupIndex 직접 변경 금지 - PageView가 onPageChanged로 변경하도록 맡김
      } else if (targetIndex == null) {
        // 자동 스크롤이 더 이상 필요 없으면 중지
        _stopAutoScroll();
      }
    });
  }

  /// 자동 스크롤 중지
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _dragPosition = null;
  }

  /// 드래그 타겟 인덱스 업데이트 (시각적 표시용)
  void _updateDragTargetIndex(Offset globalPosition, int draggingIndex) {
    if (!mounted || !_pageController.hasClients) return;

    final screenHeight = MediaQuery.of(context).size.height;
    // 🎯 fractional page 의존 제거 - 정확한 인덱스 사용
    final currentIndex = _pageController.page?.round() ?? _currentGroupIndex;

    // 현재 페이지 기준으로 드롭 위치 계산
    // 화면 중앙 기준으로 위/아래 판단
    final screenCenter = screenHeight / 2;
    final relativeY = globalPosition.dy - screenCenter;

    int? targetIndex;
    if (relativeY < -50) {
      // 화면 위쪽: 현재 인덱스 앞에 삽입
      targetIndex = (currentIndex - 1).clamp(0, _groups.length - 1);
    } else if (relativeY > 50) {
      // 화면 아래쪽: 현재 인덱스 뒤에 삽입
      targetIndex = (currentIndex + 1).clamp(0, _groups.length - 1);
    } else {
      // 화면 중앙: 현재 인덱스
      targetIndex = currentIndex.clamp(0, _groups.length - 1);
    }

    // 드래그 중인 아이템 자체는 타겟에서 제외
    if (targetIndex != draggingIndex && targetIndex != _dragTargetIndex) {
      setState(() {
        _dragTargetIndex = targetIndex;
      });
    }
  }

  /// 그룹 reorder 함수 - 인덱스 꼬임 방지 및 서버 동기화
  Future<void> _reorderGroup(int from, int to) async {
    if (from == to) return;

    if (from >= _groups.length || to >= _groups.length) return;

    // 🎯 그룹이 2개 이상일 때만 reorder 가능
    if (_groups.length < 2) return;

    final groupProvider = context.read<GroupProvider>();

    // 1) 🎯 낙관적 업데이트: 로컬 상태 즉시 변경 (UI 즉시 반영)
    final originalGroups = List<Group>.from(_groups);
    final oldIndex = _currentGroupIndex;

    setState(() {
      _isReordering = true; // 🎯 reorder 시작 플래그 설정
      final item = _groups.removeAt(from);
      _groups.insert(to, item);
      // ❌ _currentGroupIndex 직접 변경 금지 - PageView가 onPageChanged로 변경하도록 맡김
    });

    // 2) 🎯 1ms animateToPage로 변경 (PageController.page 값이 정상 유지됨)
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        to,
        duration: const Duration(milliseconds: 1),
        curve: Curves.linear,
      );
    }

    // 3) 🎯 서버 요청 (단순 검증용, 성공해도 UI는 그대로 유지)
    try {
      // 🎯 서버에 전송할 순서 정보 생성 (시스템 그룹은 -1로 전송, 서버가 자동으로 처리)
      final reorderData =
          _groups
              .asMap()
              .entries
              .map(
                (entry) => {
                  'groupId': entry.value.isSystem == true ? -1 : entry.value.id,
                  'displayOrder': entry.key,
                },
              )
              .toList();

      final success = await groupProvider.reorderGroups(reorderData);

      if (!success) {
        // 🎯 서버 요청 실패 시에만 롤백
        if (mounted) {
          setState(() {
            _groups = originalGroups;
            // ❌ _currentGroupIndex 직접 변경 금지 - PageView가 onPageChanged로 변경하도록 맡김
            _isReordering = false; // 🎯 롤백 후 reorder 플래그 해제
          });

          if (_pageController.hasClients) {
            // 🎯 1ms animateToPage로 변경 (PageController.page 값이 정상 유지됨)
            _pageController.animateToPage(
              oldIndex,
              duration: const Duration(milliseconds: 1),
              curve: Curves.linear,
            );
          }

          // Provider에서 최신 데이터 다시 가져오기
          final friendProvider = context.read<FriendProvider>();
          await groupProvider.fetchMyGroups(
            forceRefresh: true,
            friendProvider: friendProvider,
          );
        }
        if (mounted) {
          ErrorHandler.showError(context, '그룹 순서 변경에 실패했습니다');
        }
        return;
      }

      // 🎯 성공 시: UI는 그대로 유지하고 Provider만 동기화 (조용히 업데이트)
      // UI를 다시 빌드하지 않음으로써 불안정한 움직임 방지
      final friendProvider = context.read<FriendProvider>();
      await groupProvider.fetchMyGroups(
        forceRefresh: true,
        friendProvider: friendProvider,
      );

      // 🎯 Provider 업데이트 후 reorder 플래그 해제 (Consumer 업데이트 허용)
      if (mounted) {
        setState(() {
          _isReordering = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupSelectionScreen] 그룹 순서 변경 에러: $e');
      // 🎯 에러 발생 시에만 롤백
      if (mounted) {
        setState(() {
          _groups = originalGroups;
          // ❌ _currentGroupIndex 직접 변경 금지 - PageView가 onPageChanged로 변경하도록 맡김
        });

        if (_pageController.hasClients) {
          // 🎯 1ms animateToPage로 변경 (PageController.page 값이 정상 유지됨)
          _pageController.animateToPage(
            oldIndex,
            duration: const Duration(milliseconds: 1),
            curve: Curves.linear,
          );
        }

        // Provider에서 최신 데이터 다시 가져오기
        final friendProvider = context.read<FriendProvider>();
        await groupProvider.fetchMyGroups(
          forceRefresh: true,
          friendProvider: friendProvider,
        );
      }

      // 🎯 롤백 후 reorder 플래그 해제
      if (mounted) {
        setState(() {
          _isReordering = false;
        });
      }

      if (mounted) {
        ErrorHandler.showError(context, '그룹 순서 변경에 실패했습니다: $e');
      }
      return;
    }
  }

  /// 드래그 가능한 그룹 디스크 (LongPressDraggable + DragTarget)
  Widget _buildDraggableGroupDisc(Group group, int groupIndex) {
    // 🎯 그룹이 2개 이상이면 reorder 가능
    final canReorder = _groups.length >= 2;

    if (!canReorder) {
      // reorder 불가능한 그룹은 일반 디스크로 표시
      return _buildGroupDisc(group, groupIndex);
    }

    return LongPressDraggable<int>(
      data: groupIndex,
      dragAnchorStrategy: (draggable, context, position) {
        // 🎯 왼쪽 위로 보정 (피드백 위치 조정)
        return Offset(100, 100);
      },
      onDragStarted: () {
        setState(() {
          _isDragMode = true;
        });
        // 햅틱 피드백
        HapticFeedback.mediumImpact();
      },
      onDragUpdate: (details) {
        // 🎯 드래그 위치 업데이트 및 자동 스크롤 시작
        _startAutoScroll(details.globalPosition);
        // 🎯 드롭 타겟 인덱스 업데이트 (시각적 표시용)
        _updateDragTargetIndex(details.globalPosition, groupIndex);
      },
      onDragEnd: (_) async {
        // 🎯 자동 스크롤 중지
        _stopAutoScroll();

        // 🎯 드롭 타겟 인덱스 초기화 (즉시)
        if (mounted) {
          setState(() {
            _dragTargetIndex = null;
          });
        }

        // 🎯 드래그 종료 시 페이지 이동은 _reorderGroup 내부에서 처리되므로 여기서는 제거

        if (!mounted) return;

        // 🎯 드래그 모드 종료 및 인덱스 재동기화
        setState(() {
          _isDragMode = false;
        });

        // 🎯 Provider 데이터와 동기화 확인
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final groupProvider = context.read<GroupProvider>();
          final updatedGroups = groupProvider.myGroups;

          // 그룹 수가 다르면 동기화 필요
          if (updatedGroups.length != _groups.length) {
            setState(() {
              _groups = List<Group>.from(updatedGroups);
              // ❌ _currentGroupIndex 직접 변경 금지 - PageView가 onPageChanged로 변경하도록 맡김
            });

            // PageView index 재동기화 (범위 체크)
            if (_pageController.hasClients && _groups.isNotEmpty) {
              if (_currentGroupIndex >= _groups.length) {
                final targetIndex = _groups.length > 0 ? _groups.length - 1 : 0;
                _pageController.animateToPage(
                  targetIndex,
                  duration: const Duration(milliseconds: 1),
                  curve: Curves.linear,
                );
              }
            }
          }
        });
      },
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 0.85,
          child: Opacity(
            opacity: 0.9,
            child: _buildGroupDisc(group, groupIndex),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.2,
        child: _buildGroupDisc(group, groupIndex),
      ),
      child: DragTarget<int>(
        onWillAccept: (from) {
          // 🎯 드래그 중이 아니거나, 그룹이 2개 미만이면 거부
          if (!_isDragMode || !canReorder) return false;
          if (_groups.length < 2) return false;
          if (from == null) return false;
          if (from < 0 || from >= _groups.length) return false;
          return from != groupIndex;
        },
        onAccept: (from) async {
          if (from < 0 || from >= _groups.length) return;
          if (!_isDragMode) return;
          await _reorderGroup(from, groupIndex);
        },
        onMove: (details) {
          // 드래그가 이 타겟 위로 이동했을 때
          if (details.data != groupIndex) {
            setState(() {
              _dragTargetIndex = groupIndex;
            });
          }
        },
        onLeave: (data) {
          // 드래그가 이 타겟을 벗어났을 때
          setState(() {
            _dragTargetIndex = null;
          });
        },
        builder: (context, candidateData, rejectedData) {
          // 🎯 드롭 타겟 인덱스에 따라 padding만 추가 (height는 절대 변경하지 않음)
          final isDropTarget =
              _dragTargetIndex == groupIndex && candidateData.isNotEmpty;
          final isFirstGroup = groupIndex == 0;

          final screenHeight = MediaQuery.of(context).size.height;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(
              top: isDropTarget && isFirstGroup ? 44.0 : 0.0,
              bottom: isDropTarget && !isFirstGroup ? 44.0 : 0.0,
            ),
            child: SizedBox(
              height: screenHeight, // 절대 변화하지 않음
              child: _buildGroupDisc(group, groupIndex),
            ),
          );
        },
      ),
    );
  }

  /// 그룹 디스크 아이템
  Widget _buildGroupDisc(Group group, int groupIndex) {
    return GestureDetector(
      onTap: () {
        // 🎯 드래그 모드 중이거나 인덱스가 범위를 벗어나면 탭 무시
        if (_isDragMode) return;
        if (groupIndex < 0 || groupIndex >= _groups.length) return;
        if (_groups[groupIndex].id != group.id) {
          // 인덱스와 그룹 ID가 맞지 않으면 무시
          debugPrint(
            '⚠️ [GroupSelectionScreen] 인덱스 불일치: index=$groupIndex, groupId=${group.id}',
          );
          return;
        }

        // 🎯 빠른 페이드 전환
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    ManageGroupScreen(selectedGroup: group),
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 150),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 디스크 형태의 그룹 아바타
            AnimatedScale(
              scale: groupIndex == _currentGroupIndex ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // 🎯 Hero 애니메이션으로 감싸기
                    Hero(
                      tag: 'group-${group.id}',
                      child: RepaintBoundary(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: ClipOval(
                            child:
                                group.profileImageUrl != null &&
                                        group.profileImageUrl!.isNotEmpty &&
                                        (group.profileImageUrl!.startsWith(
                                              'http://',
                                            ) ||
                                            group.profileImageUrl!.startsWith(
                                              'https://',
                                            ))
                                    ? CachedNetworkImage(
                                      key: ValueKey('group-image-${group.id}'),
                                      imageUrl: group.profileImageUrl!,
                                      fit: BoxFit.cover,
                                      width: 200,
                                      height: 200,
                                      fadeInDuration: const Duration(
                                        milliseconds: 0,
                                      ), // 🎯 즉시 표시 (캐시된 이미지)
                                      fadeOutDuration: const Duration(
                                        milliseconds: 0,
                                      ), // 🎯 즉시 사라짐
                                      memCacheWidth: 400, // 🎯 메모리 캐시 크기 지정
                                      maxWidthDiskCache: 400, // 🎯 디스크 캐시 크기 지정
                                      placeholder:
                                          (context, url) => Container(
                                            width: 200,
                                            height: 200,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                            child: Center(),
                                          ),
                                      errorWidget: (context, url, error) {
                                        // 네트워크 이미지 로드 실패 시 플레이스홀더 표시
                                        return Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                GroupColorPalette.getColor(
                                                  group.id,
                                                ).withOpacity(0.55),
                                                GroupColorPalette.getColor(
                                                  group.id,
                                                ),
                                                GroupColorPalette.getColor(
                                                  group.id,
                                                ).withOpacity(0.95),
                                              ],
                                              stops: const [0.0, 0.5, 1.0],
                                            ),
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                center: Alignment(-0.4, -0.4),
                                                radius: 1.0,
                                                colors: [
                                                  Colors.white.withOpacity(
                                                    0.12,
                                                  ),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                    : Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            // 🎯 절제된 그라디언트
                                            GroupColorPalette.getColor(
                                              group.id,
                                            ).withOpacity(0.55),
                                            GroupColorPalette.getColor(
                                              group.id,
                                            ),
                                            GroupColorPalette.getColor(
                                              group.id,
                                            ).withOpacity(0.95),
                                          ],
                                          stops: const [0.0, 0.5, 1.0],
                                        ),
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            center: Alignment(-0.4, -0.4),
                                            radius: 1.0,
                                            colors: [
                                              Colors.white.withOpacity(0.12),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                          ),
                        ),
                      ),
                    ),

                    // 🎯 중앙에 멤버 수 · 포스트 수 표시 (모든 그룹에 동일하게 적용)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${group.memberCount ?? 0}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (group.postCount != null &&
                              (group.postCount ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${group.postCount} ${context.tr('post')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // 재생 버튼 (오른쪽)
                    if (group.id != -1)
                      Positioned(
                        right: 10,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.arrow_forward_ios,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 그룹 이름 (로케일 적용)
            Text(
              _getGroupDisplayName(context, group),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            // 그룹 설명
            Text(
              group.description,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 그룹 생성 디스크
  Widget _buildCreateGroupDisc() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              // 🎯 그룹 생성 UI로 바로 시작
              _groupDropDown.showGroupDropdown(
                context,
                GlobalKey(),
                [],
                null,
                (group) {},
                _createNewGroup,
                startWithCreate: true, // 그룹 생성 UI 바로 표시
              );
            },
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.2),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('create_new_group'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 그룹 생성
  Future<void> _createNewGroup(
    String groupName,
    String? description,
    String? imageUrl,
  ) async {
    // 🎯 description 추가
    if (groupName.trim().isEmpty) return;

    try {
      final groupProvider = context.read<GroupProvider>();

      // 🎯 description과 imageUrl 전달
      final success = await groupProvider.createGroup(
        groupName.trim(),
        description: description,
        profileImageUrl: imageUrl,
      );

      if (success) {
        // 그룹 목록 새로고침
        final friendProvider = context.read<FriendProvider>();
        await groupProvider.fetchMyGroups(friendProvider: friendProvider);

        // 🎯 새로 생성된 그룹으로 이동
        // 시스템 그룹 개수를 계산하여 새 그룹 위치 결정
        if (mounted && _pageController.hasClients) {
          await Future.delayed(const Duration(milliseconds: 100)); // UI 업데이트 대기
          final systemGroupCount =
              _groups.where((g) => g.isSystem == true).length;
          _pageController.animateToPage(
            systemGroupCount, // 새로 생성된 그룹 위치 (시스템 그룹 다음)
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }

        // 성공 메시지
        if (mounted) {
          ErrorHandler.showInfo(context, context.tr('group_created'));
        }
      } else {
        // 그룹 생성 실패
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('group_creation_failed')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('error_occurred').replaceAll('{error}', '$e'),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// 🎯 그룹 표시 이름 가져오기 (로케일 적용)
  /// allFriends 그룹은 "전체 친구" / "All Friends"로 표시
  String _getGroupDisplayName(BuildContext context, Group group) {
    // 🎯 시스템 그룹인 경우 로케일 적용
    if (group.isSystem == true) {
      return context.tr('all_friends');
    }
    return group.name;
  }
}
