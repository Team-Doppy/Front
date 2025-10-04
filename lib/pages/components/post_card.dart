import 'package:flutter/material.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ignore: must_be_immutable
class PostCard extends StatefulWidget {
  final double containerWidth;
  final String thumbnailImageUrl;
  final String? heroTag;
  final String title;
  final String author;
  final String? authorProfileImageUrl;
  final String content;
  final bool isVisible;
  final VoidCallback? onLikePressed;
  final String postId; // 포스트 ID 추가

  bool isLiked;
  int likeCount;

  PostCard({
    super.key,
    required this.containerWidth,
    required this.thumbnailImageUrl,
    this.heroTag,
    required this.title,
    required this.author,
    this.authorProfileImageUrl,
    required this.content,
    this.isVisible = false,
    this.onLikePressed,
    required this.postId, // 필수로 변경

    this.isLiked = false,
    this.likeCount = 0,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final LikeService _likeService = LikeService();

  @override
  void initState() {
    super.initState();
    _likeService.addListener(_onLikeServiceChanged);
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    super.dispose();
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildImage() {
    // URL인지 로컬 에셋인지 판단
    if (widget.thumbnailImageUrl.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceVariant,
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12), // 보더 두께만큼 작게
          child: CachedNetworkImage(
            imageUrl: widget.thumbnailImageUrl,
            fit: BoxFit.cover,
            key: ValueKey('bg-${widget.thumbnailImageUrl}'),
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: const Duration(milliseconds: 100),
            placeholder:
                (context, url) => ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.circular(12),
                ),
            errorWidget:
                (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Center(
                    child: Icon(
                      Icons.error,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.54),
                      size: 40,
                    ),
                  ),
                ),
          ),
        ),
      );
    } else {
      // 로컬 에셋
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceVariant,
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.error,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
            size: 40,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 배경 이미지 - 전체 카드를 덮음
        Positioned.fill(
          child:
              (widget.heroTag == null)
                  ? _buildImage()
                  : Hero(tag: widget.heroTag!, child: _buildImage()),
        ),
        // 우상단 하트 아이콘
        Positioned(
          right: 12,
          bottom: 10,
          child: GestureDetector(
            onTap: widget.onLikePressed,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _likeService.isPostLiked(widget.postId)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color:
                        _likeService.isPostLiked(widget.postId)
                            ? Colors.redAccent
                            : Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
