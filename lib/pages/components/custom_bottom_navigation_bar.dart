import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  /// 현재 선택된 인덱스 (0: 홈, 1: 검색, 2: 작성, 3: 프로필)
  final int currentIndex;

  /// 인덱스가 탭될 때 호출되는 콜백 (작성 버튼 등 화면 전환 외 동작용)
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
      'assets/icons/ic_home.svg',
      'assets/icons/ic_search.svg',
      'assets/icons/ic_write.svg',
      'assets/icons/ic_profile.svg',
    ];

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 30, top: 10),
          child: Row(
            children: List.generate(4, (index) {
              var iconSize = 28.0;
              if (index == 3) {
                iconSize = 32.0;
              }

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  child: Center(
                    child: SvgPicture.asset(
                      iconAssets[index],
                      width: iconSize,
                      height: iconSize,
                      color:
                          index == currentIndex
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
