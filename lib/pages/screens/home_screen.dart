import 'package:doppy/pages/components/post_list.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/error_state_widget.dart';
import 'package:doppy/utils/network_utils.dart';
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

  double _appBarOpacity = 1.0; // 앱바 투명도

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
  int _allCurrentPostIndex = 0;
  bool _allIsCardShimmering = false;
  int _allLoadTick = 0;
  int _allRefreshCount = 0; // 리프레시 카운터
  bool _friendsLoaded = false; // 친구글 로드 완료 여부
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

      // ✅ 첫 프레임부터 배경이 검정으로 깜빡이지 않도록 초기 배경 URL을 즉시 세팅
      if (_allPosts.isNotEmpty) {
        final post = _allPosts.first;
        final url = post.thumbnailUrlForCache.trim();
        if (url.isNotEmpty) {
          _visibleBackgroundImageUrl = url; // ✅ 첫 프레임부터 단일 소스로 배경 고정
          _previousBackgroundImageUrl = url;
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
    });
  }

  @override
  void dispose() {
    // 네트워크 구독 취소
    _networkSub?.cancel();

    super.dispose();
  }

  void _resetAllFeed({bool showLoading = true}) {
    // 새로고침 시 현재 배경 이미지를 이전 이미지로 저장
    if (_allPosts.isNotEmpty) {
      final safeIndex = _allCurrentPostIndex.clamp(0, _allPosts.length - 1);
      final currentPost = _allPosts[safeIndex];
      final String imageUrl = currentPost.thumbnailUrlForCache.trim();
      if (imageUrl.startsWith('http')) {
        _previousBackgroundImageUrl = imageUrl;
      }
    }

    setState(() {
      _allPosts = [];
      _friendsCurrentPage = 0;
      _recommendedCurrentPage = 0;
      _friendsHasMoreData = true;
      _recommendedHasMoreData = true;
      _allIsLoading = showLoading;
      _allIsLoadingMore = false;
      _allError = null;
      _allCurrentPostIndex = 0;
      _allIsCardShimmering = false;
      _allRefreshCount++; // 리프레시 카운터 증가
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
        _allIsCardShimmering = false; // 데이터 로드 완료 즉시 shimmer 해제
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
        _allIsCardShimmering = false; // 에러 시에도 shimmer 해제
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
                          ).colorScheme.background.withValues(alpha: 0.83),
                          Theme.of(
                            context,
                          ).colorScheme.background.withValues(alpha: 0.83),
                          Theme.of(
                            context,
                          ).colorScheme.background.withValues(alpha: 0.83),
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

    return PostList(
      key: ValueKey('all-${_allRefreshCount}'),
      containerWidth: screenWidth,
      posts: _allPosts,
      onLoadMore:
          (_friendsHasMoreData || _recommendedHasMoreData)
              ? _loadMoreAllPosts
              : null,
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
      onFilterTap: null, // 탭 전환 제거
      showAppBar: true,
      // 통합 피드 섹션
      sectionLabel: 'Doppy',
      appBarOpacity: _appBarOpacity, // 앱바 투명도 전달
      networkError: _allError, // 에러 상태 전달
      onRetryError: () => _loadAllPosts(refresh: true), // 에러 재시도 콜백
      isTabActive: widget.isActive, // 탭 활성
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
