import 'dart:async';

import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/group_sheet.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/providers/group_provider.dart';
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
  bool _isDragMode = false; // 🎯 드래그 모드 (롱프레스 중)
  List<Group> _groups = []; // 🎯 reorder를 위한 그룹 리스트
  Timer? _autoScrollTimer; // 🎯 자동 스크롤 타이머
  Offset? _dragPosition; // 🎯 드래그 중인 위치
  int? _dragTargetIndex; // 🎯 드래그 중 드롭 타겟 인덱스 (시각적 표시용)
  int? _draggingGroupIndex; // 🎯 현재 드래그 중인 그룹의 원래 인덱스

  // 멤버 썸네일 애니메이션 컨트롤러
  late final AnimationController _memberAnimationController;
  late final Animation<double> _memberAnimation;

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

    // 멤버 썸네일 애니메이션 컨트롤러 초기화
    _memberAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _memberAnimation = CurvedAnimation(
      parent: _memberAnimationController,
      curve: Curves.easeOutBack,
    );

    // 첫 페이지 애니메이션 시작
    // 그룹 데이터는 이미 SplashScreen에서 로드되었으므로 여기서 다시 호출하지 않음
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _memberAnimationController.forward();
    });

    // 🎯 PageController 리스너 추가 (스크롤 진행률 감지)
    _pageController.addListener(_onPageScroll);
  }

  // 🎯 페이지 스크롤 리스너
  void _onPageScroll() {
    if (!_pageController.hasClients) return;

    final page = _pageController.page ?? 0;

    // 첫 페이지에서 조금만 스크롤해도 빠르게 사라지도록
    // 0.15 이상 스크롤되면 사라짐 시작 (15% 스크롤)
    if (page < 0.15) {
      setState(() {
        _headerOpacity = 1.0 - (page / 0.15);
      });
    } else if (_headerOpacity > 0.0) {
      setState(() {
        _headerOpacity = 0.0;
      });
    }

    // 다시 첫 페이지로 돌아올 때
    if (page >= 0.0 && page < 0.01 && _headerOpacity < 1.0) {
      setState(() {
        _headerOpacity = 1.0;
      });
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _memberAnimationController.dispose();
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
        child: Stack(
          children: [
            Consumer<GroupProvider>(
              builder: (context, groupProv, child) {
                List<Group> groups = groupProv.myGroups;

                // 최신순 정렬 (createdAt 기준 내림차순)
                groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                // 🎯 _groups 업데이트 (reorder를 위해) - 드래그 중에는 업데이트 금지
                if (!_isDragMode &&
                    (_groups.length != groups.length ||
                        !_groups.every(
                          (g) => groups.any((g2) => g2.id == g.id),
                        ))) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_isDragMode) {
                      setState(() {
                        _groups = List.from(groups);
                      });
                    }
                  });
                }

                return _buildGroupSelectionContent(groups);
              },
            ),
            Positioned(top: 6, left: 0, right: 0, child: _buildAppBar()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Row(
      children: [
        SizedBox(width: 5),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_new_rounded),
        ),
        Spacer(),

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
  }

  /// 그룹 선택 메인 컨텐츠
  Widget _buildGroupSelectionContent(List<Group> groups) {
    return Stack(
      children: [
        // 세로 스크롤 그룹 디스크 (PageView로 스냅 효과)
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          physics:
              _groups.length <= 1
                  ? const NeverScrollableScrollPhysics() // 🎯 그룹이 1개 이하면 스크롤 비활성화
                  : const PageScrollPhysics(), // 🎯 드래그 중에도 자동 스크롤을 위해 스크롤 활성화
          itemCount:
              _isDragMode
                  ? _groups
                      .length // 🎯 드래그 중에는 itemCount 고정 (생성 버튼 제외)
                  : (_groups.length <= 1
                      ? _groups.length +
                          1 // 🎯 그룹이 1개 이하면 생성 버튼 포함
                      : _groups.length), // 🎯 그룹이 2개 이상이면 생성 버튼 제외
          onPageChanged: (index) {
            if (!_isDragMode) {
              // 드래그 모드가 아닐 때만 페이지 변경 처리
              setState(() {
                _currentGroupIndex = index;
              });
              // 페이지 변경 시 멤버 썸네일 애니메이션
              _memberAnimationController.reset();
              _memberAnimationController.forward();
            }
            // 🎯 드래그 중에는 페이지 변경 무시 (이웃 디스크가 원래 위치로 이동하는 것 방지)
          },
          itemBuilder: (context, index) {
            // 🎯 그룹이 1개 이하일 때만 마지막 아이템에 그룹 생성 버튼 표시
            if (_groups.length <= 1 && index == _groups.length) {
              return _buildCreateGroupDisc();
            }

            final group = _groups[index];

            // 🎯 LongPressDraggable + DragTarget으로 reorder 구현
            return _buildDraggableGroupDisc(group, index);
          },
        ),

        // 🎯 스크롤 시 사라지는 상단 헤더 텍스트
        Positioned(
          top: 70,
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
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
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
    if (_autoScrollTimer == null) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 200), (
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
          setState(() {
            _currentGroupIndex = targetIndex!;
          });
        } else if (targetIndex == null) {
          // 자동 스크롤이 더 이상 필요 없으면 중지
          _stopAutoScroll();
        }
      });
    }
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

  /// 그룹 reorder 함수 - 인덱스 꼬임 방지
  void _reorderGroup(int from, int to) {
    if (from == to) return;

    // 1) 리스트 순서 변경
    setState(() {
      final item = _groups.removeAt(from);
      _groups.insert(to, item);
      _currentGroupIndex = to; // 인덱스 보정
    });

    // 2) 다음 위젯 프레임에서 PageView index 즉시 동기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;

      // *** 핵심: PageController 내부 index를 맞춰서 index mismatch 제거 ***
      _pageController.jumpToPage(to);

      // 3) 다음 이벤트 루프(= UI 안정되는 시점)에 부드러운 스냅 애니메이션
      Future.microtask(() {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.animateToPage(
          to,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    });

    // 4) 멤버 썸네일 애니메이션 실행
    _memberAnimationController
      ..reset()
      ..forward();
  }

  /// 드래그 가능한 그룹 디스크 (LongPressDraggable + DragTarget)
  Widget _buildDraggableGroupDisc(Group group, int groupIndex) {
    // 시스템 그룹(isSystem = true)은 reorder 불가능
    final canReorder = group.isSystem != true;

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
          _draggingGroupIndex = groupIndex; // 🎯 드래그 시작 시 원래 인덱스 저장
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

        // 드래그 종료 후 현재 페이지로 스냅
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            _currentGroupIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }

        // 🎯 페이지 애니메이션 끝날 때까지 기다림 (드래그 모드 종료 지연)
        await Future.delayed(const Duration(milliseconds: 250));

        if (!mounted) return;

        setState(() {
          _isDragMode = false;
          _dragTargetIndex = null; // 드롭 타겟 인덱스 초기화
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
        onWillAccept: (from) => from != groupIndex && canReorder,
        onAccept: (from) {
          _reorderGroup(from, groupIndex);
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
        if (_isDragMode) return; // 드래그 모드 중에는 탭 무시

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
                                      group.profileImageUrl!.isNotEmpty
                                  ? Image.network(
                                    group.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    width: 200,
                                    height: 200,
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
                                          GroupColorPalette.getColor(group.id),
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

                    // 🎯 중앙에 멤버 수 표시 (시스템 그룹은 제외)
                    if (group.isSystem == true)
                      // 🐱 시스템 그룹(전체 친구): 고양이 이미지 표시
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/doppy_nobg.png',
                              width: 40,
                              height: 40,
                              color: Colors.white,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      )
                    else
                      // 일반 그룹: 멤버 수 표시
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            '${group.memberCount ?? 0}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                    // 멤버 프로필 썸네일 (우측 하단) - 현재 페이지일 때만 표시
                    if (groupIndex == _currentGroupIndex)
                      Positioned(
                        right: 10,
                        bottom: 0,
                        child: _buildMemberThumbnails(group),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 그룹 이름
            Text(
              group.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            // 그룹 설명
            Text(
              group.description,
              style: TextStyle(
                fontSize: 15,
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

  /// 이니셜 아바타 생성
  Widget _buildInitialAvatar(String username) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final colors = [
      const Color(0xFFFF6B6B), // 빨강
      const Color(0xFF4ECDC4), // 청록
      const Color(0xFFFFE66D), // 노랑
      const Color(0xFF95E1D3), // 민트
      const Color(0xFFF38181), // 핑크
    ];
    final colorIndex = username.hashCode.abs() % colors.length;

    return Container(
      color: colors[colorIndex],
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 멤버 프로필 썸네일 (겹쳐서 표시)
  Widget _buildMemberThumbnails(Group group) {
    // 🎯 서버에서 제공하는 memberThumbnails와 memberCount 사용
    final thumbnails = group.memberThumbnails ?? [];
    final totalMembers = group.memberCount ?? 0;

    if (totalMembers == 0) {
      return const SizedBox.shrink();
    }

    // 🎯 최대 3명까지 썸네일 표시, 나머지는 +N으로 표시
    final thumbnailsToShow = thumbnails.take(3).toList();
    final showPlusN = totalMembers > thumbnailsToShow.length;
    final remainingCount = totalMembers - thumbnailsToShow.length;

    // 표시할 아이템 개수 (썸네일 + +N)
    final displayCount = thumbnailsToShow.length + (showPlusN ? 1 : 0);

    // 🎯 실제 표시될 너비 계산 (멤버 수에 따라 동적 조정)
    final actualWidth = 40.0 + (displayCount - 1) * 24.0;

    return Container(
      // 🎯 1명일 때 왼쪽으로 이동하기 위한 마진
      margin: EdgeInsets.only(right: displayCount == 1 ? 15 : 0),
      child: SizedBox(
        width: actualWidth + 10,
        height: 40,
        child: Stack(
          children: List.generate(displayCount, (index) {
            // 🎯 마지막이 +N인 경우
            if (showPlusN && index == thumbnailsToShow.length) {
              return AnimatedBuilder(
                animation: _memberAnimation,
                builder: (context, child) {
                  final positionProgress = _memberAnimation.value;
                  final targetLeft = index * 24.0;

                  return Positioned(
                    left: targetLeft * positionProgress,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 15.0),
                          child: Text(
                            '+$remainingCount',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            // 일반 멤버 썸네일 (서버 데이터 사용)
            final thumbnailUrl = thumbnailsToShow[index];

            return AnimatedBuilder(
              animation: _memberAnimation,
              builder: (context, child) {
                // 위치는 동시에 이동
                final positionProgress = _memberAnimation.value;
                final targetLeft = index * 24.0; // 최종 위치

                return Positioned(
                  left: targetLeft * positionProgress, // 동시에 이동
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // 이미지 로드 실패 시 이니셜 표시
                          return _buildInitialAvatar('User${index + 1}');
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          }),
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
        await groupProvider.fetchMyGroups();

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
}
