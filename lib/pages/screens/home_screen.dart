import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/empty_post_list.dart';
// import 'package:doppy/pages/components/loading_post_list.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class HomeScreen extends StatefulWidget {
  final List<PostData>? preloadedPosts;

  const HomeScreen({super.key, this.preloadedPosts});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BlogService _blogService = BlogService();
  List<PostData> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 0;
  bool _hasMoreData = true;
  int _currentPostIndex = 0; // 현재 보이는 포스트 인덱스
  bool _isCardShimmering = false; // 새로고침 시 카드 영역만 쉬머 표시

  @override
  void initState() {
    super.initState();
    // 스플래시에서 전달된 선로딩 데이터를 즉시 반영
    if (widget.preloadedPosts != null && widget.preloadedPosts!.isNotEmpty) {
      _posts = List<PostData>.from(widget.preloadedPosts!);
      _isLoading = false;
      _hasMoreData = _posts.length == 10;
      _currentPage = 1; // 다음 페이지부터 로드
    }

    print('[HomeScreen] initState: ${widget.preloadedPosts?.length}');
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    try {
      setState(() {
        if (refresh) {
          _currentPage = 0;
          _hasMoreData = true;
          // 배경 블러 유지 위해 기존 포스트 유지
          _isCardShimmering = _posts.isNotEmpty;
        }
        // 초기 진입 시에만 전체 로딩; 새로고침은 카드 쉬머만
        _isLoading = !refresh && _posts.isEmpty;
        _error = null;
      });

      // 새로고침 시에는 항상 서버에서 가져옵니다 (forceRefresh=true)
      final serverData = await _blogService.getHomePosts(
        page: _currentPage,
        size: 10,
        forceRefresh: refresh, // 새로고침 시에만 강제 갱신
      );
      final posts =
          serverData.map((data) => PostData.fromServer(data)).toList();

      // 전환 전에 썸네일 이미지 프리캐싱 (상위 몇 개)
      await _precacheImages(posts.take(3).toList());

      setState(() {
        if (refresh) {
          _posts = posts;
        } else {
          _posts.addAll(posts);
        }
        _isLoading = false;
        _isLoadingMore = false;
        _hasMoreData = posts.length == 10; // 10개 미만이면 더 이상 데이터 없음
        _currentPage++;
        _isCardShimmering = false; // 로드 완료 후 카드 쉬머 해제
      });
    } catch (e) {
      print('[HomeScreen] Error loading posts: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
        // 서버 오류 시 빈 리스트 유지
      });
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _loadPosts();
  }

  Widget _buildDynamicBackground() {
    if (_posts.isEmpty) return const SizedBox.shrink();

    // 안전한 인덱스 범위 체크
    final safeIndex = _currentPostIndex.clamp(0, _posts.length - 1);
    final currentPost = _posts[safeIndex];
    final String imageUrl = currentPost.thumbnailImageUrl.trim();

    final bool isNetwork = imageUrl.startsWith('http');

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child:
                isNetwork
                    ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      key: ValueKey('bg-$imageUrl'),
                      placeholder:
                          (context, url) => ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                          ),
                      errorWidget:
                          (context, url, error) => const Icon(Icons.error),
                    )
                    : SizedBox.shrink(),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.background.withOpacity(0.7),
                      Theme.of(
                        context,
                      ).colorScheme.background.withOpacity(0.75),
                      Theme.of(context).colorScheme.background.withOpacity(0.8),
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        _buildDynamicBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            toolbarHeight: 80,
            backgroundColor: Colors.transparent,
            title: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                ' doppy',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            centerTitle: false,
          ),
          body: _buildContent(screenWidth),
          // 하단 네비게이션은 RootShell에서 고정 제공
        ),
      ],
    );
  }

  Widget _buildContent(double screenWidth) {
    // 데이터가 준비되어 있다면 애니메이션 없이 즉시 렌더링
    if (!_isLoading && _error == null && _posts.isNotEmpty) {
      return PostList(
        containerWidth: screenWidth,
        posts: _posts,
        onLoadMore: _hasMoreData ? _loadMorePosts : null,
        isLoadingMore: _isLoadingMore,
        onRefresh: () => _loadPosts(refresh: true),
        showCardShimmer: _isCardShimmering,
        onPageChanged: (index) {
          setState(() {
            _currentPostIndex = index;
          });
        },
      );
    }
    final Widget child =
        (_error != null)
            ? _buildError()
            : (_isLoading)
            ? PostList(
              containerWidth: screenWidth,
              posts: _posts,
              onLoadMore: null,
              isLoadingMore: false,
              onRefresh: () => _loadPosts(refresh: true),
              showCardShimmer: true,
              onPageChanged: (index) {
                setState(() {
                  _currentPostIndex = index;
                });
              },
            )
            : (_posts.isEmpty)
            ? _buildEmptyResult()
            : PostList(
              containerWidth: screenWidth,
              posts: _posts,
              onLoadMore: _hasMoreData ? _loadMorePosts : null,
              isLoadingMore: _isLoadingMore,
              onRefresh: () => _loadPosts(refresh: true),
              showCardShimmer: _isCardShimmering,
              onPageChanged: (index) {
                setState(() {
                  _currentPostIndex = index;
                });
              },
            );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        final scale = Tween<double>(begin: 0.98, end: 1.0).animate(curved);
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('${_isLoading}_${_error != null}_${_posts.length}'),
        child: child,
      ),
    );
  }

  Future<void> _precacheImages(List<PostData> posts) async {
    final List<Future<void>> futures = [];
    for (final p in posts) {
      final url = p.thumbnailImageUrl.trim();
      if (url.isEmpty) continue;
      futures.add(precacheImage(NetworkImage(url), context).catchError((_) {}));
    }
    if (futures.isNotEmpty) {
      try {
        await Future.wait(futures);
      } catch (_) {}
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 커스텀 에러 아이콘 (원형 배경)
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.1),
              ),
              child: const Center(
                child: Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '연결 상태를 확인해주세요',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '네트워크 연결이 불안정하거나\n서버에 접속할 수 없습니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontSize: 15,
                height: 1.4,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 32),
            // 세련된 재시도 버튼
            SizedBox(
              width: 160,
              height: 48,
              child: ElevatedButton(
                onPressed: _loadPosts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.refresh_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '다시 시도',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResult() {
    return EmptyPostList();
  }
}
