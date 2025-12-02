import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/search_results.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';

/// 실시간 검색어 (이미지 프리로드 포함)
class TrendingKeywordsWithPreload extends StatefulWidget {
  final List<String> keywords;
  final List<SearchContentItem> recommendedPosts;
  final bool isLoading;
  final bool shouldShowShimmer;
  final Function(String) onTapKeyword;
  final Function(SearchContentItem) onTapPost;
  final Function(int)? onPostIndexChanged;
  final Future<void> Function()? onRefresh;

  const TrendingKeywordsWithPreload({
    super.key,
    required this.keywords,
    required this.recommendedPosts,
    required this.isLoading,
    required this.shouldShowShimmer,
    required this.onTapKeyword,
    required this.onTapPost,
    this.onPostIndexChanged,
    this.onRefresh,
  });

  @override
  State<TrendingKeywordsWithPreload> createState() =>
      _TrendingKeywordsWithPreloadState();
}

class _TrendingKeywordsWithPreloadState
    extends State<TrendingKeywordsWithPreload> {
  bool _imagesPreloaded = false;
  bool _isPreloading = false;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context가 준비된 후에 이미지 프리로드 시작 (한 번만)
    if (!_hasInitialized) {
      _hasInitialized = true;
      _preloadImagesIfNeeded();
    }
  }

  @override
  void didUpdateWidget(TrendingKeywordsWithPreload oldWidget) {
    super.didUpdateWidget(oldWidget);
    // recommendedPosts가 변경되거나 shimmer 상태가 변경되면 다시 프리로드
    if (widget.recommendedPosts != oldWidget.recommendedPosts ||
        widget.shouldShowShimmer != oldWidget.shouldShowShimmer) {
      _imagesPreloaded = false;
      _isPreloading = false;
      _preloadImagesIfNeeded();
    }
  }

  Future<void> _preloadImagesIfNeeded() async {
    // 이미 프리로드 중이거나 완료했으면 스킵
    if (_isPreloading || _imagesPreloaded) {
      return;
    }

    // recommendedPosts가 없으면 스킵
    if (widget.recommendedPosts.isEmpty) {
      _imagesPreloaded = true;
      return;
    }

    // recommendedPosts가 5개 미만이면 모두, 5개 이상이면 5개만 프리로드
    final postsToPreload = widget.recommendedPosts.take(5).toList();

    // 이미지 URL 추출 (비디오 URL 제외)
    final imageUrls =
        postsToPreload
            .where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty)
            .where((post) {
              // 🎯 비디오 파일(.mp4, .mov 등) 제외 - 이미지만 프리로드
              final url = post.imageUrl!.toLowerCase();
              return !url.endsWith('.mp4') &&
                  !url.endsWith('.mov') &&
                  !url.endsWith('.avi') &&
                  !url.endsWith('.webm') &&
                  !url.contains('/videos/');
            })
            .map((post) => post.imageUrl!)
            .toList();

    if (imageUrls.isEmpty) {
      _imagesPreloaded = true;
      return;
    }

    _isPreloading = true;
    debugPrint('[TrendingKeywords] 이미지 프리로드 시작: ${imageUrls.length}개');

    try {
      // 🎯 배치 처리로 UI 블로킹 방지 (한 번에 하나씩, 각 프레임 사이에 yield)
      for (int i = 0; i < imageUrls.length; i++) {
        if (!mounted) break;

        try {
          await precacheImage(
            NetworkImage(imageUrls[i]),
            context,
            onError: (e, stack) {
              debugPrint(
                '[TrendingKeywords] 이미지 프리로드 실패: ${imageUrls[i]} - $e',
              );
            },
          );

          // 🎯 각 이미지 프리로드 후 UI 업데이트 기회 제공 (Hang 방지)
          if (i < imageUrls.length - 1) {
            await Future.delayed(const Duration(milliseconds: 16));
          }
        } catch (e) {
          debugPrint('[TrendingKeywords] 이미지 프리로드 중 오류: ${imageUrls[i]} - $e');
        }
      }

      debugPrint('[TrendingKeywords] 이미지 프리로드 완료');
      if (mounted) {
        setState(() {
          _imagesPreloaded = true;
          _isPreloading = false;
        });
      }
    } catch (e) {
      debugPrint('[TrendingKeywords] 이미지 프리로드 중 오류: $e');
      if (mounted) {
        setState(() {
          _imagesPreloaded = true; // 에러가 나도 계속 진행
          _isPreloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[TrendingKeywords] build - keywords: ${widget.keywords.length}, posts: ${widget.recommendedPosts.length}, isLoading: ${widget.isLoading}, shouldShowShimmer: ${widget.shouldShowShimmer}, _imagesPreloaded: $_imagesPreloaded',
    );

    // 🎯 shimmer를 표시해야 하는 경우 (새로고침 중이거나 로딩 중일 때만)
    // 캐시 사용 시에는 이미지 프리로드가 완료되지 않아도 shimmer 표시하지 않음
    if (widget.shouldShowShimmer) {
      return const TrendingKeywordsShimmer();
    }

    // 이미지 프리로드가 완료되지 않았어도 캐시 사용 시에는 기존 데이터 표시
    // (이미지가 로드되는 동안 기존 데이터를 보여줌)

    // 🎯 키워드와 추천 포스트 모두 없는 경우
    if (widget.keywords.isEmpty && widget.recommendedPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [],
        ),
      );
    }

    return CustomRefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 🎯 실시간 검색어 리스트
          if (widget.keywords.isNotEmpty) ...[
            ...widget.keywords.take(5).map((keyword) {
              return AccountListItem(
                account: SearchContentItem.blogKeyword(
                  id: 'trending_$keyword',
                  keyword: keyword,
                ),
                onTap: () => widget.onTapKeyword(keyword),
                showRemoveButton: false,
              );
            }).toList(),
            const SizedBox(height: 30),
          ],
          // 🎯 추천 콘텐츠 섹션 (실제 데이터)
          if (widget.recommendedPosts.isNotEmpty) ...[
            Builder(
              builder: (context) {
                debugPrint(
                  '[TrendingKeywords] Rendering posts: ${widget.recommendedPosts.length}',
                );
                return RecommendedContentSection(
                  title: '추천 포스트',
                  posts: widget.recommendedPosts,
                  onTapItem: (post) => widget.onTapPost(post),
                  onPostIndexChanged:
                      widget.onPostIndexChanged, // 🎯 인덱스 변경 콜백 전달
                );
              },
            ),
          ] else ...[
            Builder(
              builder: (context) {
                debugPrint('[TrendingKeywords] No posts to display');
                return const SizedBox.shrink();
              },
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

/// 실시간 검색어 Shimmer
class TrendingKeywordsShimmer extends StatelessWidget {
  const TrendingKeywordsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 🎯 실제 UI와 동일한 크기 계산
    final cardWidth = (screenWidth - 16) / 1.8;
    final cardImageHeight = cardWidth * 4.6 / 4;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 🎯 원형 검색칩 Shimmer (원형 아이콘 + 텍스트, 좌측 정렬)
        ...List.generate(5, (index) {
          return Padding(
            padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // 원형 아이콘
                  ShimmerBox(
                    width: 50,
                    height: 50,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  const SizedBox(width: 16),
                  // 텍스트 (100px 너비)
                  ShimmerBox(
                    width: 100,
                    height: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 12),

        // 🎯 하단 카드 Shimmer (카드 이미지만)
        SizedBox(
          height: cardImageHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 16),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(right: index < 4 ? 10 : 0),
                child: ShimmerBox(
                  width: cardWidth,
                  height: cardImageHeight,
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}

/// 추천 콘텐츠 섹션
class RecommendedContentSection extends StatefulWidget {
  final String title;
  final List<SearchContentItem> posts;
  final Function(SearchContentItem) onTapItem;
  final Function(int)? onPostIndexChanged;

  const RecommendedContentSection({
    super.key,
    required this.title,
    required this.posts,
    required this.onTapItem,
    this.onPostIndexChanged,
  });

  @override
  State<RecommendedContentSection> createState() =>
      _RecommendedContentSectionState();
}

class _RecommendedContentSectionState extends State<RecommendedContentSection> {
  late ScrollController _scrollController;
  int _currentIndex = 0;
  final LikeService _likeService = LikeService();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    // 🎯 추천 포스트의 좋아요 상태를 LikeService에 설정 (값이 없을 때만)
    _loadLikeStatusForRecommendedPosts();
    // 🎯 초기 인덱스 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.posts.isNotEmpty && widget.onPostIndexChanged != null) {
        widget.onPostIndexChanged!(0);
      }
    });
  }

  void _loadLikeStatusForRecommendedPosts() {
    // 🎯 LikeService에 값이 없을 때만 설정 (다른 화면에서 좋아요를 누른 경우 덮어쓰지 않음)
    // SearchContentItem에는 isLiked 정보가 없으므로 false로 설정
    // 다른 화면에서 좋아요를 누른 경우 hasPost 체크로 인해 덮어쓰지 않음
    for (final post in widget.posts) {
      final postId = post.id.toString();
      if (postId.isNotEmpty && !_likeService.hasPost(postId)) {
        // SearchContentItem에는 isLiked 정보가 없으므로 false로 초기 설정
        // 실제 좋아요 상태는 PostCard의 initState에서 widget.isLiked로 설정됨
        final likeCount = post.likes ?? 0;
        _likeService.setInitialLikeData(postId, false, likeCount);
      }
    }
  }

  @override
  void didUpdateWidget(RecommendedContentSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 포스트 목록이 변경되면 인덱스 리셋 및 좋아요 상태 업데이트
    if (widget.posts != oldWidget.posts) {
      _currentIndex = 0;
      _loadLikeStatusForRecommendedPosts(); // 새 포스트들의 좋아요 상태 설정
      if (widget.posts.isNotEmpty && widget.onPostIndexChanged != null) {
        widget.onPostIndexChanged!(0);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 16) / 1.8;
    final padding = 16.0;
    final scrollOffset = _scrollController.offset;

    // 현재 보이는 포스트 인덱스 계산
    final newIndex = ((scrollOffset + padding) / (cardWidth + 10))
        .round()
        .clamp(0, widget.posts.length - 1);

    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      widget.onPostIndexChanged?.call(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 안전 장치: posts가 비어있으면 빈 위젯 반환
    if (widget.posts.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 16) / 1.8; // 좌우 패딩 16씩 제외 후 1.5개 표시
    final cardImageHeight = cardWidth * 4.6 / 4; // 4:5 비율
    final cardTotalHeight = cardImageHeight + 60; // 이미지 + 제목 영역

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: cardTotalHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // 가로 스크롤일 때는 리프레시를 막기 위해 true 반환 (이벤트 소비)
              if (notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) {
                if (notification.metrics.axis == Axis.horizontal) {
                  return true; // 이벤트 소비하여 리프레시 방지
                }
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController, // 🎯 스크롤 컨트롤러 추가
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16, right: 16),
              itemCount: widget.posts.length,
              itemBuilder: (context, index) {
                // 🎯 안전 장치: 인덱스 범위 체크
                if (index < 0 || index >= widget.posts.length) {
                  debugPrint('[RecommendedContent] ⚠️ 인덱스 범위 초과: $index');
                  return const SizedBox.shrink();
                }

                final post = widget.posts[index];
                return Padding(
                  padding: EdgeInsets.only(
                    right: index < widget.posts.length - 1 ? 10 : 0,
                  ),
                  child: SearchPostCard(
                    post: post,
                    cardWidth: cardWidth,
                    cardImageHeight: cardImageHeight,
                    onTap: () => widget.onTapItem(post),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 포스트 카드 (검색 화면용)
class SearchPostCard extends StatefulWidget {
  final SearchContentItem post;
  final double cardWidth;
  final double cardImageHeight;
  final VoidCallback onTap;

  const SearchPostCard({
    super.key,
    required this.post,
    required this.cardWidth,
    required this.cardImageHeight,
    required this.onTap,
  });

  @override
  State<SearchPostCard> createState() => _SearchPostCardState();
}

class _SearchPostCardState extends State<SearchPostCard>
    with AutomaticKeepAliveClientMixin {
  final LikeService _likeService = LikeService();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _likeService.addListener(_onLikeServiceChanged);

    // 🎯 LikeService에 초기값 설정 (값이 없을 때만)
    final postId = widget.post.id.toString();
    if (postId.isNotEmpty && !_likeService.hasPost(postId)) {
      final likeCount = widget.post.likes ?? 0;
      _likeService.setInitialLikeData(postId, false, likeCount);
    }

    debugPrint(
      '[PostCard] initState - ${widget.post.id}: ${widget.post.title}',
    );
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    debugPrint('[PostCard] dispose - ${widget.post.id}');
    super.dispose();
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 🎯 AutomaticKeepAliveClientMixin 필수

    // 🎯 비디오 파일 URL 체크
    final isVideoUrl =
        widget.post.imageUrl != null &&
        (widget.post.imageUrl!.toLowerCase().endsWith('.mp4') ||
            widget.post.imageUrl!.toLowerCase().endsWith('.mov') ||
            widget.post.imageUrl!.toLowerCase().endsWith('.avi') ||
            widget.post.imageUrl!.toLowerCase().endsWith('.webm'));

    final shouldShowImage =
        widget.post.imageUrl != null &&
        widget.post.imageUrl!.isNotEmpty &&
        !isVideoUrl;

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🎯 썸네일 이미지/비디오 (4:5 비율)
          SizedBox(
            width: widget.cardWidth,
            height: widget.cardImageHeight,
            child: Stack(
              children: [
                Container(
                  width: widget.cardWidth,
                  height: widget.cardImageHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child:
                      isVideoUrl
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ThumbnailVideoPlayer(
                              videoUrl: widget.post.imageUrl!,
                              width: widget.cardWidth,
                              height: widget.cardImageHeight,
                            ),
                          )
                          : shouldShowImage
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: widget.post.imageUrl!,
                              width: widget.cardWidth,
                              height: widget.cardImageHeight,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
                                return Center(
                                  child: Icon(
                                    Icons.image,
                                    size: 40,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity(0.3),
                                  ),
                                );
                              },
                            ),
                          )
                          : Center(
                            child: Icon(
                              Icons.image,
                              size: 40,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.3),
                            ),
                          ),
                ),
                // 🎯 작성자 정보 (이미지 위 왼쪽 하단 오버레이)
                if (widget.post.author != null &&
                    widget.post.author!.isNotEmpty)
                  Positioned(
                    left: 6,
                    bottom: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CommonProfileAvatar(
                          imageUrl: widget.post.profileImageUrl,
                          username: widget.post.author ?? '',
                          size: 26,
                          borderWidth: 1,
                          borderColor: Colors.transparent,
                          // 🎯 프로필 이미지가 없을 때만 배경색 설정 (grey[100] / black)
                          backgroundColor:
                              widget.post.profileImageUrl == null ||
                                      widget.post.profileImageUrl!.isEmpty
                                  ? (Theme.of(context).brightness ==
                                          Brightness.light
                                      ? Colors.grey[100]
                                      : Colors.black)
                                  : Colors.transparent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.post.author ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 3,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 🎯 제목만 (카드 아래)
          SizedBox(
            width: widget.cardWidth,
            child: Text(
              widget.post.title ?? '제목 없음',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
