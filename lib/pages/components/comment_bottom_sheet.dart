import 'dart:ui' as ui;
import 'package:doppy/pages/components/comment_input_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comment_item.dart';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({super.key, required this.title});
  final String title;

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with SingleTickerProviderStateMixin {
  final CommentService _commentService = CommentService();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Comment? _replyTarget;
  Comment? _editingComment;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  String? _bouncingCommentId;

  @override
  void initState() {
    super.initState();
    _commentService.addListener(_onCommentsChanged);

    // 바운싱 애니메이션 초기화 (2번 바운스)
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _commentService.removeListener(_onCommentsChanged);
    _bounceController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onCommentsChanged() {
    if (mounted) {
      setState(() {});
      // 🎯 이모지 업데이트 시에는 스크롤 안 함
      if (_commentService.shouldScrollOnNextUpdate) {
        _scrollToBottom();
      }
    }
  }

  // 맨 아래로 스크롤 (새 댓글 추가 시)
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          0, // reverse:true → 0 = 맨 아래
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submitComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    // 편집 모드
    if (_editingComment != null) {
      await _commentService.updateComment(_editingComment!.id, text);
      setState(() {
        _editingComment = null;
        _textController.clear();
      });
      return;
    }

    // 새 댓글/답글 추가
    await _commentService.addComment(
      username: currentUser.username,
      content: text,
      parentId: _replyTarget?.id,
    );

    setState(() {
      _textController.clear();
      _replyTarget = null;
    });
  }

  void _onLongPress(Offset offset, Comment comment) {
    HapticFeedback.mediumImpact();
    final currentUser = context.read<UserProvider>().currentUser;
    final isMyComment =
        currentUser != null && comment.author == currentUser.username;
    openCommentMenu(
      context,
      anchor: offset,
      comment: comment,
      isMyComment: isMyComment,
    ).then((value) {
      if (value == null) return;
      if (value == 'reply') {
        setState(() => _replyTarget = comment);
        _focusNode.requestFocus();
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: comment.content));
      } else if (value == 'edit') {
        setState(() {
          _editingComment = comment;
          _textController.text = comment.content;
          _replyTarget = null;
        });
        _focusNode.requestFocus();
      } else if (value == 'delete') {
        _commentService.deleteComment(comment.id);
      } else {
        _commentService.toggleReaction(comment.id, value);
      }
    });
  }

  void _scrollToTargetComment(String commentId) {
    if (!_scrollController.hasClients) return;

    // commentId로 인덱스 찾기
    final comments = _commentService.getAllComments();
    final targetIndex = comments.indexWhere((c) => c.id == commentId);

    if (targetIndex == -1) {
      print('[CommentBottomSheet] 댓글을 찾을 수 없음: $commentId');
      return;
    }

    try {
      // reverse:true이므로 역순 계산
      const estimatedItemHeight = 80.0;
      final reversedIndex = comments.length - 1 - targetIndex;
      final targetOffset = reversedIndex * estimatedItemHeight;

      _scrollController
          .animateTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          )
          .then((_) {
            // 스크롤 완료 후 바운싱 애니메이션 시작
            setState(() => _bouncingCommentId = commentId);
            _bounceController.forward(from: 0.0).then((_) {
              _bounceController.reset();
              setState(() => _bouncingCommentId = null);
            });
          });
    } catch (e) {
      print('[CommentBottomSheet] 스크롤 에러: $e');
    }
  }

  Comment? _findTargetComment(String? parentId) {
    if (parentId == null || parentId == '0' || parentId.isEmpty) return null;
    try {
      return _commentService.getAllComments().firstWhere(
        (c) => c.id == parentId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allComments = _commentService.getAllComments();
    final comments =
        allComments..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return Stack(
      children: [
        GestureDetector(
          onTap: () => _focusNode.unfocus(),
          onHorizontalDragEnd: (details) {
            // 오른쪽으로 스와이프 (velocity.dx > 0)
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Navigator.of(context).maybePop();
            }
          },
          child: ClipRRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: const BoxDecoration(
                  color: ui.Color.fromARGB(182, 65, 65, 65),
                ),
                child: Scaffold(
                  resizeToAvoidBottomInset: true, // ← 키보드 자동 회피
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    automaticallyImplyLeading: false,
                    toolbarHeight: 45,
                    scrolledUnderElevation: 0,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white.withOpacity(0.75),
                          size: 24,
                        ),
                      ),
                    ),
                    title: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  body: Column(
                    children: [
                      // 채팅 리스트 (Align + shrinkWrap 사용)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _focusNode.unfocus(),
                          child:
                              _commentService.isLoading && comments.isEmpty
                                  ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  )
                                  : Align(
                                    alignment: Alignment.topCenter,
                                    child: RawScrollbar(
                                      controller: _scrollController,
                                      thumbColor: Colors.white.withOpacity(0.4),
                                      radius: const Radius.circular(20),
                                      thickness: 4,
                                      thumbVisibility: false,
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        reverse: true, // ✅ 키보드 변화 감지를 위해 true
                                        shrinkWrap: true, // ✅ 내용에 맞게 크기 조정
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 20,
                                        ),
                                        itemCount: comments.length,
                                        itemBuilder: (context, index) {
                                          // reverse:true이므로 역순 접근
                                          final reversedIndex =
                                              comments.length - 1 - index;
                                          final comment =
                                              comments[reversedIndex];
                                          final currentUser =
                                              context
                                                  .read<UserProvider>()
                                                  .currentUser;
                                          final isMe =
                                              currentUser != null &&
                                              comment.author ==
                                                  currentUser.username;

                                          final bool isSameAuthorAsPrevious =
                                              reversedIndex > 0 &&
                                              comments[reversedIndex - 1]
                                                      .author ==
                                                  comment.author;
                                          final bool showProfile =
                                              !isSameAuthorAsPrevious;

                                          final bool isSameAuthorAsNext =
                                              reversedIndex <
                                                  comments.length - 1 &&
                                              comments[reversedIndex + 1]
                                                      .author ==
                                                  comment.author;
                                          final bool showAuthorInfo =
                                              !isSameAuthorAsNext;

                                          final targetComment =
                                              _findTargetComment(
                                                comment.parentId,
                                              );

                                          // ValueKey로 중복 방지 (id_timestamp_reversedIndex)
                                          final uniqueKey =
                                              '${comment.id}_${comment.createdAt}_$reversedIndex';
                                          final isThisBouncing =
                                              _bouncingCommentId == comment.id;

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 0,
                                            ),
                                            child: AnimatedBuilder(
                                              animation: _bounceAnimation,
                                              builder: (context, child) {
                                                return Transform.translate(
                                                  offset:
                                                      isThisBouncing
                                                          ? Offset(
                                                            0,
                                                            -30 *
                                                                (_bounceAnimation
                                                                        .value -
                                                                    1.0),
                                                          )
                                                          : Offset.zero,
                                                  child: child,
                                                );
                                              },
                                              child: CommentItem(
                                                key: ValueKey(uniqueKey),
                                                comment: comment,
                                                commentService: _commentService,
                                                currentUser: currentUser,
                                                isMe: isMe,
                                                showProfile: showProfile,
                                                showAuthorInfo: showAuthorInfo,
                                                onReactionToggle: (
                                                  commentId,
                                                  emoji,
                                                ) {
                                                  _commentService
                                                      .toggleReaction(
                                                        commentId,
                                                        emoji,
                                                      );
                                                },
                                                onLongPress:
                                                    (offset, comment) =>
                                                        _onLongPress(
                                                          offset,
                                                          comment,
                                                        ),
                                                onTapTargetComment:
                                                    _scrollToTargetComment,
                                                targetComment: targetComment,
                                                globalKey: null,
                                                bounceAnimationValue: 1.0,
                                                isAnimating: false,
                                                onSwipeReply: () {
                                                  setState(
                                                    () =>
                                                        _replyTarget = comment,
                                                  );
                                                  _focusNode.requestFocus();
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                        ),
                      ),
                      // 입력창 (고정)
                      _buildInputSection(),
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

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      decoration: BoxDecoration(color: Colors.transparent),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 답글/편집 대상 표시
            if (_replyTarget != null || _editingComment != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 4),

                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _editingComment != null
                            ? '편집 중: ${_editingComment!.content}'
                            : '답글: ${_replyTarget!.content}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _replyTarget = null;
                          _editingComment = null;
                          _textController.clear();
                        });
                      },
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),

            CommentInputSection(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              commentController: _textController,
              focusNode: _focusNode,
              replyTarget: _replyTarget,
              editingComment: _editingComment,
              onSubmit: _submitComment,
              onCancelReply: () => setState(() => _replyTarget = null),
              onCancelEdit: () => setState(() => _editingComment = null),
            ),
          ],
        ),
      ),
    );
  }
}
