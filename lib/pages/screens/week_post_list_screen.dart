import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/image/utils/read_image_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/search_result.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 주차별 포스트 리스트 페이지 (블러/오버레이 없이 단독 페이지로 표시)
class WeekPostListScreen extends StatefulWidget {
  final int year;
  final int weekNumber;
  final List<int>? postIds; // ✅ 선택적: 그리드 셀에서 이미 알고 있는 포스트 ID들

  const WeekPostListScreen({
    super.key,
    required this.year,
    required this.weekNumber,
    this.postIds, // ✅ 선택적 파라미터로 변경
  });

  @override
  State<WeekPostListScreen> createState() => _WeekPostListScreenState();
}

class _WeekPostListScreenState extends State<WeekPostListScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  List<PostData> _posts = [];
  late AnimationController _loadingAnimationController;

  @override
  void initState() {
    super.initState();

    // ✅ 커스텀 로딩 인디케이터 애니메이션 (3개 닷 순차 확대)
    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 1.2초 주기 (각 닷당 400ms)
    )..repeat();

    // ✅ 실제 API 호출
    _loadWeekPosts();
  }

  /// 주차 포스트 목록 로드
  Future<void> _loadWeekPosts() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });

      final blogService = BlogService();
      final postsData = await blogService.getWeekPostList(
        year: widget.year,
        week: widget.weekNumber,
        postIds: widget.postIds,
      );

      // PostData로 변환
      final posts = postsData.map((data) => PostData.fromServer(data)).toList();

      // ✅ 이미지 프리로드: 첫 몇 개의 썸네일 이미지를 로드할 때까지 대기
      if (mounted && posts.isNotEmpty) {
        await _preloadThumbnailImages(context, posts);
      }

      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[WeekPostListScreen] 포스트 목록 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  /// 썸네일 이미지 프리로드 (첫 몇 개만 필수, 나머지는 백그라운드)
  Future<void> _preloadThumbnailImages(
    BuildContext context,
    List<PostData> posts,
  ) async {
    if (!mounted) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final decodeWidth = (screenWidth * MediaQuery.of(context).devicePixelRatio)
        .round()
        .clamp(1, 1920);

    // ✅ 첫 3개는 필수로 로드 (화면에 보이는 포스트들)
    const int criticalCount = 3;
    final criticalPosts = posts.take(criticalCount).toList();

    try {
      await Future.wait(
        criticalPosts.map((post) async {
          final thumbnailUrl = post.thumbnailImageUrl;
          if (thumbnailUrl.isEmpty) return;

          try {
            final imageProvider = ReadImageProvider.build(
              url: thumbnailUrl,
              decodeWidth: decodeWidth,
            );
            await precacheImage(imageProvider, context);
            debugPrint('[WeekPostListScreen] ✅ 썸네일 프리로드 완료: ${post.id}');
          } catch (e) {
            debugPrint('[WeekPostListScreen] ⚠️ 썸네일 프리로드 실패: ${post.id} - $e');
            // 프리로드 실패해도 계속 진행
          }
        }),
        eagerError: false, // 하나 실패해도 나머지 계속 진행
      );
    } catch (e) {
      debugPrint('[WeekPostListScreen] 이미지 프리로드 오류: $e');
    }

    // ✅ 나머지는 백그라운드에서 로드 (화면 진입을 막지 않음)
    if (posts.length > criticalCount) {
      final remainingPosts = posts.skip(criticalCount).toList();
      Future.microtask(() async {
        for (final post in remainingPosts) {
          if (!mounted) break;
          final thumbnailUrl = post.thumbnailImageUrl;
          if (thumbnailUrl.isEmpty) continue;

          try {
            final imageProvider = ReadImageProvider.build(
              url: thumbnailUrl,
              decodeWidth: decodeWidth,
            );
            await precacheImage(imageProvider, context);
          } catch (_) {
            // 백그라운드 로드 실패는 무시
          }
        }
      });
    }
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
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child:
              _isLoading
                  ? _buildLoadingScreen(context, colorScheme)
                  : _hasError
                  ? _buildErrorScreen(context, colorScheme)
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
          // ✅ 상단 뒤로가기 아이콘
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Spacer(),
          // ✅ 글자 부분: 먼저 사라지도록 별도 AnimatedSwitcher로 감싸기
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchOutCurve: Curves.easeIn,
            child:
                _isLoading
                    ? Column(
                      key: const ValueKey('text'),
                      children: [
                        Text(
                          context
                              .tr('loading_week_posts_title')
                              .replaceAll('{year}', '${widget.year}')
                              .replaceAll('{week}', '${widget.weekNumber}'),
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('loading_week_posts_subtitle'),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 28,
                            fontWeight: FontWeight.w300,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    )
                    : const SizedBox.shrink(key: ValueKey('empty')),
          ),
          const SizedBox(height: 40),
          // ✅ 커스텀 로딩 인디케이터: 3개 닷이 순차적으로 확대 + primary 색상
          AnimatedBuilder(
            animation: _loadingAnimationController,
            builder: (context, _) {
              final currentTime = _loadingAnimationController.value;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  // 각 닷의 활성화 구간: 0->0.33, 1->0.33~0.66, 2->0.66->1.0
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
          const SizedBox(height: 40), Spacer(),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(BuildContext context, ColorScheme colorScheme) {
    return Container(
      key: const ValueKey('error'),
      width: double.infinity,
      height: double.infinity,
      color: colorScheme.background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.tr('failed_to_load_posts'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostList(double screenWidth) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 포스트가 없을 때 빈 상태 UI
    if (_posts.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.tr('no_posts_in_week'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurface.withOpacity(0.6),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 하단 주차 정보
          _buildWeekInfoFooter(colorScheme),
        ],
      );
    }

    // 포스트가 있을 때
    return Column(
      children: [
        Expanded(
          child: SearchResultsView(
            key: const ValueKey('postList'),
            posts: _posts,
            searchQuery: '', // 주차별 포스트 리스트에서는 검색어 없음
            isLoading: false,
            isLoadingMore: false,
            hasMore: false,
            onRefresh: null,
            onLoadMore: null,
            onPageChanged: null,
            onSearchChipTap: () {}, // 빈 함수
            onClearSearch: () {}, // 빈 함수
          ),
        ),
        // 하단 주차 정보
        _buildWeekInfoFooter(colorScheme),
      ],
    );
  }

  /// 하단 주차 정보 푸터 (예: "2025.2주차")
  Widget _buildWeekInfoFooter(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.background,
        border: Border(
          top: BorderSide(
            color: colorScheme.onSurface.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Text(
          context
              .tr('week_format')
              .replaceAll('{year}', '${widget.year}')
              .replaceAll('{week}', '${widget.weekNumber}'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}
