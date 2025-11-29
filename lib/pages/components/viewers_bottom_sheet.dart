import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/profile_action_bottom_sheet.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/time_utils.dart';

/// 🎯 포스트를 본 사용자 목록 오버레이
class ViewersBottomSheet extends StatefulWidget {
  final String postId;
  final int viewerCount; // 🎯 포스트의 전체 조회수 (페이지네이션과 무관)
  final VoidCallback? onClose; // 🎯 오버레이 닫기 콜백 (오버레이로 사용할 때)

  const ViewersBottomSheet({
    super.key,
    required this.postId,
    required this.viewerCount,
    this.onClose,
  });

  @override
  State<ViewersBottomSheet> createState() => _ViewersBottomSheetState();

  // 🎯 정적 캐시: postId별로 조회자 목록 저장 (클래스 레벨에서 관리)
  static final Map<String, List<Map<String, dynamic>>> _cache = {};
  static final Map<String, bool> _isLoadingCache = {};

  /// 🎯 조회자 목록 미리 로드 (비동기, 정적 메서드)
  static Future<void> preloadViewers(String postId) async {
    // 이미 캐시에 있거나 로딩 중이면 스킵
    if (_cache.containsKey(postId) && _cache[postId]!.isNotEmpty) {
      return;
    }
    if (_isLoadingCache[postId] == true) {
      return;
    }

    _isLoadingCache[postId] = true;
    final blogService = BlogService();

    try {
      final response = await blogService.getPostViewers(
        postId,
        page: 0,
        size: 20,
      );

      if (response.isNotEmpty) {
        final viewers = (response['viewers'] as List?) ?? [];
        final readers =
            viewers.map<Map<String, dynamic>>((viewer) {
              return {
                'username': viewer['username'] ?? '',
                'profileImageUrl': viewer['profileImageUrl'],
                'viewedAt': viewer['viewedAt'],
              };
            }).toList();

        // 🎯 캐시에 저장 (0페이지만)
        _cache[postId] = readers;
        debugPrint(
          '[ViewersBottomSheet] 조회자 목록 미리 로드 완료: $postId (${readers.length}명)',
        );
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 조회자 목록 미리 로드 실패: $e');
    } finally {
      _isLoadingCache[postId] = false;
    }
  }
}

class _ViewersBottomSheetState extends State<ViewersBottomSheet> {
  List<Map<String, dynamic>> _viewers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false; // 🎯 로드 모어 중인지
  bool _hasMore = true; // 🎯 더 있는지
  int _currentPage = 0; // 🎯 현재 페이지
  String? _error;
  final BlogService _blogService = BlogService();
  late final ScrollController _scrollController;
  double _pullProgress = 0.0; // 🎯 당기는 진행률 (0.0 ~ 1.0)

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // 🎯 캐시된 데이터가 있으면 즉시 표시 (shimmer 안 뜨게)
    final cached = ViewersBottomSheet._cache[widget.postId];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _viewers = cached;
        _isLoading = false;
        _currentPage = 1; // 캐시된 데이터가 있으면 다음은 page=1부터
      });
    } else {
      // 캐시된 데이터가 없거나 로딩 중이면 로드 시작
      // 이미 로딩 중이면 기다림 (로딩이 완료되면 캐시에 저장됨)
      if (ViewersBottomSheet._isLoadingCache[widget.postId] == true) {
        // 로딩 중이면 상태만 설정 (shimmer 표시)
        setState(() {
          _isLoading = true;
        });
        // 로딩이 완료될 때까지 대기 (폴링 방식 대신 바로 로드 시도)
        _waitForCacheOrLoad();
      } else {
        // 로딩 시작
        _loadViewers(forceRefresh: false);
      }
    }
  }

  /// 🎯 캐시가 준비될 때까지 대기하거나 바로 로드
  void _waitForCacheOrLoad() async {
    // 짧은 딜레이 후 캐시 확인
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final cached = ViewersBottomSheet._cache[widget.postId];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _viewers = cached;
        _isLoading = false;
        _currentPage = 1; // 캐시된 데이터가 있으면 다음은 page=1부터
      });
    } else if (ViewersBottomSheet._isLoadingCache[widget.postId] != true) {
      // 로딩이 끝났는데 캐시가 없으면 다시 로드
      _loadViewers(forceRefresh: false);
    } else {
      // 아직 로딩 중이면 다시 확인
      _waitForCacheOrLoad();
    }
  }

  /// 🎯 스크롤 리스너: 하단 도달 시 로드 모어
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMore) return;

    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final threshold = 200.0; // 하단 200px 전에 로드

    // 하단 근처에 도달하면 로드 모어
    if (maxScroll - offset < threshold) {
      _loadMoreViewers();
    }
  }

  // 🎯 조회자 정보 로드 (페이지네이션 지원)
  Future<void> _loadViewers({bool forceRefresh = false}) async {
    // 🎯 이미 로드 중이면 스킵 (중복 요청 방지)
    if (ViewersBottomSheet._isLoadingCache[widget.postId] == true &&
        !forceRefresh) {
      return;
    }

    // 🎯 캐시된 데이터가 있고 강제 새로고침이 아니면 스킵
    if (ViewersBottomSheet._cache[widget.postId] != null && !forceRefresh) {
      setState(() {
        _viewers = ViewersBottomSheet._cache[widget.postId]!;
        _isLoading = false;
        _currentPage = 1; // 캐시된 데이터가 있으면 다음은 page=1부터
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      if (forceRefresh) {
        _currentPage = 0;
        _hasMore = true;
        _viewers.clear();
      }
    });

    ViewersBottomSheet._isLoadingCache[widget.postId] = true;
    try {
      final pageToLoad = forceRefresh ? 0 : _currentPage;
      final response = await _blogService.getPostViewers(
        widget.postId,
        page: pageToLoad,
        size: 20,
      );

      final data = response;
      List<Map<String, dynamic>> readers = [];

      // 🎯 페이지네이션 응답 파싱
      final viewers = (data['viewers'] as List?) ?? [];
      readers =
          viewers.map<Map<String, dynamic>>((viewer) {
            return {
              'username': viewer['username'] ?? '',
              'profileImageUrl': viewer['profileImageUrl'],
              'viewedAt': viewer['viewedAt'],
            };
          }).toList();

      // hasNext 확인
      final hasNext =
          data['hasNext'] as bool? ??
          data['hasNextPage'] as bool? ??
          (data['totalPages'] != null &&
              (data['totalPages'] as int) > pageToLoad + 1);

      // 🎯 캐시에 저장 (첫 페이지만)
      if (pageToLoad == 0) {
        ViewersBottomSheet._cache[widget.postId] = readers;
      }

      if (mounted) {
        setState(() {
          if (forceRefresh) {
            _viewers = readers;
          } else {
            // 중복 제거
            final existingUsernames =
                _viewers.map((r) => r['username']?.toString()).toSet();
            final uniqueReaders =
                readers
                    .where(
                      (r) =>
                          !existingUsernames.contains(
                            r['username']?.toString(),
                          ),
                    )
                    .toList();
            _viewers.addAll(uniqueReaders);
          }
          _isLoading = false;
          _hasMore = hasNext;
          _currentPage = pageToLoad + 1;
        });
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 조회자 로드 실패: $e');
      if (mounted) {
        setState(() {
          _error = '조회자 목록을 불러올 수 없습니다.';
          _isLoading = false;
        });
      }
    } finally {
      ViewersBottomSheet._isLoadingCache[widget.postId] = false;
    }
  }

  // 🎯 더 많은 조회자 로드 (페이지네이션)
  Future<void> _loadMoreViewers() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await _blogService.getPostViewers(
        widget.postId,
        page: _currentPage,
        size: 20,
      );

      final data = response;
      List<Map<String, dynamic>> readers = [];

      // 🎯 페이지네이션 응답 파싱
      final viewers = (data['viewers'] as List?) ?? [];
      readers =
          viewers.map<Map<String, dynamic>>((viewer) {
            return {
              'username': viewer['username'] ?? '',
              'profileImageUrl': viewer['profileImageUrl'],
              'viewedAt': viewer['viewedAt'],
            };
          }).toList();

      // hasNext 확인
      final hasNext =
          data['hasNext'] as bool? ??
          data['hasNextPage'] as bool? ??
          (data['totalPages'] != null &&
              (data['totalPages'] as int) > _currentPage + 1);

      if (mounted) {
        // 중복 제거
        final existingUsernames =
            _viewers.map((r) => r['username']?.toString()).toSet();
        final uniqueReaders =
            readers
                .where(
                  (r) => !existingUsernames.contains(r['username']?.toString()),
                )
                .toList();

        setState(() {
          _viewers.addAll(uniqueReaders);
          _hasMore = hasNext;
          _currentPage++;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 로드 모어 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  // 🎯 상대 시간 포맷팅 (예: "1분 전", "2시간 전")
  String _formatRelativeTime(String? viewedAt) {
    if (viewedAt == null || viewedAt.isEmpty) return '';
    try {
      final viewedTime = TimeUtils.toLocalTime(viewedAt);
      final now = DateTime.now();
      final difference = now.difference(viewedTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}일 전';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}시간 전';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}분 전';
      } else {
        return '방금 전';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildUserShimmer() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12, left: 12),
      child: Row(
        children: [
          ShimmerBox(
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                  width: 120,
                  height: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                ShimmerBox(
                  width: 80,
                  height: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return
    // 🎯 스와이프로 닫기 및 배경 탭 감지
    GestureDetector(
      onHorizontalDragEnd: (details) {
        // 오른쪽으로 스와이프 (velocity.dx > 0)
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          if (widget.onClose != null) {
            widget.onClose!();
          } else {
            Navigator.of(context).maybePop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 45,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).colorScheme.background,
          elevation: 0,
          leading: GestureDetector(
            onTap: () {
              // 부모 화면으로 돌아가기 (오버레이 닫기)
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Theme.of(
                  context,
                ).colorScheme.onBackground.withOpacity(0.75),
                size: 24,
              ),
            ),
          ),
          title: Opacity(
            opacity: 1.0 - _pullProgress.clamp(0.0, 1.0), // 🎯 당기는 만큼 투명해짐
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).translate('viewers'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onBackground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isLoading
                            ? ''
                            : _error != null
                            ? _error!
                            : AppLocalizations.of(context)
                                .translate('viewed_times')
                                .replaceAll('{count}', '${widget.viewerCount}'),
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onBackground.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: CustomRefreshIndicator(
          onRefresh: () async {
            await _loadViewers(forceRefresh: true);
          },
          onPullProgress: (progress) {
            setState(() {
              _pullProgress = progress;
            });
          },
          top: 20,
          child:
              _isLoading
                  ? RawScrollbar(
                    controller: _scrollController,
                    thumbColor: Theme.of(
                      context,
                    ).colorScheme.onBackground.withOpacity(0.3),
                    thickness: 4,
                    radius: const Radius.circular(2),
                    thumbVisibility: false,
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      itemCount: 8, // 🎯 shimmer 아이템 8개
                      separatorBuilder:
                          (context, index) => Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 72,
                            color: Theme.of(
                              context,
                            ).colorScheme.onBackground.withOpacity(0.1),
                          ),
                      itemBuilder: (context, index) {
                        return _buildUserShimmer();
                      },
                    ),
                  )
                  : _error != null
                  ? RawScrollbar(
                    controller: _scrollController,
                    thumbColor: Theme.of(
                      context,
                    ).colorScheme.onBackground.withOpacity(0.3),
                    thickness: 4,
                    radius: const Radius.circular(2),
                    thumbVisibility: false,
                    child: ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).size.height * 0.3,
                      ),
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onBackground.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onBackground.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                  : _viewers.isEmpty
                  ? RawScrollbar(
                    controller: _scrollController,
                    thumbColor: Theme.of(
                      context,
                    ).colorScheme.onBackground.withOpacity(0.3),
                    thickness: 4,
                    radius: const Radius.circular(2),
                    thumbVisibility: false,
                    child: ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).size.height * 0.3,
                      ),
                      children: [],
                    ),
                  )
                  : RawScrollbar(
                    controller: _scrollController,
                    thumbColor: Theme.of(
                      context,
                    ).colorScheme.onBackground.withOpacity(0.3),
                    thickness: 4,
                    radius: const Radius.circular(2),
                    thumbVisibility: false,
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      itemCount: _viewers.length + (_isLoadingMore ? 1 : 0),
                      separatorBuilder: (context, index) {
                        // 마지막 아이템(로드 모어 인디케이터) 전에는 디바이더 없음
                        if (index >= _viewers.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 72,
                          color: Theme.of(
                            context,
                          ).colorScheme.onBackground.withOpacity(0.1),
                        );
                      },
                      itemBuilder: (context, index) {
                        // 🎯 로드 모어 Shimmer
                        if (index >= _viewers.length) {
                          return _buildUserShimmer();
                        }

                        final viewer = _viewers[index];
                        final username = viewer['username']?.toString() ?? '';
                        final profileImageUrl =
                            viewer['profileImageUrl']?.toString();
                        final viewedAt = viewer['viewedAt']?.toString();

                        return Padding(
                          padding: const EdgeInsets.only(
                            top: 12,
                            bottom: 12,
                            left: 12,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              ProfileActionBottomSheet.show(
                                context,
                                username: username,
                                profileImageUrl: profileImageUrl,
                              );
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                // 프로필 이미지
                                CommonProfileAvatar(
                                  imageUrl: profileImageUrl,
                                  username: username,
                                  size: 56,
                                  borderWidth: 1,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        username,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onBackground,
                                        ),
                                      ),
                                      if (viewedAt != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatRelativeTime(viewedAt),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onBackground
                                                .withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // 🎯 more_vert 아이콘 (프로필 액션)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.more_vert,
                                    size: 20,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onBackground.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
        ),
      ),
    );
  }
}
