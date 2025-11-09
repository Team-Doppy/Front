import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comment_item.dart';
import 'package:doppy/l10n/app_localizations.dart';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({
    super.key,
    required this.title,
    required this.commentService,
  });
  final String title;
  final CommentService commentService;

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with SingleTickerProviderStateMixin {
  late final CommentService _commentService;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _commentKeys = {}; // 높이 측정용 GlobalKey

  Comment? _replyTarget;
  Comment? _editingComment;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  String? _bouncingCommentId;

  bool _showScrollToBottomButton = false; // 맨 아래로 버튼 표시 여부
  bool _showNewMessageBadge = false; // 새 메시지 알림 표시 여부
  int _lastCommentCount = 0; // 마지막 댓글 수
  bool _isKeyboardActive = false; // 키보드 활성화 상태

  @override
  void initState() {
    super.initState();
    _commentService = widget.commentService;
    _commentService.addListener(_onCommentsChanged);
    _scrollController.addListener(_onScroll);
    _lastCommentCount = _commentService.getAllComments().length;

    // 키보드 상태 감지
    _focusNode.addListener(_onFocusChanged);

    print('[CommentBottomSheet] 초기화 - 기존 댓글 ${_lastCommentCount}개');

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

  void _onFocusChanged() {
    if (mounted) {
      setState(() {
        _isKeyboardActive = _focusNode.hasFocus;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // 맨 아래로 버튼 표시 여부 (reverse:true이므로 offset > 100이면 위로 스크롤한 것)
    final isAtBottom = offset < 100;
    if (_showScrollToBottomButton != !isAtBottom) {
      setState(() {
        _showScrollToBottomButton = !isAtBottom;
      });
    }

    // 🎯 로드 타이밍: 상단에서 200px 이내로 접근하면 로드
    // reverse:true이므로 maxScroll에 가까워질수록 과거 댓글(상단)
    if (maxScroll > 0 &&
        maxScroll - offset < 200 && // 상단에서 200px 이내
        !_commentService.isLoading &&
        _commentService.hasMoreComments) {
      _commentService.loadComments();
    }
  }

  @override
  void dispose() {
    _commentService.removeListener(_onCommentsChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _bounceController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCommentsChanged() {
    if (!mounted) return;

    final currentCount = _commentService.getAllComments().length;
    final currentUser = context.read<UserProvider>().currentUser;

    // 삭제된 댓글의 GlobalKey 정리
    final currentCommentIds =
        _commentService.getAllComments().map((c) => c.id).toSet();
    _commentKeys.removeWhere((id, key) => !currentCommentIds.contains(id));

    // 🎯 새 댓글이 추가되었는지 확인 (페이지네이션 제외)
    // 로딩 중이 아니고, 댓글 수가 증가했을 때만 체크
    if (currentCount > _lastCommentCount && !_commentService.isLoading) {
      final allComments = _commentService.getAllComments();
      if (allComments.isNotEmpty) {
        // 🔍 진짜 새 댓글인지 확인: 최신 댓글의 생성 시간이 최근인지 체크
        final latestComment = allComments.first; // reverse:true이므로 first가 최신
        final now = DateTime.now();
        final commentAge = now.difference(
          DateTime.parse(latestComment.createdAt),
        );

        // 3초 이내에 생성된 댓글만 "새 댓글"로 간주 (로드모어는 오래된 댓글)
        final isRecentComment = commentAge.inSeconds < 3;

        if (isRecentComment) {
          final isMyComment = latestComment.author == currentUser?.username;

          // 내가 작성한 댓글이면 맨 아래로 스크롤
          if (isMyComment) {
            // 프레임 렌더링 후 스크롤
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToBottom();
            });
          } else {
            // 타인의 새 댓글이고 내가 위쪽을 보고 있으면 새 메시지 배지 표시
            if (_showScrollToBottomButton) {
              setState(() {
                _showNewMessageBadge = true;
              });
              // 5초 후 자동으로 배지 숨김
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) {
                  setState(() {
                    _showNewMessageBadge = false;
                  });
                }
              });
            }
          }
        }
      }
    }

    _lastCommentCount = currentCount;

    // 스크롤 위치 보존을 위해 setState를 다음 프레임으로 지연
    if (_scrollController.hasClients && _commentService.isLoading) {
      // 로딩 중이면 스크롤 위치 유지를 위해 setState 지연
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _submitComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    // 편집 모드
    if (_editingComment != null) {
      final commentId = _editingComment!.id;

      // 🎯 즉시 상태 초기화 (딜레이 없이)
      setState(() {
        _editingComment = null;
        _textController.clear();
      });

      // 서버 요청은 백그라운드에서 처리 (await 제거)
      _commentService.updateComment(commentId, text);
      return;
    }

    // 새 댓글/답글 추가
    final replyTargetId = _replyTarget?.id;

    // 🎯 즉시 상태 초기화 (딜레이 없이)
    setState(() {
      _textController.clear();
      _replyTarget = null;
    });

    // 서버 요청은 백그라운드에서 처리 (await 제거)
    _commentService.addComment(
      username: currentUser.username,
      content: text,
      parentId: replyTargetId,
    );
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

  void _scrollToBottom() {
    // 🎯 맨 아래(최신 댓글)로 스크롤
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      0.0, // reverse:true이므로 0이 맨 아래
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    // 새 메시지 배지 숨김
    if (_showNewMessageBadge) {
      setState(() {
        _showNewMessageBadge = false;
      });
    }
  }

  double? _getCommentHeight(String commentId) {
    // GlobalKey를 통해 실제 렌더링된 높이 가져오기
    final key = _commentKeys[commentId];
    if (key == null || key.currentContext == null) return null;

    final RenderBox? renderBox =
        key.currentContext!.findRenderObject() as RenderBox?;
    return renderBox?.size.height;
  }

  double _calculateTargetOffset(String commentId) {
    // 타겟 댓글까지의 정확한 높이 합산
    final comments = _commentService.getAllComments();
    final targetIndex = comments.indexWhere((c) => c.id == commentId);

    if (targetIndex == -1) return 0.0;

    // reverse:true이므로 역순 인덱스
    final reversedIndex = comments.length - 1 - targetIndex;

    double totalHeight = 0.0;
    int measuredCount = 0;

    // 타겟보다 뒤에 있는 댓글들의 높이 합산 (reverse:true이므로 index 0부터)
    for (int i = 0; i < reversedIndex; i++) {
      final realIndex = comments.length - 1 - i;
      final comment = comments[realIndex];
      final height = _getCommentHeight(comment.id);

      if (height != null) {
        totalHeight += height;
        measuredCount++;
      }
    }

    // 측정되지 않은 댓글은 평균 높이로 추정
    final unmeasuredCount = reversedIndex - measuredCount;
    if (unmeasuredCount > 0 && measuredCount > 0) {
      final avgHeight = totalHeight / measuredCount;
      totalHeight += avgHeight * unmeasuredCount;
    } else if (measuredCount == 0) {
      // 측정된 것이 없으면 기본 평균값 사용
      totalHeight = reversedIndex * 100.0;
    }

    return totalHeight;
  }

  void _scrollToTargetComment(String commentId) {
    // 🎯 정확한 높이 기반 스크롤
    final comments = _commentService.getAllComments();
    final targetIndex = comments.indexWhere((c) => c.id == commentId);

    if (targetIndex == -1) {
      // 타겟 댓글이 아직 로드되지 않음 - 추가 페이지 로드 후 재시도
      _commentService.loadComments().then((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _scrollToTargetComment(commentId);
            }
          });
        }
      });
      return;
    }

    if (!_scrollController.hasClients) return;

    // 정확한 높이 계산
    final targetOffset = _calculateTargetOffset(commentId);

    _scrollController
        .animateTo(
          targetOffset.clamp(
            0.0,
            _scrollController.position.maxScrollExtent - 100,
          ),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        )
        .then((_) {
          // 스크롤 완료 후 바운싱 애니메이션
          if (mounted) {
            setState(() => _bouncingCommentId = commentId);
            _bounceController.forward(from: 0.0).then((_) {
              _bounceController.reset();
              setState(() => _bouncingCommentId = null);
            });
          }
        });
  }

  Comment? _findTargetComment(String? parentId) {
    if (parentId == null || parentId == '0' || parentId.isEmpty) return null;
    try {
      final allComments = _commentService.getAllComments();
      return allComments.firstWhere((c) => c.id == parentId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allComments = _commentService.getAllComments();
    final comments =
        allComments..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final showLoadingSpinner = _commentService.isLoading && comments.isEmpty;

    if (showLoadingSpinner) {
      print('[CommentBottomSheet] 로딩 스피너 표시 - 댓글 없음');
    }

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
                              showLoadingSpinner
                                  ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : Align(
                                    alignment: Alignment.topCenter,
                                    child: RawScrollbar(
                                      controller: _scrollController,
                                      thumbColor: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.3),
                                      thickness: 4,
                                      radius: const Radius.circular(2),
                                      thumbVisibility: false,
                                      child: ListView.builder(
                                        key: const PageStorageKey(
                                          'comment_list',
                                        ),
                                        controller: _scrollController,
                                        reverse: true, // ✅ 최신 댓글이 아래
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 20,
                                        ),
                                        itemCount: comments.length,
                                        cacheExtent: 500, // 캐시 확장으로 부드러운 스크롤
                                        itemBuilder: (context, index) {
                                          // reverse:true이므로 역순 접근
                                          final reversedIndex =
                                              comments.length - 1 - index;
                                          final comment =
                                              comments[reversedIndex];

                                          // GlobalKey 생성 (높이 측정용, 지연 생성으로 최적화)
                                          final commentKey = _commentKeys
                                              .putIfAbsent(
                                                comment.id,
                                                () => GlobalKey(),
                                              );

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
                                                key: commentKey,
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
        // 🎯 맨 아래로 버튼 (오른쪽 하단)
        if (_showScrollToBottomButton)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            right: 16,
            bottom: _isKeyboardActive ? 60 : 100,
            child: GestureDetector(
              onTap: _scrollToBottom,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 28,
                    ),
                    // 새 메시지 배지
                    if (_showNewMessageBadge)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
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
            if (_replyTarget != null || _editingComment != null) ...[
              Divider(height: 0.5, color: Colors.white.withOpacity(0.2)),
              SizedBox(height: 4),
              // 답글/편집 대상 표시
              Container(
                padding: const EdgeInsets.all(4),

                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _editingComment != null
                            ? AppLocalizations.of(
                              context,
                            ).translate('editing_comment')
                            : '${AppLocalizations.of(context).translate('reply_to')} ${_replyTarget!.author}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
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
                      child: Icon(
                        Icons.close,
                        color: Colors.white.withOpacity(0.7),
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 10),
                  ],
                ),
              ),
            ],

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

/// 댓글 입력 섹션 위젯
class CommentInputSection extends StatelessWidget {
  const CommentInputSection({
    super.key,
    required this.commentController,
    required this.focusNode,
    required this.replyTarget,
    required this.editingComment,
    required this.onSubmit,
    required this.onCancelReply,
    required this.onCancelEdit,
    this.backgroundColor,
    this.foregroundColor,
  });

  final TextEditingController commentController;
  final FocusNode focusNode;
  final Comment? replyTarget;
  final Comment? editingComment;
  final VoidCallback onSubmit;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bgColor = backgroundColor ?? scheme.surface;
    final Color fgColor = foregroundColor ?? scheme.onSurface;

    return Container(
      padding: EdgeInsets.only(left: 0, right: 0, top: 0, bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 입력창
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: commentController,
                  focusNode: focusNode,
                  cursorColor: fgColor,

                  // ✅ 여러 줄 입력 설정
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline, // 엔터 시 줄바꿈
                  maxLines: null, // 무제한 줄

                  style: TextStyle(color: fgColor),
                  decoration: InputDecoration(
                    hintText:
                        editingComment != null
                            ? AppLocalizations.of(
                              context,
                            ).translate('edit_comment_hint')
                            : replyTarget != null
                            ? AppLocalizations.of(
                              context,
                            ).translate('write_reply')
                            : AppLocalizations.of(
                              context,
                            ).translate('write_comment'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(35),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: bgColor,
                    hintStyle: TextStyle(color: fgColor.withOpacity(0.5)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12, // 높이 확보
                    ),
                    suffixIcon: IconButton(
                      onPressed: onSubmit,
                      icon: Icon(Icons.send_rounded, size: 24, color: fgColor),
                    ),
                  ),

                  // ❌ onSubmitted 제거 (엔터를 줄바꿈으로 쓰기 위해)
                  // onSubmitted: (value) => onSubmit(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
