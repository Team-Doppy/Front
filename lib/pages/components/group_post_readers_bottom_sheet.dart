import 'dart:ui' as ui;
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadViewers();
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

  Future<void> _loadViewers() async {
    try {
      final blogService = BlogService();
      final response = await blogService.getPostViewers(widget.post.id);

      final viewers = (response['viewers'] as List?) ?? [];
      final readers =
          viewers.map<Map<String, dynamic>>((viewer) {
            return {
              'username': viewer['username'] ?? '',
              'profileImageUrl': viewer['profileImageUrl'],
              'readAt':
                  viewer['viewedAt'] != null
                      ? DateTime.parse(viewer['viewedAt'])
                      : null,
            };
          }).toList();

      if (mounted) {
        setState(() {
          _readers = readers;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ [GroupPostReadersBottomSheet] 조회자 정보 로드 에러: $e');
      if (mounted) {
        setState(() {
          _error = '조회자 정보를 불러올 수 없습니다';
          _isLoading = false;
        });
      }
    }
  }

  // 🎯 읽은 사람 리스트 Shimmer 빌드
  Widget _buildReadersShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 5, // 5개의 shimmer 아이템 표시
      separatorBuilder:
          (context, index) => Divider(
            height: 1,
            thickness: 0.5,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
      itemBuilder: (context, index) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ShimmerBox(
            width: 50,
            height: 50,
            shape: const CircleBorder(),
          ),
          title: ShimmerBox(
            width: 120,
            height: 16,
            borderRadius: BorderRadius.circular(4),
          ),
          trailing: ShimmerBox(
            width: 60,
            height: 13,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final readers = _readers;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
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
                          foregroundColor:
                              Theme.of(context).colorScheme.surface,
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

                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.1),
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
                            .replaceAll('{count}', '${readers.length}'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                // 읽은 사람 리스트 (세로)
                Expanded(
                  child:
                      _isLoading
                          ? _buildReadersShimmer()
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
                          : readers.isEmpty
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
                          : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: readers.length,
                            separatorBuilder:
                                (context, index) => Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.1),
                                ),
                            itemBuilder: (context, index) {
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
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
