import 'package:doppy/data/services/comment_service.dart' as comment_service;
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';

/// 🎯 댓글 이미지 전체화면 뷰 (Hero 애니메이션)
class CommentImageFullscreenDialog extends StatefulWidget {
  final ImageProvider imageProvider; // 🎯 이미지 객체 (재로드 방지)
  final String? imageUrl; // 🎯 다운로드용 URL
  final String? localImagePath; // 🎯 로컬 이미지 경로
  final String heroTag; // 🎯 Hero 태그
  final comment_service.Comment comment; // 🎯 댓글 정보

  const CommentImageFullscreenDialog({
    required this.imageProvider,
    required this.imageUrl,
    required this.localImagePath,
    required this.heroTag,
    required this.comment,
  });

  @override
  State<CommentImageFullscreenDialog> createState() =>
      _CommentImageFullscreenDialogState();
}

class _CommentImageFullscreenDialogState
    extends State<CommentImageFullscreenDialog> {
  bool _isDownloading = false;
  bool _isDownloaded = false;
  double _dragOffset = 0.0; // 🎯 드래그 오프셋 (세로)

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      // 🎯 드래그 거리에 따라 스케일 조절 (인스타그램 느낌)
      final dragDistance = _dragOffset.abs();
      final scale = (1.0 - (dragDistance / 1000)).clamp(0.85, 1.0);
      if ((scale - 1.0).abs() > 0.01) {
        // setState를 최소화
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final dragDistance = _dragOffset.abs();

    // 🎯 임계값 초과하거나 빠른 스와이프 시 닫기
    if (dragDistance > 100 || velocity.abs() > 700) {
      Navigator.of(context).pop();
    } else {
      // 🎯 원위치로 복귀
      setState(() {
        _dragOffset = 0.0;
      });
    }
  }

  Future<void> _downloadImage() async {
    if (_isDownloading || _isDownloaded) return;

    // 로컬 이미지는 다운로드 불가
    if (widget.localImagePath != null) {
      return;
    }

    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _isDownloaded = false;
    });

    try {
      final response = await http.get(Uri.parse(widget.imageUrl!));

      if (response.statusCode == 200) {
        final result = await ImageGallerySaver.saveImage(
          response.bodyBytes,
          quality: 100,
          name: 'doppy_image_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isDownloaded = result != null && result['isSuccess'] == true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isDownloaded = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[CommentImageFullscreen] 다운로드 실패: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isDownloaded = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 드래그 거리에 따른 스케일 계산 (어두워지는 효과 제거)
    final dragDistance = _dragOffset.abs();
    final scale = (1.0 - (dragDistance / 1000)).clamp(0.85, 1.0);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,

      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            // 🎯 가운데 이미지 (Hero 애니메이션)
            Center(
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Transform.scale(
                  scale: scale,
                  child: Hero(
                    tag: widget.heroTag,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 0,
                      child: Image(
                        image: widget.imageProvider,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 200,
                            height: 200,
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withOpacity(0.5),
                            child: Icon(
                              Icons.broken_image,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 🎯 우측 상단 버튼들
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                top: true,
                bottom: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🎯 다운로드 버튼 (네트워크 이미지만)
                    if (widget.localImagePath == null &&
                        widget.imageUrl != null)
                      GestureDetector(
                        onTap:
                            (_isDownloading || _isDownloaded)
                                ? null
                                : _downloadImage,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child:
                                _isDownloading
                                    ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.black87,
                                            ),
                                      ),
                                    )
                                    : _isDownloaded
                                    ? Icon(
                                      Icons.check,
                                      size: 22,
                                      color: Colors.black87,
                                    )
                                    : SvgPicture.asset(
                                      'assets/icons/download.svg',
                                      width: 22,
                                      height: 22,
                                      color: Colors.black87,
                                    ),
                          ),
                        ),
                      ),
                    if (widget.localImagePath == null &&
                        widget.imageUrl != null)
                      const SizedBox(width: 12),
                    // 🎯 닫기 X 버튼
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 24,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 🎯 하단 정보 (보낸 사람, 날짜)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                bottom: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // 🎯 프로필 이미지
                      if (widget.comment.authorProfileImageUrl.isNotEmpty)
                        CommonProfileAvatar(
                          imageUrl: widget.comment.authorProfileImageUrl,
                          username: widget.comment.author,
                          size: 42,
                          borderWidth: 1,
                        ),
                      if (widget.comment.authorProfileImageUrl.isNotEmpty)
                        const SizedBox(width: 12),
                      // 🎯 작성자 이름과 날짜
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.comment.author,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDateString(
                                context,
                                widget.comment.createdAt,
                              ),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.8),
                                fontSize: 12,
                              ),
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
        ),
      ),
    );
  }

  /// 🎯 날짜 포맷팅 (상대 시간)
  String _formatDateString(BuildContext context, String dateStr) {
    try {
      return TimeUtils.formatRelativeTimeFromUtc(context, dateStr);
    } catch (e) {
      // 포맷팅 실패 시 ISO 날짜를 간단히 표시
      try {
        final date = TimeUtils.toLocalTime(dateStr);
        return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return dateStr;
      }
    }
  }
}

/// 댓글 메뉴를 여는 helper 함수
Future<String?> openCommentMenu(
  BuildContext context, {
  required Offset anchor,
  required comment_service.Comment comment,
  required bool isMyComment, // 내 댓글인지 여부
  String? postAuthorUsername, // 🎯 포스트 작성자 username (비밀댓글 권한 체크용)
}) async {
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      anchor.dx - 140,
      anchor.dy + 20,
      anchor.dx,
      anchor.dy,
    ),
    constraints: BoxConstraints(minWidth: 180, maxWidth: 180),

    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    elevation: 8,

    items: [
      // 이모지 반응 (가로 배치)
      PopupMenuItem<String>(
        enabled: false, // 부모 아이템은 클릭 불가
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final emoji in ['❤️', '👍', '😆', '😮', '😭'])
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop(emoji);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      // 답글 (비밀댓글일 때는 호출하는 쪽에서 권한 체크 후 메뉴를 열므로, 여기서는 항상 표시)
      PopupMenuItem<String>(
        value: 'reply',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            AppLocalizations.of(context).translate('reply'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      // 수정 (내 댓글만)
      if (isMyComment)
        PopupMenuItem<String>(
          value: 'edit',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              AppLocalizations.of(context).translate('edit'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // 삭제 (내 댓글만)
      if (isMyComment)
        PopupMenuItem<String>(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              AppLocalizations.of(context).translate('delete'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // 복사
      PopupMenuItem<String>(
        value: 'copy',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            AppLocalizations.of(context).translate('copy'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ],
  );
}
