import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/feed_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/providers/category_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/common/reorderable_grid_list.dart';
import 'package:doppy/common/card_mode_list.dart';

// 카테고리 섹션 메타 (파일 최상위)
class _FeedSectionMeta {
  const _FeedSectionMeta({
    required this.title,
    required this.posts,
    this.categoryId,
  });
  final String title;
  final List<PostData> posts;
  final String? categoryId;
}

class Feed {
  Widget buildFeedContent() {
    return ValueListenableBuilder<FeedDisplayMode>(
      valueListenable: FeedDisplayModeManager(),
      builder: (context, displayMode, _) {
        return Consumer2<ProfileFeedProvider, CategoryProvider>(
          builder: (context, feedProvider, catProvider, _) {
            final postsRaw = feedProvider.posts;

            if (feedProvider.isLoading && postsRaw.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            if (postsRaw.isEmpty) {
              // 포스트가 없더라도 카테고리가 있으면 빈 섹션 헤더를 표시
              final catProvider = context.watch<CategoryProvider?>();
              final hasCategories =
                  (catProvider?.categories.isNotEmpty ?? false);
              if (hasCategories) {
                final sections = <_FeedSectionMeta>[
                  for (final cat in catProvider!.categories)
                    _FeedSectionMeta(
                      title: cat.name,
                      posts: const [],
                      categoryId: cat.id,
                    ),
                ];
                // 섹션 헤더만 렌더링(빈 가로 리스트)
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final sec = sections[index];
                    return _buildHorizontalSection(context, sec, displayMode);
                  }, childCount: sections.length),
                );
              }
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

            // 2) 카테고리 기반 그룹핑 (사용자가 만든 카테고리만) + 선택 필터 반영
            final hasCategories = (catProvider.categories.isNotEmpty);

            // 활성 필터 확인: 사용자 카테고리 선택 또는 기본 탭 선택
            final bool hasSelection =
                (catProvider.selectedCategoryId != null) ||
                (catProvider.selectedBase != BaseFilter.all);
            print(
              '[Feed] hasSelection: $hasSelection, selectedCategoryId: ${catProvider.selectedCategoryId}, selectedBase: ${catProvider.selectedBase} (instance: ${catProvider.hashCode})',
            );

            if (hasSelection) {
              // 단일 그리드로 필터 결과 표시
              final isReadOnly = catProvider.isReadOnly;
              final List<PostData> filtered;
              if (catProvider.selectedCategoryId != null) {
                final String selId = catProvider.selectedCategoryId!;
                final cat = catProvider.categories.firstWhere(
                  (c) => c.id == selId,
                  orElse: () => CategoryModel(id: '', name: ''),
                );
                if (cat.id.isEmpty) {
                  filtered = const <PostData>[];
                } else {
                  final Map<String, PostData> idToPost = {
                    for (final p in allPosts) p.id: p,
                  };
                  filtered = [
                    for (final pid in cat.postIds)
                      if (idToPost[pid] != null) idToPost[pid]!,
                  ];
                }
              } else {
                // 기본 탭 필터 (전체/나만보기/그룹공유/전체공개)
                final base = catProvider.selectedBase;
                filtered =
                    allPosts.where((p) {
                      switch (base) {
                        case BaseFilter.private:
                          return p.accessLevel == AccessLevel.private;
                        case BaseFilter.groups:
                          return p.accessLevel == AccessLevel.groups;
                        case BaseFilter.public:
                          return p.accessLevel == AccessLevel.public;
                        case BaseFilter.all:
                          return true;
                      }
                    }).toList();
                print(
                  '[Feed] Base filter applied: $base, filtered count: ${filtered.length}, total posts: ${allPosts.length}',
                );
              }

              // 필터링 결과가 비어있는 경우 빈 상태 메시지 표시
              if (filtered.isEmpty) {
                final theme = Theme.of(context);
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 40,
                    ),
                    child: Center(
                      child: Text(
                        '아직 글이 없어요',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ),
                );
              }

              // 카드 모드에서는 세로 리스트로 표시 (순서변경 불가)
              if (displayMode == FeedDisplayMode.card) {
                // 전체 탭이 아니면 라벨 숨김
                final isAllTab =
                    catProvider.selectedCategoryId == null &&
                    catProvider.selectedBase == BaseFilter.all;
                return SliverToBoxAdapter(
                  child: CardModeList(
                    title: isAllTab ? catProvider.selectedLabel : '',
                    posts: filtered,
                    onPostTap:
                        (context, post, index) =>
                            _openPost(context, post, index),
                  ),
                );
              }

              // 이미지 전용 모드는 기존 그리드
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: ReorderableGridList(
                    sectionTitle: catProvider.selectedLabel,
                    items: filtered,
                    crossAxisCount: 3,
                    spacing: 6,
                    aspectRatio: 4 / 5,
                    readOnly: isReadOnly,
                    itemBuilder:
                        (context, post, index) =>
                            _buildGridThumb(context, post, index),
                    onAccept: (post, targetIndex) {
                      final cp = context.read<CategoryProvider?>();
                      final pf = context.read<ProfileFeedProvider>();
                      if (cp == null) return;
                      if (cp.selectedCategoryId != null) {
                        // 카테고리 선택: 동일 카테고리 내 재정렬 또는 이동
                        final curCatId = cp.categoryIdOf(post.id);
                        if (curCatId == cp.selectedCategoryId) {
                          cp.moveWithinCategory(
                            categoryId: cp.selectedCategoryId!,
                            postId: post.id,
                            targetIndex: targetIndex,
                          );
                        } else {
                          // 다른 카테고리/미분류에서 현재 카테고리로 이동
                          cp.assignToCategory(
                            categoryId: cp.selectedCategoryId!,
                            postId: post.id,
                            targetIndex: targetIndex,
                          );
                        }
                      } else {
                        // 기본 탭 선택: access level 재정렬/이동
                        final base = cp.selectedBase;
                        final AccessLevel level =
                            base == BaseFilter.private
                                ? AccessLevel.private
                                : base == BaseFilter.groups
                                ? AccessLevel.groups
                                : AccessLevel.public;
                        // 같은 레벨 내 재정렬
                        if (post.accessLevel == level) {
                          pf.moveWithinAccessLevel(post.id, level, targetIndex);
                        } else {
                          pf.moveToAccessLevelAtIndex(
                            post.id,
                            level,
                            targetIndex,
                          );
                        }
                      }
                    },
                  ),
                ),
              );
            }

            if (!hasCategories) {
              // 카테고리가 없으면 카드 모드에서는 세로 리스트, 이미지 전용 모드는 그리드
              final isReadOnly =
                  context.read<CategoryProvider?>()?.isReadOnly ?? false;

              if (displayMode == FeedDisplayMode.card) {
                // 전체 탭에서 다른 카테고리가 전혀 없을 때는 라벨을 숨기기 위해 빈 타이틀 전달
                return SliverToBoxAdapter(
                  child: CardModeList(
                    title: '',
                    posts: allPosts,
                    onPostTap:
                        (context, post, index) =>
                            _openPost(context, post, index),
                  ),
                );
              }

              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: ReorderableGridList(
                    sectionTitle: '다른 글',
                    items: allPosts,
                    crossAxisCount: 3,
                    spacing: 6,
                    aspectRatio: 4 / 5,
                    readOnly: isReadOnly,
                    itemBuilder:
                        (context, post, index) =>
                            _buildGridThumb(context, post, index),
                    onAccept: (post, targetIndex) {
                      // 카테고리 없음: 동일 섹션 내 UI 재정렬만 수행 (필요시 저장 로직 확장 가능)
                    },
                  ),
                ),
              );
            }

            // 카테고리가 있으면 섹션 구성
            final Map<String, PostData> idToPost = {
              for (final p in allPosts) p.id: p,
            };
            final sections = <_FeedSectionMeta>[];
            for (final cat in catProvider.categories) {
              final posts = <PostData>[];
              for (final pid in cat.postIds) {
                final p = idToPost[pid];
                if (p != null) posts.add(p);
              }
              sections.add(
                _FeedSectionMeta(
                  title: cat.name,
                  posts: posts,
                  categoryId: cat.id,
                ),
              );
            }
            // 미분류(카테고리 미지정)도 보여주기
            final unassigned =
                allPosts
                    .where((p) => catProvider.categoryIdOf(p.id) == null)
                    .toList();
            if (unassigned.isNotEmpty) {
              sections.add(
                _FeedSectionMeta(
                  title: '다른 글',
                  posts: unassigned,
                  categoryId: null,
                ),
              );
            }
            if (sections.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            // 4) 세로로 섹션을 쌓고,
            //    일반 카테고리는 가로 리스트,
            //    '다른 글'는 그리드로 구성
            return SliverToBoxAdapter(
              child: Column(
                children:
                    sections.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final sec = entry.value;
                      final Widget sectionWidget =
                          (sec.categoryId == null && sec.title == '다른 글')
                              ? _buildUnassignedGridSection(
                                context,
                                sec,
                                displayMode,
                              )
                              : _buildHorizontalSection(
                                context,
                                sec,
                                displayMode,
                              );
                      // 섹션 간 간격 추가
                      return Padding(
                        padding: EdgeInsets.only(top: idx == 0 ? 0 : 12),
                        child: sectionWidget,
                      );
                    }).toList(),
              ),
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

    final isReadOnly = context.read<CategoryProvider?>()?.isReadOnly ?? false;

    // 카드 모드에서는 새로운 CardModeList 사용
    if (displayMode == FeedDisplayMode.card) {
      return CardModeList(
        title: sec.title,
        posts: sec.posts,
        onPostTap: (context, post, index) => _openPost(context, post, index),
      );
    }
    return DragTarget<PostData>(
      onWillAccept: (data) {
        if (isReadOnly) return false;
        return data != null;
      },
      onAccept: (data) {
        // 드롭이 성공하면 해당 카테고리로 포스트 이동
        dragDropService.setDropTarget(sec.title);

        // 동일 섹션인지 판단 후, 동일 섹션이면 재정렬, 아니면 카테고리 이동
        bool isSameSection = false;
        final catProvider = context.read<CategoryProvider?>();
        if (catProvider != null) {
          final curCatId = catProvider.categoryIdOf(data.id);
          isSameSection =
              curCatId == sec.categoryId ||
              (curCatId == null && sec.categoryId == null);
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
          final catProvider = context.read<CategoryProvider?>();
          if (catProvider != null && sec.categoryId != null) {
            catProvider.moveWithinCategory(
              categoryId: sec.categoryId!,
              postId: data.id,
              targetIndex: targetIndex,
            );
          } else {
            context.read<ProfileFeedProvider>().moveWithinAccessLevel(
              data.id,
              data.accessLevel,
              targetIndex,
            );
          }
        } else {
          final targetIndex = (dragDropService.reorderTargetIndex ?? 0).clamp(
            0,
            sec.posts.length,
          );
          final catProvider = context.read<CategoryProvider?>();
          if (catProvider != null && sec.categoryId != null) {
            catProvider.assignToCategory(
              categoryId: sec.categoryId!,
              postId: data.id,
              targetIndex: targetIndex,
            );
          } else {
            // 기존 액세스 레벨 기반 이동 (fallback)
            if (sec.title.contains('그룹')) {
              _showGroupSelectionDialog(context, data, dragDropService);
            } else {
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

              if (sec.posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.background.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.surface.withOpacity(0.1),
                        width: 0.7,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '드래그해서 글을 이동해보세요',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.1),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: height,
                  child: Padding(
                    padding: EdgeInsets.zero,
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
                              margin: EdgeInsets.only(bottom: 14),
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
        );
      },
    );
  }

  // '미분류' 섹션: 헤더 + 3열 그리드
  Widget _buildUnassignedGridSection(
    BuildContext context,
    _FeedSectionMeta sec,
    FeedDisplayMode displayMode,
  ) {
    final theme = Theme.of(context);

    // 카드 모드에서는 CardModeList 사용
    if (displayMode == FeedDisplayMode.card) {
      return CardModeList(
        title: sec.title,
        posts: sec.posts,
        onPostTap: (context, post, index) => _openPost(context, post, index),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              children: [
                Text(
                  sec.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          if (sec.posts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '이 카테고리에 글이 없어요',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(1, 2, 1, 8),
              child: ReorderableGridList(
                sectionTitle: sec.title,
                items: sec.posts,
                crossAxisCount: 3,
                spacing: 6,
                aspectRatio: 4 / 5,
                readOnly:
                    context.read<CategoryProvider?>()?.isReadOnly ?? false,
                itemBuilder:
                    (context, post, index) =>
                        _buildGridThumb(context, post, index),
                onAccept: (post, targetIndex) {
                  final catProvider = context.read<CategoryProvider?>();
                  if (catProvider == null) return;
                  final currentCatId = catProvider.categoryIdOf(post.id);
                  if (currentCatId == null) {
                    // 미분류 내 재정렬은 여기서는 UI만 반영(Provider는 미보유)
                    // 확장 필요 시 전용 정렬 상태를 추가하여 반영 가능
                  } else {
                    // 카테고리에서 미분류로 이동
                    catProvider.movePostToCategory(
                      postId: post.id,
                      targetCategoryId: null,
                      targetPosition: targetIndex,
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  // 가로 카드: 썸네일 + 텍스트 미리보기
  Widget _buildHorizontalCard(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);
    final dragDropService = context.read<PostDragDropService>();
    final isReadOnly = context.read<CategoryProvider?>()?.isReadOnly ?? false;

    if (isReadOnly) {
      return _buildHorizontalCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      );
    }

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
      child: _buildHorizontalCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      ),
    );
  }

  Widget _buildHorizontalCardBody(
    BuildContext context,
    ThemeData theme,
    PostData post,
    int index, {
    required VoidCallback onTap,
  }) {
    return Container(
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
          onTap: onTap,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
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
    );
  }

  // 이미지 전용 카드 (썸네일만 꽉 차게)
  Widget _buildImageOnlyCard(BuildContext context, PostData post, int index) {
    final theme = Theme.of(context);
    final dragDropService = context.read<PostDragDropService>();
    final isReadOnly = context.read<CategoryProvider?>()?.isReadOnly ?? false;

    if (isReadOnly) {
      return _buildImageOnlyCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      );
    }

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
      child: _buildImageOnlyCardBody(
        context,
        theme,
        post,
        index,
        onTap: () => _openPost(context, post, index),
      ),
    );
  }

  Widget _buildImageOnlyCardBody(
    BuildContext context,
    ThemeData theme,
    PostData post,
    int index, {
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
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
    );
  }

  Widget _buildGridThumb(BuildContext context, PostData post, int index) {
    final dragDropService = context.read<PostDragDropService>();
    final isReadOnly = context.read<CategoryProvider?>()?.isReadOnly ?? false;

    if (isReadOnly) {
      return GestureDetector(
        onTap: () => _openPost(context, post, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
          ),
        ),
      ),
      child: GestureDetector(
        onTap: () => _openPost(context, post, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: post.thumbnailImageUrl,
            fit: BoxFit.cover,
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
