import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 주차별 포스트 리스트 페이지 (블러/오버레이 없이 단독 페이지로 표시)
class WeekPostListScreen extends StatefulWidget {
  final int year;
  final int weekNumber;
  final List<PostData> posts;

  const WeekPostListScreen({
    super.key,
    required this.year,
    required this.weekNumber,
    required this.posts,
  });

  @override
  State<WeekPostListScreen> createState() => _WeekPostListScreenState();
}

class _WeekPostListScreenState extends State<WeekPostListScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    // 2초 후 로딩 완료 및 부드러운 전환
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child:
              _isLoading
                  ? _buildLoadingScreen(context, colorScheme)
                  : _buildPostList(screenWidth),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(BuildContext context, ColorScheme colorScheme) {
    return Container(
      key: const ValueKey('loading'),
      width: double.infinity,
      height: double.infinity,
      color: colorScheme.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              '${widget.year}년 ${widget.weekNumber}주차',
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '포스트를 불러오는 중...',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostList(double screenWidth) {
    return PostList(
      key: const ValueKey('postList'),
      containerWidth: screenWidth,
      posts: widget.posts,
      showAppBar: true,
      isTabActive: true,
      yearWeek: YearWeek(year: widget.year, week: widget.weekNumber),
    );
  }
}
