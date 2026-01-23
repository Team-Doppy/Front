import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/providers/user_provider.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  /// 현재 선택된 인덱스 (0: 홈, 1: 검색, 2: 작성, 3: 프로필)
  final int currentIndex;

  /// 인덱스가 탭될 때 호출되는 콜백 (작성 버튼 등 화면 전환 외 동작용)
  final ValueChanged<int> onTap;

  /// 검색 중인지 여부 (검색 중일 때 검색 아이콘을 primary 색상으로 표시)
  final bool isSearching;

  /// 실제 화면 인덱스 (배경색 결정용, currentIndex와 다를 수 있음)
  final int? actualIndex;

  /// 🎯 강제로 배경 불투명하게 (검색 화면용)
  final bool forceOpaqueBackground;

  const CustomBottomNavigationBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.isSearching = false,
    this.actualIndex,
    this.forceOpaqueBackground = false,
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

    // 🎯 안드로이드 시스템 내비게이션 바 높이 가져오기
    final systemNavBarHeight = MediaQuery.of(context).viewPadding.bottom;
    final baseHeight = 50.0;
    final totalHeight = baseHeight + systemNavBarHeight;

    return Container(
      height: totalHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: systemNavBarHeight, // 시스템 바 높이만큼 추가 패딩
          top: 12,
          right: 10,
          left: 10,
        ),
        child: Row(
          children: List.generate(4, (index) {
            // index 3 (프로필)은 CommonProfileAvatar 사용
            if (index == 3) {
              return Expanded(
                child: Consumer<UserProvider>(
                  builder: (context, userProvider, _) {
                    final currentUser = userProvider.currentUser;
                    final profileImageUrl = currentUser?.profileImageUrl;
                    final username = currentUser?.username ?? '';

                    return GestureDetector(
                      onTap: () => onTap(index),
                      behavior: HitTestBehavior.translucent,
                      child: Center(
                        child: CommonProfileAvatar(
                          imageUrl: profileImageUrl,
                          username: username,
                          size: 32.0,
                          borderWidth: profileImageUrl == null ? 3 : 1,
                          borderColor:
                              Theme.of(context).colorScheme.surfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              );
            }

            // 나머지 아이콘들은 기존 SVG 사용
            var iconSize = 28.0;
            if (index == 0) {
              iconSize = 25.0;
            }

            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(index),
                behavior: HitTestBehavior.translucent,
                child: Center(
                  child: SvgPicture.asset(
                    iconAssets[index],
                    width: iconSize,
                    height: iconSize,
                    color:
                        // 현재 선택된 아이콘만 primary, 나머지는 기본 색상
                        index == currentIndex
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
