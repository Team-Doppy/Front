// =============================================================================
// 홈피드 서비스 + 청크 모델
// - 스플래시/리프레시에서 서버 데이터를 받아 HomeFeedPayload로 만들고
// - 이 서비스가 "분류 + 빈 처리 규칙" 적용 후 HomeDataChunk로 변환
// - UI(HomeScreen)는 청크만 렌더링
// =============================================================================

import 'package:doppy/pages/components/home_widgets.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';
import 'package:doppy/utils/home_greetings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract class HomeDataChunk {
  const HomeDataChunk();
}

@immutable
class HomeFeedPayload {
  /// ✅ 서버에서 받은 인사말 2줄
  final HomeGreetingMessage greetingMessage;

  /// Layout2: 시간/기간 개념 카드
  final String? layout2Subtitle;
  final String layout2Title;
  final List<Layout2CardData> layout2Cards;

  /// Layout1: 군집 캐러셀
  final String? layout1Subtitle;
  final String layout1Title;
  final List<Layout1SlideData> layout1Slides;

  /// 친구 글 (Layout2 재활용)
  final String? friendsPostsSubtitle;
  final String friendsPostsTitle;
  final List<Layout2CardData> friendsPostsCards;

  /// 친구 추천 (Layout3)
  final String? friendRecommendSubtitle;
  final String friendRecommendTitle;
  final List<Layout3FriendData> recommendedFriends;

  const HomeFeedPayload({
    required this.greetingMessage,
    required this.layout2Title,
    required this.layout2Cards,
    required this.layout1Title,
    required this.layout1Slides,
    required this.friendsPostsTitle,
    required this.friendsPostsCards,
    required this.friendRecommendTitle,
    required this.recommendedFriends,
    this.layout2Subtitle,
    this.layout1Subtitle,
    this.friendsPostsSubtitle,
    this.friendRecommendSubtitle,
  });

  const HomeFeedPayload.empty()
    : greetingMessage = const HomeGreetingMessage(
        line1: [HomeGreetingChunk('안녕하세요')],
        line2: [HomeGreetingChunk('오늘도 좋은 하루 되세요')],
      ),
      layout2Subtitle = null,
      layout2Title = '',
      layout2Cards = const [],
      layout1Subtitle = null,
      layout1Title = '',
      layout1Slides = const [],
      friendsPostsSubtitle = null,
      friendsPostsTitle = '',
      friendsPostsCards = const [],
      friendRecommendSubtitle = null,
      friendRecommendTitle = '',
      recommendedFriends = const [];
}

/// ✅ 레이아웃 청크: 레이아웃 위젯을 감싸는 청크
@immutable
class HomeLayoutChunk extends HomeDataChunk {
  final Widget layout;

  const HomeLayoutChunk(this.layout);
}

/// 홈 화면 전체 데이터 (인사말 + 그리드 + 컨텐츠)
@immutable
class HomeScreenData {
  final HomeGreetingMessage greetingMessage;
  final List<WeeklyContributionData> contributions;
  final List<HomeDataChunk> contentChunks;

  const HomeScreenData({
    required this.greetingMessage,
    required this.contributions,
    required this.contentChunks,
  });
}

class HomeFeedService {
  const HomeFeedService();

  /// 홈 화면 전체 데이터를 한 번에 생성
  /// - 상단 인사말 2줄 (서버에서 받음)
  /// - 그리드 데이터
  /// - 홈 컨텐츠 청크들
  ///
  /// ✅ 이번 주에 없다가 새로 채웠을 때만 로컬 보상 멘트로 오버라이드
  HomeScreenData buildHomeData({
    required HomeFeedPayload payload,
    required bool debugShowEmptyStates,
    required VoidCallback onS1EmptyActionTap,
    required VoidCallback onAddFriendTap,
    // 로케일 문자열 주입
    required String emptyS1Line1,
    required String emptyS1Line2Bold,
    required String friendRecommendTitle,
    // 그리드 데이터
    required List<WeeklyContributionData> contributions,
    // ✅ 이번 주 방금 채웠을 때만 로컬 보상 멘트
    HomeGreetingMessage? localRewardMessage,
  }) {
    // ✅ 서버에서 받은 인사말 사용 (로컬 보상 멘트가 있으면 우선)
    final greetingMessage = localRewardMessage ?? payload.greetingMessage;

    // 홈 컨텐츠 청크 생성
    final contentChunks = buildChunks(
      payload: payload,
      debugShowEmptyStates: debugShowEmptyStates,
      onS1EmptyActionTap: onS1EmptyActionTap,
      onAddFriendTap: onAddFriendTap,
      emptyS1Line1: emptyS1Line1,
      emptyS1Line2Bold: emptyS1Line2Bold,
      friendRecommendTitle: friendRecommendTitle,
    );

    return HomeScreenData(
      greetingMessage: greetingMessage,
      contributions: contributions,
      contentChunks: contentChunks,
    );
  }

  List<HomeDataChunk> buildChunks({
    required HomeFeedPayload payload,
    required bool debugShowEmptyStates,
    required VoidCallback onS1EmptyActionTap,
    required VoidCallback onAddFriendTap,
    // 로케일 문자열 주입
    required String emptyS1Line1,
    required String emptyS1Line2Bold,
    required String friendRecommendTitle,
  }) {
    final showEmptyPreview = debugShowEmptyStates; // 디버그에서만 빈 추천 UI 노출

    return <HomeDataChunk>[
      // Layout2: 주간/기간 카드 섹션
      HomeLayoutChunk(
        HomeLayouts.layout2(
          subtitle: payload.layout2Subtitle,
          title: payload.layout2Title,
          cards: payload.layout2Cards,
          emptyMessage: emptyS1Line1,
          emptyActionText: emptyS1Line2Bold,
          onEmptyActionTap: onS1EmptyActionTap,
        ),
      ),

      // Layout1: 군집/캐러셀 (빈이면 숨김)
      HomeLayoutChunk(
        HomeLayouts.layout1(
          subtitle: payload.layout1Subtitle,
          title: payload.layout1Title,
          slides: payload.layout1Slides,
          hideWhenEmpty: true,
        ),
      ),

      // 친구 글: Layout2 재활용 (빈이면 숨김)
      HomeLayoutChunk(
        HomeLayouts.layout2(
          subtitle: payload.friendsPostsSubtitle,
          title: payload.friendsPostsTitle,
          cards: payload.friendsPostsCards,
          hideWhenEmpty: true,
        ),
      ),

      // 친구 추천: Layout3 (원형) (실제는 빈이면 숨김, 디버그 빈 토글에서는 노출)
      HomeLayoutChunk(
        HomeLayouts.layout3(
          subtitle: payload.friendRecommendSubtitle,
          title: friendRecommendTitle,
          friends: payload.recommendedFriends,
          hideWhenEmpty: showEmptyPreview ? false : true,
          onAddFriendTap: onAddFriendTap,
        ),
      ),
    ];
  }
}
