import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/pages/screens/favorites_screen.dart';
import 'package:doppy/pages/components/license_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/pages/components/account_deletion_confirm.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/main.dart' show AppConstants;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _notificationEnabled = true;
  bool _marketingEnabled = false;

  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _userService.getSettings();
      if (mounted) {
        setState(() {
          _notificationEnabled = settings['notificationEnabled'] ?? true;
          _marketingEnabled = settings['marketingConsent'] ?? false;
        });
      }
    } catch (e) {
      print('[SettingScreen] 설정 로드 실패: $e');
    }
  }

  Future<void> _toggleNotification() async {
    // 낙관적 업데이트
    final oldValue = _notificationEnabled;
    setState(() {
      _notificationEnabled = !_notificationEnabled;
    });

    try {
      final newValue = await _userService.toggleNotificationEnabled();
      // 서버 응답으로 최종 확인
      if (mounted) {
        setState(() {
          _notificationEnabled = newValue;
        });
      }

      // 🎯 알림을 켠 경우, FCM 토큰/디바이스 정보도 서버와 동기화
      if (newValue) {
        try {
          final authService = AuthService();
          await authService.syncFcmTokenAndSettings();

          // syncFcmTokenAndSettings 안에서 권한 거부 상태면
          // 서버 플래그가 다시 OFF로 동기화되므로, UI도 맞춰줌
          final settings = await _userService.getSettings();
          final serverNotificationEnabled =
              settings['notificationEnabled'] ?? false;

          if (mounted && !serverNotificationEnabled) {
            // 서버가 다시 false로 내려왔다는 것은 여전히 권한이 없다는 의미
            setState(() {
              _notificationEnabled = false;
            });

            final l10n = AppLocalizations.of(context);
            final goToSettings = await DialogUtils.showConfirmDialog(
              context,
              title: l10n.t('notification_permission_required_title'),
              message: l10n.t('notification_permission_required_message'),
              confirmText: l10n.t('open_settings'),
              cancelText: l10n.t('cancel'),
            );

            if (goToSettings == true) {
              await openAppSettings();
            }
          }
        } catch (e) {
          print('[SettingScreen] FCM 동기화 실패 (알림 ON): $e');
        }
      }
    } catch (e) {
      print('[SettingScreen] 알림 토글 실패: $e');
      // 롤백
      if (mounted) {
        setState(() {
          _notificationEnabled = oldValue;
        });
      }
    }
  }

  Future<void> _toggleMarketing() async {
    // 낙관적 업데이트
    final oldValue = _marketingEnabled;
    setState(() {
      _marketingEnabled = !_marketingEnabled;
    });

    try {
      final newValue = await _userService.toggleMarketingConsent();
      // 서버 응답으로 최종 확인
      if (mounted) {
        setState(() {
          _marketingEnabled = newValue;
        });
      }
    } catch (e) {
      print('[SettingScreen] 마케팅 토글 실패: $e');
      // 롤백
      if (mounted) {
        setState(() {
          _marketingEnabled = oldValue;
        });
      }
    }
  }

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
                showArrow: false,
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
                onTap: _toggleNotification,
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
                onTap: _toggleMarketing,
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
                  AppConstants.appVersion,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                showArrow: false,
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LicenseScreen(),
                    ),
                  );
                },
              ),
              _SettingTile(
                icon: Icons.description_outlined,
                label: context.tr('terms_of_service'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => WebViewScreen(
                            url: AppConstants.termsOfServiceUrl,
                            title: context.tr('terms_of_service'),
                          ),
                    ),
                  );
                },
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
                onTap: () async {
                  final Uri emailUri = Uri(
                    scheme: 'mailto',
                    path: 'support@doppy.app',
                    query: 'subject=Doppy 문의&body=',
                  );

                  if (await canLaunchUrl(emailUri)) {
                    await launchUrl(emailUri);
                  } else {
                    // 이메일 앱이 없으면 웹 Gmail로 대체
                    if (context.mounted) {
                      final gmailWebUrl = Uri.parse(
                        'https://mail.google.com/mail/?view=cm&fs=1&to=support@doppy.app&su=Doppy 문의',
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => WebViewScreen(
                                url: gmailWebUrl.toString(),
                                title: context.tr('inquiry'),
                              ),
                        ),
                      );
                    }
                  }
                },
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
  final bool showArrow;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.showArrow = true,
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
            if (showArrow)
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

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebViewScreen({super.key, required this.url, required this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) {
                setState(() {
                  _isLoading = true;
                });
              },
              onPageFinished: (url) {
                setState(() {
                  _isLoading = false;
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.75),
            size: 24,
          ),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const DoppyLoadingLogo(),
        ],
      ),
    );
  }
}
