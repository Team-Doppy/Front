import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/typograpy_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

/// 홈 화면 헤더 (플래그 기반 표시/숨김 + opacity 애니메이션 + 탭 + 검색칩)
class HomeHeader extends StatelessWidget {
  final bool visible;

  final int selectedIndex;
  final ValueChanged<int>? onTabChanged;
  final VoidCallback? onMenuTap;

  /// 검색 결과 시 표시할 칩 (null이면 일반 타이틀)
  final String? searchChipQuery;
  final VoidCallback? onChipTap;
  final VoidCallback? onChipClose;

  /// 노드 드래그 시 등 서브타이틀 덮어쓰기 (null이면 기본 '기록하고 패턴 발견하기')
  final String? subtitleOverride;

  const HomeHeader({
    super.key,
    required this.visible,

    this.selectedIndex = 0,
    this.onTabChanged,
    this.onMenuTap,
    this.searchChipQuery,
    this.onChipTap,
    this.onChipClose,
    this.subtitleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final username = context.watch<UserProvider>().currentUser?.username;
    final title =
        (username != null && username.isNotEmpty) ? username : '나의 기록들';

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 24,
              right: 8,
              top: 16,
              bottom: 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (searchChipQuery != null &&
                          searchChipQuery!.isNotEmpty) ...[
                        GestureDetector(
                          onTap: onChipTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? AppColors.darkTextPrimary.withValues(
                                        alpha: 0.12,
                                      )
                                      : AppColors.lightTextPrimary.withValues(
                                        alpha: 0.1,
                                      ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 18,
                                  color:
                                      isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  searchChipQuery!,
                                  style: TypographyUtil.style(
                                    context: context,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isDark
                                            ? AppColors.darkTextPrimary
                                            : AppColors.lightTextPrimary,
                                  ),
                                ),
                                if (onChipClose != null) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: onChipClose,
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color:
                                          isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          title,
                          style: TypographyUtil.style(
                            context: context,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleOverride?.isNotEmpty == true
                              ? subtitleOverride!
                              : '기록하고 패턴 발견하기',
                          style: TypographyUtil.style(
                            context: context,
                            fontSize: 16,
                            color:
                                isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onMenuTap,
                  child: SvgPicture.asset(
                    'assets/icons/menu.svg',
                    width: 24,
                    height: 24,
                    color:
                        isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
