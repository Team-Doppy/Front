import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PostCard extends StatelessWidget {
  final double containerWidth;
  final String imagePath;
  final String title;
  final String author;
  final String content;

  const PostCard({
    super.key,
    required this.containerWidth,
    required this.imagePath,
    required this.title,
    required this.author,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: containerWidth * 0.95,
      height: 120,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      child: Row(
        children: [
          // 왼쪽 사진
          Container(
            width: 144,
            height: 100, // 4:3 비율
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          SizedBox(width: 12),
          // 오른쪽 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 제목
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.lightTextPrimary,
                    fontSize: 16,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                SizedBox(height: 4),
                // 작성자
                Text(
                  author,
                  style: TextStyle(
                    color: AppColors.lightTextSecondary,
                    fontSize: 12,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                // 본문 내용 미리보기
                Text(
                  content,
                  style: TextStyle(
                    color: AppColors.lightTextSecondary,
                    fontSize: 10,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
