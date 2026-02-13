import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/emum_config.dart';

/// PostReader 바텀바
/// 공유 | 공개범위 | Spacer | 댓글 - 댓글 수 | 하트 - 하트 수
/// 기본 Material 아이콘 사용, SVG 확장 가능
class PostReaderBottomBar extends StatelessWidget {
  final bool showBottomBar;
  final int animationDuration;
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;
  final VoidCallback? onVisibilityTap;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final AccessLevel? visibility;

  /// 추후 SVG 확장용 (null이면 기본 Icon 사용)
  final String? shareSvgPath;
  final String? visibilityPublicSvgPath;
  final String? visibilityPrivateSvgPath;
  final String? commentSvgPath;
  final String? likeSvgPath;

  const PostReaderBottomBar({
    super.key,
    required this.showBottomBar,
    this.animationDuration = 300,
    this.onLikeTap,
    this.onCommentTap,
    this.onShareTap,
    this.onVisibilityTap,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.visibility,
    this.shareSvgPath,
    this.visibilityPublicSvgPath,
    this.visibilityPrivateSvgPath,
    this.commentSvgPath,
    this.likeSvgPath,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final isPrivate = visibility == AccessLevel.private;

    return AnimatedPositioned(
      duration: Duration(milliseconds: animationDuration),
      curve: Curves.easeInOut,
      bottom: showBottomBar ? 0 : -kToolbarHeight - safeBottom,
      left: 0,
      right: 0,
      child: Container(
        color: theme.colorScheme.surface,
        padding: EdgeInsets.only(bottom: safeBottom),
        child: Container(
          height: kToolbarHeight,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                // 공유
                _ActionButton(
                  icon: shareSvgPath == null ? Icons.share_outlined : null,
                  svgPath: shareSvgPath,
                  label: null,
                  onTap: onShareTap,
                ),
                // 공개범위
                _ActionButton(
                  icon:
                      (isPrivate
                              ? visibilityPrivateSvgPath
                              : visibilityPublicSvgPath) ==
                          null
                      ? (isPrivate
                            ? Icons.lock_outline
                            : Icons.lock_open_outlined)
                      : null,
                  svgPath: isPrivate
                      ? visibilityPrivateSvgPath
                      : visibilityPublicSvgPath,
                  label: null,
                  onTap: onVisibilityTap,
                ),
                const Spacer(),
                // 댓글 - 댓글 수
                _ActionButton(
                  icon: commentSvgPath == null ? Icons.comment_outlined : null,
                  svgPath: commentSvgPath,
                  label: _formatCount(commentCount),
                  onTap: onCommentTap,
                ),
                // 하트 - 하트 수
                _ActionButton(
                  icon: likeSvgPath == null
                      ? (isLiked ? Icons.favorite : Icons.favorite_border)
                      : null,
                  svgPath: likeSvgPath,
                  label: _formatCount(likeCount),
                  color: isLiked ? Colors.red : null,
                  onTap: onLikeTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count == 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}

/// 액션 버튼 위젯
/// icon 또는 svgPath 중 하나를 제공해야 합니다.
class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final String? svgPath;
  final String? label;
  final Color? color;
  final VoidCallback? onTap;

  const _ActionButton({
    this.icon,
    this.svgPath,
    this.label,
    this.color,
    this.onTap,
  }) : assert(
         (icon != null) != (svgPath != null),
         'icon 또는 svgPath 중 하나만 제공해야 합니다.',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.colorScheme.onSurface.withOpacity(0.75);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 24, color: iconColor)
            else if (svgPath != null)
              SvgPicture.asset(
                svgPath!,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            if (label != null && label!.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: iconColor,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
