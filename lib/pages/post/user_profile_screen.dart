import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/profile_top_bar.dart';
import 'package:doppy/pages/components/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  // 프로필 구분을 위한 상태 변수 (테스트용으로 false로 설정)
  bool isOwnProfile = false;

  // 피드 보기 모드 상태 (true: 카드형, false: 리스트형)
  bool isCardView = true;

  // 이웃 요청 상태 관리
  bool isNeighborRequested = false;

  double? _handleTop; // 드래그 핸들의 현재 top 위치
  late double _minHandleTop; // 핸들이 올라갈 수 있는 최소 top
  late double _initialHandleTop; // 초기 핸들 위치 (아래쪽 한계)

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 모바일 기준으로 최대 너비 제한 (오버플로우 방지)
    final maxWidth = screenWidth > 500 ? 500.0 : screenWidth;
    final containerWidth = maxWidth - 8.0; // 오버플로우 방지를 위해 8px 여백 추가
    final containerHeight = screenHeight;

    // 초기 위치 계산 (첫 빌드 시 한 번만)
    if (_handleTop == null) {
      _initialHandleTop = containerHeight * 0.320; // 이웃관리 바로 아래로 더 가깝게 위치
      _handleTop = _initialHandleTop;
      _minHandleTop = 15.0; // 뒤로가기 버튼(top: 25)보다 위로 올라가서 가릴 수 있도록
    }

    // 핸들 위치에 따라 패널 top을 선형 매핑
    final double targetPanelTop = 10.0; // 상단까지 완전히 올라가서 뒤로가기까지 가리도록
    final double initialPanelTop = containerHeight * 0.32; // 패널 초기 위치를 위로 조정
    final double a =
        (initialPanelTop - targetPanelTop) /
        (_initialHandleTop - _minHandleTop);
    final double b = initialPanelTop - a * _initialHandleTop;
    final double panelTop = a * _handleTop! + b;

    // 패널 높이를 동적으로 계산: 패널 top부터 하단 네비게이션 바 바로 위까지
    final double bottomNavHeight = containerHeight * 0.076;
    final double bottomMargin = -5.0; // 하단 네비게이션 바와의 적절한 여백
    final double dynamicPanelHeight =
        containerHeight - panelTop - bottomNavHeight - bottomMargin;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Container(
            width: containerWidth,
            height: containerHeight,
            margin: EdgeInsets.symmetric(horizontal: 4.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.lightBackground),
            child: _buildContent(
              containerWidth,
              containerHeight,
              panelTop,
              dynamicPanelHeight,
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 3,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildContent(
    double containerWidth,
    double containerHeight,
    double panelTop,
    double dynamicPanelHeight,
  ) {
    return Stack(
      children: [
        // 배경
        _buildBackground(containerWidth, containerHeight),

        // 프로필 요소들
        ..._buildProfileElements(containerWidth, containerHeight),
        // 하단 네비게이션 바
        //        _buildBottomNavigation(containerWidth, containerHeight),
        // 피드 패널 (최상위)
        _buildFeedPanel(containerWidth, panelTop, dynamicPanelHeight),

        // 상단 탑바 (최상위)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DoppyTopBar(
            title: isOwnProfile ? '@swimn_' : '@swimn_', // 사용자 아이디 표시
            showBack: !isOwnProfile, // 내 프로필이 아닐 때만 뒤로가기 버튼 표시
            onBack: !isOwnProfile ? () => Navigator.pop(context) : null,
            onMore: () {
              // 더보기 메뉴 로직 (필요시 구현)
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBackground(double containerWidth, double containerHeight) {
    return Positioned(
      left: 0,
      top: 0,
      child: Container(
        width: containerWidth,
        height: containerHeight * 0.4,
        decoration: BoxDecoration(color: AppColors.lightSurface),
      ),
    );
  }

  List<Widget> _buildProfileElements(
    double containerWidth,
    double containerHeight,
  ) {
    List<Widget> elements = [
      // 프로필 이미지 컨테이너
      Positioned(
        left: containerWidth * 0.06,
        top: containerHeight * 0.07, // 위로 올림
        child: Container(
          width: 132, // 고정 크기 132
          height: 132, // 고정 크기 132
          decoration: ShapeDecoration(
            color: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40), // 132/2 = 66
            ),
          ),
        ),
      ),
    ];

    // 내 프로필일 때만 이웃관리, 그룹관리 버튼 표시
    if (isOwnProfile) {
      elements.addAll([
        // 그룹관리 버튼
        Positioned(
          left: containerWidth * 0.517,
          top: containerHeight * 0.25,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {}, // 그룹관리 페이지 이동
              child: Container(
                width: containerWidth * 0.453,
                height: containerHeight * 0.046,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: AppColors.lightBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Center(
                  child: Text(
                    '그룹관리',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.lightTextSecondary,
                    ), // 강조 본문 - 메뉴, 중요 본문
                  ),
                ),
              ),
            ),
          ),
        ),
        // 이웃관리 버튼
        Positioned(
          left: containerWidth * 0.047,
          top: containerHeight * 0.25,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {}, // 이웃관리 페이지 이동
              child: Container(
                width: containerWidth * 0.453,
                height: containerHeight * 0.046,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: AppColors.lightSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Center(
                  child: Text(
                    '이웃관리',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w500,
                    ), // 강조 본문 - 메뉴, 중요 본문
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    } else {
      // 다른 사람 프로필일 때는 "함께 Doppy하는 이웃 n명명" 텍스트와 이웃요청하기 버튼 표시

      // 함께 Doppy하는 친구 텍스트
      elements.add(
        Positioned(
          left: containerWidth * 0.047,
          top: containerHeight * 0.23,
          child: Text(
            '함께 Doppy하는 이웃 3명',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.lightTextSecondary,
            ), // 일반 본문 - 설명 텍스트, 일반 내용
          ),
        ),
      );

      // 이웃요청하기 버튼
      elements.add(
        Positioned(
          left: containerWidth * 0.047,
          top: containerHeight * 0.263,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {
                setState(() {
                  isNeighborRequested = !isNeighborRequested;
                });
                // TODO: 실제 이웃 요청/취소 API 호출
              },
              child: Container(
                width: containerWidth * 0.906, // 전체 너비 사용
                height: containerHeight * 0.046,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color:
                      isNeighborRequested
                          ? AppColors.lightSurfaceVariant
                          : AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Center(
                  child: Text(
                    isNeighborRequested ? '요청됨' : '이웃 요청하기',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color:
                          isNeighborRequested
                              ? AppColors.lightTextSecondary
                              : Colors.white,
                      fontWeight: FontWeight.w600,
                    ), // 일반 본문 - 버튼 텍스트, 라벨
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 사용자 정보들 추가
    elements.addAll(_buildUserInfoTexts(containerWidth, containerHeight));

    // 테스트용 토글 버튼 추가 (나중에 제거 가능)
    elements.add(
      Positioned(
        left: containerWidth * 0.8,
        top: containerHeight * 0.02,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              setState(() {
                isOwnProfile = !isOwnProfile;
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOwnProfile ? AppColors.primary : AppColors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isOwnProfile ? '내 프로필' : '다른 프로필',
                style: AppTextStyles.labelMedium.copyWith(
                  color: Colors.white,
                ), // 일반 라벨 - 버튼 텍스트, 라벨
              ),
            ),
          ),
        ),
      ),
    );

    return elements;
  }

  List<Widget> _buildUserInfoTexts(
    double containerWidth,
    double containerHeight,
  ) {
    return [
      // 사용자 이름
      Positioned(
        left: containerWidth * 0.475,
        top: containerHeight * 0.09, // 위로 올림
        child: Text(
          '수최영',
          style: AppTextStyles.headlineLarge.copyWith(
            color: AppColors.lightTextPrimary,
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ), // 대형 제목 - 사용자 이름, 메인 제목
        ),
      ),
      // 사용자 설명
      Positioned(
        left: containerWidth * 0.475,
        top: containerHeight * 0.16, // 위로 올림
        child: Text(
          '무료로일상공개해드립니다..\n조아요 구독 알림설정까지......',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.lightTextSecondary,
          ), // 작은 본문 - 사용자 ID, 소개글
        ),
      ),
      // 이웃 수
      Positioned(
        left: containerWidth * 0.483,
        top: containerHeight * 0.13, // 위로 올림
        child: Text(
          '이웃 72명',
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.lightTextPrimary,
          ), // 강조 본문 - 메뉴, 중요 본문
        ),
      ),
    ];
  }

  Widget _buildNavIcon(
    String assetPath,
    IconData fallbackIcon,
    double containerWidth,
    double containerHeight,
  ) {
    return Container(
      width: containerWidth * 0.2,
      height: containerHeight * 0.065, // 네비게이션 바 높이에 맞춤
      padding: EdgeInsets.zero, // 패딩 제거
      child: Center(
        child: Image.asset(
          assetPath,
          width: 24,
          height: 24,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              fallbackIcon,
              size: 24,
              color: AppColors.lightTextSecondary,
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeedPanel(
    double containerWidth,
    double panelTop,
    double dynamicPanelHeight,
  ) {
    return Positioned(
      left: 0,
      top: panelTop,
      child: Container(
        width: containerWidth,
        height: dynamicPanelHeight,
        decoration: ShapeDecoration(
          color: AppColors.lightBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            final double nextTop = (_handleTop! + details.delta.dy).clamp(
              _minHandleTop,
              _initialHandleTop,
            );
            if (nextTop != _handleTop) {
              setState(() {
                _handleTop = nextTop;
              });
            }
          },
          onVerticalDragEnd: (details) {
            // 현재 위치에서 최대 높이까지의 거리의 중간점 계산
            final double totalDistance = _initialHandleTop - _minHandleTop;
            final double currentDistance = _initialHandleTop - _handleTop!;
            final double threshold = totalDistance * 0.5; // 50% 지점

            // 50% 이상 드래그했으면 최대 높이로, 미만이면 원래 위치로
            final double targetTop =
                currentDistance >= threshold
                    ? _minHandleTop
                    : _initialHandleTop;

            setState(() {
              _handleTop = targetTop;
            });
          },
          child: Column(
            children: [
              SizedBox(height: 16),
              // 핸들 바
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 16),
              // shape1/2 아이콘 행
              Padding(
                padding: EdgeInsets.only(left: 20, right: 20, bottom: 12),
                child: Row(
                  children: [
                    _buildShapeIcon('assets/icons/card.svg', 20.0, 20.0, true),
                    SizedBox(width: 12.0),
                    _buildShapeIcon('assets/icons/list.svg', 20.0, 20.0, false),
                  ],
                ),
              ),
              // 피드 컨텐츠
              Expanded(
                child:
                    isCardView
                        ? _buildFeedImages(containerWidth, dynamicPanelHeight)
                        : _buildFeedList(containerWidth, dynamicPanelHeight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShapeIcon(
    String assetPath,
    double width,
    double height,
    bool isCard,
  ) {
    final bool isSelected = isCard ? isCardView : !isCardView;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.5),
        splashColor: Colors.grey.withOpacity(0.6),
        highlightColor: Colors.grey.withOpacity(0.3),
        onTap: () {
          setState(() {
            isCardView = isCard;
          });
        },
        child: Container(
          padding: EdgeInsets.all(4),
          child: FutureBuilder<String>(
            future: DefaultAssetBundle.of(context).loadString(assetPath),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return SvgPicture.string(
                  snapshot.data!,
                  width: width,
                  height: height,
                  colorFilter: ColorFilter.mode(
                    isSelected
                        ? AppColors.lightTextSecondary
                        : AppColors.accent,
                    BlendMode.srcIn,
                  ),
                );
              } else {
                return Icon(
                  Icons.grid_view,
                  size: width,
                  color: AppColors.lightTextSecondary,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFeedImages(double containerWidth, double panelHeight) {
    final List<String> feedImages = [
      'assets/images/feed1.jpg',
      'assets/images/feed4.png',
      'assets/images/feed3.png',
      'assets/images/feed2.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
      'assets/images/feed1.jpg',
      'assets/images/feed3.png',
      'assets/images/feed2.png',
      'assets/images/feed4.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
      'assets/images/feed1.jpg',
      'assets/images/feed2.png',
      'assets/images/feed3.png',
      'assets/images/feed4.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 180 / 135, // width / height 비율
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: feedImages.length,
        physics: const AlwaysScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(2),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {}, // 피드 상세보기 페이지 이동
              child: Container(
                decoration: ShapeDecoration(
                  color: AppColors.lightSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.asset(
                    feedImages[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color:
                            index % 2 == 0
                                ? AppColors.accent
                                : AppColors.primary,
                        child: const Center(
                          child: Icon(
                            Icons.image,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedList(double containerWidth, double panelHeight) {
    final List<Map<String, String>> feedData = [
      {
        'image': 'assets/images/feed1.jpg',
        'title': '모태솔로지만연애를해야할까///',
        'author': '수최영',
        'content':
            '안녕하세여,.오늘은 모태솔로지만연애는하고싶 어후기로돌아왓어요다들키스씬은보셧나요저는보다가기절을할뻔했어요 완전 찰스엔터됨 진짜 갈!!!!!!!!!!!!할뻔함 어쩌고 저쩌고 저ㅉ고어쩌고',
      },
      {
        'image': 'assets/images/feed2.png',
        'title': '오늘 날씨가 너무 좋아서 산책했어요',
        'author': '김여름',
        'content':
            '오늘 날씨가 정말 좋아서 산책을 다녀왔어요. 햇살이 따뜻하고 바람도 시원해서 정말 기분이 좋았어요. 특히 공원에서 만난 강아지들이 너무 귀여웠어요!',
      },
      {
        'image': 'assets/images/feed3.png',
        'title': '새로운 카페를 발견했어요!',
        'author': '박카페',
        'content':
            '새로운 카페를 발견했어요! 분위기도 좋고 커피도 맛있어서 정말 만족스러웠어요. 다음에 친구들과 함께 가보려고 해요.',
      },
      {
        'image': 'assets/images/feed4.png',
        'title': '블로그 1000억 무조건 부자될 것 같아',
        'author': '이블로그',
        'content':
            '블로그로 1000억 벌어서 부자가 될 것 같아요! 열심히 글 쓰고 있으니까 조만간 성공할 것 같아요. 다들 응원해주세요!',
      },
      {
        'image': 'assets/images/feed5.jpg',
        'title': '오늘은 수강신청을 망쳐버렸어요',
        'author': '정수강',
        'content':
            '오늘 수강신청을 망쳐버렸어요... 원하는 과목을 못 들었어요. 다음 학기에 다시 도전해보려고 해요. 화이팅!',
      },
    ];

    return ListView.builder(
      itemCount: feedData.length,
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final feed = feedData[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.grey.withOpacity(0.6),
            highlightColor: Colors.grey.withOpacity(0.3),
            onTap: () {
              // 피드 상세보기 페이지 이동
              print('피드 ${index + 1} 클릭');
            },
            child: PostCard(
              containerWidth: containerWidth,
              imagePath: feed['image']!,
              title: feed['title']!,
              author: feed['author']!,
              content: feed['content']!,
            ),
          ),
        );
      },
    );
  }
}
