import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
    final double maxPanelHeight = containerHeight * 0.50; // 패널 최대 높이를 더 줄임
    final double calculatedHeight =
        containerHeight - panelTop - bottomNavHeight - bottomMargin;
    final double dynamicPanelHeight =
        calculatedHeight > maxPanelHeight ? maxPanelHeight : calculatedHeight;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Container(
            width: containerWidth,
            height: containerHeight,
            margin: EdgeInsets.symmetric(horizontal: 4.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.lightBackground),
            child: Column(
              children: [
                // 고정된 상단 빈 공간 (높이 65px)
                Container(
                  width: containerWidth,
                  height: 65.0,
                  color: AppColors.lightSurface,
                ),
                // 기존 컨텐츠를 Expanded로 감싸서 남은 공간 차지
                Expanded(
                  child: _buildContent(
                    containerWidth,
                    containerHeight,
                    panelTop,
                    dynamicPanelHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
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
        _buildBottomNavigation(containerWidth, containerHeight),
        // 뒤로가기 버튼
        _buildBackButton(),
        // 피드 패널 (최상위)
        _buildFeedPanel(containerWidth, panelTop, dynamicPanelHeight),
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
    return [
      // 프로필 이미지 컨테이너
      Positioned(
        left: containerWidth * 0.06,
        top: containerHeight * 0.08,
        child: Container(
          width: containerWidth * 0.34,
          height: containerHeight * 0.15,
          decoration: ShapeDecoration(
            color: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40),
            ),
          ),
        ),
      ),
      // 그룹관리 버튼
      Positioned(
        left: containerWidth * 0.517,
        top: containerHeight * 0.263,
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
              style: TextStyle(
                color: AppColors.lightTextSecondary,
                fontSize: 15,
                fontFamily: 'Pretendard Variable',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
      // 이웃관리 버튼
      Positioned(
        left: containerWidth * 0.047,
        top: containerHeight * 0.263,
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
              style: TextStyle(
                color: AppColors.lightTextPrimary,
                fontSize: 15,
                fontFamily: 'Pretendard Variable',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      // 사용자 정보들
      ..._buildUserInfoTexts(containerWidth, containerHeight),
    ];
  }

  List<Widget> _buildUserInfoTexts(
    double containerWidth,
    double containerHeight,
  ) {
    return [
      // 사용자 아이디
      Positioned(
        left: containerWidth * 0.679,
        top: containerHeight * 0.121,
        child: Text(
          '@swimn_',
          style: TextStyle(
            color: AppColors.lightTextPrimary,
            fontSize: 12,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      // 사용자 이름
      Positioned(
        left: containerWidth * 0.475,
        top: containerHeight * 0.109,
        child: Text(
          '수최영',
          style: TextStyle(
            color: AppColors.lightTextPrimary,
            fontSize: 25,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      // 사용자 설명
      Positioned(
        left: containerWidth * 0.475,
        top: containerHeight * 0.182,
        child: Text(
          '무료로일상공개해드립니다..\n조아요 구독 알림설정까지......',
          style: TextStyle(
            color: AppColors.lightTextSecondary,
            fontSize: 12,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      // 이웃 수
      Positioned(
        left: containerWidth * 0.483,
        top: containerHeight * 0.149,
        child: Text(
          '이웃 72명',
          style: TextStyle(
            color: AppColors.lightTextPrimary,
            fontSize: 15,
            fontFamily: 'Pretendard Variable',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    ];
  }

  Widget _buildBottomNavigation(double containerWidth, double containerHeight) {
    return Positioned(
      left: 0,
      bottom: 0,
      child: Container(
        width: containerWidth,
        height: containerHeight * 0.073,
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: AppColors.lightBackground,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color: AppColors.lightBorder.withOpacity(0.5),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavIcon(
              'assets/icons/home.png',
              Icons.home_outlined,
              containerWidth,
              containerHeight,
            ),
            _buildNavIcon(
              'assets/icons/search.png',
              Icons.search_outlined,
              containerWidth,
              containerHeight,
            ),
            _buildNavIcon(
              'assets/icons/write.png',
              Icons.add_box_outlined,
              containerWidth,
              containerHeight,
            ),
            _buildNavIcon(
              'assets/icons/profile.png',
              Icons.person_outline,
              containerWidth,
              containerHeight,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavIcon(
    String assetPath,
    IconData fallbackIcon,
    double containerWidth,
    double containerHeight,
  ) {
    return GestureDetector(
      onTap: () {},
      child: Container(
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
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      left: 20.0,
      top: 25.0,
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
        },
        child: Image.asset(
          'assets/icons/back.png',
          width: 20.0,
          height: 20.0,
          errorBuilder: (context, error, stackTrace) {
            return Icon(Icons.arrow_back, size: 20.0, color: Colors.black);
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
                    _buildShapeIcon('assets/icons/shape1.png'),
                    SizedBox(width: 8.0),
                    _buildShapeIcon('assets/icons/shape2.png'),
                  ],
                ),
              ),
              // 피드 컨텐츠
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: _calculateFeedHeight(dynamicPanelHeight),
                    child: _buildFeedImages(containerWidth, dynamicPanelHeight),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShapeIcon(String assetPath) {
    return GestureDetector(
      onTap: () {},
      child: Image.asset(
        assetPath,
        width: 25.0,
        height: 25.0,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.grid_view, size: 25.0, color: AppColors.accent);
        },
      ),
    );
  }

  double _calculateFeedHeight(double panelHeight) {
    // 이제 24개 이미지(12행)를 고려한 높이: 12행 * 140px = 1680px + 여백 = 1700px
    double baseFeedHeight = 1700.0;

    // 패널이 커질수록 더 많은 피드를 볼 수 있도록 높이 증가
    // 패널 높이에 직접 비례해서 피드 높이 증가
    double feedHeight = baseFeedHeight + (panelHeight * 0.3); // 패널 높이의 30%만큼 추가

    return feedHeight;
  }

  Widget _buildFeedImages(double containerWidth, double panelHeight) {
    final List<String> feedImages = [
      'assets/images/feed1.jpg',
      'assets/images/feed4.png',
      'assets/images/feed3.png',
      'assets/images/feed2.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
      'assets/images/feed1.jpg', // 재사용
      'assets/images/feed3.png', // 재사용
      'assets/images/feed2.png', // 추가 피드
      'assets/images/feed4.png', // 추가 피드
      'assets/images/feed5.jpg', // 추가 피드
      'assets/images/feed6.jpg', // 추가 피드
      'assets/images/feed1.jpg', // 추가 피드
      'assets/images/feed2.png', // 추가 피드
      'assets/images/feed3.png', // 추가 피드
      'assets/images/feed4.png', // 추가 피드
      'assets/images/feed5.jpg', // 더 많은 피드
      'assets/images/feed6.jpg', // 더 많은 피드
      'assets/images/feed1.jpg', // 더 많은 피드
      'assets/images/feed2.png', // 더 많은 피드
      'assets/images/feed3.png', // 더 많은 피드
      'assets/images/feed4.png', // 더 많은 피드
      'assets/images/feed5.jpg', // 더 많은 피드
      'assets/images/feed6.jpg', // 더 많은 피드
    ];

    // 패널 높이에 따라 이미지 간격 동적 조정
    final double availableHeight = panelHeight - 100; // 상단 여백 제외
    final double imageHeight = 135.0;
    final double dynamicRowSpacing = (availableHeight / 6).clamp(
      125.0,
      160.0,
    ); // 최소 125, 최대 160

    return Stack(
      children: List.generate(feedImages.length, (index) {
        final row = index ~/ 2;
        final col = index % 2;
        return Positioned(
          left: (containerWidth - 370) / 2 + (col * 190),
          top: 10.0 + (row * dynamicRowSpacing),
          child: Container(
            width: 180.0,
            height: 135.0,
            decoration: ShapeDecoration(
              color: AppColors.lightSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
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
                        index % 2 == 0 ? AppColors.accent : AppColors.primary,
                    child: Center(
                      child: Icon(Icons.image, color: Colors.white, size: 40),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }),
    );
  }
}
