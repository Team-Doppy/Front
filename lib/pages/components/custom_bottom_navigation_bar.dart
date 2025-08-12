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

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return; // 같은 탭 재탭 시 무시

    switch (index) {
      case 0:
        // 홈
        Navigator.of(context).pushReplacementNamed('/home');
        break;
      case 1:
        // 검색
        Navigator.of(context).pushReplacementNamed('/search');
        break;
      case 2:
        // 작성: 내부 라우팅이 없다면 콜백으로 처리(예: 글쓰기 모달/페이지)
        onTap(index);
        return;
      case 3:
        // 프로필
        Navigator.of(context).pushReplacementNamed('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 아이콘 에셋 경로
    const iconAssets = [
      'assets/icons/ic_home.svg',
      'assets/icons/ic_search.svg',
      'assets/icons/ic_write.svg',
      'assets/icons/ic_profile.svg',
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
          final iconColor = currentIndex == index ? Colors.black : Colors.grey;

          return Expanded(
            child: InkWell(
              onTap: () => _handleTap(context, index),
              child: Center(
                child: SvgPicture.asset(
                  iconAssets[index],
                  width: iconSize,
                  height: iconSize,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
