import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              context.tr('select_language'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LanguageOption(
                  language: '한국어',
                  isSelected: context.read<LocaleProvider>().isKorean,
                  onTap: () {
                    context.read<LocaleProvider>().setKorean();
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 8),
                _LanguageOption(
                  language: 'English',
                  isSelected: context.read<LocaleProvider>().isEnglish,
                  onTap: () {
                    context.read<LocaleProvider>().setEnglish();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Theme.of(context).colorScheme.onBackground,
            size: 20,
          ),
        ),

        centerTitle: true,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onBackground,
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          // 메뉴 리스트
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _SettingTile(
                  icon: Icons.notifications_none,
                  label: context.tr('notification_settings'),
                  onTap: () {},
                ),
                _SettingTile(
                  icon: Icons.language,
                  label: context.tr('language_settings'),
                  trailing: Text(
                    context.read<LocaleProvider>().isKorean ? '한국어' : 'English',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  onTap: () async {
                    // 언어 토글
                    await context.read<LocaleProvider>().toggleLocale();

                    // 변경된 region으로 서버에 업데이트 (로그인된 경우)
                    final authProvider = context.read<AuthProvider>();
                    if (authProvider.isLoggedIn &&
                        authProvider.username != null) {
                      final newRegion =
                          context.read<LocaleProvider>().regionCode;
                      // region 업데이트 API 호출 (필요시 구현)

                      await AuthProvider().updateUserRegionAndRefreshToken(
                        newRegion,
                      );
                      print('[SettingScreen] 언어 변경: region = $newRegion');
                    }
                  },
                ),
                _SettingTile(
                  icon: Icons.brightness_6,
                  label: context.tr('theme_settings'),
                  onTap: () {
                    context.read<ThemeProvider>().toggleTheme();
                  },
                ),
                _SettingTile(
                  icon: Icons.favorite_border,
                  label: context.tr('favorites'),
                  onTap: () {},
                ),
                _SettingTile(
                  icon: Icons.description_outlined,
                  label: context.tr('terms_of_service'),
                  onTap: () {},
                ),
                const SizedBox(height: 16),
                // 로그아웃은 하단에 강조
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.logout),
                    label: Text(
                      context.tr('logout'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    onPressed: () async {
                      await AuthProvider().logout();
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF181818) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
            child: Row(
              children: [
                Icon(icon, size: 26, color: Colors.grey[500]),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
                if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                language,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color:
                      isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
