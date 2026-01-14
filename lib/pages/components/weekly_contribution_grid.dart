import 'package:flutter/material.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:google_fonts/google_fonts.dart';

/// 주차별 기여도 데이터 모델 (하드코딩용, 나중에 서버 API로 대체)
class WeeklyContributionData {
  final int year;
  final int weekNumber;
  final bool hasPost;
  final int postCount; // 선택적: 해당 주의 글 개수

  const WeeklyContributionData({
    required this.year,
    required this.weekNumber,
    required this.hasPost,
    this.postCount = 0,
  });
}

/// 잔디 심기 스타일의 주차별 기여도 그리드 위젯
class WeeklyContributionGrid extends StatefulWidget {
  final int year;
  final int? selectedWeek;
  final Function(int year, int weekNumber)? onWeekSelected;
  final List<WeeklyContributionData>? contributions; // null이면 하드코딩 데이터 사용
  final bool isCompact; // 간단 모드 (작은 크기)
  final Function(
    int year,
    int weekNumber,
    Offset? position,
    Offset? cellCenter,
  )?
  onLongPress; // 길게 누르기 콜백 (위치 + 셀 중심 포함)

  const WeeklyContributionGrid({
    super.key,
    required this.year,
    this.selectedWeek,
    this.onWeekSelected,
    this.contributions,
    this.isCompact = false,
    this.onLongPress,
  });

  @override
  State<WeeklyContributionGrid> createState() => _WeeklyContributionGridState();
}

class _WeeklyContributionGridState extends State<WeeklyContributionGrid>
    with TickerProviderStateMixin {
  late final AnimationController _gridAnimationController;
  late final AnimationController _selectionAnimationController;
  late final Animation<double> _gridFadeAnimation;
  late final Animation<double> _selectionGlowAnimation;

  int? _hoveredWeek;
  int? _longPressedWeek; // 길게 누른 주차 추적
  int? _pendingTapWeek; // 탭 대기 중인 주차 (롱프레스와 구분하기 위해)

  @override
  void initState() {
    super.initState();

    // 그리드 페이드인 애니메이션
    _gridAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _gridFadeAnimation = CurvedAnimation(
      parent: _gridAnimationController,
      curve: Curves.easeOut,
    );

    // 선택 애니메이션
    _selectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _selectionGlowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _selectionAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // 그리드 애니메이션 시작
    _gridAnimationController.forward();

    // 선택된 주차가 있으면 애니메이션 시작
    if (widget.selectedWeek != null) {
      _selectionAnimationController.forward();
    }
  }

  @override
  void didUpdateWidget(WeeklyContributionGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedWeek != oldWidget.selectedWeek) {
      if (widget.selectedWeek != null) {
        _selectionAnimationController.forward();
      } else {
        _selectionAnimationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _gridAnimationController.dispose();
    _selectionAnimationController.dispose();
    super.dispose();
  }

  /// 기여도 데이터 가져오기 (외부에서 제공되면 사용, 없으면 빈 리스트 반환)
  List<WeeklyContributionData> _getContributions() {
    // 외부에서 contributions가 제공되면 사용
    if (widget.contributions != null && widget.contributions!.isNotEmpty) {
      return widget.contributions!;
    }

    // 없으면 빈 리스트 반환 (실제 데이터는 home_screen에서 생성)
    final totalWeeks = WeekUtils.getWeeksInYear(widget.year);
    return List.generate(
      totalWeeks,
      (index) => WeeklyContributionData(
        year: widget.year,
        weekNumber: index + 1,
        hasPost: false,
        postCount: 0,
      ),
    );
  }

  /// 활동도에 따른 색상 계산
  Color _getCellColor(WeeklyContributionData data, bool isSelected) {
    if (isSelected) {
      return Theme.of(context).colorScheme.primary;
    }

    // 연도 초반 주차 (1-12주차)에 색상 적용
    final isEarlyYear = data.weekNumber <= 12;

    if (!isEarlyYear) {
      // 연도 초반이 아닌 경우: 어두운 회색
      return Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFE5E5E5);
    }

    // 연도 초반: 주차 번호에 따라 primary 색상의 opacity 조절 (1주차가 가장 밝음)
    // 1주차부터 12주차까지 점진적으로 어두워짐
    final intensity = 1.0 - ((data.weekNumber - 1) / 12.0).clamp(0.0, 1.0);
    final primaryColor = Theme.of(context).colorScheme.primary;

    // primary 색상과 어두운 배경색을 lerp
    final darkColor =
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFE5E5E5);

    return Color.lerp(darkColor, primaryColor, intensity)!;
  }

  @override
  Widget build(BuildContext context) {
    final contributions = _getContributions();

    return FadeTransition(
      opacity: _gridFadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그리드
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildGrid(contributions),
          ),

          if (!widget.isCompact) const SizedBox(height: 12),

          // 하단: 선택된 주차 정보 (간단 모드일 때는 숨김)
          if (widget.selectedWeek != null && !widget.isCompact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSelectedWeekInfo(widget.selectedWeek!),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<WeeklyContributionData> contributions) {
    // 그리드를 7열로 배치 (주 7일)
    const columns = 7;
    final rows = (contributions.length / columns).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 간단 모드일 때 셀 크기와 간격 축소
        final cellSpacing = widget.isCompact ? 1.0 : 2.0;
        // 오버플로우 방지: 마지막 열의 right padding을 고려하여 계산
        final availableWidth = constraints.maxWidth;
        final totalSpacing = (columns - 1) * cellSpacing;
        final baseCellSize = (availableWidth - totalSpacing) / columns;
        final cellSize = widget.isCompact ? baseCellSize * 0.6 : baseCellSize;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(rows, (rowIndex) {
            return Padding(
              padding: EdgeInsets.only(bottom: cellSpacing),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(columns, (colIndex) {
                  final weekIndex = rowIndex * columns + colIndex;
                  if (weekIndex >= contributions.length) {
                    return SizedBox(width: cellSize);
                  }

                  final data = contributions[weekIndex];
                  final isSelected = widget.selectedWeek == data.weekNumber;
                  final isHovered = _hoveredWeek == data.weekNumber;

                  // 마지막 열은 right padding 제거하여 오버플로우 방지
                  final isLastColumn = colIndex == columns - 1;
                  return Padding(
                    key: ValueKey('week-${data.year}-${data.weekNumber}'),
                    padding: EdgeInsets.only(
                      right: isLastColumn ? 0 : cellSpacing,
                    ),
                    child: _buildCell(
                      data: data,
                      size: cellSize,
                      isSelected: isSelected,
                      isHovered: isHovered,
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildCell({
    required WeeklyContributionData data,
    required double size,
    required bool isSelected,
    required bool isHovered,
  }) {
    final cellColor = _getCellColor(data, isSelected);

    // 길게 누르기 상태 추적
    final isLongPressed = _longPressedWeek == data.weekNumber;

    // 셀 위치 추적을 위한 GlobalKey
    final cellKey = GlobalKey();

    return GestureDetector(
      onLongPressStart: (details) {
        // 롱프레스 시작: 탭 취소
        setState(() {
          _longPressedWeek = data.weekNumber;
          _pendingTapWeek = null; // 탭 취소
        });

        // 셀의 중심 위치 계산 (다음 프레임에서 실행하여 렌더링 완료 후 계산)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final RenderBox? renderBox =
              cellKey.currentContext?.findRenderObject() as RenderBox?;
          final cellCenter =
              renderBox != null
                  ? renderBox.localToGlobal(
                    Offset(renderBox.size.width / 2, renderBox.size.height / 2),
                  )
                  : details.globalPosition;

          widget.onLongPress?.call(
            data.year,
            data.weekNumber,
            details.globalPosition,
            cellCenter, // 셀의 중심 위치 전달
          );
        });
      },
      onLongPressMoveUpdate: (details) {
        // 손가락 움직임에 따라 위치만 업데이트 (셀 중심은 재계산하지 않음)
        widget.onLongPress?.call(
          data.year,
          data.weekNumber,
          details.globalPosition,
          null, // 셀 중심은 처음만 계산
        );
      },
      onLongPressEnd: (details) {
        // 길게 누르기 종료
        setState(() {
          _longPressedWeek = null;
        });
        widget.onLongPress?.call(data.year, 0, null, null); // 0은 종료를 의미
      },
      onLongPressCancel: () {
        // 길게 누르기 취소
        setState(() {
          _longPressedWeek = null;
        });
        widget.onLongPress?.call(data.year, 0, null, null);
      },
      onTapDown: (_) {
        debugPrint(
          '[WeeklyGrid] onTapDown: ${data.year}년 ${data.weekNumber}주차',
        );
        if (_hoveredWeek != data.weekNumber) {
          setState(() {
            _hoveredWeek = data.weekNumber;
          });
        }
        // 탭 대기 상태로 설정
        setState(() {
          _pendingTapWeek = data.weekNumber;
        });
        debugPrint(
          '[WeeklyGrid] _pendingTapWeek 설정: $_pendingTapWeek, _longPressedWeek: $_longPressedWeek',
        );
      },
      onTapUp: (_) {
        debugPrint(
          '[WeeklyGrid] onTapUp: ${data.year}년 ${data.weekNumber}주차, _pendingTapWeek=$_pendingTapWeek, _longPressedWeek=$_longPressedWeek',
        );
        // 탭이 완료되었고 롱프레스가 시작되지 않았으면 즉시 실행
        if (_pendingTapWeek == data.weekNumber &&
            _longPressedWeek != data.weekNumber) {
          debugPrint(
            '[WeeklyGrid] onWeekSelected 호출: ${data.year}년 ${data.weekNumber}주차',
          );
          widget.onWeekSelected?.call(data.year, data.weekNumber);
        } else {
          debugPrint('[WeeklyGrid] onWeekSelected 호출 안 함: 조건 불일치');
        }

        setState(() {
          _pendingTapWeek = null;
        });

        if (_hoveredWeek != null) {
          setState(() {
            _hoveredWeek = null;
          });
        }
      },
      onTapCancel: () {
        // 탭이 취소되면 대기 상태 해제
        setState(() {
          _pendingTapWeek = null;
        });

        if (_hoveredWeek != null) {
          setState(() {
            _hoveredWeek = null;
          });
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          if (_hoveredWeek != data.weekNumber) {
            setState(() {
              _hoveredWeek = data.weekNumber;
            });
          }
        },
        onExit: (_) {
          if (_hoveredWeek != null) {
            setState(() {
              _hoveredWeek = null;
            });
          }
        },
        child: AnimatedBuilder(
          animation: _selectionAnimationController,
          builder: (context, child) {
            return Container(
              key: cellKey,
              width: size,
              height: size * 0.85, // 세로 길이를 15% 줄임
              decoration: BoxDecoration(
                color:
                    isLongPressed
                        ? Theme.of(context).colorScheme.primary
                        : cellColor,
                borderRadius: BorderRadius.circular(7),
                border:
                    isSelected
                        ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                        : null,
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(
                              0.4 * _selectionGlowAnimation.value,
                            ),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                        : null,
              ),
              child:
                  isHovered && !isSelected
                      ? Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                      )
                      : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectedWeekInfo(int weekNumber) {
    final weekRange = WeekUtils.getWeekDateRange(widget.year, weekNumber);
    final startDate = weekRange.start;
    final endDate = weekRange.end;

    return AnimatedOpacity(
      opacity: widget.selectedWeek != null ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Row(
        children: [
          // 주차 번호
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_circle_filled,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$weekNumber',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 날짜 범위
          Text(
            '${startDate.month}/${startDate.day} - ${endDate.month}/${endDate.day}',
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
