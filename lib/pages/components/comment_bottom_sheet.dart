import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/pages/components/comment_shimmer.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({super.key});

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with SingleTickerProviderStateMixin {
  final CommentService _commentService = CommentService();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  Comment? _replyTarget;
  int _lastCommentCount = 0; // 이전 댓글 개수 추적

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();

    _commentService.addListener(_onCommentServiceChanged);
  }

  void _onCommentServiceChanged() {
    if (mounted) {
      final currentCommentCount = _commentService.getAllComments().length;

      setState(() {});

      // 새로운 댓글이 추가되었을 때만 자동 스크롤
      if (currentCommentCount > _lastCommentCount) {
        print(
          '[CommentBottomSheet] 새 댓글 감지! 이전: $_lastCommentCount, 현재: $currentCommentCount',
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }

      _lastCommentCount = currentCommentCount;
    }
  }

  // 타겟 댓글 찾기
  Comment? _findTargetComment(String? parentId) {
    if (parentId == null || parentId == '0' || parentId == '') return null;

    final allComments = _commentService.getAllComments();
    try {
      return allComments.firstWhere((comment) => comment.id == parentId);
    } catch (e) {
      return null;
    }
  }

  // 특정 댓글로 스크롤 점프
  void _scrollToComment(String commentId) {
    final allComments = _commentService.getAllComments();
    final targetIndex = allComments.indexWhere(
      (comment) => comment.id == commentId,
    );

    if (targetIndex != -1 && _scrollController.hasClients) {
      // 댓글 목록에서 해당 댓글의 위치로 스크롤
      final itemHeight = 80.0; // 대략적인 댓글 높이
      final targetOffset = targetIndex * itemHeight;

      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  String _formatRelativeTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return '방금';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}분 전';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}시간 전';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else {
        return '${(difference.inDays / 7).floor()}주 전';
      }
    } catch (e) {
      return '방금';
    }
  }

  @override
  void dispose() {
    _commentService.removeListener(_onCommentServiceChanged);

    _animationController.dispose();
    _commentController.dispose();
    _commentFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    await _commentService.addComment(
      username: currentUser.username,
      content: text,
      parentId: _replyTarget?.id,
    );

    setState(() {
      _commentController.clear();
      _replyTarget = null;
    });

    // 새 댓글로 스크롤 (맨 아래로)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleReaction(String commentId, String emoji) async {
    await _commentService.toggleReaction(commentId, emoji);
    setState(() {});
  }

  Future<String?> _openMessageMenu({
    required Offset anchor,
    required Comment comment,
  }) async {
    final media = MediaQuery.of(context);
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.black.withOpacity(0.25),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, a1, a2) {
        final Size size = media.size;
        final double left = 16;
        final double right = 16;
        final double top = (anchor.dy - 120).clamp(
          media.padding.top + 12,
          size.height - 280,
        );
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).maybePop(),
                  onVerticalDragUpdate: (d) {
                    if (d.primaryDelta != null && d.primaryDelta! > 12) {
                      Navigator.of(ctx).maybePop();
                    }
                  },
                  child: Container(color: Colors.black.withOpacity(0.5)),
                ),
              ),
              Positioned(
                left: left,
                right: right,
                top: top,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).maybePop(),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6, right: 2),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final e in const [
                            '❤️',
                            '😂',
                            '😮',
                            '😢',
                            '😡',
                            '👍',
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: GestureDetector(
                                onTap: () => Navigator.of(ctx).pop(e),
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.20),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.reply_rounded),
                            title: const Text('답글 달기'),
                            onTap: () => Navigator.of(ctx).pop('reply'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.send_outlined),
                            title: const Text('전달'),
                            onTap: () => Navigator.of(ctx).pop('forward'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.copy_rounded),
                            title: const Text('복사'),
                            onTap: () => Navigator.of(ctx).pop('copy'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.98,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allComments = _commentService.getAllComments();
    // 시간순으로 정렬 (오래된 것부터 최신 순으로)
    final comments =
        allComments..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Stack(
          children: [
            // 바텀시트
            Transform.translate(
              offset: Offset(
                0,
                _slideAnimation.value * MediaQuery.of(context).size.height,
              ),
              child: GestureDetector(
                onTap: () {
                  if (_commentFocus.hasFocus) {
                    _commentFocus.unfocus();
                  }
                },
                child: Container(
                  height: MediaQuery.of(context).size.height - 70,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withOpacity(0.9),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 드래그 핸들
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // 앱바
                      Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                _animationController.reverse().then((_) {
                                  Navigator.of(context).pop();
                                });
                              },
                              child: Icon(
                                Icons.arrow_back_ios_new,
                                color: Theme.of(context).colorScheme.onSurface,
                                size: 15,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '댓글 ${comments.length}개',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 댓글 리스트
                      Expanded(
                        child:
                            _commentService.isLoading && comments.isEmpty
                                ? const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: CommentShimmer(
                                    itemCount: 5,
                                    isPreview: false,
                                  ),
                                )
                                : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 30,
                                  ),
                                  itemCount: comments.length,
                                  itemBuilder: (context, index) {
                                    final comment = comments[index]; // 정순으로 표시
                                    final currentUser =
                                        context
                                            .read<UserProvider>()
                                            .currentUser;
                                    final isMe =
                                        currentUser != null &&
                                        comment.author == currentUser.username;
                                    final hasReactions =
                                        comment.emotionCounts.isNotEmpty;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            isMe
                                                ? MainAxisAlignment.end
                                                : MainAxisAlignment.start,
                                        children: [
                                          if (!isMe) ...[
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .surfaceVariant,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child:
                                                  comment
                                                          .authorProfileImageUrl
                                                          .isNotEmpty
                                                      ? Image.network(
                                                        comment
                                                            .authorProfileImageUrl,
                                                        fit: BoxFit.cover,
                                                        cacheWidth: 120,
                                                        cacheHeight: 120,
                                                        filterQuality:
                                                            FilterQuality.low,
                                                      )
                                                      : Icon(
                                                        Icons.person,
                                                        size: 16,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],

                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment:
                                                  isMe
                                                      ? CrossAxisAlignment.end
                                                      : CrossAxisAlignment
                                                          .start,
                                              children: [
                                                // 답글인 경우 타겟 댓글 표시
                                                if (comment.parentId != null &&
                                                    comment.parentId != '0' &&
                                                    comment.parentId != '')
                                                  ...() {
                                                    final targetComment =
                                                        _findTargetComment(
                                                          comment.parentId,
                                                        );
                                                    if (targetComment == null)
                                                      return <Widget>[];

                                                    return [
                                                      // 타겟 댓글 (투명한 말풍선)
                                                      GestureDetector(
                                                        onTap: () {
                                                          // 타겟 댓글로 스크롤 점프
                                                          _scrollToComment(
                                                            targetComment.id,
                                                          );
                                                        },
                                                        child: Container(
                                                          constraints:
                                                              BoxConstraints(
                                                                maxWidth:
                                                                    MediaQuery.of(
                                                                      context,
                                                                    ).size.width *
                                                                    0.75,
                                                              ),
                                                          margin:
                                                              const EdgeInsets.only(
                                                                bottom: 8,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Theme.of(
                                                                  context,
                                                                )
                                                                .colorScheme
                                                                .surfaceVariant
                                                                .withOpacity(
                                                                  0.3,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
                                                            border: Border.all(
                                                              color: Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .outline
                                                                  .withOpacity(
                                                                    0.2,
                                                                  ),
                                                              width: 1,
                                                            ),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                '${targetComment.author}',
                                                                style: TextStyle(
                                                                  color: Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withOpacity(
                                                                        0.7,
                                                                      ),
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 2,
                                                              ),
                                                              Text(
                                                                targetComment
                                                                    .content,
                                                                style: TextStyle(
                                                                  color: Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withOpacity(
                                                                        0.6,
                                                                      ),
                                                                  fontSize: 13,
                                                                ),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ];
                                                  }(),

                                                // 댓글 버블
                                                GestureDetector(
                                                  onLongPressStart: (details) {
                                                    HapticFeedback.mediumImpact();
                                                    final Offset gp =
                                                        details.globalPosition;
                                                    _openMessageMenu(
                                                      anchor: gp,
                                                      comment: comment,
                                                    ).then((value) {
                                                      if (value == null) return;
                                                      if (value == 'reply') {
                                                        setState(() {
                                                          _replyTarget =
                                                              comment;
                                                        });
                                                        _commentFocus
                                                            .requestFocus();
                                                      } else if (value ==
                                                          'copy') {
                                                        Clipboard.setData(
                                                          ClipboardData(
                                                            text:
                                                                comment.content,
                                                          ),
                                                        );
                                                      } else {
                                                        _toggleReaction(
                                                          comment.id,
                                                          value,
                                                        );
                                                      }
                                                    });
                                                  },
                                                  onDoubleTap:
                                                      () => _toggleReaction(
                                                        comment.id,
                                                        '❤️',
                                                      ),
                                                  child: Container(
                                                    constraints: BoxConstraints(
                                                      maxWidth:
                                                          MediaQuery.of(
                                                            context,
                                                          ).size.width *
                                                          0.75,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 8,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          isMe
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .primary
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surfaceVariant,
                                                      borderRadius: BorderRadius.only(
                                                        topLeft:
                                                            const Radius.circular(
                                                              16,
                                                            ),
                                                        topRight:
                                                            const Radius.circular(
                                                              16,
                                                            ),
                                                        bottomLeft:
                                                            Radius.circular(
                                                              isMe ? 16 : 4,
                                                            ),
                                                        bottomRight:
                                                            Radius.circular(
                                                              isMe ? 4 : 16,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      comment.content,
                                                      style: TextStyle(
                                                        color:
                                                            isMe
                                                                ? Colors.white
                                                                : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                        fontSize: 15,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                // 반응 표시
                                                if (hasReactions)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        for (final entry
                                                            in comment
                                                                .emotionCounts
                                                                .entries)
                                                          if (entry.value !=
                                                              '0')
                                                            Container(
                                                              margin:
                                                                  const EdgeInsets.only(
                                                                    right: 4,
                                                                  ),
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .surface,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      10,
                                                                    ),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withOpacity(
                                                                          0.1,
                                                                        ),
                                                                    blurRadius:
                                                                        2,
                                                                  ),
                                                                ],
                                                              ),
                                                              child: Text(
                                                                '${entry.key} ${entry.value}',
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                              ),
                                                            ),
                                                      ],
                                                    ),
                                                  ),

                                                // 시간 표시
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    '${comment.author} • ${_formatRelativeTime(comment.createdAt)}',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.6),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          if (isMe) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .surfaceVariant,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child:
                                                  comment
                                                          .authorProfileImageUrl
                                                          .isNotEmpty
                                                      ? Image.network(
                                                        comment
                                                            .authorProfileImageUrl,
                                                        fit: BoxFit.cover,
                                                        cacheWidth: 120,
                                                        cacheHeight: 120,
                                                        filterQuality:
                                                            FilterQuality.low,
                                                      )
                                                      : Icon(
                                                        Icons.person,
                                                        size: 16,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                      ),

                      // 댓글 입력창
                      Container(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 0,
                          bottom: bottomInset + 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withOpacity(0.1),
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 답글 대상 표시
                            if (_replyTarget != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '@${_replyTarget!.author}: ${_replyTarget!.content}',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap:
                                          () => setState(
                                            () => _replyTarget = null,
                                          ),
                                      child: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // 입력창
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _commentController,
                                    focusNode: _commentFocus,
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: InputDecoration(
                                      hintText:
                                          _replyTarget != null
                                              ? '답글을 입력하세요'
                                              : '댓글을 입력하세요',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor:
                                          Theme.of(
                                            context,
                                          ).colorScheme.surfaceVariant,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _submitComment,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
