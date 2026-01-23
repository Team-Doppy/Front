import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Index 3: card + background (임시 구조)
class Index3CardContent extends StatelessWidget {
  const Index3CardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.tr('onboarding_swipe_to_record'),
            style: LocaleTypography.setStyle(
              context: context,
              fontSize: 36,
              color: AppColors.darkTextPrimary.withOpacity(0.9),
              fontWeight: FontWeight.w900,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class Index3Background extends StatelessWidget {
  const Index3Background({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO(user): replace with real UI (현재 welcome text 같은 것)
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
                    context.tr('onboarding_if_passed'),
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 30,
                      color: AppColors.lightSurfaceVariant.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                  Text(
                    context.tr('onboarding_wont_come_again'),
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 30,
                      color: AppColors.lightSurfaceVariant.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                      height: 1.4,
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
