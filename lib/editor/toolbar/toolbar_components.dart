import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 툴바에서 사용하는 재사용 가능한 UI 컴포넌트들

/// 통합 메인 아이콘 버튼 (일반 아이콘 또는 SVG 아이콘)
class ToolbarMainIcon extends StatelessWidget {
  final IconData? icon;
  final String? svgPath;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;
  final double? size;
  final double iconTopPadding;
  final double? height;

  const ToolbarMainIcon({
    super.key,
    this.icon,
    this.svgPath,
    required this.isActive,
    required this.onTap,
    this.activeColor,
    this.size,
    this.iconTopPadding = 0,
    this.height,
  }) : assert(
         (icon != null) != (svgPath != null),
         'icon 또는 svgPath 중 하나만 제공해야 합니다.',
       );

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color = isActive
        ? (activeColor ?? onSurface)
        : onSurface.withOpacity(0.5);
    final double iconSize = size ?? (isActive ? 28 : 25);
    final double containerHeight = height ?? (svgPath != null ? 40 : 50);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: containerHeight,
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Padding(
              key: ValueKey(icon?.codePoint ?? svgPath),
              padding: EdgeInsets.only(top: iconTopPadding),
              child: icon != null
                  ? Icon(icon, size: iconSize, color: color)
                  : SvgPicture.asset(
                      svgPath!,
                      width: iconSize,
                      height: iconSize,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 통합 토글 아이콘 버튼 (일반 아이콘 또는 SVG 아이콘)
class ToolbarToggleIcon extends StatelessWidget {
  final IconData? icon;
  final String? svgPath;
  final bool isActive;
  final VoidCallback? onTap;
  final double? size;
  final Color? iconColor;

  const ToolbarToggleIcon({
    super.key,
    this.icon,
    this.svgPath,
    required this.isActive,
    this.onTap,
    this.size,
    this.iconColor,
  }) : assert(
         (icon != null) != (svgPath != null),
         'icon 또는 svgPath 중 하나만 제공해야 합니다.',
       );

  @override
  Widget build(BuildContext context) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool isEnabled = onTap != null;
    final double iconSize = size ?? (icon != null ? 20 : 24);
    final Color color =
        iconColor ?? (isActive ? onSurface : onSurface.withOpacity(0.4));

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.3,
      child: Material(
        color: isActive ? surfaceVariant : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: iconSize, color: color)
                : SvgPicture.asset(
                    svgPath!,
                    width: iconSize,
                    height: iconSize,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 통합 칩 버튼 (일반 아이콘 또는 SVG 아이콘)
class ToolbarChip extends StatelessWidget {
  final IconData? icon;
  final String? svgPath;
  final String label;
  final VoidCallback? onTap;
  final double? size;

  const ToolbarChip({
    super.key,
    this.icon,
    this.svgPath,
    required this.label,
    this.onTap,
    this.size,
  }) : assert(
         (icon != null) != (svgPath != null),
         'icon 또는 svgPath 중 하나만 제공해야 합니다.',
       );

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.6);
    final double iconSize = size ?? 20;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon != null
                  ? Icon(icon, size: iconSize, color: onSurface)
                  : SvgPicture.asset(
                      svgPath!,
                      width: iconSize,
                      height: iconSize,
                      colorFilter: ColorFilter.mode(onSurface, BlendMode.srcIn),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구분선
class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final Color borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.1);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: 1,
      height: 28,
      color: borderColor,
    );
  }
}

/// 색상 닷
class ToolbarColorDot extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const ToolbarColorDot({super.key, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.15);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
          ),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
