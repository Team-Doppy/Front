import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 모바일 기준으로 최대 너비 제한 (오버플로우 방지)
    final maxWidth = screenWidth > 500 ? 500.0 : screenWidth;
    final containerWidth = maxWidth - 8.0; // 오버플로우 방지를 위해 8px 여백 추가
    final containerHeight = screenHeight;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Container(
            width: containerWidth,
            height: containerHeight,
            margin: EdgeInsets.symmetric(horizontal: 4.0), // 좌우 여백 증가
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.lightBackground),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: containerWidth,
                    height: containerHeight * 0.4,
                    decoration: BoxDecoration(color: AppColors.lightSurface),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: containerHeight * 0.34,
                  child: Container(
                    width: containerWidth,
                    height: containerHeight * 0.66,
                    decoration: ShapeDecoration(
                      color: AppColors.lightBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Color(0x3F000000),
                          blurRadius: 4,
                          offset: Offset(0, 4),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: containerHeight * 0.45,
                  child: Container(
                    width: containerWidth,
                    height: containerHeight * 0.55,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        height: containerHeight * 0.9,
                        child: Stack(
                          children: [
                            Positioned(
                              left: (containerWidth - 370) / 2,
                              top: 10.0,
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
                                    'assets/images/feed1.jpg',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.accent,
                                        child: Center(
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
                            Positioned(
                              left: (containerWidth - 370) / 2 + 190,
                              top: 10.0,
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
                                    'assets/images/feed4.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.accent,
                                        child: Center(
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
                            Positioned(
                              left: (containerWidth - 370) / 2,
                              top: 150.0,
                              child: Container(
                                width: 180.0,
                                height: 135.0,
                                decoration: BoxDecoration(
                                  color: AppColors.lightSurfaceVariant,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: Image.asset(
                                    'assets/images/feed3.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.primary,
                                        child: Center(
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
                            Positioned(
                              left: (containerWidth - 370) / 2 + 190,
                              top: 150.0,
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
                                    'assets/images/feed2.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.primary,
                                        child: Center(
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
                            Positioned(
                              left: (containerWidth - 370) / 2,
                              top: 290.0,
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
                                    'assets/images/feed5.jpg',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.primary,
                                        child: Center(
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
                            Positioned(
                              left: (containerWidth - 370) / 2 + 190,
                              top: 290.0,
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
                                    'assets/images/feed6.jpg',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: AppColors.accent,
                                        child: Center(
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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

                Positioned(
                  left: 20.0,
                  top: containerHeight * 0.417,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // shape1 버튼 기능
                        },
                        child: Image.asset(
                          'assets/icons/shape1.png',
                          width: 25.0,
                          height: 25.0,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.grid_view,
                              size: 25.0,
                              color: AppColors.accent,
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 8.0),
                      GestureDetector(
                        onTap: () {
                          // shape2 버튼 기능
                        },
                        child: Image.asset(
                          'assets/icons/shape2.png',
                          width: 25.0,
                          height: 25.0,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.grid_view,
                              size: 25.0,
                              color: AppColors.accent,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: containerWidth * 0.428,
                  top: containerHeight * 0.355,
                  child: Container(
                    width: containerWidth * 0.147,
                    height: containerHeight * 0.01,
                    decoration: ShapeDecoration(
                      color: AppColors.lightBorder,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
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
                Positioned(
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
                        // Home Icon
                        GestureDetector(
                          onTap: () {
                            // 홈 버튼 기능
                          },
                          child: Container(
                            width: containerWidth * 0.2,
                            height: containerHeight * 0.073,
                            child: Center(
                              child: Image.asset(
                                'assets/icons/home.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.home_outlined,
                                    size: 24,
                                    color: AppColors.lightTextSecondary,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // Search Icon
                        GestureDetector(
                          onTap: () {
                            // 검색 버튼 기능
                          },
                          child: Container(
                            width: containerWidth * 0.2,
                            height: containerHeight * 0.073,
                            child: Center(
                              child: Image.asset(
                                'assets/icons/search.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.search_outlined,
                                    size: 24,
                                    color: AppColors.lightTextSecondary,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // Write Icon
                        GestureDetector(
                          onTap: () {
                            // 글쓰기 버튼 기능
                          },
                          child: Container(
                            width: containerWidth * 0.2,
                            height: containerHeight * 0.073,
                            child: Center(
                              child: Image.asset(
                                'assets/icons/write.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.add_box_outlined,
                                    size: 24,
                                    color: AppColors.lightTextSecondary,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        // Profile Icon
                        GestureDetector(
                          onTap: () {
                            // 프로필 버튼 기능
                          },
                          child: Container(
                            width: containerWidth * 0.2,
                            height: containerHeight * 0.073,
                            child: Center(
                              child: Image.asset(
                                'assets/icons/profile.png',
                                width: 24,
                                height: 24,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.person_outline,
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
                ),
                // 뒤로가기 버튼 (최상위에 배치)
                Positioned(
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
                        return Icon(
                          Icons.arrow_back,
                          size: 20.0,
                          color: Colors.black,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
