import 'dart:async';
import 'package:doppy/pages/components/post_card.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/firestore_notification_service.dart';

/// 연도와 주차 정보를 담는 객체
class YearWeek {
  final int year;
  final int week;

  const YearWeek({required this.year, required this.week});
}

class PostList extends StatefulWidget {
  final double containerWidth;
  final List<PostData> posts;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  final Function(int)? onPageChanged;
  final bool showCardShimmer;

  // 최소한의 파라미터만 유지
  final bool showAppBar; // 앱바 표시 여부
  final bool isTabActive; // 탭이 활성화되었는지 (다른 탭으로 이동하면 비디오 정지)
  final YearWeek? yearWeek; // 연도와 주차 정보

  const PostList({
    super.key,
    required this.containerWidth,
    required this.posts,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.onPageChanged,
    this.showCardShimmer = false,
    this.showAppBar = true,
    this.isTabActive = true,
    this.yearWeek,
  });

  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
  late PageController _pageController;
  int _currentIndex = 0;
  late List<PostData> _items;

  final Set<String> _likingInFlight = <String>{};
  final LikeService _likeService = LikeService();
  final FirestoreNotificationService _notificationService =
      FirestoreNotificationService();
  bool _suppressVisibility = false; // 글 보기로 이동 시 일시적으로 재생 차단

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
    _items = List<PostData>.from(widget.posts);

    // 각 게시물의 좋아요 상태 확인
    _loadLikeStatusForAllPosts();

    // 읽지 않은 알림 개수 로드
    _loadUnreadNotificationCount();
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      await _notificationService.getUnreadCount();
    } catch (e) {
      debugPrint('[PostList] 읽지 않은 알림 개수 조회 실패: $e');
    }
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
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildScrollView(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // AppBar (조건부 표시) - 몇 년 몇 주차만 표시
        if (widget.showAppBar)
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
                widget.yearWeek != null
                    ? '${widget.yearWeek!.year}년 ${widget.yearWeek!.week}주차'
                    : ' Doppy',
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
          ),

        SliverToBoxAdapter(
          child: Container(
            height: 50,
            decoration: BoxDecoration(color: Colors.transparent),
          ),
        ),

        // PageView
        if (_items.isEmpty && !widget.showCardShimmer)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
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

        // 텍스트 영역 (간소화)
        SliverFillRemaining(
          hasScrollBody: false,
          child: GestureDetector(
            onTapUp: (details) {
              if (_items.isEmpty) return;

              final screenWidth = MediaQuery.of(context).size.width;
              final tapX = details.globalPosition.dx;

              if (tapX < screenWidth * 0.3 && _currentIndex > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                );
              } else if (tapX > screenWidth * 0.7 &&
                  _currentIndex < _items.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                );
              } else {
                // 중앙 탭: 포스트 상세보기
                if (_items.isNotEmpty) {
                  setState(() => _suppressVisibility = true);
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder:
                              (_) => PostReaderScreen(
                                exported:
                                    _items[_currentIndex].toExportedData(),
                              ),
                        ),
                      )
                      .then((_) {
                        if (mounted) {
                          setState(() => _suppressVisibility = false);
                        }
                      });
                }
              }
            },
            child: _textArea(context),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: _buildScrollView(context));
  }

  Widget _buildPostItem(BuildContext context, PostData post, int index) {
    return GestureDetector(
      onTapUp: (details) {
        if (_items.isEmpty) return;

        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = details.globalPosition.dx;

        if (tapX < screenWidth * 0.3 && _currentIndex > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
          );
        } else if (tapX > screenWidth * 0.7 &&
            _currentIndex < _items.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
          );
        } else {
          // 중앙 탭: 포스트 상세보기
          setState(() => _suppressVisibility = true);
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder:
                      (_) => PostReaderScreen(exported: post.toExportedData()),
                ),
              )
              .then((_) {
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
                          key: ValueKey('postcard_${post.id}'),
                          containerWidth: widget.containerWidth,
                          thumbnailImageUrl: post.thumbnailUrlForCache,
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
    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }

    final safeIndex = _currentIndex.clamp(0, _items.length - 1);
    final post = _items[safeIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
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
          // 내용
          Expanded(
            child: Text(
              post.parsedContent,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.5,
                letterSpacing: -0.1,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
