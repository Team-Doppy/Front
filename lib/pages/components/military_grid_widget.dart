import 'dart:async';
import 'dart:math' as math;

import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/l10n/military_grid_messages.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:doppy/utils/week_utils.dart';

/// Military Grid 위젯 (새로운 시스템)
/// Phase 기반 그리드를 표시합니다.
/// 기존 weekly_contribution_grid의 기능을 모두 통합합니다.
class MilitaryGridWidget extends StatefulWidget {
  final MilitaryGridResponse gridResponse;
  final Function(Phase phase, Cell cell)? onCellTap;
  final Function(Phase phase, Cell cell, Offset? position, Offset? cellCenter)?
  onLongPress; // 롱프레스 콜백 (위치 + 셀 중심 포함)
  final Cell? selectedCell;
  final bool isLoading; // 로딩 중일 때 쉬머 효과 표시
  final void Function(Phase phase, Cell cell, GlobalKey key)?
  onCellKey; // 코치마크용
  final DateTime? asOf; // null이면 DateTime.now() 기준

  const MilitaryGridWidget({
    super.key,
    required this.gridResponse,
    this.onCellTap,
    this.onLongPress,
    this.selectedCell,
    this.isLoading = false,
    this.onCellKey,
    this.asOf,
  });

  @override
  State<MilitaryGridWidget> createState() => _MilitaryGridWidgetState();
}

class _MilitaryGridWidgetState extends State<MilitaryGridWidget> {
  static const int _columns = 7; // 주 7일
  static const double _horizontalPadding = 24.0; // ✅ 좌/우 패딩 고정
  Timer? _tickTimer;
  DateTime _liveNow = WeekUtils.getCurrentDate();
  final Map<String, GlobalKey> _cellKeys = {}; // phase-slotIndex 조합으로 키 생성
  String? _activeGreetingKey;
  String? _greetingMessage;
  Future<String?>? _greetingFuture;
  bool _greetingVisible = false; // ✅ 최초 진입 포함, 항상 0 → 1로 페이드인되도록 제어

  GlobalKey _keyForCell(Phase phase, Cell cell) {
    // ✅ 서버에서 gridKey가 추가됨 (동일 phase/slotIndex라도 그리드 대상이 달라질 수 있어 충돌 방지)
    final gridKeyPrefix = phase.gridKey ?? phase.phase;
    final key = '$gridKeyPrefix-${phase.phase}-${cell.slotIndex}';
    return _cellKeys.putIfAbsent(key, () => GlobalKey());
  }

  @override
  void initState() {
    super.initState();
    // ✅ 최초 greetingKey 반영: 첫 진입은 바로 보이게 (페이드인 없음)
    _activeGreetingKey = widget.gridResponse.greetingKey;
    _greetingVisible = true; // ✅ 첫 진입은 바로 보이게
    if ((_activeGreetingKey ?? '').isNotEmpty) {
      _startGreetingLoad(_activeGreetingKey!, isFirstLoad: true);
    }

    // 주차 변화 감지용 Timer
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = WeekUtils.getCurrentDate();

      // TODO: phase 기반이므로 연도 체크 로직 조정 필요

      final prevWeek = WeekUtils.getWeekNumber(_liveNow);
      final nextWeek = WeekUtils.getWeekNumber(now);
      if (prevWeek != nextWeek) {
        setState(() {
          _liveNow = now;
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
  void didUpdateWidget(covariant MilitaryGridWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ greetingKey 변경: 이전 메시지 즉시 제거(빈 상태) 후 새 메시지 로드 → 페이드인
    final nextKey = widget.gridResponse.greetingKey;
    final prevKey = oldWidget.gridResponse.greetingKey;
    if (nextKey != prevKey) {
      _activeGreetingKey = nextKey;
      _startGreetingLoad(nextKey, isFirstLoad: false); // ✅ phase 변경 시 페이드인 적용
      return;
    }

    // ✅ 로딩 상태가 끝났으면: 메시지가 준비되어 있으면 그때 표시
    if (oldWidget.isLoading && !widget.isLoading) {
      _scheduleGreetingFadeInIfPossible();
    }
  }

  void _scheduleGreetingFadeInIfPossible() {
    // ✅ 로딩 완료 후 메시지 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isLoading) return;
      if ((_activeGreetingKey ?? '').isEmpty) return;
      if ((_greetingMessage ?? '').isEmpty) return;
      if (_greetingVisible) return;
      setState(() {
        _greetingVisible = true;
      });
    });
  }

  void _startGreetingLoad(String greetingKey, {required bool isFirstLoad}) {
    setState(() {
      _activeGreetingKey = greetingKey;
      _greetingMessage = null;
      // ✅ 첫 진입은 바로 보이게, phase 변경 시에만 페이드인 적용
      _greetingVisible = isFirstLoad;
    });

    _greetingFuture = _getGreetingMessageWithFallback(greetingKey);
    _greetingFuture!.then((msg) {
      if (!mounted) return;
      // ✅ 다른 greetingKey 로드가 뒤늦게 도착한 경우 무시
      if (_activeGreetingKey != greetingKey) return;

      setState(() {
        _greetingMessage = msg ?? '';
      });

      // ✅ 메시지가 준비되면(그리고 로딩이 아니면) 다음 프레임에서 500ms 페이드인 시작
      _scheduleGreetingFadeInIfPossible();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ 그리팅 메시지: 로딩 중에는 opacity 0 (공간은 유지)
        if (widget.gridResponse.greetingKey.isNotEmpty)
          _buildGreeting(context, widget.gridResponse.greetingKey),

        // Phase별 그리드
        ...widget.gridResponse.phases.map(
          (phase) => _buildPhaseSection(context, phase),
        ),
      ],
    );
  }

  /// 그리팅 메시지 표시 (페이드 인 애니메이션 포함)
  Widget _buildGreeting(BuildContext context, String greetingKey) {
    // ✅ greetingKey가 바뀌었는데 아직 로드 트리거가 안 됐으면 build 중엔 직접 setState하지 말고 다음 프레임에 시작
    if (_activeGreetingKey != greetingKey && greetingKey.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_activeGreetingKey == greetingKey) return;
        _startGreetingLoad(
          greetingKey,
          isFirstLoad: false,
        ); // ✅ phase 변경 시 페이드인 적용
      });
    }

    final shouldShow =
        !widget.isLoading &&
        _greetingVisible &&
        ((_greetingMessage ?? '').isNotEmpty);

    // ✅ 요구사항: 로딩 중에는 "숨기지 말고 opacity=0" (레이아웃은 유지)
    // ✅ 추가: 숨김→표시는 500ms, 표시는 "즉시 숨김"(겹침/불안정 방지)
    final duration =
        shouldShow ? const Duration(milliseconds: 500) : Duration.zero;

    return ConstrainedBox(
      // ✅ 고정 height는 잘림을 유발하므로 minHeight만 둬서 레이아웃 안정화
      constraints: const BoxConstraints(minHeight: 110),
      child: AnimatedOpacity(
        opacity: shouldShow ? 1.0 : 0.0,
        duration: duration,
        curve: Curves.easeInOutCubic,
        child:
            (_greetingMessage == null)
                ? const SizedBox.shrink()
                : _buildGreetingText(context, _greetingMessage!),
      ),
    );
  }

  /// 그리팅 메시지 가져오기 (폴백 포함)
  Future<String?> _getGreetingMessageWithFallback(String greetingKey) async {
    final message = await MilitaryGridMessages.getGreetingMessage(greetingKey);
    if (message != null) {
      return message;
    }
    return await MilitaryGridMessages.getGreetingMessage(
      'military.greeting.default',
    );
  }

  Widget _buildGreetingText(BuildContext context, String message, {Key? key}) {
    // ✅ 레이아웃 안정화: 최소 높이와 정렬로 오른쪽 치우침 방지
    return Padding(
      key: key, // ✅ AnimatedSwitcher에서 사용할 key
      padding: const EdgeInsets.only(
        left: _horizontalPadding,
        right: _horizontalPadding,
        top: 0,
        bottom: 36, // ✅ 그리팅과 그리드 사이 간격 추가
      ),
      child: Align(
        alignment: Alignment.centerLeft, // ✅ 왼쪽 정렬로 치우침 방지
        child: Text(
          message,
          style: LocaleTypography.style(
            context: context,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// Phase 섹션 표시
  Widget _buildPhaseSection(BuildContext context, Phase phase) {
    final phaseLabel =
        MilitaryGridMessages.getPhaseLabel(phase.labelKey) ?? phase.phase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 라벨
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _horizontalPadding,
            vertical: 8,
          ),
          child: Text(
            phaseLabel,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),

        // 그리드 셀들
        _buildGridCells(context, phase),
      ],
    );
  }

  static const Map<String, int> _fallbackSlotCountsByPhase = {
    'preEnlistment': 7,
    'training': 5,
    'private': 13,
    'privateFirstClass': 13,
    'corporal': 13,
    'sergeant': 13,
  };

  int _fallbackSlotCountForPhase(String phaseCode) {
    return _fallbackSlotCountsByPhase[phaseCode] ?? 0;
  }

  /// 그리드 셀들 표시
  Widget _buildGridCells(BuildContext context, Phase phase) {
    // ✅ 서버가 slotCount=0을 내려주는 경우가 있어도, 빈 phase에 플레이스홀더를 보여줘야 함
    // ✅ preEnlistment는 항상 7개로 강제 설정
    final slotCount =
        phase.phase == 'preEnlistment'
            ? 7
            : (phase.slotCount > 0
                ? phase.slotCount
                : _fallbackSlotCountForPhase(phase.phase));
    if (slotCount <= 0) {
      return const SizedBox.shrink();
    }

    final cellsBySlot = <int, Cell>{};
    for (final cell in phase.cells) {
      cellsBySlot[cell.slotIndex] = cell;
    }

    // 포스트 개수 최대값 계산
    final maxPostCount = phase.cells
        .map((c) => c.postCount)
        .fold<int>(0, (a, b) => math.max(a, b));

    // ✅ 서버에서 이번주 정보를 제공하므로 클라이언트 계산 로직 제거
    // 서버에서 Cell에 isCurrentWeek 같은 플래그를 제공할 예정

    // ✅ 활동 셀 판단 (포스트가 있거나 오늘 주차)
    bool isActiveAtIndex(int index) {
      final slotIndex = index + 1;
      final cell = cellsBySlot[slotIndex];
      if (cell == null) {
        // ✅ year/week가 제거되어 현재 주차 판단 불가
        return false;
      }

      // 포스트가 있는 경우
      if (cell.postCount > 0) return true;

      // 오늘이 속한 셀 (year/week 매칭) - year/week가 서버에서 제거되어 사용하지 않음
      // if (cell.year != null && cell.week != null &&
      //     cell.year == currentYear && cell.week == currentWeek) return true;

      return false;
    }

    // ✅ fade out 효과 계산 (활성 셀 기준으로 거리에 따라 투명도 조절)
    final leftActiveIdx = List<int?>.filled(slotCount, null);
    int? lastActive;
    for (int i = 0; i < slotCount; i++) {
      if (isActiveAtIndex(i)) lastActive = i;
      leftActiveIdx[i] = lastActive;
    }

    final rightActiveIdx = List<int?>.filled(slotCount, null);
    int? nextActive;
    for (int i = slotCount - 1; i >= 0; i--) {
      if (isActiveAtIndex(i)) nextActive = i;
      rightActiveIdx[i] = nextActive;
    }

    final hasAnyActive = lastActive != null;

    // ✅ opacity 하한선 설정 (그리드 형체가 보이도록)
    const double minOpacity = 0.3;

    double stepOpacity(int dist) {
      if (dist == 1) return 0.65;
      if (dist == 2) return 0.48;
      if (dist >= 3) return minOpacity;

      return minOpacity;
    }

    final grayOpacityByIndex = List<double>.filled(slotCount, 1.0);
    for (int i = 0; i < slotCount; i++) {
      if (isActiveAtIndex(i)) {
        grayOpacityByIndex[i] = 1.0;
        continue;
      }
      final l = leftActiveIdx[i];
      final r = rightActiveIdx[i];
      if (l == null && r == null) {
        // ✅ 활성 셀이 하나도 없으면(포스트 0개) "흰 여백"이 되지 않도록 플레이스홀더 유지
        grayOpacityByIndex[i] = hasAnyActive ? minOpacity : 1.0; // 하한선 적용
        continue;
      }
      if (l != null && r != null) {
        grayOpacityByIndex[i] = 1.0; // 활성 셀 사이는 100%
      } else {
        final dist = (l != null) ? (i - l) : (r! - i);
        grayOpacityByIndex[i] = stepOpacity(
          dist,
        ).clamp(minOpacity, 1.0); // 하한선 적용
      }
    }

    // ✅ 로딩/스켈레톤 상태에서는 opacity 감쇠를 끔 (회색 셀을 항상 보여줘야 함)
    if (widget.isLoading) {
      for (int i = 0; i < grayOpacityByIndex.length; i++) {
        grayOpacityByIndex[i] = 1.0;
      }
    }

    // ✅ "최대 7칸" 규칙: slotCount가 7 미만이면 그 개수만큼 한 줄로 꽉 채움
    final columnsUsed = slotCount < _columns ? slotCount : _columns;
    final rows = (slotCount / columnsUsed).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellSpacing = 2.0;

          final availableWidth = constraints.maxWidth;
          final totalSpacing = (columnsUsed - 1) * cellSpacing;
          final baseCellSize = (availableWidth - totalSpacing) / columnsUsed;
          final cellSize = baseCellSize;
          final radius = 4.0;

          return RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, // ✅ 가로 꽉 채움
              children: List.generate(rows, (rowIndex) {
                final isFirstRow = rowIndex == 0;
                final isLastRow = rowIndex == rows - 1;
                final lastCellIndexInFirstRow = columnsUsed - 1;
                final isFirstRowFull =
                    isFirstRow && (lastCellIndexInFirstRow < phase.slotCount);
                final lastCellIndexInRow = (rowIndex + 1) * columnsUsed - 1;
                final isLastRowFull =
                    isLastRow && (lastCellIndexInRow < phase.slotCount);

                return Padding(
                  padding: EdgeInsets.only(bottom: isLastRow ? 0 : cellSpacing),
                  child: Row(
                    mainAxisSize: MainAxisSize.max, // ✅ 가로 꽉 채움
                    children: List.generate(columnsUsed, (colIndex) {
                      final index = rowIndex * columnsUsed + colIndex;
                      final isLastColumn = colIndex == columnsUsed - 1;

                      if (index >= slotCount) {
                        return Padding(
                          padding: EdgeInsets.only(
                            right: isLastColumn ? 0 : cellSpacing,
                          ),
                          child: SizedBox(width: cellSize, height: cellSize),
                        );
                      }

                      final slotIndex = index + 1;
                      final cell =
                          cellsBySlot[slotIndex] ??
                          Cell(
                            slotIndex: slotIndex,
                            year: 0,
                            week: 0,
                            currentWeek: false,
                            myPosts: [],
                          );

                      final cellKey = _keyForCell(phase, cell);
                      widget.onCellKey?.call(phase, cell, cellKey);

                      final isSelected =
                          widget.selectedCell != null &&
                          widget.selectedCell!.slotIndex == cell.slotIndex;
                      // year/week가 서버에서 제거되어 slotIndex만으로 비교
                      // && widget.selectedCell!.year == cell.year &&
                      // widget.selectedCell!.week == cell.week;

                      // ✅ 서버에서 제공하는 currentWeek 필드 사용
                      final isTodayWeek = cell.currentWeek;

                      // ✅ 클릭/롱프레스 가능: 모든 셀 가능 (핸들러에서 로직 처리)
                      final isClickable = true;
                      final isLongPressable = true;

                      return KeyedSubtree(
                        key: cellKey,
                        child: Padding(
                          key: ValueKey('${phase.phase}-$slotIndex'),
                          padding: EdgeInsets.only(
                            right: isLastColumn ? 0 : cellSpacing,
                          ),
                          child: _buildCell(
                            phase: phase,
                            cell: cell,
                            size: cellSize,
                            radius: radius,
                            isSelected: isSelected,
                            isClickable: isClickable,
                            isLongPressable: isLongPressable,
                            isTodayWeek: isTodayWeek,
                            maxPostCount: maxPostCount,
                            grayOpacity: grayOpacityByIndex[index].clamp(
                              0.0,
                              1.0,
                            ),
                            isFirstRow: isFirstRow,
                            isLastRow: isLastRow,
                            isFirstColumn: colIndex == 0,
                            isLastColumn: isLastColumn,
                            isFirstRowFull: isFirstRowFull,
                            isLastRowFull: isLastRowFull,
                            isSingleRow: rows == 1, // ✅ 한 줄 여부 전달
                            isLoading: widget.isLoading,
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  /// 개별 셀 위젯
  Widget _buildCell({
    required Phase phase,
    required Cell cell,
    required double size,
    required double radius,
    required bool isSelected,
    required bool isClickable,
    required bool isLongPressable,
    required bool isTodayWeek,
    required int maxPostCount,
    required double grayOpacity,
    required bool isFirstRow,
    required bool isLastRow,
    required bool isFirstColumn,
    required bool isLastColumn,
    required bool isFirstRowFull,
    required bool isLastRowFull,
    required bool isSingleRow, // ✅ 한 줄 여부
    required bool isLoading,
  }) {
    final fillColor =
        isLoading
            ? _getLoadingBaseColor()
            : _cellFillColor(
              cell: cell,
              maxPostCount: maxPostCount,
              grayOpacity: grayOpacity,
            );

    return Builder(
      builder: (cellContext) {
        final cornerRadius = 10.0;
        BorderRadius? borderRadius;

        // ✅ 한 줄일 때: 첫 번째와 마지막 셀에 corner radius 적용
        if (isSingleRow) {
          if (isFirstColumn && isLastColumn) {
            // 한 줄에 셀이 하나만 있는 경우
            borderRadius = BorderRadius.circular(cornerRadius);
          } else if (isFirstColumn) {
            // 첫 번째 셀: 왼쪽 모서리만 corner radius
            borderRadius = BorderRadius.only(
              topLeft: Radius.circular(cornerRadius),
              topRight: Radius.circular(radius),
              bottomLeft: Radius.circular(cornerRadius),
              bottomRight: Radius.circular(radius),
            );
          } else if (isLastColumn) {
            // 마지막 셀: 오른쪽 모서리만 corner radius
            borderRadius = BorderRadius.only(
              topLeft: Radius.circular(radius),
              topRight: Radius.circular(cornerRadius),
              bottomLeft: Radius.circular(radius),
              bottomRight: Radius.circular(cornerRadius),
            );
          } else {
            // 중간 셀
            borderRadius = BorderRadius.circular(radius);
          }
        } else if (isFirstRow && isFirstColumn) {
          // 여러 줄: 첫 번째 행, 첫 번째 열
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(cornerRadius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(radius),
            bottomRight: Radius.circular(radius),
          );
        } else if (isFirstRow && isLastColumn && isFirstRowFull) {
          // 여러 줄: 첫 번째 행, 마지막 열 (행이 꽉 참)
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(cornerRadius),
            bottomLeft: Radius.circular(radius),
            bottomRight: Radius.circular(radius),
          );
        } else if (isLastRow && isFirstColumn) {
          // 여러 줄: 마지막 행, 첫 번째 열
          borderRadius = BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(cornerRadius),
            bottomRight: Radius.circular(radius),
          );
        } else if (isLastRow && isLastColumn && isLastRowFull) {
          // 여러 줄: 마지막 행, 마지막 열 (행이 꽉 참)
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

        Border? border;
        if (isTodayWeek) {
          border = Border.all(color: primary.withOpacity(1), width: 2);
        } else if (isSelected) {
          border = null;
        }

        // 휴가 포스트 찾기 (LEAVE_OR_PRE_ENLISTMENT) - 우선 표시
        PostMeta? leavePost;
        try {
          leavePost = cell.myPosts.firstWhere((p) => p.isLeaveOrPreEnlistment);
        } catch (_) {
          leavePost = null;
        }

        // 일반 포스트 찾기 (휴가가 아닌 포스트)
        PostMeta? regularPost;
        try {
          regularPost = cell.myPosts.firstWhere(
            (p) => !p.isLeaveOrPreEnlistment,
          );
        } catch (_) {
          regularPost = cell.myPosts.isNotEmpty ? cell.myPosts.first : null;
        }

        // 셀 높이 제한: 최대 60으로 제한
        final maxCellHeight = 54.0;
        final cellHeight = (size * 0.9).clamp(0.0, maxCellHeight);

        Widget cellContent = Ink(
          width: size,
          height: cellHeight,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: borderRadius,
            border: isLoading ? null : border,
          ),
          child: Stack(
            children: [
              // ✅ InkWell을 먼저 배치하여 ripple 효과 활성화
              Positioned.fill(
                child: InkWell(
                  customBorder: RoundedRectangleBorder(
                    borderRadius: borderRadius,
                  ),
                  splashColor: primary.withOpacity(0.4),
                  highlightColor: primary.withOpacity(0.2),
                  onTap:
                      isClickable && !isLoading
                          ? () {
                            debugPrint(
                              '[MilitaryGridWidget] 셀 탭: ${phase.phase} ${cell.slotIndex}주차',
                            );
                            widget.onCellTap?.call(phase, cell);
                          }
                          : null,
                  onLongPress:
                      isLongPressable && !isLoading
                          ? () {
                            debugPrint(
                              '[MilitaryGridWidget] 셀 롱프레스 (InkWell): ${phase.phase} ${cell.slotIndex}주차',
                            );
                            // 롱프레스 시작 시 위치 계산
                            final renderObject = cellContext.findRenderObject();
                            final box =
                                renderObject is RenderBox ? renderObject : null;
                            final cellCenter = box?.localToGlobal(
                              Offset(
                                (box.size.width) / 2,
                                (box.size.height) / 2,
                              ),
                            );
                            widget.onLongPress?.call(
                              phase,
                              cell,
                              cellCenter ?? Offset.zero,
                              cellCenter,
                            );
                          }
                          : null,
                  child: const SizedBox.expand(),
                ),
              ),
              // ✅ GestureDetector를 위에 배치하여 드래그 이벤트 처리
              if (!isLoading && isLongPressable)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: (details) {
                      debugPrint(
                        '[MilitaryGridWidget] 셀 롱프레스 시작: ${phase.phase} ${cell.slotIndex}주차',
                      );
                      final renderObject = cellContext.findRenderObject();
                      final box =
                          renderObject is RenderBox ? renderObject : null;
                      final cellCenter = box?.localToGlobal(
                        Offset((box.size.width) / 2, (box.size.height) / 2),
                      );

                      widget.onLongPress?.call(
                        phase,
                        cell,
                        details.globalPosition,
                        cellCenter,
                      );
                    },
                    onLongPressMoveUpdate: (details) {
                      widget.onLongPress?.call(
                        phase,
                        cell,
                        details.globalPosition,
                        null,
                      );
                    },
                    onLongPressEnd: (_) {
                      widget.onLongPress?.call(
                        phase,
                        Cell(
                          slotIndex: 0,
                          year: 0,
                          week: 0,
                          currentWeek: false,
                          myPosts: [],
                        ),
                        null,
                        null,
                      );
                    },
                    onLongPressCancel: () {
                      widget.onLongPress?.call(
                        phase,
                        Cell(
                          slotIndex: 0,
                          year: 0,
                          week: 0,
                          currentWeek: false,
                          myPosts: [],
                        ),
                        null,
                        null,
                      );
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              // ✅ 썸네일은 휴가/입대전 포스트(LEAVE_OR_PRE_ENLISTMENT)가 있을 때만 표시
              if (leavePost != null && !isLoading)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: _buildThumbnail(leavePost, regularPost),
                  ),
                ),
            ],
          ),
        );

        // 로딩 중일 때는 쉬머 효과
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
            cursor: isClickable ? SystemMouseCursors.click : MouseCursor.defer,
            child: cellContent,
          ),
        );
      },
    );
  }

  /// 썸네일 이미지 위젯
  Widget _buildThumbnail(PostMeta? leavePost, PostMeta? regularPost) {
    // 휴가 포스트 썸네일 우선
    if (leavePost != null && leavePost.thumbnailUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: leavePost.thumbnailUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[300]),
        errorWidget:
            (context, url, error) => Container(
              color: Colors.grey[300],
              child: const Icon(Icons.error),
            ),
      );
    }

    // ✅ 일반 포스트는 썸네일 표시 안 함 (휴가일 때만 사진)
    return const SizedBox.shrink();
  }

  /// 셀 색상 결정
  Color _cellFillColor({
    required Cell cell,
    required int maxPostCount,
    required double grayOpacity,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark
            ? const Color(0xFF2A2A2A)
            : const Color.fromARGB(255, 237, 237, 240);

    final postCount = cell.postCount;

    // 포스트가 있는 주차: primary 색상 사용
    if (postCount > 0) {
      final primaryColor = scheme.primary;

      // 3개 이상: 100%, 2개: 70%, 1개: 40%
      final opacity =
          postCount >= 3
              ? 1.0
              : postCount >= 2
              ? 0.7
              : 0.4;

      return primaryColor.withOpacity(opacity);
    }

    // 빈 셀: 회색
    return base.withOpacity(grayOpacity);
  }

  /// 로딩 중일 때 사용할 기본 회색 색상
  Color _getLoadingBaseColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const Color(0xFF2A2A2A)
        : const Color.fromARGB(255, 237, 237, 240);
  }
}
