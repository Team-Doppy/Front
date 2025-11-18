import 'package:cached_network_image/cached_network_image.dart';

import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
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

  // 수직 PageView 컨트롤러
  late PageController _sectionPageController;
  int _currentSectionIndex = 0; // 0: 친구글, 1: 전체글
  double _appBarOpacity = 1.0; // 앱바 투명도

  // 친구글 섹션 데이터
  List<PostData> _friendsPosts = [];
  bool _friendsIsLoading = true;
  bool _friendsIsLoadingMore = false;
  NetworkError? _friendsError;
  bool _friendsIsRetrying = false;
  int _friendsCurrentPage = 0;
  bool _friendsHasMoreData = true;
  int _friendsCurrentPostIndex = 0;
  bool _friendsIsCardShimmering = false;
  int _friendsLoadTick = 0;
  int _friendsRefreshCount = 0; // 리프레시 카운터

  // 전체글 섹션 데이터
  List<PostData> _allPosts = [];
  bool _allIsLoading = true;
  bool _allIsLoadingMore = false;
  NetworkError? _allError;
  bool _allIsRetrying = false;
  int _allCurrentPage = 0;
  bool _allHasMoreData = true;
  int _allCurrentPostIndex = 0;
  bool _allIsCardShimmering = false;
  int _allLoadTick = 0;
  int _allRefreshCount = 0; // 리프레시 카운터
  StreamSubscription<dynamic>? _networkSub;
  bool _refreshInProgress = false;

  // 새로고침 시 배경 이미지 유지용
  String? _previousBackgroundImageUrl;

  // PostList에서 전달받은 배경 이미지 URL
  String? _friendsBackgroundImageUrl;
  String? _allBackgroundImageUrl;

  @override
  void initState() {
    super.initState();

    // 수직 PageView 컨트롤러 초기화 (친구글부터 시작)
    _sectionPageController = PageController(initialPage: 0);

    // 스플래시에서 전달된 선로딩 데이터 반영
    if (widget.preloadedHomeData != null) {
      final homeData = widget.preloadedHomeData!;

      // 친구글 데이터 설정
      _friendsPosts = List<PostData>.from(homeData.friendsPosts);
      _friendsIsLoading = false;
      _friendsHasMoreData = _friendsPosts.length == 20; // 🎯 10 -> 20으로 변경
      _friendsCurrentPage = _friendsPosts.isNotEmpty ? 1 : 0;

      // 전체글 데이터 설정
      _allPosts = List<PostData>.from(homeData.allPosts);
      _allIsLoading = false;
      _allHasMoreData = _allPosts.length == 20; // 🎯 10 -> 20으로 변경
      _allCurrentPage = _allPosts.isNotEmpty ? 1 : 0;
    }

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
          if (_friendsPosts.isEmpty) {
            await _loadFriendsPosts(refresh: true);
          }
          if (_allPosts.isEmpty) {
            await _loadAllPosts(refresh: true);
          }
        } catch (_) {
        } finally {
          _refreshInProgress = false;
        }
      });

      _loadProfileSafely();

      // 친구글이 비어있으면 로드
      // 스플래시에서 데이터를 로드했다면 _friendsPosts가 채워져 있음
      // 스플래시에서 에러가 났다면 _friendsPosts가 비어있고, 서버에서 로드 필요
      // refresh=false로 설정하면 캐시를 먼저 확인하고, 캐시가 없을 때만 서버에서 로드
      if (_friendsPosts.isEmpty && !_friendsIsLoading) {
        _loadFriendsPosts(refresh: false); // 캐시 우선 확인
      }

      // 전체글이 비어있으면 로드
      if (_allPosts.isEmpty && !_allIsLoading) {
        _loadAllPosts(refresh: false); // 캐시 우선 확인
      }
    });
  }

  @override
  void dispose() {
    // 네트워크 구독 취소
    _networkSub?.cancel();

    // PageView 컨트롤러 해제
    _sectionPageController.dispose();

    super.dispose();
  }

  void _resetFriendsFeed({bool showLoading = true}) {
    // 새로고침 시 현재 배경 이미지를 이전 이미지로 저장
    if (_friendsPosts.isNotEmpty && _currentSectionIndex == 0) {
      final safeIndex = _friendsCurrentPostIndex.clamp(
        0,
        _friendsPosts.length - 1,
      );
      final currentPost = _friendsPosts[safeIndex];
      final String imageUrl = currentPost.thumbnailImageUrl.trim();
      if (imageUrl.startsWith('http')) {
        _previousBackgroundImageUrl = imageUrl;
      }
    }

    setState(() {
      _friendsPosts = [];
      _friendsCurrentPage = 0;
      _friendsHasMoreData = true;
      _friendsIsLoading = showLoading;
      _friendsIsLoadingMore = false;
      _friendsError = null;
      _friendsCurrentPostIndex = 0;
      _friendsIsCardShimmering = false;
      _friendsRefreshCount++; // 리프레시 카운터 증가
    });
  }

  void _resetAllFeed({bool showLoading = true}) {
    // 새로고침 시 현재 배경 이미지를 이전 이미지로 저장
    if (_allPosts.isNotEmpty && _currentSectionIndex == 1) {
      final safeIndex = _allCurrentPostIndex.clamp(0, _allPosts.length - 1);
      final currentPost = _allPosts[safeIndex];
      final String imageUrl = currentPost.thumbnailImageUrl.trim();
      if (imageUrl.startsWith('http')) {
        _previousBackgroundImageUrl = imageUrl;
      }
    }

    setState(() {
      _allPosts = [];
      _allCurrentPage = 0;
      _allHasMoreData = true;
      _allIsLoading = showLoading;
      _allIsLoadingMore = false;
      _allError = null;
      _allCurrentPostIndex = 0;
      _allIsCardShimmering = false;
      _allRefreshCount++; // 리프레시 카운터 증가
    });
  }

  Future<void> _loadProfileSafely() async {
    try {
      await context.read<UserProvider>().fetchMyProfile();
      print('[HomeScreen] 프로필 로드 성공');
    } catch (e) {
      print('[HomeScreen] 프로필 로드 실패: $e');
      // 프로필 로드 실패해도 계속 진행 (UI에 영향 없음)
    }
  }

  Future<void> _retryFriendsPosts() async {
    setState(() {
      _friendsIsRetrying = true;
      _friendsError = null; // 에러 상태만 클리어 (데이터는 유지)
    });

    try {
      // refresh=false로 호출해서 reset하지 않음
      await _loadFriendsPosts(refresh: false);
      // 재시도 후 0.5초 딜레이
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      setState(() {
        _friendsIsRetrying = false;
      });
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

  Future<void> _loadFriendsPosts({bool refresh = false}) async {
    try {
      if (refresh) {
        _resetFriendsFeed(showLoading: true);
        // 새로고침 시 shimmer 표시
        setState(() {
          _friendsIsCardShimmering = true;
        });
      } else if (!_friendsIsRetrying) {
        // 재시도 중이 아닐 때만 로딩 상태 변경
        setState(() {
          _friendsIsLoading = _friendsPosts.isEmpty;
          _friendsError = null;
        });
      }

      final int token = ++_friendsLoadTick;

      // FeedDataService를 사용하여 캐시 우선 로드
      final posts = await _homeDataService.loadFriendsPosts(
        page: _friendsCurrentPage,
        size: 20, // 🎯 10 -> 20으로 증가
        refresh: refresh,
      );

      // 이미지 프리캐싱 (더 많이 프리로드)
      if (posts.isNotEmpty) {
        await _homeDataService.precacheImages(
          posts.take(10).toList(),
          context,
        ); // 🎯 3 -> 10으로 증가
      }

      if (token != _friendsLoadTick) return;

      setState(() {
        if (refresh) {
          _friendsPosts = posts;
          _previousBackgroundImageUrl = null;
        } else {
          _friendsPosts.addAll(posts);
        }
        _friendsIsLoading = false;
        _friendsIsLoadingMore = false;
        _friendsHasMoreData = posts.length == 20; // 🎯 10 -> 20으로 변경
        _friendsCurrentPage++;
        _friendsIsCardShimmering = false; // 데이터 로드 완료 즉시 shimmer 해제
        _friendsError = null; // 성공 시 에러 클리어
      });

      print(
        '[HomeScreen] 친구글 로드 성공: ${posts.length}개 (페이지 ${_friendsCurrentPage - 1})',
      );
    } catch (e) {
      final networkError = NetworkUtils.parseError(e);
      print('[HomeScreen] 친구글 로드 실패: ${networkError.message}');

      setState(() {
        _friendsError = networkError;
        _friendsIsLoading = false;
        _friendsIsLoadingMore = false;
        _friendsIsCardShimmering = false; // 에러 시에도 shimmer 해제
      });
    }
  }

  Future<void> _loadMoreFriendsPosts() async {
    if (_friendsIsLoadingMore || !_friendsHasMoreData) return;

    setState(() {
      _friendsIsLoadingMore = true;
    });

    await _loadFriendsPosts();
  }

  Future<void> _loadAllPosts({bool refresh = false}) async {
    print(
      '[HomeScreen] _loadAllPosts 시작 - refresh: $refresh, 현재 데이터: ${_allPosts.length}개',
    );

    try {
      if (refresh) {
        _resetAllFeed(showLoading: true);
        // 새로고침 시 shimmer 표시
        setState(() {
          _allIsCardShimmering = true;
        });
      } else if (!_allIsRetrying) {
        // 재시도 중이 아닐 때만 로딩 상태 변경
        setState(() {
          _allIsLoading = _allPosts.isEmpty;
          _allError = null;
        });
      }

      final int token = ++_allLoadTick;

      // FeedDataService를 사용하여 캐시 우선 로드
      final posts = await _homeDataService.loadAllPosts(
        page: _allCurrentPage,
        size: 20, // 🎯 10 -> 20으로 증가
        refresh: refresh,
      );

      // 이미지 프리캐싱 (더 많이 프리로드)
      if (posts.isNotEmpty) {
        await _homeDataService.precacheImages(
          posts.take(10).toList(),
          context,
        ); // 🎯 3 -> 10으로 증가
      }

      if (token != _allLoadTick) return;

      setState(() {
        if (refresh) {
          _allPosts = posts;
          _previousBackgroundImageUrl = null;
        } else {
          _allPosts.addAll(posts);
        }
        _allIsLoading = false;
        _allIsLoadingMore = false;
        _allHasMoreData = posts.length == 20; // 🎯 10 -> 20으로 변경
        _allCurrentPage++;
        _allIsCardShimmering = false; // 데이터 로드 완료 즉시 shimmer 해제
        _allError = null; // 성공 시 에러 클리어
      });

      print(
        '[HomeScreen] 전체글 로드 성공: ${posts.length}개 (페이지 ${_allCurrentPage - 1})',
      );
    } catch (e) {
      final networkError = NetworkUtils.parseError(e);
      print('[HomeScreen] 전체글 로드 실패: ${networkError.message}');

      setState(() {
        _allError = networkError;
        _allIsLoading = false;
        _allIsLoadingMore = false;
        _allIsCardShimmering = false; // 에러 시에도 shimmer 해제
      });
    }
  }

  Future<void> _loadMoreAllPosts() async {
    if (_allIsLoadingMore || !_allHasMoreData) return;

    setState(() {
      _allIsLoadingMore = true;
    });

    await _loadAllPosts();
  }

  Widget _buildDynamicBackground() {
    // 🎯 PostList에서 전달받은 배경 이미지 URL 사용
    String? imageUrl;
    if (_currentSectionIndex == 0) {
      // 친구글 섹션
      imageUrl = _friendsBackgroundImageUrl;
    } else {
      // 전체글 섹션
      imageUrl = _allBackgroundImageUrl;
    }

    // 새로고침 중이고 이전 배경 이미지가 있으면 그것을 사용
    if (imageUrl == null && _previousBackgroundImageUrl != null) {
      imageUrl = _previousBackgroundImageUrl;
    }

    // 이미지가 없으면 빈 위젯 반환
    if (imageUrl == null) {
      return const SizedBox.shrink();
    }

    final bool isNetwork = imageUrl.startsWith('http');

    // 🎯 비디오 URL 체크
    final isVideoUrl =
        imageUrl.toLowerCase().endsWith('.mp4') ||
        imageUrl.toLowerCase().endsWith('.mov') ||
        imageUrl.toLowerCase().endsWith('.avi') ||
        imageUrl.toLowerCase().endsWith('.webm') ||
        imageUrl.contains('/videos/');

    // 🎯 배경 이미지 위젯 (AnimatedSwitcher로 감싸기 위해 별도 위젯으로 분리)
    final backgroundImageWidget =
        (isNetwork && !isVideoUrl)
            ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              key: ValueKey('bg-$imageUrl'),
              placeholder:
                  (context, url) => ShimmerBox(
                    width: double.infinity,
                    height: double.infinity,
                  ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            )
            : const SizedBox.shrink();

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 400,
              ), // 🎯 부드러운 전환 (섹션 전환과 동일한 duration)
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: backgroundImageWidget,
            ),
          ),
          Theme.of(context).brightness == Brightness.dark
              ? Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 13, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.7),
                          Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.82),
                          Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.88),
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              )
              : Positioned.fill(
                child: Container(
                  color: Theme.of(context).colorScheme.background,
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [_buildDynamicBackground(), _buildContent(screenWidth)],
    );
  }

  void _handleSectionSwitch() async {
    // 현재 페이지에서 다음 페이지로 (무한 스크롤)
    final currentPage = _sectionPageController.page?.round() ?? 0;
    final nextPage = currentPage + 1;

    print('[HomeScreen] 섹션 전환: 페이지 $currentPage → $nextPage');

    // 다음 섹션 데이터가 비어있으면 미리 로드
    final nextActualIndex = nextPage % 2;
    if (nextActualIndex == 0 && _friendsPosts.isEmpty && !_friendsIsLoading) {
      print('[HomeScreen] 친구글 미리 로드');
      _loadFriendsPosts();
    } else if (nextActualIndex == 1 && _allPosts.isEmpty && !_allIsLoading) {
      print('[HomeScreen] 전체글 미리 로드');
      _loadAllPosts();
    }

    // 앱바 페이드 아웃
    setState(() {
      _appBarOpacity = 0.0;
    });

    // 페이지 전환
    await _sectionPageController.animateToPage(
      nextPage,
      duration: Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );

    if (mounted) {
      setState(() {
        _appBarOpacity = 1.0;

        // 배경 이미지를 새로운 섹션의 첫 번째 포스트로 변경
        if (nextActualIndex == 0) {
          // 친구글로 전환 - 첫 번째 포스트로 인덱스 설정
          _friendsCurrentPostIndex = 0;
        } else {
          // 전체글로 전환 - 첫 번째 포스트로 인덱스 설정
          _allCurrentPostIndex = 0;
        }
      });
    }
  }

  Widget _buildContent(double screenWidth) {
    // 무한 루프 PageView로 친구글/전체글 섹션 구성
    // 위로만 스크롤 가능 (한 방향)
    return Stack(
      children: [
        PageView.builder(
          controller: _sectionPageController,
          scrollDirection: Axis.vertical,
          physics: NeverScrollableScrollPhysics(), // 제스처 비활성화 (프로그래매틱하게만 전환)
          onPageChanged: (index) {
            final actualIndex = index % 2; // 0: 친구글, 1: 전체글
            setState(() {
              _currentSectionIndex = actualIndex;
            });
            print('[HomeScreen] 섹션 변경 완료: ${actualIndex == 0 ? "친구글" : "전체글"}');

            // 섹션 전환 시 데이터가 비어있으면 자동 로드
            if (actualIndex == 0 &&
                _friendsPosts.isEmpty &&
                !_friendsIsLoading) {
              print('[HomeScreen] 친구글이 비어있음 - 자동 로드');
              _loadFriendsPosts();
            } else if (actualIndex == 1 &&
                _allPosts.isEmpty &&
                !_allIsLoading) {
              print('[HomeScreen] 전체글이 비어있음 - 자동 로드');
              _loadAllPosts();
            }
          },
          itemBuilder: (context, index) {
            final actualIndex = index % 2;
            return actualIndex == 0
                ? _buildFriendsSection(screenWidth)
                : _buildAllPostsSection(screenWidth);
          },
        ),

        Positioned(top: 60, right: 0, child: _buildGroupIndexIndicator()),
      ],
    );
  }

  // 그룹 인덱스 인디케이터 (가로 라인) - 클릭/드래그 가능
  Widget _buildGroupIndexIndicator() {
    // 🎯 그룹이 1개 이하면 생성 버튼 포함, 아니면 그룹만
    final totalItems = 2;

    return GestureDetector(
      onTap: () {
        _handleSectionSwitch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(totalItems, (index) {
            final isCurrent = index == _currentSectionIndex;
            return Container(
              width: 16,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildFriendsSection(double screenWidth) {
    // 에러 상태 표시 (재시도 중이거나 에러가 있고 데이터가 비어있을 때)
    if ((_friendsError != null || _friendsIsRetrying) &&
        _friendsPosts.isEmpty &&
        !_friendsIsLoading) {
      return ErrorStateWidget(
        error:
            _friendsError ??
            NetworkError(
              type: NetworkErrorType.noConnection,
              message: '오프라인 상태에요!',
              userMessage: '오프라인 상태에요!',
              isRetryable: true,
            ),
        onRetry: _retryFriendsPosts,
        customTitle: context.tr('friends_posts_load_failed'),
        isRetrying: _friendsIsRetrying,
      );
    }

    return PostList(
      key: ValueKey('friends-${_friendsRefreshCount}'),
      containerWidth: screenWidth,
      posts: _friendsPosts,
      onLoadMore: _friendsHasMoreData ? _loadMoreFriendsPosts : null,
      isLoadingMore: _friendsIsLoadingMore,
      isLoading: _friendsIsLoading,
      onRefresh: () => _loadFriendsPosts(refresh: true),
      showCardShimmer: _friendsIsCardShimmering,
      onPageChanged: (index) {
        setState(() {
          _friendsCurrentPostIndex = index;
        });
      },
      isShowingFriendsOnly: true,
      onFilterTap: _handleSectionSwitch,
      showAppBar: true,
      // 현재 섹션 이름을 표시 (친구/팔로우/그룹 등 나와 연결된 사람들의 피드) - 로케일 기반
      sectionLabel: context.tr('my_network_feed'),
      appBarOpacity: _appBarOpacity, // 앱바 투명도 전달
      networkError: _friendsError, // 에러 상태 전달
      onRetryError: () => _loadFriendsPosts(refresh: true), // 에러 재시도 콜백
      isTabActive: widget.isActive, // 탭 활성
      onBackgroundImageChanged: (imageUrl) {
        setState(() {
          _friendsBackgroundImageUrl = imageUrl;
        });
      },
    );
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
        customTitle: '추천글을 불러올 수 없습니다',
        isRetrying: _allIsRetrying,
      );
    }

    return PostList(
      key: ValueKey('all-${_allRefreshCount}'),
      containerWidth: screenWidth,
      posts: _allPosts,
      onLoadMore: _allHasMoreData ? _loadMoreAllPosts : null,
      isLoadingMore: _allIsLoadingMore,
      isLoading: _allIsLoading,
      onRefresh: () => _loadAllPosts(refresh: true),
      showCardShimmer: _allIsCardShimmering,
      onPageChanged: (index) {
        setState(() {
          _allCurrentPostIndex = index;
        });
      },
      isShowingFriendsOnly: false,
      onFilterTap: _handleSectionSwitch,
      showAppBar: true,
      // 전체 피드 섹션에서는 현재 페이지명을 명확히 표시
      sectionLabel: context.tr('all_posts'),
      appBarOpacity: _appBarOpacity, // 앱바 투명도 전달
      networkError: _allError, // 에러 상태 전달
      onRetryError: () => _loadAllPosts(refresh: true), // 에러 재시도 콜백
      isTabActive: widget.isActive, // 탭 활성 + 오버레이 미표시
      onBackgroundImageChanged: (imageUrl) {
        setState(() {
          _allBackgroundImageUrl = imageUrl;
        });
      },
    );
  }
}
