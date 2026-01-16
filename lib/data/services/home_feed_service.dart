// =============================================================================
// 홈피드 서비스 + 청크 모델
// - 스플래시/리프레시에서 서버 데이터를 받아 HomeFeedPayload로 만들고
// - 이 서비스가 "분류 + 빈 처리 규칙" 적용 후 HomeDataChunk로 변환
// - UI(HomeScreen)는 청크만 렌더링
// =============================================================================

import 'package:doppy/pages/components/home_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract class HomeDataChunk {
  const HomeDataChunk();
}

@immutable
class HomeFeedPayload {
  /// Section1: 시간/기간 개념 카드
  final List<HomeTextChunk>? section1HeaderLine1;
  final List<HomeTextChunk> section1HeaderLine2;
  final List<Section1CardData> section1Cards;

  /// Section2: 군집 캐러셀
  final List<Section2SlideData> section2Slides;

  /// 친구 글(Section1 재활용)
  final List<HomeTextChunk> friendsPostsHeaderLine2;
  final List<Section1CardData> friendsPostsCards;

  /// 친구 추천(Section3)
  final List<HomeTextChunk> friendRecommendHeader;
  final List<Section3FriendData> recommendedFriends;

  const HomeFeedPayload({
    required this.section1HeaderLine2,
    required this.section1Cards,
    required this.section2Slides,
    required this.friendsPostsHeaderLine2,
    required this.friendsPostsCards,
    required this.friendRecommendHeader,
    required this.recommendedFriends,
    this.section1HeaderLine1,
  });

  const HomeFeedPayload.empty()
    : section1HeaderLine1 = null,
      section1HeaderLine2 = const [],
      section1Cards = const [],
      section2Slides = const [],
      friendsPostsHeaderLine2 = const [],
      friendsPostsCards = const [],
      friendRecommendHeader = const [],
      recommendedFriends = const [];
}

@immutable
class HomeSection1Chunk extends HomeDataChunk {
  final List<HomeTextChunk>? headerLine1;
  final List<HomeTextChunk> headerLine2;
  final List<Section1CardData> cards;
  final bool hideWhenEmpty;
  final String? emptyMessage;
  final String? emptyActionText;
  final VoidCallback? onEmptyActionTap;
  final double bottomSpacing;

  const HomeSection1Chunk({
    required this.headerLine2,
    required this.cards,
    this.headerLine1,
    this.hideWhenEmpty = false,
    this.emptyMessage,
    this.emptyActionText,
    this.onEmptyActionTap,
    this.bottomSpacing = 100,
  });
}

@immutable
class HomeSection2Chunk extends HomeDataChunk {
  final List<Section2SlideData> slides;
  final bool hideWhenEmpty;
  final double bottomSpacing;

  const HomeSection2Chunk({
    required this.slides,
    this.hideWhenEmpty = true,
    this.bottomSpacing = 100,
  });
}

@immutable
class HomeSection3Chunk extends HomeDataChunk {
  final List<HomeTextChunk> header;
  final List<Section3FriendData> friends;
  final bool hideWhenEmpty;
  final VoidCallback? onAddFriendTap;
  final String? emptyMessage;
  final double bottomSpacing;

  const HomeSection3Chunk({
    required this.header,
    required this.friends,
    this.hideWhenEmpty = true,
    this.onAddFriendTap,
    this.emptyMessage,
    this.bottomSpacing = 50,
  });
}

class HomeFeedService {
  const HomeFeedService();

  List<HomeDataChunk> buildChunks({
    required HomeFeedPayload payload,
    required bool debugShowEmptyStates,
    required VoidCallback onS1EmptyActionTap,
    required VoidCallback onAddFriendTap,
    // 로케일 문자열 주입
    required String emptyS1Line1,
    required String emptyS1Line2Bold,
    required List<HomeTextChunk> friendRecommendHeader,
  }) {
    final showEmptyPreview = debugShowEmptyStates; // 디버그에서만 빈 추천 UI 노출

    return <HomeDataChunk>[
      // Section1: 주간/기간 카드 섹션
      HomeSection1Chunk(
        headerLine1: payload.section1HeaderLine1,
        headerLine2: payload.section1HeaderLine2,
        cards: payload.section1Cards,
        // 빈 상태면 헤더에 카피를 넣고, > 버튼으로 액션 유도 (요구사항)
        emptyMessage: emptyS1Line1,
        emptyActionText: emptyS1Line2Bold,
        onEmptyActionTap: onS1EmptyActionTap,
      ),

      // Section2: 군집/캐러셀 (빈이면 숨김)
      HomeSection2Chunk(slides: payload.section2Slides),

      // 친구 글: Section1 재활용 (빈이면 숨김)
      HomeSection1Chunk(
        headerLine1: null,
        headerLine2: payload.friendsPostsHeaderLine2,
        cards: payload.friendsPostsCards,
        hideWhenEmpty: true,
      ),

      // 친구 추천: Section3 (원형) (실제는 빈이면 숨김, 디버그 빈 토글에서는 노출)
      // 헤더는 항상 기본 시스템 헤더 사용 (로케일 적용)
      HomeSection3Chunk(
        header: friendRecommendHeader,
        friends: payload.recommendedFriends,
        hideWhenEmpty: showEmptyPreview ? false : true,
        onAddFriendTap: onAddFriendTap,
      ),
    ];
  }
}
