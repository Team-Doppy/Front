import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/media_comment_service.dart';
import 'package:doppy/pages/components/media_comment_item.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 풀스크린 이미지 뷰어의 댓글 바텀시트 UI 위젯
class FullscreenCommentBottomSheet extends StatefulWidget {
  final List<MediaComment> comments;
  final bool hasMoreComments;
  final bool isLoadingMore;
  final MediaComment? editingComment;
  final TextEditingController commentController;
  final FocusNode commentFocus;
  final ScrollController scrollController;
  final double sheetProgress; // 0.0 ~ 1.0 (바텀시트 열림 정도)
  final VoidCallback onClose;
  final VoidCallback onScrollToLoadMore;
  final Future<void> Function(String text) onSubmit;
  final Future<void> Function(MediaComment comment) onLike;
  final Future<void> Function(MediaComment comment, String newText) onSaveEdit;
  final Future<void> Function(MediaComment comment) onDelete;
  final Future<void> Function(String? username) onProfileTap;
  final Future<void> Function(MediaComment comment) onStartEdit;
  final VoidCallback onCancelEdit;

  const FullscreenCommentBottomSheet({
    super.key,
    required this.comments,
    required this.hasMoreComments,
    required this.isLoadingMore,
    required this.editingComment,
    required this.commentController,
    required this.commentFocus,
    required this.scrollController,
    required this.sheetProgress,
    required this.onClose,
    required this.onScrollToLoadMore,
    required this.onSubmit,
    required this.onLike,
    required this.onSaveEdit,
    required this.onDelete,
    required this.onProfileTap,
    required this.onStartEdit,
    required this.onCancelEdit,
  });

  @override
  State<FullscreenCommentBottomSheet> createState() =>
      _FullscreenCommentBottomSheetState();
}

class _FullscreenCommentBottomSheetState
    extends State<FullscreenCommentBottomSheet> {
  Future<void> _handleSubmit() async {
    final text = widget.commentController.text.trim();
    if (text.isEmpty) return;

    await widget.onSubmit(text);
  }

  Future<void> _handleSaveEdit() async {
    if (widget.editingComment == null) return;

    final text = widget.commentController.text.trim();
    if (text.isEmpty || text == widget.editingComment!.text) {
      widget.onCancelEdit();
      return;
    }

    await widget.onSaveEdit(widget.editingComment!, text);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<UserProvider>().currentUser;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          // 드래그 핸들
          const SizedBox(height: 10),
          Container(
            width: 50,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // 헤더
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Text(
                  '${context.tr('comments')} (${widget.comments.length})',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(1),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Icon(
                      Icons.close,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.9),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),

          // 댓글 리스트
          const SizedBox(height: 8),
          Expanded(
            child:
                widget.comments.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: GestureDetector(
                          onTap: () => widget.commentFocus.requestFocus(),
                          child: AnimatedOpacity(
                            opacity: widget.sheetProgress.clamp(0.0, 1.0),
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                context.tr('first_comment'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // 리스트 영역 탭하면 키보드 내리기
                        FocusScope.of(context).unfocus();
                      },
                      child: RawScrollbar(
                        controller: widget.scrollController,
                        thumbColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
                        thickness: 3,
                        radius: const Radius.circular(2),
                        child: ListView.builder(
                          controller: widget.scrollController,
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          itemCount:
                              widget.comments.length +
                              (widget.hasMoreComments ? 1 : 0),
                          itemBuilder: (context, index) {
                            // 로딩 인디케이터
                            if (index == widget.comments.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }

                            final comment = widget.comments[index];
                            final isMe =
                                currentUser != null &&
                                comment.author == currentUser.username;

                            return MediaCommentItem(
                              comment: comment,
                              isMe: isMe,
                              isLast:
                                  index == widget.comments.length - 1 &&
                                  !widget.hasMoreComments,
                              onReply: () {
                                // TODO: 답글 기능
                              },
                              onLike: () => widget.onLike(comment),
                              onProfileTap:
                                  () => widget.onProfileTap(comment.author),
                              onEdit: () => widget.onStartEdit(comment),
                              onDelete: () => widget.onDelete(comment),
                            );
                          },
                        ),
                      ),
                    ),
          ),

          // 댓글 입력창 (sheetProgress가 0.95 이상일 때만 표시)
          if (widget.sheetProgress >= 0.95)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      height: 0.5,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.1),
                    ),

                    // 수정 중 헤더
                    if (widget.editingComment != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 0),
                        child: Row(
                          children: [
                            Text(
                              context.tr('editing_comment'),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: widget.onCancelEdit,
                              icon: Icon(
                                Icons.close,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 입력 필드
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            cursorColor:
                                Theme.of(context).colorScheme.onSurface,
                            controller: widget.commentController,
                            focusNode: widget.commentFocus,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onBackground,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  widget.editingComment != null
                                      ? AppLocalizations.of(
                                        context,
                                      ).translate('write_comment')
                                      : AppLocalizations.of(
                                        context,
                                      ).translate('leave_reaction'),
                              hintStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onBackground.withOpacity(0.5),
                                fontSize: 14,
                              ),
                              filled: false,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                            ),
                            // ✅ 여러 줄 입력 설정
                            keyboardType: TextInputType.multiline,
                            textInputAction:
                                TextInputAction.newline, // 엔터 시 줄바꿈
                            maxLines: null, // 무제한 줄
                            // ❌ onSubmitted 제거 (엔터를 줄바꿈으로 쓰기 위해)
                          ),
                        ),
                        GestureDetector(
                          onTap:
                              widget.editingComment != null
                                  ? _handleSaveEdit
                                  : _handleSubmit,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.send,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
