import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/editor/postwrite_screen.dart';

/// 연도/월/주차 선택 화면 (CupertinoPicker 스타일)
class DatePickerScreen extends StatefulWidget {
  final int? initialYear;
  final int? initialMonth;
  final int? initialWeek;
  final bool isEditting; // 수정 모드인지 여부
  final Function(int year, int yearOfWeek)? onDateSelected; // 날짜 선택 콜백

  const DatePickerScreen({
    super.key,
    this.initialYear,
    this.initialMonth,
    this.initialWeek,
    this.isEditting = false,
    this.onDateSelected,
  });

  @override
  State<DatePickerScreen> createState() => _DatePickerScreenState();
}

class _DatePickerScreenState extends State<DatePickerScreen> {
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedWeek;

  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _weekController;

  List<int> get _yearItems {
    final currentYear = DateTime.now().year;
    return [currentYear - 1, currentYear]; // 현재 연도와 이전 연도만
  }

  List<int> get _monthItems {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    // 현재 연도가 선택된 경우: 현재 월 이전만 선택 가능
    if (_selectedYear == currentYear) {
      return List.generate(currentMonth, (i) => i + 1);
    }
    // 이전 연도인 경우: 모든 월 선택 가능
    return List.generate(12, (i) => i + 1);
  }

  List<int> get _weekItems {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;
    final currentWeekOfMonth = WeekUtils.getWeekOfMonth(now);

    // 현재 연도이고 현재 월인 경우: 현재 주차 이전만 선택 가능 (1-4 범위 내)
    if (_selectedYear == currentYear && _selectedMonth == currentMonth) {
      final maxWeek = currentWeekOfMonth.clamp(1, 4);
      return List.generate(maxWeek, (i) => i + 1);
    }
    // 그 외의 경우: 1~4주차(월별 최대 주차)까지 선택 가능
    return [1, 2, 3, 4];
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final currentYear = now.year;

    // 초기값 설정 및 범위 검증
    _selectedYear = widget.initialYear ?? currentYear;
    // 연도 범위 검증: 현재 연도 또는 이전 연도만 허용
    if (_selectedYear < currentYear - 1) {
      _selectedYear = currentYear - 1;
    } else if (_selectedYear > currentYear) {
      _selectedYear = currentYear;
    }

    _selectedMonth = widget.initialMonth ?? now.month;
    // 현재 연도인 경우: 현재 월 이전만 허용
    if (_selectedYear == currentYear) {
      _selectedMonth = _selectedMonth.clamp(1, now.month);
    } else {
      _selectedMonth = _selectedMonth.clamp(1, 12);
    }

    // ✅ 월 기준 주차로 초기화 (연도 주차(1~53)를 그대로 쓰면 1월/경계에서 +1 밀려 보일 수 있음)
    _selectedWeek = widget.initialWeek ?? WeekUtils.getWeekOfMonth(now);
    // 주차 범위 검증: 현재 시점 이전만 허용
    if (_selectedYear == currentYear && _selectedMonth == now.month) {
      final currentWeek = WeekUtils.getWeekOfMonth(now);
      final maxWeek = currentWeek.clamp(1, 4);
      _selectedWeek = _selectedWeek.clamp(1, maxWeek);
    } else {
      _selectedWeek = _selectedWeek.clamp(1, 4);
    }

    // 초기 인덱스 계산
    final yearIndex = _yearItems.indexOf(_selectedYear);
    final monthIndex = _selectedMonth - 1;
    final weekIndex = _selectedWeek - 1;

    _yearController = FixedExtentScrollController(
      initialItem: yearIndex >= 0 ? yearIndex : 0,
    );
    _monthController = FixedExtentScrollController(initialItem: monthIndex);
    _weekController = FixedExtentScrollController(initialItem: weekIndex);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _weekController.dispose();
    super.dispose();
  }

  void _handleComplete() {
    // 선택한 year, month, week를 기반으로 yearOfWeek 계산
    // 해당 연도의 해당 주차에 해당하는 주의 시작일 계산
    final weekStartDate = WeekUtils.getWeekStartDateOfMonth(
      _selectedYear,
      _selectedMonth,
      _selectedWeek,
    );

    // 해당 날짜가 속한 실제 주차 계산 (1-53 범위, 연도 경계 고려)
    final yearOfWeek = WeekUtils.getWeekNumber(weekStartDate);

    // 수정 모드인 경우 콜백 호출하고 pop
    if (widget.isEditting) {
      widget.onDateSelected?.call(_selectedYear, yearOfWeek);
      Navigator.of(
        context,
      ).pop({'year': _selectedYear, 'yearOfWeek': yearOfWeek});
      return;
    }

    // 일반 모드: PostwriteScreen으로 pushReplacement
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (context) => PostwriteScreen(
              initialYear: _selectedYear,
              initialYearOfWeek: yearOfWeek,
            ),
      ),
    );
  }

  /// 수정 모드에서 원래 데이터와 같은지 확인
  bool _isSameAsOriginal() {
    if (!widget.isEditting || widget.initialYear == null) {
      return false;
    }

    // 원래 yearOfWeek 계산
    final originalWeekStartDate = WeekUtils.getWeekStartDate(
      widget.initialYear!,
      widget.initialWeek ?? 1,
    );
    final originalYearOfWeek = WeekUtils.getWeekNumber(originalWeekStartDate);

    // 현재 선택한 yearOfWeek 계산
    final currentWeekStartDate = WeekUtils.getWeekStartDate(
      _selectedYear,
      _selectedWeek,
    );
    final currentYearOfWeek = WeekUtils.getWeekNumber(currentWeekStartDate);

    // 연도와 주차가 모두 같으면 true
    return widget.initialYear == _selectedYear &&
        originalYearOfWeek == currentYearOfWeek;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading:
            widget.isEditting
                ? null
                : IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios,
                    color: colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
        title: Text(
          "지나간 주차 채우기",
          style: LocaleTypography.style(
            context: context,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: widget.isEditting ? false : true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 연도 선택
                  Expanded(
                    child: Stack(
                      children: [
                        CupertinoPicker(
                          scrollController: _yearController,
                          itemExtent: 60,
                          diameterRatio: 0.8,
                          useMagnifier: false,
                          onSelectedItemChanged: (index) {
                            final newYear = _yearItems[index];
                            if (newYear != _selectedYear) {
                              final now = DateTime.now();
                              final currentYear = now.year;
                              final currentMonth = now.month;

                              setState(() {
                                _selectedYear = newYear;

                                // 연도가 변경되면 월과 주차도 재계산
                                if (newYear == currentYear) {
                                  // 현재 연도로 변경: 현재 월 이전만 허용
                                  if (_selectedMonth > currentMonth) {
                                    _selectedMonth = currentMonth;
                                  }
                                  // 월 컨트롤러 재생성
                                  _monthController.dispose();
                                  _monthController =
                                      FixedExtentScrollController(
                                        initialItem: (_selectedMonth - 1).clamp(
                                          0,
                                          currentMonth - 1,
                                        ),
                                      );
                                } else {
                                  // 이전 연도로 변경: 모든 월 허용
                                  _monthController.dispose();
                                  _monthController =
                                      FixedExtentScrollController(
                                        initialItem: (_selectedMonth - 1).clamp(
                                          0,
                                          11,
                                        ),
                                      );
                                }

                                // 주차 재계산
                                if (newYear == currentYear &&
                                    _selectedMonth == currentMonth) {
                                  final currentWeek = WeekUtils.getWeekNumber(
                                    now,
                                  );
                                  final maxWeek = currentWeek.clamp(1, 4);
                                  _selectedWeek = _selectedWeek.clamp(
                                    1,
                                    maxWeek,
                                  );
                                } else {
                                  _selectedWeek = _selectedWeek.clamp(1, 4);
                                }

                                // 주차 컨트롤러 재생성
                                final weekItems = _weekItems;
                                _weekController.dispose();
                                _weekController = FixedExtentScrollController(
                                  initialItem: (weekItems.indexOf(
                                    _selectedWeek,
                                  )).clamp(0, weekItems.length - 1),
                                );
                              });
                            }
                          },
                          children:
                              _yearItems.map((year) {
                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),

                                    child: Text(
                                      '$year',
                                      style: LocaleTypography.style(
                                        context: context,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        // 고정된 "년" 텍스트 (박스 밖)
                        Positioned(
                          right: 20,
                          top: 0,
                          bottom: 2,
                          child: Center(
                            child: Text(
                              context.tr('year'),
                              style: LocaleTypography.style(
                                context: context,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 월 선택
                  Expanded(
                    child: Stack(
                      children: [
                        CupertinoPicker(
                          scrollController: _monthController,
                          itemExtent: 60,
                          diameterRatio: 0.8,
                          useMagnifier: false,
                          onSelectedItemChanged: (index) {
                            final newMonth = _monthItems[index];
                            if (newMonth != _selectedMonth) {
                              final now = DateTime.now();
                              final currentYear = now.year;
                              final currentMonth = now.month;

                              setState(() {
                                _selectedMonth = newMonth;

                                // 주차 재계산
                                if (_selectedYear == currentYear &&
                                    newMonth == currentMonth) {
                                  final currentWeek = WeekUtils.getWeekNumber(
                                    now,
                                  );
                                  final maxWeek = currentWeek.clamp(1, 4);
                                  if (_selectedWeek > maxWeek) {
                                    _selectedWeek = maxWeek;
                                  }
                                } else {
                                  _selectedWeek = _selectedWeek.clamp(1, 4);
                                }

                                // 주차 컨트롤러 재생성
                                final weekItems = _weekItems;
                                _weekController.dispose();
                                _weekController = FixedExtentScrollController(
                                  initialItem: (weekItems.indexOf(
                                    _selectedWeek,
                                  )).clamp(0, weekItems.length - 1),
                                );
                              });
                            }
                          },
                          children:
                              _monthItems.map((month) {
                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),

                                    child: Text(
                                      '$month',
                                      style: LocaleTypography.style(
                                        context: context,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        // 고정된 "월" 텍스트 (박스 밖)
                        Positioned(
                          right: 20,
                          top: 0,
                          bottom: 2,
                          child: Center(
                            child: Text(
                              context.tr('month'),
                              style: LocaleTypography.style(
                                context: context,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 주차 선택
                  Expanded(
                    child: Stack(
                      children: [
                        CupertinoPicker(
                          scrollController: _weekController,
                          itemExtent: 60,
                          diameterRatio: 0.8,
                          useMagnifier: false,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedWeek = _weekItems[index];
                            });
                          },
                          children:
                              _weekItems.map((week) {
                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),

                                    child: Text(
                                      '$week',
                                      style: LocaleTypography.style(
                                        context: context,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        // 고정된 "주차" 텍스트 (박스 밖)
                        Positioned(
                          right: 20,
                          top: 0,
                          bottom: 2,
                          child: Center(
                            child: Text(
                              context.tr('week'),
                              style: LocaleTypography.style(
                                context: context,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
          child: ElevatedButton(
            onPressed: _isSameAsOriginal() ? null : _handleComplete,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isSameAsOriginal()
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3)
                      : Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.background,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              !widget.isEditting
                  ? context.tr('write')
                  : context.tr('modify_complete'),
              style: LocaleTypography.style(
                context: context,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
