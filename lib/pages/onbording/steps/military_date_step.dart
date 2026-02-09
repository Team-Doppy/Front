import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 군인 정보 입력 - 입대일/예정 입대일 선택 단계
class MilitaryDateStep extends StatefulWidget {
  final MilitaryStatus status;
  final DateTime? initialDate;
  final Function(DateTime) onDateSelected;
  final VoidCallback? onConfirm;
  final VoidCallback? onBack;

  const MilitaryDateStep({
    super.key,
    required this.status,
    this.initialDate,
    required this.onDateSelected,
    this.onConfirm,
    this.onBack,
  });

  @override
  State<MilitaryDateStep> createState() => _MilitaryDateStepState();
}

class _MilitaryDateStepState extends State<MilitaryDateStep>
    with SingleTickerProviderStateMixin {
  late DateTime _selectedDate;
  late DateTime? _minimumDate;
  late DateTime? _maximumDate;
  late AnimationController _animationController;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleOffset;
  late Animation<double> _subtitleOpacity;
  late Animation<Offset> _subtitleOffset;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final isBeforeEnlistment = widget.status == MilitaryStatus.beforeEnlistment;
    final initialDate = widget.initialDate ?? now;

    // minimumDate와 maximumDate를 한 번만 계산하여 저장
    if (isBeforeEnlistment) {
      // 입대 예정: 오늘 날짜를 minimumDate로 설정 (시간 제거)
      _minimumDate = DateTime(now.year, now.month, now.day);
      _maximumDate = null;
    } else {
      _minimumDate = null;
      // 입대 후: 오늘 날짜를 maximumDate로 설정 (시간 제거)
      _maximumDate = DateTime(now.year, now.month, now.day);
    }

    // 초기 날짜 설정 (minimumDate/maximumDate를 고려)
    if (isBeforeEnlistment) {
      // 입대 예정: minimumDate 이후로 설정 (미래 날짜)
      if (_minimumDate != null) {
        final initialDateOnly = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
        if (initialDateOnly.isBefore(_minimumDate!)) {
          _selectedDate = _minimumDate!;
        } else {
          _selectedDate = initialDateOnly;
        }
      } else {
        _selectedDate = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
      }
    } else {
      // 입대 후: maximumDate 이전으로 설정 (과거 날짜)
      if (_maximumDate != null) {
        final initialDateOnly = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
        if (initialDateOnly.isAfter(_maximumDate!)) {
          _selectedDate = _maximumDate!;
        } else {
          _selectedDate = initialDateOnly;
        }
      } else {
        _selectedDate = DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
        );
      }
    }

    // 최종 검증: _selectedDate가 minimumDate보다 크거나 같아야 함
    if (_minimumDate != null && _selectedDate.isBefore(_minimumDate!)) {
      _selectedDate = _minimumDate!;
    }

    // 애니메이션 초기화
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _titleOffset = Tween<Offset>(
      begin: const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleOffset = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    // 애니메이션 시작
    _animationController.forward();

    // 초기 날짜가 기본 선택되어 있으므로 자동으로 선택 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onDateSelected(_selectedDate);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBeforeEnlistment = widget.status == MilitaryStatus.beforeEnlistment;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // 뒤로가기 버튼
            if (widget.onBack != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    color: colorScheme.onSurface,
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 타이틀 애니메이션
                    SlideTransition(
                      position: _titleOffset,
                      child: FadeTransition(
                        opacity: _titleOpacity,
                        child: Text(
                          isBeforeEnlistment ? '입대 예정일을 알려주세요' : '언제 입대했나요?',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 24,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 서브타이틀 애니메이션
                    SlideTransition(
                      position: _subtitleOffset,
                      child: FadeTransition(
                        opacity: _subtitleOpacity,
                        child: Text(
                          '주차 기록을 계산하는 데 사용돼요',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 16,
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      height: 250,
                      child: CupertinoDatePicker(
                        initialDateTime: _selectedDate,
                        mode: CupertinoDatePickerMode.date,
                        minimumDate: _minimumDate,
                        maximumDate: _maximumDate,
                        onDateTimeChanged: (date) {
                          setState(() {
                            _selectedDate = date;
                          });
                          widget.onDateSelected(date);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 하단 확인 버튼
            Container(
              padding: EdgeInsets.only(
                left: 50,
                right: 50,
                bottom: MediaQuery.of(context).padding.bottom,
                top: 16,
              ),
              child: GestureDetector(
                onTap: () {
                  // 확인 버튼 클릭 시 현재 선택된 날짜를 저장하고 다음으로 진행
                  widget.onDateSelected(_selectedDate);
                  widget.onConfirm?.call();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '확인',
                    textAlign: TextAlign.center,
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
