import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

class HomeSectionHeader extends StatelessWidget {
  final List<HomeTextChunk>? line1;
  final List<HomeTextChunk> line2;
  final EdgeInsets padding;
  final double line1FontSize;
  final double line2FontSize;

  const HomeSectionHeader({
    super.key,
    required this.line2,
    this.line1,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.line1FontSize = 20,
    this.line2FontSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadow = Shadow(
      offset: const Offset(0, 0.8),
      blurRadius: 0,
      color: onSurface.withOpacity(isDark ? 0.25 : 0.12),
    );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (line1 != null) ...[
            HomeRichText(
              chunks: line1!,
              baseStyle: HomeTypography.notoBase(
                color: onSurface.withOpacity(0.75),
                fontSize: line1FontSize,
                fontWeight: FontWeight.w300,
                letterSpacing: -0.8,
                height: 1.2,
              ),
              boldStyle: HomeTypography.notoBold(
                color: onSurface.withOpacity(0.75),
                fontSize: line1FontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                height: 1.2,
                shadows: [shadow],
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 2),
          ],
          HomeRichText(
            chunks: line2,
            baseStyle: HomeTypography.notoBase(
              color: onSurface,
              fontSize: line2FontSize,
              fontWeight: FontWeight.w300,
              letterSpacing: -1.0,
              height: 1.2,
            ),
            boldStyle: HomeTypography.notoBold(
              color: onSurface,
              fontSize: line2FontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
              height: 1.2,
              shadows: [shadow],
            ),
            maxLines: 1,
          ),
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

@immutable
class Section1CardData {
  final ImageProvider image;
  final List<HomeTextChunk>? title;
  final VoidCallback? onTap;

  /// 서브텍스트 (카드 하단에 표시될 추가 설명)
  final String? subtitle;

  /// 포스트 ID (클릭 시 상세 페이지 이동용)
  final String? postId;

  const Section1CardData({
    required this.image,
    this.title,
    this.onTap,
    this.subtitle,
    this.postId,
  });
}

class Section1 extends StatelessWidget {
  final List<HomeTextChunk>? headerLine1;
  final List<HomeTextChunk> headerLine2;
  final List<Section1CardData> cards;

  /// 빈 상태일 때 표시할 메시지 (옵션)
  final String? emptyMessage;

  /// 빈 상태일 때 액션 버튼 텍스트 (옵션, 있으면 버튼 표시)
  final String? emptyActionText;

  /// 빈 상태 액션 버튼 클릭 콜백
  final VoidCallback? onEmptyActionTap;

  /// 하단 여백 (섹션 간 간격)
  final double bottomSpacing;

  /// 빈 상태일 때 섹션을 숨길지 여부 (true면 섹션 완전히 숨김)
  final bool hideWhenEmpty;

  const Section1({
    super.key,
    required this.headerLine2,
    required this.cards,
    this.headerLine1,
    this.emptyMessage,
    this.emptyActionText,
    this.onEmptyActionTap,
    this.bottomSpacing = 100,
    this.hideWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final w = MediaQuery.of(context).size.width;
    final cardW = (w - 20 * 2 - 6) / 1.7; // 양옆 패딩 + 카드 간격(6)
    final cardH = cardW * 1.25;

    // 빈 상태 처리
    if (cards.isEmpty) {
      // hideWhenEmpty가 true면 섹션 완전히 숨김
      if (hideWhenEmpty) {
        return const SizedBox.shrink();
      }

      // 빈 상태: 헤더만 표시하고 옆에 ">" 버튼 추가
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onEmptyActionTap ?? () {},
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child:
                        emptyMessage != null
                            ? HomeSectionHeader(
                              line1: [
                                HomeTextChunk(emptyMessage!, bold: false),
                              ],
                              line2:
                                  emptyActionText != null
                                      ? [
                                        HomeTextChunk(
                                          emptyActionText!,
                                          bold: true,
                                        ),
                                      ]
                                      : const [],
                              padding: EdgeInsets.zero, // Row에서 padding 관리
                            )
                            : HomeSectionHeader(
                              line1: headerLine1,
                              line2: headerLine2,
                              padding: EdgeInsets.zero, // Row에서 padding 관리
                            ),
                  ),
                  if (onEmptyActionTap != null) ...[
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                      ), // 헤더와 정렬 맞추기
                      child: GestureDetector(
                        onTap: onEmptyActionTap,
                        child: Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: onSurface.withOpacity(1),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: bottomSpacing),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(line1: headerLine1, line2: headerLine2),
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

@immutable
class Section2SlideData {
  final ImageProvider image;
  final List<HomeTextChunk> line1;
  final List<HomeTextChunk> line2;
  final VoidCallback? onTap;

  const Section2SlideData({
    required this.image,
    required this.line1,
    required this.line2,
    this.onTap,
  });
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

class Section2 extends StatefulWidget {
  final List<Section2SlideData> slides;
  final double height;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  /// 빈 상태일 때 섹션을 숨길지 여부 (true면 null 반환, false면 빈 상태 UI 표시)
  final bool hideWhenEmpty;

  /// 빈 상태일 때 표시할 메시지 (hideWhenEmpty가 false일 때만 사용)
  final String? emptyMessage;

  /// 하단 여백 (섹션 간 간격)
  final double bottomSpacing;

  const Section2({
    super.key,
    required this.slides,
    this.height = 500,
    this.padding = const EdgeInsets.symmetric(horizontal: 0),
    this.borderRadius = const BorderRadius.all(Radius.circular(0)),
    this.hideWhenEmpty = true,
    this.emptyMessage,
    this.bottomSpacing = 100,
  });

  @override
  State<Section2> createState() => _Section2State();
}

class _Section2State extends State<Section2> {
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
    // 빈 상태 처리
    if (widget.slides.isEmpty) {
      if (widget.hideWhenEmpty) {
        return const SizedBox.shrink(); // 섹션 숨김
      }

      // 빈 상태 UI 표시
      final onSurface = Theme.of(context).colorScheme.onSurface;
      return Padding(
        padding: widget.padding,
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.emptyMessage ?? '아직 그룹화된 컨텐츠가 없어요',
                style: HomeTypography.notoBase(
                  color: onSurface.withOpacity(0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.4,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final shadow = Shadow(
      offset: const Offset(0, 1),
      blurRadius: 0,
      color: Colors.black.withOpacity(0.35),
    );

    return Column(
      children: [
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _HomeTextBlurScrim(
                                  borderRadius: BorderRadius.circular(14),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      HomeRichText(
                                        chunks: slide.line1,
                                        baseStyle: HomeTypography.notoBase(
                                          color: Colors.white.withOpacity(0.86),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: -0.6,
                                          height: 1.15,
                                          shadows: [shadow],
                                        ),
                                        boldStyle: HomeTypography.notoBold(
                                          color: Colors.white.withOpacity(0.92),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.8,
                                          height: 1.15,
                                          shadows: [shadow],
                                        ),
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 2),
                                      HomeRichText(
                                        chunks: slide.line2,
                                        baseStyle: HomeTypography.notoBase(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 34,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: -1.2,
                                          height: 1.12,
                                          shadows: [shadow],
                                        ),
                                        boldStyle: HomeTypography.notoBold(
                                          color: Colors.white,
                                          fontSize: 34,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1.8,
                                          height: 1.12,
                                          shadows: [shadow],
                                        ),
                                        maxLines: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

/// Section3는 원형 아바타만 사용 (친구 추천)
/// 친구 글은 Section1을 재활용

@immutable
class Section3FriendData {
  final ImageProvider avatar;
  final String name;
  final VoidCallback? onTap;

  /// 읽지 않은 스토리가 있는지 여부 (스토리 테두리 표시용)
  final bool hasUnreadStory;

  const Section3FriendData({
    required this.avatar,
    required this.name,
    this.onTap,
    this.hasUnreadStory = false,
  });
}

class Section3 extends StatelessWidget {
  final List<HomeTextChunk> header;
  final List<Section3FriendData>? friends;

  /// 친구 추가 버튼 클릭 콜백
  final VoidCallback? onAddFriendTap;

  /// 빈 상태일 때 표시할 메시지 (예: "친구추천으로 할거야!")
  final String? emptyMessage;

  /// 하단 여백 (섹션 간 간격)
  final double bottomSpacing;

  /// 빈 상태일 때 섹션을 숨길지 여부 (true면 섹션 완전히 숨김)
  final bool hideWhenEmpty;

  const Section3({
    super.key,
    required this.header,
    this.friends,
    this.onAddFriendTap,
    this.emptyMessage,
    this.bottomSpacing = 50,
    this.hideWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;

    final friendsList = friends ?? [];

    // 빈 상태 처리
    if (friendsList.isEmpty) {
      // hideWhenEmpty가 true면 섹션 완전히 숨김
      if (hideWhenEmpty) {
        return const SizedBox.shrink();
      }

      // 회색 원형 2개 표시 (메시지 없이)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: HomeRichText(
              chunks: header,
              baseStyle: HomeTypography.notoBase(
                color: onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.8,
                height: 1.2,
              ),
              boldStyle: HomeTypography.notoBold(
                color: onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.1,
                height: 1.2,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              children: [
                // 회색 원형 2개 표시
                for (int i = 0; i < 2; i++) ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: onSurface.withOpacity(0.15),
                            width: 1.2,
                          ),
                          color: onSurface.withOpacity(0.05),
                        ),
                      ),
                    ],
                  ),
                  if (i < 1) const SizedBox(width: 18), // 첫 번째와 두 번째 사이 간격
                ],
              ],
            ),
          ),
          SizedBox(height: bottomSpacing),
        ],
      );
    }

    // 친구 리스트 + 친구 추가 버튼
    final allItems = <Widget>[];
    for (int i = 0; i < friendsList.length; i++) {
      final f = friendsList[i];

      // 스토리 테두리 (읽지 않은 스토리가 있으면 primary 색상, 없으면 회색)
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
              style: HomeTypography.notoBold(
                color: onSurface.withOpacity(0.8),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                height: 1.1,
              ),
            ),
          ),
        ],
      );

      allItems.add(friendItem);
      if (i < friendsList.length - 1 || onAddFriendTap != null) {
        allItems.add(const SizedBox(width: 18));
      }
    }

    // 친구 추가 버튼 (항상 마지막에)
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
              style: HomeTypography.notoBold(
                color: onSurface.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.4,
                height: 1.1,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: HomeRichText(
            chunks: header,
            baseStyle: HomeTypography.notoBase(
              color: onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.8,
              height: 1.2,
            ),
            boldStyle: HomeTypography.notoBold(
              color: onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.1,
              height: 1.2,
            ),
            maxLines: 1,
          ),
        ),
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

/// 호출부에서는 일단 `HomeWidgets.section1/2/3`로만 써도 되게 “템플릿 엔트리” 제공.
class HomeWidgets {
  static Widget section1({
    List<HomeTextChunk>? headerLine1,
    required List<HomeTextChunk> headerLine2,
    required List<Section1CardData> cards,
    String? emptyMessage,
    String? emptyActionText,
    VoidCallback? onEmptyActionTap,
    double bottomSpacing = 100,
    bool hideWhenEmpty = false,
  }) => Section1(
    headerLine1: headerLine1,
    headerLine2: headerLine2,
    cards: cards,
    emptyMessage: emptyMessage,
    emptyActionText: emptyActionText,
    onEmptyActionTap: onEmptyActionTap,
    bottomSpacing: bottomSpacing,
    hideWhenEmpty: hideWhenEmpty,
  );

  static Widget section2({
    required List<Section2SlideData> slides,
    bool hideWhenEmpty = true,
    String? emptyMessage,
    double bottomSpacing = 100,
  }) => Section2(
    slides: slides,
    hideWhenEmpty: hideWhenEmpty,
    emptyMessage: emptyMessage,
    bottomSpacing: bottomSpacing,
  );

  /// Section3: 원형 아바타 (친구 추천)
  static Widget section3({
    required List<HomeTextChunk> header,
    required List<Section3FriendData> friends,
    VoidCallback? onAddFriendTap,
    String? emptyMessage,
    double bottomSpacing = 50,
    bool hideWhenEmpty = false,
  }) => Section3(
    header: header,
    friends: friends,
    onAddFriendTap: onAddFriendTap,
    emptyMessage: emptyMessage,
    bottomSpacing: bottomSpacing,
    hideWhenEmpty: hideWhenEmpty,
  );
}
