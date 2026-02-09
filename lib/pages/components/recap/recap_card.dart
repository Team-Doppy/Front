import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/image/utils/read_image_cache_manager.dart';
import 'package:doppy/pages/home/home_widgets.dart';
import 'package:doppy/pages/components/recap/recap_loading.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

class RecapCard extends StatefulWidget {
  const RecapCard({super.key});

  @override
  State<RecapCard> createState() => _RecapCardState();
}

class _RecapCardState extends State<RecapCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  Future<void> _handleTap({
    required BuildContext context,
    required List<String> previewThumbnails,
  }) async {
    // ✅ 리캡을 봤다는 플래그는 서버에서 성공적으로 로드했을 때만 설정
    // (RecapLoadingScreen에서 처리)

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecapLoadingScreen(thumbnailUrls: previewThumbnails),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MyProfileFeedProvider>(
      builder: (context, feedProvider, _) {
        // 사용자 정보에서 alias 가져오기
        final userInfo = feedProvider.userInfo;
        final alias =
            userInfo?['alias'] as String? ??
            userInfo?['username'] as String? ??
            '나';

        // 프로필 이미지 우선 사용
        final profileImageUrl = userInfo?['profileImageUrl'] as String?;
        final hasProfileImage =
            profileImageUrl != null && profileImageUrl.isNotEmpty;

        // 피드에서 썸네일 URL 추출 (createdAt 오름차순 기준 첫 3개를 로딩 UI에 사용)
        final posts = feedProvider.posts;
        final thumbTuples = <({DateTime? createdAt, String url})>[];
        for (final post in posts) {
          final url = post['thumbnailImageUrl'] as String?;
          if (url == null || url.isEmpty) continue;
          final createdAtStr = post['createdAt']?.toString();
          final createdAt =
              createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
          thumbTuples.add((createdAt: createdAt, url: url));
        }
        thumbTuples.sort((a, b) {
          final ad = a.createdAt;
          final bd = b.createdAt;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd); // asc
        });

        final previewThumbnails =
            thumbTuples.map((e) => e.url).toSet().toList().take(3).toList();

        final thumbnails =
            thumbTuples.map((e) => e.url).where((u) => u.isNotEmpty).toList();

        final selectedThumbnail =
            hasProfileImage
                ? profileImageUrl
                : (thumbnails.isNotEmpty ? thumbnails.first : null);

        if (selectedThumbnail == null) {
          // 썸네일이 없으면 빈 컨테이너
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(
            bottom: HomeSectionSpacing.sectionLarge,
          ),
          child: GestureDetector(
            onTap:
                () => _handleTap(
                  context: context,
                  previewThumbnails: previewThumbnails,
                ),
            child: ClipRRect(
              child: SizedBox(
                height: 400, // 명시적 높이 설정
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 배경 이미지 (원형 영역 전체를 채우도록 확대)
                    Transform.scale(
                      scale: 1.4, // 원형 영역을 완전히 채우기 위해 확대
                      child: RepaintBoundary(
                        child: CachedNetworkImage(
                          imageUrl: selectedThumbnail,
                          cacheKey: selectedThumbnail, // ✅ 명시적 캐시 키 지정
                          cacheManager:
                              ReadImageCacheManager
                                  .instance, // ✅ 읽기 전용 캐시 매니저 사용
                          fit: BoxFit.cover,
                          fadeInDuration: Duration(
                            milliseconds: 300,
                          ), // ✅ 페이드 애니메이션 제거
                          fadeOutDuration: Duration(
                            milliseconds: 300,
                          ), // ✅ 페이드 애니메이션 제거
                          useOldImageOnUrlChange: true, // ✅ URL 변경 시 이전 이미지 유지
                          errorWidget:
                              (context, url, error) => Container(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant,
                              ),
                        ),
                      ),
                    ),
                    // 블러 오버레이
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(color: Colors.black.withOpacity(0.3)),
                    ),

                    // 텍스트 오버레이
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 메인 텍스트
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$alias',
                                style: LocaleTypography.style(
                                  context: context,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  color: Color.fromARGB(255, 246, 246, 246),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '리캡 보러가기',
                                style: LocaleTypography.style(
                                  context: context,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  color: Color.fromARGB(255, 246, 246, 246),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 38,
                      left: 28,
                      child: Row(
                        children: [
                          SvgPicture.asset(
                            'assets/icons/lock_open.svg',
                            width: 20,
                            height: 20,
                            color: const Color.fromARGB(220, 255, 255, 255),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '최근 3개 포스트로 분석해볼게요!',
                            style: LocaleTypography.style(
                              context: context,
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                              color: Color.fromARGB(255, 246, 246, 255),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 48,
                      right: 24,
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_animation.value, 0),
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 32,
                              color: const Color.fromARGB(220, 255, 255, 255),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
