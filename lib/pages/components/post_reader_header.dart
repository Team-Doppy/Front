import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';

class PostReaderHeader extends StatelessWidget {
  const PostReaderHeader({
    super.key,
    required this.exportedRoot,
    this.currentExportedData,
    required this.postAuthor,
    required this.authorProfileImageUrl,
    required this.enableAuthorTap,
    required this.onAuthorTap,
    this.horizontalPadding = 20,
    this.topSpacing = 90,
    this.gapHeight = 24,
  });

  final Map<String, dynamic> exportedRoot;
  final Map<String, dynamic>? currentExportedData;
  final String postAuthor;
  final String? authorProfileImageUrl;
  final bool enableAuthorTap;
  final VoidCallback onAuthorTap;

  final double horizontalPadding;
  final double topSpacing;
  final double gapHeight;

  Map<String, dynamic>? get _contentRoot {
    final root = currentExportedData ?? exportedRoot;
    return (root['content'] as Map<String, dynamic>?);
  }

  String _titleAlign() {
    try {
      final nodes = (_contentRoot?['nodes'] as List?) ?? const [];
      for (final n in nodes) {
        if (n is Map) {
          final m = n.cast<String, dynamic>();
          if (m['type'] == 'paragraph' && m['isTitle'] == true) {
            return (m['align'] ?? 'center').toString();
          }
        }
      }
    } catch (_) {}
    return 'center';
  }

  String? _titleFont() {
    try {
      final nodes = (_contentRoot?['nodes'] as List?) ?? const [];
      for (final n in nodes) {
        if (n is Map) {
          final m = n.cast<String, dynamic>();
          if (m['type'] == 'paragraph' && m['isTitle'] == true) {
            final f = m['fontFamily']?.toString();
            if (f != null && f.trim().isNotEmpty) return f.trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  CrossAxisAlignment _toCrossAxis(String a) {
    switch (a) {
      case 'left':
        return CrossAxisAlignment.start;
      case 'right':
        return CrossAxisAlignment.end;
      case 'center':
      default:
        return CrossAxisAlignment.center;
    }
  }

  MainAxisAlignment _toMainAxis(String a) {
    switch (a) {
      case 'left':
        return MainAxisAlignment.start;
      case 'right':
        return MainAxisAlignment.end;
      case 'center':
      default:
        return MainAxisAlignment.center;
    }
  }

  TextAlign _toTextAlign(String a) {
    switch (a) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      case 'center':
      default:
        return TextAlign.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String align = _titleAlign();
    final String? titleFont = _titleFont();
    final TextStyle baseTitleStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.15,
    );
    TextStyle titleStyle = baseTitleStyle;
    if (titleFont != null && titleFont.isNotEmpty) {
      try {
        titleStyle = GoogleFonts.getFont(titleFont, textStyle: titleStyle);
      } catch (_) {
        titleStyle = titleStyle.copyWith(fontFamily: titleFont);
      }
    }

    TextStyle nameStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 18,
      fontWeight: FontWeight.w400,
    );
    if (titleFont != null && titleFont.isNotEmpty) {
      try {
        nameStyle = GoogleFonts.getFont(titleFont, textStyle: nameStyle);
      } catch (_) {
        nameStyle = nameStyle.copyWith(fontFamily: titleFont);
      }
    }

    final String titleText = (exportedRoot['title'] ?? '포스트').toString();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        crossAxisAlignment: _toCrossAxis(align),
        children: [
          SizedBox(height: topSpacing),
          Text(titleText, textAlign: _toTextAlign(align), style: titleStyle),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: enableAuthorTap ? onAuthorTap : null,
            child: Row(
              mainAxisAlignment: _toMainAxis(align),
              children: [
                CommonProfileAvatar(
                  username: postAuthor,
                  imageUrl: authorProfileImageUrl,
                  size: 30,
                  borderWidth: 1,
                ),
                const SizedBox(width: 5),
                Text(
                  postAuthor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
                const SizedBox(width: 15),
              ],
            ),
          ),
          SizedBox(height: gapHeight),
        ],
      ),
    );
  }
}

class PostReaderAppBar extends StatelessWidget {
  const PostReaderAppBar({
    super.key,
    required this.showAppBar,
    required this.barHeight,
    required this.isMyPost,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
    required this.onShowComments,
  });

  final bool showAppBar;
  final double barHeight;
  final bool isMyPost;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShowComments;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      top: showAppBar ? 0 : -barHeight,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !showAppBar,
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: barHeight,
              color: Theme.of(context).colorScheme.background.withOpacity(1),
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  bottom: 5.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 17),
                    GestureDetector(
                      onTap: onBack,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    if (isMyPost) ...[
                      GestureDetector(
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '수정',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '삭제',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                    ] else ...[
                      GestureDetector(
                        onTap: onShowComments,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                              size: 24,
                            ),
                            const SizedBox(width: 15),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
