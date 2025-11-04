import 'dart:ui' as ui;

import 'package:doppy/pages/components/comment_item.dart';
import 'package:doppy/pages/components/shimmer_box.dart';

import 'package:doppy/pages/components/comment_input_section.dart';
import 'package:doppy/pages/components/comment_list_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({super.key, required this.title});
  final String title;

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final CommentService _commentService = CommentService();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // 바운싱 애니메이션을 위한 컨트롤러들
  late AnimationController _bounceAnimationController;
  late Animation<double> _bounceScaleAnimation;

  // 애니메이션 중인 댓글 ID와 타입
  String? _animatingCommentId;
  // 'reaction' 또는 'reply'

  Comment? _replyTarget;
  Comment? _editingComment; // 편집 중인 댓글
  int _lastCommentCount = 0; // 이전 댓글 개수 추적

  // 댓글 키 맵 (스크롤용)
  final Map<String, GlobalKey> _commentKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
    print('[CommentBottomSheet] 스크롤 타겟 댓글 ID: $commentId');

    final key = _commentKeys[commentId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.1, // 뷰포트 상단에서 10% 위치
      );
      print('[CommentBottomSheet] Scrollable.ensureVisible 호출 완료');
    } else {
      print('[CommentBottomSheet] GlobalKey를 찾을 수 없습니다: $commentId');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commentService.removeListener(_onCommentServiceChanged);

    _bounceAnimationController.dispose();
    _commentController.dispose();
    _commentFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 키보드(뷰 인셋) 변화 감지 → 강제 리빌드
    if (!mounted) return;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final v = views.first;
        final kb = v.viewInsets.bottom / v.devicePixelRatio;
        print('[CommentBottomSheet] didChangeMetrics(view) keyboardHeight=$kb');
      }
    } catch (_) {}
    setState(() {});
  }

  void _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    // 편집 중인 댓글이 있으면 수정
    if (_editingComment != null) {
      await _commentService.updateComment(_editingComment!.id, text);
      setState(() {
        _editingComment = null;
        _commentController.clear();
      });
      return;
    }

    // 새 댓글 추가
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
    });

    // 애니메이션과 동시에 실제 반응 처리
    _commentService.toggleReaction(commentId, emoji);

    _bounceAnimationController.forward().then((_) {
      // 애니메이션 리셋
      _bounceAnimationController.reset();
      setState(() {
        _animatingCommentId = null;
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

  void _editComment(String commentId, String currentContent) {
    final allComments = _commentService.getAllComments();
    final comment = allComments.firstWhere((c) => c.id == commentId);

    setState(() {
      _editingComment = comment;
      _commentController.text = currentContent;
      _replyTarget = null; // 답글 모드 해제
    });

    _commentFocus.requestFocus();
  }

  void _startReplyAnimation(String commentId) {
    setState(() {
      _animatingCommentId = commentId;
    });

    _bounceAnimationController.forward().then((_) {
      _bounceAnimationController.reset();
      setState(() {
        _animatingCommentId = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // 키보드 높이는 아래 View API 계산을 사용

    final allComments = _commentService.getAllComments();
    // 시간순으로 정렬 (오래된 것부터 최신 순으로)
    final comments =
        allComments..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // 댓글마다 GlobalKey 생성
    for (final comment in comments) {
      if (!_commentKeys.containsKey(comment.id)) {
        _commentKeys[comment.id] = GlobalKey();
      }
    }

    // View API로 키보드 높이 계산 (MediaQuery가 0인 케이스 대비)
    double keyboardHeight;
    try {
      final view = View.of(context);
      keyboardHeight = view.viewInsets.bottom / view.devicePixelRatio;
    } catch (_) {
      // 폴백
      keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    }
    print('[CommentBottomSheet] keyboardHeight(calculated)=$keyboardHeight');

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
                                color: Colors.white,
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
                                  color: Colors.white,
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
                        child: Builder(
                          builder: (context) {
                            print(
                              '[CommentBottomSheet] isLoading=${_commentService.isLoading}, isEmpty=${comments.isEmpty}, comments.length=${comments.length}',
                            );
                            return _commentService.isLoading && comments.isEmpty
                                ? const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  child: ShimmerBox(
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                )
                                : CommentListBuilder(
                                  scrollController: _scrollController,
                                  comments: comments,
                                  bounceAnimationValue:
                                      _bounceScaleAnimation.value,
                                  isAnimating:
                                      (commentId) =>
                                          _animatingCommentId == commentId,
                                  findTargetComment: _findTargetComment,
                                  onReactionToggle: _toggleReaction,
                                  keyboardHeight:
                                      MediaQuery.of(context).viewInsets.bottom,
                                  onLongPress: (offset, comment) {
                                    HapticFeedback.mediumImpact();
                                    CommentItem.openMessageMenu(
                                      context,
                                      anchor: offset,
                                      comment: comment,
                                    ).then((value) {
                                      if (value == null) return;
                                      if (value == 'reply') {
                                        _startReplyAnimation(comment.id);
                                        setState(() {
                                          _replyTarget = comment;
                                        });
                                        _commentFocus.requestFocus();
                                      } else if (value == 'copy') {
                                        Clipboard.setData(
                                          ClipboardData(text: comment.content),
                                        );
                                      } else if (value == 'edit') {
                                        _editComment(
                                          comment.id,
                                          comment.content,
                                        );
                                      } else if (value == 'delete') {
                                        _deleteComment(comment.id);
                                      } else {
                                        _toggleReaction(comment.id, value);
                                      }
                                    });
                                  },
                                  onTapTargetComment: _scrollToComment,
                                  commentKeys: _commentKeys,
                                );
                          },
                        ),
                      ),

                      // 댓글 입력창 (키보드 높이만큼 올림)
                      AnimatedPadding(
                        padding: EdgeInsets.only(bottom: keyboardHeight),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: CommentInputSection(
                          commentController: _commentController,
                          focusNode: _commentFocus,
                          replyTarget: _replyTarget,
                          editingComment: _editingComment,
                          onSubmit: _submitComment,
                          onCancelReply:
                              () => setState(() => _replyTarget = null),
                          onCancelEdit: () {
                            setState(() {
                              _editingComment = null;
                              _commentController.clear();
                            });
                          },
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
