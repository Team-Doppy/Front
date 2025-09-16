import 'dart:ui';

import 'package:doppy/pages/post/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class PostCard extends StatefulWidget {
  final double containerWidth;
  final String imagePath;
  final String? heroTag;
  final String title;
  final String author;
  final String content;
  final bool isVisible;
  final List<String> tags; // 태그
  final double scrollProgress; // 스크롤 진행도 (0.0 ~ 1.0)
  final double scale; // 중앙 확대 스케일
  final double parallaxX; // 패럴럭스 X 오프셋
  bool isLiked;
  int likeCount;

  PostCard({
    super.key,
    required this.containerWidth,
    required this.imagePath,
    this.heroTag,
    required this.title,
    required this.author,
    required this.content,
    this.isVisible = false,
    this.tags = const [],
    this.scrollProgress = 1.0,
    this.scale = 1.0,
    this.parallaxX = 0.0,
    this.isLiked = false,
    this.likeCount = 0,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  @override
  Widget build(BuildContext context) {
    final double scaleProgress = ((widget.scale - 0.92) / 0.06).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(color: AppColors.darkBackground),
      margin: EdgeInsets.zero,
      child: ClipRRect(
        clipBehavior: Clip.hardEdge,
        child: Transform.scale(
          scale: widget.scale,
          alignment: Alignment.center,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이미지 영역 - Flex 기반으로 유연하게
                  Expanded(
                    flex: 9,
                    child: Stack(
                      children: [
                        // 이미지 컨테이너
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(widget.parallaxX, 0),
                            child:
                                (widget.heroTag == null)
                                    ? Image.asset(
                                      widget.imagePath,
                                      fit: BoxFit.cover,
                                    )
                                    : Hero(
                                      tag: widget.heroTag!,
                                      child: Image.asset(
                                        widget.imagePath,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                          ),
                        ),
                        // 프로필 정보 오버레이
                        Positioned(
                          top: 12,
                          left: 10,
                          child: AnimatedOpacity(
                            opacity: widget.scrollProgress,
                            duration: Duration(milliseconds: 120),
                            curve: Curves.easeOutCubic,
                            child: Transform.scale(
                              scale: lerpDouble(0.95, 1.08, scaleProgress)!,
                              alignment: Alignment.topLeft,
                              child: _buildProfileInfo(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    flex: 3,
                    child: AnimatedOpacity(
                      opacity: scaleProgress,
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: _buildText(),
                    ),
                  ),
                ],
              ),
              // 카드 오버레이 제거 (페이드 인/아웃 제거)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    print(widget.scrollProgress);
    return Padding(
      padding: EdgeInsets.only(
        top: 20.0,
        left: (1 - widget.scrollProgress) * 30,
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 20,
                fontFamily: 'Pretendard Variable',
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),

            SizedBox(height: 10),
            // 본문 내용 미리보기
            Text(
              widget.content,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
                fontFamily: 'Pretendard Variable',
                fontWeight: FontWeight.w300,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfo() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(username: widget.author),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 255, 255, 255),
                borderRadius: BorderRadius.circular(300),
                border: Border.all(
                  color: const Color.fromARGB(255, 202, 202, 202),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(300),
                child: Image.network(
                  "https://thumbnews.nateimg.co.kr/view610///news.nateimg.co.kr/orgImg/pt/2025/06/12/202506122116776778_684ac5398c368.jpg",
                  fit: BoxFit.cover,
                  width: 33,
                  height: 33,
                ),
              ),
            ),
            SizedBox(width: 4),
            Container(
              margin: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.author,
                    style: TextStyle(
                      color: const Color.fromARGB(255, 225, 225, 225),
                      fontSize: 14,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w600,
                      height: 0.9,
                    ),
                  ),
                  Text(
                    "@affection-jk",
                    style: TextStyle(
                      color: const Color.fromARGB(255, 255, 255, 255),
                      fontSize: 14,
                      fontFamily: 'Pretendard Variable',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
