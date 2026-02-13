import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// PostReader 앱바
/// 스크롤에 따라 표시/숨김을 처리합니다.
class PostReaderAppBar extends StatefulWidget implements PreferredSizeWidget {
  final bool showAppBar;
  final String title;
  final double scrollOffset;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final int animationDuration;

  // 아이콘 설정 (icon 또는 svgPath 중 하나만 제공)
  final IconData? backIcon;
  final String? backSvgPath;
  final String? editSvgPath;
  final IconData? deleteIcon;
  final String? deleteSvgPath;

  const PostReaderAppBar({
    super.key,
    required this.showAppBar,
    required this.title,
    required this.scrollOffset,
    required this.onBack,
    this.onEdit,
    this.onDelete,
    this.animationDuration = 300,
    this.backIcon,
    this.backSvgPath,
    this.editSvgPath,
    this.deleteIcon,
    this.deleteSvgPath,
  }) : assert(
         (backIcon != null) != (backSvgPath != null),
         'backIcon 또는 backSvgPath 중 하나만 제공해야 합니다.',
       ),

       assert(
         deleteIcon == null || deleteSvgPath == null,
         'deleteIcon과 deleteSvgPath를 동시에 제공할 수 없습니다.',
       );

  static const double _toolbarHeight = 44;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbarHeight);

  @override
  State<PostReaderAppBar> createState() => _PostReaderAppBarState();
}

class _PostReaderAppBarState extends State<PostReaderAppBar> {
  static const double _leadingWidth = 80;
  static const double _trailingWidthOneButton = 80;
  static const double _trailingWidthTwoButtons = 100;
  static const double _toolbarHeight = 56;

  static const double _titleVisibleScrollThreshold = 80;

  bool get _titleVisible =>
      widget.showAppBar && widget.scrollOffset >= _titleVisibleScrollThreshold;

  double get _trailingWidth =>
      (widget.onEdit != null && widget.onDelete != null)
      ? _trailingWidthTwoButtons
      : _trailingWidthOneButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.colorScheme.surface;
    final topPadding = MediaQuery.paddingOf(context).top;
    final barHeight = _toolbarHeight + topPadding;

    return AnimatedContainer(
      duration: Duration(milliseconds: widget.animationDuration),
      curve: Curves.easeInOut,
      height: widget.showAppBar ? barHeight : 0,
      child: ClipRect(
        child: Container(
          color: bgColor,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _toolbarHeight,
              child: Row(
                children: [
                  // 왼쪽: 고정 너비
                  SizedBox(
                    width: _leadingWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: widget.showAppBar ? 1 : 0,
                        child: GestureDetector(
                          onTap: widget.onBack,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: _buildIcon(
                              icon:
                                  widget.backIcon ??
                                  Icons.arrow_back_ios_new_rounded,
                              svgPath: widget.backSvgPath,
                              size: 22,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.85,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 중앙: 제목 (스크롤 80px 이상일 때만 표시)
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _titleVisible ? 1 : 0,
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // 오른쪽: edit+delete 두 개일 때 넓이 확보 (오버플로우 방지)
                  SizedBox(
                    width: _trailingWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.onEdit != null)
                            IconButton(
                              onPressed: widget.onEdit,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(6),
                                minimumSize: const Size(36, 36),
                              ),
                              icon: _buildIcon(
                                svgPath: widget.editSvgPath,
                                size: 22,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.75,
                                ),
                              ),
                            ),
                          if (widget.onDelete != null)
                            IconButton(
                              onPressed: widget.onDelete,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(6),
                                minimumSize: const Size(36, 36),
                              ),
                              icon: _buildIcon(
                                icon: widget.deleteIcon ?? Icons.delete_outline,
                                svgPath: widget.deleteSvgPath,
                                size: 22,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.75,
                                ),
                              ),
                            ),
                          SizedBox(width: 4),
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
    );
  }

  /// 아이콘 또는 SVG를 빌드하는 헬퍼 메서드
  Widget _buildIcon({
    IconData? icon,
    String? svgPath,
    required double size,
    required Color color,
  }) {
    if (svgPath != null) {
      return SvgPicture.asset(
        svgPath,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(icon, size: size, color: color);
  }
}
