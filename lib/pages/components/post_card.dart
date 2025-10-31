import 'dart:ui' as ui;

import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:doppy/pages/components/fullscreen_image_viewer.dart';

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
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12), // 보더 두께만큼 작게
          child: GestureDetector(
            onLongPress: () {
              // 이미지 전체화면 보기
              Navigator.of(context).push(
                PageRouteBuilder(
                  opaque: false,
                  pageBuilder:
                      (context, animation, secondaryAnimation) =>
                          FullscreenImageViewer(
                            imageUrl: widget.thumbnailImageUrl,
                          ),
                ),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: CachedNetworkImage(
              imageUrl: widget.thumbnailImageUrl,
              fit: BoxFit.cover,
              key: ValueKey('bg-${widget.thumbnailImageUrl}'),
              fadeInDuration: const Duration(milliseconds: 0), // 캐시된 이미지는 즉시 표시
              fadeOutDuration: const Duration(milliseconds: 0),
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
              memCacheWidth: 800, // 메모리 캐시 크기 지정
              maxWidthDiskCache: 800, // 디스크 캐시 크기
            ),
          ),
        ),
      );
    } else {
      // 로컬 에셋
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
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

        Positioned(
          left: 3,
          bottom: 3,
          child: GestureDetector(
            onTap: () {
              final isMyPost =
                  widget.author ==
                  context.read<UserProvider>().currentUser?.username;

              if (isMyPost) {
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => UserProfileScreen(
                        otherUser:
                            isMyPost
                                ? null
                                : User(
                                  id: 0,
                                  username: widget.author,
                                  alias: widget.author,
                                  profileImageUrl: widget.authorProfileImageUrl,
                                ),
                      ),
                ),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(35),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(35),
                ),
                child: Row(
                  children: [
                    CommonProfileAvatar(
                      imageUrl: widget.authorProfileImageUrl ?? "",
                      username: widget.author,
                      size: 35,
                      borderWidth: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
