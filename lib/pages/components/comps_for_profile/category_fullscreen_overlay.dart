import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CategoryFullscreenOverlay extends StatelessWidget {
  const CategoryFullscreenOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CategoryOverlayProvider>(
      builder: (context, overlayProvider, _) {
        if (!overlayProvider.isVisible) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // 배경 블러 + 반투명
              Positioned.fill(
                child: GestureDetector(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: const Color.fromARGB(182, 144, 144, 144),
                    ),
                  ),
                ),
              ),
              // 메인 콘텐츠
              Positioned.fill(
                child: Column(
                  children: [
                    // 헤더
                    _buildHeader(context, overlayProvider),
                    // 콘텐츠 영역
                    Expanded(child: _buildContent(context, overlayProvider)),
                  ],
                ),
              ),
              // 닫기 버튼
              _buildCloseButton(context, overlayProvider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    CategoryOverlayProvider overlayProvider,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 60, // 닫기 버튼 공간 확보
        bottom: 20,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              overlayProvider.categoryTitle ?? '',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    CategoryOverlayProvider overlayProvider,
  ) {
    return ValueListenableBuilder<FeedDisplayMode>(
      valueListenable: FeedDisplayModeManager(),
      builder: (context, displayMode, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: displayMode == FeedDisplayMode.card ? 1 : 2,
              childAspectRatio: displayMode == FeedDisplayMode.card ? 1.2 : 0.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: overlayProvider.categoryPosts.length,
            itemBuilder: (context, index) {
              final post = overlayProvider.categoryPosts[index];
              return _buildPostCard(context, post, index, displayMode);
            },
          ),
        );
      },
    );
  }

  Widget _buildPostCard(
    BuildContext context,
    dynamic post,
    int index,
    FeedDisplayMode displayMode,
  ) {
    // PostData로 변환
    PostData postData;
    try {
      postData = PostData.fromServer(post);
    } catch (_) {
      return const SizedBox.shrink();
    }

    if (displayMode == FeedDisplayMode.card) {
      // 카드 모드: 가로 레이아웃
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPost(context, postData, index),
          child: Row(
            children: [
              // 썸네일
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: CachedNetworkImage(
                    imageUrl: postData.thumbnailImageUrl,
                    fit: BoxFit.cover,
                    placeholder:
                        (context, url) => ShimmerBox(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.circular(16),
                        ),
                    errorWidget:
                        (context, url, error) =>
                            const Icon(Icons.error, color: Colors.white),
                  ),
                ),
              ),
              // 텍스트
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        postData.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        postData.parsedContent,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // 이미지 모드: 그리드 레이아웃
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPost(context, postData, index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: postData.thumbnailImageUrl,
              fit: BoxFit.cover,
              placeholder:
                  (context, url) => ShimmerBox(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.circular(16),
                  ),
              errorWidget:
                  (context, url, error) =>
                      const Icon(Icons.error, color: Colors.white),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildCloseButton(
    BuildContext context,
    CategoryOverlayProvider overlayProvider,
  ) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      right: 20,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 24),
          onPressed: () => overlayProvider.hideCategoryOverlay(),
        ),
      ),
    );
  }

  void _openPost(BuildContext context, PostData post, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => PostReaderScreen(
              exported: post.toExportedData(),
              heroTag: null,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}
