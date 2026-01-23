import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

import '../weekly_contribution_grid.dart';
import '../../screens/week_post_list_screen.dart';
import 'package:doppy/utils/week_utils.dart';

enum _HighlightDirection { preferRight, preferLeft }

/// GlobalKey로 타겟 Rect를 계산해 말풍선을 "정확히" 붙여서 렌더링하는 오버레이
class WeeklyStreakCoachmarkOverlay extends StatefulWidget {
  const WeeklyStreakCoachmarkOverlay({
    super.key,
    required this.targetKey,
    required this.allCellKeys,
    required this.contributions,
    required this.year,
    required this.kind,
    required this.message,
    this.colorSubstrings,
    required this.progressText,
    required this.primaryText,
    required this.onNext,
    required this.onClose,
    this.onPrevious,
  });

  final GlobalKey? targetKey;
  final Map<int, GlobalKey> allCellKeys; // weekNumber -> key
  final List<WeeklyContributionData>? contributions; // ✅ 전체 셀 색상 정보
  final int year; // ✅ 연도 정보
  final String kind; // 'intro' | 'pastFill' | 'interaction' (직렬화용)
  final String message; // ✅ title 제거, message만 사용
  final Map<String, Color>? colorSubstrings; // ✅ 색상으로 강조할 텍스트 부분들 (텍스트 -> 색상)
  final String progressText;
  final String primaryText;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final VoidCallback? onPrevious; // ✅ 이전 스텝으로 이동하는 콜백

  @override
  State<WeeklyStreakCoachmarkOverlay> createState() =>
      _WeeklyStreakCoachmarkOverlayState();
}

class _WeeklyStreakCoachmarkOverlayState
    extends State<WeeklyStreakCoachmarkOverlay>
    with TickerProviderStateMixin {
  Rect? _targetRect;
  final Map<GlobalKey, Rect> _rectByKey = {};
  int _measureNonce = 0;
  late AnimationController _animationController;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // ✅ 현재 스텝 확인 (progressText에서 파싱: "1/3", "2/3", "3/3")
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

    // ✅ 애니메이션 컨트롤러 초기화 (더 부드러운 애니메이션을 위해 duration 증가)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // ✅ 펄스 애니메이션 컨트롤러 (3단계에서 사용)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // ✅ 파도 애니메이션 컨트롤러 (2단계에서 사용)
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // ✅ 1,2번 스텝: 채워지는 애니메이션 (애니메이션은 각 셀에서 개별적으로 처리)
    if (currentStep <= 2) {
      _pulseAnimation = const AlwaysStoppedAnimation(1.0);
      // ✅ 1단계: 이번주 셀 제외한 옆 셀들에 파도 효과 (오른쪽으로 멀어지는 방향)
      // ✅ 2단계: 파도 효과 (순차적으로 밝아졌다 어두워지는 효과)
      if (currentStep == 1 || currentStep == 2) {
        _waveController.repeat(); // 반복 파도 효과
      }
    } else {
      // ✅ 3번 스텝: 펄스 애니메이션 (반복, 더 큰 스케일 변동)
      _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      );
      _pulseController.repeat(reverse: true); // 반복 펄스
    }

    _animationController.forward();

    // ✅ 온보딩 직후에는 트리가 크게 흔들릴 수 있어
    // "명시적인 딜레이 + 안정성 검증" 후 1회 측정으로 고정한다.
    _measureAfterLayoutStabilized(reset: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WeeklyStreakCoachmarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.progressText != widget.progressText) {
      _measureAfterLayoutStabilized(reset: true);
      // ✅ 스텝이 변경되면 애니메이션 재시작
      final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
      final currentStep =
          stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

      if (currentStep <= 2) {
        _pulseAnimation = const AlwaysStoppedAnimation(1.0);
        // ✅ 1단계: 이번주 셀 제외한 옆 셀들에 파도 효과 (오른쪽으로 멀어지는 방향)
        // ✅ 2단계: 파도 효과 (순차적으로 밝아졌다 어두워지는 효과)
        if (currentStep == 1 || currentStep == 2) {
          _waveController.repeat(); // 반복 파도 효과
        } else {
          _waveController.stop();
        }
      } else {
        // ✅ 3번 스텝: 펄스 애니메이션 (반복, 더 큰 스케일 변동)
        _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        );
        _pulseController.repeat(reverse: true); // 반복 펄스
        _waveController.stop();
      }
      _animationController.reset();
      _animationController.forward();
    }
  }

  static bool _isRectStable(Rect a, Rect b, {double tolerancePx = 0.75}) {
    final dCenter = a.center - b.center;
    final dCenter2 = dCenter.dx * dCenter.dx + dCenter.dy * dCenter.dy;
    final dw = a.size.width - b.size.width;
    final dh = a.size.height - b.size.height;
    final dSize2 = dw * dw + dh * dh;
    return dCenter2 <= (tolerancePx * tolerancePx) &&
        dSize2 <= (tolerancePx * tolerancePx);
  }

  Map<GlobalKey, Rect> _snapshotRects() {
    final nextMap = <GlobalKey, Rect>{};
    for (final k in widget.allCellKeys.values) {
      final ctx = k.currentContext;
      final ro = ctx?.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final size = ro.size;
        if (size.width <= 0 || size.height <= 0) continue;
        final topLeft = ro.localToGlobal(Offset.zero);
        nextMap[k] = topLeft & size;
      }
    }
    return nextMap;
  }

  /// ✅ "운"이 아니라 "정의된 대기"로 안정화된 좌표를 얻는다.
  /// - 최소: endOfFrame 2회 + 고정 딜레이
  /// - 추가: 2~3회 스냅샷 비교로 안정성 검증
  Future<void> _measureAfterLayoutStabilized({bool reset = false}) async {
    if (!mounted) return;
    final int nonce = ++_measureNonce;

    // 1) 이번 프레임/다음 프레임까지 대기 (build/layout/paint를 확실히 끝낸다)
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || nonce != _measureNonce) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || nonce != _measureNonce) return;

    // 2) 온보딩 전환 직후 안정화를 위한 고정 딜레이
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || nonce != _measureNonce) return;

    // 3) 스냅샷 2~3회로 안정성 검증
    final s1 = _snapshotRects();
    final tk = widget.targetKey;
    final r1 = (tk != null) ? s1[tk] : null;

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || nonce != _measureNonce) return;

    final s2 = _snapshotRects();
    final r2 = (tk != null) ? s2[tk] : null;

    Map<GlobalKey, Rect> chosenMap = s2;
    Rect? chosenTarget = r2;

    final stableTwo =
        (r1 != null && r2 != null) ? _isRectStable(r1, r2) : false;

    if (!stableTwo) {
      // 마지막으로 1회 더 기다렸다가 확정 (여기서도 흔들리면 그 시점의 값을 사용)
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || nonce != _measureNonce) return;
      final s3 = _snapshotRects();
      final r3 = (tk != null) ? s3[tk] : null;
      chosenMap = s3;
      chosenTarget = r3;
    }

    if (!mounted || nonce != _measureNonce) return;
    setState(() {
      _rectByKey
        ..clear()
        ..addAll(chosenMap);
      _targetRect = chosenTarget;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeTop = mq.padding.top;

    final rect = _targetRect;
    if (rect == null) {
      // 타겟 셀이 아직 렌더되지 않았을 수 있음
      return const SizedBox.shrink();
    }

    // ==============================
    // ✅ 전체 그리드 복제 + 특정 셀 강조
    // ==============================
    final allCells = _buildAllCells();
    final highlights = _buildHighlights(targetRect: rect);

    // ✅ 현재 스텝 확인
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

    return Stack(
      children: [
        // ✅ 전체 그리드 복제 (모든 셀을 색상, 투명도 유지하며 복제)
        ...allCells,
        // ✅ 강조할 셀들만 추가 레이어로 하이라이트 (애니메이션 포함)
        ...highlights,
        // ✅ 1단계(intro)일 때 가장 진한 셀 밑에 화살표와 텍스트 표시
        if (widget.kind == 'intro' && currentStep == 1)
          _buildSuccessIndicator(context, rect),
        // ✅ 2단계(pastFill)일 때도 테두리만 있는 셀 밑에 화살표와 "이번 주" 텍스트 표시
        if (widget.kind == 'pastFill' && currentStep == 2)
          _buildPastFillIndicator(context, rect),
        // 우측 상단 X 버튼 (코치마크 모드에서만)
        Positioned(
          top: safeTop + 10,
          right: 12,
          child: Opacity(
            opacity: 0.55,
            child: IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
              color: Colors.white,
              tooltip: '닫기',
            ),
          ),
        ),
        // ✅ 바닥에 멘트 크게 표시
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).size.height * 0.15,
          child: _buildBottomMessage(context),
        ),
      ],
    );
  }

  /// ✅ 전체 그리드의 모든 셀을 복제 (색상, 투명도 유지 + 페이드 규칙 적용)
  List<Widget> _buildAllCells() {
    if (widget.contributions == null) return [];

    final byWeek = <int, WeeklyContributionData>{};
    for (final c in widget.contributions!) {
      if (c.year == widget.year) byWeek[c.weekNumber] = c;
    }

    // ✅ grayOpacity 계산 (그리드의 페이드 규칙 적용)
    final grayOpacityByWeek = _calculateGrayOpacity(byWeek);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cellSpacing = 2.0;
    final items = <Widget>[];

    // ✅ 현재 스텝 확인 (2단계에서 타겟 셀 제외하기 위해)
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;
    final isStep2 = currentStep == 2 && widget.kind == 'pastFill';

    // ✅ 같은 행에 있는 셀들을 그룹화하여 마지막 열 판단
    final cellsByRow = <double, List<MapEntry<GlobalKey, Rect>>>{};
    for (final entry in _rectByKey.entries) {
      final r = entry.value;
      final rowY = r.top;
      cellsByRow.putIfAbsent(rowY, () => []).add(entry);
    }

    // 각 행에서 가장 오른쪽 셀 찾기
    final rightmostCells = <GlobalKey>{};
    for (final rowCells in cellsByRow.values) {
      if (rowCells.isEmpty) continue;
      // 같은 행에서 x 좌표가 가장 큰 셀 찾기
      rowCells.sort((a, b) => a.value.center.dx.compareTo(b.value.center.dx));
      rightmostCells.add(rowCells.last.key);
    }

    for (final entry in _rectByKey.entries) {
      final weekNumber = _getWeekNumberFromKey(entry.key);
      if (weekNumber == null) continue;

      // ✅ 2단계에서 타겟 셀은 fill을 그리지 않음 (테두리만 표시하기 위해)
      if (isStep2 &&
          widget.targetKey != null &&
          entry.key == widget.targetKey) {
        continue;
      }

      final data = byWeek[weekNumber];
      final postCount = data?.postCount ?? 0;
      final r = entry.value;
      final grayOpacity = grayOpacityByWeek[weekNumber] ?? 1.0;
      final isLastColumn = rightmostCells.contains(entry.key);

      // ✅ 실제 셀 색상 계산 (WeeklyContributionGrid의 _cellFillColor 로직과 동일)
      // ✅ 기본 셀은 투명도를 낮춰서 연하게 표시
      Color cellColor;
      if (postCount > 0) {
        // 보라색 셀
        final purpleColor =
            isDark
                ? const Color.fromARGB(255, 122, 136, 255)
                : const Color(0xFF7680FF);
        final baseOpacity =
            postCount >= 3
                ? 1.0
                : postCount >= 2
                ? 0.7
                : 0.4;
        // ✅ 기본 셀은 더 연하게 (0.5 배율)
        cellColor = purpleColor.withOpacity(baseOpacity * 0.5);
      } else {
        // 회색 셀 (grayOpacity 적용)
        final base =
            isDark
                ? const Color(0xFF2A2A2A)
                : const Color.fromARGB(255, 237, 237, 240);
        // ✅ 기본 셀은 더 연하게 (0.5 opacity) + grayOpacity 페이드 규칙 적용
        cellColor = base.withOpacity(0.5 * grayOpacity);
      }

      items.add(
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: IgnorePointer(
            child: Padding(
              // ✅ 원본 그리드와 동일하게 Padding으로 간격 처리
              padding: EdgeInsets.only(right: isLastColumn ? 0 : cellSpacing),
              child: SizedBox(
                // ✅ Rect 크기를 유지하기 위해 SizedBox로 크기 고정
                width: r.width - (isLastColumn ? 0 : cellSpacing),
                height: r.height,
                child: Container(
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return items;
  }

  /// GlobalKey에서 weekNumber 추출 (allCellKeys를 역으로 검색)
  int? _getWeekNumberFromKey(GlobalKey key) {
    for (final entry in widget.allCellKeys.entries) {
      if (entry.value == key) {
        return entry.key;
      }
    }
    return null;
  }

  /// ✅ grayOpacity 계산 (그리드의 페이드 규칙과 동일)
  Map<int, double> _calculateGrayOpacity(
    Map<int, WeeklyContributionData> byWeek,
  ) {
    final result = <int, double>{};

    // weekNumber를 정렬해서 인덱스 배열 생성
    final sortedWeeks = widget.allCellKeys.keys.toList()..sort();
    if (sortedWeeks.isEmpty) return result;

    final weeksInYear = WeekUtils.getWeeksInYear(widget.year);
    final now = DateTime.now();
    final currentYear = now.year;
    final isPastYear = widget.year < currentYear;
    final isFutureYear = widget.year > currentYear;
    final todayWeek =
        (widget.year == currentYear) ? WeekUtils.getWeekNumber(now) : null;
    final startWeek = 1; // 간단히 1주차로 설정 (signupAt 정보가 없으므로)

    // 활동 셀 판정
    bool isActive(int weekNumber) {
      if (weekNumber < 1 || weekNumber > weeksInYear) return false;
      if ((byWeek[weekNumber]?.postCount ?? 0) > 0) return true;
      if (todayWeek != null && weekNumber == todayWeek) return true;
      if (weekNumber == startWeek) return true;
      return false;
    }

    // stepOpacity 함수
    double stepOpacity(int dist) {
      if (dist == 1) return 0.65;
      if (dist == 2) return 0.48;
      if (dist == 3) return 0.32;
      if (dist == 4) return 0.13;
      if (dist == 5) return 0.0;
      return 0.0;
    }

    // leftActiveIdx, rightActiveIdx 계산
    final leftActiveIdx = List<int?>.filled(sortedWeeks.length, null);
    int? lastActive;
    for (int i = 0; i < sortedWeeks.length; i++) {
      if (isActive(sortedWeeks[i])) lastActive = i;
      leftActiveIdx[i] = lastActive;
    }

    final rightActiveIdx = List<int?>.filled(sortedWeeks.length, null);
    int? nextActive;
    for (int i = sortedWeeks.length - 1; i >= 0; i--) {
      if (isActive(sortedWeeks[i])) nextActive = i;
      rightActiveIdx[i] = nextActive;
    }

    // grayOpacityByIndex 계산
    if (isPastYear) {
      for (int i = 0; i < sortedWeeks.length; i++) {
        result[sortedWeeks[i]] = 1.0;
      }
    } else if (isFutureYear) {
      for (int i = 0; i < sortedWeeks.length; i++) {
        result[sortedWeeks[i]] = 0.25;
      }
    } else {
      // 현재 연도: 기존 opacity 감쇠 로직 적용
      for (int i = 0; i < sortedWeeks.length; i++) {
        final weekNumber = sortedWeeks[i];
        if (isActive(weekNumber)) {
          result[weekNumber] = 1.0;
          continue;
        }
        final l = leftActiveIdx[i];
        final r = rightActiveIdx[i];
        if (l == null && r == null) {
          result[weekNumber] = 0.0;
          continue;
        }
        if (l != null && r != null) {
          // 보라 사이에 끼어있을 때는 100% opacity
          result[weekNumber] = 1.0;
        } else {
          final dist = (l != null) ? (i - l) : (r! - i);
          result[weekNumber] = stepOpacity(dist);
        }
      }
    }

    return result;
  }

  List<Widget> _buildHighlights({required Rect targetRect}) {
    // ✅ 현재 스텝 확인
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

    // ✅ 3단계(interaction)는 한 셀만 하이라이트 + 펄스 애니메이션 + 클릭 가능
    if (widget.kind == 'interaction' || currentStep == 3) {
      const base = Color(0xFF7680FF);
      // ✅ targetKey에서 weekNumber 추출
      final weekNumber =
          widget.targetKey != null
              ? _getWeekNumberFromKey(widget.targetKey!)
              : null;

      return [
        Positioned(
          left: targetRect.left,
          top: targetRect.top,
          width: targetRect.width,
          height: targetRect.height,
          child: GestureDetector(
            onTap: () {
              // ✅ 코치마크 닫기
              widget.onClose();
              // ✅ 주차 상세 화면으로 이동
              if (weekNumber != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (context) => WeekPostListScreen(
                          year: widget.year,
                          weekNumber: weekNumber,
                        ),
                  ),
                );
              }
            },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                // ✅ 3단계: 펄스 애니메이션
                final scale = _pulseAnimation.value;
                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: base.withOpacity(1.0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ];
    }

    // 같은 행 후보: y가 비슷한 것들
    final targetCenter = targetRect.center;
    final sameRow =
        _rectByKey.values.where((r) {
          return (r.center.dy - targetCenter.dy).abs() <
              targetRect.height * 0.75;
        }).toList();

    List<Rect> pickRight() {
      final rights =
          sameRow.where((r) => r.center.dx > targetCenter.dx + 1).toList()
            ..sort((a, b) => a.center.dx.compareTo(b.center.dx));
      return rights.take(2).toList();
    }

    List<Rect> pickLeft() {
      final lefts =
          sameRow.where((r) => r.center.dx < targetCenter.dx - 1).toList()
            ..sort((a, b) => b.center.dx.compareTo(a.center.dx));
      // ✅ 2단계에서는 3개를 가져옴
      final count = widget.kind == 'pastFill' ? 3 : 2;
      return lefts.take(count).toList();
    }

    // ✅ 강조할 셀 선택 (kind에 따라)
    final dir =
        widget.kind == 'pastFill'
            ? _HighlightDirection.preferLeft
            : _HighlightDirection.preferRight;

    List<Rect> neighbors;
    if (dir == _HighlightDirection.preferRight) {
      neighbors = pickRight();
      if (neighbors.length < 2) {
        neighbors = [...neighbors, ...pickLeft()].take(2).toList();
      }
    } else {
      neighbors = pickLeft();
      // ✅ 2단계에서는 3개를 유지, 부족하면 오른쪽에서 보충
      if (neighbors.length < 3 && widget.kind == 'pastFill') {
        neighbors = [...neighbors, ...pickRight()].take(3).toList();
      } else if (neighbors.length < 2) {
        neighbors = [...neighbors, ...pickRight()].take(2).toList();
      }
    }

    Color c0;
    Color c1;
    Color c2;
    Color c3;
    bool isTargetBorderOnly = false; // ✅ 2단계에서 타겟 셀은 테두리만
    if (widget.kind == 'pastFill') {
      // ✅ 2단계: 타겟 셀은 테두리만, 회색 셀들은 fill (3개)
      isTargetBorderOnly = true;
      const baseGray = Color.fromARGB(255, 190, 190, 190); // 약간 어두운 회색
      c0 = const Color(0xFF7680FF); // 타겟 셀 색상 (테두리용)
      c1 = baseGray.withOpacity(0.9);
      c2 = baseGray.withOpacity(0.6);
      c3 = baseGray.withOpacity(0.35);
    } else {
      const base = Color(0xFF7680FF);
      c0 = base.withOpacity(1.0);
      c1 = base.withOpacity(0.7);
      c2 = base.withOpacity(0.45);
      c3 = base.withOpacity(0.3);
    }

    final rects = <Rect>[targetRect, ...neighbors];
    final colors = <Color>[
      c0,
      if (neighbors.isNotEmpty) c1,
      if (neighbors.length > 1) c2,
      if (neighbors.length > 2) c3,
    ];

    // ✅ 하이라이트: 원본 그리드와 동일하게 Padding으로 간격 처리
    const cellSpacing = 2.0;
    final items = <Widget>[];

    // ✅ 같은 행에 있는 셀들을 그룹화하여 마지막 열 판단
    final highlightCellsByRow = <double, List<int>>{};
    for (int i = 0; i < rects.length; i++) {
      if (i >= colors.length) break;
      final r = rects[i];
      final rowY = r.top;
      highlightCellsByRow.putIfAbsent(rowY, () => []).add(i);
    }

    // 각 행에서 가장 오른쪽 셀 인덱스 찾기
    final rightmostIndices = <int>{};
    for (final rowIndices in highlightCellsByRow.values) {
      if (rowIndices.isEmpty) continue;
      // 같은 행에서 x 좌표가 가장 큰 셀 찾기
      rowIndices.sort(
        (a, b) => rects[a].center.dx.compareTo(rects[b].center.dx),
      );
      rightmostIndices.add(rowIndices.last);
    }

    // ✅ 채워지는 방향 결정 (intro: 오른쪽, pastFill: 왼쪽)
    final fillDirection =
        widget.kind == 'pastFill'
            ? TextDirection
                .rtl // 왼쪽에서 오른쪽으로 채워짐 (RTL이므로 실제로는 오른쪽에서 왼쪽으로)
            : TextDirection.ltr; // 왼쪽에서 오른쪽으로 채워짐

    for (int i = 0; i < rects.length; i++) {
      if (i >= colors.length) break;
      final r = rects[i];
      final isLastColumn = rightmostIndices.contains(i);

      // ✅ 각 셀의 애니메이션 지연 시간 (순차적으로 채워지는 효과, 더 부드럽게)
      final delay = i * 0.12; // 각 셀마다 0.12초씩 지연 (더 빠르고 부드럽게)
      final adjustedAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            delay.clamp(0.0, 1.0),
            (delay + 0.7).clamp(0.0, 1.0), // 애니메이션 길이 증가
            curve: Curves.easeOutCubic, // 더 부드러운 curve
          ),
        ),
      );

      items.add(
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: IgnorePointer(
            child: Padding(
              // ✅ 원본 그리드와 동일하게 Padding으로 간격 처리
              padding: EdgeInsets.only(right: isLastColumn ? 0 : cellSpacing),
              child: SizedBox(
                // ✅ Rect 크기를 유지하기 위해 SizedBox로 크기 고정
                width: r.width - (isLastColumn ? 0 : cellSpacing),
                height: r.height,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    adjustedAnimation,
                    if (currentStep == 1 || currentStep == 2) _waveController,
                  ]),
                  builder: (context, child) {
                    final fillValue = adjustedAnimation.value;

                    // ✅ 1단계: 이번주 셀 제외한 옆 셀들에 파도 효과 (오른쪽으로 멀어지는 방향)
                    // ✅ 2단계: 파도 효과 (순차적으로 밝아졌다 어두워지는 효과)
                    double opacity = 1.0;
                    if (currentStep == 1) {
                      // 이번주 셀(index 0)은 제외하고 옆 셀들만 파도 효과
                      if (i > 0) {
                        // 오른쪽으로 멀어지는 방향: (i - 1) * delay (타겟 셀 제외)
                        final waveDelay = (i - 1) * 0.25;
                        final waveProgress =
                            (_waveController.value + waveDelay) % 1.0;
                        // sin 함수를 사용하여 부드러운 파도 효과 (0.7 ~ 1.0 사이)
                        final sinValue =
                            (math.sin(waveProgress * 2 * math.pi) + 1) / 2;
                        opacity = 0.7 + (0.3 * sinValue);
                      }
                    } else if (currentStep == 2) {
                      // 각 셀마다 다른 delay로 파도 효과 생성
                      final waveDelay = i * 0.25; // 각 셀마다 0.25씩 지연
                      final waveProgress =
                          (_waveController.value + waveDelay) % 1.0;
                      // sin 함수를 사용하여 부드러운 파도 효과 (0.7 ~ 1.0 사이)
                      final sinValue =
                          (math.sin(waveProgress * 2 * math.pi) + 1) / 2;
                      opacity = 0.7 + (0.3 * sinValue);
                    }

                    // ✅ 2단계에서 타겟 셀(i == 0)은 테두리만 표시
                    if (isTargetBorderOnly && i == 0) {
                      return Opacity(
                        opacity: opacity,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors[i], width: 2.0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    }

                    return Opacity(
                      opacity: opacity,
                      child: ClipRect(
                        child: Align(
                          alignment:
                              fillDirection == TextDirection.ltr
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                          widthFactor: fillValue,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors[i],
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }
    return items;
  }

  /// ✅ 1단계에서 가장 진한 셀 밑에 화살표와 성공 메시지 표시
  Widget _buildSuccessIndicator(BuildContext context, Rect targetRect) {
    // 셀 하단 중앙 위치
    final arrowStartX = targetRect.center.dx;
    final arrowStartY = targetRect.bottom;
    final arrowLength = 20.0; // 아주 짧은 화살표
    final arrowEndY = arrowStartY + arrowLength;
    final textY = arrowEndY + 8.0; // 화살표 아래 텍스트

    return Stack(
      children: [
        // 화살표 그리기
        Positioned.fill(
          child: CustomPaint(
            painter: _ShortArrowPainter(
              startX: arrowStartX,
              startY: arrowStartY,
              endY: arrowEndY,
            ),
          ),
        ),
        // "이번주 기록 성공!" 텍스트
        Positioned(
          left: 0,
          right: 0,
          top: textY,
          child: Center(
            child: Text(
              '이번 주 기록 성공!',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLight,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  /// ✅ 2단계에서 테두리만 있는 셀 밑에 화살표와 "이번 주" 텍스트 표시
  Widget _buildPastFillIndicator(BuildContext context, Rect targetRect) {
    // 셀 하단 중앙 위치
    final arrowStartX = targetRect.center.dx;
    final arrowStartY = targetRect.bottom;
    final arrowLength = 20.0; // 아주 짧은 화살표
    final arrowEndY = arrowStartY + arrowLength;
    final textY = arrowEndY + 8.0; // 화살표 아래 텍스트

    return Stack(
      children: [
        // 화살표 그리기
        Positioned.fill(
          child: CustomPaint(
            painter: _ShortArrowPainter(
              startX: arrowStartX,
              startY: arrowStartY,
              endY: arrowEndY,
            ),
          ),
        ),
        // "이번 주" 텍스트
        Positioned(
          left: 0,
          right: 0,
          top: textY,
          child: Center(
            child: Text(
              '이번 주',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLight,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  /// ✅ 첫 번째 스텝인지 확인
  bool _isFirstStep() {
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;
    return currentStep == 1;
  }

  /// ✅ 바닥에 멘트 크게 표시
  Widget _buildBottomMessage(BuildContext context) {
    final baseStyle = LocaleTypography.style(
      context: context,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppColors.darkTextPrimary.withOpacity(0.9),
      height: 1.6,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ✅ 메시지 (colorSubstrings가 있으면 색상으로 강조 적용)
        widget.colorSubstrings != null && widget.colorSubstrings!.isNotEmpty
            ? _buildMessageWithColorSpans(
              context: context,
              message: widget.message,
              colorSubstrings: widget.colorSubstrings!,
              baseStyle: baseStyle,
            )
            : Text(
              widget.message,
              style: baseStyle,
              textAlign: TextAlign.center,
            ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.16),
        // 진행 상황 및 버튼
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ✅ 첫 번째 스텝이 아니고 onPrevious가 제공된 경우에만 '이전' 버튼 표시
            if (!_isFirstStep() && widget.onPrevious != null)
              GestureDetector(
                onTap: widget.onPrevious,
                child: const Text(
                  '이전',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
            if (!_isFirstStep() && widget.onPrevious != null)
              const SizedBox(width: 16),
            ElevatedButton(
              onPressed: widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 70,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                widget.primaryText,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// ✅ 메시지에서 colorSubstrings를 찾아 TextSpan으로 색상 강조
  Widget _buildMessageWithColorSpans({
    required BuildContext context,
    required String message,
    required Map<String, Color> colorSubstrings,
    required TextStyle baseStyle,
  }) {
    final spans = <TextSpan>[];
    int lastIndex = 0;
    String remainingText = message;

    // 모든 colorSubstrings를 찾아서 처리
    final matches = <({int start, int end, String text, Color color})>[];
    for (final entry in colorSubstrings.entries) {
      final substring = entry.key;
      final color = entry.value;
      int searchStart = 0;
      while (true) {
        final index = remainingText.indexOf(substring, searchStart);
        if (index == -1) break;
        matches.add((
          start: index,
          end: index + substring.length,
          text: substring,
          color: color,
        ));
        searchStart = index + 1;
      }
    }

    // 시작 위치로 정렬
    matches.sort((a, b) => a.start.compareTo(b.start));

    // 겹치는 부분 제거 (먼저 나온 것 우선)
    final nonOverlappingMatches =
        <({int start, int end, String text, Color color})>[];
    for (final match in matches) {
      if (nonOverlappingMatches.isEmpty ||
          match.start >= nonOverlappingMatches.last.end) {
        nonOverlappingMatches.add(match);
      }
    }

    // TextSpan 생성
    for (final match in nonOverlappingMatches) {
      // match 이전 텍스트
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: remainingText.substring(lastIndex, match.start),
            style: baseStyle,
          ),
        );
      }
      // 색상으로 강조할 텍스트 (볼드 더 두껍게)
      spans.add(
        TextSpan(
          text: match.text,
          style: baseStyle.copyWith(
            color: match.color,
            fontWeight: FontWeight.w900, // ✅ 더 두꺼운 볼드
          ),
        ),
      );
      lastIndex = match.end;
    }

    // 마지막 남은 텍스트
    if (lastIndex < remainingText.length) {
      spans.add(
        TextSpan(text: remainingText.substring(lastIndex), style: baseStyle),
      );
    }

    return RichText(
      text: TextSpan(
        children:
            spans.isEmpty ? [TextSpan(text: message, style: baseStyle)] : spans,
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// ✅ 짧은 화살표를 그리는 CustomPainter
class _ShortArrowPainter extends CustomPainter {
  final double startX;
  final double startY;
  final double endY;

  _ShortArrowPainter({
    required this.startX,
    required this.startY,
    required this.endY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    // 세로선 그리기
    canvas.drawLine(Offset(startX, startY), Offset(startX, endY), paint);

    // 화살표 머리 그리기 (아래쪽을 가리키는 작은 화살표)
    final arrowSize = 6.0;
    final arrowPath = Path();
    arrowPath.moveTo(startX, endY);
    arrowPath.lineTo(startX - arrowSize * 0.5, endY - arrowSize * 0.8);
    arrowPath.moveTo(startX, endY);
    arrowPath.lineTo(startX + arrowSize * 0.5, endY - arrowSize * 0.8);

    canvas.drawPath(arrowPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ShortArrowPainter oldDelegate) {
    return oldDelegate.startX != startX ||
        oldDelegate.startY != startY ||
        oldDelegate.endY != endY;
  }
}
