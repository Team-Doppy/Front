import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/post/postview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class MainCarousel extends StatefulWidget {
  const MainCarousel({super.key});

  @override
  State<MainCarousel> createState() => _MainCarouselState();
}

class _MainCarouselState extends State<MainCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  final _images = const [
    'assets/image/feed1.jpg',
    'assets/image/feed2.png',
    'assets/image/feed3.png',
    'assets/image/feed1.jpg', // 4번째 이미지 추가
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.8, // 카드가 화면의 80% 차지하여 간격 확보
      initialPage: 0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AspectRatio(
        aspectRatio: 4 / 3, // 전체 영역 비율 고정
        child: PageView.builder(
          controller: _pageController,
          padEnds: false, // 패딩 제거
          onPageChanged: (index) {
            setState(() {
              _currentPage = index % _images.length;
            });
          },
          itemCount: _images.length, // 실제 이미지 개수만큼만
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final img = _images[index];
            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 12,
              ), // 좌우 마진 추가하여 간격 확보
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                img,
                fit: BoxFit.cover, // 4:3 비율로 맞춤
                width: double.infinity,
                height: double.infinity,
              ),
            );
          },
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentPage = 0; // 페이지 인디케이터용
  late final PageController _pageController; // PageController 추가

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose(); // PageController 해제
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 반응형 크기 계산
    final containerWidth = screenWidth;
    final containerHeight = screenHeight;

    return Scaffold(
      body: Container(
        width: containerWidth,
        height: containerHeight,
        color: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              // 스크롤 가능한 내용
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // 아이디
                      Container(
                        width: containerWidth,
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Consumer<AuthProvider>(
                                builder: (context, auth, child) {
                                  final username = auth.username ?? '사용자';
                                  return Text(
                                    '@$username',
                                    style: AppTextStyles.headlineMedium
                                        .copyWith(
                                          color: AppColors.lightTextPrimary,
                                        ), // 중형 제목 - 사용자 아이디, 중요 제목
                                  );
                                },
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  // 알람 기능 구현
                                  print('알람 버튼 클릭');
                                },
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Image.asset(
                                    'assets/icons/ic_notification.svg',
                                    width: 24,
                                    height: 24,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.notifications,
                                        size: 24,
                                        color: AppColors.lightTextSecondary,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 메인 이미지 PageView
                      Container(
                        width: containerWidth * 0.9,
                        height: containerHeight * 0.3,
                        margin: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index % 4; // 4로 나눈 나머지로 인덱스 관리
                            });
                          },
                          itemCount: 1000, // 충분히 큰 수로 설정
                          itemBuilder: (context, index) {
                            return Container(
                              margin: EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.asset(
                                  index % 3 == 0
                                      ? 'assets/image/feed1.jpg'
                                      : index % 3 == 1
                                      ? 'assets/image/feed2.png'
                                      : 'assets/image/feed3.png',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // 페이지 인디케이터
                      Container(
                        width: containerWidth,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            return Container(
                              margin: EdgeInsets.symmetric(horizontal: 4),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color:
                                    _currentPage == index
                                        ? AppColors.lightTextPrimary
                                        : AppColors.lightBorder,
                                shape: BoxShape.circle,
                              ),
                            );
                          }),
                        ),
                      ),

                      // 친한 이웃 섹션
                      Container(
                        width: containerWidth,
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          ' 친한 이웃',
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: AppColors.lightTextSecondary,
                          ), // 소형 제목 - 섹션 제목, 포스트 제목
                        ),
                      ),

                      SizedBox(height: 10),

                      // 친한 이웃 카드들 (가로 스크롤)
                      Container(
                        width: containerWidth,
                        height: 160, // 높이 줄임 (180 -> 160)
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: 5, // 친한 이웃 수
                          itemBuilder: (context, index) {
                            return Container(
                              width: containerWidth * 0.4, // 카드 너비
                              margin: EdgeInsets.only(right: 16),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    // 친한 이웃 카드 클릭 기능 구현
                                    print('친한 이웃 카드 ${index + 1} 클릭');
                                  },
                                  child: Column(
                                    children: [
                                      // 사진 부분
                                      Container(
                                        height: 108,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.asset(
                                                index % 3 == 0
                                                    ? 'assets/image/feed1.jpg'
                                                    : index % 3 == 1
                                                    ? 'assets/image/feed2.png'
                                                    : 'assets/image/feed3.png',
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                              ),
                                            ),
                                            // 프로필 사진 (오른쪽 하단)
                                            Positioned(
                                              right: 8,
                                              bottom: 8,
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: ClipOval(
                                                  child: Image.asset(
                                                    'assets/image/profile.png',
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      // 텍스트 부분
                                      Container(
                                        width: containerWidth * 0.4,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ), // 좌우 패딩 추가
                                        child: Text(
                                          index == 0
                                              ? '오늘은 수강신청을 망쳐\n버렸어요'
                                              : index == 1
                                              ? '블로그 1000억 무조건 \n부자될 것 같아'
                                              : index == 2
                                              ? '오늘 날씨가 너무 좋아서\n산책하고 왔어요'
                                              : index == 3
                                              ? '새로운 카페 발견했어요\n맛있었어요!'
                                              : '오늘 하루도 힘내자고\n화이팅!',
                                          style: AppTextStyles.labelSmall
                                              .copyWith(
                                                color:
                                                    AppColors
                                                        .lightTextSecondary,
                                              ), // 작은 라벨 - 부가 정보, 작은 텍스트
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      SizedBox(height: 0),

                      // 전체 이웃 글 보기
                      Container(
                        width: containerWidth,
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '전체 이웃 글 보기',
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: AppColors.lightTextSecondary,
                          ), // 소형 제목 - 섹션 제목, 포스트 제목
                        ),
                      ),

                      SizedBox(height: 4),

                      // 전체 이웃 글들 (Column으로 여러 개)
                      Column(
                        children: List.generate(10, (index) {
                          // 이미지 경로 결정
                          String imagePath =
                              index % 3 == 0
                                  ? 'assets/image/feed1.jpg'
                                  : index % 3 == 1
                                  ? 'assets/image/feed2.png'
                                  : 'assets/image/feed3.png';

                          // 제목 결정
                          String title =
                              index == 0
                                  ? '모태솔로지만연애를해야할까///'
                                  : index == 1
                                  ? '오늘 날씨가 너무 좋아서 산책했어요'
                                  : index == 2
                                  ? '새로운 카페를 발견했어요!'
                                  : index == 3
                                  ? '블로그 1000억 무조건 부자될 것 같아'
                                  : index == 4
                                  ? '오늘은 수강신청을 망쳐버렸어요'
                                  : index == 5
                                  ? '감성 여름이고 싶은데...'
                                  : index == 6
                                  ? '새로운 영화를 봤어요'
                                  : index == 7
                                  ? '오늘 하루도 힘내자고 화이팅!'
                                  : index == 8
                                  ? '새로운 취미를 시작했어요'
                                  : '오늘은 정말 특별한 하루였어요';

                          // 작성자 결정
                          String author =
                              index == 0
                                  ? '수최영'
                                  : index == 1
                                  ? '김여름'
                                  : index == 2
                                  ? '박카페'
                                  : index == 3
                                  ? '이블로그'
                                  : index == 4
                                  ? '정수강'
                                  : index == 5
                                  ? '한감성'
                                  : index == 6
                                  ? '최영화'
                                  : index == 7
                                  ? '강화이팅'
                                  : index == 8
                                  ? '윤취미'
                                  : '임특별';

                          // 본문 내용 결정
                          String content =
                              index == 0
                                  ? '안녕하세여,.오늘은 모태솔로지만연애는하고싶 어후기로돌아왓어요다들키스씬은보셧나요저는보다가기절을할뻔했어요 완전 찰스엔터됨 진짜 갈!!!!!!!!!!!!할뻔함 어쩌고 저쩌고 저ㅉ고어쩌고'
                                  : index == 1
                                  ? '오늘 날씨가 정말 좋아서 산책을 다녀왔어요. 햇살이 따뜻하고 바람도 시원해서 정말 기분이 좋았어요. 특히 공원에서 만난 강아지들이 너무 귀여웠어요!'
                                  : index == 2
                                  ? '새로운 카페를 발견했어요! 분위기도 좋고 커피도 맛있어서 정말 만족스러웠어요. 다음에 친구들과 함께 가보려고 해요.'
                                  : index == 3
                                  ? '블로그로 1000억 벌어서 부자가 될 것 같아요! 열심히 글 쓰고 있으니까 조만간 성공할 것 같아요. 다들 응원해주세요!'
                                  : index == 4
                                  ? '오늘 수강신청을 망쳐버렸어요... 원하는 과목을 못 들었어요. 다음 학기에 다시 도전해보려고 해요. 화이팅!'
                                  : index == 5
                                  ? '감성적인 여름이 되고 싶은데... 바다도 가고 싶고, 별자리도 보고 싶어요. 로맨틱한 여름을 만들어보려고 해요.'
                                  : index == 6
                                  ? '새로운 영화를 봤어요! 스토리도 좋고 연기도 훌륭해서 정말 만족스러웠어요. 추천해드릴게요!'
                                  : index == 7
                                  ? '오늘 하루도 힘내자고 화이팅! 매일매일이 새로운 도전이지만 포기하지 않고 열심히 살아가려고 해요.'
                                  : index == 8
                                  ? '새로운 취미를 시작했어요! 그림 그리기를 시작했는데 생각보다 재미있어요. 시간 가는 줄 모르고 그리게 되네요.'
                                  : '오늘은 정말 특별한 하루였어요. 뜻밖의 좋은 일들이 많이 일어나서 기분이 너무 좋아요. 이런 날들이 더 많았으면 좋겠어요.';

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) =>
                                            PostviewScreen(postId: index),
                                  ),
                                );
                                // 전체 이웃 글 클릭 기능 구현
                                print('전체 이웃 글 ${index + 1} 클릭');
                              },
                              child: PostCard(
                                containerWidth: containerWidth,
                                imagePath: imagePath,
                                title: title,
                                author: author,
                                content: content,
                              ),
                            ),
                          );
                        }),
                      ),

                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 0,
        onTap: (_) {}, // 2번(작성)만 콜백으로 처리됨. 필요시 모달/네비게이션 연결
      ),
    );
  }
}
