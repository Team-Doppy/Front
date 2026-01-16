import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/week_preview_content.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';
import 'package:doppy/pages/components/weekly_contribution_test_data.dart';
import 'package:doppy/pages/screens/week_post_list_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/home_feed_service.dart';
import 'package:doppy/utils/home_greetings.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/pages/components/home_widgets.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  final bool isActive; // 현재 탭이 활성 상태인지

  const HomeScreen({super.key, this.isActive = true});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  final HomeFeedService _homeFeedService = HomeFeedService();

  // 🎯 포그라운드 복귀 시 새로고침을 위한 GlobalKey
  static final GlobalKey<HomeScreenState> globalKey =
      GlobalKey<HomeScreenState>();

  // 잔디 심기 UI 관련 상태
  int? _selectedYear; // 선택된 연도
  int? _selectedWeek; // 선택된 주차

  // 길게 누르기 미리보기(블러 없이) 오버레이
  OverlayEntry? _weekPreviewEntry;
  Offset _weekPreviewPosition = Offset.zero;
  int? _weekPreviewWeek;
  int? _weekPreviewYear;

  bool _isTestMode = false; // 테스트 모드 활성화 여부
  DateTime? _testSignupAt; // 테스트용 가입일
  DateTime? _testAsOf; // 테스트용 기준일(asOf) - 행 수를 늘리려면 필수
  List<WeeklyContributionData>? _testContributions; // 테스트용 기여도 데이터

  // 디버그 모드: 샘플 데이터 표시 여부 (빈 데이터 토글용)
  bool _showSampleData = true;

  @override
  void initState() {
    super.initState();

    // 초기 연도 설정
    _selectedYear = WeekUtils.getCurrentYear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileSafely();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _removeWeekPreview();
    super.dispose();
  }

  void _removeWeekPreview() {
    _weekPreviewEntry?.remove();
    _weekPreviewEntry = null;
    _weekPreviewWeek = null;
    _weekPreviewYear = null;
  }

  void _showOrMoveWeekPreview({
    required int year,
    required int weekNumber,
    required Offset globalPosition,
  }) {
    _weekPreviewYear = year;
    _weekPreviewWeek = weekNumber;
    _weekPreviewPosition = globalPosition;

    if (_weekPreviewEntry == null) {
      final overlay = Overlay.of(context, rootOverlay: true);

      _weekPreviewEntry = OverlayEntry(
        builder: (context) {
          final media = MediaQuery.of(context);
          final size = media.size;
          final safeTop = media.padding.top;
          final safeBottom = media.padding.bottom;

          // 프리뷰 카드 크기(WeekPreviewContent 기준)
          const cardW = 250.0;
          const cardH = 200.0;

          // 손가락 근처에 표시(약간 위로)
          double left = _weekPreviewPosition.dx - (cardW / 2);
          double top = _weekPreviewPosition.dy - cardH - 16;

          // 화면 밖으로 나가지 않도록 clamp
          left = left.clamp(12.0, size.width - cardW - 12.0);
          top = top.clamp(
            safeTop + 12.0,
            size.height - safeBottom - cardH - 12.0,
          );

          return Stack(
            children: [
              // 빈 곳 탭하면 닫기
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _removeWeekPreview,
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: IgnorePointer(
                  child: WeekPreviewContent(
                    weekNumber: _weekPreviewWeek ?? weekNumber,
                    year: _weekPreviewYear ?? year,
                  ),
                ),
              ),
            ],
          );
        },
      );
      overlay.insert(_weekPreviewEntry!);
    } else {
      _weekPreviewEntry?.markNeedsBuild();
    }
  }

  Future<void> _loadProfileSafely() async {
    try {
      await context.read<UserProvider>().fetchMyProfile();
      debugPrint('[HomeScreen] 프로필 로드 성공');
    } catch (e) {
      debugPrint('[HomeScreen] 프로필 로드 실패: $e');
      // 프로필 로드 실패해도 계속 진행 (UI에 영향 없음)
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildGridSection();
  }

  void _handleS1EmptyActionTap() {
    // TODO(서버 연동 후): 글 작성 화면으로 이동
    debugPrint('지금 기록하기 버튼 클릭');
  }

  List<Widget> _buildHomeFeedSectionWidgets() {
    // 디버그 빈 데이터 토글에서는 "원래 숨기는 섹션"도 빈 상태 UI를 확인할 수 있도록 허용
    final debugShowEmptyStates = kDebugMode && !_showSampleData;

    // 로케일 가져오기
    final l10n = AppLocalizations.of(context);

    // TODO(스플래시/서버 연동): 서버에서 받은 홈피드 데이터를 payload로 변환해서 주입
    // 지금은 하드코딩 제거 요구사항에 맞춰 빈 payload만 사용 (UI는 빈 처리 규칙대로 동작)
    final payload = const HomeFeedPayload.empty();

    final chunks = _homeFeedService.buildChunks(
      payload: payload,
      debugShowEmptyStates: debugShowEmptyStates,
      onS1EmptyActionTap: _handleS1EmptyActionTap,
      onAddFriendTap: () => debugPrint('친구 추가 버튼 클릭'),
      // 로케일 문자열 주입
      emptyS1Line1: l10n.t('home_empty_s1_line1'),
      emptyS1Line2Bold: l10n.t('home_empty_s1_line2'),
      friendRecommendHeader: [
        HomeTextChunk(l10n.t('home_friend_recommend_header')),
      ],
    );

    return chunks.map((c) {
      if (c is HomeSection1Chunk) {
        return HomeWidgets.section1(
          headerLine1: c.headerLine1,
          headerLine2: c.headerLine2,
          cards: c.cards,
          hideWhenEmpty: c.hideWhenEmpty,
          emptyMessage: c.emptyMessage,
          emptyActionText: c.emptyActionText,
          onEmptyActionTap: c.onEmptyActionTap,
          bottomSpacing: c.bottomSpacing,
        );
      }
      if (c is HomeSection2Chunk) {
        return HomeWidgets.section2(
          slides: c.slides,
          hideWhenEmpty: c.hideWhenEmpty,
          bottomSpacing: c.bottomSpacing,
        );
      }
      if (c is HomeSection3Chunk) {
        return HomeWidgets.section3(
          header: c.header,
          friends: c.friends,
          hideWhenEmpty: c.hideWhenEmpty,
          onAddFriendTap: c.onAddFriendTap,
          emptyMessage: c.emptyMessage,
          bottomSpacing: c.bottomSpacing,
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }

  Widget _buildGridSection() {
    // 빈 기여도 데이터 생성 (포스트 로딩 제거됨)
    final contributions = _generateContributionsFromPosts();

    return SafeArea(
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // AppBar
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            pinned: false,
            floating: true,
            snap: false,
            title: Container(
              padding: const EdgeInsets.only(bottom: 6, left: 6),
              child: Text(
                '',
                style: GoogleFonts.notoSansKr(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              // 연도 선택 버튼
              if (_selectedYear != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      _showYearPicker(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_selectedYear',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SizedBox(width: _selectedYear != null ? 0 : 12),
            ],
          ),

          // 환영 인사
          SliverToBoxAdapter(child: _buildWelcomeMessage(context)),
          // 잔디 심기 UI (이번주 친구글)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: WeeklyContributionGrid(
                year: _selectedYear ?? WeekUtils.getCurrentYear(),
                signupAt: _testSignupAt,
                asOf:
                    _isTestMode
                        ? (_testAsOf ?? DateTime.now())
                        : DateTime.now(),
                selectedWeek: _selectedWeek,
                onWeekSelected: _handleWeekSelected,
                contributions: _isTestMode ? _testContributions : contributions,
                onLongPress:
                    (year, weekNumber, position, cellCenter) =>
                        _handleWeekLongPress(year, weekNumber, position),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 50)),
          if (kDebugMode) SliverToBoxAdapter(child: _buildTestModeButtons()),

          // 🧪 디버그 모드: 빈 데이터 토글 버튼
          if (kDebugMode) SliverToBoxAdapter(child: _buildEmptyDataToggle()),

          // ====== 섹션 템플릿: HomeFeedService가 만든 청크를 렌더링 ======
          SliverToBoxAdapter(
            child: Column(children: _buildHomeFeedSectionWidgets()),
          ),
        ],
      ),
    );
  }

  /// 연도 선택 다이얼로그 표시
  void _showYearPicker(BuildContext context) {
    if (_selectedYear == null) return;

    final currentYear = WeekUtils.getCurrentYear();
    final selectedYear = _selectedYear ?? currentYear;
    final years = List.generate(
      5,
      (index) => currentYear - 2 + index,
    ); // 현재 연도 기준 ±2년

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '연도 선택',
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: years.length,
                itemBuilder: (context, index) {
                  final year = years[index];
                  final isSelected = year == selectedYear;
                  return ListTile(
                    title: Text(
                      '$year',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                        color:
                            isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    trailing:
                        isSelected
                            ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                            : null,
                    onTap: () {
                      // 연도 변경 시 주차 선택 초기화하고 콜백 호출
                      _handleWeekSelected(year, 0);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ),
    );
  }

  /// 환영 인사 메시지 위젯
  Widget _buildWelcomeMessage(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;

    // 사용자 이름 결정 (alias가 있으면 alias, 없으면 username)
    final displayName =
        currentUser?.alias?.isNotEmpty == true
            ? currentUser!.alias!
            : (currentUser?.username ?? '');

    // ✅ 로컬 시간대 사용 (미국/한국 등 사용자 위치에 따라 자동 적용)
    // DateTime.now()는 디바이스의 현재 로컬 시간대를 반환합니다.
    final now = DateTime.now();
    final seedSalt = (currentUser?.username ?? displayName).trim();
    final safeSeedSalt = seedSalt.isEmpty ? 'anon' : seedSalt;

    // ✅ 홈 텍스트는 "그리드 상태" 기반이므로, 포스트가 없어도 contributions에서 신호를 만든다.
    final contributionsForSignals =
        _isTestMode
            ? (_testContributions ?? const <WeeklyContributionData>[])
            : _generateContributionsFromPosts();
    final currentYW = WeekUtils.getCurrentYearAndWeek();
    final postsThisWeek = contributionsForSignals
        .where(
          (c) =>
              c.year == currentYW.year &&
              c.weekNumber == currentYW.weekNumber &&
              (c.postCount > 0),
        )
        .fold<int>(0, (acc, c) => acc + c.postCount);
    final totalPosts = contributionsForSignals.fold<int>(
      0,
      (acc, c) => acc + c.postCount,
    );
    final weeklyStreak = _computeWeeklyStreakFromContributions(
      contributionsForSignals,
      currentYW.year,
      currentYW.weekNumber,
    );

    final signals = HomeGreetingSignals(
      displayName: displayName,
      // 🎯 현재 User 모델에는 signupAt이 없어서, 테스트 모드에서만 주입
      signupAt: _isTestMode ? _testSignupAt : null,
      totalPosts: totalPosts,
      postsThisWeek: postsThisWeek,
      // 포스트 원본이 없어서 정확한 "마지막 작성일"은 계산 불가(필요해지면 week->date로 근사 가능)
      lastPostAt: null,
      // ✅ streakCount는 "연속 주(weekly streak)"로 사용
      streakCount: weeklyStreak,
      now: now, // 로컬 시간대 기준
      seedSalt: safeSeedSalt,
    );

    final msg = HomeGreetings.pick(signals);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: _buildTwoLineHomeGreeting(context, msg),
    );
  }

  Widget _buildTwoLineHomeGreeting(
    BuildContext context,
    HomeGreetingMessage msg,
  ) {
    final color = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ 폰트는 2가지만: 얇은 것(w300) 또는 볼드(w700)
    // ✅ 행간을 넓게 (1.4)로 여유 있게
    // ✅ Noto Sans KR은 한글+영어 모두 지원하지만, 영어는 Noto Sans가 더 최적화됨
    final line1Base = GoogleFonts.notoSansKr(
      fontSize: 28,
      fontWeight: FontWeight.w300, // 얇은 것
      letterSpacing: -1,
      height: 1.4, // 행간 넓게
      color: color.withOpacity(0.85),
    ).copyWith(
      fontFamilyFallback: ['Noto Sans'], // 영어 폴백
    );
    // ✅ 볼드를 더 두껍게: letterSpacing을 더 줄이고, textShadow 추가
    final line1Bold = GoogleFonts.notoSansKr(
      fontSize: 28,
      fontWeight: FontWeight.w900,
      letterSpacing: -2.5, // 더 가깝게 (두껍게 보이게)
      height: 1.4,
      color: color.withOpacity(0.85),
      shadows: [
        // 약간의 shadow로 두께감 추가
        Shadow(
          offset: const Offset(0, 0.5),
          blurRadius: 0,
          color: color.withOpacity(isDark ? 0.3 : 0.15),
        ),
      ],
    ).copyWith(
      fontFamilyFallback: ['Noto Sans'], // 영어 폴백
    );

    final line2Base = GoogleFonts.notoSansKr(
      fontSize: 28,
      fontWeight: FontWeight.w300, // 얇은 것
      letterSpacing: -1,
      height: 1.4, // 행간 넓게
      color: color,
    ).copyWith(
      fontFamilyFallback: ['Noto Sans'], // 영어 폴백
    );
    // ✅ 볼드를 더 두껍게: letterSpacing을 더 줄이고, textShadow 추가
    final line2Bold = GoogleFonts.notoSansKr(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -1, // 더 가깝게 (두껍게 보이게)
      height: 1.4,
      color: color,
      shadows: [
        // 약간의 shadow로 두께감 추가
        Shadow(
          offset: const Offset(0, 0.8),
          blurRadius: 0,
          color: color.withOpacity(isDark ? 0.3 : 0.15),
        ),
      ],
    ).copyWith(
      fontFamilyFallback: ['Noto Sans'], // 영어 폴백
    );

    List<TextSpan> buildSpans(
      List<HomeGreetingChunk> chunks,
      TextStyle base,
      TextStyle bold,
    ) {
      return chunks
          .map((c) => TextSpan(text: c.text, style: c.bold ? bold : base))
          .toList();
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          ...buildSpans(msg.line1, line1Base, line1Bold),
          const TextSpan(text: '\n'),
          ...buildSpans(msg.line2, line2Base, line2Bold),
        ],
      ),
    );
  }

  /// contributions 기반으로 "연속 주(weekly streak)" 계산
  /// - currentYear/currentWeek부터 과거로 거슬러가며, 해당 주에 postCount>0이면 연속 카운트
  int _computeWeeklyStreakFromContributions(
    List<WeeklyContributionData> contributions,
    int currentYear,
    int currentWeek,
  ) {
    final map = <int, int>{};
    for (final c in contributions) {
      if (c.postCount <= 0) continue;
      map[c.weekNumber] = (map[c.weekNumber] ?? 0) + c.postCount;
    }

    int streak = 0;
    for (int w = currentWeek; w >= 1; w--) {
      final has = (map[w] ?? 0) > 0;
      if (!has) break;
      streak++;
    }
    return streak;
  }

  /// 주차 길게 누르기 핸들러
  void _handleWeekLongPress(int year, int weekNumber, Offset? position) {
    if (weekNumber == 0) {
      _removeWeekPreview();
      return;
    }

    if (position == null) return;
    _showOrMoveWeekPreview(
      year: year,
      weekNumber: weekNumber,
      globalPosition: position,
    );
  }

  /// 주차 선택 핸들러
  void _handleWeekSelected(int year, int weekNumber) {
    debugPrint('[HomeScreen] _handleWeekSelected 호출: $year년 $weekNumber주차');

    // weekNumber가 0이면 연도만 변경
    if (weekNumber == 0) {
      debugPrint('[HomeScreen] weekNumber가 0이므로 연도만 변경');
      setState(() {
        _selectedYear = year;
        _selectedWeek = null; // 연도 변경 시 주차 선택 초기화
      });
      return;
    }

    // 롱프레스 프리뷰가 떠있으면 닫고 이동
    _removeWeekPreview();

    setState(() {
      _selectedYear = year;
      _selectedWeek = weekNumber;
    });

    // 포스트 로딩 제거 상태라서 일단 빈 리스트로 전달 (화면 구조만 먼저)
    final filteredPosts = <PostData>[];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => WeekPostListScreen(
              year: year,
              weekNumber: weekNumber,
              posts: filteredPosts,
            ),
      ),
    );
  }

  /// 🧪 디버그 모드: 빈 데이터 토글 버튼
  Widget _buildEmptyDataToggle() {
    if (!kDebugMode) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        border: Border(
          top: BorderSide(color: Colors.blue.withOpacity(0.2), width: 1),
          bottom: BorderSide(color: Colors.blue.withOpacity(0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.bug_report, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(
            '빈 데이터 토글',
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade700,
            ),
          ),
          const Spacer(),
          Switch(
            value: _showSampleData,
            onChanged: (value) {
              setState(() {
                _showSampleData = value;
              });
            },
            activeColor: Colors.blue.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            _showSampleData ? '샘플 데이터' : '빈 데이터',
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }

  /// 🧪 테스트 모드 버튼 UI (가로 스크롤 한 줄)
  Widget _buildTestModeButtons() {
    if (!kDebugMode) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        border: Border(
          top: BorderSide(color: Colors.orange.withOpacity(0.2), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더 (리셋 버튼 포함)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.bug_report, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text(
                  '테스트 모드',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
                const Spacer(),
                if (_isTestMode)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isTestMode = false;
                        _testSignupAt = null;
                        _testAsOf = null;
                        _testContributions = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '리셋',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 10,
                        color: Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 가로 스크롤 버튼 리스트
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildTestButton('1. 가입일 초반', () => _loadTestCase(1)),
                const SizedBox(width: 6),
                _buildTestButton('2. 가입일 중반', () => _loadTestCase(2)),
                const SizedBox(width: 6),
                _buildTestButton('3. 가입일 말', () => _loadTestCase(3)),
                const SizedBox(width: 6),
                _buildTestButton('4. 포스트 많음', () => _loadTestCase(4)),
                const SizedBox(width: 6),
                _buildTestButton('5. 포스트 적음', () => _loadTestCase(5)),
                const SizedBox(width: 6),
                _buildTestButton('6. 그라데이션', () => _loadTestCase(6)),
                const SizedBox(width: 6),
                _buildTestButton('7. 최소 2행', () => _loadTestCase(7)),
                const SizedBox(width: 6),
                _buildTestButton('8. 오늘+미리보기', () => _loadTestCase(8)),
                const SizedBox(width: 6),
                _buildTestButton('9. 연말(45셀)', () => _loadTestCase(9)),
                const SizedBox(width: 6),
                _buildTestButton('10. 연중반(30셀)', () => _loadTestCase(10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: Colors.orange.shade50,
        foregroundColor: Colors.orange.shade900,
        elevation: 0,
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.orange.shade200),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 🧪 테스트 케이스 로드 (통합 함수)
  void _loadTestCase(int caseNumber) {
    ({
      DateTime signupAt,
      DateTime asOf,
      List<WeeklyContributionData> contributions,
      int year,
    })
    testData;

    switch (caseNumber) {
      case 1:
        testData = WeeklyContributionTestData.generateTestCase1();
        break;
      case 2:
        testData = WeeklyContributionTestData.generateTestCase2();
        break;
      case 3:
        testData = WeeklyContributionTestData.generateTestCase3();
        break;
      case 4:
        testData = WeeklyContributionTestData.generateTestCase4();
        break;
      case 5:
        testData = WeeklyContributionTestData.generateTestCase5();
        break;
      case 6:
        testData = WeeklyContributionTestData.generateTestCase6();
        break;
      case 7:
        testData = WeeklyContributionTestData.generateTestCase7();
        break;
      case 8:
        testData = WeeklyContributionTestData.generateTestCase8();
        break;
      case 9:
        testData = WeeklyContributionTestData.generateTestCase9();
        break;
      case 10:
        testData = WeeklyContributionTestData.generateTestCase10();
        break;
      default:
        return;
    }

    setState(() {
      _isTestMode = true;
      _testSignupAt = testData.signupAt;
      _testAsOf = testData.asOf;
      _testContributions = testData.contributions;
      _selectedYear = testData.year;
    });
  }

  /// 기존 포스트 데이터를 분석하여 주차별 기여도 데이터 생성
  List<WeeklyContributionData> _generateContributionsFromPosts() {
    // 포스트 로딩 제거됨 - 빈 리스트 반환
    final year = _selectedYear ?? WeekUtils.getCurrentYear();
    final totalWeeks = WeekUtils.getWeeksInYear(year);
    final contributions = <WeeklyContributionData>[];

    // 모든 주차에 대해 빈 데이터 생성
    for (int week = 1; week <= totalWeeks; week++) {
      contributions.add(
        WeeklyContributionData(
          year: year,
          weekNumber: week,
          hasPost: false,
          postCount: 0,
        ),
      );
    }

    return contributions;
  }
}
