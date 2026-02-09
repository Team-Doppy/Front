import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 군인 정보 입력 - 군종 선택 단계
class MilitaryBranchStep extends StatefulWidget {
  final MilitaryBranch? initialBranch;
  final Function(MilitaryBranch) onBranchSelected;
  final VoidCallback? onConfirm;
  final VoidCallback? onBack;

  const MilitaryBranchStep({
    super.key,
    this.initialBranch,
    required this.onBranchSelected,
    this.onConfirm,
    this.onBack,
  });

  @override
  State<MilitaryBranchStep> createState() => _MilitaryBranchStepState();
}

class _MilitaryBranchStepState extends State<MilitaryBranchStep>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentPage;
  late AnimationController _animationController;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleOffset;
  late Animation<double> _subtitleOpacity;
  late Animation<Offset> _subtitleOffset;

  // 4개 군종만 표시 (기타 제외)
  static final List<MilitaryBranch> _branches = [
    MilitaryBranch.army,
    MilitaryBranch.navy,
    MilitaryBranch.airForce,
    MilitaryBranch.marines,
  ];

  String _getBranchImagePath(MilitaryBranch branch) {
    switch (branch) {
      case MilitaryBranch.army:
        return 'assets/images/army.png';
      case MilitaryBranch.navy:
        return 'assets/images/navy.png';
      case MilitaryBranch.airForce:
        return 'assets/images/airforce.png';
      case MilitaryBranch.marines:
        return 'assets/images/marin.png';
      default:
        return 'assets/images/army.png';
    }
  }

  @override
  void initState() {
    super.initState();
    final initialBranch = widget.initialBranch ?? MilitaryBranch.army;
    _currentPage = _branches.indexOf(initialBranch);
    if (_currentPage == -1) _currentPage = 0;
    _pageController = PageController(initialPage: _currentPage);

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

    // 첫 번째 항목이 기본 선택되어 있으므로 자동으로 선택 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedBranch = _branches[_currentPage];
      widget.onBranchSelected(selectedBranch);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    final selectedBranch = _branches[page];
    widget.onBranchSelected(selectedBranch);
  }

  String _getButtonText() {
    final selectedBranch = _branches[_currentPage];
    return '${selectedBranch.displayName}입니다';
  }

  void _onBranchTap(int index) {
    if (index < _branches.length - 1) {
      // 다음 페이지로 이동
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 마지막 페이지면 다음 단계로
      widget.onConfirm?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 30),
                  // 타이틀 애니메이션
                  SlideTransition(
                    position: _titleOffset,
                    child: FadeTransition(
                      opacity: _titleOpacity,
                      child: Text(
                        '어디에서 복무하나요?',
                        style: LocaleTypography.setStyle(
                          context: context,
                          fontSize: 24,
                          color: Theme.of(context).colorScheme.primary,
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
                        '당신의 군생활에 맞게 기록이 정리돼요',
                        style: LocaleTypography.setStyle(
                          context: context,
                          fontSize: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      itemCount: _branches.length,
                      itemBuilder: (context, index) {
                        final branch = _branches[index];
                        return GestureDetector(
                          onTap: () => _onBranchTap(index),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Image.asset(
                                    _getBranchImagePath(branch),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  branch.displayName,
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  // 페이지 인디케이터
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _branches.length,
                      (index) => Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _currentPage == index
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),
                ],
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
                onTap:
                    widget.onConfirm ??
                    () {
                      widget.onBranchSelected(_branches[_currentPage]);
                    },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface,
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
