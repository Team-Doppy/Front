import 'dart:math' as math;
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/category_model.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/image_view.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/post_action_sheet.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 그리드 버전 카테고리 섹션 - 3개씩 여러 줄로 표시
class GridCategorySection extends StatefulWidget {
  const GridCategorySection({
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
  final dynamic displayMode;
  final bool isLastSection;
  final ValueListenable<int?> categoryDropTargetIndex;
  final ValueListenable<int?> draggingSectionIndex;
  final ValueListenable<bool> isDraggingCategory;
  final ScrollController? mainScrollController;
  final VoidCallback? onDragStateChanged;

  @override
  State<GridCategorySection> createState() => _GridCategorySectionState();
}

class _GridCategorySectionState extends State<GridCategorySection> {
  int? _postDropTargetIndex;
  int? _draggingPostIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = context.read<UserProvider>().currentUser?.username;
    final isReadOnly = context.read<BaseFeedProvider>().isReadOnly;
    final height = 200.0;

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
                    final dy = details.offset.dy;
                    final topLeft = box.localToGlobal(Offset.zero);
                    final rect = Rect.fromLTWH(
                      topLeft.dx,
                      topLeft.dy,
                      box.size.width,
                      box.size.height,
                    );
                    final String sectionKey =
                        '${widget.categoryId ?? widget.title}_row$currentSectionIndex';
                    context.read<PostDragDropService>().setHoverSectionKey(
                      sectionKey,
                    );
                    final localY = dy - rect.top;
                    final h = rect.height;
                    final bottomSnap = math.max(36.0, h * 0.22);
                    final topSnap = math.max(24.0, h * 0.18);

                    int targetIndex;
                    if (localY <= topSnap) {
                      targetIndex = currentSectionIndex;
                    } else if (localY >= h - bottomSnap) {
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
                } catch (_) {}

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
              },
              onLeave:
                  (_) =>
                      (widget.categoryDropTargetIndex as ValueNotifier<int?>)
                          .value = null,
              onAccept: (draggedMeta) async {
                if (isReadOnly) return;
                final pf = context.read<MyProfileFeedProvider>();

                final prev =
                    pf.categories
                        .where((c) {
                          final id = int.tryParse(c['id'].toString());
                          // 0번(미분류)도 포함해야 함
                          return id != null && id >= 0;
                        })
                        .map((c) => c['id'].toString())
                        .toList();

                final draggedId = draggedMeta.categoryId ?? '';
                if (draggedId.isEmpty) return;

                final targetRaw =
                    (widget.categoryDropTargetIndex.value ??
                        currentSectionIndex);
                final targetIdx = targetRaw.clamp(0, prev.length);
                final next = List<String>.from(prev)..remove(draggedId);
                // targetIdx가 범위를 넘으면 맨 끝에 추가
                final insertIdx =
                    targetIdx >= next.length ? next.length : targetIdx;
                next.insert(insertIdx, draggedId);

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
                    hasCandidate &&
                    widget.isLastSection &&
                    dropTargetIdx == currentSectionIndex + 1;
                return Stack(
                  children: [
                    Column(
                      children: [
                        // 헤더
                        if (widget.showHeader)
                          DragTarget<PostData>(
                            onWillAccept: (draggedPost) {
                              if (isReadOnly || widget.categoryId == null)
                                return false;
                              return true;
                            },
                            onAccept: (draggedPost) async {
                              if (widget.categoryId == null) return;
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
                                    feedback:
                                        context
                                                .read<BaseFeedProvider>()
                                                .isReadOnly
                                            ? const SizedBox.shrink()
                                            : _buildCategoryFeedback(
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
                                      final isReadOnly =
                                          context
                                              .read<BaseFeedProvider>()
                                              .isReadOnly;
                                      if (isReadOnly) return;
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
                                                            fontSize: 16,
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface
                                                                .withOpacity(
                                                                  0.8,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                  if (!context
                                                      .read<BaseFeedProvider>()
                                                      .isReadOnly)
                                                    Icon(
                                                      Icons.drag_indicator,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.4),
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
                                        child: Container(
                                          height: 6,
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
                        // 그리드 콘텐츠 - 3개씩 여러 줄로
                        if (widget.posts.isNotEmpty) ...[
                          ValueListenableBuilder<bool>(
                            valueListenable: widget.isDraggingCategory,
                            builder: (context, isDragging, _) {
                              final screenWidth =
                                  MediaQuery.of(context).size.width;
                              final cardWidth = screenWidth / 3;

                              return Opacity(
                                opacity: isDragging ? 0.3 : 1.0,
                                child: DragTarget<PostData>(
                                  onWillAccept: (_) => !isReadOnly,
                                  onMove: (details) {
                                    setState(
                                      () =>
                                          _postDropTargetIndex =
                                              widget.posts.length,
                                    );
                                  },
                                  onLeave: (_) {
                                    setState(() => _postDropTargetIndex = null);
                                  },
                                  onAccept: (draggedPost) async {
                                    final categoryIdInt = int.tryParse(
                                      widget.categoryId!,
                                    );
                                    if (categoryIdInt == null) {
                                      setState(
                                        () => _postDropTargetIndex = null,
                                      );
                                      return;
                                    }
                                    final targetIndex = widget.posts.length;
                                    if (widget.posts.contains(draggedPost)) {
                                      await _reorderPostsInCategoryWithServer(
                                        context,
                                        categoryIdInt,
                                        draggedPost.id,
                                        targetIndex,
                                      );
                                    } else {
                                      await context
                                          .read<PostDragDropService>()
                                          .movePostToCategoryWithContext(
                                            context,
                                            draggedPost,
                                            categoryIdInt,
                                            targetPosition: targetIndex,
                                          );
                                    }
                                    setState(() => _postDropTargetIndex = null);
                                  },
                                  builder: (
                                    context,
                                    candidateData,
                                    rejectedData,
                                  ) {
                                    final showDropTarget =
                                        !isReadOnly &&
                                        _postDropTargetIndex ==
                                            widget.posts.length &&
                                        _draggingPostIndex !=
                                            widget.posts.length - 1;

                                    return Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          child: GridView.builder(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 3,
                                                  mainAxisSpacing: 0,
                                                  crossAxisSpacing: 0,
                                                  childAspectRatio:
                                                      (screenWidth / 3) / 160,
                                                ),
                                            itemCount:
                                                widget.posts.length +
                                                (showDropTarget ? 1 : 0),
                                            itemBuilder: (context, index) {
                                              if (index ==
                                                  widget.posts.length) {
                                                return Stack(
                                                  children: [
                                                    // 빈 공간
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 5,
                                                          ),
                                                    ),
                                                    // 드롭 라인
                                                    Positioned(
                                                      left: 0,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: IgnorePointer(
                                                        child: Container(
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
                                                  ],
                                                );
                                              }
                                              return _buildGridItem(
                                                context,
                                                theme,
                                                widget.posts[index],
                                                index,
                                                cardWidth,
                                                isReadOnly,
                                                widget.categoryId,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            },
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
                        if (widget.isLastSection) const SizedBox(height: 20),
                      ],
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 6,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        opacity: showBottomLine ? 1.0 : 0.0,
                        child: IgnorePointer(
                          child: Container(
                            height: 6,
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

  Widget _buildGridItem(
    BuildContext context,
    ThemeData theme,
    PostData post,
    int index,
    double cardWidth,
    bool isReadOnly,
    String? categoryId,
  ) {
    final categoryIdInt = int.tryParse(categoryId ?? '');
    final isSystemCategory = categoryIdInt == null;

    if (isReadOnly || categoryId == null || isSystemCategory) {
      return SizedBox(
        width: cardWidth,
        child: GestureDetector(
          onTap: () => _openPost(context, post, index),
          onLongPress:
              !isSystemCategory
                  ? null
                  : () {
                    PostActionSheet.show(
                      context,
                      post: post,
                      onDelete: () {
                        // TODO: 구현
                      },
                      onMoveCategory: () {
                        // TODO: 구현
                      },
                      onChangeAccessLevel: () {
                        // TODO: 구현
                      },
                    );
                  },
          child: ImageView(post: post, isFirst: false, isLast: false),
        ),
      );
    }

    return DragTarget<PostData>(
      onWillAccept: (data) {
        print(
          '[GridCategorySection] onWillAccept: index=$index, data=${data?.id ?? 'null'}',
        );
        return true;
      },
      onMove: (details) {
        final String sectionKey =
            '${widget.categoryId ?? widget.title}_row${widget.sectionIndex}';
        context.read<PostDragDropService>().setHoverSectionKey(sectionKey);
        setState(() {
          _postDropTargetIndex = index;
          print(
            '[GridCategorySection] onMove: index=$index, targetIndex=$_postDropTargetIndex',
          );
        });
      },
      onLeave: (_) {
        print('[GridCategorySection] onLeave: index=$index');
        setState(() => _postDropTargetIndex = null);
      },
      onAccept: (draggedPost) async {
        final draggedIndex = widget.posts.indexOf(draggedPost);
        final targetIndex = _postDropTargetIndex ?? index;

        final categoryIdInt = int.tryParse(widget.categoryId!);
        if (categoryIdInt == null) {
          setState(() => _postDropTargetIndex = null);
          return;
        }

        // 같은 카테고리 내에서 이동
        if (draggedIndex != -1) {
          if (draggedIndex == targetIndex) {
            setState(() => _postDropTargetIndex = null);
            return;
          }
          print(
            '[GridCategorySection] 같은 카테고리 내 순서 변경: $draggedIndex -> $targetIndex',
          );

          // 같은 카테고리 내 순서 변경: 서버에도 저장
          await _reorderPostsInCategoryWithServer(
            context,
            categoryIdInt,
            draggedPost.id,
            targetIndex,
          );
        } else {
          // 다른 카테고리에서 이동
          print(
            '[GridCategorySection] 다른 카테고리에서 이동: ${draggedPost.title} -> 카테고리 ${widget.categoryId}, 위치 $targetIndex',
          );
          await context
              .read<PostDragDropService>()
              .movePostToCategoryWithContext(
                context,
                draggedPost,
                categoryIdInt,
                targetPosition: targetIndex,
              );
        }
        setState(() => _postDropTargetIndex = null);
      },
      builder: (context, candidateData, rejectedData) {
        final bool hasCandidate = candidateData.isNotEmpty;
        final bool isTargeted = _postDropTargetIndex == index;
        final bool isSelfOrLeft =
            _draggingPostIndex == index || _draggingPostIndex == index - 1;
        final showLeftLine = hasCandidate && isTargeted && !isSelfOrLeft;

        final bool isLastItem = index == widget.posts.length - 1;
        final bool showRightLine =
            hasCandidate &&
            isLastItem &&
            _postDropTargetIndex == widget.posts.length &&
            _draggingPostIndex != index;

        return Stack(
          children: [
            SizedBox(
              width: cardWidth,
              child: LongPressDraggable<PostData>(
                data: post,
                dragAnchorStrategy: (draggable, context, position) {
                  return Offset(cardWidth * 0.9 / 2 + 10, 200.0 * 0.9 / 2 + 20);
                },
                onDragStarted: () {
                  context.read<PostDragDropService>().beginDrag(post);
                  setState(() => _draggingPostIndex = index);
                },
                onDragUpdate: (details) {
                  context.read<PostDragDropService>().updateDragPosition(
                    details.globalPosition,
                  );
                  final sc = widget.mainScrollController;
                  if (sc != null && sc.hasClients) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final globalY = details.globalPosition.dy;
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
                },
                onDragEnd: (_) {
                  setState(() {
                    _postDropTargetIndex = null;
                    _draggingPostIndex = null;
                  });
                },
                feedback: Opacity(
                  opacity: 0.6,
                  child: Transform.scale(
                    scale: 0.9,
                    alignment: Alignment.center,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: cardWidth,
                        child: ImageView(
                          post: post,
                          isFirst: false,
                          isLast: false,
                        ),
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: ImageView(post: post, isFirst: false, isLast: false),
                ),
                child: GestureDetector(
                  onTap: () => _openPost(context, post, index),
                  child: ImageView(post: post, isFirst: false, isLast: false),
                ),
              ),
            ),
            if (showLeftLine)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  opacity: showLeftLine ? 1.0 : 0.0,
                  child: IgnorePointer(
                    child: Container(
                      width: 5,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            if (showRightLine)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  opacity: showRightLine ? 1.0 : 0.0,
                  child: IgnorePointer(
                    child: Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = categoryMetaData.title;
        final textStyle = theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        );
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final textWidth = textPainter.size.width;

        return Transform.translate(
          offset: Offset(-textWidth / 2, -20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              categoryMetaData.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: theme.colorScheme.surface,
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPost(BuildContext context, PostData post, int index) async {
    final result = await Navigator.of(context).push(
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

    print('[GridCategorySection] PostReaderScreen 결과: $result');
    if (result != null && result['deleted'] == true) {
      print('[GridCategorySection] 포스트 삭제 감지 - 피드 새로고침 시작');
      final provider = context.read<BaseFeedProvider>();
      provider.clearInMemory();
      provider.setNetworkError(null);
      await provider.loadInitial(force: true);
      print('[GridCategorySection] 피드 새로고침 완료');
    }
  }

  Future<void> _reorderPostsInCategoryWithServer(
    BuildContext context,
    int categoryId,
    String movedPostId,
    int targetPosition,
  ) async {
    try {
      final provider = context.read<BaseFeedProvider>();

      if (provider is MyProfileFeedProvider) {
        provider.movePostLocally(movedPostId, categoryId, targetPosition);
        final categoryStr = categoryId.toString();
        final posts = provider.postsByCategory[categoryStr] ?? [];
        final orderedPostIds = posts.map((post) => '${post['id']}').toList();
        await provider.reorderPostsInCategory(categoryId, orderedPostIds);
      } else {
        provider.movePostLocally(movedPostId, categoryId, targetPosition);
      }
    } catch (e) {
      print('⚠️ [GridCategorySection] 포스트 순서 서버 저장 실패: $e');
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('포스트 순서 저장에 실패했습니다')));
      } catch (_) {}
    }
  }
}
