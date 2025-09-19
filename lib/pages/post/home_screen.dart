import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_text_styles.dart';

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
        size: 10,
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
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // 앱바 - 항상 표시
            Container(
              height: 42,
              color: AppColors.darkBackground,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Consumer<AuthProvider>(
                        builder: (context, auth, child) {
                          final username = auth.username ?? '사용자';
                          return Text(
                            '@$username',
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ),
                    Stack(
                      children: [
                        Icon(
                          Icons.notifications,
                          color: AppColors.darkTextPrimary,
                          size: 23,
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 238, 0, 0),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 80),

            // 포스트 리스트 또는 로딩/에러 상태
            Expanded(child: _buildContent(screenWidth)),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 0,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildContent(double screenWidth) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('포스트를 불러오는 중...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              '포스트를 불러올 수 없습니다',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '서버 연결을 확인해주세요',
              style: TextStyle(color: Colors.white54, fontSize: 14),
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
