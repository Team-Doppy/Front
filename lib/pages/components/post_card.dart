import 'dart:ui';
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
      return Image.network(
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
    final double width = widget.containerWidth;
    final double height = width * 16 / 9; // 4:5 비율 (width:height)

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
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
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.35),
                      ],
                      stops: const [0.0, 0.4, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
              // 직성자 정보
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: _buildOverlayAuthor(),
              ),
              // 텍스트 오버레이 - 하단에 위치
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildOverlayText(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayAuthor() {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(300),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(300),
            child:
                (widget.authorProfileImageUrl != null &&
                        widget.authorProfileImageUrl!.isNotEmpty)
                    ? Image.network(
                      widget.authorProfileImageUrl!,
                      fit: BoxFit.cover,
                      width: 40,
                      height: 40,
                    )
                    : Container(
                      color: Colors.white,
                      child: Icon(Icons.person, color: Colors.black54),
                    ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.author,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: 'Pretendard Variable',
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            fontSize: 36,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
