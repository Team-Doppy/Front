import 'dart:ui';

import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/recap/recap_card.dart';
import 'package:doppy/pages/screens/date_picker_screen.dart'
    show DatePickerScreen;
import 'package:doppy/pages/screens/my_friends_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/providers/weekly_contribution_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/models/weekly_contribution_greeting.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/models/home_recommendation_model.dart';
import 'package:doppy/providers/home_recommendation_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';
import 'package:doppy/image/utils/read_image_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doppy/utils/route_observer.dart';

// =============================================================================
// ✅ 섹션 간격 상수
// =============================================================================

/// 홈 화면 섹션 간격 상수
class HomeSectionSpacing {
  HomeSectionSpacing._();

  // 주요 섹션 간격
  static const double sectionXLarge =
      80.0; // 매우 큰 섹션 간격 (FillSection과 ListSection 사이)
  static const double sectionLarge = 70.0; // 큰 섹션 간격 (같은 타입 섹션들 사이)
  static const double sectionMedium = 24.0; // 중간 섹션 간격
  static const double sectionSmall = 16.0; // 작은 섹션 간격
  static const double sectionXSmall = 12.0; // 매우 작은 섹션 간격
  static const double sectionXXSmall = 10.0; // 가장 작은 섹션 간격
  static const double sectionTiny = 4.0; // 미세 간격

  // 특수 간격
  static const double greetingBottom = 24.0; // 환영 인사 아래 간격
  static const double gridBottom =
      40.0; // 그리드 아래 간격 (FillSection과 ListSection 사이와 동일)
  static const double gridTop =
      24.0; // 그리드 아래 간격 (FillSection과 ListSection 사이와 동일)
  static const double bannerBottom = 24.0; // 배너 아래 간격
  static const double postCardHeaderBottom = 12.0; // 포스트 카드 헤더 아래 간격
  static const double postCardTitleBottom = 4.0; // 포스트 카드 제목 아래 간격
  static const double friendItemSpacing = 18.0; // 친구 아이템 간격 (가로)
  static const double friendItemBottom = 10.0; // 친구 아이템 아래 간격
}

// =============================================================================
// ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시)
// =============================================================================

/// ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시)
/// - createdAt 기준으로 7일 이내일 때만 표시
/// - 남은 일수에 따라 텍스트 변경
Widget? _buildBannerCard(BuildContext context, DateTime? createdAt) {
  // createdAt이 없으면 표시하지 않음
  if (createdAt == null) {
    debugPrint('[HomeWidgets] _buildBannerCard: createdAt is null');
    return null;
  }

  final now = DateTime.now();
  final createdAtLocal = createdAt.toLocal();
  final daysSinceSignup = now.difference(createdAtLocal).inDays;
  final daysRemaining = 7 - daysSinceSignup;

  // ✅ 디버깅 로그 추가
  debugPrint('[HomeWidgets] _buildBannerCard:');
  debugPrint(
    '  createdAt (original): ${createdAt.toIso8601String()} (UTC: ${createdAt.isUtc})',
  );
  debugPrint('  createdAt (local): ${createdAtLocal.toIso8601String()}');
  debugPrint('  now: ${now.toIso8601String()}');
  debugPrint('  daysSinceSignup: $daysSinceSignup');
  debugPrint('  daysRemaining: $daysRemaining');
  debugPrint(
    '  difference (total hours): ${now.difference(createdAtLocal).inHours}',
  );
  debugPrint(
    '  difference (total days as double): ${now.difference(createdAtLocal).inDays + (now.difference(createdAtLocal).inHours % 24) / 24.0}',
  );

  // 7일이 지났거나, 0일 이하로 남았으면 표시하지 않음
  if (daysRemaining <= 0) {
    debugPrint(
      '[HomeWidgets] _buildBannerCard: daysRemaining <= 0, returning null',
    );
    return null;
  }

  debugPrint(
    '[HomeWidgets] _buildBannerCard: showing banner (daysRemaining: $daysRemaining)',
  );

  final onSurface = Theme.of(context).colorScheme.onSurface;
  final background = Theme.of(context).colorScheme.background;
  final surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
  bool isDark = Theme.of(context).brightness == Brightness.dark;

  // 텍스트 결정
  String firstLine;
  String secondLine;

  if (daysRemaining == 7) {
    // 7일 남았을 때
    firstLine = '오늘부터 일주일 동안';
    secondLine = '지난 기록도 작성할 수 있어요';
  } else if (daysRemaining == 1) {
    // 1일 남았을 때
    firstLine = '내일까지만';
    secondLine = '지난 기록도 작성할 수 있어요';
  } else {
    // 2-6일 남았을 때
    firstLine = '앞으로 $daysRemaining일 동안만';
    secondLine = '과거 날짜에 기록이 가능해요 ';
  }

  return GestureDetector(
    onTap: () {
      // ✅ DatePickerScreen으로 push할 때도 createdAt 검증
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DatePickerScreen(createdAt: createdAt),
        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: HomeSectionSpacing.sectionLarge),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 80),
      decoration: BoxDecoration(color: isDark ? background : surfaceVariant),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstLine,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: onSurface.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  secondLine,
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: onSurface.withOpacity(0.95),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 20,
            color: onSurface.withOpacity(0.5),
          ),
        ],
      ),
    ),
  );
}

// =============================================================================
// ✅ 헬퍼 함수: 볼드 서브스트링 지원 텍스트
// =============================================================================

/// 제목과 볼드 서브스트링을 받아서 RichText로 반환
/// 볼드가 시작하는 부분에서 줄바꿈
Widget buildTitleWithBoldSubstrings({
  required BuildContext context,
  required String title,
  required List<String> boldSubstrings,
  required TextStyle baseStyle,
  required TextStyle boldStyle,
}) {
  // title을 줄바꿈으로 분리
  var lines = title.split('\n');
  lines = lines.map((line) => line.replaceAll('*', '')).toList();

  if (boldSubstrings.isEmpty) {
    // 볼드가 없으면 첫 2줄만 표시
    final displayLines = lines.take(2).join('\n');
    return Text(
      displayLines,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.left,
      softWrap: true,
    );
  }

  // 모든 줄에서 첫 번째 볼드 서브스트링 찾기
  String? firstBoldSubstring;
  int? firstBoldIndex;
  int? boldLineIndex; // 볼드가 있는 줄의 인덱스

  for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
    final line = lines[lineIdx];
    for (final boldSubstring in boldSubstrings) {
      final index = line.indexOf(boldSubstring);

      if (index != -1) {
        firstBoldSubstring = boldSubstring;
        firstBoldIndex = index;
        boldLineIndex = lineIdx;
        break;
      }
    }
    if (firstBoldSubstring != null) break;
  }

  // 볼드가 없으면 첫 2줄만 표시
  if (firstBoldSubstring == null ||
      firstBoldIndex == null ||
      boldLineIndex == null) {
    debugPrint(
      '[buildTitleWithBoldSubstrings] ❌ 볼드 서브스트링을 찾지 못함. lines: $lines, boldSubstrings: $boldSubstrings',
    );
    final displayLines = lines.take(2).join('\n');
    return Text(
      displayLines,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.left,
      softWrap: true,
    );
  }

  // 볼드가 있는 줄 처리
  final boldLine = lines[boldLineIndex];
  final beforeBold = boldLine.substring(0, firstBoldIndex);
  final fromBold = boldLine.substring(firstBoldIndex);

  // 각 줄을 처리하여 볼드 적용
  final spans = <TextSpan>[];

  // 볼드가 있는 줄 이전의 모든 줄 추가
  for (int i = 0; i < boldLineIndex; i++) {
    if (i > 0) spans.add(const TextSpan(text: '\n'));
    spans.add(TextSpan(text: lines[i], style: baseStyle));
  }

  // 볼드가 있는 줄: 볼드 이전 부분
  if (boldLineIndex > 0) spans.add(const TextSpan(text: '\n'));
  if (beforeBold.isNotEmpty) {
    spans.add(TextSpan(text: beforeBold, style: baseStyle));
  }

  // 볼드 부분부터 처리
  final secondLineSpans = <TextSpan>[];
  int lastIndex = 0;
  String remainingText = fromBold;

  // 모든 볼드 서브스트링 처리
  for (final boldSubstring in boldSubstrings) {
    final index = remainingText.indexOf(boldSubstring, lastIndex);
    if (index == -1) continue;

    // 볼드 서브스트링 이전 텍스트
    if (index > lastIndex) {
      secondLineSpans.add(
        TextSpan(
          text: remainingText.substring(lastIndex, index),
          style: baseStyle,
        ),
      );
    }

    // 볼드 서브스트링
    secondLineSpans.add(TextSpan(text: boldSubstring, style: boldStyle));
    lastIndex = index + boldSubstring.length;
  }

  // 마지막 남은 텍스트
  if (lastIndex < remainingText.length) {
    secondLineSpans.add(
      TextSpan(text: remainingText.substring(lastIndex), style: baseStyle),
    );
  }

  spans.addAll(secondLineSpans);

  return DefaultTextStyle(
    style: baseStyle,
    maxLines: 2,
    overflow: TextOverflow.clip,
    textAlign: TextAlign.left,
    softWrap: true,
    child: RichText(text: TextSpan(children: spans), textAlign: TextAlign.left),
  );
}

// =============================================================================
// ✅ 락용 홈 위젯
// =============================================================================

/// 락용 홈 메인 위젯 (스트릭, 그리드, 진행 바, 미디어 카드 포함)
class LockedHomeWidget extends StatelessWidget {
  final int year;
  final DateTime? signupAt;
  final DateTime asOf;
  final int? selectedWeek;
  final Function(int, int)? onWeekSelected;
  final Function(int, int, Offset?, Offset?)? onWeekLongPress;
  final PostPublishContext? postPublishContext;
  final GlobalKey? gridKey; // ✅ 가이드용 GlobalKey
  final GlobalKey? postCardKey; // ✅ 가이드용 GlobalKey

  const LockedHomeWidget({
    super.key,
    required this.year,
    this.signupAt,
    required this.asOf,
    this.selectedWeek,
    this.onWeekSelected,
    this.onWeekLongPress,
    this.postPublishContext,
    this.gridKey,
    this.postCardKey,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      WeeklyContributionProvider,
      MyProfileFeedProvider,
      FriendProvider,
      UserProvider
    >(
      builder: (
        context,
        contributionProvider,
        feedProvider,
        friendProvider,
        userProvider,
        _,
      ) {
        final greeting = contributionProvider.getGreeting(year);
        final contributions = contributionProvider.getContributions(year);
        final totalPostCount = contributionProvider.totalPostCount;
        final posts = feedProvider.posts.take(3).toList();
        // ✅ 그리드 쉬머는 "초기 로드(데이터 없음)"일 때만 표시 (백그라운드 재동기화는 UI 유지)
        final bool isGridInitialLoading =
            contributionProvider.isLoading(year) &&
            ((contributions == null) || contributions.isEmpty);

        // ✅ 친구 포스트는 FriendProvider에서 가져오기
        final friendPosts = friendProvider.friendPosts;
        final hasFriendPosts = friendPosts.isNotEmpty;

        // 섹션 리스트 구성
        final sections = <Widget>[];

        // 미디어 카드들 (포스트가 0개여도 플레이스홀더 3개 표시)
        sections.add(
          LockedPostCardSection(
            key: postCardKey, // ✅ 가이드용 GlobalKey
            posts: posts.toList(),
            title: '내 첫 리캡',
            subtitle: '해제까지 ${totalPostCount}/3',
          ),
        );

        // ✅ 친구 포스트가 있으면 친구 포스트 섹션 추가
        if (hasFriendPosts) {
          sections.add(
            UnlockedPostCardSection(
              posts: friendPosts.take(5).toList(),
              title: '요새 내 친구들',
              titleBoldSubstrings: ['요새'],
              showAuthorInfo: true,
            ),
          );
        }

        // ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시)
        // ProfileInfoBundle의 createdAt 우선, 없으면 signupAt 사용
        final createdAt = userProvider.createdAt ?? signupAt;
        debugPrint('[HomeWidgets] Banner card check:');
        debugPrint(
          '  userProvider.createdAt: ${userProvider.createdAt?.toIso8601String()}',
        );
        debugPrint('  signupAt: ${signupAt?.toIso8601String()}');
        debugPrint('  final createdAt: ${createdAt?.toIso8601String()}');
        final bannerCard = _buildBannerCard(context, createdAt);
        if (bannerCard != null) {
          sections.add(bannerCard);
        }

        // ✅ 친구 추천 섹션 항상 추가 (친구 포스트와 상관없이)
        sections.add(
          FriendRecommendationSection(
            onFriendTap: (String username) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => UserProfileScreen(
                        otherUser: User(username: username),
                      ),
                ),
              );
            },
            onAddFriendTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (context) => UserSearchBottomSheet(),
              );
            },
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: HomeSectionSpacing.gridTop),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: GreetingSection(
                greeting: greeting,
                postPublishContext: postPublishContext,
                year: year,
                isLoading: contributionProvider.isLoading(year),
              ),
            ),

            // 활동 그리드
            Container(
              key: gridKey, // ✅ 가이드용 GlobalKey
              child: WeeklyContributionGrid(
                year: year,
                signupAt: signupAt,
                asOf: asOf,
                selectedWeek: selectedWeek,
                onWeekSelected: onWeekSelected,
                // ✅ null이면 하드코딩 데이터로 바뀌면서 색/레이아웃이 흔들릴 수 있어 빈 리스트로 고정
                contributions:
                    contributions ?? const <WeeklyContributionData>[],
                isLoading: isGridInitialLoading,
                onLongPress: onWeekLongPress,
              ),
            ),
            SizedBox(height: HomeSectionSpacing.sectionLarge),

            // ✅ 네트워크 오프라인 상태 표시 (그리드 밑에)
            StreamBuilder<bool>(
              stream: NetworkManager.onConnectivityChanged,
              initialData: NetworkManager.isOnline,
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? NetworkManager.isOnline;
                if (!isOnline) {
                  return _buildOfflineBanner(context);
                }
                return const SizedBox.shrink();
              },
            ),

            // 섹션들 표시
            ...sections,
          ],
        );
      },
    );
  }
}

/// 언락용 홈 메인 위젯 (greeting, 그리드 포함)
class UnlockedHomeWidget extends StatefulWidget {
  final int year;
  final DateTime? signupAt;
  final DateTime asOf;
  final int? selectedWeek;
  final Function(int, int)? onWeekSelected;
  final Function(int, int, Offset?, Offset?)? onWeekLongPress;
  final List<WeeklyContributionData>? contributions;
  final bool isLoading;
  final WeeklyContributionGreeting? greeting;
  final PostPublishContext? postPublishContext;

  const UnlockedHomeWidget({
    super.key,
    required this.year,
    this.signupAt,
    required this.asOf,
    this.selectedWeek,
    this.onWeekSelected,
    this.onWeekLongPress,
    this.contributions,
    this.isLoading = false,
    this.greeting,
    this.postPublishContext,
  });

  /// ✅ RecapCard을 표시할지 여부 확인
  /// 리캡을 본 후 3일이 지나지 않았으면 false, 3일이 지났거나 안봤으면 true
  static Future<bool> _shouldShowRecapCard() async {
    try {
      final accountKey = await AuthService().getAccountKeyFromToken();
      if (accountKey == null || accountKey.isEmpty) return true; // 기본값: 표시

      final prefs = await SharedPreferences.getInstance();
      final key = 'insight_content_viewed_$accountKey';
      final viewedTimestampStr = prefs.getString(key);

      // 타임스탬프가 없으면 표시
      if (viewedTimestampStr == null || viewedTimestampStr.isEmpty) {
        return true;
      }

      // 타임스탬프 파싱
      final viewedTimestamp = DateTime.tryParse(viewedTimestampStr);
      if (viewedTimestamp == null) {
        // 파싱 실패 시 기존 bool 값 확인 (하위 호환성)
        final hasViewed = prefs.getBool(key) ?? false;
        return !hasViewed;
      }

      // 현재 시간과 비교 (3일 = 72시간)
      final now = DateTime.now();
      final daysSinceViewed = now.difference(viewedTimestamp).inDays;

      // 3일이 지났으면 다시 표시, 안 지났으면 숨김
      return daysSinceViewed >= 3;
    } catch (e) {
      debugPrint('[UnlockedHomeWidget] RecapCard 표시 여부 확인 실패: $e');
      return true; // 에러 시 기본값: 표시
    }
  }

  @override
  State<UnlockedHomeWidget> createState() => _UnlockedHomeWidgetState();
}

class _UnlockedHomeWidgetState extends State<UnlockedHomeWidget>
    with RouteAware {
  /// ⚠️ 매 build마다 새 Future를 만들면 FutureBuilder가 리셋되며 subtree가 교체(dispose)될 수 있음
  /// - 평소에는 Future identity를 고정해서 영상/이미지 위젯이 유지되도록 함
  /// - 다른 화면 갔다가 "돌아왔을 때(didPopNext)"만 강제로 새로고침
  Future<bool>? _shouldShowMyImpressFuture;
  bool _lastHasAnyHomeSection = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // 다른 화면에서 돌아온 시점: SharedPreferences 플래그/데이터가 바뀌었을 수 있으니 1회 리프레시
    debugPrint(
      '[UnlockedHomeWidget] didPopNext: refresh (avoid subtree dispose churn)',
    );
    setState(() {
      _shouldShowMyImpressFuture = null;
    });
  }

  Future<bool> _resolveShouldShowFuture({required bool hasAnyHomeSection}) {
    // 홈 섹션이 아무것도 없으면 무조건 노출
    if (!hasAnyHomeSection) {
      _lastHasAnyHomeSection = false;
      _shouldShowMyImpressFuture = Future.value(true);
      return _shouldShowMyImpressFuture!;
    }

    // 섹션이 생긴 순간(또는 리프레시 트리거)에는 Future를 새로 만들어 1번만 읽음
    if (_shouldShowMyImpressFuture == null || !_lastHasAnyHomeSection) {
      _shouldShowMyImpressFuture = UnlockedHomeWidget._shouldShowRecapCard();
    }
    _lastHasAnyHomeSection = true;
    return _shouldShowMyImpressFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<HomeRecommendationProvider, FriendProvider, UserProvider>(
      builder: (
        context,
        recommendationProvider,
        friendProvider,
        userProvider,
        _,
      ) {
        // 추천 데이터 가져오기
        final emotionBased = recommendationProvider.getRecommendationsByType(
          RecCardType.EVENT_EMOTION,
        );
        final socialBased = recommendationProvider.getRecommendationsByType(
          RecCardType.SOCIAL,
        );
        final timeBased = recommendationProvider.getRecommendationsByType(
          RecCardType.TIME_BASED,
        );

        // ✅ 친구 포스트는 FriendProvider에서 가져오기 (friend-bundle에서 이미 로드됨)
        final friendPosts = friendProvider.friendPosts;
        final hasFriendPosts = friendPosts.isNotEmpty;

        // 🎯 섹션 배치 규칙:
        // 1. FillSection이 처음에 와야 함
        // 2. FillSection 다음에는 반드시 ListSection이 와야 함
        // 3. FillSection은 연속으로 오면 안 됨 (중간에 ListSection이 하나 이상 껴야 함)
        // 4. 친구 추천은 최하단 1,2섹션 정도에서만 위치 조정
        // 5. RecapCard도 FillSection으로 취급

        // 1. FillSection 리스트 구성 (PostFillSection + RecapCard)
        final fillSections = <Widget>[];

        // EVENT_EMOTION (PostFillSection) 추가
        for (final rec in emotionBased) {
          if (rec.posts.isNotEmpty) {
            // ✅ 고유한 key 부여: title과 firstPostId 조합으로 중복 방지
            final firstPostId = rec.posts.first['id']?.toString() ?? '';
            final titleHash = rec.title.hashCode.toString();
            fillSections.add(
              PostFillSection(
                key: ValueKey('fill_emotion_${titleHash}_$firstPostId'),
                posts: rec.posts,
                title: rec.title,
                titleBoldSubstrings: rec.titleBoldSubstrings,
              ),
            );
          }
        }

        // 2. SOCIAL + TIME_BASED (UnlockedPostCardSection) - ListSection
        final listSections = <Widget>[];
        for (final rec in socialBased) {
          if (rec.posts.isNotEmpty) {
            // ✅ 고유한 key 부여: title과 firstPostId 조합으로 중복 방지
            final firstPostId = rec.posts.first['id']?.toString() ?? '';
            final titleHash = rec.title.hashCode.toString();
            listSections.add(
              UnlockedPostCardSection(
                key: ValueKey('list_social_${titleHash}_$firstPostId'),
                posts: rec.posts,
                title: rec.title,
                titleBoldSubstrings: rec.titleBoldSubstrings,
              ),
            );
          }
        }
        for (final rec in timeBased) {
          if (rec.posts.isNotEmpty) {
            // ✅ 고유한 key 부여: title과 firstPostId 조합으로 중복 방지
            final firstPostId = rec.posts.first['id']?.toString() ?? '';
            final titleHash = rec.title.hashCode.toString();
            listSections.add(
              UnlockedPostCardSection(
                key: ValueKey('list_time_${titleHash}_$firstPostId'),
                posts: rec.posts,
                title: rec.title,
                titleBoldSubstrings: rec.titleBoldSubstrings,
              ),
            );
          }
        }

        // ✅ RecapCard 표시 로직
        // 1. 홈 섹션에 아무것도 없으면 무조건 표시
        // 2. 하나라도 있으면: 리캡을 봤으면 숨기기, 안봤으면 최상단에 노출
        final hasAnyHomeSection =
            emotionBased.any((rec) => rec.posts.isNotEmpty) ||
            socialBased.any((rec) => rec.posts.isNotEmpty) ||
            timeBased.any((rec) => rec.posts.isNotEmpty);

        // ✅ 비동기 처리: 리캡을 봤는지 확인
        return FutureBuilder<bool>(
          // ✅ Future identity를 안정화(=subtree dispose 방지). 복귀 시(didPopNext)만 null로 만들어 새로고침.
          future: _resolveShouldShowFuture(
            hasAnyHomeSection: hasAnyHomeSection,
          ),
          builder: (context, snapshot) {
            final shouldShow = snapshot.data ?? true; // 기본값: 표시

            // fillSections를 다시 구성 (비동기 결과에 따라)
            final finalFillSections = <Widget>[];
            for (final rec in emotionBased) {
              if (rec.posts.isNotEmpty) {
                // ✅ 고유한 key 부여: title과 firstPostId 조합으로 중복 방지
                final firstPostId = rec.posts.first['id']?.toString() ?? '';
                final titleHash = rec.title.hashCode.toString();
                finalFillSections.add(
                  PostFillSection(
                    key: ValueKey('fill_emotion_${titleHash}_$firstPostId'),
                    posts: rec.posts,
                    title: rec.title,
                    titleBoldSubstrings: rec.titleBoldSubstrings,
                  ),
                );
              }
            }

            Widget? myImpressWidget;
            if (!hasAnyHomeSection) {
              // ✅ 케이스 1: 홈 섹션에 아무것도 없으면 무조건 표시
              myImpressWidget = const RecapCard();
              finalFillSections.add(myImpressWidget);
            } else if (shouldShow) {
              // ✅ 케이스 2: 하나라도 있고, 아직 안봤으면 최상단에 노출
              myImpressWidget = const RecapCard();
              finalFillSections.insert(0, myImpressWidget);
            }
            // 봤으면 숨기기 (myImpressWidget = null)

            // 섹션 배치 로직 (기존과 동일)
            final finalSections = <Widget>[];
            final finalListSections = List<Widget>.from(listSections);

            // 🎯 규칙에 따라 섹션 배치: FillSection → ListSection → FillSection → ListSection ...
            // 첫 번째는 반드시 FillSection
            if (finalFillSections.isNotEmpty) {
              finalSections.add(finalFillSections.removeAt(0));
            }

            // 나머지 섹션들을 교차 배치 (FillSection 다음에는 반드시 ListSection)
            while (finalFillSections.isNotEmpty ||
                finalListSections.isNotEmpty) {
              // FillSection이 연속으로 오지 않도록, ListSection을 우선 배치
              if (finalListSections.isNotEmpty) {
                finalSections.add(finalListSections.removeAt(0));
              } else if (finalFillSections.isNotEmpty) {
                // ListSection이 없을 때만 FillSection 추가
                finalSections.add(finalFillSections.removeAt(0));
              }

              // 그 다음 FillSection 추가 (있으면)
              if (finalFillSections.isNotEmpty) {
                finalSections.add(finalFillSections.removeAt(0));
              }
            }

            // 3. 친구 포스트가 있으면 항상 맨 뒤에 추가
            if (hasFriendPosts) {
              final friendSection = UnlockedPostCardSection(
                posts: friendPosts.take(5).toList(),
                title: '요새 내 친구들',
                titleBoldSubstrings: ['요새'],
                showAuthorInfo: true,
              );

              // ✅ 항상 맨 뒤에 추가
              finalSections.add(friendSection);
            }

            // 4. 친구 포스트가 없으면 친구 추천 섹션을 항상 맨 뒤에 추가
            if (!hasFriendPosts) {
              final friendRecommendationSection = FriendRecommendationSection(
                onFriendTap: (String username) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => UserProfileScreen(
                            otherUser: User(username: username),
                          ),
                    ),
                  );
                },
                onAddFriendTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => UserSearchBottomSheet(),
                  );
                },
              );

              // ✅ 항상 맨 뒤에 추가 (다른 섹션이 없어도 추가 가능)
              finalSections.add(friendRecommendationSection);
            }

            // ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시) - 언락 모드에서도 표시
            // ProfileInfoBundle의 createdAt 우선, 없으면 signupAt 사용
            final createdAt = userProvider.createdAt ?? widget.signupAt;
            debugPrint('[HomeWidgets] UnlockedHomeWidget Banner card check:');
            debugPrint(
              '  userProvider.createdAt: ${userProvider.createdAt?.toIso8601String()}',
            );
            debugPrint('  signupAt: ${widget.signupAt?.toIso8601String()}');
            debugPrint('  final createdAt: ${createdAt?.toIso8601String()}');
            final bannerCard = _buildBannerCard(context, createdAt);
            if (bannerCard != null) {
              // ✅ 항상 맨 뒤에 추가
              finalSections.add(bannerCard);
            }

            return Column(
              children: [
                SizedBox(height: HomeSectionSpacing.gridTop),
                // ✅ 환영 인사 (WeeklyContributionProvider에서 받은 데이터)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: GreetingSection(
                    greeting: widget.greeting,
                    postPublishContext: widget.postPublishContext,
                    year: widget.year,
                    isLoading: widget.isLoading,
                  ),
                ),

                // ✅ 잔디 심기 UI
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: WeeklyContributionGrid(
                    year: widget.year,
                    signupAt: widget.signupAt,
                    asOf: widget.asOf,
                    selectedWeek: widget.selectedWeek,
                    onWeekSelected: widget.onWeekSelected,
                    // ✅ null이면 하드코딩 데이터로 바뀌면서 색/레이아웃이 흔들릴 수 있어 빈 리스트로 고정
                    contributions:
                        widget.contributions ??
                        const <WeeklyContributionData>[],
                    // ✅ 그리드 쉬머는 "초기 로드(데이터 없음)"일 때만 표시
                    isLoading:
                        widget.isLoading &&
                        ((widget.contributions == null) ||
                            widget.contributions!.isEmpty),
                    onLongPress: widget.onWeekLongPress,
                  ),
                ),
                SizedBox(height: HomeSectionSpacing.gridBottom),

                // ✅ 네트워크 오프라인 상태 표시 (그리드 밑에)
                StreamBuilder<bool>(
                  stream: NetworkManager.onConnectivityChanged,
                  initialData: NetworkManager.isOnline,
                  builder: (context, snapshot) {
                    final isOnline = snapshot.data ?? NetworkManager.isOnline;
                    if (!isOnline) {
                      return _buildOfflineBanner(context);
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // ✅ 추천 섹션들 (RecapCard 포함, FillSection 규칙 적용)
                ...finalSections,
              ],
            );
          },
        );
      },
    );
  }
}

/// 친구 추천 섹션 (락과 관련없이 항상 표시)
class FriendRecommendationSection extends StatelessWidget {
  final Function(String) onFriendTap;
  final VoidCallback? onAddFriendTap;

  const FriendRecommendationSection({
    super.key,
    required this.onFriendTap,
    this.onAddFriendTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<FriendProvider>(
      builder: (context, friendProvider, _) {
        final recommendations = friendProvider.friendRecommendations;

        if (recommendations.isEmpty) {
          return const SizedBox.shrink();
        }

        final onSurface = Theme.of(context).colorScheme.onSurface;

        final allItems = <Widget>[];
        for (int i = 0; i < recommendations.length; i++) {
          final user = recommendations[i];
          final borderColor = onSurface.withOpacity(0.15);
          final borderWidth = 2.0;

          final avatarWidget = Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: ClipOval(
              child: CommonProfileAvatar(
                imageUrl: user.profileImageUrl,
                username: user.username,
                size: 150,
                borderWidth: 0, // 외부 컨테이너에서 border 처리
              ),
            ),
          );

          final friendItem = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => onFriendTap(user.username),
                borderRadius: BorderRadius.circular(999),
                child: avatarWidget,
              ),
              SizedBox(height: HomeSectionSpacing.sectionXXSmall),
              SizedBox(
                width: 160,
                child: Text(
                  user.alias ?? user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: onSurface.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          );

          allItems.add(friendItem);
          if (i < recommendations.length - 1 || onAddFriendTap != null) {
            allItems.add(SizedBox(width: HomeSectionSpacing.friendItemSpacing));
          }
        }

        if (onAddFriendTap != null) {
          final addButton = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: onSurface.withOpacity(0.2),
                    width: 2.0,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onAddFriendTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Center(
                      child: Icon(
                        Icons.add,
                        size: 48,
                        color: onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: HomeSectionSpacing.sectionXXSmall),
              SizedBox(
                width: 150,
                child: Text(
                  '친구 추가',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          );
          allItems.add(addButton);
        }

        return Container(
          margin: const EdgeInsets.only(
            bottom: HomeSectionSpacing.sectionLarge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '아는 친구인가요?',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              SizedBox(height: HomeSectionSpacing.sectionMedium),
              SizedBox(
                height: 190,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  children: allItems,
                ),
              ),
              // ✅ 하단 간격: 섹션 자체에서 관리
              SizedBox(height: HomeSectionSpacing.sectionMedium),
            ],
          ),
        );
      },
    );
  }
}

class GreetingSection extends StatefulWidget {
  final WeeklyContributionGreeting? greeting;
  final PostPublishContext? postPublishContext;
  final int? year;
  final bool isLoading; // 🎯 스트릭 로딩 중일 때 그리팅 메시지 숨김

  const GreetingSection({
    super.key,
    this.greeting,
    this.postPublishContext,
    this.year,
    this.isLoading = false,
  });

  @override
  State<GreetingSection> createState() => _GreetingSectionState();
}

class _GreetingSectionState extends State<GreetingSection> {
  String? _lastMessage; // 🎯 이전 메시지 저장
  late final Future<bool>
  _onboardingFirstVisitFuture; // ✅ build마다 Future 재생성 방지
  Future<String?>? _messageFuture; // ✅ build마다 Future 재생성 방지
  int? _messageKeyHash;

  @override
  void initState() {
    super.initState();
    _onboardingFirstVisitFuture = _checkOnboardingFirstHomeVisit();
  }

  @override
  void didUpdateWidget(covariant GreetingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 로딩이 끝나고 입력(연도/그리팅/컨텍스트)이 바뀌면 메시지 Future를 새로 만든다.
    // 로딩 중에는 이전 메시지/이전 Future를 유지해서 깜빡임을 막는다.
    if (!widget.isLoading &&
        (oldWidget.greeting != widget.greeting ||
            oldWidget.postPublishContext != widget.postPublishContext ||
            oldWidget.year != widget.year)) {
      _messageFuture = null;
      _messageKeyHash = null;
    }
  }

  /// ✅ 메시지 위젯 빌드 헬퍼 메서드
  Widget _buildMessageWidget(BuildContext context, String? message) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // 메시지가 없으면 기본 폴백 메시지 표시
    if (message == null || message.isEmpty) {
      return Text(
        '이번 주도 기록해봐요\n한 번만 채워도 돼요',
        style: LocaleTypography.style(
          context: context,
          color: onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w300,
          letterSpacing: -1,
          height: 1.4,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
        softWrap: true,
      );
    }

    // 메시지를 줄바꿈으로 분리 (첫 줄: tier 스타일, 둘째 줄: mode 스타일)
    final lines = message.split('\n');
    final firstLine = lines.isNotEmpty ? lines[0] : '';
    final secondLine = lines.length > 1 ? lines[1] : '';

    // 🎯 첫 줄에서 연도 부분 찾기 (예: "2025년은")
    final yearPattern = RegExp(r'(\d{4}년은)');
    final firstLineSpans = <TextSpan>[];

    if (firstLine.isNotEmpty) {
      final baseStyle = LocaleTypography.style(
        context: context,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 26,
        fontWeight: FontWeight.w300,
        letterSpacing: -1,
        height: 1.4,
      );

      final boldStyle = LocaleTypography.style(
        context: context,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        height: 1.4,
      );

      final matches = yearPattern.allMatches(firstLine);
      if (matches.isEmpty) {
        // 연도 패턴이 없으면 그대로 표시
        firstLineSpans.add(TextSpan(text: firstLine, style: baseStyle));
      } else {
        // 연도 패턴이 있으면 볼드 처리
        int lastIndex = 0;
        for (final match in matches) {
          // 연도 이전 텍스트
          if (match.start > lastIndex) {
            firstLineSpans.add(
              TextSpan(
                text: firstLine.substring(lastIndex, match.start),
                style: baseStyle,
              ),
            );
          }
          // 연도 부분 (볼드)
          firstLineSpans.add(TextSpan(text: match.group(0), style: boldStyle));
          lastIndex = match.end;
        }
        // 연도 이후 텍스트
        if (lastIndex < firstLine.length) {
          firstLineSpans.add(
            TextSpan(text: firstLine.substring(lastIndex), style: baseStyle),
          );
        }
      }
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
      softWrap: true, // 🎯 줄바꿈 활성화
      text: TextSpan(
        children: [
          ...firstLineSpans,
          if (secondLine.isNotEmpty) ...[
            if (firstLineSpans.isNotEmpty) const TextSpan(text: '\n'),
            TextSpan(
              text: secondLine,
              style: LocaleTypography.style(
                context: context,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✅ 온보딩 완료 후 첫 홈 진입인지 확인하고 플래그 제거
  Future<bool> _checkOnboardingFirstHomeVisit() async {
    try {
      final authService = AuthService();
      final accountKey = await authService.getAccountKeyFromToken();
      if (accountKey == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final key = 'onboarding_first_home_visit_$accountKey';
      final isFirstVisit = prefs.getBool(key) ?? false;

      // ✅ 플래그가 있으면 제거 (한 번만 표시)
      if (isFirstVisit) {
        await prefs.remove(key);
      }

      return isFirstVisit;
    } catch (e) {
      debugPrint('[GreetingSection] 온보딩 첫 홈 진입 체크 실패: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 높이 고정: 메시지 전환/로딩 중 레이아웃 요동 방지
    return SizedBox(
      height: 70.0,
      child: FutureBuilder<bool>(
        // ✅ Future 캐싱(한 번만 체크 + 한 번만 플래그 제거)
        future: _onboardingFirstVisitFuture,
        builder: (context, firstVisitSnapshot) {
          final isOnboardingFirstVisit = firstVisitSnapshot.data ?? false;

          // ✅ 온보딩 완료 후 첫 홈 진입이면 특별한 메시지 표시
          // - 성공: onboarding_first_post_success
          // - 실패: onboarding_first_post_failed (향후 사용 가능)
          if (isOnboardingFirstVisit) {
            // ✅ _buildMessageWidget()를 사용하여 일반 그리팅과 동일한 스타일 적용
            // (1줄째 w300, 2줄째 w800 볼드)
            return Align(
              key: const ValueKey('onboarding_first_visit'),
              alignment: Alignment.centerLeft,
              child: _buildMessageWidget(
                context,
                context.tr('onboarding_first_post_success'),
              ),
            );
          }

          // 메시지 가져오기 (FutureBuilder로 비동기 처리)
          final keyHash = Object.hash(
            widget.greeting,
            widget.postPublishContext,
            widget.year,
            Localizations.localeOf(context),
          );
          if (!widget.isLoading &&
              (_messageFuture == null || _messageKeyHash != keyHash)) {
            _messageKeyHash = keyHash;
            _messageFuture = WeeklyContributionGreeting.getMessage(
              context: context,
              greeting: widget.greeting,
              postPublishContext: widget.postPublishContext,
              year: widget.year,
            );
          }
          return FutureBuilder<String?>(
            // ✅ 로딩 중엔 Future를 새로 만들지 않고 이전 것을 유지
            future: _messageFuture,
            builder: (context, snapshot) {
              // 🎯 로딩 중이 아닐 때만 메시지 업데이트
              // 로딩 중일 때는 이전 메시지 유지
              if (!widget.isLoading &&
                  snapshot.hasData &&
                  snapshot.data != null) {
                _lastMessage = snapshot.data;
              }

              final displayMessage = _lastMessage ?? snapshot.data;

              // ✅ 단일 AnimatedSwitcher만 사용 (애니메이션 중첩 제거)
              // 메시지 변경만 AnimatedSwitcher로 처리
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child:
                    displayMessage != null
                        ? Align(
                          key: ValueKey(displayMessage),
                          alignment: Alignment.centerLeft,
                          child: _buildMessageWidget(context, displayMessage),
                        )
                        : const SizedBox.shrink(key: ValueKey('empty')),
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================================
// ✅ 일반용 포스트 카드 섹션
// =============================================================================

class UnlockedPostCardSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onPostTap;
  final Function(String postId)? onPostTapWithId;
  final String? title;
  final List<String>? titleBoldSubstrings; // ✅ 볼드 서브스트링 지원
  final bool showAuthorInfo; // ✅ 친구 포스트인 경우 프로필 정보 표시

  const UnlockedPostCardSection({
    super.key,
    required this.posts,
    this.onPostTap,
    this.onPostTapWithId,
    required this.title,
    this.titleBoldSubstrings,
    this.showAuthorInfo = false,
  });

  @override
  State<UnlockedPostCardSection> createState() =>
      _UnlockedPostCardSectionState();
}

class _UnlockedPostCardSectionState extends State<UnlockedPostCardSection>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  int _currentPage = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !mounted) return;
    final position = _scrollController.position;
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth * 0.84 + 6;
    final currentPage = (position.pixels / itemWidth).round().clamp(
      0,
      widget.posts.length - 1,
    );
    if (currentPage != _currentPage) {
      setState(() {
        _currentPage = currentPage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ AutomaticKeepAliveClientMixin을 위해 필수
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (widget.posts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          '포스트가 없습니다.',
          style: LocaleTypography.style(
            context: context,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: onSurface,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildHeader(context, widget.posts.length),
        SizedBox(height: HomeSectionSpacing.sectionXSmall),
        _buildPostList(context),
        // ✅ 하단 간격: 섹션 자체에서 관리
        SizedBox(height: HomeSectionSpacing.sectionLarge),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int itemCount) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ title만 사용, 볼드 서브스트링 지원
                widget.titleBoldSubstrings != null &&
                        widget.titleBoldSubstrings!.isNotEmpty
                    ? buildTitleWithBoldSubstrings(
                      context: context,
                      title: widget.title ?? '',
                      boldSubstrings: widget.titleBoldSubstrings!,
                      baseStyle: LocaleTypography.style(
                        context: context,
                        fontSize: 26,
                        fontWeight: FontWeight.w400,
                        color: onSurface,
                      ),
                      boldStyle: LocaleTypography.style(
                        context: context,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    )
                    : Text(
                      widget.title ?? '',
                      style: LocaleTypography.style(
                        context: context,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      softWrap: true,
                    ),
                SizedBox(height: HomeSectionSpacing.sectionTiny),
              ],
            ),
          ),
          // ✅ 친구 포스트인 경우 페이지 인디케이터 표시 (row의 끝)
          if (widget.showAuthorInfo && widget.posts.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                widget.posts.length.clamp(0, 5),
                (index) => Container(
                  margin: EdgeInsets.only(
                    right: index == widget.posts.length.clamp(0, 5) - 1 ? 0 : 4,
                  ),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _currentPage == index
                            ? onSurface
                            : onSurface.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostList(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemHeight = screenWidth * 0.74 * 1.15;

    return SizedBox(
      height: itemHeight,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        cacheExtent: 2000, // ✅ 캐시 범위 확대
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true, // ✅ 리페인트 경계 명시적 활성화
        itemCount: widget.posts.length.clamp(0, 5),
        itemBuilder: (context, index) {
          final postId = widget.posts[index]['id']?.toString() ?? 'post_$index';
          return RepaintBoundary(
            key: ValueKey('post_card_$postId'), // ✅ 인덱스 대신 postId 사용
            child: Container(
              margin: EdgeInsets.only(
                right: index == widget.posts.length - 1 ? 0 : 6,
              ),
              child: _buildPostCard(context, index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, int index) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: () {
        final postIdRaw = widget.posts[index]['id'];
        final postId = postIdRaw?.toString();
        if (postId != null && postId.isNotEmpty) {
          if (widget.onPostTapWithId != null) {
            widget.onPostTapWithId!.call(postId);
          } else {
            try {
              final postData = PostData.fromServerMeta(widget.posts[index]);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (context) =>
                          PostReaderScreen(exported: postData.toExportedData()),
                ),
              );
            } catch (e) {
              debugPrint('[UnlockedPostCardSection] 포스트 데이터 변환 실패: $e');
              widget.onPostTap?.call();
            }
          }
        } else {
          widget.onPostTap?.call();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: screenWidth * 0.74,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Builder(
                builder: (context) {
                  final thumbnailUrl =
                      widget.posts[index]['thumbnailImageUrl'] as String? ?? '';
                  final url = thumbnailUrl.toLowerCase();
                  final isVideo =
                      url.endsWith('.mp4') ||
                      url.endsWith('.mov') ||
                      url.endsWith('.m4v') ||
                      url.contains('/videos/') ||
                      url.contains('video');

                  if (isVideo && thumbnailUrl.isNotEmpty) {
                    return ThumbnailVideoPlayer(
                      videoUrl: thumbnailUrl,
                      width: screenWidth * 0.74,
                      height: screenWidth * 0.74 * 1.15,
                    );
                  }

                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final isAndroid =
                      defaultTargetPlatform == TargetPlatform.android;
                  final multiplier = isAndroid ? 1.5 : 2.0;
                  final maxDecodeWidthPx = isAndroid ? 2048 : 3072;
                  final memCacheWidth = (screenWidth * 0.74 * dpr * multiplier)
                      .round()
                      .clamp(1, maxDecodeWidthPx);

                  return RepaintBoundary(
                    child: CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      cacheKey: thumbnailUrl, // ✅ 명시적 캐시 키 지정
                      cacheManager:
                          ReadImageCacheManager.instance, // ✅ 읽기 전용 캐시 매니저 사용
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero, // ✅ 페이드 애니메이션 제거
                      fadeOutDuration: Duration.zero, // ✅ 페이드 애니메이션 제거
                      useOldImageOnUrlChange: true, // ✅ URL 변경 시 이전 이미지 유지
                      // ✅ 디코드 폭 제한(안드로이드 프레임 드롭 완화)
                      memCacheWidth: memCacheWidth,
                      placeholder:
                          (context, url) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            child: Icon(
                              Icons.image_not_supported,
                              color: onSurface.withOpacity(0.3),
                            ),
                          ),
                    ),
                  );
                },
              ),
              // ✅ 제목 및 프로필 정보 오버레이 (아래쪽)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 제목
                      Text(
                        widget.posts[index]['title'] as String? ?? '',
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // ✅ 친구 포스트인 경우 프로필 정보 표시 (제목 아래)
                      if (widget.showAuthorInfo) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // 프로필 사진
                            CommonProfileAvatar(
                              imageUrl:
                                  widget.posts[index]['authorProfileImageUrl']
                                      as String? ??
                                  '',
                              username:
                                  widget.posts[index]['author'] as String? ??
                                  '',
                              size: 32,
                              borderWidth: 0,
                            ),
                            const SizedBox(width: 8),
                            // Alias 또는 Username
                            Expanded(
                              child: Text(
                                widget.posts[index]['alias'] as String? ??
                                    widget.posts[index]['author'] as String? ??
                                    '',
                                style: LocaleTypography.style(
                                  context: context,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ✅ 락용 포스트 카드 섹션
// =============================================================================

class LockedPostCardSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onPostTap;
  final Function(String postId)? onPostTapWithId;
  final String? title;
  final String? subtitle;

  const LockedPostCardSection({
    super.key,
    required this.posts,
    this.onPostTap,
    this.onPostTapWithId,
    required this.title,
    required this.subtitle,
  });

  @override
  State<LockedPostCardSection> createState() => _LockedPostCardSectionState();
}

class _LockedPostCardSectionState extends State<LockedPostCardSection>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  int _currentPage = 0;
  static const int _totalSlots = 3;
  static const double sizeFactor = 0.6;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !mounted) return;
    final position = _scrollController.position;
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth =
        screenWidth * sizeFactor + 6; // 0.74는 포스트 카드의 너비 비율 (74% 화면 너비)
    final currentPage = (position.pixels / itemWidth).round().clamp(
      0,
      _totalSlots - 1,
    );
    if (currentPage != _currentPage) {
      setState(() {
        _currentPage = currentPage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ AutomaticKeepAliveClientMixin을 위해 필수

    if (_totalSlots == 0) {
      return Container(padding: const EdgeInsets.symmetric(horizontal: 10));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: HomeSectionSpacing.sectionLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildHeader(context),
          SizedBox(height: HomeSectionSpacing.sectionSmall),
          _buildPostList(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? '',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: HomeSectionSpacing.sectionTiny + 2),
                Text(
                  widget.subtitle ?? '',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    color: onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: HomeSectionSpacing.sectionTiny),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalSlots, (index) {
              return Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      index == _currentPage
                          ? onSurface.withOpacity(0.8)
                          : onSurface.withOpacity(0.3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPostList(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemHeight = screenWidth * sizeFactor * 1.15;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: itemHeight,
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          cacheExtent: 2000, // ✅ 캐시 범위 확대
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: true, // ✅ 리페인트 경계 명시적 활성화
          itemCount: _totalSlots,
          itemBuilder: (context, index) {
            final isPlaceholder = index >= widget.posts.length;
            final isAddIcon = index == widget.posts.length;
            final isLockIcon =
                index > widget.posts.length && widget.posts.length < 2;

            // ✅ 고유한 key 생성 (postId 또는 인덱스 기반)
            final postId =
                isPlaceholder
                    ? 'placeholder_$index'
                    : (widget.posts[index]['id']?.toString() ?? 'post_$index');

            return RepaintBoundary(
              key: ValueKey('locked_post_card_$postId'),
              child: Container(
                margin: EdgeInsets.only(
                  right: index == _totalSlots - 1 ? 0 : 6,
                ),
                child:
                    (isAddIcon || isLockIcon)
                        ? _buildPlaceholderCard(context, isAddIcon)
                        : _buildPostCard(context, index, isPlaceholder),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholderCard(BuildContext context, bool isAddIcon) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenWidth = MediaQuery.of(context).size.width;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isAddIcon) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder:
                    (context) => const PostwriteScreen(isEditingMode: false),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withOpacity(0.3),
        highlightColor: Colors.white.withOpacity(0.1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: screenWidth * sizeFactor,
            height: screenWidth * sizeFactor * 1.15,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child:
                  isAddIcon
                      ? Icon(
                        Icons.add,
                        size: 48,
                        color: onSurface.withOpacity(0.4),
                      )
                      : SvgPicture.asset(
                        'assets/icons/lock.svg',
                        width: 48,
                        height: 48,
                        colorFilter: ColorFilter.mode(
                          onSurface.withOpacity(0.4),
                          BlendMode.srcIn,
                        ),
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, int index, bool isPlaceholder) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: () {
        if (isPlaceholder) return;
        final postIdRaw = widget.posts[index]['id'];
        final postId = postIdRaw?.toString();
        if (postId != null && postId.isNotEmpty) {
          if (widget.onPostTapWithId != null) {
            widget.onPostTapWithId!.call(postId);
          } else {
            try {
              final postData = PostData.fromServerMeta(widget.posts[index]);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (context) =>
                          PostReaderScreen(exported: postData.toExportedData()),
                ),
              );
            } catch (e) {
              debugPrint('[LockedPostCardSection] 포스트 데이터 변환 실패: $e');
              widget.onPostTap?.call();
            }
          }
        } else {
          widget.onPostTap?.call();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: screenWidth * sizeFactor,
          decoration:
              !isPlaceholder
                  ? BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: onSurface.withOpacity(0.3),
                      width: 1.0,
                    ),
                  )
                  : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Builder(
                builder: (context) {
                  final thumbnailUrl =
                      widget.posts[index]['thumbnailImageUrl'] as String? ?? '';
                  final url = thumbnailUrl.toLowerCase();
                  final isVideo =
                      url.endsWith('.mp4') ||
                      url.endsWith('.mov') ||
                      url.endsWith('.m4v') ||
                      url.contains('/videos/') ||
                      url.contains('video');

                  if (isVideo && thumbnailUrl.isNotEmpty) {
                    return ThumbnailVideoPlayer(
                      videoUrl: thumbnailUrl,
                      width: screenWidth * sizeFactor,
                      height: screenWidth * sizeFactor * 1.15,
                    );
                  }

                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final isAndroid =
                      defaultTargetPlatform == TargetPlatform.android;
                  final multiplier = isAndroid ? 1.5 : 2.0;
                  final maxDecodeWidthPx = isAndroid ? 2048 : 3072;
                  final memCacheWidth = (screenWidth *
                          sizeFactor *
                          dpr *
                          multiplier)
                      .round()
                      .clamp(1, maxDecodeWidthPx);

                  return RepaintBoundary(
                    child: CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      cacheKey: thumbnailUrl, // ✅ 명시적 캐시 키 지정
                      // ✅ 디코드 폭 제한(안드로이드 프레임 드롭 완화)
                      memCacheWidth: memCacheWidth,
                      cacheManager:
                          ReadImageCacheManager.instance, // ✅ 읽기 전용 캐시 매니저 사용
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero, // ✅ 페이드 애니메이션 제거
                      useOldImageOnUrlChange: true, // ✅ URL 변경 시 이전 이미지 유지
                      placeholder:
                          (context, url) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            child: Icon(
                              Icons.image_not_supported,
                              color: onSurface.withOpacity(0.3),
                            ),
                          ),
                    ),
                  );
                },
              ),
              // ✅ 잠금 해제 시 검정색 블러 오버레이와 큰 체크 아이콘
              if (!isPlaceholder)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: Colors.black.withOpacity(0.4),
                      child: Center(
                        child: Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 120,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostFillSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onPostTap;
  final String? title;
  final List<String>? titleBoldSubstrings; // ✅ 볼드 서브스트링 지원

  PostFillSection({
    super.key,
    required this.posts,
    this.onPostTap,
    required this.title,
    this.titleBoldSubstrings,
  });

  @override
  State<PostFillSection> createState() => _PostFillSectionState();
}

class _PostFillSectionState extends State<PostFillSection>
    with AutomaticKeepAliveClientMixin {
  late final PageController _pageController;
  int _currentPage = 0;
  late List<Map<String, dynamic>> _uniquePostsCache;
  // ✅ 홈 썸네일 디코드 상한
  // - Android: 디코드/메모리 비용이 커서 더 보수적으로
  static int get _kMaxDecodeWidthPx =>
      defaultTargetPlatform == TargetPlatform.android ? 2048 : 3072;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(keepPage: true); // ✅ 페이지 상태 유지
    _pageController.addListener(_onPageChanged);

    // ✅ 중복 제거된 포스트 목록을 한 번만 만들고 캐시 (프리로드/인덱싱 안정화)
    _uniquePostsCache = _buildUniquePosts(widget.posts);

    // ✅ 첫 프레임 이후: 현재/인접 페이지 미디어 프리로드(이미지+영상)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _preloadAround(page: _currentPage);
    });
  }

  @override
  void didUpdateWidget(covariant PostFillSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posts != widget.posts) {
      _uniquePostsCache = _buildUniquePosts(widget.posts);
      // 데이터가 바뀌면 현재 페이지 기준으로 다시 프리로드
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _preloadAround(page: _currentPage);
      });
    }
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentPage && mounted) {
      setState(() {
        _currentPage = page;
      });

      // ✅ 페이지 전환 직후 인접 미디어 프리로드(체감 속도 개선)
      _preloadAround(page: page);
    }
  }

  List<Map<String, dynamic>> _buildUniquePosts(
    List<Map<String, dynamic>> posts,
  ) {
    final uniquePosts = <Map<String, dynamic>>[];
    final seenPostIds = <String>{};
    for (final post in posts) {
      final postIdRaw = post['id'];
      final postId = postIdRaw?.toString() ?? '';
      if (postId.isNotEmpty && !seenPostIds.contains(postId)) {
        seenPostIds.add(postId);
        uniquePosts.add(post);
      }
    }
    return uniquePosts;
  }

  bool _isVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.endsWith('.mov') ||
        u.endsWith('.m4v') ||
        u.contains('/videos/') ||
        u.contains('video');
  }

  int _homeDecodeWidthPx(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // ✅ CachedNetworkImage의 memCacheWidth와 동일 기준으로 맞춤(=캐시 히트 핵심)
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final multiplier = isAndroid ? 1.5 : 2.0;
    return (screenW * dpr * multiplier).round().clamp(1, _kMaxDecodeWidthPx);
  }

  void _preloadAround({required int page}) {
    if (!mounted) return;
    if (_uniquePostsCache.isEmpty) return;

    final start = (page - 2).clamp(0, _uniquePostsCache.length - 1);
    final end = (page + 2).clamp(0, _uniquePostsCache.length - 1);

    final decodeWidthPx = _homeDecodeWidthPx(context);

    for (int i = start; i <= end; i++) {
      if (i == page) continue;
      final thumb = _uniquePostsCache[i]['thumbnailImageUrl'] as String? ?? '';
      if (thumb.isEmpty) continue;

      if (_isVideoUrl(thumb)) {
        // ✅ 비디오는 컨트롤러 프리로드(이미지 precache로는 효과 없음)
        ThumbnailVideoPlayer.preload(thumb);
      } else {
        // ✅ 이미지 프리로드: cacheManager + ResizeImage(widthPx)까지 동일하게
        Future.microtask(() async {
          if (!mounted) return;
          try {
            final provider = CachedNetworkImageProvider(
              thumb,
              cacheManager: ReadImageCacheManager.instance,
            );
            final resized = ResizeImage(provider, width: decodeWidthPx);
            await precacheImage(resized, context);
          } catch (_) {
            // best-effort
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ AutomaticKeepAliveClientMixin을 위해 필수
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = widget.title;

    // ✅ 캐시된 중복 제거 목록 사용
    final uniquePosts = _uniquePostsCache;

    if (uniquePosts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          '포스트가 없습니다.',
          style: LocaleTypography.style(
            context: context,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: onSurface,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 이미지 리스트 (가로 스크롤)
        Stack(
          children: [
            SizedBox(
              height: 420,
              child: PageView.builder(
                physics: const ClampingScrollPhysics(),
                padEnds: false,
                controller: _pageController, // ✅ keepPage는 PageController에서 설정됨
                itemCount: uniquePosts.length,
                itemBuilder: (context, index) {
                  final post = uniquePosts[index];
                  final postIdRaw = post['id'];
                  final postId = postIdRaw?.toString() ?? 'post_$index';

                  // ✅ 각 페이지를 StatefulWidget으로 만들어 상태 유지
                  return _PostFillPageItem(
                    key: ValueKey('post_fill_$postId'),
                    imageUrl: post['thumbnailImageUrl'] as String? ?? '',
                    postData: post,
                    onTap: widget.onPostTap,
                    isActive: index == _currentPage,
                  );
                },
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.03),
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.4),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 제목이 잘리지 않도록 충분한 공간 확보
                      Flexible(
                        fit: FlexFit.loose,
                        child:
                            // ✅ title만 사용, 볼드 서브스트링 지원
                            widget.titleBoldSubstrings != null &&
                                    widget.titleBoldSubstrings!.isNotEmpty
                                ? buildTitleWithBoldSubstrings(
                                  context: context,
                                  title: title ?? '',
                                  boldSubstrings: widget.titleBoldSubstrings!,
                                  baseStyle: LocaleTypography.style(
                                    context: context,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                  ),
                                  boldStyle: LocaleTypography.style(
                                    context: context,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                )
                                : Text(
                                  title ?? '',
                                  style: LocaleTypography.style(
                                    context: context,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.clip,
                                  textAlign: TextAlign.left,
                                  softWrap: true,
                                ),
                      ),
                      SizedBox(height: HomeSectionSpacing.sectionTiny),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              top: 20,
              left: 24,
              child: // 페이지 인디케이터
                  Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: List.generate(uniquePosts.length, (index) {
                  return Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          index == _currentPage
                              ? Colors.white
                              : Colors.white.withOpacity(0.5),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        // ✅ 하단 간격: 섹션 자체에서 관리
        SizedBox(height: HomeSectionSpacing.sectionLarge),
      ],
    );
  }
}

// ✅ PageView의 각 페이지를 위한 StatefulWidget (이미지 상태 유지)
class _PostFillPageItem extends StatefulWidget {
  final String imageUrl;
  final Map<String, dynamic> postData;
  final VoidCallback? onTap;
  final bool isActive; // ✅ 현재 페이지인지 (비디오 자동재생 제어)

  const _PostFillPageItem({
    super.key,
    required this.imageUrl,
    required this.postData,
    this.onTap,
    required this.isActive,
  });

  @override
  State<_PostFillPageItem> createState() => _PostFillPageItemState();
}

class _PostFillPageItemState extends State<_PostFillPageItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ AutomaticKeepAliveClientMixin을 위해 필수
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final decodeWidthPx = (screenWidth * dpr * 2).round().clamp(
      1,
      _PostFillSectionState._kMaxDecodeWidthPx,
    ); // ✅ 안정성 캡

    return RepaintBoundary(
      child: Container(
        child: GestureDetector(
          onTap: () {
            if (widget.onTap != null) {
              widget.onTap!();
              return;
            }
            // 포스트 ID 추출하여 PostReaderScreen으로 이동
            final postIdRaw = widget.postData['id'];
            final postId = postIdRaw?.toString();
            if (postId != null && postId.isNotEmpty) {
              try {
                final postData = PostData.fromServerMeta(widget.postData);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (context) => PostReaderScreen(
                          exported: postData.toExportedData(),
                        ),
                  ),
                );
              } catch (e) {
                debugPrint('[PostFillSection] 포스트 데이터 변환 실패: $e');
              }
            }
          },
          child: Builder(
            builder: (context) {
              final url = widget.imageUrl.toLowerCase();
              final isVideo =
                  url.endsWith('.mp4') ||
                  url.endsWith('.mov') ||
                  url.endsWith('.m4v') ||
                  url.contains('/videos/') ||
                  url.contains('video');

              if (isVideo && widget.imageUrl.isNotEmpty) {
                return ThumbnailVideoPlayer(
                  videoUrl: widget.imageUrl,
                  width: screenWidth,
                  height: 500,
                  autoPlay: widget.isActive,
                );
              }

              return RepaintBoundary(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  cacheKey: widget.imageUrl, // ✅ 명시적 캐시 키 지정
                  cacheManager:
                      ReadImageCacheManager.instance, // ✅ 읽기 전용 캐시 매니저 사용
                  fit: BoxFit.cover,
                  // ✅ 페이드 효과 제거하여 이미지가 즉시 표시되도록 함
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  useOldImageOnUrlChange: true, // ✅ URL 변경 시 이전 이미지 유지
                  // ✅ 메모리 캐시 최적화
                  memCacheWidth: decodeWidthPx,
                  // ⚠️ maxWidthDiskCache는 리사이즈 캐시 생성 시 실패 케이스가 있어 홈에서는 사용하지 않음
                  placeholder:
                      (context, url) => Container(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                  errorWidget:
                      (context, url, error) => Container(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Icon(
                          Icons.image_not_supported,
                          color: onSurface.withOpacity(0.3),
                        ),
                      ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ✅ 오프라인 상태 배너 (그리드 밑에 표시)
Widget _buildOfflineBanner(BuildContext context) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  final l10n = AppLocalizations.of(context);
  return Container(
    margin: const EdgeInsets.only(
      bottom: HomeSectionSpacing.sectionLarge,
      left: 20,
      right: 20,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            l10n.t('offline_status'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: onSurface,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.t('check_network_connection'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            Icons.keyboard_arrow_down,
            color: onSurface.withOpacity(0.4),
            size: 28,
          ),
        ],
      ),
    ),
  );
}
