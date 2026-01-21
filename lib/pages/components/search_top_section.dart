import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 🎯 검색 화면용 Hero 섹션
class SearchHeroSection extends StatefulWidget {
  final List<SearchContentItem> posts;
  final Function(int)? onPostIndexChanged;
  final Function(SearchContentItem) onTapPost;
  final double textOpacity; // 🎯 텍스트 투명도

  const SearchHeroSection({
    required this.posts,
    this.onPostIndexChanged,
    required this.onTapPost,
    this.textOpacity = 1.0,
  });

  @override
  State<SearchHeroSection> createState() => SearchHeroSectionState();
}

class SearchHeroSectionState extends State<SearchHeroSection> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onPageChanged);
    if (widget.posts.isNotEmpty && widget.onPostIndexChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onPostIndexChanged!(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final newIndex = _pageController.page?.round() ?? 0;
    if (newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
      widget.onPostIndexChanged?.call(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Container(color: Theme.of(context).colorScheme.background);
    }

    return Stack(
      children: [
        // 배경 이미지/비디오
        PageView.builder(
          controller: _pageController,
          physics: const ClampingScrollPhysics(),
          itemCount: widget.posts.length.clamp(0, 5),
          itemBuilder: (context, index) {
            final post = widget.posts[index.clamp(0, widget.posts.length - 1)];
            final imageUrl = post.imageUrl ?? '';

            // 비디오 URL 체크
            final isVideoUrl =
                imageUrl.toLowerCase().endsWith('.mp4') ||
                imageUrl.toLowerCase().endsWith('.mov') ||
                imageUrl.toLowerCase().endsWith('.avi') ||
                imageUrl.toLowerCase().endsWith('.webm') ||
                imageUrl.contains('/videos/');

            return GestureDetector(
              onTap: () => widget.onTapPost(post),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isVideoUrl)
                    SearchBackgroundVideoWidget(
                      videoUrl: imageUrl,
                      key: ValueKey('hero-video-$index-$imageUrl'),
                    )
                  else if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration(
                        milliseconds: 200,
                      ), // 🎯 페이드인 효과 제거
                      fadeOutDuration: Duration(
                        milliseconds: 200,
                      ), // 🎯 페이드아웃 효과 제거
                      errorWidget:
                          (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                    )
                  else
                    Container(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                    ),
                  // 그라데이션 오버레이
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // 텍스트 오버레이 (하단 중앙) - 스크롤 시 투명도 적용
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: widget.textOpacity,
            child: Builder(
              builder: (context) {
                final safeIndex = _currentIndex.clamp(
                  0,
                  widget.posts.length - 1,
                );
                final currentPost = widget.posts[safeIndex];

                return Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20),
                  child: Column(
                    children: [
                      Text(
                        currentPost.title ?? '',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // 페이지 인디케이터 (하단)
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.posts.length.clamp(0, 5), // 최대 5개만 표시
              (index) => Container(
                width: index == _currentIndex ? 8 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape:
                      index == _currentIndex
                          ? BoxShape.rectangle
                          : BoxShape.circle,
                  borderRadius:
                      index == _currentIndex ? BorderRadius.circular(3) : null,
                  color:
                      index == _currentIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
