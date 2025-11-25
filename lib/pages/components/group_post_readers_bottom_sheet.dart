import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/material.dart';

// 🎯 그룹 포스트 읽은 사람 리스트 바텀시트
class GroupPostReadersBottomSheet extends StatefulWidget {
  final PostData post;

  const GroupPostReadersBottomSheet({Key? key, required this.post})
    : super(key: key);

  @override
  State<GroupPostReadersBottomSheet> createState() =>
      _GroupPostReadersBottomSheetState();
}

class _GroupPostReadersBottomSheetState
    extends State<GroupPostReadersBottomSheet> {
  List<Map<String, dynamic>> _readers = [];
  bool _isLoading = false; // 🎯 초기 로딩은 false (새로고침할 때만 true)
  bool _isRefreshing = false; // 🎯 새로고침 중 여부
  String? _error;

  // 🎯 페이지네이션 관련 상태
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  int? _totalViewerCount; // 🎯 전체 조회자 수 (서버에서 받아온 값)

  // 🎯 빈 상태 표시 지연 타이머
  bool _showEmptyState = false;
  Timer? _emptyStateTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadViewers(page: 0, forceRefresh: false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _emptyStateTimer?.cancel();
    super.dispose();
  }

  // 🎯 스크롤 리스너 (페이지네이션)
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreViewers();
      }
    }
  }

  // 읽은 시간 포맷
  String _formatReadTime(BuildContext context, DateTime readAt) {
    final now = DateTime.now();
    final difference = now.difference(readAt);

    if (difference.inMinutes < 1) {
      return context.tr('just_now');
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}${context.tr('min_ago')}';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}${context.tr('hr_ago')}';
    } else {
      return '${difference.inDays}${context.tr('days_ago')}';
    }
  }

  // 🎯 조회자 정보 로드 (페이지네이션 지원)
  Future<void> _loadViewers({int page = 0, bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    try {
      if (forceRefresh) {
        setState(() {
          _isRefreshing = true;
          _error = null;
        });
      } else {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }

      final blogService = BlogService();
      final response = await blogService.getPostViewers(
        widget.post.id,
        page: page,
        size: 20,
      );

      final viewers = (response['viewers'] as List?) ?? [];
      final totalViewerCount = response['totalViewerCount'] as int?;

      final readers =
          viewers.map<Map<String, dynamic>>((viewer) {
            return {
              'username': viewer['username'] ?? '',
              'profileImageUrl': viewer['profileImageUrl'],
              'readAt':
                  viewer['viewedAt'] != null
                      ? TimeUtils.toLocalTime(viewer['viewedAt'].toString())
                      : null,
            };
          }).toList();

      if (mounted) {
        setState(() {
          if (forceRefresh || page == 0) {
            _readers = readers;
            _currentPage = 0;
          } else {
            // 중복 제거 후 추가
            final existingUsernames =
                _readers.map((r) => r['username'] as String).toSet();
            final newReaders =
                readers
                    .where((r) => !existingUsernames.contains(r['username']))
                    .toList();
            _readers = [..._readers, ...newReaders];
          }
          _totalViewerCount = totalViewerCount;
          _hasMore = readers.length >= 20;
          _isLoading = false;
          _isRefreshing = false;
        });

        // 🎯 데이터 로딩 완료 후, 리스트가 비어있으면 0.7초 후에 빈 상태 표시
        if (readers.isEmpty) {
          _emptyStateTimer?.cancel();
          _emptyStateTimer = Timer(const Duration(milliseconds: 700), () {
            if (mounted) {
              setState(() {
                _showEmptyState = true;
              });
            }
          });
        } else {
          // 데이터가 있으면 즉시 빈 상태 플래그 해제
          _emptyStateTimer?.cancel();
          if (mounted) {
            setState(() {
              _showEmptyState = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [GroupPostReadersBottomSheet] 조회자 정보 로드 에러: $e');
      if (mounted) {
        setState(() {
          _error = '조회자 정보를 불러올 수 없습니다';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  // 🎯 더 많은 조회자 로드 (페이지네이션)
  Future<void> _loadMoreViewers() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final blogService = BlogService();
      final response = await blogService.getPostViewers(
        widget.post.id,
        page: nextPage,
        size: 20,
      );

      final viewers = (response['viewers'] as List?) ?? [];
      final readers =
          viewers.map<Map<String, dynamic>>((viewer) {
            return {
              'username': viewer['username'] ?? '',
              'profileImageUrl': viewer['profileImageUrl'],
              'readAt':
                  viewer['viewedAt'] != null
                      ? TimeUtils.toLocalTime(viewer['viewedAt'].toString())
                      : null,
            };
          }).toList();

      if (mounted) {
        setState(() {
          // 중복 제거 후 추가
          final existingUsernames =
              _readers.map((r) => r['username'] as String).toSet();
          final newReaders =
              readers
                  .where((r) => !existingUsernames.contains(r['username']))
                  .toList();
          _readers = [..._readers, ...newReaders];
          _hasMore = readers.length >= 20;
          _currentPage = nextPage;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupPostReadersBottomSheet] 조회자 더보기 로드 에러: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final readers = _readers;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 🎯 헤더: 글 정보 + 글 보러가기 버튼
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // 썸네일 이미지
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.post.thumbnailImageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 60,
                            height: 60,
                            color: Theme.of(context).colorScheme.surface,
                            child: Icon(
                              Icons.image_outlined,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 글 정보
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.post.title.isNotEmpty
                                ? widget.post.title
                                : context.tr('no_title'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context
                                .tr('by_author')
                                .replaceAll('{author}', widget.post.author),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 글 보러가기 버튼
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => PostReaderScreen(
                                  exported: widget.post.toExportedData(),
                                ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.onSurface,
                        foregroundColor: Theme.of(context).colorScheme.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        context.tr('go_to_post'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🎯 읽은 사람 리스트
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      context
                          .tr('readers_count')
                          .replaceAll(
                            '{count}',
                            '${_totalViewerCount ?? readers.length}',
                          ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              // 읽은 사람 리스트 (세로) - 당겨서 새로고침 + 페이지네이션
              Expanded(
                child: CustomRefreshIndicator(
                  onRefresh: () async {
                    await _loadViewers(page: 0, forceRefresh: true);
                  },
                  child:
                      _isRefreshing && _readers.isEmpty
                          ? ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: 5,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    ShimmerBox(
                                      width: 50,
                                      height: 50,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ShimmerBox(
                                            width: 120,
                                            height: 16,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ShimmerBox(
                                            width: 80,
                                            height: 12,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                          : _error != null
                          ? Center(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          )
                          : readers.isEmpty && !_isLoading && _showEmptyState
                          ? Center(
                            child: Text(
                              '아직 읽은 사람이 없습니다',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          )
                          : readers.isEmpty && !_isLoading && !_showEmptyState
                          ? ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: 5,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    ShimmerBox(
                                      width: 50,
                                      height: 50,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ShimmerBox(
                                            width: 120,
                                            height: 16,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ShimmerBox(
                                            width: 80,
                                            height: 12,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                          : ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount:
                                readers.length + (_isLoadingMore ? 1 : 0),
                            separatorBuilder:
                                (context, index) => Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.1),
                                ),
                            itemBuilder: (context, index) {
                              if (index >= readers.length) {
                                // 로드 더보기 인디케이터
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Center(
                                    child: Row(
                                      children: [
                                        ShimmerBox(
                                          width: 50,
                                          height: 50,
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ShimmerBox(
                                                width: 120,
                                                height: 16,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              const SizedBox(height: 8),
                                              ShimmerBox(
                                                width: 80,
                                                height: 12,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final reader = readers[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 0,
                                ),
                                leading: CommonProfileAvatar(
                                  imageUrl: reader['profileImageUrl'],
                                  username: reader['username'],
                                  size: 50,
                                  borderWidth: 0,
                                ),
                                title: Text(
                                  reader['username'],
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                subtitle:
                                    reader['readAt'] != null
                                        ? Text(
                                          _formatReadTime(
                                            context,
                                            reader['readAt'] as DateTime,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.6),
                                          ),
                                        )
                                        : null,
                                onTap: () {
                                  // 🎯 프로필 화면으로 이동
                                  final username =
                                      reader['username'] as String?;
                                  if (username != null && username.isNotEmpty) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder:
                                            (context) => UserProfileScreen(
                                              otherUser: User(
                                                username: username,
                                                profileImageUrl:
                                                    reader['profileImageUrl']
                                                        as String?,
                                              ),
                                            ),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
