import 'package:cached_network_image/cached_network_image.dart';

import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/providers/search_provider.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final HomeData? preloadedHomeData;
  final ValueNotifier<bool>? searchResultsNotifier; // 검색 결과 표시 상태 알림용
  final bool isActive; // 현재 탭이 활성 상태인지
  final Function(String?)? onOpenSearchScreen; // 검색 화면 열기 콜백 (검색어 전달)

  const HomeScreen({
    super.key,
    this.preloadedHomeData,
    this.searchResultsNotifier,
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

  // 검색 오버레이 상태
  bool _isSearchOverlayVisible = false;
  bool _isShowingSearchResults = false;
  String _searchQuery = '';
  bool _searchHasMore = true;

  // 검색 전 데이터 백업 (검색 종료 시 복원용)
  List<PostData>? _friendsPostsBeforeSearch;
  List<PostData>? _allPostsBeforeSearch;
  int _friendsCurrentPostIndexBeforeSearch = 0;
  int _allCurrentPostIndexBeforeSearch = 0;

  // 새로고침 시 배경 이미지 유지용
  String? _previousBackgroundImageUrl;

  // SearchProvider 리스너 참조 (dispose용)
  VoidCallback? _searchProviderListener;

  // 검색 결과 표시 여부를 외부에서 확인할 수 있는 getter
  bool get isShowingSearchResults => _isShowingSearchResults;

  // 탭 활성/비활성은 부모에서 전달되는 widget.isActive로 처리 (리스너 불필요)

  // 바텀 네비게이션에서 호출할 수 있는 public 메서드
  void clearSearchAndReturnToHome() {
    if (_isShowingSearchResults) {
      context.read<SearchProvider>().clearSearchResults();
      setState(() {
        _isShowingSearchResults = false;
        _searchQuery = '';
        // 백업된 데이터 복원
        if (_currentSectionIndex == 0 && _friendsPostsBeforeSearch != null) {
          _friendsPosts = _friendsPostsBeforeSearch!;
          _friendsCurrentPostIndex = _friendsCurrentPostIndexBeforeSearch;
          _friendsRefreshCount++;
        } else if (_currentSectionIndex == 1 && _allPostsBeforeSearch != null) {
          _allPosts = _allPostsBeforeSearch!;
          _allCurrentPostIndex = _allCurrentPostIndexBeforeSearch;
          _allRefreshCount++;
        }
      });
      // 백업 데이터 초기화
      _friendsPostsBeforeSearch = null;
      _allPostsBeforeSearch = null;
      // 검색 결과 표시 상태를 부모에게 알림
      widget.searchResultsNotifier?.value = false;
    }
  }

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
      _friendsHasMoreData = _friendsPosts.length == 10;
      _friendsCurrentPage = _friendsPosts.isNotEmpty ? 1 : 0;

      // 전체글 데이터 설정
      _allPosts = List<PostData>.from(homeData.allPosts);
      _allIsLoading = false;
      _allHasMoreData = _allPosts.length == 10;
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

    // 다음 프레임에서 검색 결과 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final searchResultProvider = context.read<SearchProvider>();
      if (searchResultProvider.hasSearchResults) {
        setState(() {
          // 새로운 리스트로 교체하여 PostList가 변경을 감지하도록
          _friendsPosts = List<PostData>.from(
            searchResultProvider.searchResults,
          );
          _searchQuery = searchResultProvider.searchQuery;
          _isShowingSearchResults = true;
          _friendsIsLoading = false;
          _friendsHasMoreData = false;
          _friendsCurrentPostIndex = 0;
          _friendsRefreshCount++; // 강제 새로고침
        });
      }

      // Provider의 오버레이 상태 변화를 감지
      _searchProviderListener = () {
        if (!searchResultProvider.isSearchOverlayVisible &&
            _isSearchOverlayVisible) {
          // 다른 탭으로 이동 시 오버레이 닫기
          setState(() {
            _isSearchOverlayVisible = false;
          });
        }
      };
      searchResultProvider.addListener(_searchProviderListener!);
    });
  }

  @override
  void dispose() {
    // SearchProvider 리스너 제거
    if (_searchProviderListener != null) {
      try {
        context.read<SearchProvider>().removeListener(_searchProviderListener!);
      } catch (_) {
        // context가 이미 dispose된 경우 무시
      }
    }

    // 네트워크 구독 취소
    _networkSub?.cancel();

    // PageView 컨트롤러 해제
    _sectionPageController.dispose();

    super.dispose();
  }

  Future<void> _refreshSearchResults() async {
    if (_searchQuery.trim().isEmpty) return;
    try {
      final svc = context.read<SearchService>();
      await svc.startBlogsSearch(_searchQuery, size: 20);
      final items = svc.blogResults;

      final refreshed =
          items
              .map(
                (item) => PostData(
                  id: item.id,
                  thumbnailImageUrl: item.imageUrl ?? '',
                  title: item.title ?? '',
                  summary: item.summary ?? item.parsedContent ?? '',
                  author: item.author ?? item.username ?? '',
                  authorProfileImageUrl: item.profileImageUrl ?? '',
                  content: item.content ?? '',
                  accessLevel: AccessLevel.public,
                  viewCount: 0,
                  commentCount: item.comments ?? 0,
                  likeCount: item.likes ?? 0,
                  isLiked: false,
                  createdAt: DateTime.now().toIso8601String(),
                  updatedAt: DateTime.now().toIso8601String(),
                ),
              )
              .toList();

      // 현재 섹션에 반영
      setState(() {
        if (_currentSectionIndex == 0) {
          _friendsPosts = refreshed;
          _friendsIsLoading = false;
          _friendsIsLoadingMore = false;
          _friendsHasMoreData = false;
          _friendsCurrentPostIndex = 0;
          _friendsRefreshCount++; // 강제 새로고침
        } else {
          _allPosts = refreshed;
          _allIsLoading = false;
          _allIsLoadingMore = false;
          _allHasMoreData = false;
          _allCurrentPostIndex = 0;
          _allRefreshCount++; // 강제 새로고침
        }
        _searchHasMore = svc.blogsHasMore;
      });

      // 전역 상태도 업데이트
      context.read<SearchProvider>().setSearchResults(refreshed, _searchQuery);
    } catch (e) {
      debugPrint('[HomeScreen] 검색 새로고침 실패: $e');
    }
  }

  Future<void> _loadMoreSearchResults() async {
    final svc = context.read<SearchService>();
    if (!_searchHasMore) return;
    if (_currentSectionIndex == 0 && _friendsIsLoadingMore) return;
    if (_currentSectionIndex == 1 && _allIsLoadingMore) return;

    setState(() {
      if (_currentSectionIndex == 0) {
        _friendsIsLoadingMore = true;
      } else {
        _allIsLoadingMore = true;
      }
    });

    try {
      final items = await svc.loadMoreBlogs(size: 20);
      final append =
          items
              .map(
                (item) => PostData(
                  id: item.id,
                  thumbnailImageUrl: item.imageUrl ?? '',
                  title: item.title ?? '',
                  summary: item.summary ?? item.parsedContent ?? '',
                  author: item.author ?? item.username ?? '',
                  authorProfileImageUrl: item.profileImageUrl ?? '',
                  content: item.content ?? '',
                  accessLevel: AccessLevel.public,
                  viewCount: 0,
                  likeCount: item.likes ?? 0,
                  commentCount: item.comments ?? 0,
                  isLiked: false,
                  createdAt: DateTime.now().toIso8601String(),
                  updatedAt: DateTime.now().toIso8601String(),
                ),
              )
              .toList();

      setState(() {
        if (_currentSectionIndex == 0) {
          _friendsPosts.addAll(append);
          _friendsIsLoadingMore = false;
        } else {
          _allPosts.addAll(append);
          _allIsLoadingMore = false;
        }
        _searchHasMore = svc.blogsHasMore;
      });
    } catch (e) {
      setState(() {
        if (_currentSectionIndex == 0) {
          _friendsIsLoadingMore = false;
        } else {
          _allIsLoadingMore = false;
        }
      });
    }
  }

  // 검색 결과 설정 (외부에서 호출) - 현재 섹션에 설정
  void setSearchResults(List<PostData> results, String query) {
    if (mounted) {
      setState(() {
        if (_currentSectionIndex == 0) {
          // 검색 전 데이터 백업 (첫 검색 시에만)
          if (!_isShowingSearchResults) {
            _friendsPostsBeforeSearch = List<PostData>.from(_friendsPosts);
            _friendsCurrentPostIndexBeforeSearch = _friendsCurrentPostIndex;
          }
          // 친구글 섹션 - 새로운 리스트로 교체하여 PostList가 변경을 감지하도록
          _friendsPosts = List<PostData>.from(results);
          _friendsCurrentPostIndex = 0;
          _friendsRefreshCount++; // 강제 새로고침
          _friendsIsLoading = false;
          _friendsHasMoreData = false;
        } else {
          // 검색 전 데이터 백업 (첫 검색 시에만)
          if (!_isShowingSearchResults) {
            _allPostsBeforeSearch = List<PostData>.from(_allPosts);
            _allCurrentPostIndexBeforeSearch = _allCurrentPostIndex;
          }
          // 전체글 섹션 - 새로운 리스트로 교체하여 PostList가 변경을 감지하도록
          _allPosts = List<PostData>.from(results);
          _allCurrentPostIndex = 0;
          _allRefreshCount++; // 강제 새로고침
          _allIsLoading = false;
          _allHasMoreData = false;
        }
        _isShowingSearchResults = true;
        _searchQuery = query;
        // 검색 결과 표시 상태를 부모에게 알림
        widget.searchResultsNotifier?.value = true;
      });
    }
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
      _isShowingSearchResults = false;
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
      _isShowingSearchResults = false;
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
    // 검색 결과 표시 중에는 로드하지 않음
    if (_isShowingSearchResults && !refresh) return;

    try {
      if (refresh) {
        _resetFriendsFeed(showLoading: true);
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
        size: 10,
        refresh: refresh,
      );

      // 이미지 프리캐싱
      if (posts.isNotEmpty) {
        await _homeDataService.precacheImages(posts.take(3).toList(), context);
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
        _friendsHasMoreData = posts.length == 10;
        _friendsCurrentPage++;
        _friendsIsCardShimmering = false;
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
      });
    }
  }

  Future<void> _loadMoreFriendsPosts() async {
    if (_friendsIsLoadingMore ||
        !_friendsHasMoreData ||
        _isShowingSearchResults)
      return;

    setState(() {
      _friendsIsLoadingMore = true;
    });

    await _loadFriendsPosts();
  }

  Future<void> _loadAllPosts({bool refresh = false}) async {
    print(
      '[HomeScreen] _loadAllPosts 시작 - refresh: $refresh, 현재 데이터: ${_allPosts.length}개',
    );

    // 검색 결과 표시 중에는 로드하지 않음
    if (_isShowingSearchResults && !refresh) return;

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

      // FeedDataService를 사용하여 캐시 우선 로드
      final posts = await _homeDataService.loadAllPosts(
        page: _allCurrentPage,
        size: 10,
        refresh: refresh,
      );

      // 이미지 프리캐싱
      if (posts.isNotEmpty) {
        await _homeDataService.precacheImages(posts.take(3).toList(), context);
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
        _allHasMoreData = posts.length == 10;
        _allCurrentPage++;
        _allIsCardShimmering = false;
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
      });
    }
  }

  Future<void> _loadMoreAllPosts() async {
    if (_allIsLoadingMore || !_allHasMoreData || _isShowingSearchResults)
      return;

    setState(() {
      _allIsLoadingMore = true;
    });

    await _loadAllPosts();
  }

  Widget _buildDynamicBackground() {
    // 현재 섹션의 포스트 가져오기
    final currentPosts = _currentSectionIndex == 0 ? _friendsPosts : _allPosts;
    final currentPostIndex =
        _currentSectionIndex == 0
            ? _friendsCurrentPostIndex
            : _allCurrentPostIndex;

    // 새로고침 중이고 이전 배경 이미지가 있으면 그것을 사용
    if (currentPosts.isEmpty && _previousBackgroundImageUrl != null) {
      return Positioned.fill(
        child: Stack(
          children: [
            Theme.of(context).brightness == Brightness.dark
                ? Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: _previousBackgroundImageUrl!,
                    fit: BoxFit.cover,
                    key: ValueKey('bg-previous-$_previousBackgroundImageUrl'),
                    placeholder:
                        (context, url) => ShimmerBox(
                          width: double.infinity,
                          height: double.infinity,
                        ),
                    errorWidget:
                        (context, url, error) => const Icon(Icons.error),
                  ),
                )
                : SizedBox.shrink(),
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.8),
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.8),
                        Theme.of(
                          context,
                        ).colorScheme.background.withOpacity(0.8),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (currentPosts.isEmpty) return const SizedBox.shrink();

    // 안전한 인덱스 범위 체크
    final safeIndex = currentPostIndex.clamp(0, currentPosts.length - 1);
    final currentPost = currentPosts[safeIndex];
    final String imageUrl = currentPost.thumbnailImageUrl.trim();

    final bool isNetwork = imageUrl.startsWith('http');

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child:
                isNetwork
                    ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      key: ValueKey('bg-$imageUrl'),
                      placeholder:
                          (context, url) => ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                          ),
                      errorWidget:
                          (context, url, error) => const Icon(Icons.error),
                    )
                    : SizedBox.shrink(),
          ),
          Theme.of(context).brightness == Brightness.dark
              ? Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.85),
                          Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.75),
                          Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.8),
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
    return PageView.builder(
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
        if (actualIndex == 0 && _friendsPosts.isEmpty && !_friendsIsLoading) {
          print('[HomeScreen] 친구글이 비어있음 - 자동 로드');
          _loadFriendsPosts();
        } else if (actualIndex == 1 && _allPosts.isEmpty && !_allIsLoading) {
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
      onLoadMore:
          _isShowingSearchResults
              ? (_searchHasMore ? _loadMoreSearchResults : null)
              : (_friendsHasMoreData ? _loadMoreFriendsPosts : null),
      isLoadingMore: _friendsIsLoadingMore,
      isLoading: _friendsIsLoading,
      onRefresh:
          () =>
              _isShowingSearchResults
                  ? _refreshSearchResults()
                  : _loadFriendsPosts(refresh: true),
      showCardShimmer: _friendsIsCardShimmering,
      onPageChanged: (index) {
        setState(() {
          _friendsCurrentPostIndex = index;
        });
      },
      isShowingSearchResults: _isShowingSearchResults,
      searchQuery: _searchQuery,
      onSearchChipTap: () => widget.onOpenSearchScreen?.call(_searchQuery),
      onClearSearch: () {
        context.read<SearchProvider>().clearSearchResults();
        setState(() {
          _isShowingSearchResults = false;
          _searchQuery = '';
          // 백업된 데이터 복원
          if (_friendsPostsBeforeSearch != null) {
            _friendsPosts = _friendsPostsBeforeSearch!;
            _friendsCurrentPostIndex = _friendsCurrentPostIndexBeforeSearch;
            _friendsRefreshCount++; // UI 갱신
          }
        });
        // 백업 데이터 초기화
        _friendsPostsBeforeSearch = null;
        // 검색 결과 표시 상태를 부모에게 알림
        widget.searchResultsNotifier?.value = false;
      },
      isShowingFriendsOnly: true,
      onFilterTap: _handleSectionSwitch,
      showAppBar: true,
      sectionLabel: context.tr('all_posts'),
      appBarOpacity: _appBarOpacity, // 앱바 투명도 전달
      networkError: _friendsError, // 에러 상태 전달
      onRetryError: () => _loadFriendsPosts(refresh: true), // 에러 재시도 콜백
      isTabActive: widget.isActive, // 탭 활성
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
      onLoadMore:
          _isShowingSearchResults
              ? (_searchHasMore ? _loadMoreSearchResults : null)
              : (_allHasMoreData ? _loadMoreAllPosts : null),
      isLoadingMore: _allIsLoadingMore,
      isLoading: _allIsLoading,
      onRefresh:
          () =>
              _isShowingSearchResults
                  ? _refreshSearchResults()
                  : _loadAllPosts(refresh: true),
      showCardShimmer: _allIsCardShimmering,
      onPageChanged: (index) {
        setState(() {
          _allCurrentPostIndex = index;
        });
      },
      isShowingSearchResults: _isShowingSearchResults,
      searchQuery: _searchQuery,
      onSearchChipTap: () => widget.onOpenSearchScreen?.call(_searchQuery),
      onClearSearch: () {
        context.read<SearchProvider>().clearSearchResults();
        setState(() {
          _isShowingSearchResults = false;
          _searchQuery = '';
          // 백업된 데이터 복원
          if (_allPostsBeforeSearch != null) {
            _allPosts = _allPostsBeforeSearch!;
            _allCurrentPostIndex = _allCurrentPostIndexBeforeSearch;
            _allRefreshCount++; // UI 갱신
          }
        });
        // 백업 데이터 초기화
        _allPostsBeforeSearch = null;
        // 검색 결과 표시 상태를 부모에게 알림
        widget.searchResultsNotifier?.value = false;
      },
      isShowingFriendsOnly: false,
      onFilterTap: _handleSectionSwitch,
      showAppBar: true,
      sectionLabel: context.tr('friends_posts'),
      appBarOpacity: _appBarOpacity, // 앱바 투명도 전달
      networkError: _allError, // 에러 상태 전달
      onRetryError: () => _loadAllPosts(refresh: true), // 에러 재시도 콜백
      isTabActive: widget.isActive, // 탭 활성 + 오버레이 미표시
    );
  }
}
