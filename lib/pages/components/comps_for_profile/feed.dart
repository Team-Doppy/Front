import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 카테고리 섹션 메타 (파일 최상위)
class _FeedSectionMeta {
  const _FeedSectionMeta({required this.title, required this.posts});
  final String title;
  final List<PostData> posts;
}

class Feed {
  Widget buildFeedContent() {
    return ValueListenableBuilder<FeedDisplayMode>(
      valueListenable: FeedDisplayModeManager(),
      builder: (context, displayMode, _) {
        return Consumer<ProfileFeedProvider>(
          builder: (context, feedProvider, _) {
            final postsRaw = feedProvider.posts;

            if (feedProvider.isLoading && postsRaw.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            if (postsRaw.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      '아직은 아무 글도 없어요',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              );
            }

            // 1) 서버 포스트를 PostData로 안전 변환
            final allPosts = <PostData>[];
            for (final raw in postsRaw) {
              try {
                allPosts.add(PostData.fromServer(raw));
              } catch (_) {}
            }

            // 2) 기본 카테고리로 그룹핑
            final privatePosts =
                allPosts
                    .where((p) => p.accessLevel == AccessLevel.private)
                    .toList();
            final publicPosts =
                allPosts
                    .where((p) => p.accessLevel == AccessLevel.public)
                    .toList();
            final groupPosts =
                allPosts
                    .where((p) => p.accessLevel == AccessLevel.groups)
                    .toList();

            // 3) 카테고리 섹션 리스트 구성
            final sections =
                <_FeedSectionMeta>[
                  _FeedSectionMeta(title: '나만보기', posts: privatePosts),
                  _FeedSectionMeta(title: '전체공개', posts: publicPosts),
                  _FeedSectionMeta(title: '그룹공개', posts: groupPosts),
                ].where((s) => s.posts.isNotEmpty).toList();

            if (sections.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            // 4) 세로로 섹션을 쌓고, 각 섹션은 가로 PageView로 구성
            return SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final sec = sections[index];
                return _buildHorizontalSection(context, sec, displayMode);
              }, childCount: sections.length),
            );
          },
        );
      },
    );
  }

  // 섹션 헤더 + 가로 PageView
  Widget _buildHorizontalSection(
    BuildContext context,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
  ) {
    final theme = Theme.of(context);
    final height = 200.0; // 섹션 높이(헤더 제외)
    final dragDropService = context.read<PostDragDropService>();
    final listKey = GlobalKey();
    // 섹션별 가로 스크롤 컨트롤러
    final sectionId = sec.title;
    final hController = context
        .read<PostDragDropService>()
        .horizontalControllerFor(sectionId);
    double? _cachedCardWidth;

    return DragTarget<PostData>(
      onWillAccept: (data) {
        // 데이터가 있으면 수락 (세부 검증은 서버/모델 기준으로 처리)
        return data != null;
      },
      onAccept: (data) {
        // 드롭이 성공하면 해당 카테고리로 포스트 이동
        dragDropService.setDropTarget(sec.title);

        // 동일 섹션인지 판단 후, 동일 섹션이면 재정렬, 아니면 카테고리 이동
        bool isSameSection = false;
        switch (data.accessLevel) {
          case AccessLevel.private:
            isSameSection = (sec.title.contains('나만'));
            break;
          case AccessLevel.public:
            isSameSection = (sec.title.contains('전체'));
            break;
          case AccessLevel.groups:
            isSameSection = (sec.title.contains('그룹'));
            break;
        }

        if (isSameSection) {
          // 단일 소스 인덱스 사용: 드래그 중 계산된 값
          int? targetIndex = dragDropService.reorderTargetIndex;
          final curIdx = sec.posts.indexWhere((p) => p.id == data.id);
          if (targetIndex == null) {
            dragDropService.setReorderTargetIndex(null);
            return;
          }
          targetIndex = targetIndex.clamp(0, sec.posts.length);
          // 제자리(no-op) 방지: 본인 바로 앞/뒤면 변경 안함
          if (curIdx != -1 &&
              (targetIndex == curIdx || targetIndex == curIdx + 1)) {
            dragDropService.setReorderTargetIndex(null);
            return;
          }
          context.read<ProfileFeedProvider>().moveWithinAccessLevel(
            data.id,
            data.accessLevel,
            targetIndex,
          );
        } else {
          // 섹션 이동 + 단일 소스 인덱스 사용
          int targetIndex = (dragDropService.reorderTargetIndex ?? 0).clamp(
            0,
            sec.posts.length,
          );
          AccessLevel level = AccessLevel.public;
          if (sec.title.contains('나만')) {
            level = AccessLevel.private;
          } else if (sec.title.contains('그룹'))
            // ignore: curly_braces_in_flow_control_structures
            level = AccessLevel.groups;
          context.read<ProfileFeedProvider>().moveToAccessLevelAtIndex(
            data.id,
            level,
            targetIndex,
          );
        }
        // 프리뷰 슬롯 리셋
        dragDropService.setReorderTargetIndex(null);
      },
      onMove: (details) {
        // 타겟 표시 + 인서트 위치 계산 + 섹션별 수평 오토 스크롤
        dragDropService.setDropTarget(sec.title);
        try {
          final box = listKey.currentContext?.findRenderObject() as RenderBox?;
          if (box != null && _cachedCardWidth != null) {
            final local = box.globalToLocal(details.offset);
            const sep = 5.0;
            final viewportX = local.dx.clamp(0.0, box.size.width);
            final scrollX =
                hController.hasClients ? hController.position.pixels : 0.0;
            final totalX = scrollX + viewportX;
            final raw = totalX / (_cachedCardWidth! + sep);
            final idx = raw.floor().clamp(0, sec.posts.length);
            dragDropService.setReorderTargetIndex(idx);

            // 섹션 가로 오토 스크롤
            if (hController.hasClients) {
              const edge = 80.0;
              const speed = 6.0; // 느린 가로 오토 스크롤 속도
              final pos = hController.position;
              if (local.dx < edge) {
                final next = (pos.pixels - speed).clamp(
                  0.0,
                  pos.maxScrollExtent,
                );
                if (next != pos.pixels) hController.jumpTo(next);
              } else if (local.dx > box.size.width - edge) {
                final next = (pos.pixels + speed).clamp(
                  0.0,
                  pos.maxScrollExtent,
                );
                if (next != pos.pixels) hController.jumpTo(next);
              }
            }
          }
        } catch (_) {}
      },
      onLeave: (data) {
        // 프리뷰 슬롯 리셋만 수행
        dragDropService.setReorderTargetIndex(null);
      },
      builder: (context, candidateData, rejectedData) {
        // 같은 카테고리 위에 있을 때는 하이라이트 비활성화
        final dragSvc = context.watch<PostDragDropService>();
        bool isOwnCategory = false;
        if (dragSvc.draggedPost != null) {
          switch (dragSvc.draggedPost!.accessLevel) {
            case AccessLevel.private:
              isOwnCategory = sec.title.contains('나만');
              break;
            case AccessLevel.public:
              isOwnCategory = sec.title.contains('전체');
              break;
            case AccessLevel.groups:
              isOwnCategory = sec.title.contains('그룹');
              break;
          }
        }
        final bool isHighlighted = candidateData.isNotEmpty && !isOwnCategory;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            decoration: BoxDecoration(
              color:
                  isHighlighted
                      ? theme.colorScheme.onSurface.withOpacity(0.1)
                      : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sec.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color:
                                isHighlighted
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface.withOpacity(
                                      0.8,
                                    ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          context
                              .read<CategoryOverlayProvider>()
                              .showCategoryOverlay(
                                context,
                                sec.title,
                                sec.posts,
                              );
                        },
                        child: Icon(
                          Icons.chevron_right,
                          color:
                              isHighlighted
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withOpacity(
                                    0.7,
                                  ),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  height: height,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double cardWidth =
                            displayMode == FeedDisplayMode.imageOnly
                                ? height * 4 / 5
                                : math.min(constraints.maxWidth, 360.0);
                        _cachedCardWidth = cardWidth;
                        return Consumer<PostDragDropService>(
                          builder: (context, dragSvc, _) {
                            // 드래그 중이고 현재 섹션 위에 있을 때만 목표 인덱스 표시
                            final int? rawReorderIndex =
                                (dragSvc.isDragging &&
                                        dragSvc.targetCategory == sec.title)
                                    ? dragSvc.reorderTargetIndex
                                    : null;

                            // 원래 자기 위치면 스페이싱 미표시
                            int? reorderIndex = rawReorderIndex;
                            if (dragSvc.isDragging &&
                                dragSvc.targetCategory == sec.title &&
                                rawReorderIndex != null &&
                                dragSvc.draggedPost != null) {
                              final curIdx = sec.posts.indexWhere(
                                (p) => p.id == dragSvc.draggedPost!.id,
                              );
                              if (curIdx != -1 &&
                                  (rawReorderIndex == curIdx ||
                                      rawReorderIndex == curIdx + 1)) {
                                reorderIndex = null;
                              }
                            }

                            return Container(
                              margin: EdgeInsets.only(bottom: 10),
                              key: listKey,
                              child: ListView.builder(
                                controller: hController,
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                itemCount:
                                    sec.posts.length +
                                    ((reorderIndex != null) ? 1 : 0),
                                itemBuilder: (context, i) {
                                  // 인서트 가상 슬롯
                                  if (reorderIndex != null &&
                                      i == reorderIndex) {
                                    return const SizedBox(width: 18);
                                  }

                                  // 실제 데이터 인덱스로 매핑
                                  final dataIndex =
                                      (reorderIndex != null && i > reorderIndex)
                                          ? i - 1
                                          : i;
                                  final post = sec.posts[dataIndex];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 5),
                                    child: SizedBox(
                                      width: cardWidth,
                                      child:
                                          displayMode == FeedDisplayMode.card
                                              ? _buildHorizontalCard(
                                                context,
                                                post,
                                                dataIndex,
                                              )
                                              : _buildImageOnlyCard(
                                                context,
                                                post,
                                                dataIndex,
                                              ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 가로 카드: 썸네일 + 텍스트 미리보기
  Widget _buildHorizontalCard(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);
    final dragDropService = context.read<PostDragDropService>();

    return LongPressDraggable<PostData>(
      data: post,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        dragDropService.beginDrag(post);
      },
      onDragUpdate: (details) {
        dragDropService.updateDragPosition(details.globalPosition);
      },
      onDragEnd: (details) {
        dragDropService.endDrag();
      },
      feedback: _buildDragFeedbackCard(context, post),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openPost(context, post, index),
              child: Row(
                children: [
                  // 썸네일
                  ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                    child: AspectRatio(
                      aspectRatio: 4 / 5,
                      child: CachedNetworkImage(
                        imageUrl: post.thumbnailImageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // 텍스트
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            post.title,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            post.parsedContent,
                            style: TextStyle(
                              fontWeight: FontWeight.w300,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 14,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openPost(context, post, index),
            child: Row(
              children: [
                // 썸네일
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: CachedNetworkImage(
                      imageUrl: post.thumbnailImageUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                // 텍스트
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          post.title,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          post.parsedContent,
                          style: TextStyle(
                            fontWeight: FontWeight.w300,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 이미지 전용 카드 (썸네일만 꽉 차게)
  Widget _buildImageOnlyCard(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);
    final dragDropService = context.read<PostDragDropService>();

    return LongPressDraggable<PostData>(
      data: post,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        dragDropService.beginDrag(post);
      },
      onDragUpdate: (details) {
        dragDropService.updateDragPosition(details.globalPosition);
      },
      onDragEnd: (details) {
        dragDropService.endDrag();
      },
      feedback: _buildDragFeedbackImage(context, post),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openPost(context, post, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: post.thumbnailImageUrl,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => ShimmerBox(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.circular(14),
                    ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openPost(context, post, index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: post.thumbnailImageUrl,
              fit: BoxFit.cover,
              placeholder:
                  (context, url) => ShimmerBox(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.circular(14),
                  ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
          ),
        ),
      ),
    );
  }

  // Draggable feedbacks
  Widget _buildDragFeedbackCard(BuildContext context, PostData post) {
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.95,
        child: Container(
          width: 280,
          height: 180,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 4 / 5,
                child: CachedNetworkImage(
                  imageUrl: post.thumbnailImageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        post.title,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.parsedContent,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragFeedbackImage(BuildContext context, PostData post) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 160,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
          ),
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
