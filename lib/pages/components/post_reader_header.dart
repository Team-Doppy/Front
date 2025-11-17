import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
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
    required this.isMyPost,
    required this.likeCount,
    required this.commentCount,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.isLiked, // ← 추가
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

  final bool isMyPost;
  final int likeCount;
  final int commentCount;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final bool isLiked; // ← 추가

  Map<String, dynamic>? get _contentRoot {
    final root = currentExportedData ?? exportedRoot;
    return (root['content'] as Map<String, dynamic>?);
  }

  // HEX 문자열(#RRGGBB 또는 AARRGGBB)을 Flutter Color로 변환
  Color _parseHexColor(String input) {
    try {
      String hex = input.trim();
      if (hex.startsWith('#')) hex = hex.substring(1);
      // 6자리면 불투명 알파 추가
      if (hex.length == 6) {
        final value = int.parse(hex, radix: 16);
        return Color(0xFF000000 | value);
      }
      // 8자리면 그대로 사용 (AARRGGBB)
      if (hex.length == 8) {
        final value = int.parse(hex, radix: 16);
        return Color(value);
      }
    } catch (_) {}
    // 파싱 실패 시 onSurface로 폴백
    return Colors.black;
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

  /// 제목 텍스트와 스타일 정보 추출
  Map<String, dynamic> _getTitleData() {
    try {
      final nodes = (_contentRoot?['nodes'] as List?) ?? const [];
      for (final n in nodes) {
        if (n is Map) {
          final m = n.cast<String, dynamic>();
          if (m['type'] == 'paragraph' && m['isTitle'] == true) {
            final text = (m['text'] ?? '').toString();
            final spans = (m['spans'] as List?) ?? const [];
            return {
              'text': text,
              'fontFamily': m['fontFamily'],
              'spans': spans,
            };
          }
        }
      }
    } catch (_) {}
    return {'text': '', 'spans': []};
  }

  /// 제목 TextSpan 빌드 (모든 스타일 속성 반영)
  List<TextSpan> _buildTitleTextSpans(
    String text,
    List spans,
    TextStyle baseStyle,
    String? baseFontFamily,
  ) {
    if (text.isEmpty) return [TextSpan(text: text, style: baseStyle)];

    // 기본 폰트 적용
    TextStyle defaultStyle = baseStyle;
    if (baseFontFamily != null && baseFontFamily.isNotEmpty) {
      try {
        defaultStyle = GoogleFonts.getFont(
          baseFontFamily,
          textStyle: defaultStyle,
        );
      } catch (_) {
        defaultStyle = defaultStyle.copyWith(fontFamily: baseFontFamily);
      }
    }

    final List<TextSpan> result = [];
    int currentPos = 0;

    for (final s in spans) {
      if (s is! Map) continue;
      final m = s.cast<String, dynamic>();
      final int start = (m['start'] as num?)?.toInt() ?? 0;
      final int end = (m['end'] as num?)?.toInt() ?? text.length;
      final annotations = (m['annotations'] as List?) ?? const [];

      // 이전 위치부터 현재 시작까지 기본 스타일 텍스트
      if (currentPos < start) {
        result.add(
          TextSpan(
            text: text.substring(currentPos, start),
            style: defaultStyle,
          ),
        );
      }

      // 현재 span 스타일 빌드
      TextStyle spanStyle = defaultStyle;
      for (final ann in annotations) {
        if (ann is! Map) continue;
        final a = ann.cast<String, dynamic>();

        if (a['bold'] == true) {
          spanStyle = spanStyle.copyWith(fontWeight: FontWeight.bold);
        }
        if (a['italic'] == true) {
          spanStyle = spanStyle.copyWith(fontStyle: FontStyle.italic);
        }
        if (a['underline'] == true) {
          spanStyle = spanStyle.copyWith(decoration: TextDecoration.underline);
        }
        if (a['strikethrough'] == true) {
          spanStyle = spanStyle.copyWith(
            decoration: TextDecoration.lineThrough,
          );
        }
        if (a['color'] != null) {
          try {
            final colorHex = a['color'].toString();
            final color = _parseHexColor(colorHex);
            spanStyle = spanStyle.copyWith(color: color);
          } catch (_) {}
        }
        if (a['fontSize'] != null) {
          final fontSize = (a['fontSize'] as num?)?.toDouble();
          if (fontSize != null) {
            spanStyle = spanStyle.copyWith(fontSize: fontSize);
          }
        }
        if (a['fontFamily'] != null) {
          final fontFamily = a['fontFamily'].toString();
          if (fontFamily.isNotEmpty) {
            try {
              spanStyle = GoogleFonts.getFont(fontFamily, textStyle: spanStyle);
            } catch (_) {
              spanStyle = spanStyle.copyWith(fontFamily: fontFamily);
            }
          }
        }
      }

      result.add(
        TextSpan(
          text: text.substring(start, end.clamp(start, text.length)),
          style: spanStyle,
        ),
      );
      currentPos = end;
    }

    // 나머지 텍스트
    if (currentPos < text.length) {
      result.add(
        TextSpan(text: text.substring(currentPos), style: defaultStyle),
      );
    }

    return result.isEmpty
        ? [TextSpan(text: text, style: defaultStyle)]
        : result;
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
    final Map<String, dynamic> titleData = _getTitleData();

    // 제목은 항상 exportedRoot['title']을 우선 사용 (서버 데이터)
    // content 내부의 isTitle 노드는 스타일 정보만 가져옴
    final root = currentExportedData ?? exportedRoot;
    final String titleText = (root['title'] ?? '포스트').toString();

    final List spans = (titleData['spans'] as List?) ?? const [];
    final String? titleFont = titleData['fontFamily'] as String?;

    // 기본 제목 스타일
    final TextStyle baseTitleStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 30,
      // 기본 두께 완화 (너무 두껍다는 피드백)
      fontWeight: FontWeight.w700,
      height: 1.15,
    );

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

    // 제목을 RichText로 렌더링 (spans의 모든 스타일 반영)
    Widget titleWidget;
    if (spans.isEmpty || titleText.isEmpty) {
      // spans가 없으면 단순 텍스트
      TextStyle titleStyle = baseTitleStyle;
      if (titleFont != null && titleFont.isNotEmpty) {
        try {
          titleStyle = GoogleFonts.getFont(titleFont, textStyle: titleStyle);
        } catch (_) {
          titleStyle = titleStyle.copyWith(fontFamily: titleFont);
        }
      }
      titleWidget = Text(
        titleText,
        textAlign: _toTextAlign(align),
        style: titleStyle,
      );
    } else {
      // spans가 있으면 RichText로 렌더링
      titleWidget = RichText(
        textAlign: _toTextAlign(align),
        text: TextSpan(
          children: _buildTitleTextSpans(
            titleText,
            spans,
            baseTitleStyle,
            titleFont,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        crossAxisAlignment: _toCrossAxis(align),
        children: [
          SizedBox(height: topSpacing),
          titleWidget,
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enableAuthorTap ? onAuthorTap : null,
            child: Row(
              mainAxisAlignment: _toMainAxis(align),
              mainAxisSize: MainAxisSize.min,
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
    required this.title,
    required this.likeCount,
    required this.commentCount,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.isLiked,
    required this.animationDuration, // 🎯 바텀바와 동일한 속도
    this.onMoreTap, // 🎯 글 액션 바텀시트 열기
    this.scrollOffset = 0.0, // 🎯 현재 스크롤 위치 (타이틀 표시용)
  });

  final bool showAppBar;
  final double barHeight;
  final bool isMyPost;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShowComments;
  final String title;
  final int likeCount;
  final int commentCount;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final bool isLiked;
  final int animationDuration; // 🎯 바텀바와 동일한 속도
  final VoidCallback? onMoreTap; // 🎯 글 액션 바텀시트 열기
  final double scrollOffset; // 🎯 현재 스크롤 위치 (타이틀 표시용)

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: Duration(milliseconds: animationDuration), // 🎯 동적 속도
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
                  bottom: 8.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: onBack,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.75),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 15),
                    // 🎯 다른 사람 포스트일 때 타이틀 표시 (헤더가 보이지 않을 때만, 즉 300px 이상일 때만)
                    if (!isMyPost && showAppBar)
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: scrollOffset > 200.0 ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: Text(
                            title.isNotEmpty ? title : '포스트',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (isMyPost) ...[
                      // 수정
                      GestureDetector(
                        onTap: onEdit,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SvgPicture.asset(
                            'assets/icons/pen.svg',
                            width: 22,
                            height: 22,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 삭제
                      GestureDetector(
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SvgPicture.asset(
                            'assets/icons/delete.svg',
                            width: 22,
                            height: 22,
                            color: Colors.red.withOpacity(0.7),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else if (onMoreTap != null) ...[
                      // 🎯 다른 사람 포스트일 때 more_vert 아이콘
                      GestureDetector(
                        onTap: onMoreTap,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.more_vert,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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

class DateFormat {
  static String format(DateTime date) {
    return '${date.year}.${date.month}.${date.day}';
  }
}
