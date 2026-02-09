import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;

import '../../screens/week_post_list_screen.dart';
import 'package:doppy/data/models/military_grid_model.dart';

enum _HighlightDirection { preferRight, preferLeft }

/// Military Grid 기반 코치마크 오버레이
/// Phase/Cell 기반으로 동작합니다.
class MilitaryGridCoachmarkOverlay extends StatefulWidget {
  const MilitaryGridCoachmarkOverlay({
    super.key,
    required this.targetKey,
    required this.allCellKeys,
    required this.gridResponse,
    required this.targetPhase,
    required this.targetCell,
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
  final Map<String, Map<int, GlobalKey>>
  allCellKeys; // phase -> slotIndex -> key
  final MilitaryGridResponse gridResponse; // 전체 그리드 데이터
  final Phase targetPhase; // 타겟 Phase
  final Cell targetCell; // 타겟 Cell
  final String kind; // 'intro' | 'pastFill' | 'interaction'
  final String message;
  final Map<String, Color>? colorSubstrings;
  final String progressText;
  final String primaryText;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final VoidCallback? onPrevious;

  @override
  State<MilitaryGridCoachmarkOverlay> createState() =>
      _MilitaryGridCoachmarkOverlayState();
}

class _MilitaryGridCoachmarkOverlayState
    extends State<MilitaryGridCoachmarkOverlay>
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
    // ✅ 현재 스텝 확인
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

    // ✅ 애니메이션 컨트롤러 초기화
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    if (currentStep <= 2) {
      _pulseAnimation = const AlwaysStoppedAnimation(1.0);
      if (currentStep == 1 || currentStep == 2) {
        _waveController.repeat();
      }
    } else {
      _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      );
      _pulseController.repeat(reverse: true);
    }

    _animationController.forward();
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
  void didUpdateWidget(covariant MilitaryGridCoachmarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.progressText != widget.progressText) {
      _measureAfterLayoutStabilized(reset: true);
      final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
      final currentStep =
          stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

      if (currentStep <= 2) {
        _pulseAnimation = const AlwaysStoppedAnimation(1.0);
        if (currentStep == 1 || currentStep == 2) {
          _waveController.repeat();
        } else {
          _waveController.stop();
        }
      } else {
        _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        );
        _pulseController.repeat(reverse: true);
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
    // 모든 Phase의 모든 셀 키 수집
    for (final phaseKeys in widget.allCellKeys.values) {
      for (final k in phaseKeys.values) {
        final ctx = k.currentContext;
        final ro = ctx?.findRenderObject();
        if (ro is RenderBox && ro.hasSize) {
          final size = ro.size;
          if (size.width <= 0 || size.height <= 0) continue;
          final topLeft = ro.localToGlobal(Offset.zero);
          nextMap[k] = topLeft & size;
        }
      }
    }
    return nextMap;
  }

  Future<void> _measureAfterLayoutStabilized({bool reset = false}) async {
    if (!mounted) return;
    final int nonce = ++_measureNonce;

    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || nonce != _measureNonce) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || nonce != _measureNonce) return;

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || nonce != _measureNonce) return;

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
      return const SizedBox.shrink();
    }

    final allCells = _buildAllCells();
    final highlights = _buildHighlights(targetRect: rect);

    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

    return Stack(
      children: [
        // ✅ 전체 그리드 복제
        ...allCells,
        // ✅ 강조할 셀들만 추가 레이어로 하이라이트
        ...highlights,
        // ✅ 1단계(intro)일 때 가장 진한 셀 밑에 화살표와 텍스트 표시
        if (widget.kind == 'intro' && currentStep == 1)
          _buildSuccessIndicator(context, rect),
        // ✅ 2단계(pastFill)일 때도 테두리만 있는 셀 밑에 화살표와 "이번 주" 텍스트 표시
        if (widget.kind == 'pastFill' && currentStep == 2)
          _buildPastFillIndicator(context, rect),
        // 우측 상단 X 버튼
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

  /// ✅ 전체 그리드의 모든 셀을 복제
  List<Widget> _buildAllCells() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cellSpacing = 2.0;
    final items = <Widget>[];

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

    final rightmostCells = <GlobalKey>{};
    for (final rowCells in cellsByRow.values) {
      if (rowCells.isEmpty) continue;
      rowCells.sort((a, b) => a.value.center.dx.compareTo(b.value.center.dx));
      rightmostCells.add(rowCells.last.key);
    }

    // 모든 Phase의 모든 셀을 순회
    for (final phase in widget.gridResponse.phases) {
      for (final cell in phase.cells) {
        final cellKey = _getCellKey(phase, cell);
        if (cellKey == null) continue;

        final rect = _rectByKey[cellKey];
        if (rect == null) continue;

        // ✅ 2단계에서 타겟 셀은 fill을 그리지 않음
        if (isStep2 &&
            widget.targetKey != null &&
            cellKey == widget.targetKey) {
          continue;
        }

        final postCount = cell.postCount;
        final isLastColumn = rightmostCells.contains(cellKey);

        // ✅ 셀 색상 계산 (primary 기반)
        final scheme = Theme.of(context).colorScheme;
        Color cellColor;
        if (postCount > 0) {
          final primaryColor = scheme.primary;
          final baseOpacity =
              postCount >= 3
                  ? 1.0
                  : postCount >= 2
                  ? 0.7
                  : 0.4;
          cellColor = primaryColor.withOpacity(baseOpacity * 0.5);
        } else {
          final base =
              isDark
                  ? const Color(0xFF2A2A2A)
                  : const Color.fromARGB(255, 237, 237, 240);
          cellColor = base.withOpacity(0.5);
        }

        items.add(
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.only(right: isLastColumn ? 0 : cellSpacing),
                child: SizedBox(
                  width: rect.width - (isLastColumn ? 0 : cellSpacing),
                  height: rect.height,
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
    }

    return items;
  }

  /// Phase와 Cell에서 GlobalKey 가져오기
  GlobalKey? _getCellKey(Phase phase, Cell cell) {
    return widget.allCellKeys[phase.phase]?[cell.slotIndex];
  }

  List<Widget> _buildHighlights({required Rect targetRect}) {
    final stepMatch = RegExp(r'(\d+)/(\d+)').firstMatch(widget.progressText);
    final currentStep =
        stepMatch != null ? int.tryParse(stepMatch.group(1) ?? '1') ?? 1 : 1;

    // ✅ 3단계(interaction)는 한 셀만 하이라이트 + 펄스 애니메이션
    if (widget.kind == 'interaction' || currentStep == 3) {
      const base = Color(0xFF7680FF);

      return [
        Positioned(
          left: targetRect.left,
          top: targetRect.top,
          width: targetRect.width,
          height: targetRect.height,
          child: GestureDetector(
            onTap: () {
              widget.onClose();
              // ✅ 셀 상세 화면으로 이동 (phase + slotIndex 기반)
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (context) => MilitaryPostListScreen(
                        phase: widget.targetPhase.phase,
                        slotIndex: widget.targetCell.slotIndex,
                      ),
                ),
              );
            },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
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

    // 같은 행 후보 찾기
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
      final count = widget.kind == 'pastFill' ? 3 : 2;
      return lefts.take(count).toList();
    }

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
    bool isTargetBorderOnly = false;
    if (widget.kind == 'pastFill') {
      isTargetBorderOnly = true;
      const baseGray = Color.fromARGB(255, 190, 190, 190);
      c0 = const Color(0xFF7680FF);
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

    const cellSpacing = 2.0;
    final items = <Widget>[];

    final highlightCellsByRow = <double, List<int>>{};
    for (int i = 0; i < rects.length; i++) {
      if (i >= colors.length) break;
      final r = rects[i];
      final rowY = r.top;
      highlightCellsByRow.putIfAbsent(rowY, () => []).add(i);
    }

    final rightmostIndices = <int>{};
    for (final rowIndices in highlightCellsByRow.values) {
      if (rowIndices.isEmpty) continue;
      rowIndices.sort(
        (a, b) => rects[a].center.dx.compareTo(rects[b].center.dx),
      );
      rightmostIndices.add(rowIndices.last);
    }

    final fillDirection =
        widget.kind == 'pastFill' ? TextDirection.rtl : TextDirection.ltr;

    for (int i = 0; i < rects.length; i++) {
      if (i >= colors.length) break;
      final r = rects[i];
      final isLastColumn = rightmostIndices.contains(i);

      final delay = i * 0.12;
      final adjustedAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            delay.clamp(0.0, 1.0),
            (delay + 0.7).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
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
              padding: EdgeInsets.only(right: isLastColumn ? 0 : cellSpacing),
              child: SizedBox(
                width: r.width - (isLastColumn ? 0 : cellSpacing),
                height: r.height,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    adjustedAnimation,
                    if (currentStep == 1 || currentStep == 2) _waveController,
                  ]),
                  builder: (context, child) {
                    final fillValue = adjustedAnimation.value;

                    double opacity = 1.0;
                    if (currentStep == 1) {
                      if (i > 0) {
                        final waveDelay = (i - 1) * 0.25;
                        final waveProgress =
                            (_waveController.value + waveDelay) % 1.0;
                        final sinValue =
                            (math.sin(waveProgress * 2 * math.pi) + 1) / 2;
                        opacity = 0.7 + (0.3 * sinValue);
                      }
                    } else if (currentStep == 2) {
                      final waveDelay = i * 0.25;
                      final waveProgress =
                          (_waveController.value + waveDelay) % 1.0;
                      final sinValue =
                          (math.sin(waveProgress * 2 * math.pi) + 1) / 2;
                      opacity = 0.7 + (0.3 * sinValue);
                    }

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
    final arrowStartX = targetRect.center.dx;
    final arrowStartY = targetRect.bottom;
    final arrowLength = 20.0;
    final arrowEndY = arrowStartY + arrowLength;
    final textY = arrowEndY + 8.0;
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ShortArrowPainter(
              startX: arrowStartX,
              startY: arrowStartY,
              endY: arrowEndY,
              color: scheme.primary,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: textY,
          child: Center(
            child: Text(
              '이번 주 기록 성공!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primaryContainer,
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
    final arrowStartX = targetRect.center.dx;
    final arrowStartY = targetRect.bottom;
    final arrowLength = 20.0;
    final arrowEndY = arrowStartY + arrowLength;
    final textY = arrowEndY + 8.0;
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ShortArrowPainter(
              startX: arrowStartX,
              startY: arrowStartY,
              endY: arrowEndY,
              color: scheme.primary,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: textY,
          child: Center(
            child: Text(
              '이번 주',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primaryContainer,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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

    matches.sort((a, b) => a.start.compareTo(b.start));

    final nonOverlappingMatches =
        <({int start, int end, String text, Color color})>[];
    for (final match in matches) {
      if (nonOverlappingMatches.isEmpty ||
          match.start >= nonOverlappingMatches.last.end) {
        nonOverlappingMatches.add(match);
      }
    }

    for (final match in nonOverlappingMatches) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: remainingText.substring(lastIndex, match.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.text,
          style: baseStyle.copyWith(
            color: match.color,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      lastIndex = match.end;
    }

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
  final Color color;

  _ShortArrowPainter({
    required this.startX,
    required this.startY,
    required this.endY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(startX, startY), Offset(startX, endY), paint);

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
        oldDelegate.endY != endY ||
        oldDelegate.color != color;
  }
}
