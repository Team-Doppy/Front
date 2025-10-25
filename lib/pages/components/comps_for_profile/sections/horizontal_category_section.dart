import 'dart:math' as math;
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/category_model.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/image_view.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';

import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// feed.dart의 `_buildHorizontalSection`을 클래스로 분리한 컴포넌트
class HorizontalCategorySection extends StatefulWidget {
  const HorizontalCategorySection({
    super.key,
    this.showHeader = false,
    required this.title,
    required this.categoryId,
    required this.posts,
    required this.sectionIndex,
    required this.displayMode,
    required this.isLastSection,
    required this.categoryDropTargetIndex,
    required this.draggingSectionIndex,
    required this.isDraggingCategory,
    required this.mainScrollController,
    this.onDragStateChanged,
  });

  final bool showHeader;
  final String title;
  final String? categoryId;
  final List<PostData> posts;
  final int sectionIndex;
  final dynamic displayMode; // FeedDisplayMode
  final bool isLastSection;
  final ValueListenable<int?> categoryDropTargetIndex;
  final ValueListenable<int?> draggingSectionIndex;
  final ValueListenable<bool> isDraggingCategory;
  final ScrollController? mainScrollController;
  final VoidCallback? onDragStateChanged;

  @override
  State<HorizontalCategorySection> createState() =>
      _HorizontalCategorySectionState();
}

class _HorizontalCategorySectionState extends State<HorizontalCategorySection> {
  final GlobalKey _listKey = GlobalKey();
  int? _imageDropTargetIndex;
  int? _draggingImageIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = context.read<UserProvider>().currentUser?.username;
    final isReadOnly = context.read<BaseFeedProvider>().isReadOnly;
    final height = 200.0;
    final hController = context
        .read<PostDragDropService>()
        .horizontalControllerFor(widget.title);

    // 미분류 카테고리가 비어있으면 숨김
    final isSystemCategoryEmpty =
        widget.categoryId == '0' && widget.posts.isEmpty;

    return isSystemCategoryEmpty
        ? SizedBox.shrink()
        : ValueListenableBuilder<int?>(
          valueListenable: widget.categoryDropTargetIndex,
          builder: (context, dropTargetIdx, _) {
            final currentSectionIndex = widget.sectionIndex;
            return DragTarget<CategoryMetaData>(
              onWillAccept: (_) => !isReadOnly,
              onMove: (details) {
                try {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    final dy = details.offset.dy; // global Y
                    final topLeft = box.localToGlobal(Offset.zero);
                    final rect = Rect.fromLTWH(
                      topLeft.dx,
                      topLeft.dy,
                      box.size.width,
                      box.size.height,
                    );
                    final localY = dy - rect.top;
                    final h = rect.height;
                    final bottomSnap = math.max(36.0, h * 0.22);
                    final topSnap = math.max(24.0, h * 0.18);

                    int targetIndex;
                    if (localY <= topSnap) {
                      targetIndex = currentSectionIndex;
                    } else if (localY >= h - bottomSnap) {
                      // 널널한 바닥 스냅: 마지막 줄 근처에서는 아래로 드롭 처리
                      targetIndex = currentSectionIndex + 1;
                    } else {
                      targetIndex =
                          localY >= h / 2
                              ? currentSectionIndex + 1
                              : currentSectionIndex;
                    }

                    final notifier =
                        widget.categoryDropTargetIndex as ValueNotifier<int?>;
                    notifier.value = targetIndex;
                  }

                  // 글로벌 좌표 기준 메인 스크롤 엣지 처리
                  final sc = widget.mainScrollController;
                  if (sc != null && sc.hasClients) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final globalY = details.offset.dy;
                    const edge = 100.0;
                    const speed = 14.0;
                    final pos = sc.position;
                    if (globalY < edge) {
                      final next = (pos.pixels - speed).clamp(
                        0.0,
                        pos.maxScrollExtent,
                      );
                      if (next != pos.pixels) sc.jumpTo(next);
                    } else if (globalY > screenHeight - edge) {
                      final next = (pos.pixels + speed).clamp(
                        0.0,
                        pos.maxScrollExtent,
                      );
                      if (next != pos.pixels) sc.jumpTo(next);
                    }
                  }
                } catch (_) {}
              },
              onLeave:
                  (_) =>
                      (widget.categoryDropTargetIndex as ValueNotifier<int?>)
                          .value = null,
              onAccept: (draggedMeta) async {
                if (isReadOnly) return;
                final pf = context.read<MyProfileFeedProvider>();
                final prev =
                    pf.categories.map((c) => c['id'].toString()).toList();
                final draggedId = draggedMeta.categoryId ?? '';
                if (draggedId.isEmpty) return;
                final targetRaw =
                    (widget.categoryDropTargetIndex.value ??
                        currentSectionIndex);
                final targetIdx = targetRaw.clamp(0, prev.length);
                final next = List<String>.from(prev)..remove(draggedId);
                if (targetIdx <= next.length) next.insert(targetIdx, draggedId);
                if (!listEquals(prev, next)) {
                  await pf.reorderAllSections(next);
                }
                (widget.categoryDropTargetIndex as ValueNotifier<int?>).value =
                    null;
              },
              builder: (context, candidateData, rejectedData) {
                final bool hasCandidate = candidateData.isNotEmpty;
                final bool showTopLine =
                    hasCandidate && dropTargetIdx == currentSectionIndex;
                final bool showBottomLine =
                    hasCandidate && dropTargetIdx == currentSectionIndex + 1;
                return Stack(
                  children: [
                    Column(
                      children: [
                        // 헤더 - 섹션 드래그 소스 + 포스트 드롭 타겟 + 드롭라인 오버레이
                        if (widget.showHeader)
                          DragTarget<PostData>(
                            onWillAccept: (draggedPost) {
                              // 다른 카테고리에서 온 포스트만 받음
                              if (isReadOnly || widget.categoryId == null)
                                return false;
                              return true;
                            },
                            onAccept: (draggedPost) async {
                              if (widget.categoryId == null) return;
                              print(
                                '[HorizontalCategorySection] 헤더에 포스트 드롭: ${draggedPost.title} -> 카테고리 ${widget.categoryId}',
                              );
                              // 카테고리 간 이동: 맨 앞(position 0)에 삽입
                              final pf = context.read<BaseFeedProvider>();
                              await context
                                  .read<PostDragDropService>()
                                  .movePostToCategoryWithContext(
                                    context,
                                    draggedPost,
                                    int.parse(widget.categoryId!),
                                    targetPosition: 0,
                                    provider: pf,
                                  );
                            },
                            builder: (
                              context,
                              candidatePostData,
                              rejectedPostData,
                            ) {
                              return Stack(
                                children: [
                                  LongPressDraggable<CategoryMetaData>(
                                    data: CategoryMetaData(
                                      title: widget.title,
                                      posts: widget.posts,
                                      categoryId: widget.categoryId,
                                    ),
                                    dragAnchorStrategy:
                                        pointerDragAnchorStrategy,
                                    feedback: _buildCategoryFeedback(
                                      context,
                                      theme,
                                      CategoryMetaData(
                                        title: widget.title,
                                        posts: widget.posts,
                                        categoryId: widget.categoryId,
                                      ),
                                      widget.displayMode,
                                    ),
                                    onDragStarted: () {
                                      (widget.isDraggingCategory
                                              as ValueNotifier<bool>)
                                          .value = true;
                                      (widget.draggingSectionIndex
                                              as ValueNotifier<int?>)
                                          .value = currentSectionIndex;
                                      widget.onDragStateChanged?.call();
                                    },
                                    onDragUpdate: (details) {
                                      final sc = widget.mainScrollController;
                                      if (sc != null && sc.hasClients) {
                                        final screenHeight =
                                            MediaQuery.of(context).size.height;
                                        final globalY =
                                            details.globalPosition.dy;
                                        const edge = 100.0;
                                        const speed = 14.0;
                                        final pos = sc.position;
                                        if (globalY < edge) {
                                          final next = (pos.pixels - speed)
                                              .clamp(0.0, pos.maxScrollExtent);
                                          if (next != pos.pixels)
                                            sc.jumpTo(next);
                                        } else if (globalY >
                                            screenHeight - edge) {
                                          final next = (pos.pixels + speed)
                                              .clamp(0.0, pos.maxScrollExtent);
                                          if (next != pos.pixels)
                                            sc.jumpTo(next);
                                        }
                                      }
                                    },
                                    onDragEnd: (_) {
                                      (widget.isDraggingCategory
                                              as ValueNotifier<bool>)
                                          .value = false;
                                      (widget.categoryDropTargetIndex
                                              as ValueNotifier<int?>)
                                          .value = null;
                                      (widget.draggingSectionIndex
                                              as ValueNotifier<int?>)
                                          .value = null;
                                      widget.onDragStateChanged?.call();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child:
                                          widget.showHeader
                                              ? Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _getCategoryDisplayTitle(
                                                        widget.title,
                                                        widget.categoryId,
                                                        username,
                                                      ),
                                                      style: theme
                                                          .textTheme
                                                          .titleLarge
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 18,
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface
                                                                .withOpacity(
                                                                  0.8,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                              : SizedBox.shrink(),
                                    ),
                                  ),
                                  Positioned(
                                    left: 16,
                                    right: 16,
                                    top: 0,
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      curve: Curves.easeOut,
                                      opacity: showTopLine ? 1.0 : 0.0,
                                      child: IgnorePointer(
                                        ignoring: true,
                                        child: Container(
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        // 수평 컨텐츠 리스트
                        if (widget.posts.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            height: widget.showHeader ? height : height + 10,
                            child: Padding(
                              padding: EdgeInsets.zero,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final double cardWidth =
                                      widget.displayMode.toString().contains(
                                            'imageOnly',
                                          )
                                          ? height * 4 / 5
                                          : math.min(
                                            constraints.maxWidth,
                                            360.0,
                                          );
                                  return ValueListenableBuilder<bool>(
                                    valueListenable: widget.isDraggingCategory,
                                    builder: (context, isDragging, _) {
                                      return Opacity(
                                        opacity: isDragging ? 0.3 : 1.0,
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
                                          key: _listKey,
                                          child: ListView.builder(
                                            controller: hController,
                                            scrollDirection: Axis.horizontal,
                                            padding: EdgeInsets.zero,
                                            itemCount:
                                                widget.posts.length +
                                                (isReadOnly ? 0 : 1),
                                            itemBuilder: (context, i) {
                                              final categoryId =
                                                  widget.categoryId;

                                              // 마지막 아이템 다음: 꼬리 드롭 타겟
                                              if (i == widget.posts.length) {
                                                return DragTarget<PostData>(
                                                  onWillAccept: (_) => true,
                                                  onMove: (_) {
                                                    setState(
                                                      () =>
                                                          _imageDropTargetIndex =
                                                              widget
                                                                  .posts
                                                                  .length,
                                                    );
                                                  },
                                                  onLeave: (_) {
                                                    setState(
                                                      () =>
                                                          _imageDropTargetIndex =
                                                              null,
                                                    );
                                                  },
                                                  onAccept: (
                                                    draggedPost,
                                                  ) async {
                                                    if (categoryId == null)
                                                      return;
                                                    final draggedIndex = widget
                                                        .posts
                                                        .indexOf(draggedPost);
                                                    final targetIndex =
                                                        widget.posts.length;

                                                    // 같은 카테고리 내에서 이동
                                                    if (draggedIndex != -1) {
                                                      print(
                                                        '[ImageOnly] 같은 카테고리 끝 위치 드롭: $draggedIndex -> $targetIndex',
                                                      );

                                                      // 같은 카테고리 내 순서 변경: 서버에도 저장
                                                      await _reorderPostsInCategoryWithServer(
                                                        context,
                                                        int.parse(categoryId),
                                                        draggedPost.id,
                                                        targetIndex,
                                                      );
                                                    } else {
                                                      // 다른 카테고리에서 이동 (카테고리 이동 + 맨 끝에 배치)
                                                      print(
                                                        '[ImageOnly] 다른 카테고리에서 끝 위치로 이동: ${draggedPost.title} -> 카테고리 $categoryId, 위치 $targetIndex',
                                                      );
                                                      await context
                                                          .read<
                                                            PostDragDropService
                                                          >()
                                                          .movePostToCategoryWithContext(
                                                            context,
                                                            draggedPost,
                                                            int.parse(
                                                              categoryId,
                                                            ),
                                                            targetPosition:
                                                                targetIndex,
                                                          );
                                                    }
                                                    setState(
                                                      () =>
                                                          _imageDropTargetIndex =
                                                              null,
                                                    );
                                                  },
                                                  builder: (
                                                    context,
                                                    candidateData,
                                                    rejectedData,
                                                  ) {
                                                    final showLine =
                                                        candidateData
                                                            .isNotEmpty &&
                                                        _imageDropTargetIndex ==
                                                            widget
                                                                .posts
                                                                .length &&
                                                        _draggingImageIndex !=
                                                            widget
                                                                    .posts
                                                                    .length -
                                                                1;
                                                    return Stack(
                                                      children: [
                                                        Container(
                                                          width: 40,
                                                          height: height,
                                                          color:
                                                              Colors
                                                                  .transparent,
                                                        ),
                                                        if (showLine)
                                                          Positioned(
                                                            left: 0,
                                                            top: 0,
                                                            bottom: 0,
                                                            child: AnimatedOpacity(
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        300,
                                                                  ),
                                                              curve:
                                                                  Curves
                                                                      .easeOut,
                                                              opacity: 1.0,
                                                              child: IgnorePointer(
                                                                child: Container(
                                                                  margin:
                                                                      const EdgeInsets.symmetric(
                                                                        vertical:
                                                                            5,
                                                                      ),
                                                                  width: 5,
                                                                  decoration: BoxDecoration(
                                                                    color:
                                                                        theme
                                                                            .colorScheme
                                                                            .primary,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              }

                                              // 일반 아이템
                                              final post = widget.posts[i];

                                              if (isReadOnly ||
                                                  categoryId == null) {
                                                return SizedBox(
                                                  width: cardWidth,
                                                  child: GestureDetector(
                                                    onTap:
                                                        () => _openPost(
                                                          context,
                                                          post,
                                                          i,
                                                        ),
                                                    child: ImageView(
                                                      post: post,
                                                    ),
                                                  ),
                                                );
                                              }

                                              return DragTarget<PostData>(
                                                onWillAccept: (data) {
                                                  return true;
                                                },
                                                onMove: (details) {
                                                  // 기본적으로 현재 인덱스 타겟
                                                  setState(
                                                    () =>
                                                        _imageDropTargetIndex =
                                                            i,
                                                  );
                                                },
                                                onLeave: (_) {
                                                  setState(
                                                    () =>
                                                        _imageDropTargetIndex =
                                                            null,
                                                  );
                                                },
                                                onAccept: (draggedPost) async {
                                                  final draggedIndex = widget
                                                      .posts
                                                      .indexOf(draggedPost);
                                                  final targetIndex =
                                                      _imageDropTargetIndex ??
                                                      i;

                                                  // 같은 카테고리 내에서 이동
                                                  if (draggedIndex != -1) {
                                                    if (draggedIndex ==
                                                        targetIndex) {
                                                      setState(
                                                        () =>
                                                            _imageDropTargetIndex =
                                                                null,
                                                      );
                                                      return;
                                                    }
                                                    print(
                                                      '[ImageOnly] 같은 카테고리 내 순서 변경: $draggedIndex -> $targetIndex (categoryId: $categoryId)',
                                                    );

                                                    // 같은 카테고리 내 순서 변경: 서버에도 저장
                                                    await _reorderPostsInCategoryWithServer(
                                                      context,
                                                      int.parse(categoryId),
                                                      draggedPost.id,
                                                      targetIndex,
                                                    );
                                                  } else {
                                                    // 다른 카테고리에서 이동 (카테고리 이동 + 순서 지정)
                                                    print(
                                                      '[ImageOnly] 다른 카테고리에서 이동: ${draggedPost.title} -> 카테고리 $categoryId, 위치 $targetIndex',
                                                    );
                                                    await context
                                                        .read<
                                                          PostDragDropService
                                                        >()
                                                        .movePostToCategoryWithContext(
                                                          context,
                                                          draggedPost,
                                                          int.parse(categoryId),
                                                          targetPosition:
                                                              targetIndex,
                                                        );
                                                  }
                                                  setState(
                                                    () =>
                                                        _imageDropTargetIndex =
                                                            null,
                                                  );
                                                },
                                                builder: (
                                                  context,
                                                  candidateData,
                                                  rejectedData,
                                                ) {
                                                  // 드롭라인 표시 조건:
                                                  // 왼쪽 라인: 현재 위치가 타겟이고, 자기/바로 왼쪽이 아닐 때
                                                  // 오른쪽 라인: 마지막 아이템이고, 타겟이 마지막+1일 때
                                                  final bool hasCandidate =
                                                      candidateData.isNotEmpty;
                                                  final bool isTargeted =
                                                      _imageDropTargetIndex ==
                                                      i;
                                                  final bool isSelfOrLeft =
                                                      _draggingImageIndex ==
                                                          i ||
                                                      _draggingImageIndex ==
                                                          i - 1;
                                                  final showLeftLine =
                                                      hasCandidate &&
                                                      isTargeted &&
                                                      !isSelfOrLeft;

                                                  final bool isLastItem =
                                                      i ==
                                                      widget.posts.length - 1;
                                                  final bool showRightLine =
                                                      hasCandidate &&
                                                      isLastItem &&
                                                      _imageDropTargetIndex ==
                                                          widget.posts.length &&
                                                      _draggingImageIndex != i;

                                                  return Stack(
                                                    children: [
                                                      Container(
                                                        width: cardWidth,

                                                        child: LongPressDraggable<
                                                          PostData
                                                        >(
                                                          data: post,
                                                          dragAnchorStrategy: (
                                                            draggable,
                                                            context,
                                                            position,
                                                          ) {
                                                            // 이미지 중앙이 손가락 끝에 오도록 조정
                                                            // cardWidth = height * 4/5 = 200 * 4/5 = 160
                                                            // 중앙 오프셋: width/2 = 80, height/2 = 100
                                                            return Offset(
                                                              cardWidth *
                                                                      0.9 /
                                                                      2 +
                                                                  10, // scale 0.9 적용된 너비의 절반
                                                              height * 0.9 / 2 +
                                                                  20, // scale 0.9 적용된 높이의 절반
                                                            );
                                                          },
                                                          onDragStarted: () {
                                                            print(
                                                              '[ImageOnly] 포스트 드래그 시작: ${post.title}, index: $i',
                                                            );
                                                            setState(
                                                              () =>
                                                                  _draggingImageIndex =
                                                                      i,
                                                            );
                                                          },
                                                          onDragUpdate: (
                                                            details,
                                                          ) {
                                                            // 가로 스크롤 엣지 감지
                                                            if (hController
                                                                .hasClients) {
                                                              final screenWidth =
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.width;
                                                              final globalX =
                                                                  details
                                                                      .globalPosition
                                                                      .dx;
                                                              const edge = 80.0;
                                                              const speed =
                                                                  12.0;
                                                              final pos =
                                                                  hController
                                                                      .position;
                                                              if (globalX <
                                                                  edge) {
                                                                final next = (pos
                                                                            .pixels -
                                                                        speed)
                                                                    .clamp(
                                                                      0.0,
                                                                      pos.maxScrollExtent,
                                                                    );
                                                                if (next !=
                                                                    pos.pixels) {
                                                                  hController
                                                                      .jumpTo(
                                                                        next,
                                                                      );
                                                                }
                                                              } else if (globalX >
                                                                  screenWidth -
                                                                      edge) {
                                                                final next = (pos
                                                                            .pixels +
                                                                        speed)
                                                                    .clamp(
                                                                      0.0,
                                                                      pos.maxScrollExtent,
                                                                    );
                                                                if (next !=
                                                                    pos.pixels) {
                                                                  hController
                                                                      .jumpTo(
                                                                        next,
                                                                      );
                                                                }
                                                              }
                                                            }

                                                            // 메인 스크롤 컨트롤러 연동 (세로)
                                                            final sc =
                                                                widget
                                                                    .mainScrollController;
                                                            if (sc != null &&
                                                                sc.hasClients) {
                                                              final screenHeight =
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.height;
                                                              final globalY =
                                                                  details
                                                                      .globalPosition
                                                                      .dy;
                                                              const edge =
                                                                  100.0;
                                                              const speed =
                                                                  14.0;
                                                              final pos =
                                                                  sc.position;
                                                              if (globalY <
                                                                  edge) {
                                                                final next = (pos
                                                                            .pixels -
                                                                        speed)
                                                                    .clamp(
                                                                      0.0,
                                                                      pos.maxScrollExtent,
                                                                    );
                                                                if (next !=
                                                                    pos.pixels) {
                                                                  sc.jumpTo(
                                                                    next,
                                                                  );
                                                                }
                                                              } else if (globalY >
                                                                  screenHeight -
                                                                      edge) {
                                                                final next = (pos
                                                                            .pixels +
                                                                        speed)
                                                                    .clamp(
                                                                      0.0,
                                                                      pos.maxScrollExtent,
                                                                    );
                                                                if (next !=
                                                                    pos.pixels) {
                                                                  sc.jumpTo(
                                                                    next,
                                                                  );
                                                                }
                                                              }
                                                            }
                                                          },
                                                          onDragEnd: (_) {
                                                            print(
                                                              '[ImageOnly] 포스트 드래그 종료',
                                                            );
                                                            setState(() {
                                                              _imageDropTargetIndex =
                                                                  null;
                                                              _draggingImageIndex =
                                                                  null;
                                                            });
                                                          },
                                                          feedback: Opacity(
                                                            opacity: 0.6,
                                                            child: Transform.scale(
                                                              scale: 0.9,
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              child: Material(
                                                                elevation: 8,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                                child: SizedBox(
                                                                  width:
                                                                      cardWidth,
                                                                  child:
                                                                      ImageView(
                                                                        post:
                                                                            post,
                                                                      ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          childWhenDragging:
                                                              Opacity(
                                                                opacity: 0.3,
                                                                child:
                                                                    ImageView(
                                                                      post:
                                                                          post,
                                                                    ),
                                                              ),
                                                          child: GestureDetector(
                                                            onTap:
                                                                () => _openPost(
                                                                  context,
                                                                  post,
                                                                  i,
                                                                ),
                                                            child: ImageView(
                                                              post: post,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      // 왼쪽 드롭라인
                                                      Positioned(
                                                        left: 0,
                                                        top: 0,
                                                        bottom: 0,
                                                        child: AnimatedOpacity(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    160,
                                                              ),
                                                          curve: Curves.easeOut,
                                                          opacity:
                                                              showLeftLine
                                                                  ? 1.0
                                                                  : 0.0,
                                                          child: IgnorePointer(
                                                            child: Container(
                                                              width: 5,
                                                              margin:
                                                                  const EdgeInsets.symmetric(
                                                                    vertical: 5,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    theme
                                                                        .colorScheme
                                                                        .primary,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      // 오른쪽 드롭라인 (마지막 아이템 꼬리 삽입용)
                                                      Positioned(
                                                        right: 0,
                                                        top: 0,
                                                        bottom: 0,
                                                        child: AnimatedOpacity(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    160,
                                                              ),
                                                          curve: Curves.easeOut,
                                                          opacity:
                                                              showRightLine
                                                                  ? 1.0
                                                                  : 0.0,
                                                          child: IgnorePointer(
                                                            child: Container(
                                                              width: 5,
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    theme
                                                                        .colorScheme
                                                                        .primary,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      2,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        if (widget.posts.isEmpty) ...[
                          DragTarget<PostData>(
                            onWillAccept: (draggedPost) {
                              if (isReadOnly || widget.categoryId == null)
                                return false;
                              return true;
                            },
                            onAccept: (draggedPost) async {
                              if (widget.categoryId == null) return;
                              print(
                                '[HorizontalCategorySection] 빈 카테고리에 포스트 드롭: ${draggedPost.title} -> 카테고리 ${widget.categoryId}',
                              );
                              // 카테고리 간 이동: 맨 앞(position 0)에 삽입
                              await context
                                  .read<PostDragDropService>()
                                  .movePostToCategoryWithContext(
                                    context,
                                    draggedPost,
                                    int.parse(widget.categoryId!),
                                    targetPosition: 0,
                                  );
                            },
                            builder: (context, candidateData, rejectedData) {
                              final bool acceptingPost =
                                  candidateData.isNotEmpty;
                              return Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color:
                                      widget.showHeader
                                          ? theme.colorScheme.surface
                                              .withOpacity(0.1)
                                          : Colors.transparent,
                                  borderRadius:
                                      acceptingPost
                                          ? BorderRadius.circular(12)
                                          : null,

                                  border:
                                      acceptingPost
                                          ? Border.all(
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.8),
                                            width: 0.5,
                                          )
                                          : null,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 50,
                                  ),
                                  child: Center(
                                    child: Text(
                                      acceptingPost
                                          ? '여기에 놓기'
                                          : '이 카테고리에 글이 없어요!',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.6),
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    // 섹션 전체 하단 드롭 라인 (마지막 섹션 꼬리 삽입 포함)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        opacity: showBottomLine ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: true,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
  }

  String _getCategoryDisplayTitle(
    String title,
    String? categoryId,
    String? username,
  ) {
    if (categoryId == '0') {
      return (username != null && username.isNotEmpty)
          ? '${username}의 다른 글'
          : '다른 글';
    }
    return title;
  }

  Widget _buildCategoryFeedback(
    BuildContext context,
    ThemeData theme,
    CategoryMetaData categoryMetaData,
    FeedDisplayMode displayMode,
  ) {
    return Transform.scale(
      scale: 0.8,
      child: Container(
        width: MediaQuery.of(context).size.width - 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildSectionFeedback(
            context,
            theme,
            categoryMetaData,
            displayMode,
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
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  /// 카테고리 내부 포스트 순서 변경을 서버에 저장하는 헬퍼 메서드
  Future<void> _reorderPostsInCategoryWithServer(
    BuildContext context,
    int categoryId,
    String movedPostId,
    int targetPosition,
  ) async {
    try {
      final provider = context.read<BaseFeedProvider>();

      // MyProfileFeedProvider인 경우에만 서버 저장 시도
      if (provider is MyProfileFeedProvider) {
        // 먼저 로컬에서 순서 변경
        provider.movePostLocally(movedPostId, categoryId, targetPosition);

        // 현재 카테고리의 모든 포스트 ID 순서 가져오기
        final categoryStr = categoryId.toString();
        final posts = provider.postsByCategory[categoryStr] ?? [];
        final orderedPostIds = posts.map((post) => '${post['id']}').toList();

        // 서버에 순서 변경 저장
        await provider.reorderPostsInCategory(categoryId, orderedPostIds);

        print('[HorizontalCategorySection] 카테고리 $categoryId 포스트 순서 서버 저장 완료');
      } else {
        // OtherProfileFeedProvider인 경우 로컬 변경만
        provider.movePostLocally(movedPostId, categoryId, targetPosition);
        print('[HorizontalCategorySection] 읽기 전용 프로필: 로컬 변경만 수행');
      }
    } catch (e) {
      print('⚠️ [HorizontalCategorySection] 포스트 순서 서버 저장 실패: $e');

      // 에러 발생 시 사용자에게 알림
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('포스트 순서 저장에 실패했습니다')));
      } catch (_) {}
    }
  }
}

// 섹션 미리보기 (헤더 + 콘텐츠)
Widget _buildSectionFeedback(
  BuildContext context,
  ThemeData theme,
  CategoryMetaData categoryMetaData,
  FeedDisplayMode displayMode,
) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 헤더
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                categoryMetaData.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
      // 콘텐츠 미리보기
      _buildContentPreview(context, theme, categoryMetaData, displayMode),
    ],
  );
}

// 콘텐츠 미리보기
Widget _buildContentPreview(
  BuildContext context,
  ThemeData theme,
  CategoryMetaData categoryMetaData,
  FeedDisplayMode displayMode,
) {
  return SizedBox(
    height: 100,
    child: Center(
      child: Text(
        '',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
          fontSize: 12,
        ),
      ),
    ),
  );
}
