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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
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
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
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
      ),
    );
  }
}
