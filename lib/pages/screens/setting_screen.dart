import 'package:doppy/pages/screens/favorites_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/pages/components/account_deletion_confirm.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _notificationEnabled = true;
  bool _marketingEnabled = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.75),
            size: 24,
          ),
        ),

        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 사용자 정보
          _buildSection(
            context,
            title: context.tr('user_info'),
            surfaceColor: surfaceColor,
            children: [
              _SettingTile(
                icon: Icons.person_outline,
                label: context.tr('user_id'),
                trailing: Text(
                  authProvider.username ?? '-',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                onTap: () {},
              ),
              _SettingTile(
                icon: Icons.favorite_border,
                label: context.tr('favorites'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FavoritesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. 일반
          _buildSection(
            context,
            title: context.tr('general'),
            surfaceColor: surfaceColor,
            children: [
              _SettingTile(
                icon: Icons.notifications_outlined,
                label: context.tr('notification_settings'),
                trailing: Text(
                  _notificationEnabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _notificationEnabled = !_notificationEnabled;
                  });
                },
              ),
              _SettingTile(
                icon: Icons.campaign_outlined,
                label: context.tr('marketing_consent'),
                trailing: Text(
                  _marketingEnabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _marketingEnabled = !_marketingEnabled;
                  });
                },
              ),
              _SettingTile(
                icon: Icons.brightness_6_outlined,
                label: context.tr('theme_settings'),
                trailing: Text(
                  context.watch<ThemeProvider>().themeMode == ThemeMode.dark
                      ? context.tr('dark')
                      : context.tr('light'),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  context.read<ThemeProvider>().toggleTheme();
                },
              ),
              _SettingTile(
                icon: Icons.language_outlined,
                label: context.tr('language_settings'),
                trailing: Text(
                  context.watch<LocaleProvider>().isKorean ? '한국어' : 'English',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  await context.read<LocaleProvider>().toggleLocale();
                  final authProvider = context.read<AuthProvider>();
                  if (authProvider.isLoggedIn &&
                      authProvider.username != null) {
                    final newRegion = context.read<LocaleProvider>().regionCode;
                    try {
                      await AuthProvider().updateUserRegionAndRefreshToken(
                        newRegion,
                      );
                    } catch (e) {
                      print('[SettingScreen] Region 업데이트 에러 무시: $e');
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. 앱 정보
          _buildSection(
            context,
            title: context.tr('app_info'),
            surfaceColor: surfaceColor,
            children: [
              _SettingTile(
                icon: Icons.info_outline,
                label: context.tr('app_version'),
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. 기타
          _buildSection(
            context,
            title: context.tr('others'),
            surfaceColor: surfaceColor,
            children: [
              _SettingTile(
                icon: Icons.article_outlined,
                label: context.tr('license'),
                onTap: () {},
              ),
              _SettingTile(
                icon: Icons.description_outlined,
                label: context.tr('terms_of_service'),
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 5. 고객지원
          _buildSection(
            context,
            title: context.tr('customer_support'),
            surfaceColor: surfaceColor,
            children: [
              _SettingTile(
                icon: Icons.help_outline,
                label: context.tr('inquiry'),
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 6. 계정관리
          _buildSection(
            context,
            title: context.tr('account_management'),
            surfaceColor: surfaceColor,
            children: [
              _SettingTile(
                icon: Icons.logout,
                label: context.tr('logout'),
                onTap: () async {
                  final confirmed = await DialogUtils.showConfirmDialog(
                    context,
                    title: context.tr('logout'),
                    message: context.tr('logout_confirm'),
                    confirmText: context.tr('logout'),
                    cancelText: context.tr('cancel'),
                    isDestructive: false,
                  );

                  if (confirmed == true) {
                    await AuthProvider().logout();
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  }
                },
              ),
              _SettingTile(
                icon: Icons.person_remove_outlined,
                label: context.tr('delete_account'),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const AccountDeletionSheet(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Color surfaceColor,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.08);

    // 타일 사이에 구분선 추가
    final childrenWithDividers = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      childrenWithDividers.add(children[i]);
      if (i < children.length - 1) {
        childrenWithDividers.add(
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...childrenWithDividers,
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
