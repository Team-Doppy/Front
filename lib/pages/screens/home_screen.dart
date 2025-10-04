import 'package:doppy/pages/components/empty_post_list.dart';
import 'package:doppy/pages/components/loading_post_list.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
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

  @override
  void initState() {
    super.initState();

    // 미리 로드된 데이터가 있으면 사용, 없으면 서버에서 로드
    if (widget.preloadedPosts != null && widget.preloadedPosts!.isNotEmpty) {
      setState(() {
        _posts = widget.preloadedPosts!;
        _isLoading = false;
        _currentPage = 1; // 이미 첫 페이지 로드됨
      });
    } else {
      _loadPosts();
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    try {
      setState(() {
        if (refresh) {
          _currentPage = 0;
          _hasMoreData = true;
          _posts.clear();
        }
        _isLoading = refresh || _posts.isEmpty;
        _error = null;
      });

      final serverData = await _blogService.getHomePosts(
        page: _currentPage,
        size: 30,
        forceRefresh: refresh, // 새로고침 시에만 강제 갱신
      );
      final posts =
          serverData.map((data) => PostData.fromServer(data)).toList();

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
                    ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      key: ValueKey('bg-$imageUrl'),
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
            backgroundColor: Colors.transparent,
            title: Text(
              ' doppy',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: Theme.of(context).colorScheme.primary,
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
    if (_error != null) {
      return _buildError();
    } else if (_isLoading) {
      return _buildLoading();
    } else if (_posts.isEmpty) {
      return _buildEmptyResult();
    }
    return PostList(
      containerWidth: screenWidth,
      posts: _posts,
      onLoadMore: _hasMoreData ? _loadMorePosts : null,
      isLoadingMore: _isLoadingMore,
      onRefresh: () => _loadPosts(refresh: true),
      onPageChanged: (index) {
        setState(() {
          _currentPostIndex = index;
        });
      },
    );
  }

  Widget _buildLoading() {
    return const LoadingPostList(containerWidth: 0);
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
