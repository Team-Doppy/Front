import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class EmptyPostList extends StatefulWidget {
  @override
  State<EmptyPostList> createState() => EmptyPostListState();
}

class EmptyPostListState extends State<EmptyPostList> {
  late PageController _pageController;
  int _currentIndex = 0;
  double _page = 0.0;

  @override
  void initState() {
    super.initState();
    // PostList와 동일한 viewportFraction 사용
    _pageController = PageController(viewportFraction: 0.82);
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
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.none,
      padEnds: true,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      itemCount: 2,
      itemBuilder: (context, index) {
        return _buildEmptyCard(context, index);
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 120, top: 10),
      child: Stack(
        children: [
          pageView,
          Positioned(
            left: 10,
            right: 20,
            bottom: 20,
            child: _buildEmptyAuthor(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context, int index) {
    // PostList와 동일한 스케일 애니메이션
    final content = AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        final double pageNow =
            _pageController.hasClients
                ? (_pageController.page ?? _currentIndex.toDouble())
                : _currentIndex.toDouble();
        final double ad = (pageNow - index).abs().clamp(0.0, 1.0);
        final double t = 1.0 - ad;
        final double eased = Curves.easeOutCubic.transform(t);
        final double scale = 0.9 + 0.1 * eased;
        return Transform.scale(scale: scale, child: child);
      },
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 9 / 12,
              child: _buildEmptyPostCard(context, index),
            ),
          ),
        ],
      ),
    );
    return content;
  }

  Widget _buildEmptyPostCard(BuildContext context, int index) {
    final List<Map<String, dynamic>> cardData = [
      {
        'icon': Icons.add_photo_alternate_rounded,
        'title': '오늘 친구들의 활동이 없네요',
        'subtitle': '내 일상을 올려볼까요?',
        'buttonText': '글쓰기',
        'buttonIcon': Icons.edit_rounded,
        'backgroundImage': 'assets/images/feed1.jpg',
      },
      {
        'icon': Icons.people_rounded,
        'title': '친구를 추가해볼까요?',
        'subtitle': '새로운 사람들과 연결해보세요',
        'buttonText': '친구 찾기',
        'buttonIcon': Icons.search_rounded,
        'backgroundImage': 'assets/images/feed5.jpg',
      },
    ];

    final data = cardData[index];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경 이미지
            Image.asset(
              data['backgroundImage']?.toString() ?? 'assets/images/feed1.jpg',
              fit: BoxFit.cover,
            ),
            // 블러 오버레이
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const ui.Color.fromARGB(182, 144, 144, 144),
                    ],
                  ),
                ),
              ),
            ),
            // Glassy 효과 오버레이
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 1.0],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // 콘텐츠
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data['title'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['subtitle'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.3,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // 버튼
                    Container(
                      width: 180,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0.1),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(25),
                          onTap: () {
                            // TODO: 각 버튼에 따른 액션
                          },
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  data['buttonIcon'] as IconData,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  data['buttonText'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAuthor(BuildContext context) {
    final List<Map<String, dynamic>> cardData = [
      {'title': '오늘 친구들의 활동이 없네요', 'subtitle': '내 일상을 올려볼까요?'},
      {'title': '친구를 추가해볼까요?', 'subtitle': '새로운 사람들과 연결해보세요'},
    ];

    final data = cardData[_currentIndex];

    return Padding(
      padding: const EdgeInsets.only(right: 20, left: 5),
      child: Column(
        key: ValueKey('empty-author-$_currentIndex'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            data['title'] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            data['subtitle'] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
