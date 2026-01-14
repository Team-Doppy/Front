import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/providers/blur_overlay_provider.dart';

/// 주차별 포스트 리스트 콘텐츠 (오버레이용)
class WeekPostListContent extends StatelessWidget {
  final int weekNumber;
  final int year;
  final AnimationController controller;

  const WeekPostListContent({
    super.key,
    required this.weekNumber,
    required this.year,
    required this.controller,
  });

  // 🎯 하드코딩된 테스트 데이터 (홈 데이터 대신) - static으로 고정하여 재생성 방지
  static final List<PostData> _testPosts = [
    PostData(
      id: 'test1',
      title: '테스트 포스트 1',
      content: '이것은 테스트 포스트입니다. 하드코딩된 데이터로 표시됩니다.',
      author: '테스트 작성자',
      authorProfileImageUrl: 'https://picsum.photos/seed/test1/200/200',
      thumbnailImageUrl: 'https://picsum.photos/seed/test1/800/1000',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      summary: '테스트 요약',
      accessLevel: AccessLevel.public,
      viewCount: 0,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
    ),
    PostData(
      id: 'test2',
      title: '테스트 포스트 2',
      content: '두 번째 테스트 포스트입니다.',
      author: '테스트 작성자 2',
      authorProfileImageUrl: 'https://picsum.photos/seed/test2/200/200',
      thumbnailImageUrl: 'https://picsum.photos/seed/test2/800/1000',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      summary: '테스트 요약 2',
      accessLevel: AccessLevel.public,
      viewCount: 0,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
    ),
    PostData(
      id: 'test3',
      title: '테스트 포스트 3',
      content: '세 번째 테스트 포스트입니다.',
      author: '테스트 작성자 3',
      authorProfileImageUrl: 'https://picsum.photos/seed/test3/200/200',
      thumbnailImageUrl: 'https://picsum.photos/seed/test3/800/1000',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      summary: '테스트 요약 3',
      accessLevel: AccessLevel.public,
      viewCount: 0,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // 🎯 PostList의 SliverAppBar를 사용하여 앱바와 함께 스크롤되도록
    return PostList(
      containerWidth: screenWidth,
      posts: _testPosts, // 🎯 static 리스트 사용
      showAppBar: true, // 🎯 SliverAppBar 표시
      sectionLabel: '$year년 $weekNumber주차',
      selectedYear: year,
      selectedWeek: weekNumber,
      isTabActive: true,
      isShowingFriendsOnly: true, // 🎯 그리드 숨기기 (오버레이에서는 PostList만 표시)
      onCloseButton: () {
        // 닫기 버튼 클릭 시 오버레이 닫기
        controller
            .animateTo(0.0, duration: const Duration(milliseconds: 100))
            .then((_) {
              if (context.mounted) {
                context.read<BlurOverlayProvider>().hideBlurOverlay();
              }
            });
      },
      onDragDownToClose: () {
        // 스크롤이 맨 위에 있을 때 아래로 드래그하면 오버레이 닫기
        // 🎯 weekPostList 타입일 때는 더 빠르게 닫기
        controller
            .animateTo(0.0, duration: const Duration(milliseconds: 100))
            .then((_) {
              if (context.mounted) {
                context.read<BlurOverlayProvider>().hideBlurOverlay();
              }
            });
      },
    );
  }
}
