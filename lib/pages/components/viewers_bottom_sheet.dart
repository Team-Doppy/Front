import 'dart:ui' as ui;
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/profile_action_bottom_sheet.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/user_provider.dart';

/// 🎯 포스트를 본 사용자 목록 및 좋아요 사용자 목록 오버레이
class ViewersBottomSheet extends StatefulWidget {
  final String postId;
  final int viewerCount; // 🎯 포스트의 전체 조회수 (페이지네이션과 무관)
  final int? likeCount; // 🎯 포스트의 전체 좋아요 수 (페이지네이션과 무관, nullable)
  final VoidCallback? onClose; // 🎯 오버레이 닫기 콜백 (오버레이로 사용할 때)

  const ViewersBottomSheet({
    super.key,
    required this.postId,
    required this.viewerCount,
    this.likeCount,
    this.onClose,
  });

  @override
  State<ViewersBottomSheet> createState() => _ViewersBottomSheetState();

  // 🎯 정적 캐시: postId별로 조회자 목록 저장 (클래스 레벨에서 관리)
  static final Map<String, List<Map<String, dynamic>>> _viewersCache = {};
  static final Map<String, bool> _viewersLoadingCache = {};

  // 🎯 정적 캐시: postId별로 좋아요 사용자 목록 저장 (클래스 레벨에서 관리)
  static final Map<String, List<Map<String, dynamic>>> _likesCache = {};
  static final Map<String, bool> _likesLoadingCache = {};

  /// 🎯 조회자 및 좋아요 목록 미리 로드 (병렬 처리, 비동기, 정적 메서드)
  static Future<void> preloadViewers(String postId) async {
    // 이미 캐시에 있거나 로딩 중이면 스킵
    if (_viewersCache.containsKey(postId) &&
        _viewersCache[postId]!.isNotEmpty) {
      return;
    }
    if (_viewersLoadingCache[postId] == true) {
      return;
    }

    _viewersLoadingCache[postId] = true;
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
        _viewersCache[postId] = readers;
        debugPrint(
          '[ViewersBottomSheet] 조회자 목록 미리 로드 완료: $postId (${readers.length}명)',
        );
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 조회자 목록 미리 로드 실패: $e');
    } finally {
      _viewersLoadingCache[postId] = false;
    }
  }

  /// 🎯 좋아요 사용자 목록 미리 로드 (병렬 처리용)
  static Future<void> preloadLikes(String postId) async {
    // 이미 캐시에 있거나 로딩 중이면 스킵
    if (_likesCache.containsKey(postId) && _likesCache[postId]!.isNotEmpty) {
      return;
    }
    if (_likesLoadingCache[postId] == true) {
      return;
    }

    _likesLoadingCache[postId] = true;
    final Dio dio = BaseApiService().dio;

    try {
      final response = await dio.get(
        '/api/posts/$postId/likes?page=0&size=20',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        List<Map<String, dynamic>> users = [];

        // 🎯 페이지네이션 응답 파싱
        if (data is Map) {
          if (data.containsKey('content')) {
            users =
                (data['content'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
          } else if (data.containsKey('users')) {
            users =
                (data['users'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
          }
        } else if (data is List) {
          users = data.map((e) => Map<String, dynamic>.from(e)).toList();
        }

        // 🎯 캐시에 저장 (0페이지만)
        _likesCache[postId] = users;
        debugPrint(
          '[ViewersBottomSheet] 좋아요 목록 미리 로드 완료: $postId (${users.length}명)',
        );
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 좋아요 목록 미리 로드 실패: $e');
    } finally {
      _likesLoadingCache[postId] = false;
    }
  }

  /// 🎯 조회자와 좋아요 목록을 병렬로 미리 로드
  static Future<void> preloadAll(String postId) async {
    await Future.wait([preloadViewers(postId), preloadLikes(postId)]);
  }
}

class _ViewersBottomSheetState extends State<ViewersBottomSheet> {
  // 🎯 조회자 관련 상태
  List<Map<String, dynamic>> _viewers = [];
  bool _isLoadingViewers = true;
  bool _isLoadingMoreViewers = false;
  bool _hasMoreViewers = true;
  int _currentViewersPage = 0;
  String? _viewersError;

  // 🎯 좋아요 관련 상태
  List<Map<String, dynamic>> _likedUsers = [];
  bool _isLoadingLikes = true;
  bool _isLoadingMoreLikes = false;
  bool _hasMoreLikes = true;
  int _currentLikesPage = 0;
  String? _likesError;

  final BlogService _blogService = BlogService();
  final Dio _dio = BaseApiService().dio;
  late final ScrollController _scrollController;
  double _pullProgress = 0.0; // 🎯 당기는 진행률 (0.0 ~ 1.0)

  // 🎯 좋아요한 사용자 username Set (빠른 확인용)
  Set<String> get _likedUsernames =>
      _likedUsers
          .map((u) => u['username']?.toString() ?? '')
          .where((username) => username.isNotEmpty)
          .toSet();

  // 🎯 통합 리스트: 조회자와 좋아요 사용자를 하나로 합침
  // 정렬 기준: 1) 좋아요 여부 (좋아요 누른 사람 우선), 2) 조회 시간 (최근 조회 순)
  List<Map<String, dynamic>> get _mergedList {
    final Map<String, Map<String, dynamic>> mergedMap = {};

    // 조회자 추가
    for (final viewer in _viewers) {
      final username = viewer['username']?.toString() ?? '';
      if (username.isNotEmpty) {
        mergedMap[username] = {
          ...viewer,
          'isLiked': _likedUsernames.contains(username),
        };
      }
    }

    // 좋아요 사용자 추가 (조회자에 없는 경우)
    for (final likedUser in _likedUsers) {
      final username = likedUser['username']?.toString() ?? '';
      if (username.isNotEmpty && !mergedMap.containsKey(username)) {
        mergedMap[username] = {...likedUser, 'isLiked': true};
      }
    }

    // 🎯 정렬: 좋아요 누른 사람을 위로, 그 다음 조회 시간 최근 순
    final sortedList = mergedMap.values.toList();
    sortedList.sort((a, b) {
      final aIsLiked = a['isLiked'] == true;
      final bIsLiked = b['isLiked'] == true;

      // 1순위: 좋아요 여부 (좋아요 누른 사람이 위로)
      if (aIsLiked && !bIsLiked) return -1;
      if (!aIsLiked && bIsLiked) return 1;

      // 2순위: 조회 시간 (최근 조회 순) - viewedAt이 있는 경우만 비교
      final aViewedAt = a['viewedAt']?.toString();
      final bViewedAt = b['viewedAt']?.toString();

      if (aViewedAt != null &&
          aViewedAt.isNotEmpty &&
          bViewedAt != null &&
          bViewedAt.isNotEmpty) {
        try {
          final aTime = TimeUtils.toLocalTime(aViewedAt);
          final bTime = TimeUtils.toLocalTime(bViewedAt);
          // 최근 시간이 앞에 오도록 (내림차순)
          return bTime.compareTo(aTime);
        } catch (e) {
          // 파싱 실패 시 무시
        }
      }

      // viewedAt이 하나만 있는 경우, 있는 것이 앞으로
      if (aViewedAt != null &&
          aViewedAt.isNotEmpty &&
          (bViewedAt == null || bViewedAt.isEmpty)) {
        return -1;
      }
      if ((aViewedAt == null || aViewedAt.isEmpty) &&
          bViewedAt != null &&
          bViewedAt.isNotEmpty) {
        return 1;
      }

      // 동일하면 유지
      return 0;
    });

    return sortedList;
  }

  // 🎯 로딩 상태
  bool get _isLoading => _isLoadingViewers || _isLoadingLikes;
  bool get _isLoadingMore => _isLoadingMoreViewers || _isLoadingMoreLikes;
  bool get _hasMore => _hasMoreViewers || _hasMoreLikes;
  String? get _error => _viewersError ?? _likesError;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // 🎯 조회자 캐시 확인 및 초기 로드
    final viewersCached = ViewersBottomSheet._viewersCache[widget.postId];
    if (viewersCached != null && viewersCached.isNotEmpty) {
      setState(() {
        _viewers = viewersCached;
        _isLoadingViewers = false;
        _currentViewersPage = 1;
      });
    } else {
      if (ViewersBottomSheet._viewersLoadingCache[widget.postId] == true) {
        _waitForViewersCacheOrLoad();
      } else {
        _loadViewers(forceRefresh: false);
      }
    }

    // 🎯 좋아요 캐시 확인 및 초기 로드 (likeCount가 있을 때만)
    if (widget.likeCount != null) {
      final likesCached = ViewersBottomSheet._likesCache[widget.postId];
      if (likesCached != null && likesCached.isNotEmpty) {
        setState(() {
          _likedUsers = likesCached;
          _isLoadingLikes = false;
          _currentLikesPage = 1;
        });
      } else {
        if (ViewersBottomSheet._likesLoadingCache[widget.postId] == true) {
          _waitForLikesCacheOrLoad();
        } else {
          _loadLikedUsers(forceRefresh: false);
        }
      }
    } else {
      // likeCount가 없으면 좋아요 로딩 완료로 표시
      setState(() {
        _isLoadingLikes = false;
      });
    }
  }

  /// 🎯 조회자 캐시가 준비될 때까지 대기하거나 바로 로드
  void _waitForViewersCacheOrLoad() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final cached = ViewersBottomSheet._viewersCache[widget.postId];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _viewers = cached;
        _isLoadingViewers = false;
        _currentViewersPage = 1;
      });
    } else if (ViewersBottomSheet._viewersLoadingCache[widget.postId] != true) {
      _loadViewers(forceRefresh: false);
    } else {
      _waitForViewersCacheOrLoad();
    }
  }

  /// 🎯 좋아요 캐시가 준비될 때까지 대기하거나 바로 로드
  void _waitForLikesCacheOrLoad() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final cached = ViewersBottomSheet._likesCache[widget.postId];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _likedUsers = cached;
        _isLoadingLikes = false;
        _currentLikesPage = 1;
      });
    } else if (ViewersBottomSheet._likesLoadingCache[widget.postId] != true) {
      _loadLikedUsers(forceRefresh: false);
    } else {
      _waitForLikesCacheOrLoad();
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
      // 조회자와 좋아요 사용자 모두 로드 모어 시도
      if (_hasMoreViewers && !_isLoadingMoreViewers) {
        _loadMoreViewers();
      }
      if (_hasMoreLikes && !_isLoadingMoreLikes && widget.likeCount != null) {
        _loadMoreLikedUsers();
      }
    }
  }

  // 🎯 조회자 정보 로드 (페이지네이션 지원)
  Future<void> _loadViewers({bool forceRefresh = false}) async {
    // 🎯 이미 로드 중이면 스킵 (중복 요청 방지)
    if (ViewersBottomSheet._viewersLoadingCache[widget.postId] == true &&
        !forceRefresh) {
      return;
    }

    // 🎯 캐시된 데이터가 있고 강제 새로고침이 아니면 스킵
    if (ViewersBottomSheet._viewersCache[widget.postId] != null &&
        !forceRefresh) {
      setState(() {
        _viewers = ViewersBottomSheet._viewersCache[widget.postId]!;
        _isLoadingViewers = false;
        _currentViewersPage = 1;
      });
      return;
    }

    setState(() {
      _isLoadingViewers = true;
      _viewersError = null;
      if (forceRefresh) {
        _currentViewersPage = 0;
        _hasMoreViewers = true;
        _viewers.clear();
      }
    });

    ViewersBottomSheet._viewersLoadingCache[widget.postId] = true;
    try {
      final pageToLoad = forceRefresh ? 0 : _currentViewersPage;
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
        ViewersBottomSheet._viewersCache[widget.postId] = readers;
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
          _isLoadingViewers = false;
          _hasMoreViewers = hasNext;
          _currentViewersPage = pageToLoad + 1;
        });
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 조회자 로드 실패: $e');
      if (mounted) {
        setState(() {
          _viewersError = '조회자 목록을 불러올 수 없습니다.';
          _isLoadingViewers = false;
        });
      }
    } finally {
      ViewersBottomSheet._viewersLoadingCache[widget.postId] = false;
    }
  }

  // 🎯 더 많은 조회자 로드 (페이지네이션)
  Future<void> _loadMoreViewers() async {
    if (_isLoadingMoreViewers || !_hasMoreViewers || _isLoadingViewers) return;

    setState(() {
      _isLoadingMoreViewers = true;
    });

    try {
      final response = await _blogService.getPostViewers(
        widget.postId,
        page: _currentViewersPage,
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
              (data['totalPages'] as int) > _currentViewersPage + 1);

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
          _hasMoreViewers = hasNext;
          _currentViewersPage++;
          _isLoadingMoreViewers = false;
        });
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 조회자 로드 모어 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingMoreViewers = false;
        });
      }
    }
  }

  // 🎯 좋아요 사용자 정보 로드 (페이지네이션 지원)
  Future<void> _loadLikedUsers({bool forceRefresh = false}) async {
    if (widget.likeCount == null) return;

    // 🎯 이미 로드 중이면 스킵 (중복 요청 방지)
    if (ViewersBottomSheet._likesLoadingCache[widget.postId] == true &&
        !forceRefresh) {
      return;
    }

    // 🎯 캐시된 데이터가 있고 강제 새로고침이 아니면 스킵
    if (ViewersBottomSheet._likesCache[widget.postId] != null &&
        !forceRefresh) {
      setState(() {
        _likedUsers = ViewersBottomSheet._likesCache[widget.postId]!;
        _isLoadingLikes = false;
        _currentLikesPage = 1;
      });
      return;
    }

    setState(() {
      _isLoadingLikes = true;
      _likesError = null;
      if (forceRefresh) {
        _currentLikesPage = 0;
        _hasMoreLikes = true;
        _likedUsers.clear();
      }
    });

    ViewersBottomSheet._likesLoadingCache[widget.postId] = true;
    try {
      final pageToLoad = forceRefresh ? 0 : _currentLikesPage;
      final response = await _dio.get(
        '/api/posts/${widget.postId}/likes?page=$pageToLoad&size=20',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        List<Map<String, dynamic>> users = [];
        bool hasNext = false;

        // 🎯 페이지네이션 응답 파싱
        if (data is Map) {
          if (data.containsKey('content')) {
            users =
                (data['content'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
          } else if (data.containsKey('users')) {
            users =
                (data['users'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
          }
          // hasNext 확인
          hasNext =
              data['hasNext'] as bool? ??
              data['hasNextPage'] as bool? ??
              (data['totalPages'] != null &&
                  (data['totalPages'] as int) > pageToLoad + 1);
        } else if (data is List) {
          users = data.map((e) => Map<String, dynamic>.from(e)).toList();
          hasNext = false;
        }

        // 🎯 캐시에 저장 (첫 페이지만)
        if (pageToLoad == 0) {
          ViewersBottomSheet._likesCache[widget.postId] = users;
        }

        if (mounted) {
          setState(() {
            if (forceRefresh) {
              _likedUsers = users;
            } else {
              // 중복 제거
              final existingIds =
                  _likedUsers.map((u) => u['username']?.toString()).toSet();
              final uniqueUsers =
                  users
                      .where(
                        (u) => !existingIds.contains(u['username']?.toString()),
                      )
                      .toList();
              _likedUsers.addAll(uniqueUsers);
            }
            _isLoadingLikes = false;
            _hasMoreLikes = hasNext;
            _currentLikesPage = pageToLoad + 1;
          });
        }
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 좋아요 사용자 로드 실패: $e');
      if (mounted) {
        setState(() {
          _likesError = '좋아요 사용자 목록을 불러올 수 없습니다.';
          _isLoadingLikes = false;
        });
      }
    } finally {
      ViewersBottomSheet._likesLoadingCache[widget.postId] = false;
    }
  }

  /// 🎯 로드 모어 (좋아요 사용자)
  Future<void> _loadMoreLikedUsers() async {
    if (_isLoadingMoreLikes || !_hasMoreLikes || _isLoadingLikes) return;
    if (widget.likeCount == null) return;

    setState(() {
      _isLoadingMoreLikes = true;
    });

    try {
      final response = await _dio.get(
        '/api/posts/${widget.postId}/likes?page=$_currentLikesPage&size=20',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        List<Map<String, dynamic>> users = [];
        bool hasNext = false;

        // 🎯 페이지네이션 응답 파싱
        if (data is Map) {
          if (data.containsKey('content')) {
            users =
                (data['content'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
          } else if (data.containsKey('users')) {
            users =
                (data['users'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];
          }
          hasNext =
              data['hasNext'] as bool? ??
              data['hasNextPage'] as bool? ??
              (data['totalPages'] != null &&
                  (data['totalPages'] as int) > _currentLikesPage + 1);
        } else if (data is List) {
          users = data.map((e) => Map<String, dynamic>.from(e)).toList();
          hasNext = false;
        }

        if (mounted) {
          // 중복 제거
          final existingIds =
              _likedUsers.map((u) => u['username']?.toString()).toSet();
          final uniqueUsers =
              users
                  .where(
                    (u) => !existingIds.contains(u['username']?.toString()),
                  )
                  .toList();

          setState(() {
            _likedUsers.addAll(uniqueUsers);
            _hasMoreLikes = hasNext;
            _currentLikesPage++;
            _isLoadingMoreLikes = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[ViewersBottomSheet] 좋아요 로드 모어 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingMoreLikes = false;
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

  /// 🎯 사용자 아이템 빌드 (조회자와 좋아요 사용자 통합)
  Widget _buildUserItem(Map<String, dynamic> user) {
    final username = user['username']?.toString() ?? '';
    final profileImageUrl = user['profileImageUrl']?.toString();
    final alias = user['alias']?.toString();
    final viewedAt = user['viewedAt']?.toString();
    final isLiked = user['isLiked'] == true;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12, left: 12),
      child: Builder(
        builder: (context) {
          final currentUser = context.read<UserProvider>().currentUser;
          final isMe = currentUser != null && currentUser.username == username;

          return GestureDetector(
            onTap: () {
              ProfileActionBottomSheet.show(
                context,
                username: username,
                alias: alias,
                profileImageUrl: profileImageUrl,
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // 프로필 이미지 (좋아요 아이콘 포함)
                Stack(
                  children: [
                    CommonProfileAvatar(
                      imageUrl: profileImageUrl,
                      username: username,
                      size: 56,
                      borderWidth: 1,
                    ),
                    if (isLiked)
                      Positioned(
                        bottom: -2,
                        right: 0,
                        child: Container(
                          decoration: const BoxDecoration(),
                          child: const Icon(
                            Icons.favorite,
                            size: 20,
                            color: ui.Color.fromARGB(255, 255, 89, 89),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alias ?? username,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onBackground,
                        ),
                      ),
                      if (alias != null && alias != username) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onBackground.withOpacity(0.6),
                          ),
                        ),
                      ] else if (viewedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatRelativeTime(viewedAt),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onBackground.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 🎯 more_vert 아이콘 (본인이 아닐 때만)
                if (!isMe)
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
          );
        },
      ),
    );
  }

  /// 🎯 통합 리스트 빌드
  Widget _buildListContent() {
    if (_isLoading) {
      return RawScrollbar(
        controller: _scrollController,
        thumbColor: Theme.of(context).colorScheme.onBackground.withOpacity(0.3),
        thickness: 4,
        radius: const Radius.circular(2),
        thumbVisibility: false,
        child: ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          itemCount: 8,
          separatorBuilder:
              (context, index) => Divider(
                height: 1,
                thickness: 0.5,
                indent: 72,
                color: Theme.of(
                  context,
                ).colorScheme.onBackground.withOpacity(0.1),
              ),
          itemBuilder: (context, index) => _buildUserShimmer(),
        ),
      );
    }

    if (_error != null) {
      return RawScrollbar(
        controller: _scrollController,
        thumbColor: Theme.of(context).colorScheme.onBackground.withOpacity(0.3),
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
      );
    }

    final mergedList = _mergedList;
    if (mergedList.isEmpty) {
      return RawScrollbar(
        controller: _scrollController,
        thumbColor: Theme.of(context).colorScheme.onBackground.withOpacity(0.3),
        thickness: 4,
        radius: const Radius.circular(2),
        thumbVisibility: false,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.3,
          ),
          children: const [],
        ),
      );
    }

    return RawScrollbar(
      controller: _scrollController,
      thumbColor: Theme.of(context).colorScheme.onBackground.withOpacity(0.3),
      thickness: 4,
      radius: const Radius.circular(2),
      thumbVisibility: false,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: mergedList.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) {
          if (index >= mergedList.length - 1) {
            return const SizedBox.shrink();
          }
          return Divider(
            height: 1,
            thickness: 0.5,
            indent: 72,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
          );
        },
        itemBuilder: (context, index) {
          if (index >= mergedList.length) {
            return _buildUserShimmer();
          }

          return _buildUserItem(mergedList[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleText = AppLocalizations.of(context).translate('viewers');

    return GestureDetector(
      onHorizontalDragEnd: (details) {
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
            opacity: 1.0 - _pullProgress.clamp(0.0, 1.0),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onBackground,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
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
            await Future.wait([
              _loadViewers(forceRefresh: true),
              if (widget.likeCount != null) _loadLikedUsers(forceRefresh: true),
            ]);
          },
          onPullProgress: (progress) {
            setState(() {
              _pullProgress = progress;
            });
          },
          top: 20,
          child: _buildListContent(),
        ),
      ),
    );
  }
}
