import 'dart:math' as math;
import 'package:doppy/pages/components/comps_for_profile/sections/card_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/category_model.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/image_view.dart';
import 'package:doppy/pages/components/comps_for_profile/sections/post_action_sheet.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';

/// 수직 카드 뷰 카테고리 섹션
class VerticalCategorySection extends StatefulWidget {
  const VerticalCategorySection({
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
  State<VerticalCategorySection> createState() =>
      _VerticalCategorySectionState();
}

class _VerticalCategorySectionState extends State<VerticalCategorySection> {
  int? _postDropTargetIndex;
  int? _draggingPostIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = context.read<UserProvider>().currentUser?.username;
    final isReadOnly = context.read<BaseFeedProvider>().isReadOnly;
    final isImageOnly = widget.displayMode == FeedDisplayMode.imageOnly;

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

                  // 글로벌 좌표 기준 메인 스크롤 엣지 처리
                  final sc = widget.mainScrollController;
                  if (sc != null && sc.hasClients) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final globalY = details.offset.dy;
                    const edge = 120.0; // 엣지 영역 확대
                    const speed = 16.0; // 스크롤 속도 증가
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
                    pf.categories
                        .where((c) {
                          final id = int.tryParse(c['id'].toString());
                          return id != null && id >= 0; // 0 포함
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
                              return LongPressDraggable<CategoryMetaData>(
                                data: CategoryMetaData(
                                  title: widget.title,
                                  posts: widget.posts,
                                  categoryId: widget.categoryId,
                                ),
                                dragAnchorStrategy: pointerDragAnchorStrategy,
                                feedback:
                                    context.read<BaseFeedProvider>().isReadOnly
                                        ? const SizedBox.shrink()
                                        : _buildCategoryFeedback(
                                          context,
                                          theme,
                                          CategoryMetaData(
                                            title: widget.title,
                                            posts: widget.posts,
                                            categoryId: widget.categoryId,
                                          ),
                                        ),
                                onDragStarted: () {
                                  // readonly일 때는 드래그 시작하지 않음
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
                                  // 드래그 중 글로벌 위치 업데이트하여 스크롤 트리거
                                  final sc = widget.mainScrollController;
                                  if (sc != null && sc.hasClients) {
                                    final screenHeight =
                                        MediaQuery.of(context).size.height;
                                    final globalY = details.globalPosition.dy;
                                    const edge = 120.0;
                                    const speed = 16.0;
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
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _getCategoryDisplayTitle(
                                            widget.title,
                                            widget.categoryId,
                                            username,
                                          ),
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.8),
                                              ),
                                        ),
                                      ),
                                      if (!context
                                          .read<BaseFeedProvider>()
                                          .isReadOnly)
                                        Icon(
                                          Icons.drag_indicator,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.4),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        // 포스트 리스트
                        if (widget.posts.isNotEmpty)
                          ...widget.posts.asMap().entries.map((entry) {
                            final i = entry.key;
                            final post = entry.value;
                            final isFirstPost = i == 0;
                            final isLastPost = i == widget.posts.length - 1;

                            // 시스템 카테고리 체크
                            final categoryIdInt = int.tryParse(
                              widget.categoryId ?? '',
                            );
                            final isSystemCategory = categoryIdInt == null;

                            // 시스템 카테고리이거나 readOnly이면 드래그 불가
                            if (isReadOnly || isSystemCategory) {
                              return GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.of(
                                    context,
                                  ).push(
                                    PageRouteBuilder(
                                      pageBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                          ) => PostReaderScreen(
                                            exported: post.toExportedData(),
                                            heroTag: null,
                                          ),
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                            child,
                                          ) => FadeTransition(
                                            opacity: animation,
                                            child: child,
                                          ),
                                      transitionDuration: const Duration(
                                        milliseconds: 200,
                                      ),
                                    ),
                                  );

                                  if (result != null &&
                                      result['deleted'] == true) {
                                    final provider =
                                        context.read<BaseFeedProvider>();
                                    provider.loadInitial();
                                  }
                                },
                                onLongPress:
                                    !isSystemCategory
                                        ? null
                                        : () {
                                          PostActionSheet.show(
                                            context,
                                            post: post,
                                            onDelete:
                                                () =>
                                                    _deletePost(context, post),
                                            onMoveCategory:
                                                () => _movePostToCategory(
                                                  context,
                                                  post,
                                                ),
                                            onChangeAccessLevel:
                                                () => _changePostAccessLevel(
                                                  context,
                                                  post,
                                                ),
                                          );
                                        },
                                child: CardView(
                                  post: post,
                                  isFirst: isFirstPost,
                                  isLast: isLastPost,
                                ),
                              );
                            }

                            return DragTarget<PostData>(
                              onWillAccept: (data) => true,
                              onMove: (details) {
                                final String sectionKey =
                                    '${widget.categoryId ?? widget.title}_row$currentSectionIndex';
                                context
                                    .read<PostDragDropService>()
                                    .setHoverSectionKey(sectionKey);
                                setState(() => _postDropTargetIndex = i);
                              },
                              onLeave: (_) {
                                setState(() => _postDropTargetIndex = null);
                              },
                              onAccept: (draggedPost) async {
                                final draggedIndex = widget.posts.indexOf(
                                  draggedPost,
                                );
                                final targetIndex = _postDropTargetIndex ?? i;

                                if (draggedIndex != -1) {
                                  if (draggedIndex == targetIndex) {
                                    setState(() => _postDropTargetIndex = null);
                                    return;
                                  }
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
                              builder: (context, candidateData, rejectedData) {
                                final bool hasCandidate =
                                    candidateData.isNotEmpty;
                                final bool isTargeted =
                                    _postDropTargetIndex == i;
                                // 드래그 중인 항목이거나 그 위의 항목이면 라인 숨김
                                final bool isDraggingSelf =
                                    _draggingPostIndex == i;
                                final showLeftLine =
                                    hasCandidate &&
                                    isTargeted &&
                                    !isDraggingSelf;

                                return Stack(
                                  children: [
                                    LongPressDraggable<PostData>(
                                      data: post,
                                      dragAnchorStrategy:
                                          pointerDragAnchorStrategy,
                                      onDragStarted: () {
                                        context
                                            .read<PostDragDropService>()
                                            .beginDrag(post);
                                        setState(() => _draggingPostIndex = i);
                                      },
                                      onDragUpdate: (details) {
                                        context
                                            .read<PostDragDropService>()
                                            .updateDragPosition(
                                              details.globalPosition,
                                            );
                                      },
                                      onDragEnd: (_) {
                                        setState(() {
                                          _postDropTargetIndex = null;
                                          _draggingPostIndex = null;
                                        });
                                      },
                                      feedback: LayoutBuilder(
                                        builder: (context, constraints) {
                                          // 카드의 예상 높이 계산
                                          const estimatedCardHeight = 120.0;

                                          return Transform.translate(
                                            offset: Offset(
                                              -MediaQuery.of(
                                                    context,
                                                  ).size.width /
                                                  2,
                                              -estimatedCardHeight / 2,
                                            ),
                                            child: Transform.scale(
                                              scale: 0.9,
                                              child: ConstrainedBox(
                                                constraints:
                                                    BoxConstraints.loose(
                                                      Size.fromWidth(
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width,
                                                      ),
                                                    ),
                                                child: Opacity(
                                                  opacity: 0.8,
                                                  child:
                                                      isImageOnly
                                                          ? ImageView(
                                                            post: post,
                                                          )
                                                          : _buildPostCard(
                                                            theme,
                                                            post,
                                                            isFirstPost,
                                                            isLastPost,
                                                          ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child:
                                            isImageOnly
                                                ? ImageView(post: post)
                                                : _buildPostCard(
                                                  theme,
                                                  post,
                                                  isFirstPost,
                                                  isLastPost,
                                                ),
                                      ),
                                      child: InkWell(
                                        onTap: () => _openPost(context, post),
                                        child:
                                            isImageOnly
                                                ? ImageView(post: post)
                                                : _buildPostCard(
                                                  theme,
                                                  post,
                                                  isFirstPost,
                                                  isLastPost,
                                                ),
                                      ),
                                    ),
                                    if (showLeftLine)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: AnimatedOpacity(
                                          duration: const Duration(
                                            milliseconds: 160,
                                          ),
                                          curve: Curves.easeOut,
                                          opacity: 1.0,
                                          child: IgnorePointer(
                                            child: Container(
                                              width: 5,
                                              decoration: BoxDecoration(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          }),
                        if (widget.posts.isEmpty)
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
                                height: 200,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(
                                    0.1,
                                  ),
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
                                child: Center(
                                  child: Text(
                                    acceptingPost
                                        ? '여기에 놓기'
                                        : '이 카테고리에 글이 없어요!',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        if (widget.isLastSection) const SizedBox(height: 15),
                      ],
                    ),
                    // 상단 드롭 라인
                    if (widget.showHeader)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          opacity: showTopLine ? 1.0 : 0.0,
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
                    // 하단 드롭 라인
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 0,
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
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 텍스트의 예상 너비 계산
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
          offset: Offset(-textWidth / 2, -20), // 왼쪽으로 텍스트 중앙만큼 이동
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

  Widget _buildPostCard(
    ThemeData theme,
    PostData post,
    bool isFirstPost,
    bool isLastPost,
  ) {
    // 내 피드인지 확인 (BaseFeedProvider가 MyProfileFeedProvider인지 확인)
    final isMyFeed = context.read<BaseFeedProvider>() is MyProfileFeedProvider;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: CardView(
            post: post,
            showViewBadge: isMyFeed,
            isFirst: isFirstPost,
            isLast: isLastPost,
          ),
        ),
      ],
    );
  }

  void _openPost(BuildContext context, PostData post) async {
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

    // 포스트가 삭제된 경우 피드를 다시 로드
    if (result != null && result['deleted'] == true) {
      print('[VerticalCategorySection] 포스트 삭제 감지 - 피드 새로고침 시작');
      final provider = context.read<BaseFeedProvider>();
      provider.clearInMemory();
      provider.setNetworkError(null);
      await provider.loadInitial(force: true);
      print('[VerticalCategorySection] 피드 새로고침 완료');
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
      print('⚠️ 포스트 순서 서버 저장 실패: $e');
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('포스트 순서 저장에 실패했습니다')));
      } catch (_) {}
    }
  }

  void _deletePost(BuildContext context, PostData post) {
    // TODO: 구현
  }

  void _movePostToCategory(BuildContext context, PostData post) {
    // TODO: 구현
  }

  void _changePostAccessLevel(BuildContext context, PostData post) {
    // TODO: 구현
  }
}
