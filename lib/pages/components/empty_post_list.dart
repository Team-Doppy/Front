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
      itemCount: 2,
      itemBuilder: (context, index) {
        return _buildEmptyCard(context, index);
      },
    );

    // 헤더(작가 프로필/이름) + 본문(PageView)를 컬럼으로 분리
    final double topInset = MediaQuery.of(context).padding.top;

    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(24, topInset, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildEmptyAuthor(context)],
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

  Widget _buildEmptyCard(BuildContext context, int index) {
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
          child: _buildEmptyPostCard(context, index),
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.only(right: 20, left: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Text(
            '빈 피드',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // 내용
          Text(
            '새로운 콘텐츠를 만들어보세요',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
