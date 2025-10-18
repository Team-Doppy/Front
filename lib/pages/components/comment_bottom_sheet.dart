import 'dart:ui' as ui;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/pages/components/comment_shimmer.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({super.key, required this.title});
  final String title;

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with TickerProviderStateMixin {
  final CommentService _commentService = CommentService();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // 바운싱 애니메이션을 위한 컨트롤러들
  late AnimationController _bounceAnimationController;
  late Animation<double> _bounceScaleAnimation;

  // 애니메이션 중인 댓글 ID와 타입
  String? _animatingCommentId;
  String? _animationType; // 'reaction' 또는 'reply'

  Comment? _replyTarget;
  int _lastCommentCount = 0; // 이전 댓글 개수 추적

  @override
  void initState() {
    super.initState();

    // 바운싱 애니메이션 초기화
    _bounceAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _bounceScaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _bounceAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _commentService.addListener(_onCommentServiceChanged);

    // 오버레이 열릴 때 자동 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _commentFocus.requestFocus();
        }
      });
    });
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

    _bounceAnimationController.dispose();
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
    // 바운싱 애니메이션과 동시에 반응 처리
    setState(() {
      _animatingCommentId = commentId;
      _animationType = 'reaction';
    });

    // 애니메이션과 동시에 실제 반응 처리
    _commentService.toggleReaction(commentId, emoji);

    _bounceAnimationController.forward().then((_) {
      // 애니메이션 리셋
      _bounceAnimationController.reset();
      setState(() {
        _animatingCommentId = null;
        _animationType = null;
      });
    });
  }

  void _deleteComment(String commentId) async {
    final bool shouldDelete = true;

    if (shouldDelete == true) {
      await _commentService.deleteComment(commentId);
      setState(() {});
    }
  }

  void _editComment(String commentId, String currentContent) async {
    final TextEditingController editController = TextEditingController(
      text: currentContent,
    );

    final String? newContent = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('댓글 수정'),
          content: TextField(
            controller: editController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '수정할 내용을 입력하세요',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed:
                  () => Navigator.of(context).pop(editController.text.trim()),
              child: const Text('수정'),
            ),
          ],
        );
      },
    );

    if (newContent != null &&
        newContent.isNotEmpty &&
        newContent != currentContent) {
      await _commentService.updateComment(commentId, newContent);
      setState(() {});
    }
  }

  void _startReplyAnimation(String commentId) {
    setState(() {
      _animatingCommentId = commentId;
      _animationType = 'reply';
    });

    _bounceAnimationController.forward().then((_) {
      _bounceAnimationController.reset();
      setState(() {
        _animatingCommentId = null;
        _animationType = null;
      });
    });
  }

  Future<String?> _openMessageMenu({
    required Offset anchor,
    required Comment comment,
  }) async {
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        anchor.dx - 100,
        anchor.dy + 10,
        anchor.dx + 10,
        anchor.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      items: [
        // 이모지 반응
        PopupMenuItem<String>(
          value: '❤️',
          child: SizedBox(
            height: 50,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    const [
                      '❤️',
                      '😂',
                      '😮',
                      '😢',
                      '😡',
                      '👍',
                      '🔥',
                      '💯',
                      '👏',
                      '🎉',
                    ].map((emoji) {
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pop(emoji),
                        child: Container(
                          width: 50,
                          height: 50,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
        ),
        // 답글 달기
        PopupMenuItem<String>(
          value: 'reply',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.reply_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '답글 달기',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 수정
        PopupMenuItem<String>(
          value: 'edit',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.edit_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '수정',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 삭제
        PopupMenuItem<String>(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '삭제',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 복사
        PopupMenuItem<String>(
          value: 'copy',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.tertiary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.copy_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '복사',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allComments = _commentService.getAllComments();
    // 시간순으로 정렬 (오래된 것부터 최신 순으로)
    final comments =
        allComments..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        // 바텀시트
        GestureDetector(
          onTap: () {
            if (_commentFocus.hasFocus) {
              _commentFocus.unfocus();
            }
          },
          child: Container(
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(182, 96, 96, 96),
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: 50),

                      // 앱바
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).maybePop();
                              },
                              child: Icon(
                                Icons.arrow_back_ios_new,
                                color: Theme.of(context).colorScheme.onSurface,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                widget.title,
                                key: ValueKey(comments.length),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
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

                                    // 이전 댓글과 같은 사람인지 확인
                                    final bool isSameAuthorAsPrevious =
                                        index > 0 &&
                                        comments[index - 1].author ==
                                            comment.author;
                                    final bool showProfile =
                                        !isSameAuthorAsPrevious;

                                    // 다음 댓글도 같은 사람인지 확인
                                    final bool isSameAuthorAsNext =
                                        index < comments.length - 1 &&
                                        comments[index + 1].author ==
                                            comment.author;
                                    final bool showAuthorInfo =
                                        !isSameAuthorAsNext;

                                    return TweenAnimationBuilder<double>(
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      tween: Tween(begin: 0.0, end: 1.0),
                                      builder: (context, value, child) {
                                        return Opacity(
                                          opacity: value,
                                          child: Transform.translate(
                                            offset: Offset(0, 20 * (1 - value)),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          top: showProfile ? 8 : 2,
                                          bottom: showAuthorInfo ? 8 : 2,
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
                                              if (showProfile)
                                                GestureDetector(
                                                  onTap: () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder:
                                                            (
                                                              context,
                                                            ) => UserProfileScreen(
                                                              otherUser: User(
                                                                id: 0,
                                                                username:
                                                                    comment
                                                                        .author,
                                                                alias:
                                                                    comment
                                                                        .author,
                                                                profileImageUrl:
                                                                    comment
                                                                        .authorProfileImageUrl,
                                                              ),
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    width: 50,
                                                    height: 50,
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
                                                    clipBehavior:
                                                        Clip.antiAlias,
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
                                                                  FilterQuality
                                                                      .low,
                                                            )
                                                            : Icon(
                                                              Icons.person,
                                                              size: 16,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurfaceVariant,
                                                            ),
                                                  ),
                                                )
                                              else
                                                const SizedBox(width: 50),
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
                                                  if (comment.parentId !=
                                                          null &&
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
                                                            constraints: BoxConstraints(
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
                                                                  horizontal:
                                                                      12,
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
                                                                  targetComment
                                                                      .author,
                                                                  style: TextStyle(
                                                                    color: Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withOpacity(
                                                                          0.7,
                                                                        ),
                                                                    fontSize:
                                                                        12,
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
                                                                    fontSize:
                                                                        13,
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
                                                    onLongPressStart: (
                                                      details,
                                                    ) {
                                                      HapticFeedback.mediumImpact();
                                                      final Offset gp =
                                                          details
                                                              .globalPosition;
                                                      _openMessageMenu(
                                                        anchor: gp,
                                                        comment: comment,
                                                      ).then((value) {
                                                        if (value == null)
                                                          return;
                                                        if (value == 'reply') {
                                                          _startReplyAnimation(
                                                            comment.id,
                                                          );
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
                                                                  comment
                                                                      .content,
                                                            ),
                                                          );
                                                        } else if (value ==
                                                            'edit') {
                                                          _editComment(
                                                            comment.id,
                                                            comment.content,
                                                          );
                                                        } else if (value ==
                                                            'delete') {
                                                          _deleteComment(
                                                            comment.id,
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
                                                    child: AnimatedBuilder(
                                                      animation:
                                                          _bounceAnimationController,
                                                      builder: (
                                                        context,
                                                        child,
                                                      ) {
                                                        final isAnimating =
                                                            _animatingCommentId ==
                                                            comment.id;
                                                        final scale =
                                                            isAnimating
                                                                ? _bounceScaleAnimation
                                                                    .value
                                                                : 1.0;

                                                        return Transform.scale(
                                                          scale: scale,
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
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  isMe
                                                                      ? Theme.of(
                                                                        context,
                                                                      ).colorScheme.primary
                                                                      : Theme.of(
                                                                        context,
                                                                      ).colorScheme.surfaceVariant,
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
                                                                      isMe
                                                                          ? 16
                                                                          : 4,
                                                                    ),
                                                                bottomRight:
                                                                    Radius.circular(
                                                                      isMe
                                                                          ? 4
                                                                          : 16,
                                                                    ),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              comment.content,
                                                              style: TextStyle(
                                                                color:
                                                                    isMe
                                                                        ? Colors
                                                                            .white
                                                                        : Theme.of(
                                                                          context,
                                                                        ).colorScheme.onSurface,
                                                                fontSize: 15,
                                                                height: 1.35,
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
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
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      Theme.of(
                                                                        context,
                                                                      ).colorScheme.surface,
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

                                                  // 시간 표시 (연속 댓글의 마지막에만 표시)
                                                  if (showAuthorInfo)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                          ),
                                                      child: Text(
                                                        '${comment.author} • ${_formatRelativeTime(comment.createdAt)}',
                                                        style: TextStyle(
                                                          color: Theme.of(
                                                                context,
                                                              )
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
                                              if (showProfile)
                                                Container(
                                                  width: 50,
                                                  height: 50,
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
                                                          .withOpacity(1),
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
                                                                FilterQuality
                                                                    .low,
                                                          )
                                                          : Icon(
                                                            Icons.person,
                                                            size: 16,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                          ),
                                                )
                                              else
                                                const SizedBox(width: 50),
                                            ],
                                          ],
                                        ),
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
                                    cursorColor:
                                        Theme.of(context).colorScheme.onSurface,
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
                                        borderRadius: BorderRadius.circular(35),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor:
                                          Theme.of(context).colorScheme.surface,
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
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.send_rounded,
                                      size: 24,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
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
          ),
        ),
      ],
    );
  }
}
