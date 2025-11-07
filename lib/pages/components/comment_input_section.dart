import 'package:flutter/material.dart';
import 'package:doppy/data/services/comment_service.dart';

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
                            ? '수정할 내용을 입력하세요'
                            : replyTarget != null
                            ? '답글을 입력하세요'
                            : '이 글에 대해 채팅하기',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(35),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: bgColor,
                    hintStyle: TextStyle(color: fgColor.withOpacity(0.5)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
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
