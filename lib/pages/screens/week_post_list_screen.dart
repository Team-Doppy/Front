import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/utils/text_bold_utils.dart';
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

class _WeekPostListScreenState extends State<WeekPostListScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  late AnimationController _loadingAnimationController;

  @override
  void initState() {
    super.initState();

    // ✅ 커스텀 로딩 인디케이터 애니메이션 (3개 닷 순차 확대)
    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200), // 1.2초 주기 (각 닷당 400ms)
    )..repeat();

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
  void dispose() {
    _loadingAnimationController.dispose();
    super.dispose();
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Spacer(),
          Text(
            '${widget.year}, ${widget.weekNumber}주차를',
            style: LocaleTypography.setStyle(
              context: context,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '불러오고 있어요',
            style: GoogleFonts.notoSansKr(
              fontSize: 36,
              fontWeight: FontWeight.w300,
              color: colorScheme.onSurface,
            ),
          ),
          Spacer(),
          // ✅ 커스텀 로딩 인디케이터: 3개 닷이 순차적으로 확대 + primary 색상
          AnimatedBuilder(
            animation: _loadingAnimationController,
            builder: (context, _) {
              final currentTime = _loadingAnimationController.value;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  // 각 닷의 활성화 구간: 0->0.33, 1->0.33~0.66, 2->0.66~1.0
                  final delay = index / 3.0;

                  // 현재 시간에서 delay를 빼고 순환 처리
                  double relativeTime = (currentTime - delay) % 1.0;
                  if (relativeTime < 0) relativeTime += 1.0;

                  // 각 닷의 활성화 구간은 1/3 (약 0.33)
                  final duration = 1.0 / 3.0;
                  final t = (relativeTime / duration).clamp(0.0, 1.0);

                  // 부드러운 확대/축소 (easeInOut)
                  // 10px 기준으로 12px까지 확대 (20% 증가)
                  final scale = 1.0 + (0.2 * Curves.easeInOut.transform(t));
                  final isActive = t < 1.0;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 10,
                    height: 10,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isActive
                                  ? colorScheme.primary
                                  : colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
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
