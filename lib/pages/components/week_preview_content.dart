import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 주차별 포스트 미리보기 콘텐츠 (Hero 애니메이션용 보라색 위젯)
class WeekPreviewContent extends StatelessWidget {
  final int weekNumber;
  final int year;

  const WeekPreviewContent({
    super.key,
    required this.weekNumber,
    this.year = 2025,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: 250,
      height: 200,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$weekNumber주차',
          style: GoogleFonts.notoSansKr(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
