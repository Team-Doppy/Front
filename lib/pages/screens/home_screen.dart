import 'package:doppy/pages/components/week_long_press_preview.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';
import 'package:doppy/pages/components/home_widgets.dart';
import 'package:doppy/pages/screens/week_post_list_screen.dart';
import 'package:doppy/pages/screens/date_picker_screen.dart';
import 'package:doppy/data/models/weekly_contribution_greeting.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/providers/weekly_contribution_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/editor/postwrite_screen.dart';
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
  bool _isDraggingPreview = false; // 🎯 드래그 중인지 여부
  late AnimationController _previewAnimationController;
  late Animation<double> _previewScaleAnimation;

  bool _isTestMode = false; // 테스트 모드 활성화 여부
  DateTime? _testSignupAt; // 테스트용 가입일
  DateTime? _testAsOf; // 테스트용 기준일(asOf) - 행 수를 늘리려면 필수
  List<WeeklyContributionData>? _testContributions; // 테스트용 기여도 데이터

  // 디버그 모드: 샘플 데이터 표시 여부 (빈 데이터 토글용)
  // ignore: unused_field
  bool _showSampleData = true;

  // ✅ 디버그용: 코치마크 리스타트마다 표시 (플래그 제거)

  // ✅ 코치마크: 첫 회원가입 후 온보딩 완료 → 첫 홈 진입에서만 1회 표시
  // 서버의 onboardingCompleted 값(명시적으로 false)만으로 트리거한다.
  bool _coachmarkStartScheduled = false;
  int _coachmarkStartNonce = 0;

  // ✅ "글 쓰자마자" 홈 인삿말 보상 스왑을 위한 로컬 오버라이드
  // - 현재 서버/포스트 로딩이 비어있는 상태에서도, 방금 작성한 주차는 즉시 채워진 것으로 처리
  // - 앱이 종료될 때까지 보상 멘트 유지
  final Map<int, Map<int, int>> _localWeekPostOverrides = {};

  // ✅ "글 쓰자마자" 그리팅(클라이언트 전용) 컨텍스트
  PostPublishContext? _postPublishContext;
  int? _lastPublishedYear;
  int? _lastPublishedWeek;

  PostPublishContext? _effectivePostPublishContext() {
    final ctx = _postPublishContext;
    if (ctx == null) return null;

    // ✅ "방금 쓴 보상 멘트"는 현재 연도/현재 주차에서만 보여준다.
    final now = DateTime.now();
    final currentYear = WeekUtils.getCurrentYear();
    final currentWeek = WeekUtils.getWeekNumber(now);
    final selectedYear = _selectedYear ?? currentYear;

    if (selectedYear != currentYear) return null;
    if (_lastPublishedYear != currentYear) return null;
    if (_lastPublishedWeek != currentWeek) return null;
    return ctx;
  }

  @override
  void initState() {
    super.initState();

    // ✅ 코치마크는 build에서 Consumer<UserProvider>로 실시간 체크

    // 미리보기 애니메이션 컨트롤러 초기화
    _previewAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _previewScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _previewAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    // 초기 연도 설정
    _selectedYear = WeekUtils.getCurrentYear();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<WeeklyContributionProvider>();

      // 선택된 연도가 현재 연도가 아니고, 아직 로드되지 않았으면 로드
      final currentYear = WeekUtils.getCurrentYear();
      if (_selectedYear != currentYear) {
        final contributions = provider.getContributions(_selectedYear!);
        if (contributions == null) {
          await provider.loadContributions(_selectedYear!);
        }
      }
      // 현재 연도는 splash_screen에서 이미 로드됨

      // 총 포스트 개수가 아직 설정되지 않았으면 다시 시도
      if (provider.totalPostCount == 0) {
        final feedProvider = context.read<MyProfileFeedProvider>();
        final userInfo = feedProvider.userInfo;
        if (userInfo != null && userInfo.containsKey('totalPosts')) {
          final totalPosts = userInfo['totalPosts'] as int?;
          if (totalPosts != null) {
            provider.setTotalPostCount(totalPosts);
          } else {
            // totalPosts가 null이면 BaseFeedProvider의 totalPostCount 사용
            final totalPostCount = feedProvider.totalPostCount;
            if (totalPostCount > 0) {
              provider.setTotalPostCount(totalPostCount);
            }
          }
        }
      }

      // 포스트 발행 시 콜백 등록
      provider.onPostRegister = () async {
        // 서버에서 최신 총 포스트 개수 동기화
        try {
          final feedProvider = context.read<MyProfileFeedProvider>();
          await feedProvider.refresh();
          final userInfo = feedProvider.userInfo;
          if (userInfo != null && userInfo.containsKey('totalPosts')) {
            final totalPosts = userInfo['totalPosts'] as int?;
            if (totalPosts != null) {
              provider.setTotalPostCount(totalPosts);
            } else {
              // totalPosts가 null이면 BaseFeedProvider의 totalPostCount 사용
              final totalPostCount = feedProvider.totalPostCount;
              if (totalPostCount > 0) {
                provider.setTotalPostCount(totalPostCount);
              }
            }
          }
        } catch (e) {
          // 동기화 실패 시 무시
        }
      };
    });
  }

  void _maybeScheduleCoachmarkStart({
    required WeeklyContributionProvider contributionProvider,
    required UserProvider userProvider,
    required int currentYear,
  }) {
    if (!mounted) return;
    if (_isTestMode) return;
    if (_coachmarkStartScheduled) return;

    // ✅ 새로 가입한 사용자의 경우 onboardingCompleted가 null 또는 false일 수 있다.
    // - null: 서버에서 아직 설정되지 않음 (새로 가입한 사용자)
    // - false: 명시적으로 false로 설정됨
    // - true: 이미 온보딩을 완료한 사용자 (코치마크 스킵)
    final completed = userProvider.onboardingCompleted;
    debugPrint('[HomeScreen] 코치마크 체크: onboardingCompleted=$completed');

    // ✅ true가 아닐 때만 코치마크 시작 (null 또는 false)
    if (completed == true) {
      debugPrint('[HomeScreen] 코치마크 스킵: onboardingCompleted=true (이미 완료)');
      return;
    }

    // ✅ null인 경우는 서버 데이터가 아직 로드되지 않았을 수 있으므로
    // UserProvider의 currentUser가 있는지 확인
    if (completed == null && userProvider.currentUser == null) {
      debugPrint('[HomeScreen] 코치마크 스킵: currentUser가 null (아직 로드 중)');
      return;
    }

    // 코치마크는 현재 연도 홈에서만
    if (currentYear != WeekUtils.getCurrentYear()) {
      debugPrint('[HomeScreen] 코치마크 스킵: 현재 연도가 아님 (currentYear=$currentYear)');
      return;
    }

    if (contributionProvider.showAnyOverlay) {
      debugPrint('[HomeScreen] 코치마크 스킵: 이미 오버레이 표시 중');
      return;
    }

    debugPrint('[HomeScreen] ✅ 코치마크 시작 예약 (onboardingCompleted=false)');
    _coachmarkStartScheduled = true;
    final int nonce = ++_coachmarkStartNonce;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ✅ build 중 setState 금지. 프레임 이후에만 시작 시도.
      if (!mounted || nonce != _coachmarkStartNonce) return;

      debugPrint('[HomeScreen] 코치마크 시작: 프레임 대기 시작');

      // 1) 레이아웃/키 등록이 끝날 때까지 명시적으로 대기
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || nonce != _coachmarkStartNonce) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || nonce != _coachmarkStartNonce) return;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || nonce != _coachmarkStartNonce) return;

      debugPrint('[HomeScreen] 코치마크 시작: 키/데이터 준비 확인 시작');

      // 2) 키/데이터 준비 확인 (명시적 재시도, 확률게임 X)
      const maxAttempts = 12;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted || nonce != _coachmarkStartNonce) return;

        final keys = contributionProvider.getWeekCellKeysForYear(currentYear);
        final hasKeys = keys.isNotEmpty;
        final hasData =
            contributionProvider.getContributions(currentYear) != null;

        debugPrint(
          '[HomeScreen] 코치마크 체크 (attempt ${attempt + 1}/$maxAttempts): hasKeys=$hasKeys, hasData=$hasData, showAnyOverlay=${contributionProvider.showAnyOverlay}',
        );

        if (hasKeys && hasData && !contributionProvider.showAnyOverlay) {
          debugPrint('[HomeScreen] ✅ 코치마크 시작!');
          contributionProvider.startWeeklyStreakCoachmark(
            year: currentYear,
            now: DateTime.now(),
          );

          // ✅ 코치마크 시작 후 서버에 onboardingCompleted 업데이트
          // ignore: discarded_futures
          _consumeOnboardingCoachmarkFlag();
          return;
        }

        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      debugPrint('[HomeScreen] ⚠️ 코치마크 시작 실패: 키/데이터 준비 안됨 (maxAttempts 도달)');

      // 실패했으면 다음 프레임에서 다시 시도할 수 있게 풀어둔다.
      if (mounted && nonce == _coachmarkStartNonce) {
        _coachmarkStartScheduled = false;
      }
    });
  }

  Future<void> _consumeOnboardingCoachmarkFlag() async {
    // ✅ 코치마크를 표시한 후에는 서버에 온보딩 완료 상태를 업데이트
    // 이렇게 하면 다음 번에는 코치마크가 표시되지 않음
    try {
      await UserService().updateOnboardingCompleted(onboardingCompleted: true);
      // UserProvider 메모리도 즉시 갱신
      if (mounted) {
        context.read<UserProvider>().setOnboardingCompleted(true);
      }
    } catch (e) {
      debugPrint('[HomeScreen] 온보딩 완료 업데이트 실패: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // ✅ 프리뷰 제거를 먼저 수행 (컨트롤러 dispose 전)
    _removeWeekPreview();
    _previewAnimationController.dispose();
    super.dispose();
  }

  void _removeWeekPreview() {
    // ✅ 컨트롤러가 이미 dispose되었거나 mounted가 아니면 바로 제거
    if (!mounted || !_previewAnimationController.isAnimating) {
      _weekPreviewEntry?.remove();
      _weekPreviewEntry = null;
      _weekPreviewWeek = null;
      _weekPreviewYear = null;
      return;
    }

    try {
      _previewAnimationController
          .reverse()
          .then((_) {
            if (mounted) {
              _weekPreviewEntry?.remove();
              _weekPreviewEntry = null;
              _weekPreviewWeek = null;
              _weekPreviewYear = null;
            }
          })
          .catchError((_) {
            // reverse 실패 시 바로 제거
            _weekPreviewEntry?.remove();
            _weekPreviewEntry = null;
            _weekPreviewWeek = null;
            _weekPreviewYear = null;
          });
    } catch (e) {
      // 컨트롤러가 이미 dispose된 경우 바로 제거
      _weekPreviewEntry?.remove();
      _weekPreviewEntry = null;
      _weekPreviewWeek = null;
      _weekPreviewYear = null;
    }
  }

  void _showOrMoveWeekPreview({
    required int year,
    required int weekNumber,
    required Offset globalPosition,
    bool isDragging = false, // 🎯 드래그 중인지 여부
  }) {
    _weekPreviewYear = year;
    _weekPreviewWeek = weekNumber;
    _weekPreviewPosition = globalPosition;
    _isDraggingPreview = isDragging;

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

          // 손가락 근처에 표시(약간 위로, 아래로 보정)
          double left = _weekPreviewPosition.dx - (cardW / 2);
          double top =
              _weekPreviewPosition.dy - cardH + 20; // 16 -> 8로 조정하여 아래로 보정

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
                  child:
                      _isDraggingPreview
                          ? WeekLongPressPreview(
                            key: ValueKey(
                              'preview-${_weekPreviewYear}-${_weekPreviewWeek}',
                            ),
                            weekNumber: _weekPreviewWeek ?? weekNumber,
                            year: _weekPreviewYear ?? year,
                          )
                          : ScaleTransition(
                            scale: _previewScaleAnimation,
                            alignment: Alignment.center,
                            child: WeekLongPressPreview(
                              key: ValueKey(
                                'preview-${_weekPreviewYear}-${_weekPreviewWeek}',
                              ), // 🎯 위젯 교체 시 애니메이션 재시작
                              weekNumber: _weekPreviewWeek ?? weekNumber,
                              year: _weekPreviewYear ?? year,
                            ),
                          ),
                ),
              ),
            ],
          );
        },
      );
      overlay.insert(_weekPreviewEntry!);
      // 애니메이션 시작 (드래그 중이 아닐 때만)
      if (!_isDraggingPreview) {
        _previewAnimationController.reset();
        _previewAnimationController.forward();
      } else {
        // 드래그 중이면 애니메이션을 완료 상태로 설정 (스케일 1.0)
        _previewAnimationController.value = 1.0;
      }
    } else {
      // 기존 오버레이가 있을 때
      // 🎯 위치는 항상 업데이트해야 하므로 markNeedsBuild 호출
      // 단, 같은 주차를 드래그하는 경우에는 위젯 교체 없이 위치만 업데이트
      final isSameWeek =
          _weekPreviewWeek == weekNumber && _weekPreviewYear == year;
      _weekPreviewEntry?.markNeedsBuild();

      if (!_isDraggingPreview) {
        // 드래그 중이 아니면 애니메이션 재시작 (위젯이 변경된 경우)
        if (!isSameWeek) {
          _previewAnimationController.reset();
          _previewAnimationController.forward();
        }
      } else {
        // 드래그 중이면 애니메이션을 완료 상태로 유지 (스케일 1.0)
        _previewAnimationController.value = 1.0;
      }
    }
  }

  /// 외부(발행 화면)에서 호출: 방금 게시된 글을 홈 그리드/인삿말에 즉시 반영
  void notifyPostPublished({DateTime? createdAt}) async {
    final when = (createdAt ?? DateTime.now());
    final year = _selectedYear ?? when.year;
    final weekNumber = WeekUtils.getWeekNumber(when);

    // ✅ 발행 직전 상태 기반으로 컨텍스트 결정 (로컬 기반)
    // - 이미 이번 주에 작성한 적 있으면: alreadyWrittenThisWeek
    // - 이번 주 첫 기록 + 주말이면: weekendClutch
    // - 이번 주 첫 기록(평일): firstWrittenThisWeek
    PostPublishContext nextContext = PostPublishContext.firstWrittenThisWeek;
    try {
      final provider = context.read<WeeklyContributionProvider>();
      final contributions = provider.getContributions(year);
      int existingCount = 0;
      if (contributions != null) {
        final idx = contributions.indexWhere((c) => c.weekNumber == weekNumber);
        if (idx != -1) existingCount = contributions[idx].postCount;
      }
      final overrideCount = _localWeekPostOverrides[year]?[weekNumber] ?? 0;
      final totalBefore = existingCount + overrideCount;
      if (totalBefore > 0) {
        nextContext = PostPublishContext.alreadyWrittenThisWeek;
      } else {
        final isWeekend =
            when.weekday == DateTime.saturday ||
            when.weekday == DateTime.sunday;
        nextContext =
            isWeekend
                ? PostPublishContext.weekendClutch
                : PostPublishContext.firstWrittenThisWeek;
      }
    } catch (_) {}

    setState(() {
      final byWeek = _localWeekPostOverrides.putIfAbsent(year, () => {});
      byWeek[weekNumber] = (byWeek[weekNumber] ?? 0) + 1;
      _postPublishContext = nextContext;
      _lastPublishedYear = year;
      _lastPublishedWeek = weekNumber;
    });

    // 프로바이더 상태 갱신 (즉시 로컬 업데이트 + 백그라운드 서버 동기화)
    final provider = context.read<WeeklyContributionProvider>();
    await provider.refreshAfterPostPublished(
      year,
      weekNumber: weekNumber,
      optimisticUpdate: true, // 즉시 로컬 업데이트
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildGridSection();
  }

  Widget _buildGridSection() {
    return SafeArea(
      child: CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
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

          // ✅ isLocked에 따라 조건부 UI 표시
          Consumer2<WeeklyContributionProvider, UserProvider>(
            builder: (context, contributionProvider, userProvider, _) {
              final isLocked = contributionProvider.isLocked;
              // 🎯 전해로 갈 때는 무조건 _selectedYear 사용 (null이 아니면)
              final currentYear = _selectedYear ?? WeekUtils.getCurrentYear();
              final contributions = _isTestMode ? _testContributions : null;

              // ✅ 코치마크 시작 조건 체크 (빌드 중 setState 금지)
              _maybeScheduleCoachmarkStart(
                contributionProvider: contributionProvider,
                userProvider: userProvider,
                currentYear: currentYear,
              );

              if (isLocked) {
                // 락용 UI
                return SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // 락용 메인 위젯
                      LockedHomeWidget(
                        year: currentYear, // 🎯 _selectedYear가 있으면 전해로 이동
                        signupAt: _testSignupAt,
                        asOf:
                            _isTestMode
                                ? (_testAsOf ?? DateTime.now())
                                : DateTime.now(),
                        selectedWeek: _selectedWeek,
                        onWeekSelected: _handleWeekSelected,
                        onWeekLongPress: _handleWeekLongPress,
                        postPublishContext: _effectivePostPublishContext(),
                      ),
                      const SizedBox(height: 50),
                    ],
                  ),
                );
              } else {
                // 언락용 UI
                final actualContributions =
                    contributions ??
                    contributionProvider.getContributions(currentYear);
                return SliverToBoxAdapter(
                  child: UnlockedHomeWidget(
                    year: currentYear, // 🎯 _selectedYear가 있으면 전해로 이동
                    signupAt: _testSignupAt,
                    asOf:
                        _isTestMode
                            ? (_testAsOf ?? DateTime.now())
                            : DateTime.now(),
                    selectedWeek: _selectedWeek,
                    onWeekSelected: _handleWeekSelected,
                    onWeekLongPress: _handleWeekLongPress,
                    contributions: actualContributions,
                    isLoading:
                        _isTestMode
                            ? false
                            : contributionProvider.isLoading(currentYear),
                    greeting: contributionProvider.getGreeting(currentYear),
                    postPublishContext: _effectivePostPublishContext(),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// 연도 선택 UI 표시
  void _showYearPicker(BuildContext context) {
    if (_selectedYear == null) return;

    final weeklyProvider = context.read<WeeklyContributionProvider>();

    final currentYear = WeekUtils.getCurrentYear();
    final selectedYear = _selectedYear ?? currentYear;
    // 2025년부터 현재 연도까지
    final startYear = 2025;
    final years = List.generate(
      currentYear - startYear + 1,
      (index) => startYear + index,
    );

    // Provider에 연도 선택 UI 표시 요청
    weeklyProvider.showYearPicker(
      selectedYear: selectedYear,
      years: years,
      onConfirm: (year) {
        // 연도 변경 시 주차 선택 초기화하고 콜백 호출
        _handleWeekSelected(year, 0);
        weeklyProvider.closeYearPicker();
      },
    );
  }

  /// 주차 길게 누르기 핸들러
  void _handleWeekLongPress(
    int year,
    int weekNumber,
    Offset? position, [
    Offset? cellCenter,
  ]) {
    if (weekNumber == 0) {
      _removeWeekPreview();
      return;
    }

    if (position == null) return;

    // 🎯 onLongPressMoveUpdate에서 호출된 경우 (드래그 중)
    // - 기존 오버레이가 있고, 같은 주차를 드래그하는 경우
    final isDragging =
        _weekPreviewEntry != null &&
        _weekPreviewWeek == weekNumber &&
        _weekPreviewYear == year;

    _showOrMoveWeekPreview(
      year: year,
      weekNumber: weekNumber,
      globalPosition: position,
      isDragging: isDragging,
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
      // ✅ 연도 변경 시: 항상 서버에서 새로 로드
      final provider = context.read<WeeklyContributionProvider>();
      provider.reloadContributions(year);
      return;
    }

    // 롱프레스 프리뷰가 떠있으면 닫고 이동
    _removeWeekPreview();

    setState(() {
      _selectedYear = year;
      _selectedWeek = weekNumber;
    });

    // 🎯 미래 주차 클릭 시: 조용히 무시 (스낵바 없이)
    final currentYear = WeekUtils.getCurrentYear();
    final currentWeek = WeekUtils.getWeekNumber(DateTime.now());
    final isFutureWeek =
        (year > currentYear) ||
        (year == currentYear && weekNumber > currentWeek);

    if (isFutureWeek) {
      debugPrint('[HomeScreen] 미래 주차($year년 $weekNumber주차) 클릭 → 무시');
      return;
    }

    // ✅ 최우선: postCount > 0이면 무조건 주차 조회 화면으로 이동
    final provider = context.read<WeeklyContributionProvider>();
    final contributions = provider.getContributions(year);
    int postCount = 0;
    if (contributions != null) {
      final weekData = contributions.firstWhere(
        (c) => c.weekNumber == weekNumber,
        orElse:
            () => WeeklyContributionData(
              year: year,
              weekNumber: weekNumber,
              hasPost: false,
              postCount: 0,
            ),
      );
      postCount = weekData.postCount;
    }

    if (postCount > 0) {
      debugPrint(
        '[HomeScreen] 주차($year년 $weekNumber주차)에 포스트 있음 → WeekPostListScreen으로 이동',
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) =>
                  WeekPostListScreen(year: year, weekNumber: weekNumber),
        ),
      );
      return;
    }

    // 🎯 오늘 주차이고 포스트가 없는 경우 → PostwriteScreen으로 이동
    final isTodayWeek = year == currentYear && weekNumber == currentWeek;

    if (isTodayWeek) {
      debugPrint(
        '[HomeScreen] 오늘 주차($weekNumber) 빈 셀 클릭 → PostwriteScreen으로 이동',
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PostwriteScreen(isEditingMode: false),
        ),
      );
      return;
    }

    // 🎯 최후순위: 지나간 주차 클릭 시: 가입 후 7일 이내이면 DatePickerScreen으로 이동
    final isPastWeek =
        (year < currentYear) ||
        (year == currentYear && weekNumber < currentWeek);

    if (isPastWeek) {
      final userProvider = context.read<UserProvider>();
      final createdAt = userProvider.createdAt;

      // 가입 후 7일 이내인지 확인
      if (WeekUtils.isWithin7DaysAfterSignup(createdAt)) {
        debugPrint(
          '[HomeScreen] 지나간 주차($year년 $weekNumber주차) 빈 셀 클릭 → DatePickerScreen으로 이동 (7일 이내, 최후순위)',
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => DatePickerScreen(
                  initialYear: year,
                  initialWeek: weekNumber,
                  createdAt: createdAt,
                ),
          ),
        );
        return;
      }
    }

    // ✅ 포스트가 없는 경우에도 WeekPostListScreen으로 이동 (빈 리스트 표시)
    debugPrint(
      '[HomeScreen] 주차($year년 $weekNumber주차) 빈 셀 클릭 → WeekPostListScreen으로 이동',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => WeekPostListScreen(year: year, weekNumber: weekNumber),
      ),
    );
  }
}
