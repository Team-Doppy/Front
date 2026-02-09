import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:async';

/// 역할 선택 옵션
class _UserTypeOption {
  final String label;
  final UserType type;
  final bool isPlanned;

  _UserTypeOption({
    required this.label,
    required this.type,
    this.isPlanned = false,
  });
}

/// 사용자 타입 선택 단계 (CupertinoPicker)
class MilitaryUserTypeSelectionStep extends StatefulWidget {
  final UserType? initialUserType;
  final bool? initialIsPlanned;
  final Function(UserType, bool isPlanned) onUserTypeSelected;
  final VoidCallback? onConfirm;

  const MilitaryUserTypeSelectionStep({
    super.key,
    this.initialUserType,
    this.initialIsPlanned,
    required this.onUserTypeSelected,
    this.onConfirm,
  });

  @override
  State<MilitaryUserTypeSelectionStep> createState() =>
      _MilitaryUserTypeSelectionStepState();
}

class _MilitaryUserTypeSelectionStepState
    extends State<MilitaryUserTypeSelectionStep>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static final List<_UserTypeOption> _options = [
    _UserTypeOption(label: '군인입니다', type: UserType.military, isPlanned: false),
    _UserTypeOption(
      label: '입대 예정이에요',
      type: UserType.plannedEnlistment,
      isPlanned: true,
    ),
    _UserTypeOption(label: '곰신이에요', type: UserType.girlfriend),
  ];

  // ✅ static 변수로 전역적으로 애니메이션 시작 여부 추적 (위젯 재생성과 무관)
  static bool _globalAnimationStarted = false;

  late int _selectedIndex;
  late FixedExtentScrollController _controller;
  late AnimationController _animationController;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleOffset;
  late Animation<double> _subtitleOpacity;
  late Animation<Offset> _subtitleOffset;
  bool _isAnimationComplete = false; // ✅ 애니메이션 완료 여부
  Timer? _selectionDebounce;

  @override
  bool get wantKeepAlive => true; // 위젯 상태 유지

  @override
  void initState() {
    super.initState();
    // 초기 선택 인덱스 찾기 (기본값: 입대 예정이에요)
    _selectedIndex = 1;
    if (widget.initialUserType != null) {
      final isPlanned = widget.initialIsPlanned ?? false;
      _selectedIndex = _options.indexWhere(
        (opt) =>
            opt.type == widget.initialUserType && opt.isPlanned == isPlanned,
      );
      if (_selectedIndex == -1) _selectedIndex = 1; // 기본값: 입대 예정이에요
    }
    _controller = FixedExtentScrollController(initialItem: _selectedIndex);

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

    // 애니메이션 시작 (한 번만 실행 - static 변수로 전역 추적)
    if (!_globalAnimationStarted && _animationController.value == 0.0) {
      _globalAnimationStarted = true;
      _animationController.forward().then((_) {
        if (!mounted) return;
        setState(() {
          _isAnimationComplete = true;
        });
      });
    } else if (_globalAnimationStarted || _animationController.value > 0.0) {
      // 이미 시작되었거나 진행 중인 경우 완료 상태로 스냅
      if (!_isAnimationComplete) {
        _animationController.value = 1.0;
        _isAnimationComplete = true;
      }
    }

    // 첫 번째 항목이 기본 선택되어 있으므로 자동으로 선택 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final option = _options[_selectedIndex];
      widget.onUserTypeSelected(option.type, option.isPlanned);
    });
  }

  @override
  void didUpdateWidget(covariant MilitaryUserTypeSelectionStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 위젯이 재생성되어도 애니메이션은 다시 시작하지 않음
    // static 변수로 이미 시작되었는지 확인
    if (_globalAnimationStarted &&
        !_isAnimationComplete &&
        !_animationController.isAnimating) {
      // 애니메이션이 시작되었지만 완료되지 않은 경우 완료 상태로 스냅
      _animationController.value = 1.0;
      if (mounted) {
        setState(() {
          _isAnimationComplete = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _selectionDebounce?.cancel();
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onSelectedItemChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
    final option = _options[index];
    // ✅ 스크롤 중에는 onSelectedItemChanged가 매우 자주 호출됨 → 상위 setState 남발로 끊김 발생
    // 짧게 디바운스해서 "스크롤이 잠깐 멈췄을 때"만 상위에 전달
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      widget.onUserTypeSelected(option.type, option.isPlanned);
    });
  }

  String _getButtonText() {
    final selectedOption = _options[_selectedIndex];
    switch (selectedOption.label) {
      case '곰신이에요':
        return '곰신으로 시작하기';
      case '군인입니다':
        return '군인으로 시작하기';
      case '입대 예정이에요':
        return '예비군인으로 시작하기';
      default:
        return '확인';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin을 위해 필요
    final hasSelection = true; // 항상 선택 가능

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 30),
                    // 타이틀 애니메이션 (완료 후에는 일반 위젯으로 전환하여 스크롤 성능 최적화)
                    _isAnimationComplete
                        ? Text(
                          '지금 어떤 입장인가요?',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 24,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                        : AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return SlideTransition(
                              position: _titleOffset,
                              child: FadeTransition(
                                opacity: _titleOpacity,
                                child: Text(
                                  '지금 어떤 입장인가요?',
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 24,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    const SizedBox(height: 12),
                    // 서브타이틀 애니메이션 (완료 후에는 일반 위젯으로 전환하여 스크롤 성능 최적화)
                    _isAnimationComplete
                        ? Text(
                          '당신의 역할에 맞게 기록이 정리돼요',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 16,
                            color: AppColors.darkTextSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        )
                        : AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return SlideTransition(
                              position: _subtitleOffset,
                              child: FadeTransition(
                                opacity: _subtitleOpacity,
                                child: Text(
                                  '당신의 역할에 맞게 기록이 정리돼요',
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 16,
                                    color: AppColors.darkTextSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    const SizedBox(height: 40),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: CupertinoPicker(
                        scrollController: _controller,
                        itemExtent: 100,
                        diameterRatio: 2.0,
                        useMagnifier: true,
                        magnification: 1.1,
                        squeeze: 1.0,
                        selectionOverlay: const SizedBox.shrink(),
                        onSelectedItemChanged: _onSelectedItemChanged,
                        children:
                            _options.asMap().entries.map((entry) {
                              final index = entry.key;
                              final option = entry.value;
                              final isSelected = index == _selectedIndex;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Center(
                                  child: Text(
                                    option.label,
                                    style: LocaleTypography.setStyle(
                                      context: context,
                                      fontSize: 24,
                                      fontWeight:
                                          isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w400,
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : AppColors
                                                  .darkTextSecondary, // 회색
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 하단 확인 버튼
            if (hasSelection && widget.onConfirm != null)
              Container(
                padding: EdgeInsets.only(
                  left: 50,
                  right: 50,
                  bottom: MediaQuery.of(context).padding.bottom,
                  top: 16,
                ),
                child: GestureDetector(
                  onTap: widget.onConfirm,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface, // 포인트 컬러
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getButtonText(),
                      textAlign: TextAlign.center,
                      style: LocaleTypography.setStyle(
                        context: context,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.surface,
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
