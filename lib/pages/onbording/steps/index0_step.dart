import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';

/// Index 0: card + background (임시 구조)
class Index0CardContent extends StatelessWidget {
  const Index0CardContent({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO(user): replace with real UI
    return Center(
      child: Text(
        '지금부터 차곡차곡\n쌓아갈게요',
        style: LocaleTypography.boldStyle(
          context: context,
          fontSize: 32,
          color: Colors.white,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              Text(
                '안 남기면',
                style: TextStyle(
                  color: AppColors.darkSurfaceVariant,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '없어질 순간들',
                style: TextStyle(
                  color: AppColors.darkSurfaceVariant,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
