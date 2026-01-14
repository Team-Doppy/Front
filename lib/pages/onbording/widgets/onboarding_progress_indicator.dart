import 'package:flutter/material.dart';

/// 온보딩 진행 표시기
/// 하단에 점으로 진행 상태를 표시하는 위젯
class OnboardingProgressIndicator extends StatelessWidget {
  final int currentPage;
  final int totalPages;

  const OnboardingProgressIndicator({
    super.key,
    required this.currentPage,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        totalPages,
        (index) => _buildDot(index == currentPage),
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color:
            isActive
                ? const Color(0xFF1A1A1A)
                : const Color(0xFF1A1A1A).withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
