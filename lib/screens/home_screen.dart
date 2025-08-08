import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 반응형 크기 계산
    final containerWidth = screenWidth;
    final containerHeight = screenHeight;

    return Scaffold(
      body: SafeArea(
        child: Container(
          width: containerWidth,
          height: containerHeight,
          color: Colors.white,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // 상단 프로필 영역
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.grey[400],
                        child: Icon(
                          Icons.person,
                          size: 32,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '@affection-jh',
                          style: TextStyle(
                            color: const Color(0xFF292828),
                            fontSize: 20,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.grey[400],
                        child: Icon(
                          Icons.person,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // 메인 이미지
                Container(
                  width: containerWidth * 0.9,
                  height: containerHeight * 0.3,
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Icon(Icons.image, size: 50, color: Colors.grey[600]),
                  ),
                ),

                // 페이지 인디케이터
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),

                // 친한 이웃 섹션
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    ' 친한 이웃',
                    style: TextStyle(
                      color: const Color(0xFF747474),
                      fontSize: 16,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // 친한 이웃 카드들
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 108,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.image,
                              size: 30,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 108,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.image,
                              size: 30,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // 친한 이웃 텍스트들
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '오늘은 수강신청을 망쳐\n버렸어요',
                          style: TextStyle(
                            color: const Color(0xFF575757),
                            fontSize: 10,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '블로그 1000억 무조건 \n부자될 것 같아',
                          style: TextStyle(
                            color: const Color(0xFF727272),
                            fontSize: 10,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // 친한 이웃 이름들
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '모솔을 여름은 메기남',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '모솔을 여름은 메기남',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // 전체 이웃 글 보기
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '전체 이웃 글 보기',
                    style: TextStyle(
                      color: const Color(0xFF747474),
                      fontSize: 16,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // 전체 이웃 글 카드
                Container(
                  width: containerWidth * 0.9,
                  height: 144,
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(Icons.image, size: 30, color: Colors.grey[500]),
                  ),
                ),

                SizedBox(height: 16),

                // 전체 이웃 글 제목
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '모태솔로지만연애를해야할까///',
                    style: TextStyle(
                      color: const Color(0xFF4E4E4E),
                      fontSize: 17,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                SizedBox(height: 8),

                // 전체 이웃 글 작성자
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '수최영',
                    style: TextStyle(
                      color: const Color(0xFF797979),
                      fontSize: 10,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                SizedBox(height: 8),

                // 전체 이웃 글 내용
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '안녕하세여,.오늘은 모태솔로지만연애는하고싶 어후기로돌아왓어요다들키스씬은보셧나요저는보다가기절을할뻔했어요 완전 찰스엔터됨 진짜 갈!!!!!!!!!!!!할뻔함 어쩌고 저쩌고 저ㅉ고어쩌고',
                    style: TextStyle(
                      color: const Color(0xFF717070),
                      fontSize: 8,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // 하단 이미지
                Container(
                  width: containerWidth * 0.9,
                  height: 120,
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(Icons.image, size: 40, color: Colors.grey[600]),
                  ),
                ),

                SizedBox(height: 16),

                // 하단 프로필
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 21,
                        backgroundColor: Colors.grey[400],
                        child: Icon(
                          Icons.person,
                          size: 24,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '모솔을 여름은 메기남',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontFamily: 'Pretendard Variable',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // 하단 텍스트
                Container(
                  width: containerWidth,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '감성 여름이고 싶은데...',
                    style: TextStyle(
                      color: const Color(0xFF797979),
                      fontSize: 10,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                SizedBox(height: 100), // 하단 네비게이션 공간
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(width: 1, color: const Color(0x7FD9D9D9)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Icon(Icons.home, size: 24, color: Colors.grey[600]),
            Icon(Icons.search, size: 24, color: Colors.grey[600]),
            Icon(Icons.add, size: 24, color: Colors.grey[600]),
            Icon(Icons.person, size: 24, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}
