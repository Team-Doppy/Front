import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/image/utils/read_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
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

  // 🎯 포그라운드 복귀 시 새로고침을 위한 GlobalKey
  static final GlobalKey<HomeScreenState> globalKey =
      GlobalKey<HomeScreenState>();

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

  // ✅ 실제로 화면에 "보이는" 배경 URL은 이 값 하나로만 결정한다.
  // 섹션 토글/로딩 중 friends/all 값을 즉시 바꾸면 fallback과 섞이며 빠르게 떨릴 수 있어서,
  // 프리캐시가 끝난 뒤에만 이 값을 교체한다.
  String? _visibleBackgroundImageUrl;
  int _bgToken = 0;
  String? _bgRequestedUrl; // ✅ 현재 요청 중(또는 직전 요청) URL (중복 프리캐시/세트 방지)

  Future<void> _precacheBackground(String url) async {
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return;
    // ✅ 카드 썸네일/프리캐시와 같은 크기로 통일해서 캐시/디코딩 중복을 줄인다
    // (배경은 블러가 들어가므로 고해상도 불필요 + imageCache thrash 방지)
    const int widthPx = 800;
    try {
      await precacheImage(
        ReadImageProvider.build(url: url, decodeWidth: widthPx),
        context,
      );
    } catch (_) {}
  }

  void _requestBackground({required bool friends, required String? url}) {
    // ✅ 렌더링은 _visibleBackgroundImageUrl 하나이므로, 중복 체크도 이 값 기준으로만 한다
    if (url != null && url.isNotEmpty && url == _visibleBackgroundImageUrl) {
      return;
    }
    if (url != null && url.isNotEmpty && url == _bgRequestedUrl) {
      // ✅ 같은 URL을 연속으로 요청하는 경우(스와이프/리빌드 타이밍) 중복 실행 방지
      return;
    }

    final int token = ++_bgToken;

    // ✅ null/empty는 무시: 로딩/리프레시 중 배경이 null로 떨어지며 이전/현재가 번갈아 깜빡이는 현상 방지
    if (url == null || url.isEmpty) return;

    // 요청 URL 기록 (중복 방지용)
    _bgRequestedUrl = url;

    // ✅ 배경은 "프리캐시 완료 후에만" 교체해서, 매 전환마다 Shimmer/검정으로 떨어지는 깜빡임 제거
    Future.microtask(() async {
      if (!mounted) return;
      await _precacheBackground(url);
      if (!mounted) return;
      final stillLatest = token == _bgToken;
      if (!stillLatest) return;
      setState(() {
        // ✅ 프리캐시 완료 후에만 "보이는 배경"을 교체한다 (파르르 떨림 방지의 핵심)
        _visibleBackgroundImageUrl = url;
        _previousBackgroundImageUrl = url;
      });
    });
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
      _friendsHasMoreData = _friendsPosts.length == 20; // 🎯 10 -> 20으로 변경
      _friendsCurrentPage = _friendsPosts.isNotEmpty ? 1 : 0;

      // 전체글 데이터 설정
      _allPosts = List<PostData>.from(homeData.allPosts);
      _allIsLoading = false;
      _allHasMoreData = _allPosts.length == 20; // 🎯 10 -> 20으로 변경
      _allCurrentPage = _allPosts.isNotEmpty ? 1 : 0;

      // ✅ 첫 프레임부터 배경이 검정으로 깜빡이지 않도록 초기 배경 URL을 즉시 세팅
      final primary =
          _friendsPosts.isNotEmpty
              ? _friendsPosts
              : (_allPosts.isNotEmpty ? _allPosts : const <PostData>[]);
      if (primary.isNotEmpty) {
        final post = primary.first;
        final url = post.thumbnailUrlForCache.trim();
        if (url.isNotEmpty) {
          _visibleBackgroundImageUrl = url; // ✅ 첫 프레임부터 단일 소스로 배경 고정
          _previousBackgroundImageUrl = url;
        }
      }

      if (_allPosts.isNotEmpty) {
        final post = _allPosts.first;
        final url = post.thumbnailUrlForCache.trim();
        if (url.isNotEmpty) {
          // no-op: visible은 friends 탭에서 시작하므로 여기서 교체하지 않음
        }
      }
    }

    // 초기 배경도 프리캐시를 걸어두면 첫 전환부터 안정적
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initUrl = _visibleBackgroundImageUrl ?? _previousBackgroundImageUrl;
      if (initUrl != null) {
        _precacheBackground(initUrl);
      }
    });

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
          // 🎯 비어있을 때 자동 재로드 제거
          // if (_friendsPosts.isEmpty) {
          //   await _loadFriendsPosts(refresh: true);
          // }
          if (_allPosts.isEmpty) {
            await _loadAllPosts(refresh: true);
          }
        } catch (_) {
        } finally {
          _refreshInProgress = false;
        }
      });

      _loadProfileSafely();

      // 🎯 친구글 비어있을 때 자동 재로드 제거
      // 스플래시에서 데이터를 로드했다면 _friendsPosts가 채워져 있음
      // 스플래시에서 에러가 났거나 데이터가 없어도 자동으로 재로드하지 않음
      // if (_friendsPosts.isEmpty && !_friendsIsLoading) {
      //   _loadFriendsPosts(refresh: false); // 캐시 우선 확인
      // }

      // 🎯 전체글은 초기 로드하지 않음 - 전체 탭으로 이동할 때만 로드
      // (친구 탭에서 전체 탭으로 이동할 때 _handleSectionSwitch나 onPageChanged에서 로드됨)
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
      final String imageUrl = currentPost.thumbnailUrlForCache.trim();
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
      final String imageUrl = currentPost.thumbnailUrlForCache.trim();
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
      debugPrint('[HomeScreen] 프로필 로드 성공');
    } catch (e) {
      debugPrint('[HomeScreen] 프로필 로드 실패: $e');
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

      // 🎯 이미지 프리캐싱
      if (posts.isNotEmpty) {
        if (refresh || _friendsPosts.isEmpty) {
          // 초기 로드나 새로고침: 처음 3개만 동기, 나머지는 비동기
          await _homeDataService.precacheImages(
            posts,
            context,
            syncCount: 3,
            preloadVideos: false,
          );
        } else {
          // loadMore: 모두 비동기로 처리
          _homeDataService.precacheImages(
            posts,
            context,
            syncCount: 0,
            preloadVideos: false,
          );
        }
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

      debugPrint(
        '[HomeScreen] 친구글 로드 성공: ${posts.length}개 (페이지 ${_friendsCurrentPage - 1})',
      );
    } catch (e) {
      final networkError = NetworkUtils.parseError(e);
      debugPrint('[HomeScreen] 친구글 로드 실패: ${networkError.message}');

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
    debugPrint(
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

      // 🎯 이미지 프리캐싱: 추천글은 모두 비동기로 처리
      if (posts.isNotEmpty) {
        _homeDataService.precacheImages(
          posts,
          context,
          syncCount: 0, // 추천글은 모두 비동기 처리 (초기 로드, loadMore 모두)
        );
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

      debugPrint(
        '[HomeScreen] 전체글 로드 성공: ${posts.length}개 (페이지 ${_allCurrentPage - 1})',
      );
    } catch (e) {
      final networkError = NetworkUtils.parseError(e);
      debugPrint('[HomeScreen] 전체글 로드 실패: ${networkError.message}');

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
    // ✅ 렌더링은 단일 소스만 사용 (섹션 토글/로딩 중 흔들림 방지)
    String? imageUrl =
        _visibleBackgroundImageUrl ?? _previousBackgroundImageUrl;

    // 이미지가 없으면 빈 위젯 반환
    if (imageUrl == null) {
      return const SizedBox.shrink();
    }

    final bool isNetwork = imageUrl.startsWith('http');
    final bool isLocalAsset = imageUrl.startsWith('assets/');

    // 🎯 비디오 URL 체크
    final isVideoUrl =
        imageUrl.toLowerCase().endsWith('.mp4') ||
        imageUrl.toLowerCase().endsWith('.mov') ||
        imageUrl.toLowerCase().endsWith('.avi') ||
        imageUrl.toLowerCase().endsWith('.webm') ||
        imageUrl.contains('/videos/');

    // 🎯 배경 이미지 위젯 (네트워크/로컬 에셋/비디오 처리)
    final backgroundImageWidget =
        (isNetwork && !isVideoUrl)
            ? Image(
              image: ReadImageProvider.build(url: imageUrl, decodeWidth: 800),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              key: ValueKey('bg-$imageUrl'),
              loadingBuilder: (context, child, loadingProgress) {
                // ✅ 배경은 URL 교체 전에 precache를 끝내도록 했으므로 로딩 위젯으로 깜빡이지 않게 함
                if (loadingProgress == null) return child;
                return const SizedBox.shrink();
              },
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.error);
              },
            )
            : (isNetwork && isVideoUrl)
            ? _BackgroundVideoWidget(
              videoUrl: imageUrl,
              key: ValueKey('bg-video-$imageUrl'),
            )
            : (isLocalAsset)
            ? Image.asset(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              key: ValueKey('bg-asset-$imageUrl'),
            )
            : const SizedBox.shrink();

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(child: backgroundImageWidget),
          Theme.of(context).brightness == Brightness.dark
              ? Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.background.withValues(alpha: 0.8),
                          Theme.of(
                            context,
                          ).colorScheme.background.withValues(alpha: 0.8),
                          Theme.of(
                            context,
                          ).colorScheme.background.withValues(alpha: 0.8),
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

    debugPrint('[HomeScreen] 섹션 전환: 페이지 $currentPage → $nextPage');

    // 🎯 다음 섹션 데이터가 비어있으면 미리 로드 (이동할 탭만 로드)
    final nextActualIndex = nextPage % 2;
    // 🎯 친구글 비어있을 때 자동 재로드 제거
    // if (nextActualIndex == 0 && _friendsPosts.isEmpty && !_friendsIsLoading) {
    //   debugPrint('[HomeScreen] 친구글 미리 로드 (친구 탭으로 이동)');
    //   _loadFriendsPosts();
    // }
    if (nextActualIndex == 1 && _allPosts.isEmpty && !_allIsLoading) {
      // ✅ 전환 "전에" 로드를 끝내서, 전환 중 Shimmer/빈상태가 보이며 깜빡이는 현상 제거
      debugPrint('[HomeScreen] 전체글 선로딩 후 전환 (깜빡임 방지)');
      await _loadAllPosts(refresh: false);

      // ✅ 첫 배경은 미리 프리캐시만 해둠 (전환 전에는 배경 URL을 바꾸지 않음)
      if (_allPosts.isNotEmpty) {
        final firstUrl = _allPosts.first.thumbnailUrlForCache.trim();
        if (firstUrl.startsWith('http')) {
          await _precacheBackground(firstUrl);
        }
      }
    }
    // 🎯 현재 탭 데이터는 이미 로드되어 있으므로 다시 로드하지 않음

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
            debugPrint(
              '[HomeScreen] 섹션 변경 완료: ${actualIndex == 0 ? "친구글" : "전체글"}',
            );

            // 🎯 섹션 전환 시 이동한 탭의 데이터가 비어있을 때만 로드
            // (이미 로드된 탭은 다시 로드하지 않음)
            // 🎯 친구글 비어있을 때 자동 재로드 제거
            // if (actualIndex == 0 &&
            //     _friendsPosts.isEmpty &&
            //     !_friendsIsLoading) {
            //   debugPrint('[HomeScreen] 친구글이 비어있음 - 자동 로드 (친구 탭으로 이동)');
            //   _loadFriendsPosts();
            // }
            if (actualIndex == 1 && _allPosts.isEmpty && !_allIsLoading) {
              debugPrint('[HomeScreen] 전체글이 비어있음 - 자동 로드 (전체 탭으로 이동)');
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
      behavior: HitTestBehavior.opaque, // 🎯 클릭 감지 영역 확대
      onTap: () {
        _handleSectionSwitch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 0,
        ), // 🎯 패딩 확대 (8 -> 16)
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
        if (_friendsPosts.isNotEmpty) {
          final safeIndex = index.clamp(0, _friendsPosts.length - 1);
          final post = _friendsPosts[safeIndex];
          _requestBackground(
            friends: true,
            url: post.thumbnailUrlForCache.trim(),
          );
        }
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
        if (_allPosts.isNotEmpty) {
          final safeIndex = index.clamp(0, _allPosts.length - 1);
          final post = _allPosts[safeIndex];
          _requestBackground(
            friends: false,
            url: post.thumbnailUrlForCache.trim(),
          );
        }
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
    );
  }
}

/// 🎯 배경 비디오 위젯 (VideoCacheService로 프리로드)
class _BackgroundVideoWidget extends StatefulWidget {
  final String videoUrl;

  const _BackgroundVideoWidget({super.key, required this.videoUrl});

  @override
  State<_BackgroundVideoWidget> createState() => _BackgroundVideoWidgetState();
}

class _BackgroundVideoWidgetState extends State<_BackgroundVideoWidget> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(_BackgroundVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeVideo();
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  void _initializeVideo() {
    // 🎯 VideoCacheService에서 컨트롤러 가져오기 (프리로드)
    _videoController = VideoCacheService().getOrCreateController(
      widget.videoUrl,
      namespace: 'background',
    );

    // 이미 초기화된 경우
    if (_videoController!.value.isInitialized) {
      setState(() {
        _isInitialized = true;
      });
      // 첫 프레임에서 멈춤 (배경으로 사용)
      _videoController!.seekTo(Duration.zero);
      _videoController!.pause();
      _videoController!.setVolume(0);
    } else {
      // 초기화 대기
      _videoController!.addListener(_onVideoInitialized);
    }
  }

  void _onVideoInitialized() {
    if (_videoController?.value.isInitialized ?? false) {
      _videoController?.removeListener(_onVideoInitialized);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // 첫 프레임에서 멈춤 (배경으로 사용)
        _videoController!.seekTo(Duration.zero);
        _videoController!.pause();
        _videoController!.setVolume(0);
      }
    }
  }

  void _disposeVideo() {
    _videoController?.removeListener(_onVideoInitialized);
    if (_videoController != null) {
      VideoCacheService().releaseController(
        widget.videoUrl,
        namespace: 'background',
      );
      _videoController = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _videoController == null) {
      return ShimmerBox(width: double.infinity, height: double.infinity);
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController!.value.size.width,
          height: _videoController!.value.size.height,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }
}
