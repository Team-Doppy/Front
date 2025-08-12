import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';
import 'fixed_underline_tab_indicator.dart';

class SearchTabBar extends StatelessWidget {
  const SearchTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: 46,
        child: TabBar(
          dividerColor: Colors.transparent, // 기본 하단선 제거
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black,
          labelStyle: AppTextStyles.withWeight(
            AppTextStyles.headlineMedium,
            FontWeight.w600,
          ),
          unselectedLabelStyle: AppTextStyles.withWeight(
            AppTextStyles.headlineMedium,
            FontWeight.w600,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 32),
          indicator: FixedUnderlineTabIndicator(
            color: Colors.black,
            thickness: 2.0,
            bottomInset: 0.0,
            screenWidth: w,
            fraction: 0.375, // 화면 너비의 37.5%
          ),
          tabs: const [Tab(text: '계정'), Tab(text: '게시글')],
        ),
      ),
    );
  }
}
