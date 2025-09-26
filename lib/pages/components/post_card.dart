import 'package:flutter/material.dart';

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

    this.isLiked = false,
    this.likeCount = 0,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  // ignore: non_constant_identifier_names
  Widget _PulseLoadingWidget() {
    return Container(
      padding: const EdgeInsets.all(8),
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildImage() {
    // URL인지 로컬 에셋인지 판단
    if (widget.thumbnailImageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          widget.thumbnailImageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _PulseLoadingWidget();
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
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
            );
          },

          // 고화질을 위한 최적화
          filterQuality: FilterQuality.high,
        ),
      );
    } else {
      // 로컬 에셋
      return Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
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
        // 하단 그라데이션 오버레이
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.2),
                ],
                stops: const [0.0, 0.5, 0.9, 0.98],
              ),
            ),
          ),
        ),

        // 텍스트 오버레이 - 하단에 위치
        Positioned(left: 20, right: 20, bottom: 20, child: _buildOverlayText()),
      ],
    );
  }

  Widget _buildOverlayText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 제목 - 큰 텍스트
        Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        // 내용
        Text(
          widget.content,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
