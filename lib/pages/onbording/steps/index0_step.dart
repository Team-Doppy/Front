import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Index 0: card + background (임시 구조)
class Index0CardContent extends StatelessWidget {
  const Index0CardContent({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO(user): replace with real UI
    return Center(
      child: Text(
        context.tr('onboarding_swipe_to_start'),
        style: LocaleTypography.setStyle(
          context: context,
          fontSize: 36,
          color: Colors.white,
          letterSpacing: -1.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class Index0Background extends StatelessWidget {
  final String name;
  const Index0Background({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Container(
          padding: EdgeInsets.all(24),
          color: Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 30),
                  Text(
                    '${name}',
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 30,
                      color: AppColors.darkSurfaceVariant.withOpacity(0.9),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('onboarding_welcome_message'),
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 30,
                      color: AppColors.darkSurfaceVariant.withOpacity(0.9),
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
