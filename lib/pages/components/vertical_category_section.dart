import 'dart:math' as math;
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/card_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/models/category_model.dart';
import 'package:doppy/pages/components/image_view.dart';
import 'package:doppy/pages/components/post_action_sheet.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/pages/components/access_level_sheet.dart';

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

  Future<void> _showCategoryDropdown(BuildContext iconContext) async {
    final int? catId = int.tryParse(widget.categoryId ?? '');
    if (catId == null) return;

    // categoryId = 0 (기본 카테고리)은 수정/삭제 불가
    if (catId == 0) {
      return;
    }

    final RenderBox button = iconContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(iconContext).overlay!.context.findRenderObject()
            as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final l10n = AppLocalizations.of(iconContext);
    final String? action = await showMenu<String>(
      context: iconContext,
      position: position,
      color: Theme.of(iconContext).colorScheme.surface,
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [Text(l10n.t('edit_category_name'))]),
        ),

        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [Text(l10n.t('delete_category_title'))]),
        ),
      ],
    );

    if (action == 'edit') {
      final newName = await DialogUtils.showTextInputDialog(
        iconContext,
        title: l10n.t('edit_category_title'),
        hintText: l10n.t('category_name_input'),
        initialText: widget.title,
        confirmText: l10n.t('save'),
      );
      if (newName != null && newName.trim().isNotEmpty) {
        try {
          final provider = iconContext.read<BaseFeedProvider>();
          await BlogService().updateCategoryName(
            categoryId: catId,
            name: newName.trim(),
          );
          await provider.refresh();
        } catch (_) {
          try {
            ScaffoldMessenger.of(iconContext).showSnackBar(
              SnackBar(content: Text(l10n.t('category_update_failed'))),
            );
          } catch (_) {}
        }
      }
    } else if (action == 'delete') {
      final bool? confirmed = await DialogUtils.showConfirmDialog(
        iconContext,
        title: l10n.t('delete_category_title'),
        message: l10n.t('delete_category_message'),
        confirmText: l10n.t('delete'),
        cancelText: l10n.t('cancel'),
        isDestructive: true,
      );
      if (confirmed == true) {
        try {
          final provider = iconContext.read<BaseFeedProvider>();
          await BlogService().deleteCategory(catId);
          await provider.refresh();
        } catch (_) {
          try {
            ScaffoldMessenger.of(iconContext).showSnackBar(
              SnackBar(content: Text(l10n.t('category_delete_failed'))),
            );
          } catch (_) {}
        }
      }
    }
  }

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
                                          username,
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
                                            context,
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
                                              .isReadOnly &&
                                          widget.categoryId != '0')
                                        Builder(
                                          builder:
                                              (iconCtx) => GestureDetector(
                                                onTap:
                                                    () => _showCategoryDropdown(
                                                      iconCtx,
                                                    ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.4),
                                                  ),
                                                ),
                                              ),
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
                                            heroTag: 'profile-post-${post.id}',
                                            fromProfile: true,
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
                                  showViewBadge: !isReadOnly,
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
                                      feedback: Transform.translate(
                                        offset: Offset(
                                          -MediaQuery.of(context).size.width /
                                              2,
                                          -120 / 2,
                                        ),
                                        child: Transform.scale(
                                          scale: 0.9,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints.loose(
                                              Size.fromWidth(
                                                MediaQuery.of(
                                                  context,
                                                ).size.width,
                                              ),
                                            ),
                                            child: Opacity(
                                              opacity: 0.8,
                                              child: _buildPostCardFeedback(
                                                theme,
                                                post,
                                                isFirstPost,
                                                isLastPost,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child:
                                            isImageOnly
                                                ? ImageView(
                                                  post: post,
                                                  showViewCount:
                                                      !isReadOnly &&
                                                      !isSystemCategory,
                                                )
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
                                                ? ImageView(
                                                  post: post,
                                                  showViewCount:
                                                      !isReadOnly &&
                                                      !isSystemCategory,
                                                )
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
    BuildContext context,
    String title,
    String? categoryId,
    String? username,
  ) {
    if (categoryId == '0') {
      return (username != null && username.isNotEmpty)
          ? '$username${context.tr('other_posts_by')}'
          : context.tr('all_posts');
    }
    return title;
  }

  Widget _buildCategoryFeedback(
    BuildContext context,
    ThemeData theme,
    CategoryMetaData categoryMetaData,
    String? username,
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
          offset: Offset(-textWidth / 2 + 40, -30), // 왼쪽으로 텍스트 중앙만큼 이동
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _getCategoryDisplayTitle(
                context,
                categoryMetaData.title,
                categoryMetaData.categoryId,
                username,
              ),
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
    final feedProvider = context.read<BaseFeedProvider>();
    final isReadOnly = feedProvider.isReadOnly;

    // 시스템 카테고리 확인 (categoryId가 null이거나 숫자가 아닌 경우)
    final categoryIdInt = int.tryParse(widget.categoryId ?? '');
    final isSystemCategory = categoryIdInt == null;

    // 이미지 모드와 동일한 조건: !isReadOnly && !isSystemCategory
    final showViewBadge = !isReadOnly && !isSystemCategory;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: CardView(
            post: post,
            showViewBadge: showViewBadge,
            isFirst: isFirstPost,
            isLast: isLastPost,
          ),
        ),
      ],
    );
  }

  Widget _buildPostCardFeedback(
    ThemeData theme,
    PostData post,
    bool isFirstPost,
    bool isLastPost,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(
        width: double.infinity,
        height: 140,
      ),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: CardView(
          post: post,
          showViewBadge: false,
          isFirst: isFirstPost,
          isLast: isLastPost,
        ),
      ),
    );
  }

  void _openPost(BuildContext context, PostData post) async {
    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => PostReaderScreen(
              exported: post.toExportedData(),
              heroTag: 'profile-post-${post.id}',
              fromProfile: true, // 프로필에서 들어옴
            ),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );

    // 🎯 포스트 삭제 또는 공개 범위 변경 시 피드 새로고침
    if (result != null) {
      if (result['deleted'] == true) {
        debugPrint('[VerticalCategorySection] 포스트 삭제 감지 - 피드 새로고침 시작');
        final provider = context.read<BaseFeedProvider>();
        provider.clearInMemory();
        provider.setNetworkError(null);
        await provider.loadInitial(force: true);
        debugPrint('[VerticalCategorySection] 피드 새로고침 완료');
      } else if (result['accessLevelChanged'] == true) {
        // 🎯 공개 범위 변경 감지 - 선택적 업데이트 (전체 새로고침 생략)
        final postId = result['postId']?.toString();
        final accessLevel = result['accessLevel']?.toString();
        final sharedGroupIds = result['sharedGroupIds'] as List<int>?;

        if (postId != null && accessLevel != null) {
          debugPrint(
            '[VerticalCategorySection] 공개 범위 변경 감지 - 선택적 업데이트 시작 (postId: $postId)',
          );
          final provider = context.read<BaseFeedProvider>();
          provider.updatePostMetadata(
            postId,
            accessLevel: accessLevel,
            sharedGroupIds: sharedGroupIds,
          );
          debugPrint('[VerticalCategorySection] 피드 선택적 업데이트 완료 (공개 범위 변경)');
        } else {
          // fallback: 정보가 없으면 전체 새로고침
          debugPrint('[VerticalCategorySection] 공개 범위 변경 감지 - 정보 부족으로 전체 새로고침');
          final provider = context.read<BaseFeedProvider>();
          provider.clearInMemory();
          provider.setNetworkError(null);
          await provider.loadInitial(force: true);
          debugPrint('[VerticalCategorySection] 피드 새로고침 완료 (공개 범위 변경)');
        }
      }
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
      debugPrint('⚠️ 포스트 순서 서버 저장 실패: $e');
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('포스트 순서 저장에 실패했습니다')));
      } catch (_) {}
    }
  }

  Future<void> _deletePost(BuildContext context, PostData post) async {
    final l10n = AppLocalizations.of(context);

    // 삭제 확인 다이얼로그
    final bool? shouldDelete = await DialogUtils.showConfirmDialog(
      context,
      title: l10n.translate('delete_post_confirm_title'),
      message: l10n.translate('delete_post_confirm_message'),
      confirmText: l10n.translate('delete'),
      cancelText: l10n.translate('cancel'),
      isDestructive: true,
    );

    if (shouldDelete != true) return;

    try {
      final blogService = BlogService();
      final provider = context.read<BaseFeedProvider>();

      // 🎯 삭제 전에 공개범위 정보 저장
      final accessLevel = post.accessLevel;
      final sharedGroupIds = post.sharedGroupIds;

      await blogService.deletePost(post.id);

      // 🎯 포스트 삭제 후 관련 그룹의 postCount 및 포스트 캐시 동기화
      try {
        final groupProvider = context.read<GroupProvider>();

        // GROUPS 공개범위인 경우
        if (accessLevel == AccessLevel.groups &&
            sharedGroupIds != null &&
            sharedGroupIds.isNotEmpty) {
          final groupIdToDelta = <int, int>{};
          for (final groupId in sharedGroupIds) {
            groupIdToDelta[groupId] = -1;
          }
          groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);
          ManageGroupScreen.invalidateMultipleGroupsPostsCache(sharedGroupIds);
        }
        // FRIENDS 공개범위인 경우
        else if (accessLevel == AccessLevel.friends) {
          ManageGroupScreen.invalidateGroupPostsCache(-1);
        }
      } catch (e) {
        debugPrint('[VerticalCategorySection] 그룹 동기화 실패: $e');
      }

      // 🎯 피드에서 포스트 제거 및 새로고침
      provider.clearInMemory();
      provider.setNetworkError(null);
      await provider.loadInitial(force: true);

      if (context.mounted) {
        ErrorHandler.showInfo(context, l10n.translate('post_deleted'));
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(context, l10n.translate('post_delete_failed'));
      }
    }
  }

  Future<void> _movePostToCategory(BuildContext context, PostData post) async {
    final provider = context.read<BaseFeedProvider>();

    // 🎯 시스템 카테고리가 아닌 사용자 카테고리만 표시
    final userCategories =
        provider.categories.where((c) => !(c['isSystem'] == true)).toList();

    if (userCategories.isEmpty) {
      ErrorHandler.showInfo(context, context.tr('no_categories_available'));
      return;
    }

    // 🎯 현재 포스트가 속한 카테고리 ID 찾기
    String? currentCategoryId;
    for (final categoryId in provider.postsByCategory.keys) {
      final posts = provider.postsByCategory[categoryId] ?? [];
      if (posts.any((p) => '${p['id']}' == post.id)) {
        currentCategoryId = categoryId;
        break;
      }
    }

    // 🎯 카테고리 선택 바텀시트 표시
    final selectedCategory = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 제목
                          Text(
                            context.tr('select_category'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 🎯 "지정 안 함" 옵션 (미분류 카테고리)
                          Builder(
                            builder: (context) {
                              final isUncategorized = currentCategoryId == '0';
                              return InkWell(
                                onTap:
                                    isUncategorized
                                        ? null
                                        : () {
                                          Navigator.of(context).pop({
                                            'id': 0,
                                            'name': context.tr('uncategorized'),
                                          });
                                        },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    context.tr('uncategorized'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          isUncategorized
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.3)
                                              : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // 디바이더
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 0,
                            endIndent: 0,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.05),
                          ),
                          // 카테고리 리스트
                          ...userCategories.map((category) {
                            final categoryId = category['id']?.toString();
                            final isCurrentCategory =
                                categoryId == currentCategoryId;
                            return InkWell(
                              onTap:
                                  isCurrentCategory
                                      ? null
                                      : () {
                                        Navigator.of(context).pop(category);
                                      },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(
                                  category['name']?.toString() ?? '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        isCurrentCategory
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.3)
                                            : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          const SizedBox(height: 24),
                          // 취소 버튼
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.03),
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                context.tr('cancel'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );

    if (selectedCategory == null) return;

    final targetCategoryId = selectedCategory['id'] as int?;
    if (targetCategoryId == null) return;

    try {
      final blogService = BlogService();

      // 🎯 서버에 카테고리 변경 요청
      await blogService.movePostToCategory(
        postId: int.parse(post.id),
        targetCategoryId: targetCategoryId,
      );

      // 🎯 피드 새로고침
      provider.clearInMemory();
      provider.setNetworkError(null);
      await provider.loadInitial(force: true);

      if (context.mounted) {
        ErrorHandler.showInfo(context, context.tr('category_changed'));
      }
    } catch (e) {
      debugPrint('[VerticalCategorySection] 카테고리 변경 실패: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, context.tr('category_change_failed'));
      }
    }
  }

  Future<void> _changePostAccessLevel(
    BuildContext context,
    PostData post,
  ) async {
    final provider = context.read<BaseFeedProvider>();

    // 🎯 공개범위를 문자열로 변환
    String currentAccessLevel = 'PUBLIC';
    if (post.accessLevel == AccessLevel.private) {
      currentAccessLevel = 'PRIVATE';
    } else if (post.accessLevel == AccessLevel.friends) {
      currentAccessLevel = 'FRIENDS';
    } else if (post.accessLevel == AccessLevel.groups) {
      currentAccessLevel = 'GROUPS';
    }

    // 🎯 AccessLevelSheet 표시
    AccessLevelSheet.show(
      context,
      postId: post.id,
      currentAccessLevel: currentAccessLevel,
      currentSharedGroupIds: post.sharedGroupIds,
      currentSharedGroupNames: post.sharedGroupNames,
      isBatchMode: false,
      onChanged: (String accessLevel, List<int>? sharedGroupIds) async {
        // 🎯 공개범위 변경 후 피드 업데이트
        provider.updatePostMetadata(
          post.id,
          accessLevel: accessLevel,
          sharedGroupIds: sharedGroupIds,
        );
      },
    );
  }
}
