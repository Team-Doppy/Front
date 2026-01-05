import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/email_verification_flow.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';

class EmailVerificationScreen extends StatelessWidget {
  final String? initialEmail;
  const EmailVerificationScreen({super.key, this.initialEmail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 24,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: EmailVerificationFlow(
        title: context.tr('email_verification_title'),
        subtitle: context.tr('email_verification_subtitle'),
        initialEmail: initialEmail,
        enabledEmailEdit: true,
        onVerified: (email) async {
          // 🎯 API 문서에 따라: verify-code 성공 후 update-email API 호출
          // 이메일을 DB에 저장하고 새 토큰(이메일 포함)을 발급받음
          final authService = AuthService();
          final result = await authService.updateEmail(email: email);

          if (!context.mounted) return;

          if (result == null) {
            // 이메일 업데이트 실패 시 에러 표시
            ErrorHandler.showError(
              context,
              context.tr('email_verification_update_failed'),
            );
            return;
          }

          // 성공: 새 토큰이 저장되었고, 이메일이 DB에 반영됨
          // 홈으로: Splash를 다시 밟아서 동일한 부트스트랩 경로로 진입
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const SplashScreen(),
              transitionDuration: const Duration(milliseconds: 250),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOut,
                  ),
                  child: child,
                );
              },
            ),
            (route) => false,
          );
        },
      ),
    );
  }
}
