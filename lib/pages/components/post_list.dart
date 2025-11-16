import 'dart:ui' as ui;
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

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
  final bool isShowingSearchResults;
  final String searchQuery;
  final VoidCallback? onSearchChipTap;
  final VoidCallback? onClearSearch;
  final bool isShowingFriendsOnly;
  final VoidCallback? onFilterTap;
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
    this.isShowingSearchResults = false,
    this.searchQuery = '',
    this.onSearchChipTap,
    this.onClearSearch,
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
  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();
  bool _suppressVisibility = false; // 글 보기로 이동 시 일시적으로 재생 차단

  double _gestureAccumY = 0.0;
  double _gestureAccumX = 0.0;
  bool _isGestureActive = false;
  bool _isHorizontalGesture = false; // 가로 제스처 감지 여부
  double _pullProgress = 0.0; // 당기는 진행률 (0.0 ~ 1.0)
  double _verticalSwipeThreshold = 250.0; // 500.0에서 200.0으로 낮춤

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
    _items = List<PostData>.from(widget.posts);

    // LikeService 변경사항 감지
    _likeService.addListener(_onLikeServiceChanged);

    // 각 게시물의 좋아요 상태 확인
    _loadLikeStatusForAllPosts();
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _loadLikeStatusForAllPosts() {
    // PostData에서 직접 좋아요 상태와 수 설정
    for (final post in _items) {
      final postId = post.id.toString();
      if (postId.isNotEmpty) {
        _likeService.setInitialLikeData(postId, post.isLiked, post.likeCount);
      }
    }
  }

  void _loadLikeStatusForNewPosts(List<PostData> newPosts) {
    // 새로운 게시물들의 좋아요 상태와 수 설정
    for (final post in newPosts) {
      final postId = post.id.toString();
      if (postId.isNotEmpty) {
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
      print(' PostList 업데이트: 기존 ${_items.length}개 → 새로운 $newLen개');

      if (newLen > _items.length) {
        // 증가: 새로 추가된 항목들만 반영
        final newPosts = widget.posts.sublist(_items.length);
        _items.addAll(newPosts);
        _loadLikeStatusForNewPosts(newPosts);
        print('새로운 포스트 ${newPosts.length}개 추가됨');
      } else {
        // 감소하거나 완전 교체: 전체 재동기화
        _items = List<PostData>.from(widget.posts);
        _loadLikeStatusForAllPosts();
        print('[PostList] 포스트 목록 재동기화(길이 감소/교체)');

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
                print('[PostList] PageController를 0으로 이동');
              } else {
                print('[PostList] PageController 이미 0번 페이지');
              }

              // 항상 한 번 더 setState하여 PostCard들이 완전히 재빌드되도록 보장
              // 특히 0번 포스트가 비디오인 경우 볼륨이 재설정되어야 함
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    print('[PostList] 강제 재빌드로 볼륨 재설정 트리거');
                  });
                }
              });
            }
          });
        }
      }
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
              opacity: (1.0 - _pullProgress) * widget.appBarOpacity,
              duration:
                  _pullProgress != 0.0
                      ? Duration(milliseconds: 0)
                      : Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              child:
                  widget.isShowingSearchResults
                      ? Container() // 검색 결과일 때는 doppy 로고 숨김
                      : Container(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          ' doppy',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
            ),
            centerTitle: false,
            actions: [
              // 검색 중이면 검색어 칩, 아니면 필터 아이콘
              AnimatedOpacity(
                opacity: (1.0 - _pullProgress) * widget.appBarOpacity,
                duration: Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child:
                    widget.isShowingSearchResults &&
                            widget.searchQuery.isNotEmpty
                        ? GestureDetector(
                          onTap: widget.onSearchChipTap,
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(width: 8),
                                      Text(
                                        widget.searchQuery,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        onTap: widget.onClearSearch,
                                        child: Icon(
                                          Icons.close,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        : Padding(
                          padding: const EdgeInsets.only(right: 20, top: 6),
                          child: GestureDetector(
                            onTap: widget.onFilterTap,
                            child: Row(
                              children: [
                                if (widget.sectionLabel != null) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      widget.sectionLabel!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(1),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 24,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.9),
                                ),
                              ],
                            ),
                          ),
                        ),
              ),
            ],
          ),
        SliverToBoxAdapter(
          child: Container(
            height: 50,
            decoration: BoxDecoration(color: Colors.transparent),
          ),
        ),

        // PageView 또는 빈 상태
        SliverToBoxAdapter(
          child: Container(
            height: 400,
            decoration: BoxDecoration(color: Colors.transparent),
            child:
                _items.isEmpty && !widget.showCardShimmer && !widget.isLoading
                    ? _buildEmptyState(context)
                    : PageView.builder(
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

                        // 무한 스크롤: 마지막 페이지 근처에서 더 로드
                        if (widget.onLoadMore != null &&
                            index >= _items.length - 2 &&
                            !widget.isLoadingMore) {
                          print(
                            '🔄 로드 모어 실행! 현재 인덱스: $index, 전체 아이템: ${_items.length}',
                          );
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
                    print('🔄 가로 제스처 감지! 세로 완전 차단');
                  }
                }
              }

              // 가로 제스처가 활성화되면 세로 누적값 무시
              if (_isHorizontalGesture) {
                _gestureAccumX += details.delta.dx;
                // 세로 움직임은 완전히 무시 (누적하지 않음)

                // 수평 스크롤만 처리
                if (_gestureAccumX.abs() > 30) {
                  if (_gestureAccumX > 0 && _currentIndex > 0) {
                    // 오른쪽으로 스크롤 - 이전 페이지
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                    );
                    _isGestureActive = false;
                  } else if (_gestureAccumX < 0 &&
                      _currentIndex < _items.length - 1) {
                    // 왼쪽으로 스크롤 - 다음 페이지
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
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
                  widget.onFilterTap != null &&
                  !widget.isShowingSearchResults) {
                print(
                  '⬆️ Listener로 위로 스와이프 감지! 섹션 전환 (임계값: $_verticalSwipeThreshold)',
                );
                widget.onFilterTap!();
                _isGestureActive = false;
                return;
              }
            },
            onPointerUp: (details) {
              setState(() {
                _isGestureActive = false;
                _isHorizontalGesture = false;
              });
              _gestureAccumY = 0.0;
              _gestureAccumX = 0.0;
            },
            child: GestureDetector(
              onTapUp: (details) async {
                // 텍스트 영역에서도 탭 위치에 따라 다른 동작
                final screenWidth = MediaQuery.of(context).size.width;
                final tapX = details.globalPosition.dx;

                if (tapX < screenWidth * 0.2) {
                  // 왼쪽 30% - 이전 페이지
                  if (_currentIndex > 0) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else if (tapX > screenWidth * 0.8) {
                  // 오른쪽 30% - 다음 페이지
                  if (_currentIndex < _items.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                    );
                  }
                } else {
                  setState(() => _suppressVisibility = true);
                  // 중앙 40% - 포스트 상세보기
                  await Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 340),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 100,
                      ),
                      opaque: false,
                      pageBuilder:
                          (_, __, ___) => PostReaderScreen(
                            exported: _items[_currentIndex].toExportedData(),
                            heroTag:
                                'post-hero-${widget.sectionLabel ?? "main"}-${_items[_currentIndex].id}-$_currentIndex',
                          ),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) {
                        const begin = Offset(0.0, 0.1);
                        const end = Offset.zero;
                        const curve = Curves.easeOutCubic;
                        var tween = Tween(
                          begin: begin,
                          end: end,
                        ).chain(CurveTween(curve: curve));
                        var offsetAnimation = animation.drive(tween);
                        var fadeAnimation = Tween<double>(
                          begin: 0.0,
                          end: 1.0,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                        );
                        return FadeTransition(
                          opacity: fadeAnimation,
                          child: SlideTransition(
                            position: offsetAnimation,
                            child: child,
                          ),
                        );
                      },
                    ),
                  );

                  // 🎯 공개 범위 변경 또는 삭제는 피드 자체가 처리하므로 여기서는 별도 처리 불필요
                  // (home_screen.dart에서 피드가 자동으로 새로고침되어 PostList는 didUpdateWidget으로 업데이트됨)
                  if (mounted) {
                    setState(() => _suppressVisibility = false);
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
    return SafeArea(
      child: CustomRefreshIndicator(
        top: 50,
        onRefresh: widget.onRefresh,
        onPullProgress: (progress) {
          setState(() {
            _pullProgress = progress;
          });
        },
        child:
            widget.showCardShimmer
                ? _buildRefreshingShimmer()
                : _buildScrollView(context),
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    return GestureDetector(
      onTapUp: (details) {
        // 탭 위치에 따라 다른 동작
        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = details.globalPosition.dx;

        if (tapX < screenWidth * 0.3) {
          // 왼쪽 30% - 이전 페이지
          if (_currentIndex > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        } else if (tapX > screenWidth * 0.7) {
          // 오른쪽 30% - 다음 페이지
          if (_currentIndex < _items.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        } else {
          // 중앙 40% - 포스트 상세보기
          // 먼저 현재 프레임에서 가시성 차단을 적용
          setState(() => _suppressVisibility = true);
          // 다음 프레임에서 push하여 정지가 먼저 반영되도록 함
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await Navigator.of(context).push(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 340),
                reverseTransitionDuration: const Duration(milliseconds: 100),
                opaque: false,
                pageBuilder:
                    (_, __, ___) => PostReaderScreen(
                      exported: post.toExportedData(),
                      heroTag:
                          'post-hero-${widget.sectionLabel ?? "main"}-${post.id}-$index',
                    ),
                transitionsBuilder: (
                  context,
                  animation,
                  secondaryAnimation,
                  child,
                ) {
                  const begin = Offset(0.0, 0.1);
                  const end = Offset.zero;
                  const curve = Curves.easeOutCubic;
                  var tween = Tween(
                    begin: begin,
                    end: end,
                  ).chain(CurveTween(curve: curve));
                  var offsetAnimation = animation.drive(tween);
                  var fadeAnimation = Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  );
                  return FadeTransition(
                    opacity: fadeAnimation,
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  );
                },
              ),
            );

            // 🎯 공개 범위 변경 또는 삭제는 피드 자체가 처리하므로 여기서는 별도 처리 불필요
            // (home_screen.dart에서 피드가 자동으로 새로고침되어 PostList는 didUpdateWidget으로 업데이트됨)
            if (mounted) {
              setState(() => _suppressVisibility = false);
            }
          });
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
                          containerWidth: widget.containerWidth,
                          thumbnailImageUrl: post.thumbnailImageUrl,
                          heroTag:
                              'post-hero-${widget.sectionLabel ?? "main"}-${post.id}-$index',
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

  Widget _buildEmptyState(BuildContext context) {
    // 현재 탭에 따른 메시지 결정
    String message;
    String subtitle;
    bool showRecommendButton = false;

    if (widget.isShowingSearchResults) {
      message = context.tr('no_search_results_short');
      subtitle = '"${widget.searchQuery}"${context.tr('no_results_for_query')}';
      showRecommendButton = false; // 검색 중에는 추천글 이동 버튼 숨김
    } else if (widget.isShowingFriendsOnly) {
      message = context.tr('no_friend_posts');
      subtitle = context.tr('post_first_today');
      showRecommendButton = true; // 친구글 탭에서만 추천글 버튼 표시
    } else {
      message = context.tr('no_posts_yet');
      subtitle = context.tr('new_posts_coming_soon');
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 200),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),

          // 추천글 보러가기 버튼 (친구글 탭에서만 표시)
          if (showRecommendButton) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                // 전체글 탭으로 전환 (위로 스와이프와 동일한 동작)
                if (widget.onFilterTap != null) {
                  widget.onFilterTap!();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('go_to_recommended'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textArea(BuildContext context) {
    if (_items.isEmpty) {
      // 빈 상태일 때는 빈 공간 표시
      return const SizedBox.shrink();
    }
    final safeIndex = _currentIndex.clamp(0, _items.length - 1);
    final post = _items[safeIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
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
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // 내용 (남은 공간 모두 사용)
          Expanded(
            child: Text(
              post.parsedContent,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.w300,
                height: 1.8,
                letterSpacing: -0.1,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
