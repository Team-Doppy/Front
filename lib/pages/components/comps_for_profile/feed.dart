import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/group_provider.dart';
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
          // 섹션 이동
          if (sec.title.contains('그룹')) {
            // 그룹공개로 이동할 때는 그룹 선택 다이얼로그 표시
            _showGroupSelectionDialog(context, data, dragDropService);
          } else {
            // 나만보기, 전체공개로 이동할 때는 바로 적용
            int targetIndex = (dragDropService.reorderTargetIndex ?? 0).clamp(
              0,
              sec.posts.length,
            );
            AccessLevel level =
                sec.title.contains('나만')
                    ? AccessLevel.private
                    : AccessLevel.public;
            context.read<ProfileFeedProvider>().moveToAccessLevelAtIndex(
              data.id,
              level,
              targetIndex,
            );
          }
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
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        context
                            .read<CategoryOverlayProvider>()
                            .showCategoryOverlay(context, sec.title, sec.posts);
                      },
                      child: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
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
                                if (reorderIndex != null && i == reorderIndex) {
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

  // 그룹 선택 다이얼로그 표시
  void _showGroupSelectionDialog(
    BuildContext context,
    PostData post,
    PostDragDropService dragDropService,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => _GroupSelectionBottomSheet(
            post: post,
            onGroupSelected: (selectedGroupIds) {
              // 선택된 그룹으로 포스트 이동
              if (selectedGroupIds.isNotEmpty) {
                int targetIndex = (dragDropService.reorderTargetIndex ?? 0)
                    .clamp(0, context.read<ProfileFeedProvider>().posts.length);
                context.read<ProfileFeedProvider>().moveToAccessLevelAtIndex(
                  post.id,
                  AccessLevel.groups,
                  targetIndex,
                );
              }
              // 드래그 상태 리셋
              dragDropService.setReorderTargetIndex(null);
            },
          ),
    );
  }
}

// 그룹 선택 바텀시트
class _GroupSelectionBottomSheet extends StatefulWidget {
  final PostData post;
  final Function(List<int>) onGroupSelected;

  const _GroupSelectionBottomSheet({
    required this.post,
    required this.onGroupSelected,
  });

  @override
  State<_GroupSelectionBottomSheet> createState() =>
      _GroupSelectionBottomSheetState();
}

class _GroupSelectionBottomSheetState
    extends State<_GroupSelectionBottomSheet> {
  Set<int> _selectedGroupIds = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 16, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 헤더 섹션
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '공유 그룹 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),

                // 포스트 미리보기 카드
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 썸네일
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          widget.post.thumbnailImageUrl,
                          fit: BoxFit.cover,
                          width: 80,
                          height: 100,
                          errorBuilder:
                              (context, error, stackTrace) => Container(
                                width: 80,
                                height: 100,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceVariant,
                                child: Icon(
                                  Icons.image,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // 포스트 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.post.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.post.parsedContent,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 그룹 목록
          Expanded(
            child: Consumer<GroupProvider>(
              builder: (context, groupProvider, _) {
                if (groupProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final groups = groupProvider.myGroups;
                if (groups.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '아직 그룹이 없어요',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final isSelected = _selectedGroupIds.contains(group.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1)
                                : Theme.of(
                                  context,
                                ).colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              isSelected
                                  ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.3)
                                  : Theme.of(
                                    context,
                                  ).colorScheme.outline.withOpacity(0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedGroupIds.remove(group.id);
                              } else {
                                _selectedGroupIds.add(group.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // 그룹 아바타
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                            : Theme.of(
                                              context,
                                            ).colorScheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      group.name.substring(0, 1).toUpperCase(),
                                      style: TextStyle(
                                        color:
                                            isSelected
                                                ? Colors.white
                                                : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // 그룹 정보
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        group.description,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // 선택 아이콘
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child:
                                      isSelected
                                          ? Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 16,
                                          )
                                          : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 하단 버튼
          Container(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.3),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      '취소',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _selectedGroupIds.isEmpty
                            ? null
                            : () {
                              Navigator.of(context).pop();
                              widget.onGroupSelected(
                                _selectedGroupIds.toList(),
                              );
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _selectedGroupIds.isEmpty
                              ? Theme.of(context).colorScheme.surfaceVariant
                              : Theme.of(context).colorScheme.primary,
                      foregroundColor:
                          _selectedGroupIds.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: _selectedGroupIds.isEmpty ? 0 : 2,
                      shadowColor: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_selectedGroupIds.isNotEmpty) ...[
                          Icon(Icons.share, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          '공유하기 (${_selectedGroupIds.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
