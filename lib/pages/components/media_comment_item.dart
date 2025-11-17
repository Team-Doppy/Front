import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/utils/format_utils.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/services/media_comment_service.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 미디어(이미지/비디오) 댓글 아이템 (일반 댓글 스타일)
class MediaCommentItem extends StatefulWidget {
  final MediaComment comment;
  final bool isMe;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final VoidCallback? onProfileTap;
  final bool isLast;
  final VoidCallback? onEdit; // 수정 시작
  final VoidCallback? onDelete; // 삭제

  const MediaCommentItem({
    super.key,
    required this.comment,
    this.isMe = false,
    this.onReply,
    this.onLike,
    this.onProfileTap,
    this.isLast = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<MediaCommentItem> createState() => _MediaCommentItemState();
}

class _MediaCommentItemState extends State<MediaCommentItem> {
  double _dragOffset = 0.0;

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    // 내 댓글만 왼쪽으로 스와이프 가능
    if (!widget.isMe) return;

    setState(() {
      final delta = details.delta.dx;
      // 왼쪽으로만 (음수 방향)
      if (delta < 0) {
        _dragOffset = (_dragOffset + delta).clamp(-120.0, 0.0);
      } else if (delta > 0 && _dragOffset < 0) {
        // 오른쪽으로 복귀
        _dragOffset = (_dragOffset + delta).clamp(-120.0, 0.0);
      }
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    // 임계값 초과 시 열린 상태 유지, 아니면 닫힘
    if (_dragOffset < -60.0) {
      setState(() => _dragOffset = -120.0); // 완전히 열림
    } else {
      setState(() => _dragOffset = 0.0); // 닫힘
    }
  }

  String _formatTime(BuildContext context, String isoString) {
    try {
      // UTC 시간을 로컬 시간으로 변환
      final dateTime = TimeUtils.toLocalTime(isoString);
      final now = DateTime.now();
      final diff = now.difference(dateTime);
      final loc = AppLocalizations.of(context);

      if (diff.inSeconds < 60) {
        return loc.translate('just_now');
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes} ${loc.translate('min_ago')}';
      } else if (diff.inHours < 24) {
        return '${diff.inHours} ${loc.translate('hr_ago')}';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} ${loc.translate('days_ago')}';
      } else {
        return '${dateTime.month}/${dateTime.day}';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          children: [
            // 뒤에 숨겨진 수정/삭제 버튼 (내 댓글일 때만)
            if (widget.isMe)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 수정 버튼
                      GestureDetector(
                        onTap: () {
                          setState(() => _dragOffset = 0.0);
                          widget.onEdit?.call();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(
                              255,
                              126,
                              163,
                              255,
                            ).withOpacity(0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          width: 50,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      // 삭제 버튼
                      GestureDetector(
                        onTap: () {
                          setState(() => _dragOffset = 0.0);
                          widget.onDelete?.call();
                        },
                        child: Container(
                          width: 50,
                          margin: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 앞쪽 댓글 내용 (스와이프 가능)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
              child: GestureDetector(
                onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                onHorizontalDragEnd: _handleHorizontalDragEnd,
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 프로필 사진 (탭 가능)
                        GestureDetector(
                          onTap: widget.onProfileTap,
                          child: CommonProfileAvatar(
                            imageUrl: widget.comment.authorProfileImageUrl,
                            username: widget.comment.author ?? '',
                            size: 47,
                            borderWidth: 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 댓글 내용
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 작성자 + 시간
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.comment.author ?? '',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatTime(
                                      context,
                                      widget.comment.createdAt,
                                    ),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // 댓글 내용
                              Text(
                                widget.comment.text,
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        // 좋아요 (오른쪽 하단)
                        if (widget.onLike != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: GestureDetector(
                              onTap: widget.onLike,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.comment.isLiked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 20,
                                    color:
                                        widget.comment.isLiked
                                            ? Colors.red
                                            : Colors.grey.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatCount(widget.comment.likeCount),
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // 구분선 (마지막 요소가 아닐 때만 표시)
        if (!widget.isLast)
          Padding(
            padding: const EdgeInsets.only(left: 70, right: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
            ),
          ),
      ],
    );
  }
}
