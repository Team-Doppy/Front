import 'package:doppy/main.dart' show AppConstants;
import 'package:doppy/provider/theme_provider.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/typograpy_util.dart';
import 'package:doppy/editor/utils/dialog_util.dart';
import 'package:doppy/widgets/accout_delete_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    final sectionBgColor = Theme.of(
      context,
    ).colorScheme.surfaceVariant.withOpacity(0.5);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.75),
            size: 24,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '설정 및 지원',
              style: TypographyUtil.style(
                context: context,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 1. 사용자 정보
          _buildSection(
            context,
            title: '사용자 정보',
            surfaceColor: sectionBgColor,
            children: [
              _SettingTile(
                icon: SvgPicture.asset(
                  'assets/icons/ic_profile.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '내 계정',
                trailing: Text(
                  authProvider.username ?? '-',
                  style: TextStyle(
                    fontSize: 17,

                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                showArrow: false,
                onTap: () {},
              ),
              _SettingTile(
                showArrow: false,
                icon: SvgPicture.asset(
                  'assets/icons/card.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '내 플랜',
                trailing: Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 17,

                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: () {},
              ),
              _SettingTile(
                icon: SvgPicture.asset(
                  'assets/icons/lock.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '비밀번호 변경',

                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 2. 일반
          _buildSection(
            context,
            title: '일반',
            surfaceColor: sectionBgColor,
            children: [
              _SettingTile(
                icon: SvgPicture.asset(
                  'assets/icons/moon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '테마',
                trailing: Text(
                  context.watch<ThemeProvider>().themeMode == ThemeMode.dark
                      ? '다크'
                      : '라이트',
                  style: TextStyle(fontSize: 17, color: AppColors.primary),
                ),
                onTap: () {
                  context.read<ThemeProvider>().toggleTheme();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 3. 앱 정보
          _buildSection(
            context,
            title: '앱 정보',
            surfaceColor: sectionBgColor,
            children: [
              _SettingTile(
                icon: Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
                label: '앱 버전',
                trailing: Text(
                  AppConstants.appVersion,
                  style: TextStyle(
                    fontSize: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                showArrow: false,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 4. 기타
          _buildSection(
            context,
            title: '기타',
            surfaceColor: sectionBgColor,
            children: [
              _SettingTile(
                icon: SvgPicture.asset(
                  'assets/icons/license.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '라이선스',
                onTap: () {
                  showLicensePage(context: context, applicationName: 'Doppy');
                },
              ),
              _SettingTile(
                icon: SvgPicture.asset(
                  'assets/icons/paper.svg',
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '이용약관',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => WebViewScreen(
                            url: AppConstants.termsOfServiceUrl,
                            title: '이용약관',
                          ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 5. 고객지원
          _buildSection(
            context,
            title: '고객지원',
            surfaceColor: sectionBgColor,
            children: [
              _SettingTile(
                icon: Icon(
                  Icons.help_outline,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
                label: '문의하기',
                onTap: () async {
                  final Uri emailUri = Uri(
                    scheme: 'mailto',
                    path: AppConstants.contactEmail,
                    query: 'subject=Doppy 문의&body=',
                  );
                  if (await canLaunchUrl(emailUri)) {
                    await launchUrl(emailUri);
                  } else {
                    if (context.mounted) {
                      final gmailWebUrl = Uri.parse(
                        'https://mail.google.com/mail/?view=cm&fs=1&to=${AppConstants.contactEmail}&su=Doppy 문의',
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => WebViewScreen(
                                url: gmailWebUrl.toString(),
                                title: '문의하기',
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
            title: '계정관리',
            surfaceColor: sectionBgColor,
            children: [
              _SettingTile(
                icon: Icon(
                  Icons.logout,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
                label: '로그아웃',
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          title: const Text('로그아웃'),
                          content: const Text('로그아웃 하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('로그아웃'),
                            ),
                          ],
                        ),
                  );
                  if (confirmed == true && context.mounted) {
                    await AuthProvider().logout();
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    }
                  }
                },
              ),
              _SettingTile(
                icon: SvgPicture.asset(
                  'assets/icons/delete.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    BlendMode.srcIn,
                  ),
                ),
                label: '계정 삭제',
                onTap: () async {
                  final result = await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => const AccountDeletionSheet(),
                  );
                  if (result == null || result['reason'] == null) return;
                  final confirmed = await DialogUtils.showConfirmDialog(
                    context,
                    title: '회원 탈퇴',
                    message:
                        '한 번 탈퇴하면 복구할 수 없습니다. 그래도 탈퇴하시겠습니까?',
                    confirmText: '탈퇴하기',
                    cancelText: '취소',
                    isDestructive: true,
                  );
                  if (confirmed == true) {
                    await AccountDeletionSheet.performDeletionAndNavigate(
                      context,
                      reasonKey: result['reason'] as String,
                      detail: result['detail'] as String?,
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
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
    final childrenWithDividers = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      childrenWithDividers.add(children[i]);
      if (i < children.length - 1) {
        childrenWithDividers.add(
          const Padding(
            padding: EdgeInsets.only(left: 58),
            child: Divider(height: 1, thickness: 1, color: Colors.transparent),
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              title,
              style: TypographyUtil.style(
                context: context,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.75),
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
  final Widget icon;
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
    final isDisabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: icon,
              ),
              const SizedBox(width: 8),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                  size: 20,
                ),
            ],
          ),
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

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(onPageStarted: (_) {}, onPageFinished: (_) {}),
          )
          ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
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
      body: Stack(children: [WebViewWidget(controller: _controller)]),
    );
  }
}
