import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ImmersivePostScreen extends StatefulWidget {
  final String heroTag;
  final String imageAsset;
  final String title;
  final String content;

  const ImmersivePostScreen({
    super.key,
    required this.heroTag,
    required this.imageAsset,
    required this.title,
    required this.content,
  });

  @override
  State<ImmersivePostScreen> createState() => _ImmersivePostScreenState();
}

class _ImmersivePostScreenState extends State<ImmersivePostScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // 스크롤 본문: 상단 이미지 영역이 먼저 가려지고, 그 후 본문만 스크롤
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                // 상단 대표 이미지(스크롤로 가려짐)
                SliverPersistentHeader(
                  pinned: false,
                  floating: false,
                  delegate: _ImageHeaderDelegate(
                    heroTag: widget.heroTag,
                    imageAsset: widget.imageAsset,
                    maxHeight: MediaQuery.of(context).size.width * 3 / 4, // 4:3
                  ),
                ),

                // 제목/요약
                SliverToBoxAdapter(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 30, 16, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.content,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 더미 본문 리스트
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 12),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          '더미 본문 문단 ${index + 1}. '
                          '여기에 본문이 이어집니다. 자연스러운 스크롤을 확인하세요. '
                          '감각적인 인터랙션과 함께 읽기 경험을 제공합니다.',
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.7,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }, childCount: 24),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),

          // 닫기 버튼
          Positioned(
            top: media.padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String heroTag;
  final String imageAsset;
  final double maxHeight;

  _ImageHeaderDelegate({
    required this.heroTag,
    required this.imageAsset,
    required this.maxHeight,
  });

  @override
  double get minExtent => 0; // 완전히 가려질 수 있게 0으로

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final double visible = (maxExtent - shrinkOffset).clamp(0.0, maxExtent);
    return SizedBox(
      height: visible,
      child: Hero(
        tag: heroTag,
        child: Image.asset(imageAsset, fit: BoxFit.cover),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ImageHeaderDelegate oldDelegate) {
    return oldDelegate.imageAsset != imageAsset ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.heroTag != heroTag;
  }
}
