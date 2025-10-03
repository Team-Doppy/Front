import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';

class LoadingPostList extends StatefulWidget {
  final double containerWidth;
  final int itemCount;

  const LoadingPostList({
    super.key,
    required this.containerWidth,
    this.itemCount = 5,
  });

  @override
  State<LoadingPostList> createState() => _LoadingPostListState();
}

class _LoadingPostListState extends State<LoadingPostList> {
  late PageController _pageController;
  int _currentIndex = 0;
  double _page = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        final current = _pageController.page ?? _currentIndex.toDouble();
        if ((current - _page).abs() > 0.0001) {
          setState(() {
            _page = current;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget pageView = PageView.builder(
      scrollDirection: Axis.horizontal,
      controller: _pageController,
      pageSnapping: true,
      clipBehavior: Clip.none,
      padEnds: true,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        return _buildLoadingPostItem(context, index);
      },
    );

    // 헤더(작가 프로필/이름) + 본문(PageView)를 컬럼으로 분리
    final double topInset = MediaQuery.of(context).padding.top;

    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(24, topInset, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildLoadingAuthor(context)],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: pageView),
        Expanded(flex: 1, child: header),
      ],
    );
  }

  Widget _buildLoadingPostItem(BuildContext context, int index) {
    // 스크롤 진행도 기반 전환 효과 설정
    final bool hasClients = _pageController.hasClients;
    final double pageNow = hasClients ? _page : _currentIndex.toDouble();
    final double delta = pageNow - index;
    final double ad = delta.abs();
    final double proximity = (1.0 - ad).clamp(0.0, 1.0);
    double scale = 0.90 + 0.10 * proximity;

    return Transform.scale(
      scale: scale,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 12,
          child: _buildLoadingPostCard(context),
        ),
      ),
    );
  }

  Widget _buildLoadingPostCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // 이미지 영역 (상단 70%)
            Expanded(
              flex: 7,
              child: ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingAuthor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20, left: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          ShimmerBox(
            width: MediaQuery.of(context).size.width * 0.7,
            height: 22,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          // 내용
          ShimmerBox(
            width: MediaQuery.of(context).size.width * 0.5,
            height: 13,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}
