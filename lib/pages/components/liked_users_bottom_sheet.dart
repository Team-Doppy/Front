import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/profile_action_bottom_sheet.dart';

/// 🎯 좋아요를 누른 사용자 목록 오버레이
class LikedUsersBottomSheet extends StatefulWidget {
  final String postId;
  final int likeCount; // 🎯 포스트의 전체 좋아요 수 (페이지네이션과 무관)

  const LikedUsersBottomSheet({
    super.key,
    required this.postId,
    required this.likeCount,
  });

  @override
  State<LikedUsersBottomSheet> createState() => _LikedUsersBottomSheetState();

  // 🎯 정적 캐시: postId별로 좋아요 사용자 목록 저장 (클래스 레벨에서 관리)
  static final Map<String, List<Map<String, dynamic>>> _cache = {};
  static final Map<String, bool> _isLoadingCache = {};

  /// 🎯 좋아요 사용자 목록 미리 로드 (비동기, 정적 메서드)
  static Future<void> preloadLikedUsers(String postId) async {
    // 이미 캐시에 있거나 로딩 중이면 스킵
    if (_cache.containsKey(postId) && _cache[postId]!.isNotEmpty) {
      return;
    }
    if (_isLoadingCache[postId] == true) {
      return;
    }

    _isLoadingCache[postId] = true;
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
        _cache[postId] = users;
        print(
          '[LikedUsersBottomSheet] 좋아요 사용자 목록 미리 로드 완료: $postId (${users.length}명)',
        );
      }
    } catch (e) {
      print('[LikedUsersBottomSheet] 좋아요 사용자 목록 미리 로드 실패: $e');
    } finally {
      _isLoadingCache[postId] = false;
    }
  }
}

class _LikedUsersBottomSheetState extends State<LikedUsersBottomSheet> {
  List<Map<String, dynamic>> _likedUsers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false; // 🎯 로드 모어 중인지
  bool _hasMore = true; // 🎯 더 있는지
  int _currentPage = 0; // 🎯 현재 페이지
  String? _error;
  final Dio _dio = BaseApiService().dio;
  late final ScrollController _scrollController;
  double _pullProgress = 0.0; // 🎯 당기는 진행률 (0.0 ~ 1.0)

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // 🎯 캐시된 데이터가 있으면 즉시 표시 (shimmer 안 뜨게)
    final cached = LikedUsersBottomSheet._cache[widget.postId];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _likedUsers = cached;
        _isLoading = false;
        _currentPage = 1; // 캐시된 데이터가 있으면 다음은 page=1부터
      });
    } else {
      // 캐시된 데이터가 없거나 로딩 중이면 로드 시작
      // 이미 로딩 중이면 기다림 (로딩이 완료되면 캐시에 저장됨)
      if (LikedUsersBottomSheet._isLoadingCache[widget.postId] == true) {
        // 로딩 중이면 상태만 설정 (shimmer 표시)
        setState(() {
          _isLoading = true;
        });
        // 로딩이 완료될 때까지 대기 (폴링 방식 대신 바로 로드 시도)
        _waitForCacheOrLoad();
      } else {
        // 로딩 시작
        _loadLikedUsers(forceRefresh: false);
      }
    }
  }

  /// 🎯 캐시가 준비될 때까지 대기하거나 바로 로드
  void _waitForCacheOrLoad() async {
    // 짧은 딜레이 후 캐시 확인
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final cached = LikedUsersBottomSheet._cache[widget.postId];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _likedUsers = cached;
        _isLoading = false;
        _currentPage = 1; // 캐시된 데이터가 있으면 다음은 page=1부터
      });
    } else if (LikedUsersBottomSheet._isLoadingCache[widget.postId] != true) {
      // 로딩이 끝났는데 캐시가 없으면 다시 로드
      _loadLikedUsers(forceRefresh: false);
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
      _loadMoreLikedUsers();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLikedUsers({bool forceRefresh = false}) async {
    // 🎯 이미 로드 중이면 스킵 (중복 요청 방지)
    if (LikedUsersBottomSheet._isLoadingCache[widget.postId] == true &&
        !forceRefresh) {
      return;
    }

    // 🎯 캐시된 데이터가 있고 강제 새로고침이 아니면 스킵
    if (LikedUsersBottomSheet._cache[widget.postId] != null && !forceRefresh) {
      setState(() {
        _likedUsers = LikedUsersBottomSheet._cache[widget.postId]!;
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
        _likedUsers.clear();
      }
    });

    LikedUsersBottomSheet._isLoadingCache[widget.postId] = true;
    try {
      final pageToLoad = forceRefresh ? 0 : _currentPage;
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
          // List 응답이면 더 있는지 확인 불가 (기본값 false)
          hasNext = false;
        }

        // 🎯 캐시에 저장 (첫 페이지만)
        if (pageToLoad == 0) {
          LikedUsersBottomSheet._cache[widget.postId] = users;
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
            _isLoading = false;
            _hasMore = hasNext;
            _currentPage = pageToLoad + 1;
          });
        }
      }
    } catch (e) {
      print('[LikedUsersBottomSheet] 좋아요 사용자 로드 실패: $e');
      if (mounted) {
        setState(() {
          _error = '좋아요 사용자 목록을 불러올 수 없습니다';
          _isLoading = false;
        });
      }
    } finally {
      LikedUsersBottomSheet._isLoadingCache[widget.postId] = false;
    }
  }

  /// 🎯 로드 모어 (다음 페이지)
  Future<void> _loadMoreLikedUsers() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await _dio.get(
        '/api/posts/${widget.postId}/likes?page=$_currentPage&size=20',
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
                  (data['totalPages'] as int) > _currentPage + 1);
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
            _hasMore = hasNext;
            _currentPage++;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      print('[LikedUsersBottomSheet] 로드 모어 실패: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 🎯 스와이프로 닫기 및 배경 탭 감지
        GestureDetector(
          onHorizontalDragEnd: (details) {
            // 오른쪽으로 스와이프 (velocity.dx > 0)
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Navigator.of(context).maybePop();
            }
          },
          child: ClipRRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: const BoxDecoration(
                  color: ui.Color.fromARGB(207, 50, 50, 50),
                ),
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    automaticallyImplyLeading: false,
                    toolbarHeight: 45,
                    scrolledUnderElevation: 0,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: GestureDetector(
                      onTap: () {
                        // 부모 화면으로 돌아가기 (오버레이 닫기)
                        Navigator.of(context).maybePop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white.withOpacity(0.75),
                          size: 24,
                        ),
                      ),
                    ),
                    title: Opacity(
                      opacity:
                          1.0 - _pullProgress.clamp(0.0, 1.0), // 🎯 당기는 만큼 투명해짐
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '좋아요',
                                  style: TextStyle(
                                    color: Colors.white,
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
                                      : '${widget.likeCount}명이 좋아요를 눌렀습니다',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
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
                    onRefresh: () => _loadLikedUsers(forceRefresh: true),
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
                              thumbColor: Colors.white.withOpacity(0.3),
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
                                      color: Colors.white.withOpacity(0.1),
                                    ),
                                itemBuilder: (context, index) {
                                  return _buildUserShimmer();
                                },
                              ),
                            )
                            : _error != null
                            ? RawScrollbar(
                              controller: _scrollController,
                              thumbColor: Colors.white.withOpacity(0.3),
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
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _error!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                            : _likedUsers.isEmpty
                            ? RawScrollbar(
                              controller: _scrollController,
                              thumbColor: Colors.white.withOpacity(0.3),
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
                              thumbColor: Colors.white.withOpacity(0.3),
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
                                itemCount:
                                    _likedUsers.length +
                                    (_isLoadingMore ? 1 : 0),
                                separatorBuilder: (context, index) {
                                  // 마지막 아이템(로드 모어 인디케이터) 전에는 디바이더 없음
                                  if (index >= _likedUsers.length - 1) {
                                    return const SizedBox.shrink();
                                  }
                                  return Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    indent: 72,
                                    color: Colors.white.withOpacity(0.1),
                                  );
                                },
                                itemBuilder: (context, index) {
                                  // 🎯 로드 모어 Shimmer
                                  if (index >= _likedUsers.length) {
                                    return _buildUserShimmer();
                                  }

                                  final user = _likedUsers[index];
                                  final username =
                                      user['username']?.toString() ?? '';
                                  final profileImageUrl =
                                      user['profileImageUrl']?.toString();
                                  final alias = user['alias']?.toString();

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 12,
                                      left: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        // 프로필 이미지
                                        Stack(
                                          children: [
                                            CommonProfileAvatar(
                                              imageUrl: profileImageUrl,
                                              username: username,
                                              size: 56,
                                              borderWidth: 0,
                                            ),
                                            // 좋아요 아이콘 배지
                                            Positioned(
                                              bottom: -2,
                                              right: 0,
                                              child: Container(
                                                decoration: BoxDecoration(),
                                                child: const Icon(
                                                  Icons.favorite,
                                                  size: 20,
                                                  color: ui.Color.fromARGB(
                                                    255,
                                                    255,
                                                    89,
                                                    89,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 16),
                                        // 사용자 정보
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                alias ?? username,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              if (alias != null &&
                                                  alias != username) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '@$username',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withOpacity(0.6),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // 더보기 아이콘
                                        GestureDetector(
                                          onTap: () {
                                            ProfileActionBottomSheet.show(
                                              context,
                                              username: username,
                                              alias: alias,
                                              profileImageUrl: profileImageUrl,
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Icon(
                                              Icons.more_vert,
                                              color: Colors.white.withOpacity(
                                                0.6,
                                              ),
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 🎯 사용자 목록 Shimmer 아이템 (다크 배경용) - 간결한 버전
  Widget _buildUserShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          // 프로필 이미지 Shimmer
          ShimmerBox(
            width: 56,
            height: 56,
            shape: const CircleBorder(),
            isDarkMode: true,
          ),
          const SizedBox(width: 16),
          // 이름 Shimmer
          ShimmerBox(
            width: 140,
            height: 16,
            borderRadius: BorderRadius.circular(4),
            isDarkMode: true,
          ),
        ],
      ),
    );
  }
}
