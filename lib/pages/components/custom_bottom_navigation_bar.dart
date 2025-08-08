// lib/pages/components/custom_bottom_navigation_bar.dart
import 'package:flutter/material.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  /// 현재 선택된 인덱스 (0: 홈, 1: 검색, 2: 작성, 3: 프로필)
  final int currentIndex;

  /// 인덱스가 탭될 때 호출되는 콜백
  final ValueChanged<int> onTap;

  const CustomBottomNavigationBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 아이콘 에셋 경로
    const iconAssets = [
      'assets/images/home_icon.png',
      'assets/images/search_icon.png',
      'assets/images/write_icon.png',
      'assets/images/profile_icon_bar.png',
    ];

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(width: 1, color: Color(0x7FD9D9D9))),
      ),
      child: Row(
        children: List.generate(4, (index) {
          final isProfile = index == 3;
          final iconSize = isProfile ? 26.0 : 24.0;
          // 선택된 탭이면 검정, 아니면 회색
          final iconColor = currentIndex == index ? Colors.black : Colors.grey;

          return Expanded(
            child: InkWell(
              onTap: () => onTap(index),
              child: Center(
                child: Image.asset(
                  iconAssets[index],
                  width: iconSize,
                  height: iconSize,
                  color: iconColor,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
