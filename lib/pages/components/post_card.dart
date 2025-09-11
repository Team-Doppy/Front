import 'dart:math';
import 'dart:ui';

import 'package:doppy/pages/post/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class PostCard extends StatefulWidget {
  final double containerWidth;
  final String imagePath;
  final String title;
  final String author;
  final String content;
  final bool isVisible;
  final List<String> tags; // 태그
  final double scrollProgress; // 스크롤 진행도 (0.0 ~ 1.0)
  bool isLiked;
  int likeCount;

  PostCard({
    super.key,
    required this.containerWidth,
    required this.imagePath,
    required this.title,
    required this.author,
    required this.content,
    this.isVisible = false,
    this.tags = const [],
    this.scrollProgress = 1.0,
    this.isLiked = false,
    this.likeCount = 0,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  // 스크롤 진행도에 따른 오버레이 투명도 계산
  double _calculateOverlayAlpha() {
    // 스크롤 진행도가 1.0 (완전히 보이는 상태)일 때는 기본 오버레이 (0.0 ~ 살짝)
    // 스크롤 진행도가 0.0 (완전히 안 보이는 상태)일 때는 완전 검정 (1.0)
    final minAlpha = 0.0; // 정지 후 현재 카드에선 거의 없는 상태를 기본으로
    final maxAlpha = 1.0; // 완전 암전

    // 스크롤 진행도에 따라 부드러운 곡선으로 변화
    final progress = 1.0 - widget.scrollProgress; // 0(밝음) ~ 1(암전)
    final curvedProgress = 1.0 - pow(1.0 - progress, 3);
    final alpha = minAlpha + (maxAlpha - minAlpha) * curvedProgress;

    return alpha.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = widget.containerWidth;

    return Container(
      decoration: BoxDecoration(color: AppColors.darkSurface),
      width: screenWidth,
      margin: EdgeInsets.zero,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 이미지 영역 - Flex 기반으로 유연하게
              Expanded(
                flex: 11,
                child: Stack(
                  children: [
                    // 이미지 컨테이너
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        child: Image.asset(widget.imagePath, fit: BoxFit.cover),
                      ),
                    ),
                    // 프로필 정보 오버레이
                    Positioned(
                      top: 12,
                      left: 10,
                      child: Container(child: _buildProfileInfo()),
                    ),
                    Positioned(
                      bottom: 20,
                      right: 10,
                      child: _buildLikeButton(),
                    ),
                  ],
                ),
              ),
              // 태그 영역 - 이미지와 제목 사이
              if (widget.tags.isNotEmpty)
                AnimatedOpacity(
                  opacity: widget.isVisible ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 600),
                  child: AnimatedSlide(
                    offset: widget.isVisible ? Offset.zero : Offset(0, 0.3),
                    duration: Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    child: _buildTags(),
                  ),
                ),
              // 텍스트 영역 - Flex 기반으로 남은 공간 사용
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_buildText()],
                ),
              ),
            ],
          ),
          // 카드 전체를 덮는 오버레이: 텍스트 영역까지 함께 암전
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: Duration(milliseconds: 90),
                curve: Curves.easeOutCubic,
                color: AppColors.darkSurface.withValues(
                  alpha: _calculateOverlayAlpha(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildText() {
    return AnimatedOpacity(
      opacity: widget.scrollProgress,
      duration: Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.tags.isEmpty) SizedBox(height: 10),
            SizedBox(
              width: widget.containerWidth * 0.9,
              child: Text(
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
            SizedBox(height: 10),
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

  Widget _buildTags() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(left: 10, right: 10, top: 16, bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...widget.tags.map((friend) {
              return Padding(
                padding: EdgeInsets.only(right: 3),
                child: _buildTag(friend),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String tag) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 50, 48, 48),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '#$tag',
        style: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'Pretendard Variable',
        ),
      ),
    );
  }

  Widget _buildLikeButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          widget.isLiked = !widget.isLiked;
          widget.likeCount++;
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.isLiked ? Icons.favorite : Icons.favorite_border,
            color:
                widget.isLiked
                    ? const Color.fromARGB(255, 255, 78, 78)
                    : AppColors.darkTextSecondary,
          ),
          SizedBox(width: 4),
          Text(
            widget.likeCount.toString(),
            style: TextStyle(color: AppColors.darkTextSecondary),
          ),
        ],
      ),
    );
  }
}
