import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doppy/utils/text_bold_utils.dart';

@immutable
class HomeTextChunk {
  final String text;
  final bool bold;

  const HomeTextChunk(this.text, {this.bold = false});
}

/// 홈에서 쓰는 텍스트(일반/볼드) 렌더링을 표준화.
///
/// - **볼드 스타일은 NotoSans 계열을 강제**(유지보수/일관성)
/// - 섹션 제목, 카드 오버레이, 캐러셀 오버레이 등 재사용
class HomeRichText extends StatelessWidget {
  final List<HomeTextChunk> chunks;
  final TextStyle baseStyle;
  final TextStyle boldStyle;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;

  const HomeRichText({
    super.key,
    required this.chunks,
    required this.baseStyle,
    required this.boldStyle,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      text: TextSpan(
        children:
            chunks
                .map(
                  (c) => TextSpan(
                    text: c.text,
                    style: c.bold ? boldStyle : baseStyle,
                  ),
                )
                .toList(),
      ),
    );
  }
}

class HomeTypography {
  HomeTypography._();

  /// **볼드는 무조건 NotoSans 계열**로 보장.
  ///
  /// - 한글은 `notoSansKr`가 안정적
  /// - 폰트 fallback에 `Noto Sans`를 강제해(영문 포함) “NotoSans” 요구 충족
  static TextStyle notoBase({
    required Color color,
    required double fontSize,
    FontWeight fontWeight = FontWeight.w300,
    double letterSpacing = -1,
    double height = 1.25,
    List<Shadow>? shadows,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      shadows: shadows,
    ).copyWith(fontFamilyFallback: const ['Noto Sans', 'Noto Sans KR']);
  }

  static TextStyle notoBold({
    required Color color,
    required double fontSize,
    FontWeight fontWeight = FontWeight.w700,
    double letterSpacing = -1.2,
    double height = 1.25,
    List<Shadow>? shadows,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      shadows: shadows,
    ).copyWith(
      // “볼드채는 무조건 NotoSans” 요구 충족(영문 포함 일관성 강화)
      fontFamilyFallback: const ['Noto Sans', 'Noto Sans KR'],
    );
  }
}

/// ✅ 공통 레이아웃 헤더 (서브타이틀 + 타이틀)
/// - 서브타이틀: LocaleTypography, w300, 24font
/// - 타이틀: LocaleTypography, w900, 32font
class HomeLayoutHeader extends StatelessWidget {
  final String? subtitle;
  final String title;
  final EdgeInsets padding;

  const HomeLayoutHeader({
    super.key,
    this.subtitle,
    required this.title,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            Text(
              subtitle!,
              style: LocaleTypography.style(
                context: context,
                fontSize: 24,
                fontWeight: FontWeight.w300,
                color: onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            title,
            style: LocaleTypography.style(
              context: context,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ 빈 상태 레이아웃
class HomeEmptyLayout extends StatelessWidget {
  final String? message;
  final String? actionText;
  final VoidCallback? onActionTap;
  final EdgeInsets padding;

  const HomeEmptyLayout({
    super.key,
    this.message,
    this.actionText,
    this.onActionTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (message != null)
            Expanded(
              child: Text(
                message!,
                style: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  color: onSurface.withOpacity(0.75),
                ),
              ),
            ),
          if (actionText != null && onActionTap != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onActionTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionText!,
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios, size: 18, color: onSurface),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeTextBlurScrim extends StatelessWidget {
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final Widget child;

  const _HomeTextBlurScrim({
    required this.borderRadius,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // “검정 블러를 아주 약간”: blur는 작게, 검정 오버레이도 아주 연하게.
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: Container(
          padding: padding,
          color: Colors.black.withOpacity(0.10),
          child: child,
        ),
      ),
    );
  }
}

class HomeImageCard extends StatelessWidget {
  final ImageProvider image;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  /// 카드 안에 들어갈 제목(옵션). 있으면 **약한 블러+검정 스크림**이 자동 적용됨.
  final List<HomeTextChunk>? title;

  /// 카드 제목 스타일(옵션)
  final double titleFontSize;

  /// 서브텍스트 (제목 아래에 작은 텍스트로 표시)
  final String? subtitle;

  const HomeImageCard({
    super.key,
    required this.image,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.onTap,
    this.title,
    this.titleFontSize = 18,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Colors.white;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadow = Shadow(
      offset: const Offset(0, 1),
      blurRadius: 0,
      color: Colors.black.withOpacity(isDark ? 0.45 : 0.30),
    );

    final card = SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(image: image, fit: BoxFit.cover),
            // 미세한 그라데이션(이미지 가독성 살짝)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.02),
                      Colors.black.withOpacity(0.12),
                    ],
                  ),
                ),
              ),
            ),
            if (title != null && title!.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _HomeTextBlurScrim(
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HomeRichText(
                        chunks: title!,
                        baseStyle: HomeTypography.notoBase(
                          color: onSurface.withOpacity(0.92),
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.6,
                          height: 1.15,
                          shadows: [shadow],
                        ),
                        boldStyle: HomeTypography.notoBold(
                          color: onSurface,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.9,
                          height: 1.15,
                          shadows: [shadow],
                        ),
                        maxLines: 2,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HomeTypography.notoBase(
                            color: onSurface.withOpacity(0.75),
                            fontSize: titleFontSize - 4,
                            fontWeight: FontWeight.w300,
                            letterSpacing: -0.4,
                            height: 1.1,
                            shadows: [shadow],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: borderRadius, child: card);
  }
}

// =============================================================================
// ✅ 레이아웃 데이터 모델
// =============================================================================

/// Layout2 (리스트 뷰)용 카드 데이터
@immutable
class Layout2CardData {
  final ImageProvider image;
  final List<HomeTextChunk>? title;
  final VoidCallback? onTap;
  final String? subtitle;
  final String? postId;

  const Layout2CardData({
    required this.image,
    this.title,
    this.onTap,
    this.subtitle,
    this.postId,
  });
}

/// Layout1 (가득 채우는 스와이프)용 슬라이드 데이터
@immutable
class Layout1SlideData {
  final ImageProvider image;
  final String line1;
  final String line2;
  final VoidCallback? onTap;

  const Layout1SlideData({
    required this.image,
    required this.line1,
    required this.line2,
    this.onTap,
  });
}

/// Layout3 (원형 리스트 뷰)용 친구 데이터
@immutable
class Layout3FriendData {
  final ImageProvider avatar;
  final String name;
  final VoidCallback? onTap;
  final bool hasUnreadStory;

  const Layout3FriendData({
    required this.avatar,
    required this.name,
    this.onTap,
    this.hasUnreadStory = false,
  });
}

// =============================================================================
// ✅ Layout2: 리스트 뷰 (가로 스크롤)
// =============================================================================
class Layout2 extends StatelessWidget {
  final String? subtitle;
  final String title;
  final List<Layout2CardData> cards;
  final String? emptyMessage;
  final String? emptyActionText;
  final VoidCallback? onEmptyActionTap;
  final double bottomSpacing;
  final bool hideWhenEmpty;

  const Layout2({
    super.key,
    this.subtitle,
    required this.title,
    required this.cards,
    this.emptyMessage,
    this.emptyActionText,
    this.onEmptyActionTap,
    this.bottomSpacing = 100,
    this.hideWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cardW = (w - 20 * 2 - 6) / 1.7;
    final cardH = cardW * 1.25;

    if (cards.isEmpty) {
      if (hideWhenEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeLayoutHeader(subtitle: subtitle, title: title),
          const SizedBox(height: 12),
          HomeEmptyLayout(
            message: emptyMessage,
            actionText: emptyActionText,
            onActionTap: onEmptyActionTap,
          ),
          SizedBox(height: bottomSpacing),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeLayoutHeader(subtitle: subtitle, title: title),
        const SizedBox(height: 12),
        SizedBox(
          height: cardH,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              return HomeImageCard(
                image: cards[i].image,
                width: cardW,
                height: cardH,
                title: cards[i].title,
                subtitle: cards[i].subtitle,
                onTap: cards[i].onTap,
              );
            },
          ),
        ),
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

class _HomeDots extends StatelessWidget {
  final int count;
  final int index;

  const _HomeDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(active ? 0.95 : 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

// =============================================================================
// ✅ Layout1: 가득 채우는 스와이프 (PageView)
// =============================================================================
class Layout1 extends StatefulWidget {
  final String? subtitle;
  final String title;
  final List<Layout1SlideData> slides;
  final double height;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final bool hideWhenEmpty;
  final String? emptyMessage;
  final double bottomSpacing;

  const Layout1({
    super.key,
    this.subtitle,
    required this.title,
    required this.slides,
    this.height = 500,
    this.padding = const EdgeInsets.symmetric(horizontal: 0),
    this.borderRadius = const BorderRadius.all(Radius.circular(0)),
    this.hideWhenEmpty = true,
    this.emptyMessage,
    this.bottomSpacing = 100,
  });

  @override
  State<Layout1> createState() => _Layout1State();
}

class _Layout1State extends State<Layout1> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) {
      if (widget.hideWhenEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeLayoutHeader(subtitle: widget.subtitle, title: widget.title),
          const SizedBox(height: 12),
          HomeEmptyLayout(message: widget.emptyMessage),
          SizedBox(height: widget.bottomSpacing),
        ],
      );
    }

    final shadow = Shadow(
      offset: const Offset(0, 1),
      blurRadius: 0,
      color: Colors.black.withOpacity(0.35),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeLayoutHeader(subtitle: widget.subtitle, title: widget.title),
        const SizedBox(height: 12),
        Padding(
          padding: widget.padding,
          child: SizedBox(
            height: widget.height,
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: Stack(
                children: [
                  PageView.builder(
                    physics: const ClampingScrollPhysics(),
                    controller: _controller,
                    itemCount: widget.slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final slide = widget.slides[i];
                      final page = Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(image: slide.image, fit: BoxFit.cover),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.10),
                                    Colors.black.withOpacity(0.28),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            right: 18,
                            top: 18,
                            child: _HomeTextBlurScrim(
                              borderRadius: BorderRadius.circular(14),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    slide.line1,
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.white.withOpacity(0.86),
                                      shadows: [shadow],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    slide.line2,
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      shadows: [shadow],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );

                      if (slide.onTap == null) return page;
                      return InkWell(onTap: slide.onTap, child: page);
                    },
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: _HomeDots(
                        count: widget.slides.length,
                        index: _index.clamp(0, widget.slides.length - 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: widget.bottomSpacing),
      ],
    );
  }
}

// =============================================================================
// ✅ Layout3: 원형 리스트 뷰 (친구 추천 등)
// =============================================================================
class Layout3 extends StatelessWidget {
  final String? subtitle;
  final String title;
  final List<Layout3FriendData> friends;
  final VoidCallback? onAddFriendTap;
  final String? emptyMessage;
  final double bottomSpacing;
  final bool hideWhenEmpty;

  const Layout3({
    super.key,
    this.subtitle,
    required this.title,
    required this.friends,
    this.onAddFriendTap,
    this.emptyMessage,
    this.bottomSpacing = 50,
    this.hideWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;

    if (friends.isEmpty) {
      if (hideWhenEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeLayoutHeader(subtitle: subtitle, title: title),
          const SizedBox(height: 24),
          HomeEmptyLayout(message: emptyMessage),
          SizedBox(height: bottomSpacing),
        ],
      );
    }

    final allItems = <Widget>[];
    for (int i = 0; i < friends.length; i++) {
      final f = friends[i];
      final borderColor =
          f.hasUnreadStory ? primary : onSurface.withOpacity(0.15);
      final borderWidth = f.hasUnreadStory ? 3.0 : 2.0;

      final avatarWidget = Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipOval(
          child: Image(
            image: f.avatar,
            width: 150,
            height: 150,
            fit: BoxFit.cover,
          ),
        ),
      );

      final friendItem = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          f.onTap == null
              ? avatarWidget
              : InkWell(
                onTap: f.onTap,
                borderRadius: BorderRadius.circular(999),
                child: avatarWidget,
              ),
          const SizedBox(height: 10),
          SizedBox(
            width: 150,
            child: Text(
              f.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: LocaleTypography.style(
                context: context,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      );

      allItems.add(friendItem);
      if (i < friends.length - 1 || onAddFriendTap != null) {
        allItems.add(const SizedBox(width: 18));
      }
    }

    if (onAddFriendTap != null) {
      final addButton = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: onSurface.withOpacity(0.2),
                width: 2.0,
                style: BorderStyle.solid,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAddFriendTap,
                borderRadius: BorderRadius.circular(999),
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 48,
                    color: onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 150,
            child: Text(
              '친구 추가',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: LocaleTypography.style(
                context: context,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      );
      allItems.add(addButton);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeLayoutHeader(subtitle: subtitle, title: title),
        const SizedBox(height: 24),
        SizedBox(
          height: 250,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            children: allItems,
          ),
        ),
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

// =============================================================================
// ✅ 레이아웃 호출부 (하드코딩 없이 레이아웃만 부르면 됨)
// =============================================================================
class HomeLayouts {
  /// Layout1: 가득 채우는 스와이프 (PageView)
  static Widget layout1({
    String? subtitle,
    required String title,
    required List<Layout1SlideData> slides,
    double height = 500,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 0),
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(0)),
    bool hideWhenEmpty = true,
    String? emptyMessage,
    double bottomSpacing = 100,
  }) => Layout1(
    subtitle: subtitle,
    title: title,
    slides: slides,
    height: height,
    padding: padding,
    borderRadius: borderRadius,
    hideWhenEmpty: hideWhenEmpty,
    emptyMessage: emptyMessage,
    bottomSpacing: bottomSpacing,
  );

  /// Layout2: 리스트 뷰 (가로 스크롤)
  static Widget layout2({
    String? subtitle,
    required String title,
    required List<Layout2CardData> cards,
    String? emptyMessage,
    String? emptyActionText,
    VoidCallback? onEmptyActionTap,
    double bottomSpacing = 100,
    bool hideWhenEmpty = false,
  }) => Layout2(
    subtitle: subtitle,
    title: title,
    cards: cards,
    emptyMessage: emptyMessage,
    emptyActionText: emptyActionText,
    onEmptyActionTap: onEmptyActionTap,
    bottomSpacing: bottomSpacing,
    hideWhenEmpty: hideWhenEmpty,
  );

  /// Layout3: 원형 리스트 뷰 (친구 추천 등)
  static Widget layout3({
    String? subtitle,
    required String title,
    required List<Layout3FriendData> friends,
    VoidCallback? onAddFriendTap,
    String? emptyMessage,
    double bottomSpacing = 50,
    bool hideWhenEmpty = false,
  }) => Layout3(
    subtitle: subtitle,
    title: title,
    friends: friends,
    onAddFriendTap: onAddFriendTap,
    emptyMessage: emptyMessage,
    bottomSpacing: bottomSpacing,
    hideWhenEmpty: hideWhenEmpty,
  );
}
