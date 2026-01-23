import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:shimmer/shimmer.dart';

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
  final DateTime? signupAt; // null이면 해당 연도의 1주차부터 시작
  final DateTime? asOf; // null이면 DateTime.now() 기준 (서버 asOf가 있으면 주입)
  final int? selectedWeek;
  final Function(int year, int weekNumber)? onWeekSelected;
  final List<WeeklyContributionData>? contributions; // null이면 하드코딩 데이터 사용
  final Function(
    int year,
    int weekNumber,
    Offset? position,
    Offset? cellCenter,
  )?
  onLongPress; // 길게 누르기 콜백 (위치 + 셀 중심 포함)
  final bool isLoading; // 로딩 중일 때 쉬머 효과 표시
  // ✅ 코치마크 등을 위해 각 주차 셀에 GlobalKey를 부여하고 외부로 노출
  final void Function(int year, int weekNumber, GlobalKey key)? onCellKey;

  const WeeklyContributionGrid({
    super.key,
    required this.year,
    this.signupAt,
    this.asOf,
    this.selectedWeek,
    this.onWeekSelected,
    this.contributions,
    this.onLongPress,
    this.isLoading = false,
    this.onCellKey,
  });

  @override
  State<WeeklyContributionGrid> createState() => _WeeklyContributionGridState();
}

class _WeeklyContributionGridState extends State<WeeklyContributionGrid> {
  static const int _columns = 7; // 주 7일
  Timer? _tickTimer;
  DateTime _liveNow = WeekUtils.getCurrentDate(); // ✅ 테스트 모드 지원
  final Map<int, GlobalKey> _cellKeysByWeek = {};

  GlobalKey _keyForWeek(int weekNumber) {
    return _cellKeysByWeek.putIfAbsent(weekNumber, () => GlobalKey());
  }

  @override
  void initState() {
    super.initState();

    // ✅ 앱을 켜둔 채로 시간이 흘러도(특히 주차가 바뀌는 시점) 그리드가 자동 확장되도록
    // "현재 연도일 때만" 주차 변화를 감지해서 리빌드한다.
    // ✅ 테스트 모드에서는 Timer 비활성화 (테스트 날짜는 고정)
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = WeekUtils.getCurrentDate(); // ✅ 테스트 모드 지원
      if (widget.year != now.year) return;

      final prevWeek = WeekUtils.getWeekNumber(_liveNow);
      final nextWeek = WeekUtils.getWeekNumber(now);
      if (prevWeek != nextWeek) {
        setState(() {
          _liveNow = now; // ✅ 테스트 모드에서는 변경되지 않음
        });
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contributions = _getContributions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildGrid(contributions),
        ),
      ],
    );
  }

  Widget _buildGrid(List<WeeklyContributionData> contributions) {
    final weeksInYear = WeekUtils.getWeeksInYear(widget.year);
    final currentYear = _asOf.year;
    final isPastYear = widget.year < currentYear;
    final isFutureYear = widget.year > currentYear;

    final byWeek = <int, WeeklyContributionData>{};
    for (final c in contributions) {
      if (c.year == widget.year) byWeek[c.weekNumber] = c;
    }

    // 🎯 가입일 이전 주차에 글을 "지정해서" 쓴 케이스를 지원하기 위해
    // 해당 연도에서 가장 이른 포스트 주차를 렌더 범위 계산에 반영한다.
    int? earliestPostWeek;
    for (final entry in byWeek.entries) {
      if ((entry.value.postCount) > 0) {
        if (earliestPostWeek == null || entry.key < earliestPostWeek) {
          earliestPostWeek = entry.key;
        }
      }
    }

    final range = _getRenderRange(
      weeksInYear,
      earliestPostWeek: earliestPostWeek,
    );
    final firstWeek = range.firstWeek;
    final lastWeek = range.lastWeek;
    final startWeek = range.startWeek;
    final todayWeek = range.todayWeek;

    final renderWeeks = <int>[];
    for (int w = firstWeek; w <= lastWeek; w++) {
      renderWeeks.add(w);
    }

    // ✅ 최소 2행 보장: 연말 등으로 실제 주차가 부족하면 아래 행을 placeholder로 채운다.
    // (placeholder는 weeksInYear를 초과하는 weekNumber로 표시하며, 선택 불가/연하게 렌더링)
    final minWeeksToRender = _columns * 2;
    if (renderWeeks.length < minWeeksToRender) {
      int next = lastWeek + 1;
      while (renderWeeks.length < minWeeksToRender) {
        renderWeeks.add(next);
        next++;
      }
    }

    final maxPostCount = renderWeeks
        .map((w) => byWeek[w]?.postCount ?? 0)
        .fold<int>(0, (a, b) => math.max(a, b));

    final rows = (renderWeeks.length / _columns).ceil();

    // ==============================
    // 회색 셀 단계형 opacity 계산 (줄바꿈 없이 1D로 간주)
    // - 보라 사이: 100% 고정
    // - 바깥쪽: 80/60/40/20/10/0
    // - 활동 셀: postCount > 0, 오늘 주차, 가입일 주차
    // ==============================
    bool isActiveAtIndex(int idx) {
      final w = renderWeeks[idx];
      if (w < 1 || w > weeksInYear) return false;

      // ✅ WeekUtils는 "1월 1일부터 7일=1주" 규칙을 사용한다.
      // 따라서 ISO(목요일 anchor) 기반 연도 소속 판정은 사용하지 않는다.

      // 포스트가 있는 경우
      if ((byWeek[w]?.postCount ?? 0) > 0) return true;
      // 오늘이 속한 셀
      if (todayWeek != null && w == todayWeek) return true;
      // 가입일이 속한 셀
      if (w == startWeek) return true;
      return false;
    }

    double stepOpacity(int dist) {
      // dist: 보라 셀로부터의 거리(1부터) - 바깥쪽용
      if (dist == 1) return 0.65; // 80
      if (dist == 2) return 0.48; // 60
      if (dist == 3) return 0.32; // 40
      if (dist == 4) return 0.13; // 20
      if (dist == 5) return 0.0; // 10
      return 0.0; // 0
    }

    final leftActiveIdx = List<int?>.filled(renderWeeks.length, null);
    int? lastActive;
    for (int i = 0; i < renderWeeks.length; i++) {
      if (isActiveAtIndex(i)) lastActive = i;
      leftActiveIdx[i] = lastActive;
    }

    final rightActiveIdx = List<int?>.filled(renderWeeks.length, null);
    int? nextActive;
    for (int i = renderWeeks.length - 1; i >= 0; i--) {
      if (isActiveAtIndex(i)) nextActive = i;
      rightActiveIdx[i] = nextActive;
    }

    final grayOpacityByIndex = List<double>.filled(renderWeeks.length, 1.0);
    final grayBetweenByIndex = List<bool>.filled(renderWeeks.length, false);

    // 🎯 과거 연도에서는 모든 셀을 100% opacity로 표시 (opacity 감쇠 없음)
    // 🎯 미래 연도는 전체를 약하게(연하게) 보여주되, 상호작용은 막는다.
    if (isPastYear) {
      for (int i = 0; i < renderWeeks.length; i++) {
        grayOpacityByIndex[i] = 1.0;
        grayBetweenByIndex[i] = false;
      }
    } else if (isFutureYear) {
      for (int i = 0; i < renderWeeks.length; i++) {
        grayOpacityByIndex[i] = 0.25;
        grayBetweenByIndex[i] = false;
      }
    } else {
      // 현재 연도: 기존 opacity 감쇠 로직 적용
      for (int i = 0; i < renderWeeks.length; i++) {
        if (isActiveAtIndex(i)) {
          grayOpacityByIndex[i] = 1.0;
          grayBetweenByIndex[i] = false;
          continue;
        }
        final l = leftActiveIdx[i];
        final r = rightActiveIdx[i];
        if (l == null && r == null) {
          grayOpacityByIndex[i] = 0.0;
          grayBetweenByIndex[i] = false;
          continue;
        }
        if (l != null && r != null) {
          // 보라 사이에 끼어있을 때는 100% opacity
          grayOpacityByIndex[i] = 1.0; // 100% 고정
          grayBetweenByIndex[i] = true;
        } else {
          final dist = (l != null) ? (i - l) : (r! - i);
          grayOpacityByIndex[i] = stepOpacity(dist);
          grayBetweenByIndex[i] = false;
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 간단 모드일 때 셀 크기와 간격 축소
        final cellSpacing = 2.0;
        final containerPadding = 2.0;

        // 오버플로우 방지: Container padding을 고려하여 계산
        final availableWidth = constraints.maxWidth - (containerPadding * 2);
        final totalSpacing = (_columns - 1) * cellSpacing;
        final baseCellSize = (availableWidth - totalSpacing) / _columns;
        final cellSize = baseCellSize;
        final radius = 4.0;

        return RepaintBoundary(
          child: Container(
            padding: EdgeInsets.all(containerPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(rows, (rowIndex) {
                final isFirstRow = rowIndex == 0;
                final isLastRow = rowIndex == rows - 1;
                // 첫 번째 행이 완전히 차지했는지 확인 (회색 셀 포함해서 7개 셀이 모두 있는지)
                final lastCellIndexInFirstRow = _columns - 1;
                final isFirstRowFull =
                    isFirstRow &&
                    (lastCellIndexInFirstRow < renderWeeks.length);
                // 마지막 행이 완전히 차지했는지 확인 (회색 셀 포함해서 7개 셀이 모두 있는지)
                final lastCellIndexInRow = (rowIndex + 1) * _columns - 1;
                final isLastRowFull =
                    isLastRow && (lastCellIndexInRow < renderWeeks.length);

                return Padding(
                  padding: EdgeInsets.only(bottom: cellSpacing),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_columns, (colIndex) {
                      final index = rowIndex * _columns + colIndex;
                      final isLastColumn = colIndex == _columns - 1;

                      if (index >= renderWeeks.length) {
                        // 빈 셀도 다른 행과 정렬 맞추기 위해 padding 적용
                        return Padding(
                          padding: EdgeInsets.only(
                            right: isLastColumn ? 0 : cellSpacing,
                          ),
                          child: SizedBox(width: cellSize),
                        );
                      }

                      final weekNumber = renderWeeks[index];
                      // ✅ 셀 GlobalKey 등록 (코치마크 타겟으로 사용)
                      final cellKey = _keyForWeek(weekNumber);
                      widget.onCellKey?.call(widget.year, weekNumber, cellKey);
                      final data = byWeek[weekNumber];
                      final postCount = data?.postCount ?? 0;

                      // 🎯 가입일 이전이라도 "이미 포스트가 있으면" 비활성 취급하면 안 된다.
                      // (과거 기록: 가입 후 과거 주차로 지정해서 쓰는 케이스)
                      final hasPost = postCount > 0;
                      final signupAt = widget.signupAt;
                      final isBeforeSignup =
                          !hasPost &&
                          signupAt != null &&
                          // ✅ "가입일 이전 연도"는 막지 않는다. (과거 기록/데이터 이관 등 케이스)
                          // ✅ 가입 연도 내에서만, 가입 주차 이전을 비활성 처리한다.
                          (widget.year == signupAt.year &&
                              weekNumber < startWeek);
                      final isFuturePreview =
                          isFutureYear ||
                          (weekNumber > weeksInYear) ||
                          (todayWeek != null && weekNumber > todayWeek);

                      // 🎯 포스트가 있는 경우 또는 오늘 주차의 빈 셀은 클릭 가능
                      // 🎯 가입한지 7일 안되었고 현재주보다 이전인 빈 셀도 클릭 가능
                      final isPastWeek =
                          todayWeek != null && weekNumber < todayWeek;
                      final canClickEmptyPastWeek =
                          isPastWeek &&
                          postCount == 0 &&
                          signupAt != null &&
                          WeekUtils.isWithin7DaysAfterSignup(signupAt);

                      final isClickable =
                          !isBeforeSignup &&
                          !isFutureYear &&
                          (weekNumber <= weeksInYear) &&
                          (todayWeek == null
                              ? true
                              : weekNumber <= todayWeek) &&
                          (postCount > 0 || // 포스트가 있으면 클릭 가능
                              (todayWeek != null &&
                                  weekNumber == todayWeek &&
                                  postCount == 0) || // 오늘 주차의 빈 셀도 클릭 가능
                              canClickEmptyPastWeek); // 가입한지 7일 안되었고 현재주보다 이전인 빈 셀도 클릭 가능

                      // 🎯 롱프레스는 포스트 유무와 관계없이 가능 (단, 가입 전/미래는 제외)
                      final isLongPressable =
                          !isBeforeSignup &&
                          !isFutureYear &&
                          (weekNumber <= weeksInYear) &&
                          (todayWeek == null ? true : weekNumber <= todayWeek);

                      final isSelected =
                          isClickable && widget.selectedWeek == weekNumber;

                      // 마지막 열은 right padding 제거하여 오버플로우 방지
                      return KeyedSubtree(
                        key: cellKey,
                        child: Padding(
                          key: ValueKey('week-${widget.year}-$weekNumber'),
                          padding: EdgeInsets.only(
                            right: isLastColumn ? 0 : cellSpacing,
                          ),
                          child: _buildCell(
                            weekNumber: weekNumber,
                            data: data,
                            size: cellSize,
                            radius: radius,
                            isSelected: isSelected,
                            isBeforeSignup: isBeforeSignup,
                            isFuturePreview: isFuturePreview,
                            isClickable: isClickable,
                            isLongPressable: isLongPressable,
                            todayWeek: todayWeek,
                            maxPostCount: maxPostCount,
                            grayOpacity:
                                (() {
                                  // 일괄적인 규칙만 적용: 보라 사이 100%, 바깥쪽 80/60/40/20/10/0
                                  return grayOpacityByIndex[index].clamp(
                                    0.0,
                                    1.0,
                                  );
                                })(),
                            isFirstRow: isFirstRow,
                            isLastRow: isLastRow,
                            isFirstColumn: colIndex == 0,
                            isLastColumn: isLastColumn,
                            isFirstRowFull: isFirstRowFull,
                            isLastRowFull: isLastRowFull,
                            isLoading: widget.isLoading,
                            postCount: postCount, // 🎯 빈 셀 판단을 위해 postCount 전달
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCell({
    required int weekNumber,
    required WeeklyContributionData? data,
    required double size,
    required double radius,
    required bool isSelected,
    required bool isBeforeSignup,
    required bool isFuturePreview,
    required bool isClickable,
    required bool isLongPressable,
    required int? todayWeek,
    required int maxPostCount,
    required double grayOpacity,
    required bool isFirstRow,
    required bool isLastRow,
    required bool isFirstColumn,
    required bool isLastColumn,
    required bool isFirstRowFull,
    required bool isLastRowFull,
    required bool isLoading,
    required int postCount, // 🎯 빈 셀 판단을 위해 postCount 전달
  }) {
    // 로딩 중일 때는 모든 셀을 회색으로 표시
    final fillColor =
        isLoading
            ? _getLoadingBaseColor()
            : _cellFillColor(
              weekNumber: weekNumber,
              data: data,
              isBeforeSignup: isBeforeSignup,
              isFuturePreview: isFuturePreview,
              todayWeek: todayWeek,
              maxPostCount: maxPostCount,
              grayOpacity: grayOpacity,
            );

    return Builder(
      builder: (cellContext) {
        // borderRadius를 먼저 계산
        final cornerRadius = 10.0;
        BorderRadius? borderRadius;
        if (isFirstRow && isFirstColumn) {
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(cornerRadius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(radius),
            bottomRight: Radius.circular(radius),
          );
        } else if (isFirstRow && isLastColumn && isFirstRowFull) {
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(cornerRadius),
            bottomLeft: Radius.circular(radius),
            bottomRight: Radius.circular(radius),
          );
        } else if (isLastRow && isFirstColumn) {
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(cornerRadius),
            bottomRight: Radius.circular(radius),
          );
        } else if (isLastRow && isLastColumn && isLastRowFull) {
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(radius),
            bottomRight: Radius.circular(cornerRadius),
          );
        } else {
          borderRadius = BorderRadius.circular(radius);
        }

        final scheme = Theme.of(cellContext).colorScheme;
        final primary = scheme.primary;
        final isTodayWeek = todayWeek != null && weekNumber == todayWeek;

        // "선택/롱프레스 시 fillColor가 차는 UX"는 제거하고,
        // 잉크 물결(리플)만 보이도록 한다. (선택/오늘은 테두리로만 표현)
        Border? border;
        if (isTodayWeek) {
          border = Border.all(color: primary.withOpacity(1), width: 2);
        } else if (isSelected) {
          border = null; // 선택 시 테두리 제거
        }

        // 월 텍스트 표시 여부 확인 (4주마다 = 4칸에 한번)
        // - WeekUtils(1/1 기준 7일=1주)에 맞춰 "주차 중앙(weekStart+3일)"
        //   연도 경계를 넘는 경우(마지막 주)에는 해당 연도의 마지막 날로 클램프하여 월 표시를 안정화한다.
        // - 같은 월이 연속으로 찍히면(4주 간격) 중복 제거
        String? monthText;
        if (weekNumber >= 1 &&
            weekNumber <= WeekUtils.getWeeksInYear(widget.year) &&
            (weekNumber - 1) % 4 == 0) {
          DateTime anchor = WeekUtils.getWeekStartDate(
            widget.year,
            weekNumber,
          ).add(const Duration(days: 3));
          final jan1 = DateTime(widget.year, 1, 1);
          final dec31 = DateTime(widget.year, 12, 31);
          if (anchor.isBefore(jan1)) anchor = jan1;
          if (anchor.isAfter(dec31)) anchor = dec31;

          final month = anchor.month;
          if (weekNumber > 4) {
            final prevCycleWeek = weekNumber - 4;
            DateTime prevAnchor = WeekUtils.getWeekStartDate(
              widget.year,
              prevCycleWeek,
            ).add(const Duration(days: 3));
            if (prevAnchor.isBefore(jan1)) prevAnchor = jan1;
            if (prevAnchor.isAfter(dec31)) prevAnchor = dec31;

            // 같은 월이면 표시하지 않음
            if (prevAnchor.month == month) {
              monthText = null;
            } else {
              monthText = '$month';
            }
          } else {
            monthText = '$month';
          }
        }

        // 로딩 중일 때는 쉬머 효과 적용
        Widget cellContent = Ink(
          width: size,
          height: size * 0.9,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: borderRadius,
            border: isLoading ? null : border,
          ),
          child: Stack(
            children: [
              // 🎯 롱프레스 프리뷰는 "Start/Move/End"로 안정적으로 처리한다.
              // - Start: showBlurOverlay (weekNumber>0)
              // - Move: updateBlurPosition
              // - End/Cancel: weekNumber==0 으로 종료 신호 전송
              if (!isLoading)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart:
                        isLongPressable
                            ? (details) {
                              final renderObject =
                                  cellContext.findRenderObject();
                              final box =
                                  renderObject is RenderBox
                                      ? renderObject
                                      : null;
                              final cellCenter = box?.localToGlobal(
                                Offset(
                                  (box.size.width) / 2,
                                  (box.size.height) / 2,
                                ),
                              );

                              widget.onLongPress?.call(
                                widget.year,
                                weekNumber,
                                details.globalPosition,
                                cellCenter,
                              );
                            }
                            : null,
                    onLongPressMoveUpdate:
                        isLongPressable
                            ? (details) {
                              // position은 null이 되면 프리뷰가 화면 중앙으로 튈 수 있어서
                              // 항상 globalPosition을 유지한다.
                              widget.onLongPress?.call(
                                widget.year,
                                weekNumber,
                                details.globalPosition,
                                null,
                              );
                            }
                            : null,
                    onLongPressEnd:
                        isLongPressable
                            ? (_) {
                              widget.onLongPress?.call(
                                widget.year,
                                0,
                                null,
                                null,
                              );
                            }
                            : null,
                    onLongPressCancel:
                        isLongPressable
                            ? () {
                              widget.onLongPress?.call(
                                widget.year,
                                0,
                                null,
                                null,
                              );
                            }
                            : null,
                    child: InkWell(
                      // 셀 전체에 리플이 꽉 차도록
                      customBorder: RoundedRectangleBorder(
                        borderRadius: borderRadius,
                      ),
                      splashColor: primary.withOpacity(0.4),
                      highlightColor: primary.withOpacity(0.0),
                      // 🎯 빈 셀이면 무조건 리플 효과 표시 (7일 판단은 home_screen에서 처리)
                      // 🎯 포스트가 있는 셀도 클릭 가능
                      onTap:
                          (postCount == 0 || isClickable)
                              ? () {
                                widget.onWeekSelected?.call(
                                  widget.year,
                                  weekNumber,
                                );
                              }
                              : null,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              // 월 텍스트 표시 (로딩 중일 때는 표시하지 않음)
              // 🎯 IgnorePointer로 감싸서 제스처가 바로 전달되도록 함
              if (monthText != null && !isLoading)
                IgnorePointer(
                  child: Center(
                    child: Text(
                      '$monthText월',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        // 배경이 보라색(포스트 있음)이면 흰색, 회색이면 검정색
                        // opacity도 배경과 동일하게 적용
                        color:
                            (data?.postCount ?? 0) > 0
                                ? Colors.white
                                : const Color.fromARGB(
                                  255,
                                  94,
                                  94,
                                  94,
                                ).withOpacity(grayOpacity),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        // 로딩 중일 때는 쉬머 효과로 감싸기
        if (isLoading) {
          final baseColor = _getLoadingBaseColor();
          return Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: baseColor.withOpacity(0.3),
            period: const Duration(milliseconds: 1500),
            child: Material(
              color: Colors.transparent,
              child: MouseRegion(cursor: MouseCursor.defer, child: cellContent),
            ),
          );
        }

        return Material(
          color: Colors.transparent,
          child: MouseRegion(
            // 🎯 포스트가 있는 경우에만 클릭 커서 표시
            cursor: isClickable ? SystemMouseCursors.click : MouseCursor.defer,
            child: cellContent,
          ),
        );
      },
    );
  }

  /// 로딩 중일 때 사용할 기본 회색 색상
  Color _getLoadingBaseColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const Color(0xFF2A2A2A)
        : const Color.fromARGB(255, 237, 237, 240);
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

  DateTime get _asOf {
    // ✅ 테스트 모드 지원: WeekUtils.getCurrentDate() 사용
    final currentDate = WeekUtils.getCurrentDate();
    // 현재 연도는 "실시간"으로 따라가야 그리드가 자연스럽게 확장된다.
    if (widget.year == currentDate.year) return currentDate;
    return widget.asOf ?? currentDate;
  }

  /// 선택 연도에서 "시작 주"를 결정한다.
  /// - 가입연도면 가입 주차부터
  /// - 그 외 연도면 1주차부터
  int _getStartWeek() {
    final signupAt = widget.signupAt;
    if (signupAt == null) return 1;
    if (signupAt.year != widget.year) return 1;
    return WeekUtils.getWeekNumber(signupAt);
  }

  /// 선택 연도에서 "오늘 주차"(현재연도일 때만 의미)를 반환한다.
  int? _getTodayWeekIfCurrentYear() {
    if (_asOf.year != widget.year) return null;
    return WeekUtils.getWeekNumber(_asOf);
  }

  /// 가입 주차가 포함된 "행(=row)"부터 시작해,
  /// - 현재 연도면: 오늘이 속한 행 + 아래 1행까지
  /// - 과거 연도면: 해당 연도 끝까지
  /// - 최소 2행 보장
  ({int firstWeek, int lastWeek, int startWeek, int? todayWeek})
  _getRenderRange(int weeksInYear, {int? earliestPostWeek}) {
    final startWeek = _getStartWeek().clamp(1, weeksInYear);
    final todayWeek = _getTodayWeekIfCurrentYear();

    // ✅ 과거/현재/미래 연도 분리 (todayWeek == null 로 과거/미래가 섞이는 문제 방지)
    // ✅ 테스트 모드 지원: WeekUtils.getCurrentYear() 사용
    final currentYear = WeekUtils.getCurrentYear();
    final isPastYear = widget.year < currentYear;
    final isFutureYear = widget.year > currentYear;

    int firstWeek;
    int lastWeek;

    if (isPastYear) {
      // 🎯 과거 연도: 전체 주차 표시 (1주차부터 마지막 주차까지)
      firstWeek = 1;
      lastWeek = weeksInYear;
    } else if (isFutureYear) {
      // 🎯 미래 연도: "논리적 셀"만(최소 2행) 보여주고, 상호작용은 상위에서 막는다.
      firstWeek = 1;
      lastWeek = math.min(weeksInYear, _columns * 2);
    } else {
      // 현재 연도: 기존 로직 유지
      // ✅ 가입일 이전 주차에 "이미 포스트가 있는" 경우, 그 주차까지는 보여줘야 함
      final effectiveStartWeek =
          (earliestPostWeek != null)
              ? math.min(startWeek, earliestPostWeek.clamp(1, weeksInYear))
              : startWeek;

      // startWeek가 속한 행 계산
      final startRow = (effectiveStartWeek - 1) ~/ _columns;
      final firstWeekInRow = startRow * _columns + 1;
      // 가입일이 속한 행의 첫 번째 셀부터 시작 (행 전체를 보여줌)
      firstWeek = firstWeekInRow;

      final totalRows = (weeksInYear / _columns).ceil();
      final lastRowIndex = totalRows - 1;

      // 현재 연도: 오늘 주가 속한 행 + 아래 1행
      // todayWeek는 현재 연도에서만 의미가 있으나, 안전하게 null 가드
      final safeTodayWeek = todayWeek ?? startWeek;
      final todayRow = (safeTodayWeek - 1) ~/ _columns;
      int targetLastRow = math.min(lastRowIndex, todayRow + 1);

      // 최소 2행 보장: startRow부터 최소 2행은 보여줘야 함
      // targetLastRow가 startRow + 1보다 작으면 startRow + 1로 확장
      if (targetLastRow < startRow + 1) {
        targetLastRow = math.min(lastRowIndex, startRow + 1);
      }

      // 마지막 행의 마지막 주차 계산
      final lastWeekInRow = (targetLastRow + 1) * _columns;
      lastWeek = math.min(weeksInYear, lastWeekInRow);
    }

    return (
      firstWeek: firstWeek,
      lastWeek: lastWeek,
      startWeek: startWeek,
      todayWeek: todayWeek,
    );
  }

  Color _cellFillColor({
    required int weekNumber,
    required WeeklyContributionData? data,
    required bool isBeforeSignup,
    required bool isFuturePreview,
    required int? todayWeek,
    required int maxPostCount,
    required double grayOpacity,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark
            ? const Color(0xFF2A2A2A)
            : const Color.fromARGB(255, 237, 237, 240);

    final postCount = data?.postCount ?? 0;

    // 🎯 포스트가 있는 주차: #7680FF 색상 사용 (다크모드에서는 더 밝게)
    if (postCount > 0) {
      // 다크모드에서는 더 밝은 보라색 사용 (#8A95FF)
      // 라이트모드: #7680FF = RGB(118, 128, 255)
      // 다크모드: #8A95FF = RGB(138, 149, 255)
      final purpleColor =
          isDark
              ? const Color.fromARGB(255, 122, 136, 255)
              : const Color(0xFF7680FF);

      // 3개 이상: 100%, 2개: 70%, 1개: 40%
      final opacity =
          postCount >= 3
              ? 1.0
              : postCount >= 2
              ? 0.7
              : 0.4;

      return purpleColor.withOpacity(opacity);
    }

    // 🎯 빈 셀: 회색 (현재처럼 유지)
    return base.withOpacity(grayOpacity);
  }
}
