import 'dart:math';
import 'package:doppy/pages/components/post_card.dart';
import 'package:flutter/material.dart';
import 'package:doppy/pages/post/postview_screen.dart';
import 'package:doppy/data/models/post_data.dart';

class PostList extends StatefulWidget {
  final double containerWidth;
  final List<PostData> posts;

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
  });

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isScrolling = false;
  double _page = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        final current = _pageController.page ?? _currentIndex.toDouble();
        if ((current - _page).abs() > 0.0001) {
          setState(() {
            _page = current;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // 페이지 정지 직전(정확히 맞물리기 직전)으로 가까워지면 미리 밝기 복원
          final metrics = notification.metrics;
          final viewport = metrics.viewportDimension;
          if (viewport > 0) {
            final page = metrics.pixels / viewport;
            final nearest = page.round();
            final distance = (nearest - page).abs();
            // 임계값: 0.12 페이지 이내로 접근하면 정지 취급
            if (distance < 0.12) {
              if (_isScrolling || _currentIndex != nearest) {
                setState(() {
                  _isScrolling = false;
                  // 범위 보호
                  final maxIndex = widget.posts.length - 1;
                  _currentIndex = nearest.clamp(0, maxIndex);
                });
              }
            } else {
              if (!_isScrolling) {
                setState(() {
                  _isScrolling = true;
                });
              }
            }
          }
        }
        if (notification is ScrollStartNotification) {
          if (!_isScrolling) {
            setState(() {
              _isScrolling = true;
            });
          }
        } else if (notification is ScrollEndNotification) {
          if (_isScrolling) {
            setState(() {
              _isScrolling = false;
            });
          }
        }
        return false;
      },
      child: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.posts.length,
        itemBuilder: (context, index) {
          final post = widget.posts[index];
          return _buildPostItem(context, post, index);
        },
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    // 인접 페이지 여부에 따라 부드럽게 밝아짐/어두워짐
    double progress;
    if (_pageController.hasClients) {
      final distance = (_page - index).abs();
      // 0(멀리) ~ 1(정확히 맞물림)
      final raw = (1.0 - distance).clamp(0.0, 1.0);
      // 멈추었거나 매우 가까우면 즉시 밝게
      if (!_isScrolling && _currentIndex == index) {
        progress = 1.0;
      } else if (distance < 0.12) {
        progress = 1.0;
      } else {
        // 부드러운 커브
        progress = 1.0 - pow(1.0 - raw, 3).toDouble();
      }
    } else {
      progress = (_currentIndex == index) ? 1.0 : 0.0;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostviewScreen(postId: post.postId),
          ),
        );
        print('전체 이웃 글 ${post.postId} 클릭');
      },
      onDoubleTap: () {
        setState(() {
          post.isLiked = !post.isLiked;
          post.likeCount++;
        });
      },
      child: PostCard(
        containerWidth: widget.containerWidth,
        imagePath: post.imagePath,
        title: post.title,
        author: post.author,
        content: post.content,
        isVisible: _currentIndex == index,
        tags: post.tags ?? [],
        scrollProgress: progress,
      ),
    );
  }
}
