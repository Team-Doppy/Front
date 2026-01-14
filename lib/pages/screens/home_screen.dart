import 'dart:ui';
import 'package:doppy/pages/components/card_view.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/blur_overlay_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final HomeData? preloadedHomeData;
  final bool isActive; // 현재 탭이 활성 상태인지
  final Function(String?)? onOpenSearchScreen; // 검색 화면 열기 콜백 (검색어 전달)

  const HomeScreen({
    super.key,
    this.preloadedHomeData,
    this.isActive = true,
    this.onOpenSearchScreen,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final HomeDataService _homeDataService = HomeDataService();
  final ScrollController _scrollController = ScrollController();

  // 🎯 포그라운드 복귀 시 새로고침을 위한 GlobalKey
  static final GlobalKey<HomeScreenState> globalKey =
      GlobalKey<HomeScreenState>();

  // 통합 포스트 리스트 (친구글 먼저, 추천글 뒤에)
  List<PostData> _allPosts = [];
  bool _allIsLoading = true;
  bool _allIsLoadingMore = false;
  NetworkError? _allError;
  bool _allIsRetrying = false;
  int _friendsCurrentPage = 0; // 친구글 페이지
  int _recommendedCurrentPage = 0; // 추천글 페이지
  bool _friendsHasMoreData = true;
  bool _recommendedHasMoreData = true;
  int _allLoadTick = 0;
  bool _friendsLoaded = false; // 친구글 로드 완료 여부
  StreamSubscription<dynamic>? _networkSub;
  bool _refreshInProgress = false;

  // 잔디 심기 UI 관련 상태
  int? _selectedYear; // 선택된 연도
  int? _selectedWeek; // 선택된 주차

  // 길게 누르기 미리보기 관련 상태
  int? _longPressedWeek; // 길게 누른 주차 (로컬 추적용)
  late final AnimationController _previewAnimationController;

  @override
  void initState() {
    super.initState();

    // 스플래시에서 전달된 선로딩 데이터 반영
    if (widget.preloadedHomeData != null) {
      final homeData = widget.preloadedHomeData!;

      // 친구글과 추천글을 합쳐서 단일 리스트로 구성
      final combinedPosts = <PostData>[
        ...homeData.friendsPosts,
        ...homeData.allPosts,
      ];

      _allPosts = List<PostData>.from(combinedPosts);
      _allIsLoading = false;
      _friendsHasMoreData = homeData.friendsPosts.length == 20;
      _recommendedHasMoreData = homeData.allPosts.length == 20;
      _friendsCurrentPage = homeData.friendsPosts.isNotEmpty ? 1 : 0;
      _recommendedCurrentPage = homeData.allPosts.isNotEmpty ? 1 : 0;
      _friendsLoaded = true; // 스플래시에서 로드했으므로 완료로 표시
    }

    // 초기 연도 설정
    _selectedYear = WeekUtils.getCurrentYear();

    // 미리보기 애니메이션 컨트롤러 초기화
    _previewAnimationController = AnimationController(
      duration: const Duration(milliseconds: 150), // 🎯 300ms → 150ms로 빠르게
      vsync: this,
    );

    // 네트워크 에러는 API 요청 시점에서만 처리

    // 백그라운드에서 필요한 데이터 로드 (인스타그램 방식)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 네트워크 복구 시 자동 새로고침 (단발 락)
      _networkSub?.cancel();
      _networkSub = NetworkManager.onConnectivityChanged.listen((
        dynamic v,
      ) async {
        final bool isOnline = v == true;
        if (!mounted || !isOnline) return;
        if (_refreshInProgress) return;
        _refreshInProgress = true;
        try {
          if (_allPosts.isEmpty) {
            await _loadAllPosts(refresh: true);
          }
        } catch (_) {
        } finally {
          _refreshInProgress = false;
        }
      });

      _loadProfileSafely();

      // 초기 로드: 친구글 먼저, 그 다음 추천글 자동 로드
      if (_allPosts.isEmpty && !_allIsLoading) {
        _loadAllPosts(refresh: false);
      }

      // 스크롤 리스너 추가 (무한 스크롤)
      _scrollController.addListener(_onScroll);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_allIsLoadingMore &&
          (_friendsHasMoreData || _recommendedHasMoreData)) {
        _loadMoreAllPosts();
      }
    }
  }

  @override
  void dispose() {
    // 네트워크 구독 취소
    _networkSub?.cancel();
    _scrollController.dispose();
    _previewAnimationController.dispose();
    super.dispose();
  }

  void _resetAllFeed({bool showLoading = true}) {
    setState(() {
      _allPosts = [];
      _friendsCurrentPage = 0;
      _recommendedCurrentPage = 0;
      _friendsHasMoreData = true;
      _recommendedHasMoreData = true;
      _allIsLoading = showLoading;
      _allIsLoadingMore = false;
      _allError = null;
      _friendsLoaded = false; // 새로고침 시 친구글부터 다시 로드
    });
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

  Future<void> _retryAllPosts() async {
    setState(() {
      _allIsRetrying = true;
      _allError = null; // 에러 상태만 클리어 (데이터는 유지)
    });

    try {
      // refresh=false로 호출해서 reset하지 않음
      await _loadAllPosts(refresh: false);
      // 재시도 후 0.5초 딜레이
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      setState(() {
        _allIsRetrying = false;
      });
    }
  }

  Future<void> _loadAllPosts({bool refresh = false}) async {
    debugPrint(
      '[HomeScreen] _loadAllPosts 시작 - refresh: $refresh, 현재 데이터: ${_allPosts.length}개, 친구글 로드 완료: $_friendsLoaded',
    );

    try {
      if (refresh) {
        _resetAllFeed(showLoading: true);
      } else if (!_allIsRetrying) {
        // 재시도 중이 아닐 때만 로딩 상태 변경
        setState(() {
          _allIsLoading = _allPosts.isEmpty;
          _allError = null;
        });
      }

      final int token = ++_allLoadTick;

      // 친구글을 아직 로드하지 않았으면 먼저 로드
      if (!_friendsLoaded) {
        try {
          final friendsPosts = await _homeDataService.loadFriendsPosts(
            page: _friendsCurrentPage,
            size: 20,
            refresh: refresh,
          );

          if (token != _allLoadTick) return;

          // 🎯 이미지 프리캐싱: 친구글은 처음 3개만 동기
          if (friendsPosts.isNotEmpty) {
            if (refresh || _allPosts.isEmpty) {
              await _homeDataService.precacheImages(
                friendsPosts,
                context,
                syncCount: 3,
                preloadVideos: false,
              );
            } else {
              _homeDataService.precacheImages(
                friendsPosts,
                context,
                syncCount: 0,
                preloadVideos: false,
              );
            }
          }

          setState(() {
            if (refresh) {
              _allPosts = friendsPosts;
            } else {
              _allPosts.addAll(friendsPosts);
            }
            _friendsHasMoreData = friendsPosts.length == 20;
            _friendsCurrentPage++;
            _friendsLoaded = true;
          });

          debugPrint(
            '[HomeScreen] 친구글 로드 성공: ${friendsPosts.length}개 (페이지 ${_friendsCurrentPage - 1})',
          );
        } catch (e) {
          final networkError = NetworkUtils.parseError(e);
          debugPrint('[HomeScreen] 친구글 로드 실패: ${networkError.message}');

          // 친구글 로드 실패해도 추천글은 시도
          setState(() {
            _friendsLoaded = true; // 실패해도 다음 단계로 진행
          });
        }
      }

      // 추천글 로드 (친구글 로드 완료 후 또는 친구글이 없을 때)
      if (_friendsLoaded && _recommendedHasMoreData) {
        try {
          final recommendedPosts = await _homeDataService.loadAllPosts(
            page: refresh ? 0 : _recommendedCurrentPage, // 새로고침 시 페이지 0부터
            size: 20,
            refresh: refresh, // 새로고침 시 추천글도 새로고침
          );

          if (token != _allLoadTick) return;

          // 🎯 이미지 프리캐싱: 추천글은 모두 비동기로 처리
          if (recommendedPosts.isNotEmpty) {
            _homeDataService.precacheImages(
              recommendedPosts,
              context,
              syncCount: 0,
            );
          }

          setState(() {
            _allPosts.addAll(recommendedPosts);
            _recommendedHasMoreData = recommendedPosts.length == 20;
            _recommendedCurrentPage++;
          });

          debugPrint(
            '[HomeScreen] 추천글 로드 성공: ${recommendedPosts.length}개 (페이지 ${_recommendedCurrentPage - 1})',
          );
        } catch (e) {
          final networkError = NetworkUtils.parseError(e);
          debugPrint('[HomeScreen] 추천글 로드 실패: ${networkError.message}');

          setState(() {
            _recommendedHasMoreData = false;
          });
        }
      }

      if (token != _allLoadTick) return;

      setState(() {
        _allIsLoading = false;
        _allIsLoadingMore = false;
        _allError = null; // 성공 시 에러 클리어
      });

      debugPrint(
        '[HomeScreen] 전체 로드 완료: 총 ${_allPosts.length}개 (친구글: ${_friendsCurrentPage > 0 ? _friendsCurrentPage * 20 : 0}개, 추천글: ${_recommendedCurrentPage > 0 ? _recommendedCurrentPage * 20 : 0}개)',
      );
    } catch (e) {
      final networkError = NetworkUtils.parseError(e);
      debugPrint('[HomeScreen] 전체 로드 실패: ${networkError.message}');

      setState(() {
        _allError = networkError;
        _allIsLoading = false;
        _allIsLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreAllPosts() async {
    if (_allIsLoadingMore) return;

    // 친구글과 추천글 중 하나라도 더 로드할 데이터가 있으면 진행
    if (!_friendsHasMoreData && !_recommendedHasMoreData) return;

    setState(() {
      _allIsLoadingMore = true;
    });

    // 친구글이 더 있으면 친구글부터, 없으면 추천글만
    if (_friendsHasMoreData) {
      try {
        final friendsPosts = await _homeDataService.loadFriendsPosts(
          page: _friendsCurrentPage,
          size: 20,
          refresh: false,
        );

        if (friendsPosts.isNotEmpty) {
          _homeDataService.precacheImages(
            friendsPosts,
            context,
            syncCount: 0,
            preloadVideos: false,
          );
        }

        setState(() {
          _allPosts.addAll(friendsPosts);
          _friendsHasMoreData = friendsPosts.length == 20;
          _friendsCurrentPage++;
        });

        debugPrint('[HomeScreen] 친구글 추가 로드: ${friendsPosts.length}개');
      } catch (e) {
        debugPrint('[HomeScreen] 친구글 추가 로드 실패: $e');
        setState(() {
          _friendsHasMoreData = false;
        });
      }
    }

    // 추천글 로드
    if (_recommendedHasMoreData) {
      try {
        final recommendedPosts = await _homeDataService.loadAllPosts(
          page: _recommendedCurrentPage,
          size: 20,
          refresh: false,
        );

        if (recommendedPosts.isNotEmpty) {
          _homeDataService.precacheImages(
            recommendedPosts,
            context,
            syncCount: 0,
          );
        }

        setState(() {
          _allPosts.addAll(recommendedPosts);
          _recommendedHasMoreData = recommendedPosts.length == 20;
          _recommendedCurrentPage++;
        });

        debugPrint('[HomeScreen] 추천글 추가 로드: ${recommendedPosts.length}개');
      } catch (e) {
        debugPrint('[HomeScreen] 추천글 추가 로드 실패: $e');
        setState(() {
          _recommendedHasMoreData = false;
        });
      }
    }

    setState(() {
      _allIsLoadingMore = false;
    });
  }

  Widget _buildDynamicBackground() {
    // 단색 배경으로 단순화
    return Positioned.fill(
      child: Container(color: Theme.of(context).colorScheme.background),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        _buildDynamicBackground(),
        _buildContent(screenWidth),
        // 길게 누르기 미리보기 오버레이는 이제 RootShell에서 전역으로 처리
      ],
    );
  }

  Widget _buildContent(double screenWidth) {
    // 단일 PostList로 통합 (친구글 + 추천글)
    return _buildAllPostsSection(screenWidth);
  }

  Widget _buildAllPostsSection(double screenWidth) {
    // 에러 상태 표시 (재시도 중이거나 에러가 있고 데이터가 비어있을 때)
    if ((_allError != null || _allIsRetrying) &&
        _allPosts.isEmpty &&
        !_allIsLoading) {
      return ErrorStateWidget(
        error:
            _allError ??
            NetworkError(
              type: NetworkErrorType.noConnection,
              message: '오프라인 상태에요!',
              userMessage: '오프라인 상태에요!',
              isRetryable: true,
            ),
        onRetry: _retryAllPosts,
        customTitle: '포스트를 불러올 수 없습니다',
        isRetrying: _allIsRetrying,
      );
    }

    // 기존 포스트 데이터를 분석하여 주차별 기여도 데이터 생성
    final contributions = _generateContributionsFromPosts();

    // 필터링된 포스트 리스트 (주차 선택 시)
    List<PostData> filteredPosts = _allPosts;
    if (_selectedYear != null && _selectedWeek != null) {
      filteredPosts =
          _allPosts.where((post) {
            try {
              final postDate = DateTime.parse(post.createdAt);
              final (
                year: postYear,
                weekNumber: postWeek,
              ) = WeekUtils.getYearAndWeekFromUtc(postDate);
              return postYear == _selectedYear && postWeek == _selectedWeek;
            } catch (e) {
              return false;
            }
          }).toList();
    }

    // 최대 5개까지만 표시
    final displayedPosts = filteredPosts.take(5).toList();

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
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: WeeklyContributionGrid(
                year: _selectedYear ?? WeekUtils.getCurrentYear(),
                selectedWeek: _selectedWeek,
                onWeekSelected: _handleWeekSelected,
                contributions: contributions,
                onLongPress:
                    (year, weekNumber, position, cellCenter) =>
                        _handleWeekLongPress(year, weekNumber, position),
              ),
            ),
          ),

          // 섹션 헤더: 친구들 도피 (포스트가 있거나 로딩 중일 때만 표시)
          if (!displayedPosts.isEmpty || _allIsLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text(
                  '친구들 도피',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),

          // 포스트 리스트
          if (_allIsLoading && displayedPosts.isEmpty)
            // 로딩 중
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 3,
                      ),
                      height: 125,
                      child: Row(
                        children: [
                          // 썸네일 Shimmer
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Container(
                              width: 140,
                              height: 125,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surface.withOpacity(0.1),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 텍스트 영역 Shimmer
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: screenWidth * 0.4,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: 80,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: screenWidth * 0.3,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }, childCount: 5),
              ),
            )
          else if (displayedPosts.isEmpty)
            // 빈 상태
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '포스트가 없습니다',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            // 카드뷰 리스트 (최대 5개)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index >= displayedPosts.length) {
                    return const SizedBox.shrink();
                  }

                  final post = displayedPosts[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => PostReaderScreen(
                                  exported: post.toExportedData(),
                                  heroTag: 'home-post-${post.id}-$index',
                                ),
                          ),
                        );
                      },
                      child: CardView(
                        post: post,
                        isLast: index == displayedPosts.length - 1,
                      ),
                    ),
                  );
                }, childCount: displayedPosts.length),
              ),
            ),

          // 하단 여백
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
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

    // 시간대별 인사말
    final hour = DateTime.now().hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = '좋은 아침이에요';
    } else if (hour >= 12 && hour < 18) {
      greeting = '안녕하세요';
    } else if (hour >= 18 && hour < 22) {
      greeting = '좋은 저녁이에요';
    } else {
      greeting = '안녕하세요';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (displayName.isNotEmpty)
            RichText(
              text: TextSpan(
                style: GoogleFonts.notoSansKr(
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                children: [
                  TextSpan(text: '$greeting,\n'),
                  TextSpan(
                    text: displayName,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              greeting,
              style: GoogleFonts.notoSansKr(
                fontSize: 40,
                fontWeight: FontWeight.w300,
                letterSpacing: -0.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  /// 주차 길게 누르기 핸들러
  void _handleWeekLongPress(int year, int weekNumber, Offset? position) {
    final blurProvider = context.read<BlurOverlayProvider>();

    if (weekNumber == 0) {
      // 종료: 애니메이션 역재생 후 상태 초기화
      // 🎯 weekPostList 타입일 때는 hideBlurOverlay 호출하지 않음 (탭으로 열린 경우)
      // 🎯 또는 _longPressedWeek가 null이면 롱프레스가 시작되지 않은 것이므로 무시
      if (blurProvider.overlayType == BlurOverlayType.weekPostList ||
          _longPressedWeek == null) {
        debugPrint(
          '[HomeScreen] _handleWeekLongPress: weekNumber==0이지만 weekPostList 타입이거나 롱프레스가 시작되지 않았으므로 hideBlurOverlay 호출 안 함',
        );
        setState(() => _longPressedWeek = null);
        return;
      }

      debugPrint(
        '[HomeScreen] _handleWeekLongPress: weekNumber==0, hideBlurOverlay 호출',
      );
      _previewAnimationController.reverse().then((_) {
        if (mounted) {
          blurProvider.hideBlurOverlay();
          setState(() => _longPressedWeek = null);
        }
      });
      return;
    }

    // 시작 또는 위치 업데이트
    if (_longPressedWeek == null) {
      setState(() => _longPressedWeek = weekNumber);
      blurProvider.showBlurOverlay(
        year: year,
        weekNumber: weekNumber,
        position: position,
        controller: _previewAnimationController,
      );
      _previewAnimationController.forward();
    } else {
      blurProvider.updateBlurPosition(position);
    }
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

    // 해당 주차의 포스트 필터링 (포스트가 있든 없든 항상 블러 오버레이 표시)
    debugPrint('[HomeScreen] 포스트 필터링 시작: 전체 포스트 ${_allPosts.length}개');
    final filteredPosts =
        _allPosts.where((post) {
          try {
            final postDate = DateTime.parse(post.createdAt);
            final (
              year: postYear,
              weekNumber: postWeek,
            ) = WeekUtils.getYearAndWeekFromUtc(postDate);
            return postYear == year && postWeek == weekNumber;
          } catch (e) {
            return false;
          }
        }).toList();
    debugPrint('[HomeScreen] 필터링된 포스트: ${filteredPosts.length}개');

    // 블러 오버레이 표시 (포스트가 있든 없든 항상 표시)
    final blurProvider = context.read<BlurOverlayProvider>();

    // 🎯 단순화: 애니메이션 컨트롤러가 완료 상태면 리셋
    if (_previewAnimationController.isCompleted) {
      _previewAnimationController.reset();
    }

    // 🎯 상태 설정 및 애니메이션 시작을 한 번에
    blurProvider.showWeekPostListOverlay(
      weekNumber: weekNumber,
      year: year,
      controller: _previewAnimationController,
      filteredPosts: filteredPosts,
    );

    // 🎯 애니메이션 시작 (단순화: then 제거)
    _previewAnimationController.forward();
  }

  /// 기존 포스트 데이터를 분석하여 주차별 기여도 데이터 생성
  List<WeeklyContributionData> _generateContributionsFromPosts() {
    final year = _selectedYear ?? WeekUtils.getCurrentYear();
    final totalWeeks = WeekUtils.getWeeksInYear(year);
    final contributions = <WeeklyContributionData>[];

    // 주차별로 포스트 개수 집계
    final weekPostCounts = <int, int>{};
    for (final post in _allPosts) {
      try {
        final postDate = DateTime.parse(post.createdAt);
        final (
          year: postYear,
          weekNumber: postWeek,
        ) = WeekUtils.getYearAndWeekFromUtc(postDate);

        if (postYear == year) {
          weekPostCounts[postWeek] = (weekPostCounts[postWeek] ?? 0) + 1;
        }
      } catch (e) {
        debugPrint('[HomeScreen] 포스트 날짜 파싱 실패: ${post.createdAt}, 에러: $e');
      }
    }

    // 모든 주차에 대해 데이터 생성
    for (int week = 1; week <= totalWeeks; week++) {
      final postCount = weekPostCounts[week] ?? 0;
      contributions.add(
        WeeklyContributionData(
          year: year,
          weekNumber: week,
          hasPost: postCount > 0,
          postCount: postCount,
        ),
      );
    }

    return contributions;
  }
}
