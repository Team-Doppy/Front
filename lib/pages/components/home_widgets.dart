import 'dart:ui';

import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/pages/components/recap/recap_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/date_picker_screen.dart'
    show DatePickerScreen;
import 'package:doppy/pages/screens/my_friends_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
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
import 'package:doppy/utils/week_utils.dart';

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
      0.0; // 그리드 아래 간격 (FillSection과 ListSection 사이와 동일)
  static const double bannerBottom = 24.0; // 배너 아래 간격
  static const double postCardHeaderBottom = 12.0; // 포스트 카드 헤더 아래 간격
  static const double postCardTitleBottom = 4.0; // 포스트 카드 제목 아래 간격
  static const double friendItemSpacing = 18.0; // 친구 아이템 간격 (가로)
  static const double friendItemBottom = 10.0; // 친구 아이템 아래 간격
}

// =============================================================================
// ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시)
// =============================================================================

/// ✅ 가입 후 7일 이내인지 확인하는 메서드
/// - _buildBannerCard와 동일한 조건 사용
// ✅ isWithin7DaysAfterSignup은 WeekUtils로 이동됨

/// ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시)
/// - createdAt 기준으로 7일 이내일 때만 표시
/// - 남은 일수에 따라 텍스트 변경
Widget? _buildBannerCard(BuildContext context, DateTime? createdAt) {
  // createdAt이 없으면 표시하지 않음
  if (createdAt == null) {
    debugPrint('[HomeWidgets] _buildBannerCard: createdAt is null');
    return null;
  }

  // ✅ WeekUtils의 공통 메서드 사용
  if (!WeekUtils.isWithin7DaysAfterSignup(createdAt)) {
    debugPrint('[HomeWidgets] _buildBannerCard: 7일 이내가 아님, returning null');
    return null;
  }

  // 남은 일수 계산 (배너 텍스트용)
  final now = WeekUtils.getCurrentDate(); // ✅ 테스트 모드 지원
  final createdAtLocal = createdAt.toLocal();
  final daysSinceSignup = now.difference(createdAtLocal).inDays;
  final daysRemaining = 7 - daysSinceSignup;

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
    secondLine = '지난 기록도 작성할 수 있어요';
  }

  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DatePickerScreen(createdAt: createdAt),
        ),
      );
    },
    child: Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 80, bottom: 110),
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
          PostCardSection(
            key: postCardKey, // ✅ 가이드용 GlobalKey
            mode: PostCardSectionMode.locked,
            posts: posts.toList(),
            title: '나만의 기록 리포트',
            subtitle: '기록 3개면 볼 수 있어요',
            titleBoldSubstrings: ['나만의 기록 리포트'],
            titleColor: AppColors.primary, // ✅ primary 색상 적용
          ),
        );

        // ✅ 친구 포스트가 있으면 친구 포스트 섹션 추가
        if (hasFriendPosts) {
          sections.add(
            PostCardSection(
              mode: PostCardSectionMode.unlocked,
              posts: friendPosts.take(5).toList(),
              title: '요새 내 친구들',
              titleBoldSubstrings: ['요새'],
              showAuthorInfo: true,
            ),
          );
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

        // ✅ 7일 제한 배너 카드 (조건에 맞을 때만 표시)
        // ProfileInfoBundle의 createdAt 우선, 없으면 signupAt 사용
        final createdAt = userProvider.createdAt ?? signupAt;
        final bannerCard = _buildBannerCard(context, createdAt);
        if (bannerCard != null) {
          sections.add(bannerCard);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: HomeSectionSpacing.gridTop),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 주간 스트릭 제목 (그리드 바로 위, 왼쪽 정렬)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 20,
                      top: 30,
                      bottom: 4,
                    ),
                    child: Text(
                      '$year 주간 기록',
                      style: LocaleTypography.style(
                        context: context,
                        fontSize: 16,
                        fontWeight: FontWeight.w700, // 볼드체
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                  WeeklyContributionGrid(
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
                    onCellKey: (y, w, k) {
                      contributionProvider.registerWeekCellKey(y, w, k);
                    },
                  ),
                ],
              ),
            ),

            // 코치마크 (주간 스트릭 설명)
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
  /// 리캡을 한 번 보면 바로 사라짐 (3일 조건 없음)
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

      // ✅ 타임스탬프가 있으면 무조건 숨김 (3일 조건 제거)
      return false;
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
    return Consumer4<
      HomeRecommendationProvider,
      FriendProvider,
      UserProvider,
      MyProfileFeedProvider
    >(
      builder: (
        context,
        recommendationProvider,
        friendProvider,
        userProvider,
        feedProvider,
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
              PostCardSection(
                key: ValueKey('list_social_${titleHash}_$firstPostId'),
                mode: PostCardSectionMode.unlocked,
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
              PostCardSection(
                mode: PostCardSectionMode.unlocked,
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
        // ✅ 중요: 포스트가 3개 이상일 때만 표시
        final posts = feedProvider.posts;
        final hasEnoughPosts = posts.length >= 3;
        final hasAnyHomeSection =
            emotionBased.any((rec) => rec.posts.isNotEmpty) ||
            socialBased.any((rec) => rec.posts.isNotEmpty) ||
            timeBased.any((rec) => rec.posts.isNotEmpty);

        // ✅ 비동기 처리: 리캡을 봤는지 확인 (포스트가 3개 이상일 때만)
        return FutureBuilder<bool>(
          // ✅ Future identity를 안정화(=subtree dispose 방지). 복귀 시(didPopNext)만 null로 만들어 새로고침.
          future:
              hasEnoughPosts
                  ? _resolveShouldShowFuture(
                    hasAnyHomeSection: hasAnyHomeSection,
                  )
                  : Future.value(false), // 포스트가 3개 미만이면 표시하지 않음
          builder: (context, snapshot) {
            final shouldShow = snapshot.data ?? false; // 포스트가 3개 미만이면 기본값: 숨김

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
            // ✅ 포스트가 3개 이상일 때만 표시
            if (hasEnoughPosts) {
              if (!hasAnyHomeSection) {
                // ✅ 케이스 1: 홈 섹션에 아무것도 없으면 무조건 표시
                myImpressWidget = const RecapCard();
                finalFillSections.add(myImpressWidget);
              } else if (shouldShow) {
                // ✅ 케이스 2: 하나라도 있고, 아직 안봤으면 최상단에 노출
                myImpressWidget = const RecapCard();
                finalFillSections.insert(0, myImpressWidget);
              }
            }
            // 봤으면 숨기기 (myImpressWidget = null)

            // 섹션 배치 로직
            final finalSections = <Widget>[];
            final finalListSections = List<Widget>.from(listSections);

            // 🎯 규칙에 따라 섹션 배치: FillSection → ListSection → FillSection → ListSection ...
            // 첫 번째는 반드시 FillSection
            if (finalFillSections.isNotEmpty) {
              finalSections.add(finalFillSections.removeAt(0));
            }

            // ✅ 2번째 섹션: 친구 포스트가 있으면 바로 추가
            if (hasFriendPosts) {
              final friendSection = PostCardSection(
                mode: PostCardSectionMode.unlocked,
                posts: friendPosts.take(5).toList(),
                title: '요새 내 친구들',
                titleBoldSubstrings: ['요새'],
                showAuthorInfo: true,
              );
              finalSections.add(friendSection);
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
                    vertical: 12,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 주간 스트릭 제목 (그리드 바로 위, 왼쪽 정렬)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 20,
                          top: 30,
                          bottom: 4,
                        ),
                        child: Text(
                          '${widget.year} 주간 기록',
                          style: LocaleTypography.style(
                            context: context,
                            fontSize: 16,
                            fontWeight: FontWeight.w700, // 볼드체
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.80),
                          ),
                        ),
                      ),
                      WeeklyContributionGrid(
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
                        onCellKey: (y, w, k) {
                          context
                              .read<WeeklyContributionProvider>()
                              .registerWeekCellKey(y, w, k);
                        },
                      ),
                    ],
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
                  context.tr('home_friend_recommend_header'),
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
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
  Future<String?>? _messageFuture; // ✅ build마다 Future 재생성 방지
  int? _messageKeyHash;

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
        '환영해요\n이번주도 기록해볼까요?',
        style: LocaleTypography.style(
          context: context,
          color: onSurface,
          fontSize: 24,
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
        fontSize: 24,
        fontWeight: FontWeight.w300,
        letterSpacing: -1,
        height: 1.4,
      );

      final boldStyle = LocaleTypography.style(
        context: context,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 24,
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
                fontSize: 24,
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

  @override
  Widget build(BuildContext context) {
    // ✅ 높이 고정: 메시지 전환/로딩 중 레이아웃 요동 방지
    return SizedBox(
      height: 70.0,
      child: Builder(
        builder: (context) {
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

class PostFillSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onPostTap;
  final Function(String postId)? onPostTapWithId;
  final String? title;
  final List<String>? titleBoldSubstrings;

  const PostFillSection({
    super.key,
    required this.posts,
    this.onPostTap,
    this.onPostTapWithId,
    required this.title,
    this.titleBoldSubstrings,
  });

  @override
  State<PostFillSection> createState() => _PostFillSectionState();
}

class _PostFillSectionState extends State<PostFillSection>
    with AutomaticKeepAliveClientMixin {
  late final PageController _pageController;
  late final ValueNotifier<int> _currentPageNotifier;
  late List<Map<String, dynamic>> _uniquePostsCache;

  static int get _kMaxDecodeWidthPx =>
      defaultTargetPlatform == TargetPlatform.android ? 2048 : 3072;

  @override
  bool get wantKeepAlive => true;

  void _openPost(
    BuildContext context,
    Map<String, dynamic> post,
    String postId,
  ) {
    if (widget.onPostTapWithId != null) {
      widget.onPostTapWithId!(postId);
      return;
    }

    try {
      final postData = PostData.fromServerMeta(post);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostReaderScreen(exported: postData.toExportedData()),
        ),
      );
    } catch (e) {
      debugPrint('[PostFillSection] 포스트 열기 실패: $e');
      widget.onPostTap?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(keepPage: true);
    _currentPageNotifier = ValueNotifier<int>(0);

    _pageController.addListener(() {
      if (!_pageController.hasClients) return;
      final page = _pageController.page?.round() ?? 0;
      if (_currentPageNotifier.value != page) {
        _currentPageNotifier.value = page;
      }
    });

    _uniquePostsCache = _buildUniquePosts(widget.posts);
  }

  @override
  void didUpdateWidget(covariant PostFillSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posts != widget.posts) {
      _uniquePostsCache = _buildUniquePosts(widget.posts);
    }
  }

  @override
  void dispose() {
    _currentPageNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _buildUniquePosts(
    List<Map<String, dynamic>> posts,
  ) {
    final seenIds = <String>{};
    final result = <Map<String, dynamic>>[];

    for (final post in posts) {
      final id = post['id']?.toString();
      if (id != null && id.isNotEmpty && seenIds.add(id)) {
        result.add(post);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = widget.title ?? '';
    final posts = _uniquePostsCache;

    if (posts.isEmpty) {
      return Padding(
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
      children: [
        Stack(
          children: [
            /// ---------------- PageView (고정) ----------------
            SizedBox(
              height: 420,
              child: PageView.builder(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                padEnds: false,
                allowImplicitScrolling: false,
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final postId = post['id']?.toString() ?? index.toString();

                  return ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (_, currentPage, __) {
                      return _PostFillPageItem(
                        key: ValueKey('post_fill_$postId'),
                        imageUrl: post['thumbnailImageUrl'] ?? '',
                        postData: post,
                        onTap: () => _openPost(context, post, postId),
                        isActive: index == currentPage,
                      );
                    },
                  );
                },
              ),
            ),

            /// ---------------- Gradient + Title ----------------
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(24),
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
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child:
                            widget.titleBoldSubstrings != null &&
                                    widget.titleBoldSubstrings!.isNotEmpty
                                ? buildTitleWithBoldSubstrings(
                                  context: context,
                                  title: title,
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
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.clip,
                                  style: LocaleTypography.style(
                                    context: context,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                      ),
                      SizedBox(height: HomeSectionSpacing.sectionTiny),
                    ],
                  ),
                ),
              ),
            ),

            /// ---------------- Indicator (최소 rebuild) ----------------
            Positioned(
              top: 20,
              left: 24,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentPageNotifier,
                builder: (_, currentPage, __) {
                  return Row(
                    children: List.generate(posts.length, (index) {
                      return Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              index == currentPage
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.5),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
        SizedBox(height: HomeSectionSpacing.sectionLarge),
      ],
    );
  }
}

class _PostFillPageItem extends StatefulWidget {
  final String imageUrl;
  final Map<String, dynamic> postData;
  final VoidCallback? onTap;
  final bool isActive;

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
    super.build(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final decodeWidthPx = (screenWidth * dpr * 2).round().clamp(
      1,
      _PostFillSectionState._kMaxDecodeWidthPx,
    );

    final url = widget.imageUrl.toLowerCase();
    final isVideo =
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.m4v') ||
        url.contains('video');

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child:
            isVideo
                ? ThumbnailVideoPlayer(
                  videoUrl: widget.imageUrl,
                  width: screenWidth,
                  height: 500,
                  autoPlay: widget.isActive,
                )
                : CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  cacheKey: widget.imageUrl,
                  cacheManager: ReadImageCacheManager.instance,
                  fit: BoxFit.cover,
                  memCacheWidth: decodeWidthPx,
                  fadeInDuration: const Duration(milliseconds: 200),
                  fadeOutDuration: const Duration(milliseconds: 200),
                  placeholder:
                      (_, __) => ShimmerBox(width: screenWidth, height: 420),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                ),
      ),
    );
  }
}

enum PostCardSectionMode { unlocked, locked }

class PostCardSection extends StatefulWidget {
  final PostCardSectionMode mode;
  final List<Map<String, dynamic>> posts;

  final String? title;
  final String? subtitle;
  final List<String>? titleBoldSubstrings; // 🎯 볼드 서브스트링 지원
  final Color? titleColor; // ✅ title 색상 커스터마이징

  final bool showAuthorInfo;
  final VoidCallback? onPostTap;
  final Function(String postId)? onPostTapWithId;

  const PostCardSection({
    super.key,
    required this.mode,
    required this.posts,
    this.title,
    this.subtitle,
    this.titleBoldSubstrings,
    this.titleColor,
    this.showAuthorInfo = false,
    this.onPostTap,
    this.onPostTapWithId,
  });

  @override
  State<PostCardSection> createState() => _PostCardSectionState();
}

class _PostCardSectionState extends State<PostCardSection>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  late final ValueNotifier<int> _currentPageNotifier;

  static const int _lockedSlots = 3;
  static const double _unlockedSizeFactor = 0.74;
  static const double _lockedSizeFactor = 0.6;

  double get _sizeFactor =>
      widget.mode == PostCardSectionMode.locked
          ? _lockedSizeFactor
          : _unlockedSizeFactor;

  int get _itemCount =>
      widget.mode == PostCardSectionMode.locked
          ? _lockedSlots
          : widget.posts.length.clamp(0, 5);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _currentPageNotifier = ValueNotifier<int>(0);

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth * _sizeFactor + 6;

    final page = (_scrollController.position.pixels / itemWidth).round().clamp(
      0,
      _itemCount - 1,
    );

    if (_currentPageNotifier.value != page) {
      _currentPageNotifier.value = page;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.posts.isEmpty && widget.mode == PostCardSectionMode.unlocked) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Header(
          title: widget.title,
          subtitle: widget.subtitle,
          titleColor: widget.titleColor,
          titleBoldSubstrings: widget.titleBoldSubstrings,
          count: _itemCount,
          notifier: _currentPageNotifier,
          showIndicator:
              widget.mode == PostCardSectionMode.locked ||
              widget.showAuthorInfo,
        ),
        SizedBox(height: HomeSectionSpacing.sectionSmall),
        _buildList(context),
        SizedBox(height: HomeSectionSpacing.sectionLarge),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final height = screenWidth * _sizeFactor * 1.15;

    return SizedBox(
      height: height,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _itemCount,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final isLocked = widget.mode == PostCardSectionMode.locked;
          final isPlaceholder = index >= widget.posts.length;

          if (isLocked && isPlaceholder) {
            return Container(
              margin: EdgeInsets.only(right: index == _itemCount - 1 ? 0 : 6),
              child: _PlaceholderCard(sizeFactor: _sizeFactor),
            );
          }

          final post = widget.posts[index];
          final postId = post['id']?.toString() ?? index.toString();

          return RepaintBoundary(
            key: ValueKey('post_card_$postId'),
            child: Container(
              margin: EdgeInsets.only(right: index == _itemCount - 1 ? 0 : 6),
              child: _PostCard(
                post: post,
                sizeFactor: _sizeFactor,
                locked: isLocked,
                showAuthorInfo: widget.showAuthorInfo,
                titleBoldSubstrings: widget.titleBoldSubstrings,
                onTap: () => _onTap(context, index),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, int index) {
    if (index >= widget.posts.length) return;

    final postId = widget.posts[index]['id']?.toString();
    if (postId == null) return;

    if (widget.onPostTapWithId != null) {
      widget.onPostTapWithId!(postId);
      return;
    }

    try {
      final postData = PostData.fromServerMeta(widget.posts[index]);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostReaderScreen(exported: postData.toExportedData()),
        ),
      );
    } catch (_) {
      widget.onPostTap?.call();
    }
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final double sizeFactor;
  final bool locked;
  final bool showAuthorInfo;
  final List<String>? titleBoldSubstrings; // 🎯 볼드 서브스트링 지원
  final VoidCallback onTap;

  const _PostCard({
    required this.post,
    required this.sizeFactor,
    required this.locked,
    required this.showAuthorInfo,
    this.titleBoldSubstrings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    final memCacheWidth = (screenWidth *
            sizeFactor *
            dpr *
            (isAndroid ? 1.5 : 2.0))
        .round()
        .clamp(1, isAndroid ? 2048 : 3072);

    final thumbnailUrl = post['thumbnailImageUrl'] as String? ?? '';
    final isVideo = thumbnailUrl.toLowerCase().contains('video');

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: screenWidth * sizeFactor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              isVideo
                  ? ThumbnailVideoPlayer(
                    videoUrl: thumbnailUrl,
                    width: screenWidth * sizeFactor,
                    height: screenWidth * sizeFactor * 1.15,
                  )
                  : CachedNetworkImage(
                    imageUrl: thumbnailUrl,
                    cacheKey: thumbnailUrl,
                    cacheManager: ReadImageCacheManager.instance,
                    fit: BoxFit.cover,
                    memCacheWidth: memCacheWidth,
                    fadeInDuration: const Duration(milliseconds: 200),
                    fadeOutDuration: const Duration(milliseconds: 200),
                  ),

              if (locked)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                      ),

                      child: const Center(
                        child: Icon(Icons.check, color: Colors.white, size: 96),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _PostCardOverlay(
                    post: post,
                    showAuthorInfo: showAuthorInfo,
                    titleBoldSubstrings: titleBoldSubstrings,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostCardOverlay extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool showAuthorInfo;
  final List<String>? titleBoldSubstrings; // 🎯 볼드 서브스트링 지원

  const _PostCardOverlay({
    required this.post,
    required this.showAuthorInfo,
    this.titleBoldSubstrings,
  });

  @override
  Widget build(BuildContext context) {
    final title = post['title'] as String? ?? '';
    final author = post['author'] as String? ?? '';
    final alias = post['alias'] as String? ?? '';
    final profile = post['authorProfileImageUrl'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🎯 buildTitleWithBoldSubstrings 사용하여 통일
          titleBoldSubstrings != null && titleBoldSubstrings!.isNotEmpty
              ? buildTitleWithBoldSubstrings(
                context: context,
                title: title,
                boldSubstrings: titleBoldSubstrings!,
                baseStyle: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                boldStyle: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              )
              : Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LocaleTypography.style(
                  context: context,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
          if (showAuthorInfo) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                CommonProfileAvatar(
                  imageUrl: profile,
                  username: author,
                  size: 32,
                  borderWidth: 0,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alias.isNotEmpty ? alias : author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Color? titleColor; // ✅ title 색상 커스터마이징
  final List<String>? titleBoldSubstrings; // ✅ 볼드 서브스트링 지원
  final int count;
  final ValueNotifier<int> notifier;
  final bool showIndicator;

  const _Header({
    this.title,
    this.subtitle,
    this.titleColor,
    this.titleBoldSubstrings,
    required this.count,
    required this.notifier,
    this.showIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if ((title == null || title!.isEmpty) &&
        (subtitle == null || subtitle!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          /// LEFT : TITLE / SUBTITLE
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty)
                  titleBoldSubstrings != null && titleBoldSubstrings!.isNotEmpty
                      ? buildTitleWithBoldSubstrings(
                        context: context,
                        title: title!,
                        boldSubstrings: titleBoldSubstrings!,
                        baseStyle: LocaleTypography.style(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          color: titleColor ?? onSurface,
                        ),
                        boldStyle: LocaleTypography.style(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: titleColor ?? onSurface,
                        ),
                      )
                      : Text(
                        title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                          color:
                              titleColor ??
                              onSurface, // ✅ titleColor가 있으면 사용, 없으면 기본 색상
                        ),
                      ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  SizedBox(height: HomeSectionSpacing.sectionTiny + 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LocaleTypography.style(
                      context: context,
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),

          /// RIGHT : PAGE INDICATOR
          if (showIndicator && count > 1) ...[
            const SizedBox(width: 12),
            ValueListenableBuilder<int>(
              valueListenable: notifier,
              builder: (context, currentPage, _) {
                final visibleCount = count.clamp(0, 5);

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(visibleCount, (index) {
                    return Container(
                      width: 10,
                      height: 10,
                      margin: EdgeInsets.only(
                        right: index == visibleCount - 1 ? 0 : 4,
                      ),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            currentPage == index
                                ? onSurface
                                : onSurface.withOpacity(0.3),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  final double sizeFactor;

  const _PlaceholderCard({required this.sizeFactor});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    PostwriteScreen(isEditingMode: false),
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: screenWidth * sizeFactor,
          height: screenWidth * sizeFactor * 1.15,
          color:
              isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                size: 48,
              ),
            ],
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
