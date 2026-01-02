import 'dart:async';
import 'dart:collection';
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/pages/screens/group_selection_screen.dart';
import 'package:doppy/image/utils/read_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doppy/l10n/app_localizations.dart';

class PostList extends StatefulWidget {
  final double containerWidth;
  final List<PostData> posts;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  final bool isLoading; // 초기 로딩 상태
  final Future<void> Function()? onRefresh;
  final Function(int)? onPageChanged;
  final bool showCardShimmer;

  // 홈화면 앱바 관련 파라미터들
  final bool isShowingFriendsOnly; // 친구글 탭인지 전체글 탭인지
  final VoidCallback? onFilterTap; // 섹션 전환 콜백
  final bool showAppBar; // 앱바 표시 여부
  final String? sectionLabel; // 섹션 레이블 (친구글/전체글)
  final double appBarOpacity; // 앱바 추가 투명도 (섹션 전환 시 페이드 효과)
  final NetworkError? networkError; // 네트워크 에러 상태
  final VoidCallback? onRetryError; // 에러 재시도 콜백
  final bool isTabActive; // 탭이 활성화되었는지 (다른 탭으로 이동하면 비디오 정지)

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.isLoading = false, // 기본값은 false
    this.onRefresh,
    this.onPageChanged,
    this.showCardShimmer = false,
    this.isShowingFriendsOnly = false,
    this.onFilterTap,
    this.showAppBar = true, // 기본값은 true (기존 동작 유지)
    this.sectionLabel,
    this.appBarOpacity = 1.0, // 기본값은 1.0 (완전 불투명)
    this.networkError, // 네트워크 에러 상태
    this.onRetryError, // 에러 재시도 콜백
    this.isTabActive = true, // 기본값은 활성화
  });

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = 0;
  late List<PostData> _items;
  final LinkedHashSet<String> _prefetchedThumbs = LinkedHashSet<String>();
  bool _prefetchScheduled = false;
  double _lastPullProgress = 0.0;

  // ✅ 좌/우 넘김 애니메이션을 통일해서 체감을 부드럽게
  static const Duration _pageTurnDuration = Duration(milliseconds: 200);
  static const Curve _pageTurnCurve = Curves.easeInOut;

  // 🎯 친구글이 없을 때 보여줄 온보딩 플레이스홀더 아이템
  final List<PostData> _noFriendPostItem = [
    PostData(
      id: 'onboarding_placeholder',
      title: '아직 친구글이 없어요',
      content: '', // 🎯 content는 빈 문자열로 (JSON 파싱 에러 방지)
      author: '',
      authorProfileImageUrl: 'test',
      thumbnailImageUrl: 'assets/images/onboarding1.png',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      summary: '친구 초대하고 그룹 만들기', // 🎯 summary에 텍스트 넣기
      accessLevel: AccessLevel.public,
      viewCount: 0,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
    ),
    PostData(
      id: 'onboarding_placeholder2',
      title: '포스트를 게시해보세요',
      content: '', // 🎯 content는 빈 문자열로 (JSON 파싱 에러 방지)
      author: 'test',
      authorProfileImageUrl: 'test',
      thumbnailImageUrl: 'assets/images/onboarding2.png',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      summary: '지금 바로 작성하기', // 🎯 summary에 텍스트 넣기
      accessLevel: AccessLevel.public,
      viewCount: 0,
      likeCount: 0,
      commentCount: 0,
      isLiked: false,
    ),
  ];

  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();
  bool _suppressVisibility = false; // 글 보기로 이동 시 일시적으로 재생 차단

  double _gestureAccumY = 0.0;
  double _gestureAccumX = 0.0;
  bool _isGestureActive = false;
  bool _isHorizontalGesture = false; // 가로 제스처 감지 여부
  double _pullProgress = 0.0; // 당기는 진행률 (0.0 ~ 1.0)
  double _verticalSwipeThreshold = 250.0; // 500.0에서 200.0으로 낮춤
  bool _hideAllPostsButton = false; // 🎯 전체 글 보러가기 버튼 숨김 플래그

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
    _items = List<PostData>.from(widget.posts);

    // LikeService 변경사항 감지
    _likeService.addListener(_onLikeServiceChanged);

    // 각 게시물의 좋아요 상태 확인
    _loadLikeStatusForAllPosts();

    // ✅ 다음 카드(들) 썸네일 미리 프리캐시 (현재 카드가 중앙에 오기 전)
    _schedulePrefetchAround(_currentIndex);
  }

  List<PostData> _postsToUse() =>
      _items.isEmpty && widget.isShowingFriendsOnly
          ? _noFriendPostItem
          : _items;

  bool _isNetworkUrl(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  void _touchPrefetchedThumb(String url) {
    // LRU-ish: 최근 접근을 뒤로 이동
    _prefetchedThumbs.remove(url);
    _prefetchedThumbs.add(url);

    // 상한을 둬서 무한 성장 방지 (메모리 누수 느낌 제거)
    const int maxEntries = 250;
    while (_prefetchedThumbs.length > maxEntries) {
      _prefetchedThumbs.remove(_prefetchedThumbs.first);
    }
  }

  void _schedulePrefetchAround(int index) {
    if (_prefetchScheduled) return;
    _prefetchScheduled = true;
    Future.microtask(() async {
      _prefetchScheduled = false;
      if (!mounted) return;
      await _prefetchAround(index);
    });
  }

  Future<void> _prefetchAround(int index) async {
    final postsToUse = _postsToUse();
    if (postsToUse.isEmpty) return;

    // 다음 2장만 선로드 (너무 공격적이면 메모리/네트워크 낭비)
    final nextIndices = <int>[index + 1, index + 2];

    for (final i in nextIndices) {
      if (i < 0 || i >= postsToUse.length) continue;
      final url = postsToUse[i].thumbnailUrlForCache.trim();
      if (!_isNetworkUrl(url)) continue;
      if (_prefetchedThumbs.contains(url)) {
        _touchPrefetchedThumb(url);
        continue;
      }
      _touchPrefetchedThumb(url);

      try {
        // PostCard와 동일하게 width=800 기준으로 프리캐시
        await precacheImage(
          ReadImageProvider.build(url: url, decodeWidth: 800),
          context,
        );
      } catch (_) {
        // 실패는 무시 (다음 프레임에서 자연 로드)
      }
    }
  }

  void _onLikeServiceChanged() {
    // 🎯 PostList에서 setState 제거: 각 PostCard가 이미 LikeService 변경을 감지하고 있으므로
    // PostList 전체를 리빌드할 필요 없음 (불필요한 리빌드 방지)
    // 각 PostCard의 _onLikeServiceChanged가 개별적으로 setState를 호출함
  }

  void _loadLikeStatusForAllPosts() {
    // PostData에서 직접 좋아요 상태와 수 설정
    // 🎯 LikeService에 값이 없을 때만 설정 (다른 화면에서 좋아요를 누른 경우 덮어쓰지 않음)
    for (final post in _items) {
      final postId = post.id.toString();
      if (postId.isNotEmpty && !_likeService.hasPost(postId)) {
        _likeService.setInitialLikeData(postId, post.isLiked, post.likeCount);
      }
    }
  }

  void _loadLikeStatusForNewPosts(List<PostData> newPosts) {
    // 새로운 게시물들의 좋아요 상태와 수 설정
    // 🎯 LikeService에 값이 없을 때만 설정 (다른 화면에서 좋아요를 누른 경우 덮어쓰지 않음)
    for (final post in newPosts) {
      final postId = post.id.toString();
      if (postId.isNotEmpty && !_likeService.hasPost(postId)) {
        _likeService.setInitialLikeData(postId, post.isLiked, post.likeCount);
      }
    }
  }

  @override
  void didUpdateWidget(PostList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 부모에서 같은 리스트 인스턴스를 mutate(addAll)해도 길이 변경을 감지하여 동기화
    final int newLen = widget.posts.length;
    if (newLen != _items.length || widget.posts != oldWidget.posts) {
      assert(() {
        debugPrint(' PostList 업데이트: 기존 ${_items.length}개 → 새로운 $newLen개');
        return true;
      }());

      if (newLen > _items.length) {
        // 증가: 새로 추가된 항목들만 반영
        final newPosts = widget.posts.sublist(_items.length);
        _items.addAll(newPosts);
        _loadLikeStatusForNewPosts(newPosts);
        assert(() {
          debugPrint('새로운 포스트 ${newPosts.length}개 추가됨');
          return true;
        }());
      } else {
        // 감소하거나 완전 교체: 전체 재동기화
        _items = List<PostData>.from(widget.posts);
        _loadLikeStatusForAllPosts();
        _prefetchedThumbs.clear(); // ✅ 새 피드로 교체되면 프리패치도 리셋
        assert(() {
          debugPrint('[PostList] 포스트 목록 재동기화(길이 감소/교체)');
          return true;
        }());

        // 현재 인덱스를 0으로 리셋 (즉시 반영하여 PostCard의 isVisible 업데이트)
        _currentIndex = 0;

        // PageController를 0으로 이동 (이미 0이어도 강제 실행)
        if (_pageController.hasClients && _items.isNotEmpty) {
          // 즉시 실행하여 페이지 위치 동기화
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients && _items.isNotEmpty) {
              // 현재 페이지가 0이 아닐 때만 jumpToPage 호출
              if ((_pageController.page ?? 0).round() != 0) {
                _pageController.jumpToPage(0);
                assert(() {
                  debugPrint('[PostList] PageController를 0으로 이동');
                  return true;
                }());
              } else {
                assert(() {
                  debugPrint('[PostList] PageController 이미 0번 페이지');
                  return true;
                }());
              }
            }
          });
        }
      }
    }

    // 데이터가 바뀌었으면 현재 위치 기준으로 다시 프리캐시
    _schedulePrefetchAround(_currentIndex);

    // 🎯 섹션이 변경되면 (친구글 -> 전체글) 버튼 숨김 플래그 리셋
    if (widget.isShowingFriendsOnly != oldWidget.isShowingFriendsOnly) {
      _hideAllPostsButton = false;
    }
  }

  @override
  void dispose() {
    _likeService.removeListener(_onLikeServiceChanged);
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildScrollView(BuildContext context) {
    return CustomScrollView(
      controller: _scrollController,
      physics:
          _isHorizontalGesture
              ? const NeverScrollableScrollPhysics() // 가로 제스처 시 스크롤 차단
              : const AlwaysScrollableScrollPhysics(),
      slivers: [
        // AppBar (조건부 표시)
        if (widget.showAppBar)
          SliverAppBar(
            toolbarHeight: 35,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            pinned: false,
            floating: true,
            snap: false,
            title: AnimatedOpacity(
              opacity:
                  (1.0 - _pullProgress) *
                  widget.appBarOpacity, // 🎯 친구 탭과 전체글 탭 모두 계속 표시
              duration:
                  _pullProgress != 0.0
                      ? Duration(milliseconds: 0)
                      : Duration(milliseconds: 300), // 🎯 페이드 아웃을 더 부드럽게
              curve: Curves.easeInOut,
              child: Container(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  widget.isShowingFriendsOnly ? ' Doppy' : ' All Posts',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            centerTitle: false,
            actions: [],
          ),
        SliverToBoxAdapter(
          child: Container(
            height: 50,
            decoration: BoxDecoration(color: Colors.transparent),
          ),
        ),

        // PageView 또는 빈 상태
        if (_items.isEmpty && !widget.showCardShimmer && !widget.isLoading)
          // 🎯 친구글이 없을 때는 온보딩 플레이스홀더 표시
          widget.isShowingFriendsOnly
              ? SliverToBoxAdapter(
                child: Container(
                  height: 400,
                  decoration: BoxDecoration(color: Colors.transparent),
                  child: PageView.builder(
                    scrollDirection: Axis.horizontal,
                    controller: _pageController,
                    pageSnapping: true,
                    physics:
                        const ClampingScrollPhysics(), // 🎯 전체글 탭과 동일하게 끝에서 당겨지지 않도록
                    clipBehavior: Clip.none,
                    padEnds: true,
                    allowImplicitScrolling: false,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });

                      // 페이지 변경 콜백 호출
                      if (widget.onPageChanged != null) {
                        widget.onPageChanged!(index);
                      }
                    },
                    itemCount: _noFriendPostItem.length,
                    itemBuilder: (context, index) {
                      final post = _noFriendPostItem[index];
                      return _buildPostItem(context, post, index);
                    },
                  ),
                ),
              )
              // 🎯 전체글이 비어있을 때는 빈 상태 표시 (위로 스와이프 지원)
              : SliverFillRemaining(
                hasScrollBody: false,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (details) {
                    _gestureAccumY = 0.0;
                    _gestureAccumX = 0.0;
                    _isGestureActive = true;
                    _isHorizontalGesture = false;
                  },
                  onPointerMove: (details) {
                    if (!_isGestureActive) return;

                    // 세로 제스처만 처리 (빈 상태에서는 가로 제스처 없음)
                    _gestureAccumY += details.delta.dy;

                    // 위로 스와이프 감지 (섹션 전환용)
                    if (_gestureAccumY < -_verticalSwipeThreshold &&
                        widget.onFilterTap != null) {
                      debugPrint('⬆️ 빈 상태에서 위로 스와이프 감지! 섹션 전환');
                      widget.onFilterTap!();
                      _isGestureActive = false;
                      return;
                    }
                  },
                  onPointerUp: (details) {
                    _isGestureActive = false;
                    _isHorizontalGesture = false;
                    _gestureAccumY = 0.0;
                    _gestureAccumX = 0.0;
                  },
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
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
                            AppLocalizations.of(context).translate('no_posts'),
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
                  ),
                ),
              )
        else
          SliverToBoxAdapter(
            child: Container(
              height: 400,
              decoration: BoxDecoration(color: Colors.transparent),
              child: PageView.builder(
                scrollDirection: Axis.horizontal,
                controller: _pageController,
                pageSnapping: true,
                physics: const ClampingScrollPhysics(),
                clipBehavior: Clip.none,
                padEnds: true,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });

                  // 페이지 변경 콜백 호출
                  if (widget.onPageChanged != null) {
                    widget.onPageChanged!(index);
                  }

                  // ✅ 다음 카드 프리캐시 (현재 카드가 중앙일 때 이미 다음 이미지가 준비되도록)
                  _schedulePrefetchAround(index);

                  // 무한 스크롤: 마지막 페이지 근처에서 더 로드 (더 일찍 트리거)
                  if (widget.onLoadMore != null &&
                      index >= _items.length - 5 &&
                      !widget.isLoadingMore) {
                    assert(() {
                      debugPrint(
                        '🔄 로드 모어 실행! 현재 인덱스: $index, 전체 아이템: ${_items.length}',
                      );
                      return true;
                    }());
                    widget.onLoadMore!();
                  }
                },
                itemCount: _items.length + (widget.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _items.length) {
                    // 로딩 인디케이터
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            '더 많은 포스트를 불러오는 중...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    );
                  }

                  final post = _items[index];
                  return _buildPostItem(context, post, index);
                },
              ),
            ),
          ),

        // Author Section
        SliverFillRemaining(
          hasScrollBody: false,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (details) {
              _gestureAccumY = 0.0;
              _gestureAccumX = 0.0;
              _isGestureActive = true;
              _isHorizontalGesture = false;
            },
            onPointerMove: (details) {
              if (!_isGestureActive) return;

              // 제스처 방향 결정 (더 빠르게, 더 민감하게)
              if (!_isHorizontalGesture) {
                _gestureAccumY += details.delta.dy;
                _gestureAccumX += details.delta.dx;

                // 제스처 방향 빠르게 결정 (3px 이상 움직임 시)
                if (_gestureAccumX.abs() > 3 || _gestureAccumY.abs() > 3) {
                  // 가로 움직임이 세로보다 크면 가로 제스처로 고정
                  if (_gestureAccumX.abs() > _gestureAccumY.abs()) {
                    setState(() {
                      _isHorizontalGesture = true;
                    });
                    assert(() {
                      debugPrint('🔄 가로 제스처 감지! 세로 완전 차단');
                      return true;
                    }());
                  }
                }
              }

              // 가로 제스처가 활성화되면 세로 누적값 무시
              if (_isHorizontalGesture) {
                // 🎯 친구글이 없을 때는 _noFriendPostItem 사용
                final List<PostData> postsToUse =
                    _items.isEmpty && widget.isShowingFriendsOnly
                        ? _noFriendPostItem
                        : _items;

                _gestureAccumX += details.delta.dx;
                // 세로 움직임은 완전히 무시 (누적하지 않음)

                // 수평 스크롤만 처리
                if (_gestureAccumX.abs() > 30) {
                  if (_gestureAccumX > 0 && _currentIndex > 0) {
                    // 오른쪽으로 스크롤 - 이전 페이지
                    _pageController.previousPage(
                      duration: _pageTurnDuration,
                      curve: _pageTurnCurve,
                    );
                    _isGestureActive = false;
                  } else if (_gestureAccumX < 0 &&
                      _currentIndex < postsToUse.length - 1) {
                    // 왼쪽으로 스크롤 - 다음 페이지
                    _pageController.nextPage(
                      duration: _pageTurnDuration,
                      curve: _pageTurnCurve,
                    );
                    _isGestureActive = false;
                  }
                }
                return; // 세로 동작 완전 차단
              }

              // 세로 제스처 처리 (가로가 아닐 때만)
              _gestureAccumY += details.delta.dy;

              // 위로 스와이프 감지 (섹션 전환용)
              if (_gestureAccumY < -_verticalSwipeThreshold &&
                  widget.onFilterTap != null) {
                assert(() {
                  debugPrint(
                    '⬆️ Listener로 위로 스와이프 감지! 섹션 전환 (임계값: $_verticalSwipeThreshold)',
                  );
                  return true;
                }());
                widget.onFilterTap!();
                _isGestureActive = false;
                return;
              }
            },
            onPointerUp: (details) {
              if (_isGestureActive || _isHorizontalGesture) {
                setState(() {
                  _isGestureActive = false;
                  _isHorizontalGesture = false;
                });
              } else {
                _isGestureActive = false;
                _isHorizontalGesture = false;
              }
              _gestureAccumY = 0.0;
              _gestureAccumX = 0.0;
            },
            child: GestureDetector(
              onTapUp: (details) async {
                // 🎯 친구글이 없을 때는 _noFriendPostItem 사용
                final List<PostData> postsToUse =
                    _items.isEmpty && widget.isShowingFriendsOnly
                        ? _noFriendPostItem
                        : _items;

                if (postsToUse.isEmpty) return;

                // 텍스트 영역에서도 탭 위치에 따라 다른 동작
                final screenWidth = MediaQuery.of(context).size.width;
                final tapX = details.globalPosition.dx;

                if (tapX < screenWidth * 0.3) {
                  // 왼쪽 30% - 이전 페이지
                  if (_currentIndex > 0) {
                    _pageController.previousPage(
                      duration: _pageTurnDuration,
                      curve: _pageTurnCurve,
                    );
                  }
                } else if (tapX > screenWidth * 0.7) {
                  // 오른쪽 30% - 다음 페이지
                  if (_currentIndex < postsToUse.length - 1) {
                    _pageController.nextPage(
                      duration: _pageTurnDuration,
                      curve: _pageTurnCurve,
                    );
                  }
                } else {
                  // 중앙 40% - 포스트 상세보기 또는 글 작성 화면으로 이동
                  // 🎯 친구글이 없을 때는 _noFriendPostItem 사용
                  final List<PostData> postsToUse =
                      _items.isEmpty && widget.isShowingFriendsOnly
                          ? _noFriendPostItem
                          : _items;

                  if (postsToUse.isNotEmpty) {
                    final safeIndex = _currentIndex.clamp(
                      0,
                      postsToUse.length - 1,
                    );
                    final currentPost = postsToUse[safeIndex];

                    // 🎯 "아직 친구글이 없어요" 플레이스홀더를 클릭하면 그룹 선택 화면으로 이동
                    if (currentPost.id == 'onboarding_placeholder') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const GroupSelectionScreen(),
                        ),
                      );
                    } else if (currentPost.id == 'onboarding_placeholder2') {
                      // 🎯 "글을 작성해보세요" 플레이스홀더를 클릭하면 글 작성 화면으로 이동
                      Navigator.pushNamed(context, '/post-write');
                    } else if (_items.isNotEmpty &&
                        !widget.isShowingFriendsOnly) {
                      // 실제 포스트가 있을 때만 상세보기로 이동
                      setState(() => _suppressVisibility = true);
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => PostReaderScreen(
                                exported:
                                    _items[_currentIndex].toExportedData(),
                                heroTag:
                                    'post-hero-${widget.sectionLabel ?? "main"}-${_items[_currentIndex].id}-$_currentIndex-${widget.key?.hashCode ?? hashCode}',
                              ),
                        ),
                      );

                      // 🎯 공개 범위 변경 또는 삭제는 피드 자체가 처리하므로 여기서는 별도 처리 불필요
                      // (home_screen.dart에서 피드가 자동으로 새로고침되어 PostList는 didUpdateWidget으로 업데이트됨)
                      if (mounted) {
                        setState(() => _suppressVisibility = false);
                      }
                    }
                  }
                }
              },
              child: Container(
                decoration: BoxDecoration(color: Colors.transparent),
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  opacity: widget.appBarOpacity,
                  child: _textArea(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 친구글이 없을 때 하단에 "전체 글 보러가기" 버튼 표시
    final bool showAllPostsButton =
        _items.isEmpty &&
        !widget.showCardShimmer &&
        !widget.isLoading &&
        widget.isShowingFriendsOnly &&
        widget.onFilterTap != null &&
        _pullProgress == 0.0 && // 🎯 새로고침 당기기 시 숨김
        !_hideAllPostsButton; // 🎯 버튼을 눌렀을 때 숨김

    return SafeArea(
      child: Stack(
        children: [
          CustomRefreshIndicator(
            top: 50,
            onRefresh: widget.onRefresh,
            onPullProgress: (progress) {
              // ✅ drag 중 매 프레임 setState는 비싸다 → 임계치 기반으로만 업데이트
              final next = progress.clamp(0.0, 1.0);
              final diff = (next - _lastPullProgress).abs();
              if (diff < 0.02 && next != 0.0 && next != 1.0) return;
              _lastPullProgress = next;
              if (!mounted) return;
              setState(() {
                _pullProgress = next;
              });
            },
            child:
                widget.showCardShimmer
                    ? _buildRefreshingShimmer()
                    : _buildScrollView(context),
          ),
          // 🎯 친구글이 없을 때 하단에 "전체 글 보러가기" 버튼 표시
          if (showAllPostsButton)
            Positioned(
              left: 0,
              right: 0,
              bottom: 62,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    // 🎯 버튼을 눌렀을 때 즉시 숨김
                    setState(() {
                      _hideAllPostsButton = true;
                    });
                    widget.onFilterTap?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.transparent
                              : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      context.tr('view_all_posts'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.95),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    return GestureDetector(
      onTapUp: (details) {
        // 🎯 친구글이 없을 때는 _noFriendPostItem 사용
        final List<PostData> postsToUse =
            _items.isEmpty && widget.isShowingFriendsOnly
                ? _noFriendPostItem
                : _items;

        if (postsToUse.isEmpty) return;

        // 탭 위치에 따라 다른 동작
        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = details.globalPosition.dx;

        if (tapX < screenWidth * 0.3) {
          // 왼쪽 30% - 이전 페이지
          if (_currentIndex > 0) {
            _pageController.previousPage(
              duration: _pageTurnDuration,
              curve: _pageTurnCurve,
            );
          }
        } else if (tapX > screenWidth * 0.7) {
          // 오른쪽 30% - 다음 페이지
          if (_currentIndex < postsToUse.length - 1) {
            _pageController.nextPage(
              duration: _pageTurnDuration,
              curve: _pageTurnCurve,
            );
          }
        } else {
          // 중앙 40% - 포스트 상세보기, 글 작성 화면, 또는 그룹 선택 화면으로 이동
          // 🎯 "아직 친구글이 없어요" 플레이스홀더를 클릭하면 그룹 선택 화면으로 이동
          if (post.id == 'onboarding_placeholder') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const GroupSelectionScreen(),
              ),
            );
          } else if (post.id == 'onboarding_placeholder2') {
            // 🎯 "글을 작성해보세요" 플레이스홀더를 클릭하면 글 작성 화면으로 이동
            Navigator.pushNamed(context, '/post-write');
          } else if (_items.isNotEmpty &&
              !post.id.startsWith('onboarding_placeholder')) {
            // 먼저 현재 프레임에서 가시성 차단을 적용
            setState(() => _suppressVisibility = true);
            // 다음 프레임에서 push하여 정지가 먼저 반영되도록 함
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => PostReaderScreen(
                        exported: post.toExportedData(),
                        heroTag:
                            'post-hero-${widget.sectionLabel ?? "main"}-${post.id}-$index-${widget.key?.hashCode ?? hashCode}',
                      ),
                ),
              );

              // 🎯 공개 범위 변경 또는 삭제는 피드 자체가 처리하므로 여기서는 별도 처리 불필요
              // (home_screen.dart에서 피드가 자동으로 새로고침되어 PostList는 didUpdateWidget으로 업데이트됨)
              if (mounted) {
                setState(() => _suppressVisibility = false);
              }
            });
          }
        }
      },
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, _) {
          final double pageNow =
              _pageController.hasClients
                  ? (_pageController.page ?? _currentIndex.toDouble())
                  : _currentIndex.toDouble();
          final double ad = (pageNow - index).abs().clamp(0.0, 1.0);
          final double t = 1.0 - ad; // 0.0~1.0 노출 비율 근사치
          final double eased = Curves.easeOutCubic.transform(t);
          final double scale = 0.85 + 0.15 * eased;
          final bool isMainVisible =
              widget.isTabActive &&
              !_suppressVisibility &&
              t >= 0.7; // 70% 이상 노출일 때만 재생

          return Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child:
                    widget.showCardShimmer
                        ? _buildImageAreaShimmer()
                        : PostCard(
                          key: ValueKey('postcard_${post.id}'),
                          containerWidth: widget.containerWidth,
                          thumbnailImageUrl: post.thumbnailUrlForCache,
                          heroTag:
                              'post-hero-${widget.sectionLabel ?? "main"}-${post.id}-$index-${widget.key?.hashCode ?? hashCode}',
                          title: post.title,
                          author: post.author,
                          authorProfileImageUrl: post.authorProfileImageUrl,
                          content: post.parsedContent,
                          isVisible: isMainVisible,
                          postId: post.id.toString(),
                          isLiked: _likeService.isPostLiked(post.id.toString()),
                          likeCount: _likeService.getPostLikeCount(
                            post.id.toString(),
                          ),
                          onLikePressed: () async {
                            final id = post.id.toString();
                            if (id.isEmpty) return;

                            if (_likingInFlight.contains(id)) return;
                            setState(() => _likingInFlight.add(id));

                            try {
                              await _likeService.togglePostLike(id);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('좋아요 처리 중 오류가 발생했습니다'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(milliseconds: 900),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _likingInFlight.remove(id));
                              }
                            }
                          },
                        ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRefreshingShimmer() {
    // 새로고침 중 PostList와 동일한 레이아웃의 shimmer 표시
    return CustomScrollView(
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        // AppBar 영역 (투명)
        if (widget.showAppBar)
          SliverAppBar(
            toolbarHeight: 55,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            pinned: false,
            floating: true,
          ),
        SliverToBoxAdapter(child: Container(height: 35)),

        // PageView 영역의 shimmer
        SliverToBoxAdapter(
          child: Container(
            height: 400,
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: _buildImageAreaShimmer(),
              ),
            ),
          ),
        ),

        // 텍스트 영역 shimmer
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // 제목 shimmer
                ShimmerBox(
                  width: 200,
                  height: 32,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                // 내용 shimmer (여러 줄)
                ShimmerBox(
                  width: double.infinity,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                ShimmerBox(
                  width: double.infinity,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                ShimmerBox(
                  width: MediaQuery.of(context).size.width * 0.6,
                  height: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageAreaShimmer() {
    // PostCard의 이미지 영역과 동일 크기로 보이도록, 이미지 자체만 쉬머 느낌으로
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ShimmerBox(
          width: double.infinity,
          height: double.infinity,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _textArea(BuildContext context) {
    // 🎯 친구글이 없을 때는 _noFriendPostItem 사용
    final List<PostData> postsToUse =
        _items.isEmpty && widget.isShowingFriendsOnly
            ? _noFriendPostItem
            : _items;

    if (postsToUse.isEmpty) {
      // 빈 상태일 때는 빈 공간 표시
      return const SizedBox.shrink();
    }

    final safeIndex = _currentIndex.clamp(0, postsToUse.length - 1);
    final post = postsToUse[safeIndex];

    return GestureDetector(
      onTapUp: (details) {
        // 🎯 텍스트 영역에서도 탭 위치에 따라 다른 동작
        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = details.globalPosition.dx;

        if (tapX < screenWidth * 0.3) {
          // 왼쪽 30% - 이전 페이지
          if (_currentIndex > 0) {
            _pageController.previousPage(
              duration: _pageTurnDuration,
              curve: _pageTurnCurve,
            );
          }
        } else if (tapX > screenWidth * 0.7) {
          // 오른쪽 30% - 다음 페이지
          if (_currentIndex < postsToUse.length - 1) {
            _pageController.nextPage(
              duration: _pageTurnDuration,
              curve: _pageTurnCurve,
            );
          }
        } else {
          // 중앙 40% - 포스트 상세보기로 이동
          if (post.id == 'onboarding_placeholder') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const GroupSelectionScreen(),
              ),
            );
          } else if (post.id == 'onboarding_placeholder2') {
            Navigator.pushNamed(context, '/post-write');
          } else if (_items.isNotEmpty &&
              !post.id.startsWith('onboarding_placeholder')) {
            // 먼저 현재 프레임에서 가시성 차단을 적용
            setState(() => _suppressVisibility = true);
            // 다음 프레임에서 push하여 정지가 먼저 반영되도록 함
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => PostReaderScreen(
                        exported: post.toExportedData(),
                        heroTag:
                            'post-hero-${widget.sectionLabel ?? "main"}-${post.id}-$safeIndex-${widget.key?.hashCode ?? hashCode}',
                      ),
                ),
              );

              if (mounted) {
                setState(() => _suppressVisibility = false);
              }
            });
          }
        }
      },
      behavior: HitTestBehavior.opaque, // 🎯 빈 공간도 클릭 가능하도록 설정
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(height: 10),
            // 제목
            Text(
              post.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // 내용 (남은 공간 모두 사용, 최소 높이 보장)
            Expanded(
              child: Text(
                post.parsedContent,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  letterSpacing: -0.1,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
