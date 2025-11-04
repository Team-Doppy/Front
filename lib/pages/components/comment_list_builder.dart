import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comment_item.dart';

/// 댓글 리스트 빌더 (ListView.builder 로직 분리)
class CommentListBuilder extends StatefulWidget {
  const CommentListBuilder({
    super.key,
    required this.scrollController,
    required this.comments,
    required this.bounceAnimationValue,
    required this.isAnimating,
    required this.findTargetComment,
    required this.onReactionToggle,
    required this.onLongPress,
    required this.onTapTargetComment,
    required this.commentKeys,
    required this.keyboardHeight,
  });

  final ScrollController scrollController;
  final List<Comment> comments;
  final double bounceAnimationValue;
  final bool Function(String) isAnimating;
  final Comment? Function(String?) findTargetComment;
  final Function(String, String) onReactionToggle;
  final Function(Offset, Comment) onLongPress;
  final Function(String) onTapTargetComment;
  final Map<String, GlobalKey> commentKeys;
  final double keyboardHeight;

  @override
  State<CommentListBuilder> createState() => _CommentListBuilderState();
}

class _CommentListBuilderState extends State<CommentListBuilder> {
  double _lastInsetsBottom = 0.0;

  @override
  Widget build(BuildContext context) {
    final double currentInsetsBottom = widget.keyboardHeight;
    print(
      '[CommentList] build - insets: $currentInsetsBottom, last: $_lastInsetsBottom',
    );

    // 키보드가 올라올 때만 스크롤 조정
    if (currentInsetsBottom > _lastInsetsBottom + 20.0) {
      final double delta = currentInsetsBottom - _lastInsetsBottom;
      print('[CommentList] 키보드 올라감 - delta: $delta');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !widget.scrollController.hasClients) {
          print(
            '[CommentList] 스크롤 불가 - mounted: $mounted, hasClients: ${widget.scrollController.hasClients}',
          );
          return;
        }
        // 프레임 반영을 기다린 후 맨 아래로 이동
        await Future.delayed(const Duration(milliseconds: 16));
        if (!mounted || !widget.scrollController.hasClients) return;
        final pos = widget.scrollController.position;
        final target = pos.maxScrollExtent;
        print('[CommentList] 스크롤 이동 - from: ${pos.pixels} to: $target');
        try {
          await widget.scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
          print('[CommentList] 스크롤 완료');
        } catch (e) {
          print('[CommentList] 스크롤 에러: $e');
        }

        // 2차 안전 시도 (애니메이션 중 레이아웃 변경 대비)
        await Future.delayed(const Duration(milliseconds: 48));
        if (!mounted || !widget.scrollController.hasClients) return;
        try {
          final pos2 = widget.scrollController.position;
          final target2 = pos2.maxScrollExtent;
          if ((target2 - pos2.pixels).abs() > 2.0) {
            widget.scrollController.jumpTo(target2);
            print('[CommentList] 스크롤 jumpTo 보정 완료');
          }
        } catch (e) {
          print('[CommentList] jumpTo 에러: $e');
        }
      });
      setState(() {
        _lastInsetsBottom = currentInsetsBottom;
        print('[CommentList] setState - new last: $_lastInsetsBottom');
      });
    } else if ((currentInsetsBottom - _lastInsetsBottom).abs() > 20.0) {
      // 키보드가 내려갈 때 상태만 업데이트
      print('[CommentList] 키보드 내려감');
      setState(() => _lastInsetsBottom = currentInsetsBottom);
    }

    // 하단 패딩을 키보드 높이만큼 추가하여 마지막 항목이 입력창 위에 정확히 붙도록 함
    final EdgeInsets listPadding = EdgeInsets.only(
      left: 8,
      right: 8,
      top: 30,
      bottom: 30 + currentInsetsBottom,
    );

    final ScrollPhysics physics =
        currentInsetsBottom > 0
            ? const ClampingScrollPhysics()
            : const BouncingScrollPhysics();

    return ListView.builder(
      controller: widget.scrollController,
      padding: listPadding,
      physics: physics,
      itemCount: widget.comments.length,
      itemBuilder: (context, index) {
        final comment = widget.comments[index];
        final currentUser = context.read<UserProvider>().currentUser;
        final isMe =
            currentUser != null && comment.author == currentUser.username;

        // 이전 댓글과 같은 사람인지 확인
        final bool isSameAuthorAsPrevious =
            index > 0 && widget.comments[index - 1].author == comment.author;
        final bool showProfile = !isSameAuthorAsPrevious;

        // 다음 댓글도 같은 사람인지 확인
        final bool isSameAuthorAsNext =
            index < widget.comments.length - 1 &&
            widget.comments[index + 1].author == comment.author;
        final bool showAuthorInfo = !isSameAuthorAsNext;

        final targetComment = _findTargetComment(comment);

        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 400),
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
          child: CommentItem(
            comment: comment,
            currentUser: currentUser,
            isMe: isMe,
            showProfile: showProfile,
            showAuthorInfo: showAuthorInfo,
            onReactionToggle: widget.onReactionToggle,
            onLongPress: widget.onLongPress,
            bounceAnimationValue: widget.bounceAnimationValue,
            isAnimating: widget.isAnimating(comment.id),
            onTapTargetComment: widget.onTapTargetComment,
            targetComment: targetComment,
            globalKey: widget.commentKeys[comment.id],
          ),
        );
      },
    );
  }

  Comment? _findTargetComment(Comment comment) {
    if (comment.parentId == null ||
        comment.parentId == '0' ||
        comment.parentId == '') {
      return null;
    }
    return widget.findTargetComment(comment.parentId);
  }
}
