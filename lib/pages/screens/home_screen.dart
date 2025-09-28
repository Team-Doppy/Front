import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          ' doppy',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: _isLoading ? _buildLoadingCard() : _buildContent(screenWidth),
      ),
      // 하단 네비게이션은 RootShell에서 고정 제공
    );
  }

  Widget _buildLoadingCard() {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      width: screenSize.width,
      height: screenSize.height - bottomPadding,
      decoration: const BoxDecoration(color: Color.fromARGB(255, 38, 38, 38)),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
    );
  }

  Widget _buildContent(double screenWidth) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              '포스트를 불러올 수 없습니다',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onBackground.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '서버 연결을 확인해주세요',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onBackground.withOpacity(0.54),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPosts, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    return PostList(
      containerWidth: screenWidth,
      posts: _posts,
      onLoadMore: _hasMoreData ? _loadMorePosts : null,
      isLoadingMore: _isLoadingMore,
      onRefresh: () => _loadPosts(refresh: true),
    );
  }
}
